// chart.js/auto registers every controller/element/plugin, matching the
// legacy <script src="chart.umd.min.js"> behavior (no manual tree-shaking).
import { Chart } from "chart.js/auto";
import type { ChartData, ChartOptions, ChartType } from "chart.js";

export { Chart };
export type { ChartData, ChartOptions, ChartType };

export interface ChartTheme {
  grid: string;
  text: string;
}

export function chartTheme(): ChartTheme {
  const isDark = document.documentElement.getAttribute("data-theme") === "dark";
  return {
    grid: isDark ? "rgba(255,255,255,0.08)" : "rgba(0,0,0,0.06)",
    text: isDark ? "#d8cfaf" : "#444",
  };
}

// Metas fixas: mesmo valor repetido em todos os pontos da série. Retorna
// null quando a meta não está cadastrada, para o gráfico omitir a linha.
export function metaFixaSerie(
  valor: number | null | undefined,
  n: number,
): (number | null)[] | null {
  const v = Number(valor);
  return valor === null || valor === undefined || !isFinite(v) ? null : Array(n).fill(v);
}

export function datasetMetaFixa(
  label: string,
  serie: (number | null)[],
  cor = "#2563eb",
) {
  return {
    label,
    data: serie,
    type: "line" as const,
    borderColor: cor,
    backgroundColor: "transparent",
    borderWidth: 2,
    pointRadius: 0,
    borderDash: [6, 4],
    spanGaps: true,
    yAxisID: "y",
  };
}
