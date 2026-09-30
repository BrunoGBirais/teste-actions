import { useState } from "react";
import { MessageCircle, LayoutDashboard, ChevronDown, UploadCloud, UsersRound, Target, ListChecks, PanelLeftClose } from "lucide-react";
import type { DashboardSubTab, View } from "../types/view";

interface MainSidebarProps {
  view: View;
  dashboardSubTab: DashboardSubTab;
  isAdmin: boolean;
  onSwitchView: (view: View) => void;
  onSwitchSubTab: (tab: DashboardSubTab) => void;
  onOpenUploadDataset: () => void;
  onOpenManageUsers: () => void;
}

export function MainSidebar({
  view,
  dashboardSubTab,
  isAdmin,
  onSwitchView,
  onSwitchSubTab,
  onOpenUploadDataset,
  onOpenManageUsers,
}: MainSidebarProps) {
  const [collapsed, setCollapsed] = useState(false);
  const [submenuOpen, setSubmenuOpen] = useState(true);

  return (
    <aside className={`main-sidebar${collapsed ? " collapsed" : ""}`}>
      <div className="sidebar-header">
        <a href="https://printiag.com.br" target="_blank" rel="noopener noreferrer">
          <img src="https://printiag.com.br/demos/landing-2/images/logo-print.png" alt="PRINT IAG" />
        </a>
      </div>
      <ul className="sidebar-menu">
        <li>
          <button
            type="button"
            className={`sidebar-menu-btn${view === "chat" ? " is-active" : ""}`}
            onClick={() => onSwitchView("chat")}
          >
            <MessageCircle /> <span>Chat IA</span>
          </button>
        </li>
        <li>
          <button
            type="button"
            className={`sidebar-menu-btn${submenuOpen ? " submenu-open" : ""}`}
            onClick={() => setSubmenuOpen((v) => !v)}
          >
            <LayoutDashboard /> <span>Dashboard</span>
            <ChevronDown className="sidebar-menu-caret" />
          </button>
          <ul className={`sidebar-submenu${submenuOpen ? " is-open" : ""}`}>
            <li style={{ display: "none" }}>
              <button
                type="button"
                className={`sidebar-submenu-btn${view === "dashboard" && dashboardSubTab === "oee" ? " is-active" : ""}`}
                onClick={() => {
                  onSwitchView("dashboard");
                  onSwitchSubTab("oee");
                }}
              >
                OEE Geral
              </button>
            </li>
            <li>
              <button
                type="button"
                className={`sidebar-submenu-btn${view === "dashboard" && dashboardSubTab === "indicadores" ? " is-active" : ""}`}
                onClick={() => {
                  onSwitchView("dashboard");
                  onSwitchSubTab("indicadores");
                }}
              >
                Semanal
              </button>
            </li>
            <li>
              <button
                type="button"
                className={`sidebar-submenu-btn${view === "dashboard" && dashboardSubTab === "indicadoresMensal" ? " is-active" : ""}`}
                onClick={() => {
                  onSwitchView("dashboard");
                  onSwitchSubTab("indicadoresMensal");
                }}
              >
                Mensal
              </button>
            </li>
          </ul>
        </li>
        <li style={{ marginTop: 16, borderTop: "1px solid var(--border-color)", paddingTop: 16 }} />
        {isAdmin && (
          <li>
            <button type="button" className="sidebar-menu-btn" title="Adicionar dados (admin)" onClick={onOpenUploadDataset}>
              <UploadCloud /> <span>Adicionar dados</span>
            </button>
          </li>
        )}
        {isAdmin && (
          <li>
            <button type="button" className="sidebar-menu-btn" title="Gerenciar usuários (admin)" onClick={onOpenManageUsers}>
              <UsersRound /> <span>Editar usuários</span>
            </button>
          </li>
        )}
        {isAdmin && (
          <li>
            <button
              type="button"
              className={`sidebar-menu-btn${view === "metas" ? " is-active" : ""}`}
              title="Metas de Equipamentos (admin)"
              onClick={() => onSwitchView("metas")}
            >
              <Target /> <span>Metas de Equip.</span>
            </button>
          </li>
        )}
        {isAdmin && (
          <li>
            <button
              type="button"
              className={`sidebar-menu-btn${view === "classificacao" ? " is-active" : ""}`}
              title="Classificações de apontamento (admin)"
              onClick={() => onSwitchView("classificacao")}
            >
              <ListChecks /> <span>Classificações</span>
            </button>
          </li>
        )}
      </ul>
      <div className="sidebar-footer">
        <button type="button" className="sidebar-toggle-btn" onClick={() => setCollapsed((v) => !v)}>
          <PanelLeftClose />
        </button>
      </div>
    </aside>
  );
}
