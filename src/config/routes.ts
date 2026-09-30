import type { DashboardSubTab } from "../types/view";

// URL segment under /dashboard for each sub-tab, plus the admin upload screen.
export const DASHBOARD_SLUGS: Record<DashboardSubTab, string> = {
  oee: "oee",
  indicadores: "semanal",
  indicadoresMensal: "mensal",
};
export const DASHBOARD_UPLOAD_SLUG = "upload";
