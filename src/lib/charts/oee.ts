import { chartTheme, type ChartData, type ChartOptions } from "../chartSetup";
import type { OeePorSemanaRow, ParetoRow, PorEquipamentoRow, ProducaoTipoRow } from "../../types/dashboard";

export function buildOeeEvolucaoConfig(rows: OeePorSemanaRow[]): { data: ChartData; options: ChartOptions } {
  const labels = rows.map((r) => "Semana " + r.semana);
  const disp = rows.map((r) => Number(r.disp_operacional || 0));
  const desemp = rows.map((r) => Number(r.desempenho || 0));
  const oee = rows.map((r) => Number(r.oee_operacional || 0));
  const th = chartTheme();
  return {
    data: {
      labels,
      datasets: [
        { label: "Disponibilidade Oper. (%)", data: disp, backgroundColor: "rgba(201,154,46,0.75)", borderWidth: 0 },
        { label: "Desempenho (%)", data: desemp, backgroundColor: "rgba(139,106,29,0.75)", borderWidth: 0 },
        {
          label: "OEE Operacional (%)",
          data: oee,
          type: "line",
          borderColor: "#e74c3c",
          backgroundColor: "rgba(231,76,60,0.15)",
          tension: 0.3,
          pointRadius: 5,
          borderWidth: 2,
          yAxisID: "y",
        },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      interaction: { mode: "index", intersect: false },
      plugins: { legend: { labels: { color: th.text } } },
      scales: {
        x: { ticks: { color: th.text }, grid: { color: th.grid } },
        y: {
          min: 0,
          suggestedMax: 100,
          ticks: { color: th.text, callback: (v) => v + "%" },
          grid: { color: th.grid },
          title: { display: true, text: "%", color: th.text },
        },
      },
    },
  };
}

export function buildVelocidadeConfig(rows: PorEquipamentoRow[]): { data: ChartData; options: ChartOptions } {
  const data = rows.filter((r) => Number(r.vel_media_virando || 0) > 0 || Number(r.meta_velocidade || 0) > 0);
  const labels = data.map((r) => r.equipamento || "");
  const real = data.map((r) => Number(r.vel_media_virando || 0));
  const meta = data.map((r) => Number(r.meta_velocidade || 0));
  const th = chartTheme();
  return {
    data: {
      labels,
      datasets: [
        { label: "Velocidade Real (peç/h)", data: real, backgroundColor: "rgba(201,154,46,0.8)" },
        { label: "Meta 2026 (peç/h)", data: meta, backgroundColor: "rgba(192,57,43,0.5)", borderColor: "#c0392b", borderWidth: 1 },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: { legend: { labels: { color: th.text } } },
      scales: {
        x: { ticks: { color: th.text }, grid: { color: th.grid } },
        y: { ticks: { color: th.text }, grid: { color: th.grid }, title: { display: true, text: "Peças/hora", color: th.text } },
      },
    },
  };
}

export function buildParetoConfig(rows: ParetoRow[]): { data: ChartData; options: ChartOptions } {
  const labels = rows.map((r) => r.classificacao_perda || "");
  const horas = rows.map((r) => Number(r.horas_parado || 0));
  const acum = rows.map((r) => Number(r.pct_acumulado || 0));
  const th = chartTheme();
  const palette = ["#c99a2e", "#8b6a1d", "#e9a826", "#d9b14a", "#a37e22", "#c0392b", "#6b6b6b", "#4caf50", "#3498db", "#9b59b6"];
  return {
    data: {
      labels,
      datasets: [
        { label: "Horas paradas", data: horas, backgroundColor: labels.map((_, i) => palette[i % palette.length]), yAxisID: "y", type: "bar" },
        {
          label: "% acumulado",
          data: acum,
          type: "line",
          borderColor: "#e74c3c",
          backgroundColor: "rgba(231,76,60,0.1)",
          tension: 0.2,
          pointRadius: 4,
          borderWidth: 2,
          yAxisID: "y1",
        },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      interaction: { mode: "index", intersect: false },
      plugins: { legend: { labels: { color: th.text } } },
      scales: {
        x: { ticks: { color: th.text, maxRotation: 35 }, grid: { color: th.grid } },
        y: { position: "left", ticks: { color: th.text }, grid: { color: th.grid }, title: { display: true, text: "Horas", color: th.text } },
        y1: { position: "right", ticks: { color: th.text, callback: (v) => v + "%" }, grid: { drawOnChartArea: false }, min: 0, max: 100 },
      },
    },
  };
}

export function buildTipoConfig(rows: ProducaoTipoRow[]): { data: ChartData; options: ChartOptions } {
  const data = rows.filter((r) => Number(r.qtd_produzida || 0) > 0).slice(0, 10);
  const labels = data.map((r) => (r.tipo_acabamento && r.tipo_acabamento !== "Sem Tipo" ? r.tipo_acabamento : null) || r.equipamento_plan || "Outros");
  const vals = data.map((r) => Number(r.qtd_produzida || 0));
  const th = chartTheme();
  return {
    data: {
      labels,
      datasets: [{ label: "Peças produzidas", data: vals, backgroundColor: "rgba(201,154,46,0.75)", borderWidth: 0 }],
    },
    options: {
      indexAxis: "y",
      responsive: true,
      maintainAspectRatio: false,
      plugins: { legend: { display: false } },
      scales: {
        x: { ticks: { color: th.text }, grid: { color: th.grid } },
        y: { ticks: { color: th.text, font: { size: 11 } }, grid: { color: th.grid } },
      },
    },
  };
}
