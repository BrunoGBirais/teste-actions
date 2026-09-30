import { chartTheme, datasetMetaFixa, metaFixaSerie, type ChartData, type ChartOptions } from "../chartSetup";
import type { IndSemanaRow, MetasFixas, ParetoRow } from "../../types/dashboard";

type BarLineConfig = { data: ChartData; options: ChartOptions };

// 1. Tempo médio de acerto × meta
export function buildIndAcertoSemanaConfig(rows: IndSemanaRow[], labels: string[], metas: MetasFixas): BarLineConfig {
  const qtd = rows.map((r) => Number(r.quantidade_acerto || 0));
  const acertoMin = rows.map((r, i) => (qtd[i] > 0 ? +((Number(r.acerto_hrs || 0) / qtd[i]) * 60).toFixed(1) : null));
  const metaVal = metas?.meta_tempo_medio_acerto ?? null;
  const metaAc = metaFixaSerie(metaVal, labels.length);
  const th = chartTheme();
  const barColors = acertoMin.map((v) => (metaAc !== null && v !== null && v > (metaVal as number) ? "rgba(231,76,60,0.82)" : "rgba(76,175,80,0.82)"));
  const datasets: ChartData["datasets"] = [{ label: "Tempo Médio (min)", data: acertoMin, backgroundColor: barColors, yAxisID: "y" }];
  if (metaAc) datasets.push(datasetMetaFixa("Meta (min)", metaAc));
  return {
    data: { labels, datasets },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      interaction: { mode: "index", intersect: false },
      plugins: {
        legend: { labels: { color: th.text } },
        tooltip: { callbacks: { label: (c) => ` ${c.dataset.label}: ${c.parsed.y !== null ? c.parsed.y.toFixed(1) + " min" : "—"}` } },
      },
      scales: {
        x: { ticks: { color: th.text }, grid: { color: th.grid } },
        y: {
          ticks: { color: th.text, callback: (v) => Number(v).toFixed(0) + "min" },
          grid: { color: th.grid },
          title: { display: true, text: "Minutos / acerto", color: th.text },
          beginAtZero: true,
        },
      },
    },
  };
}

// 2. Velocidade virando × meta
export function buildIndVelocVirandoConfig(rows: IndSemanaRow[], labels: string[], metas: MetasFixas): BarLineConfig {
  const real = rows.map((r) => {
    const h = Number(r.virando_hrs || 0);
    return h > 0 ? Math.round(Number(r.produzido_virando || 0) / h) : null;
  });
  const metaVal = metas?.meta_velocidade_virando ?? null;
  const meta = metaFixaSerie(metaVal, labels.length);
  const th = chartTheme();
  const barColors = real.map((v) => (meta !== null && v !== null && v < (metaVal as number) ? "rgba(231,76,60,0.82)" : "rgba(76,175,80,0.82)"));
  const datasets: ChartData["datasets"] = [{ label: "Vel. Real (peç/h)", data: real, backgroundColor: barColors, yAxisID: "y" }];
  if (meta) datasets.push(datasetMetaFixa("Meta (peç/h)", meta));
  return {
    data: { labels, datasets },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      interaction: { mode: "index", intersect: false },
      plugins: {
        legend: { labels: { color: th.text } },
        tooltip: { callbacks: { label: (c) => ` ${c.dataset.label}: ${c.parsed.y !== null ? c.parsed.y.toLocaleString("pt-BR") : "—"}` } },
      },
      scales: {
        x: { ticks: { color: th.text }, grid: { color: th.grid } },
        y: {
          ticks: { color: th.text, callback: (v) => Number(v).toLocaleString("pt-BR") },
          grid: { color: th.grid },
          title: { display: true, text: "Peças/hora", color: th.text },
          beginAtZero: true,
        },
      },
    },
  };
}

