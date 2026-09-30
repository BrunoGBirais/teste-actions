import { useEffect } from "react";
import { RefreshCw } from "lucide-react";
import { useIndicadoresSemana } from "../../hooks/useIndicadoresSemana";
import { MaquinaFilterDropdown } from "./MaquinaFilterDropdown";
import { PeriodFilterDropdown } from "./PeriodFilterDropdown";
import { ChartCard } from "./ChartCard";
import { ChartCanvas } from "./ChartCanvas";
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

export function IndicadoresScreen() {
  const ind = useIndicadoresSemana();

  useEffect(() => {
    window.addEventListener("dashboard-auto-refresh", ind.reload);
    return () => window.removeEventListener("dashboard-auto-refresh", ind.reload);
  }, [ind.reload]);

  return (
    <div>
      <div className="dashboard-toolbar" style={{ padding: "12px 0 4px" }}>
        <div style={{ display: "flex", gap: 10, alignItems: "center", flexWrap: "wrap" }}>
          <label style={{ fontSize: 13, color: "var(--text-muted)" }}>Ano:</label>
          <select className="filter-select" style={{ minWidth: 90 }} value={ind.ano} onChange={(e) => ind.setAno(Number(e.target.value))}>
            {ind.anos.map((a) => (
              <option key={a} value={a}>
                {a}
              </option>
            ))}
          </select>
          <label style={{ fontSize: 13, color: "var(--text-muted)" }}>Máquina:</label>
          <MaquinaFilterDropdown filtro={ind.maquinaFiltro} />
          <label style={{ fontSize: 13, color: "var(--text-muted)" }}>Semana:</label>
          <PeriodFilterDropdown
            options={ind.semanasDisponiveis}
            selected={ind.semanasSelecionadas}
            onChange={ind.setSemanasSelecionadas}
            labelFor={(n) => "S" + n}
          />
          <label style={{ fontSize: 13, color: "var(--text-muted)" }}>Operador:</label>
          <select className="filter-select" style={{ minWidth: 150 }} value={ind.operador} onChange={(e) => ind.setOperador(e.target.value)}>
            <option value="">Todos</option>
            {ind.operadoresDisponiveis.map((op) => (
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
            onClick={() => ind.reload()}
          >
            <RefreshCw style={{ width: 14, height: 14 }} /> Atualizar
          </button>
          <span style={{ fontSize: 12, color: "var(--text-muted)" }}>{ind.loading ? "Carregando…" : ind.error || ""}</span>
        </div>
      </div>

      {ind.data && (
        <>
          <div className="dashboard-row" style={{ marginTop: 12, gridTemplateColumns: "1fr" }}>
            <ChartCard title="Quantidade Produzindo X Tiragem Média" subtitle="peças produzidas e tiragem média por acerto">
              <ChartCanvas type="bar" {...buildIndTiragemConfig(ind.data.tiragem, ind.labels)} />
            </ChartCard>
          </div>

          <div className="dashboard-row" style={{ marginTop: 12, gridTemplateColumns: "1fr" }}>
            <ChartCard title='Velocidade Média Produzindo (com acerto)"' subtitle="real vs meta por semana (virando + acerto + improdutivos área e gerenciais)">
              <ChartCanvas
                type="bar"
                {...buildIndVelocAcertoConfig(ind.data.velocAcerto, ind.ano, "semana", (s) => "S" + s, ind.data.metas)}
              />
            </ChartCard>
          </div>

          <div className="dashboard-row" style={{ marginTop: 12, gridTemplateColumns: "1fr" }}>
            <ChartCard title="Tempo Médio de Acerto × Meta por Semana" subtitle="minutos por acerto: real vs meta (por semana)">
              <ChartCanvas type="bar" {...buildIndAcertoSemanaConfig(ind.data.acerto, ind.labels, ind.data.metas)} />
            </ChartCard>
          </div>

          <div className="dashboard-row" style={{ marginTop: 12, gridTemplateColumns: "1fr" }}>
            <ChartCard title="Velocidade Média Virando por Semana" subtitle="peças/hora real vs meta">
              <ChartCanvas type="bar" {...buildIndVelocVirandoConfig(ind.data.velocVirando, ind.labels, ind.data.metas)} />
            </ChartCard>
          </div>

          <div className="dashboard-row" style={{ marginTop: 12 }}>
            <ChartCard title="Índice de improdutivos área" subtitle="% sobre virando + improdutivo área, real vs meta">
              <ChartCanvas type="bar" {...buildIndImprodutivosConfig(ind.data.improdutivos, ind.labels, ind.data.metas)} />
            </ChartCard>
            <ChartCard title="Pareto de Improdutivos — Operacional" subtitle="top motivos de parada (última semana do período, escopo área)">
              <ChartCanvas type="bar" {...buildParetoAreaConfig(ind.data.paretoArea)} />
            </ChartCard>
          </div>

          <div className="dashboard-row" style={{ marginTop: 12 }}>
            <ChartCard title="Índice de Improdutivos Gerencial" subtitle="% sobre virando + acerto + improdutivos, real vs meta">
              <ChartCanvas type="bar" {...buildIndDisponibilidadeConfig(ind.data.improdutivos, ind.labels, ind.data.metas)} />
            </ChartCard>
            <ChartCard title="Pareto de Improdutivos — Gerencial" subtitle="top motivos de parada (última semana do período, escopo gerencial)">
              <ChartCanvas type="bar" {...buildParetoGerencialConfig(ind.data.paretoGerencial)} />
            </ChartCard>
          </div>
        </>
      )}
    </div>
  );
}
