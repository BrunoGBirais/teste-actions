// Limpeza de encoding na entrada do upload: deixa o texto 100% ASCII, sem
// acento e sem caractere corrompido, preservando a estrutura do CSV.
//
// Porte do pipeline de .github/skills/limpeza-encoding/scripts/encoding_fix.py.
// Rodar isto ANTES do parser evita que "Produção" e "Produ??o" virem duas
// categorias no GROUP BY e que um join por nome de cliente perca linha.
//
// Ordem das etapas (da mais confiavel para a menos):
//   1. deteccao de encoding do arquivo (BOM / UTF-8 / Windows-1252);
//   2. mojibake duplo ("Ã§Ã£o" -> "ção"): reversivel, os bytes ainda estao la;
//   3. U+FFFD: informacao perdida na origem, resolvida por glossario/lexico
//      ou declarada como pendencia — nunca chutada;
//   4. normalizacao ASCII;
//   5. validacao estrutural (linhas/separadores/aspas nao podem mudar).

import { GLOSSARIO } from "./glossarioEncoding";

const RUINA = "\uFFFD";
const ACENTUADOS = "áàâãäéèêëíìîïóòôõöúùûüçñýÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑÝºª";

// Sequencias tipicas de UTF-8 lido como CP1252 ("mojibake duplo"), ex.: "ç" -> "Ã§".
const ASSINATURA_DUPLO = /[ÃÂ][\u0080-\u00ff\u2013\u2014\u201c\u201d\u2019\u20ac]/g;

// A classe exclui os separadores de coluna de proposito: sem isso o token
// atravessa a celula e vira a linha inteira, e nada casa com o glossario.
const TOKEN_QUEBRADO = new RegExp(`[^\\s,;|\t"\r\n]*${RUINA}[^\\s,;|\t"\r\n]*`, "g");

// Substituicoes que a remocao de acento (NFD) nao resolve sozinha.
const ESPECIAIS: Record<string, string> = {
  "\ufeff": "", // BOM
  "\u00ba": "", // ordinal masculino -> some ("01o" -> "01")
  "\u00b0": "", // grau              -> some ("N 32")
  "\u00aa": "", // ordinal feminino  -> some ("3 ED")
  "\u00b4": "'", // acento agudo solto -> apostrofo (L'Acqua)
  "\u2019": "'",
  "\u2018": "'",
  "\u201c": '"',
  "\u201d": '"',
  "\u2013": "-",
  "\u2014": "-",
  "\u00a0": " ", // espaco nao separavel
  "\u00b5": "u",
  "\u00d7": "x",
  "\u00f7": "/",
  "\u20ac": "EUR",
  "\u00a3": "GBP",
  "\u00a5": "JPY",
  "\u2026": "...",
  "\u2022": "-",
  "\u00ad": "",
};

// Trocas de letra que o NFD nao cobre (nao sao acento, sao letras proprias).
const LETRAS: Record<string, string> = {
  "ç": "c", "Ç": "C", "ñ": "n", "Ñ": "N", "ð": "d", "Ð": "D",
  "þ": "th", "Þ": "Th", "æ": "ae", "Æ": "AE", "ø": "o", "Ø": "O",
  "ß": "ss", "ł": "l", "Ł": "L", "đ": "d", "Đ": "D",
};

export interface Pendencia {
  token: string;
  ocorrencias: number;
  motivo: string;
  exemplos: string[];
}

export interface Laudo {
  arquivo: string;
  encodingDetectado: string;
  avisos: string[];
  problemas: string[];
  correcoes: string[];
  /** Tokens U+FFFD que exigem decisao humana. Com pendencia, `texto` vem null. */
  pendencias: Pendencia[];
  quebrasEstrutura: string[];
  asciiPuro: boolean;
}

export interface ResultadoLimpeza {
  /** null = arquivo reprovado (pendencia ou quebra estrutural); nao use os dados. */
  texto: string | null;
  laudo: Laudo;
}

// --------------------------------------------------------------------------
// 1. Leitura e deteccao de encoding
// --------------------------------------------------------------------------

interface TextoLido {
  texto: string;
  encoding: string;
  avisos: string[];
}

