"use client";

import { useState } from "react";
import { ListChecks, Plus, RefreshCw } from "lucide-react";
import { useClassificacoes } from "../hooks/useClassificacoes";
import { ClassificacaoRow } from "../components/classificacao/ClassificacaoRow";
import { ClassifOrfaRow } from "../components/classificacao/ClassifOrfaRow";
import { ClassifFormModal, type ClassifPrefill } from "../components/modals/ClassifFormModal";

export function ClassificacaoPage() {
  const c = useClassificacoes();
  const [subTab, setSubTab] = useState<"cadastradas" | "orfas">("cadastradas");
  const [formOpen, setFormOpen] = useState(false);
  const [prefill, setPrefill] = useState<ClassifPrefill | null>(null);
  const [applying, setApplying] = useState(false);

  function openForm(pre: ClassifPrefill | null) {
    setPrefill(pre);
    setFormOpen(true);
  }

  async function handleDelete(item: Parameters<typeof c.deleteClassificacao>[0]) {
    const rotulo = [item.tipo_apontam, item.motivo].filter(Boolean).join(" / ");
    if (!confirm(`Excluir a classificação "${rotulo}"? Esta ação não pode ser desfeita.`)) return;
    await c.deleteClassificacao(item);
  }

  async function handleApply() {
    setApplying(true);
    try {
      await c.aplicarAosDashboards();
    } finally {
      setApplying(false);
    }
  }

  return (
    <section className="dashboard-area" style={{ background: "var(--bg-body)" }}>
      <div className="dashboard-toolbar">
        <div className="dashboard-title">
          <ListChecks />
          <span>Classificações de Apontamento</span>
        </div>
        <div style={{ display: "flex", gap: 8, alignItems: "center", marginLeft: "auto" }}>
          <input
            type="search"
            className="filter-select"
            placeholder="Buscar tipo, motivo..."
            style={{ minWidth: 220 }}
            value={c.busca}
            onChange={(e) => c.setBusca(e.target.value)}
          />
          <button type="button" className="toolbar-btn toolbar-btn-primary" onClick={() => openForm(null)}>
            <Plus /> Nova classificação
          </button>
          <button
            type="button"
            className={`toolbar-btn toolbar-btn-ghost${c.pendente ? " is-pending" : ""}${applying ? " is-loading" : ""}`}
            title="Recalcula a base dos dashboards"
            disabled={applying}
            onClick={handleApply}
          >
            <RefreshCw /> Aplicar aos dashboards
          </button>
        </div>
      </div>
      <div className="dashboard-scroll" style={{ padding: 24 }}>
        <div className="subtab-strip">
          <button
            type="button"
            className={`subtab-btn${subTab === "cadastradas" ? " is-active" : ""}`}
            onClick={() => setSubTab("cadastradas")}
          >
            Cadastradas
          </button>
          <button type="button" className={`subtab-btn${subTab === "orfas" ? " is-active" : ""}`} onClick={() => setSubTab("orfas")}>
            Órfãs
            {c.orfas.length > 0 && <span className="dashboard-badge warn">{c.orfas.length}</span>}
          </button>
        </div>

        {subTab === "cadastradas" ? (
          <div className="chart-card">
            <h3>De-para de Apontamentos</h3>
            <p style={{ color: "var(--text-muted)", fontSize: 14, marginBottom: 12 }}>
              Define como cada apontamento entra no cálculo de OEE. Tipo e motivo são fixos após o cadastro, porque é
              a combinação dos dois que liga a classificação aos apontamentos importados.
            </p>
            <div style={{ fontSize: 13, color: "var(--text-muted)", marginBottom: 4, minHeight: 18 }}>
              {c.zeradas
                ? `${c.zeradas} de ${c.totalItens} classificações sem nenhum apontamento — listadas no topo.`
                : `${c.totalItens} classificações, todas em uso.`}
            </div>
            <div style={{ fontSize: 13, marginBottom: 16, minHeight: 18, color: c.status.type === "error" ? "#ef4444" : c.status.type === "success" ? "#16a34a" : "var(--text-muted)" }}>
              {c.status.text}
            </div>
            <div className="table-responsive">
              <table className="data-table">
                <thead>
                  <tr>
                    <th>Tipo</th>
                    <th>Motivo</th>
                    <th>Classificação de Perda</th>
                    <th>Atuação</th>
                    <th>Nível</th>
                    <th style={{ width: 90, textAlign: "right" }}>Apont.</th>
                    <th style={{ width: 200 }}>Ações</th>
                  </tr>
                </thead>
                <tbody>
                  {c.loadingItens ? (
                    <tr>
                      <td colSpan={7} style={{ textAlign: "center" }}>
                        Carregando...
                      </td>
                    </tr>
                  ) : c.itens.length === 0 ? (
                    <tr>
                      <td colSpan={7} style={{ textAlign: "center" }}>
                        Nenhuma classificação encontrada.
                      </td>
                    </tr>
                  ) : (
                    c.itens.map((item) => (
                      <ClassificacaoRow key={item.id} item={item} onSave={c.updateClassificacao} onDelete={handleDelete} />
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </div>
        ) : (
          <div className="chart-card">
            <h3>Apontamentos sem Classificação</h3>
            <p style={{ color: "var(--text-muted)", fontSize: 14, marginBottom: 12 }}>
              Combinações de tipo e motivo que aparecem nos apontamentos mas não estão no de-para. As horas delas não
              entram em nenhum indicador. Ordenado por horas, do maior impacto para o menor.
            </p>
            <div style={{ fontSize: 13, marginBottom: 16, minHeight: 18, color: c.orfasStatus.type === "error" ? "#ef4444" : c.orfasStatus.type === "success" ? "#16a34a" : "var(--text-muted)" }}>
              {c.orfasStatus.text ||
                (c.orfas.length > 0
                  ? `${c.orfas.length} combinações sem classificação.`
                  : "Todos os apontamentos estão classificados.")}
            </div>
            <div className="table-responsive">
              <table className="data-table">
                <thead>
                  <tr>
                    <th>Tipo</th>
                    <th>Motivo</th>
                    <th>Área</th>
                    <th>Máquinas</th>
                    <th style={{ width: 90 }}>Apont.</th>
                    <th style={{ width: 90 }}>Horas</th>
                    <th style={{ width: 140 }}>Ações</th>
                  </tr>
                </thead>
                <tbody>
                  {c.loadingOrfas ? (
                    <tr>
                      <td colSpan={7} style={{ textAlign: "center" }}>
                        Carregando...
                      </td>
                    </tr>
                  ) : c.orfas.length === 0 ? (
                    <tr>
                      <td colSpan={7} style={{ textAlign: "center" }}>
                        Nenhuma órfã encontrada.
                      </td>
                    </tr>
                  ) : (
                    c.orfas.map((item, idx) => <ClassifOrfaRow key={idx} item={item} onClassify={openForm} />)
                  )}
                </tbody>
              </table>
            </div>
          </div>
        )}
      </div>

      <ClassifFormModal open={formOpen} prefill={prefill} onClose={() => setFormOpen(false)} onSubmit={c.createClassificacao} />
    </section>
  );
}
