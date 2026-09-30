import { useEffect, useRef, useState } from "react";
import { ChevronDown, Moon, Sun, LogOut } from "lucide-react";
import { useAuth } from "../context/AuthContext";
import { useTheme } from "../context/ThemeContext";

export function UserMenu() {
  const { currentUser, isAdmin, logout } = useAuth();
  const { theme, toggleTheme } = useTheme();
  const [open, setOpen] = useState(false);
  const wrapRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function onDocClick(e: MouseEvent) {
      if (wrapRef.current && !wrapRef.current.contains(e.target as Node)) setOpen(false);
    }
    function onKeyDown(e: KeyboardEvent) {
      if (e.key === "Escape") setOpen(false);
    }
    document.addEventListener("click", onDocClick);
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("click", onDocClick);
      document.removeEventListener("keydown", onKeyDown);
    };
  }, []);

  const meta = currentUser?.user_metadata || {};
  const fullName = meta.full_name || currentUser?.email || "Usuário";
  const initials =
    fullName
      .split(/\s+/)
      .filter(Boolean)
      .slice(0, 2)
      .map((p) => p[0])
      .join("")
      .toUpperCase()
      .slice(0, 2) || "U";
  const roleLabel = isAdmin ? "Administrador" : "Visualizador";

  return (
    <div className="user-menu" ref={wrapRef}>
      <button
        type="button"
        className="user-menu-btn"
        aria-haspopup="true"
        aria-expanded={open}
        title="Opções do usuário"
        onClick={() => setOpen((v) => !v)}
      >
        <div className="user-avatar">{initials}</div>
        <div className="user-info">
          <div className="user-name">{fullName}</div>
          <div className="user-role">{roleLabel}</div>
        </div>
        <ChevronDown className="user-menu-caret" />
      </button>
      <div className={`user-menu-dropdown${open ? " open" : ""}`} role="menu">
        <button type="button" className="user-menu-item" title="Alternar tema" onClick={toggleTheme}>
          {theme === "dark" ? <Sun style={{ width: 14, height: 14 }} /> : <Moon style={{ width: 14, height: 14 }} />}
          <span>{theme === "dark" ? "Light" : "Dark"}</span>
        </button>
        <div className="user-menu-sep" />
        <button
          type="button"
          className="user-menu-item user-menu-item-danger"
          title="Sair do sistema"
          onClick={() => {
            setOpen(false);
            logout();
          }}
        >
          <LogOut /> <span>Sair</span>
        </button>
      </div>
    </div>
  );
}
