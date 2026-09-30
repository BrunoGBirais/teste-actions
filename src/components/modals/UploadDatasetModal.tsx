import { useState } from "react";
import { Upload, UploadCloud, X } from "lucide-react";
import { uploadDataset } from "../../services/n8n";

interface UploadDatasetModalProps {
  open: boolean;
  onClose: () => void;
}

export function UploadDatasetModal({ open, onClose }: UploadDatasetModalProps) {
  const [dataset, setDataset] = useState("");
  const [file, setFile] = useState<File | null>(null);
  const [status, setStatus] = useState<{ text: string; kind?: "error" | "success" }>({ text: "" });
  const [submitting, setSubmitting] = useState(false);

  function reset() {
    setDataset("");
    setFile(null);
    setStatus({ text: "" });
  }

  async function handleSubmit() {
    if (!dataset) {
      setStatus({ text: "Selecione o dataset a atualizar.", kind: "error" });
      return;
    }
    if (!file) {
      setStatus({ text: "Selecione um arquivo (.xlsx ou .csv).", kind: "error" });
      return;
    }
    setSubmitting(true);
    setStatus({ text: "Enviando e processando..." });
    try {
      const j = await uploadDataset(dataset, file);
      const linhas = j.rows_imported != null ? ` (${j.rows_imported} linha(s))` : "";
      setStatus({ text: `✅ ${j.message || "Arquivo atualizado com sucesso."}${linhas}`, kind: "success" });
    } catch (err) {
      setStatus({ text: `❌ ${(err as Error).message || err}`, kind: "error" });
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div
      className={`confirm-modal-backdrop${open ? " active" : ""}`}
      onClick={(e) => {
        if (e.target === e.currentTarget) {
          onClose();
          reset();
        }
      }}
    >
      <div className="confirm-modal admin-modal">
        <div className="admin-modal-header">
          <h3 className="confirm-title" style={{ margin: 0 }}>
            <UploadCloud style={{ width: 18, height: 18, verticalAlign: -3, marginRight: 6 }} />
            Atualizar planilha de produção
          </h3>
          <button
            className="admin-close-btn"
            title="Fechar"
            onClick={() => {
              onClose();
              reset();
            }}
          >
            <X style={{ width: 18, height: 18 }} />
          </button>
        </div>
        <div style={{ padding: "16px 24px 8px", fontSize: 13, color: "var(--color-text-secondary)" }}>
          Substitui o arquivo correspondente no Storage e recarrega a tabela no banco. O cabeçalho da planilha é
          comparado de forma flexível — <b>o nome da aba e do arquivo não importam</b>.
        </div>
        <div style={{ padding: "0 24px 16px", display: "flex", flexDirection: "column", gap: 12 }}>
          <label style={{ fontSize: 13, fontWeight: 600 }}>
            Dataset a atualizar
            <select
              value={dataset}
              onChange={(e) => setDataset(e.target.value)}
              style={{
                display: "block",
                width: "100%",
                marginTop: 4,
                padding: 8,
                border: "1px solid var(--color-border)",
                borderRadius: 6,
                background: "var(--color-bg)",
                color: "var(--color-text)",
              }}
            >
              <option value="">— selecione —</option>
              <option value="ordens_servico">Ordens de Serviço (ordens_servico)</option>
              <option value="facas">Facas (facas)</option>
              <option value="apontamentos">Apontamentos de produção (apontamentos)</option>
            </select>
          </label>
          <label style={{ fontSize: 13, fontWeight: 600 }}>
            Arquivo (.xlsx ou .csv)
            <input
              type="file"
              accept=".xlsx,.xls,.csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,application/vnd.ms-excel,text/csv"
              style={{
                display: "block",
                width: "100%",
                marginTop: 4,
                padding: 8,
                border: "1px solid var(--color-border)",
                borderRadius: 6,
                background: "var(--color-bg)",
                color: "var(--color-text)",
              }}
              onChange={(e) => setFile(e.target.files?.[0] || null)}
            />
          </label>
          <div
            className="dashboard-status"
            style={{
              padding: 0,
              minHeight: 18,
              color: status.kind === "error" ? "var(--color-danger, #dc2626)" : status.kind === "success" ? "var(--color-success, #16a34a)" : "var(--color-text-secondary)",
            }}
          >
            {status.text}
          </div>
        </div>
        <div style={{ padding: "0 24px 20px", display: "flex", justifyContent: "flex-end", gap: 8 }}>
          <button
            type="button"
            className="btn-modal"
            onClick={() => {
              onClose();
              reset();
            }}
          >
            Cancelar
          </button>
          <button type="button" className="btn-modal btn-confirm" disabled={submitting} onClick={handleSubmit}>
            <Upload style={{ width: 14, height: 14, verticalAlign: -2, marginRight: 4 }} />
            Enviar e atualizar
          </button>
        </div>
      </div>
    </div>
  );
}
