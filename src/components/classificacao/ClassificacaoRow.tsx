import { useState } from "react";
import { CLASSIF_ATUACAO_OPCOES, CLASSIF_NIVEL_OPCOES, CLASSIF_PERDA_OPCOES } from "../../hooks/useClassificacoes";
import type { Classificacao } from "../../types/admin";

interface ClassificacaoRowProps {
  item: Classificacao;
  onSave: (item: Classificacao, changes: Pick<Classificacao, "classificacao_perda" | "atuacao" | "nivel_atuacao">) => Promise<void>;
  onDelete: (item: Classificacao) => Promise<void>;
}

export function ClassificacaoRow({ item, onSave, onDelete }: ClassificacaoRowProps) {
  const [editing, setEditing] = useState(false);
  const [saving, setSaving] = useState(false);
  const [perda, setPerda] = useState(item.classificacao_perda);
  const [atuacao, setAtuacao] = useState(item.atuacao);
  const [nivel, setNivel] = useState(item.nivel_atuacao || "");

  const semUso = Number(item.qtd_apontamentos || 0) === 0;

  async function handleSave() {
    setSaving(true);
    try {
      await onSave(item, { classificacao_perda: perda, atuacao, nivel_atuacao: nivel || null });
      setEditing(false);
    } finally {
      setSaving(false);
    }
  }

  return (
    <tr>
      <td title={item.chave_duplicada ? `Outra classificação normaliza para a mesma chave ("${item.chave}"). Na base, vence a de menor id.` : undefined}>
        {item.tipo_apontam || "—"}
        {item.chave_duplicada && <span style={{ color: "var(--color-danger, #dc2626)" }}> ⚠</span>}
      </td>
      <td>{item.motivo || "—"}</td>
      {editing ? (
        <>
          <td>
            <select className="form-control" value={perda} onChange={(e) => setPerda(e.target.value)}>
              {CLASSIF_PERDA_OPCOES.map((o) => (
                <option key={o} value={o}>
                  {o}
                </option>
              ))}
            </select>
          </td>
          <td>
            <select className="form-control" value={atuacao} onChange={(e) => setAtuacao(e.target.value)}>
              {CLASSIF_ATUACAO_OPCOES.map((o) => (
                <option key={o} value={o}>
                  {o}
                </option>
              ))}
            </select>
          </td>
          <td>
            <select className="form-control" value={nivel} onChange={(e) => setNivel(e.target.value)}>
              <option value="">—</option>
              {CLASSIF_NIVEL_OPCOES.map((o) => (
                <option key={o} value={o}>
                  {o}
                </option>
              ))}
            </select>
          </td>
        </>
      ) : (
        <>
          <td>{item.classificacao_perda}</td>
          <td>{item.atuacao}</td>
          <td>{item.nivel_atuacao || "—"}</td>
        </>
      )}
      <td style={{ textAlign: "right", color: semUso ? "var(--text-muted)" : undefined, fontStyle: semUso ? "italic" : undefined }}>
        {Number(item.qtd_apontamentos || 0).toLocaleString("pt-BR")}
      </td>
      <td>
        {editing ? (
          <>
            <button type="button" className="btn btn-save" disabled={saving} onClick={handleSave}>
              Salvar
            </button>
            <button type="button" className="btn btn-action" disabled={saving} onClick={() => setEditing(false)}>
              Cancelar
            </button>
          </>
        ) : (
          <>
            <button type="button" className="btn btn-action" onClick={() => setEditing(true)}>
              Editar
            </button>
            {semUso && (
              <button type="button" className="btn btn-danger" onClick={() => onDelete(item)}>
                Excluir
              </button>
            )}
          </>
        )}
      </td>
    </tr>
  );
}