// 3. Improdutivos Área × meta
export function buildIndImprodutivosConfig(rows: IndSemanaRow[], labels: string[], metas: MetasFixas): BarLineConfig {
  const impPct = rows.map((r) => {
    const area = Number(r.horas_improdutivas_area || 0);
    const base = Number(r.virando_hrs || 0) + area;
    return base > 0 ? +((area / base) * 100).toFixed(2) : null;
  });
  const metaVal = metas?.meta_improdutivo_area_pct ?? null;
  const meta = metaFixaSerie(metaVal, labels.length);
  const th = chartTheme();
  const barColors = impPct.map((v) => (meta !== null && v !== null && v > (metaVal as number) ? "rgba(231,76,60,0.82)" : "rgba(76,175,80,0.82)"));
  const datasets: ChartData["datasets"] = [{ label: "Improd. Área (%)", data: impPct, backgroundColor: barColors, yAxisID: "y" }];
  if (meta) datasets.push(datasetMetaFixa("Meta (%)", meta, "#c99a2e"));
  return {
    data: { labels, datasets },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      interaction: { mode: "index", intersect: false },
      plugins: {
        legend: { labels: { color: th.text } },
        tooltip: { callbacks: { label: (c) => (c.parsed.y === null ? ` ${c.dataset.label}: —` : ` ${c.dataset.label}: ${c.parsed.y.toFixed(2)}%`) } },
      },
      scales: {
        x: { ticks: { color: th.text }, grid: { color: th.grid } },
        y: {
          ticks: { color: th.text, callback: (v) => Number(v).toFixed(1) + "%" },
          grid: { color: th.grid },
          title: { display: true, text: "% improdutivo área", color: th.text },
          beginAtZero: true,
        },
      },
    },
  };
}

// 4/5. Pareto (área / gerencial)
export function buildParetoAreaConfig(rows: ParetoRow[]): BarLineConfig {
  const data = rows.slice(0, 12);
  const labels = data.map((r) => r.apontamento || "");
  const horas = data.map((r) => Number(r.horas_improdutivas_area || 0));
  const th = chartTheme();
  return {
    data: { labels, datasets: [{ label: "Horas (Área)", data: horas, backgroundColor: "rgba(231,76,60,0.75)" }] },
    options: {
      indexAxis: "y",
      responsive: true,
      maintainAspectRatio: false,
      plugins: { legend: { display: false } },
      scales: {
        x: { ticks: { color: th.text, callback: (v) => Number(v).toFixed(1) + "h" }, grid: { color: th.grid } },
        y: { ticks: { color: th.text, font: { size: 11 } }, grid: { display: false } },
      },
    },
  };
}

export function buildParetoGerencialConfig(rows: ParetoRow[]): BarLineConfig {
  const data = rows.slice(0, 12);
  const labels = data.map((r) => r.apontamento || "");
  const horas = data.map((r) => Number(r.horas_improdutivas_gerencial || 0));
  const th = chartTheme();
  return {
    data: { labels, datasets: [{ label: "Horas (Gerencial)", data: horas, backgroundColor: "rgba(201,154,46,0.75)" }] },
    options: {
      indexAxis: "y",
      responsive: true,
      maintainAspectRatio: false,
      plugins: { legend: { display: false } },
      scales: {
        x: { ticks: { color: th.text, callback: (v) => Number(v).toFixed(1) + "h" }, grid: { color: th.grid } },
        y: { ticks: { color: th.text, font: { size: 11 } }, grid: { display: false } },
      },
    },
  };
}

// 6. Velocidade + acerto (ano corrente)
export function buildIndVelocAcertoConfig(
  rows: IndSemanaRow[],
  anoFiltro: number | null,
  periodoKey: "semana" | "mes",
  labelFn: (p: number) => string,
  metas: MetasFixas,
): BarLineConfig {
  const anoAtual = anoFiltro || new Date().getFullYear();
  const atual = rows.filter((r) => Number(r.ano) === anoAtual);
  const periodos = [...new Set(atual.map((r) => Number(r[periodoKey])))].sort((a, b) => a - b);
  const labels = periodos.map(labelFn);
  const getVel = (w: number) => {
    const r = atual.find((x) => Number(x[periodoKey]) === w);
    if (!r) return null;
    const h =
      Number(r.virando_hrs || 0) + Number(r.acerto_hrs || 0) + Number(r.horas_improdutivas_area || 0) + Number(r.horas_improdutivas_gerencial || 0);
    return h > 0 ? Math.round(Number(r.produzido_virando || 0) / h) : null;
  };
  const th = chartTheme();
  const dataAtual = periodos.map(getVel);
  const metaVal = metas?.meta_velocidade_com_acerto ?? null;
  const meta = metaFixaSerie(metaVal, labels.length);
  const barColors = dataAtual.map((v) => (meta !== null && v !== null && v < (metaVal as number) ? "rgba(231,76,60,0.82)" : "rgba(76,175,80,0.82)"));
  const datasets: ChartData["datasets"] = [{ label: anoAtual + " (peç/h)", data: dataAtual, backgroundColor: barColors, yAxisID: "y" }];
  if (meta) datasets.push(datasetMetaFixa("Meta (peç/h)", meta));
  return {
    data: { labels, datasets },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      interaction: { mode: "index", intersect: false },
      plugins: {
        legend: { labels: { color: th.text } },
        tooltip: { callbacks: { label: (c) => ` ${c.dataset.label}: ${c.parsed.y !== null ? c.parsed.y.toLocaleString("pt-BR") : "—"}` } },
      },
      scales: {
        x: { ticks: { color: th.text }, grid: { color: th.grid } },
        y: {
          ticks: { color: th.text, callback: (v) => Number(v).toLocaleString("pt-BR") },
          grid: { color: th.grid },
          title: { display: true, text: "Peças/hora", color: th.text },
          beginAtZero: true,
        },
      },
    },
  };
}

