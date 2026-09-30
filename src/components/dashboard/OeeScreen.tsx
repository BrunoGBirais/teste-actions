import { useEffect } from "react";
import { useOeeDashboard } from "../../hooks/useOeeDashboard";
import { ChartCard } from "./ChartCard";
import { ChartCanvas } from "./ChartCanvas";
import { buildOeeEvolucaoConfig, buildParetoConfig, buildTipoConfig, buildVelocidadeConfig } from "../../lib/charts/oee";
import { fmtInt, fmtPct } from "../../lib/format";

export function OeeScreen() {
  const { data, loading, error, reload } = useOeeDashboard();

  useEffect(() => {
    window.addEventListener("dashboard-auto-refresh", reload);
    return () => window.removeEventListener("dashboard-auto-refresh", reload);
  }, [reload]);

  if (loading && !data) return <div style={{ padding: 24 }}>Carregando…</div>;
  if (error) return <div style={{ padding: 24, color: "#c0392b" }}>Erro ao carregar OEE: {error}</div>;
  if (!data) return null;

  const { kpis, porSemana, pareto, tipo, porEquipamento } = data;
  const oeeVal = Number(kpis.oee_operacional || 0);
  const oeeColor = oeeVal >= 85 ? "#4caf50" : oeeVal >= 65 ? "#c99a2e" : "#e74c3c";

  const evolucao = buildOeeEvolucaoConfig(porSemana);
  const velocidade = buildVelocidadeConfig(porEquipamento);
  const paretoCfg = buildParetoConfig(pareto);
  const tipoCfg = buildTipoConfig(tipo);

  return (
    <div>
      <div className="kpi-grid" id="kpiGrid">
        <div className="kpi-card">
          <div className="kpi-label">OEE Operacional</div>
          <div className="kpi-value" style={{ color: oeeColor }}>
            {fmtPct(oeeVal)}
          </div>
          <div className="kpi-sub">{fmtInt(Math.round(Number(kpis.qtd_produzido || 0)))} peças virando</div>
        </div>
        <div className="kpi-card">
          <div className="kpi-label">Disponibilidade Oper.</div>
          <div className="kpi-value">{fmtPct(kpis.disp_operacional)}</div>
          <div className="kpi-sub">{fmtInt(Math.round(Number(kpis.min_virando || 0) / 60))}h virando</div>
        </div>
        <div className="kpi-card">
          <div className="kpi-label">Desempenho</div>
          <div className="kpi-value">{fmtPct(kpis.desempenho)}</div>
          <div className="kpi-sub">{fmtInt(Number(kpis.vel_media_virando || 0))} peças/h real</div>
        </div>
        <div className="kpi-card">
          <div className="kpi-label">Vel. Média Virando</div>
          <div className="kpi-value">{fmtInt(Number(kpis.vel_media_virando || 0))}</div>
          <div className="kpi-sub">peças / hora</div>
        </div>
        <div className="kpi-card kpi-warn">
          <div className="kpi-label">Tempo Médio de Acerto</div>
          <div className="kpi-value">{Number(kpis.tempo_medio_acerto_h || 0).toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}h</div>
          <div className="kpi-sub">horas / setup</div>
        </div>
        <div className="kpi-card kpi-warn">
          <div className="kpi-label">Índice de Improdutivos</div>
          <div className="kpi-value">{fmtPct(kpis.indice_improdutivos)}</div>
          <div className="kpi-sub">{fmtInt(Math.round(Number(kpis.min_acerto || 0) / 60))}h acerto + paradas</div>
        </div>
      </div>

      <div className="dashboard-row">
        <ChartCard title="Evolução do OEE" subtitle="disponibilidade operacional e desempenho (%)" wide>
          <ChartCanvas type="bar" data={evolucao.data} options={evolucao.options} />
        </ChartCard>
        <ChartCard title="Velocidade × Meta" subtitle="peças/hora virando vs capacidade">
          <ChartCanvas type="bar" data={velocidade.data} options={velocidade.options} />
        </ChartCard>
      </div>

      <div className="dashboard-row">
        <ChartCard title="Pareto de Improdutivos" subtitle="horas paradas por classificação (top 10)" wide>
          <ChartCanvas type="bar" data={paretoCfg.data} options={paretoCfg.options} />
        </ChartCard>
        <ChartCard title="Produção por Tipo" subtitle="peças por tipo de acabamento">
          <ChartCanvas type="bar" data={tipoCfg.data} options={tipoCfg.options} />
        </ChartCard>
      </div>

      <div className="dashboard-card">
        <div className="dashboard-card-header">
          <h3>Detalhes Semanais</h3>
          <span className="dashboard-card-sub">indicadores consolidados por semana</span>
        </div>
        <div className="dashboard-table-wrap">
          <table className="dashboard-table">
            <thead>
              <tr>
                <th>Semana</th>
                <th>OEE Oper. (%)</th>
                <th>Disp. Oper. (%)</th>
                <th>Desempenho (%)</th>
                <th>Vel. Real (pç/h)</th>
                <th>Acerto Médio (h)</th>
                <th>Improdutivos (%)</th>
              </tr>
            </thead>
            <tbody>
              {porSemana.length === 0 ? (
                <tr>
                  <td colSpan={7} className="dashboard-empty">
                    Sem dados
                  </td>
                </tr>
              ) : (
                porSemana.map((r, i) => (
                  <tr key={i}>
                    <td>
                      <strong>Semana {r.semana}</strong>
                    </td>
                    <td>{fmtPct(r.oee_operacional)}</td>
                    <td>{fmtPct(r.disp_operacional)}</td>
                    <td>{fmtPct(r.desempenho)}</td>
                    <td>{fmtInt(Number(r.vel_media_virando || 0))}</td>
                    <td>{Number(r.tempo_medio_acerto_h || 0).toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</td>
                    <td>{fmtPct(r.indice_improdutivos)}</td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
