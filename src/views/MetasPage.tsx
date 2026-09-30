"use client";

import { useMetasMaquinas } from "../hooks/useMetasMaquinas";
import { METAS_MAQ_CAMPOS } from "../hooks/useMetasMaquinas";
import { MetasMaquinasRow } from "../components/metas/MetasMaquinasRow";
import { Target } from "lucide-react";

export function MetasPage() {
  const { metas, loading, error, save } = useMetasMaquinas();

  return (
    <section className="dashboard-area" style={{ background: "var(--bg-body)" }}>
      <div className="dashboard-toolbar">
        <div className="dashboard-title">
          <Target />
          <span>Metas de Equipamentos</span>
        </div>
      </div>
      <div className="dashboard-scroll" style={{ padding: 24 }}>
        <div className="chart-card">
          <h3>Metas Fixas dos Gráficos de Indicadores</h3>
          <p style={{ color: "var(--text-muted)", fontSize: 14, marginBottom: 24 }}>
            Valores fixos por máquina usados nas linhas pontilhadas. Quando mais de uma máquina está no filtro, o
            gráfico usa a média simples.
          </p>
          <div className="table-responsive">
            <table className="data-table">
              <thead>
                <tr>
                  <th>Máquina</th>
                  {METAS_MAQ_CAMPOS.map((c) => (
                    <th key={c.key}>{c.label}</th>
                  ))}
                  <th style={{ width: 160 }}>Ações</th>
                </tr>
              </thead>
              <tbody>
                {loading ? (
                  <tr>
                    <td colSpan={7} style={{ textAlign: "center" }}>
                      Carregando...
                    </td>
                  </tr>
                ) : error ? (
                  <tr>
                    <td colSpan={7} style={{ textAlign: "center", color: "var(--color-danger)" }}>
                      {error}
                    </td>
                  </tr>
                ) : metas.length === 0 ? (
                  <tr>
                    <td colSpan={7} style={{ textAlign: "center" }}>
                      Nenhuma máquina encontrada.
                    </td>
                  </tr>
                ) : (
                  metas.map((item) => <MetasMaquinasRow key={item.nome_maquina} item={item} onSave={save} />)
                )}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </section>
  );
}
