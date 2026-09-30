import type { ClassificacaoOrfa } from "../../types/admin";

interface ClassifOrfaRowProps {
  item: ClassificacaoOrfa;
  onClassify: (prefill: { tipo: string; motivo: string }) => void;
}

export function ClassifOrfaRow({ item, onClassify }: ClassifOrfaRowProps) {
  const multiplasAreas = (item.areas || "").includes(",");
  return (
    <tr>
      <td>{item.tipo_apontam}</td>
      <td>{item.motivo || "(sem motivo)"}</td>
      <td
        style={multiplasAreas ? { color: "var(--color-danger, #dc2626)" } : undefined}
        title={multiplasAreas ? "Este motivo aparece em mais de uma área. A classificação vale para todas." : undefined}
      >
        {item.areas || "—"}
      </td>
      <td style={{ fontSize: "0.8rem", color: "var(--text-muted)" }}>{item.maquinas || "—"}</td>
      <td>{Number(item.qtd_apontamentos || 0).toLocaleString("pt-BR")}</td>
      <td>{Number(item.horas || 0).toLocaleString("pt-BR", { maximumFractionDigits: 1 })}</td>
      <td>
        <button
          type="button"
          className="btn btn-action"
          onClick={() => onClassify({ tipo: item.tipo_apontam, motivo: item.motivo || "" })}
        >
          Classificar
        </button>
      </td>
    </tr>
  );
}
