import { Menu } from "lucide-react";
import { UserMenu } from "./UserMenu";

interface ChatHeaderProps {
  showHistoryToggle: boolean;
  isOffline: boolean;
  onToggleHistory: () => void;
}

export function ChatHeader({ showHistoryToggle, isOffline, onToggleHistory }: ChatHeaderProps) {
  return (
    <header className="chat-header" style={{ padding: "12px 24px" }}>
      <button
        className="toggle-sidebar-btn"
        title="Alternar lista de conversas"
        style={{ marginRight: 16, display: showHistoryToggle ? "flex" : "none" }}
        onClick={onToggleHistory}
      >
        <Menu />
      </button>

      <div className="header-title" style={{ flex: 1, fontWeight: 600 }}>
        Assistente de Produção
      </div>

      <div className="header-right">
        <div
          className="connection-status"
          style={
            isOffline
              ? { color: "#f44336", background: "rgba(244, 67, 54, 0.1)", borderColor: "rgba(244, 67, 54, 0.2)" }
              : undefined
          }
        >
          <div
            className="connection-dot"
            style={
              isOffline
                ? { background: "#f44336", boxShadow: "0 0 5px #f44336", animation: "none" }
                : undefined
            }
          />
          <span>{isOffline ? "Offline" : "Online"}</span>
        </div>
        <UserMenu />
      </div>
    </header>
  );
}
