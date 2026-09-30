import { useCallback, useEffect, useMemo, useState } from "react";
import { sbRpc } from "../services/supabase";
import { useMaquinaFiltro } from "./useMaquinaFiltro";
import type { IndFiltros, IndSemanaRow, MetasFixas, ParetoRow } from "../types/dashboard";

export interface IndicadoresSemanaData {
  acerto: IndSemanaRow[];
  velocVirando: IndSemanaRow[];
  improdutivos: IndSemanaRow[];
  paretoArea: ParetoRow[];
  paretoGerencial: ParetoRow[];
  velocAcerto: IndSemanaRow[];
  tiragem: IndSemanaRow[];
  metas: MetasFixas;
}

const ANOS = [2026, 2025];

export function useIndicadoresSemana() {
  const [ano, setAno] = useState(2026);
  const [semanasDisponiveis, setSemanasDisponiveis] = useState<number[]>([]);
  const [semanasSelecionadas, setSemanasSelecionadas] = useState<number[]>([]);
  const [operadoresDisponiveis, setOperadoresDisponiveis] = useState<string[]>([]);
  const [operador, setOperador] = useState("");
  const [maquinas, setMaquinas] = useState<IndFiltros["maquinas"]>([]);
  const maquinaFiltro = useMaquinaFiltro(maquinas || []);

  const [data, setData] = useState<IndicadoresSemanaData | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const loadFiltros = useCallback(async () => {
    try {
      const rows = await sbRpc<IndFiltros[]>("printag_ind_filtros", { p_ano: ano });
      const f = rows?.[0] || {};
      setMaquinas(f.maquinas || []);
      setSemanasDisponiveis(f.semanas || []);
      setOperadoresDisponiveis(f.operadores || []);
    } catch (err) {
      console.warn("Erro ao carregar filtros indicadores:", err);
    }
  }, [ano]);

  useEffect(() => {
    loadFiltros();
  }, [loadFiltros]);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const params = {
        p_ano: ano,
        p_maquinas: maquinaFiltro.rpcIds,
        p_semanas: semanasSelecionadas.length > 0 ? semanasSelecionadas : null,
        p_operadores: operador ? [operador] : null,
      };
      const [acerto, velocVirando, improdutivos, paretoArea, paretoGerencial, velocAcerto, tiragem, metasRows] = await Promise.all([
        sbRpc<IndSemanaRow[]>("printag_ind_acerto_semana", params),
        sbRpc<IndSemanaRow[]>("printag_ind_veloc_virando_semana", params),
        sbRpc<IndSemanaRow[]>("printag_ind_improdutivos_semana", params),
        sbRpc<ParetoRow[]>("printag_ind_pareto_area", params),
        sbRpc<ParetoRow[]>("printag_ind_pareto_gerencial", params),
        sbRpc<IndSemanaRow[]>("printag_ind_velocidade_com_acerto", params),
        sbRpc<IndSemanaRow[]>("printag_ind_qtd_tiragem", params),
        sbRpc<MetasFixas[]>("printag_metas_fixas", { p_maquinas: params.p_maquinas }),
      ]);
      setData({
        acerto: acerto || [],
        velocVirando: velocVirando || [],
        improdutivos: improdutivos || [],
        paretoArea: paretoArea || [],
        paretoGerencial: paretoGerencial || [],
        velocAcerto: velocAcerto || [],
        tiragem: tiragem || [],
        metas: metasRows?.[0] || {},
      });
    } catch (err) {
      setError((err as Error).message || String(err));
    } finally {
      setLoading(false);
    }
  }, [ano, maquinaFiltro.rpcIds, operador, semanasSelecionadas]);

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const labels = useMemo(() => (data ? data.acerto.map((r) => "S" + r.semana) : []), [data]);

  return {
    ano,
    setAno,
    anos: ANOS,
    semanasDisponiveis,
    semanasSelecionadas,
    setSemanasSelecionadas,
    operadoresDisponiveis,
    operador,
    setOperador,
    maquinaFiltro,
    data,
    labels,
    loading,
    error,
    reload: load,
  };
}
