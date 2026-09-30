// Creates or updates every workflow JSON in WORKFLOWS_DIR on an n8n instance
// through its public REST API, then writes a report to the job summary.
//
// Required env: N8N_API_URL (e.g. https://n8n.example.com), N8N_API_KEY
// Optional env: WORKFLOWS_DIR (default: workflows)
//
// Matching: n8n assigns a new id when the API creates a workflow, so ids differ
// between dev and prod. A file is matched by its "id" first and by its exact
// "name" second; the name is the key that stays stable across instances.
//
// Errors: one bad file does not stop the others. Every file is attempted, the
// report lists each result, and the script exits 1 if any file failed.
import { appendFileSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const baseUrl = (process.env.N8N_API_URL ?? "").replace(/\/+$/, "").replace(/\/api\/v1$/, "");
const apiKey = process.env.N8N_API_KEY ?? "";
const dir = process.env.WORKFLOWS_DIR ?? "workflows";
const summaryPath = process.env.GITHUB_STEP_SUMMARY;

// The API rejects properties it does not know, so only these are sent.
// staticData is left out on purpose: it is runtime state of the target instance.
const SETTINGS_KEYS = [
  "saveExecutionProgress",
  "saveManualExecutions",
  "saveDataErrorExecution",
  "saveDataSuccessExecution",
  "executionTimeout",
  "errorWorkflow",
  "timezone",
  "executionOrder",
  "callerPolicy",
  "callerIds",
];

if (!baseUrl || !apiKey) {
  console.error("::error::N8N_API_URL and N8N_API_KEY must be set in this GitHub Environment.");
  process.exit(1);
}

async function api(method, path, body) {
  const res = await fetch(`${baseUrl}/api/v1${path}`, {
    method,
    headers: { "X-N8N-API-KEY": apiKey, "Content-Type": "application/json", Accept: "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${method} ${path} -> HTTP ${res.status}: ${text.slice(0, 300)}`);
  return text ? JSON.parse(text) : {};
}

async function listRemote() {
  const all = [];
  let cursor;
  do {
    const query = new URLSearchParams({ limit: "250" });
    if (cursor) query.set("cursor", cursor);
    const page = await api("GET", `/workflows?${query}`);
    all.push(...page.data);
    cursor = page.nextCursor;
  } while (cursor);
  return all;
}

function toPayload(wf) {
  const settings = {};
  for (const key of SETTINGS_KEYS) if (wf.settings?.[key] !== undefined) settings[key] = wf.settings[key];
  return { name: wf.name, nodes: wf.nodes, connections: wf.connections ?? {}, settings };
}

async function upsert(file, remote) {
  const wf = JSON.parse(readFileSync(join(dir, file), "utf8"));
  if (!wf.name || !Array.isArray(wf.nodes)) throw new Error('not an n8n workflow export (missing "name" or "nodes")');

  const byName = remote.filter((r) => r.name === wf.name);
  let target = remote.find((r) => wf.id && r.id === wf.id);
  if (!target && byName.length > 1) {
    throw new Error(`${byName.length} workflows named "${wf.name}" on the instance; rename one or set the right "id"`);
  }
  target ??= byName[0];

  let result;
  if (target) {
    result = await api("PUT", `/workflows/${target.id}`, toPayload(wf));
  } else {
    result = await api("POST", "/workflows", toPayload(wf));
    remote.push(result);
  }

  // Only ever activates; a workflow is never switched off by a deploy.
  let note = "";
  if (wf.active === true && !result.active) {
    try {
      await api("POST", `/workflows/${result.id}/activate`);
      note = "activated";
    } catch (err) {
      note = `saved, but activation failed: ${err.message}`;
    }
  }
  return { action: target ? "updated" : "created", id: result.id, name: wf.name, note };
}

let files;
try {
  files = readdirSync(dir).filter((f) => f.toLowerCase().endsWith(".json")).sort();
} catch {
  files = [];
}

const results = [];
if (files.length) {
  const remote = await listRemote();
  for (const file of files) {
    try {
      const r = await upsert(file, remote);
      results.push({ file, ok: true, ...r });
      console.log(`OK   ${file}: ${r.action} "${r.name}" (id ${r.id})${r.note ? ` - ${r.note}` : ""}`);
    } catch (err) {
      results.push({ file, ok: false, error: err.message });
      console.error(`::error file=${dir}/${file}::${err.message}`);
    }
  }
}

const cell = (s) => String(s ?? "").replaceAll("|", "\\|").replaceAll("\n", " ");
const lines = ["## n8n workflows", ""];
if (!files.length) {
  lines.push(`No JSON files in \`${dir}/\`. Nothing to deploy.`);
} else {
  lines.push("| File | Result | Workflow | Id | Notes |", "|---|---|---|---|---|");
  for (const r of results) {
    lines.push(
      r.ok
        ? `| \`${r.file}\` | ${r.action} | ${cell(r.name)} | \`${r.id}\` | ${cell(r.note)} |`
        : `| \`${r.file}\` | **failed** | | | ${cell(r.error)} |`,
    );
  }
  const failed = results.filter((r) => !r.ok).length;
  lines.push("", `${results.length - failed} of ${results.length} workflows deployed.`);
}
const report = lines.join("\n") + "\n";
if (summaryPath) appendFileSync(summaryPath, report);
else console.log(report);

if (results.some((r) => !r.ok)) process.exitCode = 1;