function lerBuffer(buf: ArrayBuffer): TextoLido {
  const bytes = new Uint8Array(buf);
  if (bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) {
    return {
      texto: new TextDecoder("utf-8").decode(bytes.subarray(3)),
      encoding: "utf-8-sig (BOM)",
      avisos: ["arquivo tinha BOM UTF-8"],
    };
  }
  if (bytes[0] === 0xff && bytes[1] === 0xfe) {
    return { texto: new TextDecoder("utf-16le").decode(bytes.subarray(2)), encoding: "utf-16 (BOM)", avisos: ["arquivo estava em UTF-16"] };
  }
  if (bytes[0] === 0xfe && bytes[1] === 0xff) {
    return { texto: new TextDecoder("utf-16be").decode(bytes.subarray(2)), encoding: "utf-16 (BOM)", avisos: ["arquivo estava em UTF-16"] };
  }
  try {
    // fatal: um arquivo Latin1 lanca aqui; um UTF-8 valido passa direto.
    return { texto: new TextDecoder("utf-8", { fatal: true }).decode(bytes), encoding: "utf-8", avisos: [] };
  } catch {
    return {
      texto: new TextDecoder("windows-1252").decode(bytes),
      encoding: "windows-1252",
      avisos: ["nao decodifica como utf-8; li como Windows-1252"],
    };
  }
}

// --------------------------------------------------------------------------
// 2. Mojibake duplo (reversivel, 100% codigo)
// --------------------------------------------------------------------------

// Bytes 0x80-0x9F do CP1252 que nao coincidem com Unicode.
const CP1252_ALTOS: Record<string, number> = {
  "\u20ac": 0x80, "\u201a": 0x82, "\u0192": 0x83, "\u201e": 0x84, "\u2026": 0x85,
  "\u2020": 0x86, "\u2021": 0x87, "\u02c6": 0x88, "\u2030": 0x89, "\u0160": 0x8a,
  "\u2039": 0x8b, "\u0152": 0x8c, "\u017d": 0x8e, "\u2018": 0x91, "\u2019": 0x92,
  "\u201c": 0x93, "\u201d": 0x94, "\u2022": 0x95, "\u2013": 0x96, "\u2014": 0x97,
  "\u02dc": 0x98, "\u2122": 0x99, "\u0161": 0x9a, "\u203a": 0x9b, "\u0153": 0x9c,
  "\u017e": 0x9e, "\u0178": 0x9f,
};

/** Reverte a leitura errada: devolve os bytes originais ou null se nao couberem. */
function paraBytes(texto: string, tabela: "cp1252" | "latin-1"): Uint8Array | null {
  const bytes = new Uint8Array(texto.length);
  for (let i = 0; i < texto.length; i++) {
    const cp = texto.codePointAt(i) as number;
    if (cp > 0xffff) return null; // fora do BMP: nao veio de byte unico
    if (cp <= 0xff) {
      bytes[i] = cp;
      continue;
    }
    const alto = tabela === "cp1252" ? CP1252_ALTOS[texto[i]] : undefined;
    if (alto === undefined) return null;
    bytes[i] = alto;
  }
  return bytes;
}

function contar(texto: string, re: RegExp): number {
  return (texto.match(re) || []).length;
}

function corrigirMojibakeDuplo(texto: string): { texto: string; mudou: boolean } {
  const antes = contar(texto, ASSINATURA_DUPLO);
  if (antes === 0) return { texto, mudou: false };

  const utf8 = new TextDecoder("utf-8", { fatal: true });
  for (const tabela of ["cp1252", "latin-1"] as const) {
    const bytes = paraBytes(texto, tabela);
    if (!bytes) continue;
    let tentativa: string;
    try {
      tentativa = utf8.decode(bytes);
    } catch {
      continue;
    }
    if (contar(tentativa, ASSINATURA_DUPLO) < antes && !tentativa.includes(RUINA)) {
      return { texto: tentativa, mudou: true };
    }
  }
  return { texto, mudou: false };
}

// --------------------------------------------------------------------------
// 3. Reconstrucao do caractere perdido (U+FFFD)
// --------------------------------------------------------------------------

function semAcento(txt: string): string {
  const trocado = Array.from(txt).map((c) => LETRAS[c] ?? c).join("");
  return trocado.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
}

function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function extrairTokensQuebrados(texto: string): Map<string, number> {
  const contagem = new Map<string, number>();
  for (const m of texto.matchAll(TOKEN_QUEBRADO)) {
    contagem.set(m[0], (contagem.get(m[0]) || 0) + 1);
  }
  return new Map([...contagem].sort((a, b) => b[1] - a[1]));
}

/** Vocabulario de palavras acentuadas conhecidas, tirado do proprio corpus. */
function construirLexico(texto: string, extra: string[] = []): Set<string> {
  const lexico = new Set(extra);
  const palavras = texto.matchAll(new RegExp(`[0-9A-Za-z${ACENTUADOS}'.]+`, "g"));
  for (const [p] of palavras) {
    if (Array.from(p).some((c) => ACENTUADOS.includes(c))) lexico.add(p);
  }
  return lexico;
}

