import { useRef } from "react";
import { CalendarClock, CheckCircle, Database, FileUp, Layers, Ruler, Upload } from "lucide-react";
import { useUploadSnapshot, type DatasetKey } from "../../hooks/useUploadSnapshot";

const CARDS: { key: DatasetKey; icon: typeof CalendarClock; label: string; sub: string }[] = [
  { key: "apontamentos", icon: CalendarClock, label: "Apontamentos Máquinas", sub: "Apontamentos 2025 e 2026.csv" },
  { key: "acabamento", icon: Layers, label: "Tipo Acabamento", sub: "Tipo Acabamento - MM.csv" },
  { key: "facas", icon: Ruler, label: "Metros Lineares / Facas", sub: "Levantamento Metros Lineares.csv" },
];

export function UploadSnapshotSection() {
  const up = useUploadSnapshot();
  const inputRefs = useRef<Record<DatasetKey, HTMLInputElement | null>>({ apontamentos: null, acabamento: null, facas: null });

  return (
    <div className="upload-section">
      <div className="upload-header">
        <h2>
          <Upload /> Importar Snapshot
        </h2>
        <p>Selecione as três planilhas exportadas do sistema. Os dados anteriores serão substituídos.</p>
      </div>
      <div className="upload-grid">
        {CARDS.map(({ key, icon: Icon, label, sub }) => {
          const file = up.files[key];
          return (
            <div className={`upload-card${file ? " has-file" : ""}`} key={key}>
              <div className="upload-icon">
                <Icon />
              </div>
              <div className="upload-label">{label}</div>
              <div className="upload-sub">{sub}</div>
              <label className="upload-btn">
                <FileUp /> Escolher arquivo
                <input
                  type="file"
                  accept=".csv,.txt"
                  style={{ display: "none" }}
                  ref={(el) => {
                    inputRefs.current[key] = el;
                  }}
                  onChange={(e) => up.setFile(key, e.target.files?.[0] || null)}
                />
              </label>
              <div className="upload-filename">{file ? file.name : "Nenhum arquivo"}</div>
              {file && (
                <div className="upload-ok">
                  <CheckCircle />
                </div>
              )}
            </div>
          );
        })}
      </div>
      <div className="upload-actions">
        <button type="button" id="btnUploadSnapshot" className="upload-send-btn" disabled={!up.hasAnyFile || up.running} onClick={up.run}>
          <Database /> Enviar Snapshot
        </button>
        {up.running || up.progress.pct > 0 ? (
          <div className="upload-progress-wrap">
            <div className="upload-progress-bar">
              <div style={{ width: `${up.progress.pct}%` }} />
            </div>
            <div className="upload-progress-label">{up.progress.label}</div>
          </div>
        ) : null}
      </div>
      <div className="upload-log">
        {up.log.map((l, i) => (
          <div className={l.kind === "ok" ? "log-ok" : l.kind === "err" ? "log-err" : undefined} key={i}>
            {l.text}
          </div>
        ))}
      </div>
    </div>
  );
}
