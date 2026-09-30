import { useState } from "react";
import { METAS_MAQ_CAMPOS } from "../../hooks/useMetasMaquinas";
import type { MetaMaquina } from "../../types/admin";

function fmtMetaCell(v: number | null | undefined): string {
  return v === null || v === undefined ? "—" : Number(v).toLocaleString("pt-BR");
}

interface MetasMaquinasRowProps {
  item: MetaMaquina;
  onSave: (payload: Record<string, unknown>) => Promise<void>;
}

export function MetasMaquinasRow({ item, onSave }: MetasMaquinasRowProps) {
  const [editing, setEditing] = useState(false);
  const [saving, setSaving] = useState(false);
  const [values, setValues] = useState<Record<string, string>>(() =>
    Object.fromEntries(METAS_MAQ_CAMPOS.map((c) => [c.key, item[c.key] != null ? String(item[c.key]) : ""])),
  );

  async function handleSave() {
    setSaving(true);
    const payload: Record<string, unknown> = { p_nome_maquina: item.nome_maquina };
    METAS_MAQ_CAMPOS.forEach((c) => {
      const raw = (values[c.key] || "").trim();
      payload["p_" + c.key] = raw === "" ? null : Number(raw);
    });
    try {
      await onSave(payload);
    } finally {
      setSaving(false);
      setEditing(false);
    }
  }

  if (!editing) {
    return (
      <tr>
        <td>{item.nome_maquina}</td>
        {METAS_MAQ_CAMPOS.map((c) => (
          <td key={c.key}>{fmtMetaCell(item[c.key])}</td>
        ))}
        <td>
          <button type="button" className="btn btn-action" onClick={() => setEditing(true)}>
            Editar
          </button>
        </td>
      </tr>
    );
  }

  return (
    <tr>
      <td>{item.nome_maquina}</td>
      {METAS_MAQ_CAMPOS.map((c) => (
        <td key={c.key}>
          <input
            type="number"
            step={c.step}
            min="0"
            className="form-control"
            style={{ width: 120, padding: 4 }}
            value={values[c.key]}
            onChange={(e) => setValues((prev) => ({ ...prev, [c.key]: e.target.value }))}
          />
        </td>
      ))}
      <td>
        <button type="button" className="btn btn-save" disabled={saving} onClick={handleSave}>
          Salvar
        </button>
        <button type="button" className="btn btn-action" disabled={saving} onClick={() => setEditing(false)}>
          Cancelar
        </button>
      </td>
    </tr>
  );
}