/** Regex do token com cada U+FFFD virando "um caractere acentuado qualquer". */
function padraoDoNucleo(nucleo: string, fator: 1 | 2): RegExp | null {
  let alvo = nucleo;
  if (fator === 2) {
    if (!alvo.includes(RUINA + RUINA)) return null;
    alvo = alvo.split(RUINA + RUINA).join(RUINA);
  }
  const partes = Array.from(alvo).map((c) => (c === RUINA ? `[${ACENTUADOS}]` : escapeRegExp(c)));
  return new RegExp(`^${partes.join("")}$`);
}

const CHAVES_GLOSSARIO = Object.keys(GLOSSARIO).sort((a, b) => b.length - a.length);

/**
 * Descobre o que era um token com U+FFFD. Devolve [valor, metodo]; valor null
 * significa "nao resolvido, precisa de decisao humana".
 */
function resolverToken(token: string, lexico: Set<string>): [string | null, string] {
  if (GLOSSARIO[token]) return [GLOSSARIO[token], "glossario"];

  const nucleo = token.replace(/^[.,;:()[\]{}/-]+/, "").replace(/[.,;:()[\]{}/-]+$/, "");
  if (GLOSSARIO[nucleo]) return [token.split(nucleo).join(GLOSSARIO[nucleo]), "glossario"];

  // Token composto ("Menta-Lim?o", "Servi?os", "Cx.V?lvula"): aplica as entradas
  // do glossario de dentro do token, da mais longa para a mais curta. Chaves
  // curtas ("P?", "N?") so valem soltas, senao "P?ssego" viraria "Possego".
  let composto = token;
  for (const chave of CHAVES_GLOSSARIO) {
    if (!composto.includes(chave)) continue;
    const valor = GLOSSARIO[chave];
    if (chave.split(RUINA).join("").length < 3) {
      composto = composto.replace(new RegExp(`(?<![A-Za-z])${escapeRegExp(chave)}(?![A-Za-z])`, "g"), () => valor);
    } else {
      composto = composto.split(chave).join(valor);
    }
  }
  if (!composto.includes(RUINA)) return [composto, "glossario (composicao)"];

  for (const fator of [1, 2] as const) {
    const padrao = padraoDoNucleo(nucleo, fator);
    if (!padrao) continue;
    const candidatos = [...lexico].filter((p) => padrao.test(p));
    const formas = new Set(candidatos.map(semAcento));
    if (formas.size === 1) {
      const limpo = [...formas][0];
      return [token.split(nucleo).join(limpo), `lexico (${candidatos.length} candidato)`];
    }
    if (formas.size > 1) return [null, "ambiguo: " + [...formas].sort().slice(0, 4).join(", ")];
  }

  return [null, "sem candidato no lexico"];
}

function exemplos(linhas: string[], token: string, n = 3): string[] {
  const saida: string[] = [];
  const vistos = new Set<string>();
  for (const linha of linhas) {
    if (linha.includes(token) && !vistos.has(linha)) {
      vistos.add(linha);
      saida.push(linha.slice(0, 160));
    }
    if (saida.length >= n) break;
  }
  return saida;
}

// --------------------------------------------------------------------------
// 4. Normalizacao ASCII
// --------------------------------------------------------------------------

export function paraAscii(texto: string): string {
  const trocado = Array.from(texto)
    .map((c) => ESPECIAIS[c] ?? LETRAS[c] ?? c)
    .join("");
  return trocado.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
}

// --------------------------------------------------------------------------
// 5. Validacao estrutural
// --------------------------------------------------------------------------

