import { useCallback, useEffect, useState } from "react";
import { sbRpc } from "../services/supabase";
import type { OeeKpis, OeePorSemanaRow, ParetoRow, PorEquipamentoRow, ProducaoTipoRow } from "../types/dashboard";

export interface OeeDashboardData {
  kpis: OeeKpis;
  porSemana: OeePorSemanaRow[];
  pareto: ParetoRow[];
  tipo: ProducaoTipoRow[];
  porEquipamento: PorEquipamentoRow[];
}

// Tela "OEE Geral" não expõe filtros no HTML legado (o toolbar correspondente
// está vazio) — os RPCs sempre rodam com os parâmetros default.
const BASE_PARAMS = { p_semanas: null, p_ano: null, p_equipamento: null, p_operador: null, p_tipo_acabamento: null, p_dias: 999 };

export function useOeeDashboard() {
  const [data, setData] = useState<OeeDashboardData | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [kpis, porSemana, pareto, tipo, porEquipamento] = await Promise.all([
        sbRpc<OeeKpis>("printag_oee_kpis", BASE_PARAMS),
        sbRpc<OeePorSemanaRow[]>("printag_oee_por_semana", BASE_PARAMS),
        sbRpc<ParetoRow[]>("printag_oee_pareto_improdutivos", { ...BASE_PARAMS, p_top: 10 }),
        sbRpc<ProducaoTipoRow[]>("printag_oee_producao_por_tipo", BASE_PARAMS),
        sbRpc<PorEquipamentoRow[]>("printag_oee_por_equipamento", BASE_PARAMS),
      ]);
      setData({ kpis: kpis || {}, porSemana: porSemana || [], pareto: pareto || [], tipo: tipo || [], porEquipamento: porEquipamento || [] });
    } catch (err) {
      setError((err as Error).message || String(err));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  return { data, loading, error, reload: load };
}
