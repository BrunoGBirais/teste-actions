import { marked } from "marked";
import hljs from "highlight.js";
import type { ParsedAssistantContent, ProductCard, QuickFormQuestion } from "../types/chat";

const renderer = new marked.Renderer();
renderer.code = (code: string, infostring: string | undefined) => {
  const highlighted = hljs.highlightAuto(code).value;
  return `<pre><code class="hljs${infostring ? " language-" + infostring : ""}">${highlighted}</code></pre>`;
};

marked.setOptions({ renderer, breaks: true, gfm: true });

// Marca as seções (h2) com uma classe de cor conforme o emoji inicial, e
// força links a abrirem em nova aba — mesma pós-processagem do DOM que a
// versão legada fazia depois do innerHTML.
function postProcess(html: string): string {
  const doc = new DOMParser().parseFromString(`<div>${html}</div>`, "text/html");
  doc.querySelectorAll("h2").forEach((h) => {
    const t = (h.textContent || "").trim();
    if (/^✅|^✔|^✓/.test(t)) h.classList.add("sec-spec");
    else if (/^⚠|^❌|^🚫/.test(t)) h.classList.add("sec-warn");
    else if (/^🧮|^📊|^🔢|^🏢|^📋/.test(t)) h.classList.add("sec-info");
    else if (/^🧾|^➡|^👉|^🚀|^🎯/.test(t)) h.classList.add("sec-cta");
  });
  doc.querySelectorAll("a").forEach((link) => {
    link.setAttribute("target", "_blank");
    link.setAttribute("rel", "noopener noreferrer");
  });
  return doc.body.firstElementChild?.innerHTML ?? html;
}

export function parseAssistantContent(content: string): ParsedAssistantContent {
  let rawContent = content || "";
  let quickReplies: string[] | null = null;
  let quickForm: QuickFormQuestion[] | null = null;
  let products: ProductCard[] | null = null;

  const qrMatch = rawContent.match(/<!--\s*QUICK_REPLIES\s*:\s*(\[[\s\S]*?\])\s*-->/i);
  if (qrMatch) {
    try {
      const parsed = JSON.parse(qrMatch[1]);
      if (Array.isArray(parsed) && parsed.length > 0) {
        quickReplies = parsed.filter((x: unknown): x is string => typeof x === "string" && x.trim().length > 0);
      }
    } catch (e) {
      console.warn("Quick replies parse failed:", e);
    }
    rawContent = rawContent.replace(qrMatch[0], "").trim();
  }

  const qfMatch = rawContent.match(/<!--\s*QUICK_FORM\s*:\s*(\[[\s\S]*?\])\s*-->/i);
  if (qfMatch) {
    try {
      const parsed = JSON.parse(qfMatch[1]);
      if (Array.isArray(parsed) && parsed.length > 0) {
        quickForm = parsed.filter(
          (x: unknown): x is QuickFormQuestion => !!x && typeof x === "object" && typeof (x as QuickFormQuestion).q === "string",
        );
      }
    } catch (e) {
      console.warn("Quick form parse failed:", e);
    }
    rawContent = rawContent.replace(qfMatch[0], "").trim();
  }

  const prMatch = rawContent.match(/<!--\s*PRODUCTS\s*:\s*(\[[\s\S]*?\])\s*-->/i);
  if (prMatch) {
    try {
      const parsed = JSON.parse(prMatch[1]);
      if (Array.isArray(parsed) && parsed.length > 0) {
        products = parsed.filter(
          (x: unknown): x is ProductCard => !!x && typeof x === "object" && typeof (x as ProductCard).nome === "string",
        );
      }
    } catch (e) {
      console.warn("Products parse failed:", e);
    }
    rawContent = rawContent.replace(prMatch[0], "").trim();
  }

  const html = postProcess(marked.parse(rawContent, { async: false }) as string);

  return { html, quickReplies, quickForm, products };
}