function forma(texto: string): Record<string, number> {
  return {
    linhas: texto.split("\n").length,
    "ponto-e-virgula": contar(texto, /;/g),
    virgula: contar(texto, /,/g),
    tab: contar(texto, /\t/g),
    aspas: contar(texto, /"/g),
    "quebras CRLF": contar(texto, /\r\n/g),
  };
}

/** A limpeza so troca caracteres: se a contagem mudou, deslocou celula. */
function validarEstrutura(antes: string, depois: string): string[] {
  const a = forma(antes);
  const d = forma(depois);
  return Object.keys(a).filter((k) => a[k] !== d[k]).map((k) => `${k}: ${a[k]} -> ${d[k]}`);
}

// --------------------------------------------------------------------------
// API principal
// --------------------------------------------------------------------------

export function limparTexto(original: string, arquivo: string, encoding = "utf-8", avisos: string[] = []): ResultadoLimpeza {
  const laudo: Laudo = {
    arquivo,
    encodingDetectado: encoding,
    avisos,
    problemas: [],
    correcoes: [],
    pendencias: [],
    quebrasEstrutura: [],
    asciiPuro: false,
  };

  if (encoding.includes("BOM")) {
    laudo.problemas.push("BOM no inicio do arquivo (gruda na 1a coluna do CSV)");
    laudo.correcoes.push("BOM removido");
  }

  const duplo = corrigirMojibakeDuplo(original);
  let texto = duplo.texto;
  if (duplo.mudou) {
    laudo.problemas.push('UTF-8 lido como CP1252 (mojibake duplo, ex.: "Ã§")');
    laudo.correcoes.push("bytes reinterpretados (correcao reversivel, sem perda)");
  }

  if (texto.includes(RUINA)) {
    const tokens = extrairTokensQuebrados(texto);
    const totalRuina = contar(texto, new RegExp(RUINA, "g"));
    laudo.problemas.push(`${totalRuina} caractere(s) ilegivel(is) no arquivo de origem (U+FFFD)`);
    const lexico = construirLexico(texto);
    const linhas = texto.split("\n");
    const mapa = new Map<string, string>();
    for (const [token, qtd] of tokens) {
      const [valor, metodo] = resolverToken(token, lexico);
      if (valor === null) {
        laudo.pendencias.push({ token, ocorrencias: qtd, motivo: metodo, exemplos: exemplos(linhas, token) });
      } else {
        mapa.set(token, valor);
        laudo.correcoes.push(`"${token}" -> "${valor}" (${metodo})`);
      }
    }
    // Um passe unico casando o token inteiro: trocar token a token faria a
    // chave curta "P?" atingir tambem o miolo de "P?ssego" ("Possego").
    texto = texto.replace(TOKEN_QUEBRADO, (m) => mapa.get(m) ?? m);
  }

  // Com pendencia, para: gravar um chute silencioso e pior do que parar.
  if (laudo.pendencias.length) return { texto: null, laudo };

  const naoAscii = contar(texto, /[^\x00-\x7F]/g);
  if (naoAscii) {
    laudo.problemas.push(`${naoAscii} caractere(s) nao-ASCII validos (acento/simbolo)`);
    laudo.correcoes.push(`${naoAscii} acento(s)/simbolo(s) normalizados para ASCII`);
  }

  const limpo = paraAscii(texto);
  laudo.quebrasEstrutura = validarEstrutura(original, limpo);
  laudo.asciiPuro = !/[^\x00-\x7F]/.test(limpo);

  if (laudo.quebrasEstrutura.length) return { texto: null, laudo };
  return { texto: limpo, laudo };
}

/** Le o arquivo, corrige o encoding e devolve texto ASCII pronto para o parser. */
export async function limparArquivo(file: File): Promise<ResultadoLimpeza> {
  const { texto, encoding, avisos } = lerBuffer(await file.arrayBuffer());
  return limparTexto(texto, file.name, encoding, avisos);
}

/** Linhas de log para o usuario: resumo do que mudou e o detalhe do que travou. */
export function resumirLaudo(laudo: Laudo): { texto: string; kind?: "ok" | "err" }[] {
  const linhas: { texto: string; kind?: "ok" | "err" }[] = [];
  if (!laudo.problemas.length) {
    linhas.push({ texto: `   Encoding OK (${laudo.encodingDetectado}), arquivo ja em ASCII.` });
    return linhas;
  }
  linhas.push({ texto: `   Encoding detectado: ${laudo.encodingDetectado}.` });
  for (const p of laudo.problemas) linhas.push({ texto: `   • ${p}` });

  const glossario = laudo.correcoes.filter((c) => c.includes("(glossario")).length;
  const lexico = laudo.correcoes.filter((c) => c.includes("(lexico")).length;
  if (glossario || lexico) {
    linhas.push({ texto: `   ${glossario + lexico} palavra(s) reconstruída(s): ${glossario} pelo glossário, ${lexico} pelo léxico do arquivo.` });
  }

  for (const p of laudo.pendencias) {
    linhas.push({ texto: `   • "${p.token}" — ${p.ocorrencias} ocorrência(s) — ${p.motivo}`, kind: "err" });
    for (const ex of p.exemplos.slice(0, 2)) linhas.push({ texto: `       ${ex}`, kind: "err" });
  }
  for (const q of laudo.quebrasEstrutura) {
    linhas.push({ texto: `   • estrutura alterada pela limpeza — ${q}`, kind: "err" });
  }
  return linhas;
}
