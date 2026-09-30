"use client";

import { LayoutDashboard } from "lucide-react";
import type { DashboardSubTab } from "../types/view";
import { OeeScreen } from "../components/dashboard/OeeScreen";
import { IndicadoresScreen } from "../components/dashboard/IndicadoresScreen";
import { IndicadoresMensalScreen } from "../components/dashboard/IndicadoresMensalScreen";
import { UploadSnapshotSection } from "../components/dashboard/UploadSnapshotSection";
import { useModoExibicao } from "../hooks/useModoExibicao";

interface DashboardPageProps {
  subTab: DashboardSubTab;
  showUpload: boolean;
}

export function DashboardPage({ subTab, showUpload }: DashboardPageProps) {
  useModoExibicao(() => {
    // Recarrega a tela visível — cada tela gerencia seu próprio refetch via reload().
    window.dispatchEvent(new CustomEvent("dashboard-auto-refresh"));
  });

  return (
    <section className="dashboard-area">
      <div className="dashboard-toolbar">
        <div className="dashboard-title">
          <LayoutDashboard />
          <span>Dashboard de Produção</span>
        </div>
        <div className="dashboard-actions" />
      </div>

      <div className="dashboard-status" />

      {showUpload && <UploadSnapshotSection />}

      {!showUpload && (
        <div className="dashboard-scroll">
          {subTab === "oee" && <OeeScreen />}
          {subTab === "indicadores" && <IndicadoresScreen />}
          {subTab === "indicadoresMensal" && <IndicadoresMensalScreen />}
        </div>
      )}
    </section>
  );
}
