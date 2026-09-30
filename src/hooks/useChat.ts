import { useCallback, useEffect, useRef, useState } from "react";
import { useAuth } from "../context/AuthContext";
import {
  deleteSession as apiDeleteSession,
  fetchHistory,
  fetchSessions,
  sendMessage as apiSendMessage,
  uploadFileToDrive,
} from "../services/n8n";
import { generateUUID } from "../lib/format";
import type { ChatMessage, ChatSession } from "../types/chat";

export interface DisplayMessage extends ChatMessage {
  key: string;
}

type StatusType = "" | "success" | "error" | "warning";

function toDisplayMessage(m: ChatMessage): DisplayMessage {
  return { ...m, key: `${m.id ?? m.timestamp ?? generateUUID()}` };
}

export function useChat() {
  const { sessionPrefix, sessionBelongsToCurrentUser } = useAuth();

  const [sessions, setSessions] = useState<ChatSession[]>([]);
  const [currentSessionId, setCurrentSessionId] = useState<string | null>(null);
  const [messages, setMessages] = useState<DisplayMessage[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [messagesLoading, setMessagesLoading] = useState(false);
  const [status, setStatus] = useState<{ text: string; type: StatusType }>({ text: "", type: "" });
  const [editing, setEditing] = useState<{ key: string; id?: number | string; content: string } | null>(null);

  const abortRef = useRef<AbortController | null>(null);
  const uploadAbortRef = useRef<AbortController | null>(null);
  const statusTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const setStatusMessage = useCallback((text: string, type: StatusType = "") => {
    setStatus({ text, type });
    if (statusTimerRef.current) clearTimeout(statusTimerRef.current);
    if (text) {
      statusTimerRef.current = setTimeout(() => setStatus({ text: "", type: "" }), 3000);
    }
  }, []);

  const refreshSessions = useCallback(async () => {
    const list = await fetchSessions(sessionPrefix);
    setSessions(list);
    return list;
  }, [sessionPrefix]);

  const loadSession = useCallback(async (sessionId: string) => {
    setCurrentSessionId(sessionId);
    setSessions((prev) => prev.filter((s) => !s._isTemp));
    setMessagesLoading(true);
    setMessages([]);
    const history = await fetchHistory(sessionId);
    setMessages(history.map(toDisplayMessage));
    setMessagesLoading(false);
  }, []);

  const startNewChat = useCallback(() => {
    setSessions((prev) => prev.filter((s) => !s._isTemp));
    const newId = sessionPrefix ? sessionPrefix + generateUUID() : generateUUID();
    setCurrentSessionId(newId);
    setMessages([]);
    const tempSession: ChatSession = {
      session_id: newId,
      titulo: "Nova conversa",
      data_inicio: new Date().toISOString(),
      _isTemp: true,
    };
    setSessions((prev) => [tempSession, ...prev]);
    setStatusMessage("Nova conversa iniciada", "success");
  }, [sessionPrefix, setStatusMessage]);

  // Bootstrap: load most recent session, or start a new empty chat.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      const list = await refreshSessions();
      if (cancelled) return;
      if (list.length > 0) {
        await loadSession(list[0].session_id);
      } else {
        startNewChat();
      }
    })();
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const confirmDeleteSession = useCallback(
    async (sessionId: string) => {
      if (!sessionBelongsToCurrentUser(sessionId)) {
        setStatusMessage("Você não tem permissão para excluir esta conversa.", "error");
        return false;
      }
      const success = await apiDeleteSession(sessionId);
      if (!success) {
        setStatusMessage("Erro ao excluir conversa.", "error");
        return false;
      }
      const list = await refreshSessions();
      if (currentSessionId === sessionId) {
        if (list.length > 0) {
          await loadSession(list[0].session_id);
        } else {
          startNewChat();
        }
      }
      return true;
    },
    [currentSessionId, loadSession, refreshSessions, sessionBelongsToCurrentUser, setStatusMessage, startNewChat],
  );

  const syncMessageIds = useCallback(async (sessionId: string) => {
    const latest = await fetchHistory(sessionId);
    if (!latest.length) return;
    setMessages((prev) => {
      if (prev.length === 0) return prev;
      const next = [...prev];
      const lastIdx = next.length - 1;
      const lastHistory = latest[latest.length - 1];
      if (lastHistory && next[lastIdx] && !next[lastIdx].id) {
        next[lastIdx] = { ...next[lastIdx], id: lastHistory.id };
      }
      if (next.length >= 2) {
        const userIdx = next.length - 2;
        const userHistory = latest[latest.length - 2];
        if (userHistory && next[userIdx] && !next[userIdx].id) {
          next[userIdx] = { ...next[userIdx], id: userHistory.id };
        }
      }
      return next;
    });
  }, []);

  const send = useCallback(
    async (text: string) => {
      const trimmed = text.trim();
      if (!trimmed || isLoading || !currentSessionId) return;

      if (editing) {
        // Editar só limpa a visualização local; o histórico no n8n permanece.
        setMessages((prev) => {
          const idx = prev.findIndex((m) => m.key === editing.key);
          return idx >= 0 ? prev.slice(0, idx) : prev;
        });
        setEditing(null);
      }

      const userMsg: DisplayMessage = { key: generateUUID(), role: "user", content: trimmed, timestamp: Date.now() };
      setMessages((prev) => [...prev, userMsg]);
      setIsLoading(true);
      abortRef.current = new AbortController();
      const response = await apiSendMessage(trimmed, currentSessionId, abortRef.current.signal);
      abortRef.current = null;
      if (response !== "Geração cancelada.") {
        setMessages((prev) => [
          ...prev,
          { key: generateUUID(), role: "assistant", content: response, timestamp: Date.now() },
        ]);
      }
      setIsLoading(false);
      await syncMessageIds(currentSessionId);
      await refreshSessions();
    },
    [currentSessionId, editing, isLoading, refreshSessions, syncMessageIds],
  );

  const stopGeneration = useCallback(() => {
    if (abortRef.current) {
      abortRef.current.abort();
      abortRef.current = null;
      setStatusMessage("Geração interrompida.", "warning");
      setIsLoading(false);
    }
    if (uploadAbortRef.current) {
      uploadAbortRef.current.abort();
      uploadAbortRef.current = null;
      setStatusMessage("Upload cancelado.", "warning");
      setIsLoading(false);
    }
  }, [setStatusMessage]);

  const startEdit = useCallback((msg: DisplayMessage) => {
    setEditing({ key: msg.key, id: msg.id, content: msg.content });
  }, []);

  const cancelEdit = useCallback(() => setEditing(null), []);

  const uploadFile = useCallback(
    async (file: File) => {
      setMessages((prev) => [
        ...prev,
        { key: generateUUID(), role: "user", content: `Enviando arquivo: ${file.name}`, file: file.name },
      ]);
      setStatusMessage(`Processando ${file.name}...`, "warning");
      setIsLoading(true);
      uploadAbortRef.current = new AbortController();
      try {
        await uploadFileToDrive(file, currentSessionId, uploadAbortRef.current.signal);
        setStatusMessage(`${file.name} processado com sucesso!`, "success");
        setMessages((prev) => [
          ...prev,
          {
            key: generateUUID(),
            role: "assistant",
            content: `✅ **Arquivo Recebido**\n\nO documento "${file.name}" foi processado. Você pode fazer perguntas sobre ele agora.`,
          },
        ]);
      } catch (error) {
        if (!(error instanceof DOMException && error.name === "AbortError")) {
          console.error("Upload error:", error);
          setStatusMessage(`Erro ao processar ${file.name}`, "error");
          setMessages((prev) => [
            ...prev,
            {
              key: generateUUID(),
              role: "assistant",
              content: `❌ **Falha no envio**\n\nNão foi possível processar o arquivo "${file.name}". Tente novamente.`,
            },
          ]);
        }
      } finally {
        uploadAbortRef.current = null;
        setIsLoading(false);
      }
    },
    [currentSessionId, setStatusMessage],
  );

  return {
    sessions,
    currentSessionId,
    messages,
    isLoading,
    messagesLoading,
    status,
    editing,
    setStatusMessage,
    loadSession,
    startNewChat,
    confirmDeleteSession,
    send,
    stopGeneration,
    startEdit,
    cancelEdit,
    uploadFile,
  };
}
