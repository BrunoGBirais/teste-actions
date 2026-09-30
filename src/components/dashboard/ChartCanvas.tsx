import { useEffect, useRef } from "react";
import { Chart, type ChartData, type ChartOptions, type ChartType } from "../../lib/chartSetup";

export interface ChartCanvasProps {
  type: ChartType;
  data: ChartData;
  options?: ChartOptions;
}

// Generic Chart.js mount point: destroys and recreates the instance whenever
// the config changes, mirroring the legacy destroy-then-`new Chart()` pattern.
export function ChartCanvas({ type, data, options }: ChartCanvasProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const chartRef = useRef<Chart | null>(null);

  useEffect(() => {
    if (!canvasRef.current) return;
    chartRef.current = new Chart(canvasRef.current, { type, data, options });
    return () => {
      chartRef.current?.destroy();
      chartRef.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [type, data, options]);

  useEffect(() => {
    function onModoExibicaoToggle() {
      chartRef.current?.resize();
      chartRef.current?.update();
    }
    window.addEventListener("modo-exibicao-toggle", onModoExibicaoToggle);
    return () => window.removeEventListener("modo-exibicao-toggle", onModoExibicaoToggle);
  }, []);

  return <canvas ref={canvasRef} />;
}
