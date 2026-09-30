// CSV parsing helpers ported from the legacy upload-snapshot pipeline.
// Values are semicolon-separated, BR-locale decimals, header-driven and
// accent-insensitive (spreadsheet headers vary in accentuation).
//
// O texto entra aqui já limpo por lib/encoding (ASCII puro, sem acento e sem
// U+FFFD), então o parser não precisa mais adivinhar cabeçalho degradado —
// basta o normKey continuar tirando acento dos nomes escritos no código.

export function normKey(s: string | null | undefined): string {
  return String(s || "")
    .replace(/^\uFEFF/, "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .trim();
}

function splitLine(line: string, delim: string): string[] {
  const result: string[] = [];
  let cur = "";
  let inQ = false;
  for (const ch of line) {
    if (ch === '"') {
      inQ = !inQ;
    } else if (ch === delim && !inQ) {
      result.push(cur);
      cur = "";
    } else {
      cur += ch;
    }
  }
  result.push(cur);
  return result;
}

// O sistema de origem exporta com ";", mas Excel/Sheets reexportam com "," ou TAB.
function detectDelimiter(headerLine: string): string {
  const candidates = [";", ",", "\t"];
  let best = ";";
  let bestCount = 0;
  for (const d of candidates) {
    const count = splitLine(headerLine, d).length;
    if (count > bestCount) {
      bestCount = count;
      best = d;
    }
  }
  return best;
}

export type CsvRow = Record<string, string>;

export function parseCsv(text: string): { headers: string[]; rows: CsvRow[] } {
  const lines = text.replace(/^\uFEFF/, "").replace(/\r\n?/g, "\n").split("\n");
  const delim = detectDelimiter(lines[0] || "");
  const headers = splitLine(lines[0] || "", delim).map((h) => h.trim());
  const rows: CsvRow[] = [];
  for (let i = 1; i < lines.length; i++) {
    if (!lines[i].trim()) continue;
    const cols = splitLine(lines[i], delim);
    const obj: CsvRow = {};
    headers.forEach((h, idx) => {
      const val = (cols[idx] || "").trim();
      obj[h] = val;
      obj["__" + normKey(h)] = val; // acesso acento-insensível
    });
    rows.push(obj);
  }
  return { headers, rows };
}

export function col(row: CsvRow, ...names: string[]): string {
  for (const n of names) {
    const k = "__" + normKey(n);
    if (row[k] !== undefined && row[k] !== "") return row[k];
  }
  return "";
}

export function brDec(s: string | null | undefined): number | null {
  const v = parseFloat((s || "").trim().replace(/\s/g, "").replace(",", "."));
  return isNaN(v) ? null : v;
}

export function brInt(s: string | null | undefined): number {
  const v = parseInt((s || "").trim().replace(/\s/g, ""), 10);
  return isNaN(v) ? 0 : v;
}

// Aceita dd/mm/aaaa e dd/mm/aa (planilhas antigas exportam ano com 2 dígitos).
// Formatos não reconhecidos viram null — enviar o texto cru quebra o ::DATE no Postgres.
export function brDateISO(s: string | null | undefined): string | null {
  const v = String(s ?? "").trim();
  if (!v) return null;
  if (/^\d{4}-\d{2}-\d{2}$/.test(v)) return v;
  const m = v.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4}|\d{2})\b/);
  if (!m) return null;
  const [, d, mo, y] = m;
  const year = y.length === 4 ? y : String(Number(y) >= 70 ? 1900 + Number(y) : 2000 + Number(y));
  return `${year}-${mo.padStart(2, "0")}-${d.padStart(2, "0")}`;
}

export function parseBrDateTime(s: string | null | undefined): Date | null {
  if (!s) return null;
  const c = s.trim().replace("-", " ");
  const m = c.match(/^(\d{2})\/(\d{2})\/(\d{4}) (\d{2}):(\d{2})$/);
  if (!m) return null;
  return new Date(+m[3], +m[2] - 1, +m[1], +m[4], +m[5]);
}
