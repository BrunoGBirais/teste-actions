import {
  CHAT_URL,
  DELETE_URL,
  HEALTH_URL,
  HISTORY_URL,
  SESSIONS_URL,
  UPLOAD_DATASET_URL,
  UPLOAD_URL,
} from "../config/constants";
import { authHeaders, getAccessToken } from "../lib/authToken";
import type { ChatMessage, ChatSession } from "../types/chat";

function sessionBelongsToPrefix(sid: unknown, prefix: string | null): boolean {
  if (!prefix) return false;
  return typeof sid === "string" && sid.startsWith(prefix);
}

// Escopo por usuário: só mostra sessões cujo session_id pertence ao usuário
// logado (prefixo `u_<userId>__`). Sessões antigas, sem prefixo, ficam
// invisíveis em qualquer login.
export async function fetchSessions(sessionPrefix: string | null): Promise<ChatSession[]> {
  try {
    const response = await fetch(SESSIONS_URL, { cache: "no-store", headers: authHeaders() });
    if (!response.ok) throw new Error("Failed to fetch sessions");
    const text = await response.text();
    if (!text || text.trim().length === 0) return [];
    let data: unknown;
    try {
      data = JSON.parse(text);
    } catch {
      return [];
    }
    const list: ChatSession[] = Array.isArray(data) ? data : data ? [data as ChatSession] : [];
    if (!sessionPrefix) {
      console.warn("⚠️ Sem usuário logado: ocultando todas as sessões.");
      return [];
    }
    return list.filter((s) => sessionBelongsToPrefix(s?.session_id, sessionPrefix));
  } catch (error) {
    console.error("❌ Error fetching sessions:", error);
    return [];
  }
}

interface RawHistoryItem {
  id?: number | string;
  message?: { type?: string; content?: string; timestamp?: string | number };
  created_at?: string | number;
  role?: string;
  content?: string;
  timestamp?: string | number;
}

export async function fetchHistory(sessionId: string): Promise<ChatMessage[]> {
  try {
    const response = await fetch(`${HISTORY_URL}?sessionId=${sessionId}`, { headers: authHeaders() });
    if (!response.ok) throw new Error("Failed to fetch history");
    const text = await response.text();
    if (!text || text.trim().length === 0) return [];
    let data: RawHistoryItem[];
    try {
      data = JSON.parse(text);
    } catch {
      return [];
    }
    return data.map((item) => {
      let processed: ChatMessage;
      if (item.message) {
        processed = {
          id: item.id,
          role: item.message.type === "human" ? "user" : "assistant",
          content: item.message.content || "",
          timestamp: item.created_at || item.message.timestamp,
        };
      } else {
        processed = {
          id: item.id,
          role: (item.role as ChatMessage["role"]) || "assistant",
          content: item.content || "",
          timestamp: item.timestamp,
        };
      }

      const legacyMatch = processed.content.match(/^Enviando arquivo: (.+)$/);
      const newMatch = processed.content.match(/^Arquivo (.+) enviado para análise\.$/);
      if ((legacyMatch || newMatch) && processed.role === "user") {
        processed.file = newMatch ? newMatch[1] : legacyMatch![1];
      }
      return processed;
    });
  } catch (error) {
    console.error("Error fetching history:", error);
    return [];
  }
}

export async function deleteSession(sessionId: string): Promise<boolean> {
  try {
    const response = await fetch(`${DELETE_URL}?sessionId=${sessionId}`, {
      method: "DELETE",
      headers: authHeaders(),
    });
    if (!response.ok) throw new Error("Failed to delete session");
    return true;
  } catch (error) {
    console.error("Error deleting session:", error);
    return false;
  }
}

export async function sendMessage(
  message: string,
  sessionId: string,
  signal?: AbortSignal,
): Promise<string> {
  try {
    const response = await fetch(CHAT_URL, {
      method: "POST",
      headers: authHeaders({ "Content-Type": "application/json" }),
      body: JSON.stringify({ chatInput: message, sessionId }),
      signal,
    });
    const rawText = await response.text();
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${rawText.slice(0, 200)}`);
    }
    if (!rawText || !rawText.trim()) {
      return "⚠️ Resposta vazia do servidor (verifique se o workflow do n8n está ativo e se o nó 'Respond to Webhook' está configurado).";
    }
    try {
      const data = JSON.parse(rawText);
      return data.output || data.message || data.text || data.answer || "Resposta recebida";
    } catch {
      return `⚠️ Servidor respondeu em formato inesperado: ${rawText.slice(0, 200)}`;
    }
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      return "Geração cancelada.";
    }
    console.error("Error sending message:", error);
    return `Desculpe, ocorreu um erro: ${(error as Error).message}`;
  }
}

export async function checkHealth(): Promise<boolean> {
  try {
    const response = await fetch(HEALTH_URL, { cache: "no-store" });
    if (!response.ok) return false;
    const data = await response.json();
    return data?.status === "ok";
  } catch {
    return false;
  }
}

export async function uploadFileToDrive(
  file: File,
  sessionId: string | null,
  signal?: AbortSignal,
): Promise<unknown> {
  const formData = new FormData();
  formData.append("file", file);
  if (sessionId) {
    formData.append("session_id", sessionId);
    formData.append("sessionId", sessionId);
  }
  const url = sessionId ? `${UPLOAD_URL}?sessionId=${sessionId}` : UPLOAD_URL;
  const response = await fetch(url, { method: "POST", body: formData, signal });
  if (!response.ok) throw new Error("Upload failed");
  const text = await response.text();
  if (!text || !text.trim()) return {};
  try {
    return JSON.parse(text);
  } catch {
    return {};
  }
}

export interface UploadDatasetResult {
  ok?: boolean;
  message?: string;
  error?: string;
  rows_imported?: number;
}

export async function uploadDataset(dataset: string, file: File): Promise<UploadDatasetResult> {
  const token = getAccessToken();
  if (!token) throw new Error("Sessão expirada. Faça login novamente.");
  const fd = new FormData();
  fd.append("dataset", dataset);
  fd.append("file", file, file.name);
  const r = await fetch(UPLOAD_DATASET_URL, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
    body: fd,
  });
  let j: UploadDatasetResult = {};
  try {
    j = await r.json();
  } catch {
    /* ignore non-JSON body */
  }
  if (!r.ok || j.ok === false) {
    throw new Error(j.message || j.error || `HTTP ${r.status}`);
  }
  return j;
}
