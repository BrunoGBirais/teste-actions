import { Plus, X } from "lucide-react";
import type { ChatSession } from "../../types/chat";
import { formatDate } from "../../lib/format";

interface ChatSidebarProps {
  sessions: ChatSession[];
  currentSessionId: string | null;
  loading: boolean;
  onNewChat: () => void;
  onSelect: (sessionId: string) => void;
  onDelete: (sessionId: string) => void;
}

function tituloDe(session: ChatSession): string {
  if (session.titulo) {
    if (typeof session.titulo === "object" && session.titulo.content) return session.titulo.content;
    if (typeof session.titulo === "string") return session.titulo;
  }
  return "Nova conversa";
}

function SkeletonSessions() {
  return (
    <>
      {[0, 1, 2].map((i) => (
        <div className="skeleton-session" key={i}>
          <div className="skeleton skeleton-session-title" />
          <div className="skeleton skeleton-session-date" />
        </div>
      ))}
    </>
  );
}

export function ChatSidebar({ sessions, currentSessionId, loading, onNewChat, onSelect, onDelete }: ChatSidebarProps) {
  return (
    <aside id="sidebar">
      <div id="sidebar-header">
        <button id="newChatBtn" onClick={onNewChat}>
          <Plus />
          <span>Nova Conversa</span>
        </button>
      </div>
      <div id="sessionList">
        {loading ? (
          <SkeletonSessions />
        ) : sessions.length === 0 ? (
          <div style={{ color: "#999", textAlign: "center", padding: 20, fontSize: 12 }}>Nenhuma conversa ainda</div>
        ) : (
          sessions.map((session) => (
            <div
              key={session.session_id}
              className={`session-item${session.session_id === currentSessionId ? " active" : ""}`}
              onClick={() => onSelect(session.session_id)}
            >
              <div className="session-content">
                <div className="session-title">{tituloDe(session)}</div>
                <div className="session-date">{formatDate(session.data_inicio)}</div>
              </div>
              <button
                className="delete-btn"
                onClick={(e) => {
                  e.stopPropagation();
                  onDelete(session.session_id);
                }}
              >
                <X />
              </button>
            </div>
          ))
        )}
      </div>
    </aside>
  );
}
