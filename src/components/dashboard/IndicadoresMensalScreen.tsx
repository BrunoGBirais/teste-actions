import { useEffect } from "react";
import { RefreshCw } from "lucide-react";
import { useIndicadoresMensal } from "../../hooks/useIndicadoresMensal";
import { MaquinaFilterDropdown } from "./MaquinaFilterDropdown";
import { PeriodFilterDropdown } from "./PeriodFilterDropdown";
import { ChartCard } from "./ChartCard";
import { ChartCanvas } from "./ChartCanvas";
import { mesLabel } from "../../lib/format";
import {
  buildIndAcertoSemanaConfig,
  buildIndDisponibilidadeConfig,
  buildIndImprodutivosConfig,
  buildIndTiragemConfig,
  buildIndVelocAcertoConfig,
  buildIndVelocVirandoConfig,
  buildParetoAreaConfig,
  buildParetoGerencialConfig,
} from "../../lib/charts/indicadores";

export function IndicadoresMensalScreen() {
  const indm = useIndicadoresMensal();

  useEffect(() => {
    window.addEventListener("dashboard-auto-refresh", indm.reload);
    return () => window.removeEventListener("dashboard-auto-refresh", indm.reload);
  }, [indm.reload]);

  return (
    <div>
      <div className="dashboard-toolbar" style={{ padding: "12px 0 4px" }}>
        <div style={{ display: "flex", gap: 10, alignItems: "center", flexWrap: "wrap" }}>
          <label style={{ fontSize: 13, color: "var(--text-muted)" }}>Ano:</label>
          <select className="filter-select" style={{ minWidth: 90 }} value={indm.ano} onChange={(e) => indm.setAno(Number(e.target.value))}>
            {indm.anos.map((a) => (
              <option key={a} value={a}>
                {a}
              </option>
            ))}
          </select>
          <label style={{ fontSize: 13, color: "var(--text-muted)" }}>Máquina:</label>
          <MaquinaFilterDropdown filtro={indm.maquinaFiltro} />
          <label style={{ fontSize: 13, color: "var(--text-muted)" }}>Mês:</label>
          <PeriodFilterDropdown
            options={indm.mesesDisponiveis}
            selected={indm.mesesSelecionados}
            onChange={indm.setMesesSelecionados}
            labelFor={mesLabel}
          />
          <label style={{ fontSize: 13, color: "var(--text-muted)" }}>Operador:</label>
          <select className="filter-select" style={{ minWidth: 150 }} value={indm.operador} onChange={(e) => indm.setOperador(e.target.value)}>
            <option value="">Todos</option>
            {indm.operadoresDisponiveis.map((op) => (
              <option key={op} value={op}>
                {op}
              </option>
            ))}
          </select>
          <button
            type="button"
            style={{
              marginLeft: 8,
              display: "flex",
              alignItems: "center",
              gap: 6,
              padding: "6px 14px",
              background: "var(--accent,#2563eb)",
              color: "#fff",
              border: "none",
              borderRadius: 6,
              fontSize: 13,
              fontWeight: 600,
              cursor: "pointer",
            }}
            onClick={() => indm.reload()}
          >
            <RefreshCw style={{ width: 14, height: 14 }} /> Atualizar
          </button>
          <span style={{ fontSize: 12, color: "var(--text-muted)" }}>{indm.loading ? "Carregando…" : indm.error || ""}</span>
        </div>
      </div>

      {indm.data && (
        <>
          <div className="dashboard-row" style={{ marginTop: 12, gridTemplateColumns: "1fr" }}>
            <ChartCard title="Quantidade Produzindo x Tiragem Média" subtitle="peças produzidas e tiragem média por acerto">
              <ChartCanvas type="bar" {...buildIndTiragemConfig(indm.data.tiragem, indm.labels)} />
            </ChartCard>
          </div>

          <div className="dashboard-row" style={{ marginTop: 12, gridTemplateColumns: "1fr" }}>
            <ChartCard title='Velocidade Média Produzindo (com acerto)"' subtitle="real vs meta por mês (virando + acerto + improdutivos área e gerenciais)">
              <ChartCanvas type="bar" {...buildIndVelocAcertoConfig(indm.data.velocAcerto, indm.ano, "mes", mesLabel, indm.data.metas)} />
            </ChartCard>
          </div>

          <div className="dashboard-row" style={{ marginTop: 12, gridTemplateColumns: "1fr" }}>
            <ChartCard title="Tempo Médio de Acerto × Meta por Mês" subtitle="minutos por acerto: real vs meta (por mês)">
              <ChartCanvas type="bar" {...buildIndAcertoSemanaConfig(indm.data.acerto, indm.labels, indm.data.metas)} />
            </ChartCard>
          </div>

          <div className="dashboard-row" style={{ marginTop: 12, gridTemplateColumns: "1fr" }}>
            <ChartCard title="Velocidade Média Virando por Mês" subtitle="peças/hora real vs meta">
              <ChartCanvas type="bar" {...buildIndVelocVirandoConfig(indm.data.velocVirando, indm.labels, indm.data.metas)} />
            </ChartCard>
          </div>

          <div className="dashboard-row" style={{ marginTop: 12 }}>
            <ChartCard title="Índice de improdutivos área" subtitle="% sobre virando + improdutivo área, real vs meta">
              <ChartCanvas type="bar" {...buildIndImprodutivosConfig(indm.data.improdutivos, indm.labels, indm.data.metas)} />
            </ChartCard>
            <ChartCard title="Pareto de Improdutivos — Operacional" subtitle="top motivos de parada (último mês do período, escopo área)">
              <ChartCanvas type="bar" {...buildParetoAreaConfig(indm.data.paretoArea)} />
            </ChartCard>
          </div>

          <div className="dashboard-row" style={{ marginTop: 12 }}>
            <ChartCard title="Índice de Improdutivos Gerencial" subtitle="% sobre virando + acerto + improdutivos, real vs meta">
              <ChartCanvas type="bar" {...buildIndDisponibilidadeConfig(indm.data.improdutivos, indm.labels, indm.data.metas)} />
            </ChartCard>
            <ChartCard title="Pareto de Improdutivos — Gerencial" subtitle="top motivos de parada (último mês do período, escopo gerencial)">
              <ChartCanvas type="bar" {...buildParetoGerencialConfig(indm.data.paretoGerencial)} />
            </ChartCard>
          </div>
        </>
      )}
    </div>
  );
}
