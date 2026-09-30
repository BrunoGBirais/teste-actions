"use client";

import { createContext, useContext, useEffect, useState, type ReactNode } from "react";
import { usePathname, useRouter } from "next/navigation";
import { AuthProvider, useAuth } from "../context/AuthContext";
import { ThemeProvider } from "../context/ThemeContext";
import { LoginPage } from "../components/LoginPage";
import { MainSidebar } from "./MainSidebar";
import { ChatHeader } from "./ChatHeader";
import { UsersModal } from "../components/modals/UsersModal";
import { useConnectionStatus } from "../hooks/useConnectionStatus";
import { DASHBOARD_SLUGS, DASHBOARD_UPLOAD_SLUG } from "../config/routes";
import type { DashboardSubTab, View } from "../types/view";

const ADMIN_PATHS = ["/metas", "/classificacao", `/dashboard/${DASHBOARD_UPLOAD_SLUG}`];
const VIEW_PATHS: Record<View, string> = {
  chat: "/chat",
  dashboard: `/dashboard/${DASHBOARD_SLUGS.indicadores}`,
  metas: "/metas",
  classificacao: "/classificacao",
};

// Shell state that route pages need: the chat history sidebar lives in the
// header toggle but is rendered by the chat page.
interface ShellContextValue {
  chatSidebarOpen: boolean;
  closeChatSidebar: () => void;
}
const ShellContext = createContext<ShellContextValue | null>(null);

export function useShell(): ShellContextValue {
  const ctx = useContext(ShellContext);
  if (!ctx) throw new Error("useShell must be used within AppShell");
  return ctx;
}

function viewFromPath(pathname: string): { view: View; subTab: DashboardSubTab } {
  const [, first, second] = pathname.split("/");
  const subTab =
    (Object.keys(DASHBOARD_SLUGS) as DashboardSubTab[]).find((k) => DASHBOARD_SLUGS[k] === second) ?? "indicadores";
  if (first === "dashboard") return { view: "dashboard", subTab };
  if (first === "metas" || first === "classificacao") return { view: first, subTab };
  return { view: "chat", subTab };
}

function Shell({ children }: { children: ReactNode }) {
  const { isAdmin } = useAuth();
  const isOffline = useConnectionStatus();
  const pathname = usePathname();
  const router = useRouter();
  const { view, subTab } = viewFromPath(pathname);

  const [usersModalOpen, setUsersModalOpen] = useState(false);
  const [chatSidebarOpen, setChatSidebarOpen] = useState(true);

  useEffect(() => {
    function handleResize() {
      setChatSidebarOpen(window.innerWidth > 768);
    }
    handleResize();
    window.addEventListener("resize", handleResize);
    return () => window.removeEventListener("resize", handleResize);
  }, []);

  // Admin screens were only hidden from the menu; with real URLs they also
  // need to bounce non-admins who type the address directly.
  const blocked = !isAdmin && ADMIN_PATHS.some((p) => pathname.startsWith(p));
  useEffect(() => {
    if (blocked) router.replace("/chat");
  }, [blocked, router]);

  return (
    <ShellContext.Provider value={{ chatSidebarOpen, closeChatSidebar: () => setChatSidebarOpen(false) }}>
      <div className="app-container">
        <MainSidebar
          view={view}
          dashboardSubTab={subTab}
          isAdmin={isAdmin}
          onSwitchView={(next) => {
            if (next !== view) router.push(VIEW_PATHS[next]);
          }}
          onSwitchSubTab={(tab) => router.push(`/dashboard/${DASHBOARD_SLUGS[tab]}`)}
          onOpenUploadDataset={() => router.push(`/dashboard/${DASHBOARD_UPLOAD_SLUG}`)}
          onOpenManageUsers={() => setUsersModalOpen(true)}
        />
        <div className="content-wrapper">
          <ChatHeader
            showHistoryToggle={view === "chat"}
            isOffline={isOffline}
            onToggleHistory={() => setChatSidebarOpen((v) => !v)}
          />
          {!blocked && children}
        </div>

        <UsersModal open={usersModalOpen} onClose={() => setUsersModalOpen(false)} />
      </div>
    </ShellContext.Provider>
  );
}

function AuthGate({ children }: { children: ReactNode }) {
  const { ready, isLoggedIn } = useAuth();
  if (!ready) return null;
  return isLoggedIn ? <Shell>{children}</Shell> : <LoginPage />;
}

export function AppShell({ children }: { children: ReactNode }) {
  return (
    <ThemeProvider>
      <AuthProvider>
        <AuthGate>{children}</AuthGate>
      </AuthProvider>
    </ThemeProvider>
  );
}
