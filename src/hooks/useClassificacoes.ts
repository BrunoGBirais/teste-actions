import { useCallback, useEffect, useMemo, useState } from "react";
import { sbRpc } from "../services/supabase";
import type { Classificacao, ClassificacaoOrfa } from "../types/admin";

export const CLASSIF_PERDA_OPCOES = [
  "Virando",
  "Acerto",
  "Sem Apontamento",
  "Sem Serviço",
  "Sem Tripulação",
  "Operacional Planejado",
  "Manutenção Preventiva",
  "Manutenção Corretiva",
  "Problema de Processo",
  "Aguardando",
];
export const CLASSIF_ATUACAO_OPCOES = ["Virando", "Acerto", "Área", "Gerencial", "Sem Apontamento"];
export const CLASSIF_NIVEL_OPCOES = ["Gerencial", "Liderança", "Operacional"];

export function useClassificacoes() {
  const [itens, setItens] = useState<Classificacao[]>([]);
  const [orfas, setOrfas] = useState<ClassificacaoOrfa[]>([]);
  const [busca, setBusca] = useState("");
  const [pendente, setPendente] = useState(false);
  const [loadingItens, setLoadingItens] = useState(true);
  const [loadingOrfas, setLoadingOrfas] = useState(true);
  const [status, setStatus] = useState<{ text: string; type?: "success" | "error" }>({ text: "" });
  const [orfasStatus, setOrfasStatus] = useState<{ text: string; type?: "success" | "error" }>({ text: "" });

  const loadItens = useCallback(async () => {
    setLoadingItens(true);
    try {
      const data = await sbRpc<Classificacao[]>("printag_get_classificacoes");
      setItens(data || []);
    } catch (err) {
      setStatus({ text: (err as Error).message || "Erro ao carregar classificações", type: "error" });
    } finally {
      setLoadingItens(false);
    }
  }, []);

  const loadOrfas = useCallback(async () => {
    setLoadingOrfas(true);
    try {
      const data = await sbRpc<ClassificacaoOrfa[]>("printag_get_classificacoes_orfas");
      setOrfas(data || []);
    } catch (err) {
      setOrfasStatus({ text: (err as Error).message || "Erro ao carregar órfãs", type: "error" });
    } finally {
      setLoadingOrfas(false);
    }
  }, []);

  useEffect(() => {
    loadItens();
    loadOrfas();
  }, [loadItens, loadOrfas]);

  const filtradas = useMemo(() => {
    const termo = busca.trim().toLowerCase();
    const filtrada = termo
      ? itens.filter((i) =>
          [i.chave, i.tipo_apontam, i.motivo, i.classificacao_perda, i.atuacao].some((v) =>
            (v || "").toLowerCase().includes(termo),
          ),
        )
      : itens;
    const semUso = (i: Classificacao) => (Number(i.qtd_apontamentos || 0) === 0 ? 0 : 1);
    return [...filtrada].sort((a, b) => semUso(a) - semUso(b));
  }, [itens, busca]);

  const orfasFiltradas = useMemo(() => {
    const termo = busca.trim().toLowerCase();
    return termo
      ? orfas.filter((i) => [i.tipo_apontam, i.motivo, i.areas, i.maquinas].some((v) => (v || "").toLowerCase().includes(termo)))
      : orfas;
  }, [orfas, busca]);

  const zeradas = itens.filter((i) => Number(i.qtd_apontamentos || 0) === 0).length;

  const updateClassificacao = useCallback(
    async (item: Classificacao, changes: Pick<Classificacao, "classificacao_perda" | "atuacao" | "nivel_atuacao">) => {
      await sbRpc("printag_update_classificacao", {
        p_id: item.id,
        p_classificacao_perda: changes.classificacao_perda,
        p_atuacao: changes.atuacao,
        p_nivel_atuacao: changes.nivel_atuacao || null,
      });
      setItens((prev) => prev.map((i) => (i.id === item.id ? { ...i, ...changes } : i)));
      setPendente(true);
      setStatus({ text: "Classificação atualizada.", type: "success" });
    },
    [],
  );

  const deleteClassificacao = useCallback(
    async (item: Classificacao) => {
      await sbRpc("printag_delete_classificacao", { p_id: item.id });
      setStatus({ text: "Classificação excluída.", type: "success" });
      await loadItens();
    },
    [loadItens],
  );

  const createClassificacao = useCallback(
    async (payload: {
      chave: string;
      tipo_apontam: string;
      motivo: string;
      classificacao_perda: string;
      atuacao: string;
      nivel_atuacao: string | null;
    }) => {
      await sbRpc("printag_insert_classificacao", {
        p_chave: payload.chave,
        p_tipo_apontam: payload.tipo_apontam,
        p_motivo: payload.motivo,
        p_classificacao_perda: payload.classificacao_perda,
        p_atuacao: payload.atuacao,
        p_nivel_atuacao: payload.nivel_atuacao,
      });
      setPendente(true);
      setStatus({ text: "Classificação criada.", type: "success" });
      await Promise.all([loadItens(), loadOrfas()]);
    },
    [loadItens, loadOrfas],
  );

  const aplicarAosDashboards = useCallback(async () => {
    setStatus({ text: "Recalculando a base... isso pode demorar alguns minutos." });
    try {
      await sbRpc("printag_refresh_base");
      setPendente(false);
      setStatus({ text: "Base atualizada. Os dashboards já refletem as mudanças.", type: "success" });
      await loadItens();
    } catch (err) {
      setStatus({
        text:
          ((err as Error).message || "Erro ao atualizar a base") +
          " — se foi timeout, o recálculo pode continuar rodando no servidor.",
        type: "error",
      });
    }
  }, [loadItens]);

  return {
    itens: filtradas,
    orfas: orfasFiltradas,
    totalItens: itens.length,
    zeradas,
    busca,
    setBusca,
    pendente,
    loadingItens,
    loadingOrfas,
    status,
    orfasStatus,
    updateClassificacao,
    deleteClassificacao,
    createClassificacao,
    aplicarAosDashboards,
  };
}
