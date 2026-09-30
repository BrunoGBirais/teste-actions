import { useEffect, useState } from "react";
import { X } from "lucide-react";
import { CLASSIF_ATUACAO_OPCOES, CLASSIF_NIVEL_OPCOES, CLASSIF_PERDA_OPCOES } from "../../hooks/useClassificacoes";

export interface ClassifPrefill {
  tipo: string;
  motivo: string;
}

interface ClassifFormModalProps {
  open: boolean;
  prefill: ClassifPrefill | null;
  onClose: () => void;
  onSubmit: (payload: {
    chave: string;
    tipo_apontam: string;
    motivo: string;
    classificacao_perda: string;
    atuacao: string;
    nivel_atuacao: string | null;
  }) => Promise<void>;
}

export function ClassifFormModal({ open, prefill, onClose, onSubmit }: ClassifFormModalProps) {
  const [tipo, setTipo] = useState("");
  const [motivo, setMotivo] = useState("");
  const [chave, setChave] = useState("");
  const [chaveEditada, setChaveEditada] = useState(false);
  const [perda, setPerda] = useState(CLASSIF_PERDA_OPCOES[0]);
  const [atuacao, setAtuacao] = useState(CLASSIF_ATUACAO_OPCOES[0]);
  const [nivel, setNivel] = useState("");
  const [error, setError] = useState("");
  const [saving, setSaving] = useState(false);

  const travado = !!prefill;

  useEffect(() => {
    if (!open) return;
    setTipo(prefill?.tipo ?? "");
    setMotivo(prefill?.motivo ?? "");
    setChave(prefill ? (prefill.tipo ?? "") + (prefill.motivo ?? "") : "");
    setChaveEditada(false);
    setPerda(CLASSIF_PERDA_OPCOES[0]);
    setAtuacao(CLASSIF_ATUACAO_OPCOES[0]);
    setNivel("");
    setError("");
  }, [open, prefill]);

  function handleTipoChange(v: string) {
    setTipo(v);
    if (!chaveEditada) setChave(v + motivo);
  }
  function handleMotivoChange(v: string) {
    setMotivo(v);
    if (!chaveEditada) setChave(tipo + v);
  }

  async function handleSubmit() {
    setSaving(true);
    setError("");
    try {
      await onSubmit({
        chave: chave.trim(),
        tipo_apontam: tipo.trim(),
        motivo: motivo.trim(),
        classificacao_perda: perda,
        atuacao,
        nivel_atuacao: nivel || null,
      });
      onClose();
    } catch (err) {
      setError((err as Error).message || "Erro ao criar classificação");
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className={`confirm-modal-backdrop${open ? " active" : ""}`} onClick={(e) => e.target === e.currentTarget && onClose()}>
      <div className="confirm-modal admin-form-modal">
        <div className="admin-modal-header">
          <h3 className="confirm-title" style={{ margin: 0 }}>
            Nova classificação
          </h3>
          <button className="admin-close-btn" title="Fechar" type="button" onClick={onClose}>
            <X style={{ width: 18, height: 18 }} />
          </button>
        </div>
        <form
          className="admin-form"
          onSubmit={(e) => {
            e.preventDefault();
            handleSubmit();
          }}
        >
          <label className="admin-form-label">
            Tipo de apontamento
            <input
              type="text"
              className="login-input"
              placeholder="Ex.: Ocioso"
              required
              readOnly={travado}
              style={travado ? { opacity: 0.7 } : undefined}
              value={tipo}
              onChange={(e) => handleTipoChange(e.target.value)}
            />
          </label>
          <label className="admin-form-label">
            Motivo
            <input
              type="text"
              className="login-input"
              placeholder="Deixe vazio se o tipo não tem motivo"
              readOnly={travado}
              style={travado ? { opacity: 0.7 } : undefined}
              value={motivo}
              onChange={(e) => handleMotivoChange(e.target.value)}
            />
          </label>
          <label className="admin-form-label">
            Chave
            <input
              type="text"
              className="login-input"
              placeholder="Tipo + motivo, exatamente como vem da planilha"
              required
              readOnly={travado}
              style={travado ? { opacity: 0.7 } : undefined}
              value={chave}
              onChange={(e) => {
                setChaveEditada(true);
                setChave(e.target.value);
              }}
            />
          </label>
          <label className="admin-form-label">
            Classificação de perda
            <select className="login-input" required value={perda} onChange={(e) => setPerda(e.target.value)}>
              {CLASSIF_PERDA_OPCOES.map((o) => (
                <option key={o} value={o}>
                  {o}
                </option>
              ))}
            </select>
          </label>
          <label className="admin-form-label">
            Atuação
            <select className="login-input" required value={atuacao} onChange={(e) => setAtuacao(e.target.value)}>
              {CLASSIF_ATUACAO_OPCOES.map((o) => (
                <option key={o} value={o}>
                  {o}
                </option>
              ))}
            </select>
          </label>
          <label className="admin-form-label">
            Nível de atuação
            <select className="login-input" value={nivel} onChange={(e) => setNivel(e.target.value)}>
              <option value="">—</option>
              {CLASSIF_NIVEL_OPCOES.map((o) => (
                <option key={o} value={o}>
                  {o}
                </option>
              ))}
            </select>
          </label>
          {error && <div className="err-msg" style={{ display: "block" }}>{error}</div>}
          <div className="confirm-actions">
            <button type="button" className="btn-modal btn-cancel" onClick={onClose}>
              Cancelar
            </button>
            <button type="submit" className="btn-modal btn-confirm" disabled={saving}>
              Salvar
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
