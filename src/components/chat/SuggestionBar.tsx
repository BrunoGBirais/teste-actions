import { Users, Factory, OctagonAlert, TrendingUp, Recycle, ClipboardList } from "lucide-react";

const SUGGESTIONS = [
  { icon: Users, prompt: "Análise de produtividade dos operadores nos últimos 12 meses", label: "Produtividade dos operadores" },
  { icon: Factory, prompt: "Análise de desempenho de todas as máquinas nos últimos 12 meses", label: "Desempenho das máquinas" },
  { icon: OctagonAlert, prompt: "Principais motivos de parada nos últimos 12 meses", label: "Motivos de parada" },
  { icon: TrendingUp, prompt: "Produção diária dos últimos 12 meses", label: "Produção diária" },
  { icon: Recycle, prompt: "Percentual de refugo por setor", label: "Refugo por setor" },
  { icon: ClipboardList, prompt: "Últimas 10 ordens de serviço cadastradas", label: "Últimas OS" },
];

interface SuggestionBarProps {
  disabled: boolean;
  onSelect: (prompt: string) => void;
}

export function SuggestionBar({ disabled, onSelect }: SuggestionBarProps) {
  return (
    <div className="suggestion-bar" aria-label="Sugestões de perguntas">
      {SUGGESTIONS.map(({ icon: Icon, prompt, label }) => (
        <button
          key={prompt}
          type="button"
          className="suggestion-chip"
          disabled={disabled}
          onClick={() => onSelect(prompt)}
        >
          <Icon /> {label}
        </button>
      ))}
    </div>
  );
}
