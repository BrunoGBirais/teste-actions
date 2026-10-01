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
// Placeholders: per-environment values are written in the JSON as __NAME__
// (e.g. __SUPABASE_URL__) and filled from the env var N8N_VAR_NAME before the
// workflow is sent. A file using a placeholder with no value fails.
//
// Credentials: exported node credentials carry the source instance's ids. Each
// one is re-pointed to the credential with the same name and type on the target
// instance, so credentials only need to exist there with matching names. This
// needs the credential:list API scope. A credential missing on the target does
// not fail the file: its reference is removed from the node, the workflow is
// still imported but left unpublished, and the report lists what to create.
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

async function listAll(resource) {
  const all = [];
  let cursor;
  do {
    const query = new URLSearchParams({ limit: "250" });
    if (cursor) query.set("cursor", cursor);
    const page = await api("GET", `/${resource}?${query}`);
    all.push(...page.data);
    cursor = page.nextCursor;
  } while (cursor);
  return all;
}

// Fills __NAME__ placeholders from N8N_VAR_NAME. Values are JSON-escaped since
// they land inside JSON strings.
function fillPlaceholders(text) {
  const missing = new Set();
  const out = text.replace(/__([A-Z][A-Z0-9_]*)__/g, (match, name) => {
    const value = process.env[`N8N_VAR_${name}`];
    if (value === undefined || value === "") {
      missing.add(name);
      return match;
    }
    return JSON.stringify(value).slice(1, -1);
  });
  if (missing.size) {
    const names = [...missing].map((n) => `N8N_VAR_${n}`).join(", ");
    throw new Error(`no value for placeholder(s): set ${names} for this environment`);
  }
  return out;
}

// Re-points each node credential to the target instance's credential with the
// same type and name. `credentials` is null when the instance can't list them.
// Unmatched references are removed from their node and returned, so the
// workflow can still be imported; the credential is then set in the n8n editor.
function remapCredentials(wf, credentials) {
  const missing = [];
  for (const node of wf.nodes) {
    for (const [type, ref] of Object.entries(node.credentials ?? {})) {
      if (!credentials) throw new Error(`can't map credentials: ${credentialsError}`);
      const match = credentials.filter((c) => c.type === type && c.name === ref.name);
      if (match.length === 1) {
        node.credentials[type] = { id: match[0].id, name: match[0].name };
      } else {
        delete node.credentials[type];
        missing.push(`"${ref.name}" (${type})${match.length > 1 ? ": more than one with this name" : ""}`);
      }
    }
    if (node.credentials && !Object.keys(node.credentials).length) delete node.credentials;
  }
  return [...new Set(missing)];
}

function toPayload(wf) {
  const settings = {};
  for (const key of SETTINGS_KEYS) if (wf.settings?.[key] !== undefined) settings[key] = wf.settings[key];
  return { name: wf.name, nodes: wf.nodes, connections: wf.connections ?? {}, settings };
}

async function upsert(file, remote, credentials) {
  const wf = JSON.parse(fillPlaceholders(readFileSync(join(dir, file), "utf8")));
  if (!wf.name || !Array.isArray(wf.nodes)) throw new Error('not an n8n workflow export (missing "name" or "nodes")');
  const missingCreds = remapCredentials(wf, credentials);

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

  // Publishes on every deploy, even if already active: on n8n versions with
  // draft/published versions, a PUT only saves a draft until activate is called.
  // Only ever activates; a workflow is never switched off by a deploy. A
  // workflow with missing credentials is not published, since n8n would reject it.
  let note = "";
  if (missingCreds.length) {
    note = `not published, create credentials: ${missingCreds.join(", ")}`;
  } else if (wf.active === true) {
    try {
      await api("POST", `/workflows/${result.id}/activate`);
      note = "published";
    } catch (err) {
      throw new Error(`saved, but publishing failed: ${err.message}`);
    }
  }
  return { action: target ? "updated" : "created", id: result.id, name: wf.name, note, warn: missingCreds.length > 0 };
}

let files;
try {
  files = readdirSync(dir).filter((f) => f.toLowerCase().endsWith(".json")).sort();
} catch {
  files = [];
}

const results = [];
let credentialsError = "";
if (files.length) {
  const remote = await listAll("workflows");
  // Only files whose nodes use credentials need this; a failure is reported per file.
  let credentials = null;
  try {
    credentials = await listAll("credentials");
  } catch (err) {
    credentialsError = `listing credentials failed (API key needs the credential:list scope): ${err.message}`;
  }
  for (const file of files) {
    try {
      const r = await upsert(file, remote, credentials);
      results.push({ file, ok: true, ...r });
      console.log(`OK   ${file}: ${r.action} "${r.name}" (id ${r.id})${r.note ? ` - ${r.note}` : ""}`);
      if (r.warn) console.log(`::warning file=${dir}/${file}::${r.note}`);
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
