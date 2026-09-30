import { useEffect, useRef } from "react";
import { Chart } from "../lib/chartSetup";

// "Modo exibição" (TV do chão de fábrica): ao entrar em fullscreen num card,
// aumenta fonte/linha/ponto globalmente e recarrega a tela visível a cada
// 5 minutos enquanto durar.
export function useModoExibicao(reloadVisible: () => void) {
  const backupRef = useRef<{ font: number; line: number; point: number } | null>(null);
  const reloadRef = useRef(reloadVisible);
  reloadRef.current = reloadVisible;

  useEffect(() => {
    let refreshTimer: ReturnType<typeof setInterval> | null = null;

    function onFullscreenChange() {
      const ativo = !!document.fullscreenElement;
      if (ativo) {
        if (!backupRef.current) {
          backupRef.current = {
            font: Chart.defaults.font.size as number,
            line: Chart.defaults.elements.line.borderWidth as number,
            point: Chart.defaults.elements.point.radius as number,
          };
          Chart.defaults.font.size = 18;
          // Chart.js types these as scriptable options; plain numbers are valid at runtime.
          (Chart.defaults.elements.line as { borderWidth: number }).borderWidth = 4;
          (Chart.defaults.elements.point as { radius: number }).radius = 6;
        }
      } else if (backupRef.current) {
        Chart.defaults.font.size = backupRef.current.font;
        (Chart.defaults.elements.line as { borderWidth: number }).borderWidth = backupRef.current.line;
        (Chart.defaults.elements.point as { radius: number }).radius = backupRef.current.point;
        backupRef.current = null;
      }
      window.dispatchEvent(new CustomEvent("modo-exibicao-toggle"));

      if (refreshTimer) clearInterval(refreshTimer);
      refreshTimer = ativo ? setInterval(() => reloadRef.current(), 5 * 60 * 1000) : null;
    }

    document.addEventListener("fullscreenchange", onFullscreenChange);
    return () => {
      document.removeEventListener("fullscreenchange", onFullscreenChange);
      if (refreshTimer) clearInterval(refreshTimer);
    };
  }, []);
}
