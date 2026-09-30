import { useRef, type ReactNode } from "react";

interface ChartCardProps {
  title: string;
  subtitle: string;
  wide?: boolean;
  children: ReactNode;
}

// Duplo clique abre o card em tela cheia ("modo exibição" para TVs de chão de
// fábrica) — a mudança de tamanho de fonte/linha é global e tratada pelo hook
// useModoExibicao no nível da página.
export function ChartCard({ title, subtitle, wide, children }: ChartCardProps) {
  const cardRef = useRef<HTMLDivElement>(null);

  function handleDoubleClick() {
    if (document.fullscreenElement) return;
    const el = cardRef.current;
    if (!el) return;
    el.requestFullscreen?.().catch((err) => console.warn("Modo exibição indisponível:", err));
  }

  return (
    <div className={`dashboard-card${wide ? " dashboard-card-wide" : ""}`} ref={cardRef} onDoubleClick={handleDoubleClick}>
      <div className="dashboard-card-header">
        <h3>{title}</h3>
        <span className="dashboard-card-sub">{subtitle}</span>
      </div>
      <div className="chart-wrap">{children}</div>
    </div>
  );
}