// 7. Quantidade de tiragem
export function buildIndTiragemConfig(rows: IndSemanaRow[], labels: string[]): BarLineConfig {
  const qtd = rows.map((r) => Number(r.produzido_total || 0));
  const ac = rows.map((r) => Number(r.quantidade_acerto || 0));
  const tiragem = qtd.map((q, i) => (ac[i] > 0 ? Math.round(q / ac[i]) : null));
  const th = chartTheme();
  return {
    data: {
      labels,
      datasets: [
        { label: "Peças Produzidas", data: qtd, backgroundColor: "rgba(201,154,46,0.75)", yAxisID: "y" },
        {
          label: "Tiragem Média (peç/acerto)",
          data: tiragem,
          type: "line",
          borderColor: "#4caf50",
          backgroundColor: "transparent",
          borderWidth: 2,
          pointRadius: 4,
          yAxisID: "y2",
        },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      interaction: { mode: "index", intersect: false },
      plugins: {
        legend: { labels: { color: th.text } },
        tooltip: { callbacks: { label: (c) => ` ${c.dataset.label}: ${c.parsed.y !== null ? c.parsed.y.toLocaleString("pt-BR") : "—"}` } },
      },
      scales: {
        x: { ticks: { color: th.text }, grid: { color: th.grid } },
        y: { ticks: { color: th.text }, grid: { color: th.grid }, title: { display: true, text: "Peças", color: th.text } },
        y2: {
          position: "right",
          ticks: { color: th.text, callback: (v) => Number(v).toLocaleString("pt-BR") },
          grid: { display: false },
          title: { display: true, text: "Peças / acerto", color: th.text },
        },
      },
    },
  };
}

// 8. Índice de improdutivos gerencial
export function buildIndDisponibilidadeConfig(rows: IndSemanaRow[], labels: string[], metas: MetasFixas): BarLineConfig {
  const th = chartTheme();
  const realPct = rows.map((r) => {
    const ger = Number(r.horas_improdutivas_gerencial || 0);
    const base = Number(r.virando_hrs || 0) + Number(r.acerto_hrs || 0) + Number(r.horas_improdutivas_area || 0) + ger;
    return base > 0 ? +((ger / base) * 100).toFixed(2) : null;
  });
  const metaVal = metas?.meta_improdutivo_gerencial_pct ?? null;
  const meta = metaFixaSerie(metaVal, labels.length);
  const barColors = realPct.map((v) => (meta !== null && v !== null && v > (metaVal as number) ? "rgba(231,76,60,0.82)" : "rgba(76,175,80,0.82)"));
  const datasets: ChartData["datasets"] = [{ label: "Improd. Gerencial (%)", data: realPct, backgroundColor: barColors, yAxisID: "y" }];
  if (meta) datasets.push(datasetMetaFixa("Meta (%)", meta));
  return {
    data: { labels, datasets },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      interaction: { mode: "index", intersect: false },
      plugins: {
        legend: { labels: { color: th.text } },
        tooltip: { callbacks: { label: (c) => ` ${c.dataset.label}: ${c.parsed.y !== null ? c.parsed.y.toFixed(1) + "%" : "—"}` } },
      },
      scales: {
        x: { ticks: { color: th.text }, grid: { color: th.grid } },
        y: {
          ticks: { color: th.text, callback: (v) => Number(v).toFixed(1) + "%" },
          grid: { color: th.grid },
          title: { display: true, text: "Improd. Gerencial (%)", color: th.text },
          beginAtZero: true,
        },
      },
    },
  };
}
