import { useCallback, useEffect, useState } from "react";
import { sbRpc } from "../services/supabase";
import type { MetaMaquina } from "../types/admin";

type MetaNumericField = Exclude<keyof MetaMaquina, "nome_maquina">;

export const METAS_MAQ_CAMPOS: { key: MetaNumericField; step: string; label: string }[] = [
  { key: "meta_velocidade_virando", step: "1", label: "Vel. Virando (peç/h)" },
  { key: "meta_velocidade_com_acerto", step: "1", label: "Vel. + Acerto (peç/h)" },
  { key: "meta_tempo_medio_acerto", step: "0.1", label: "Tempo Médio Acerto (min)" },
  { key: "meta_improdutivo_area_pct", step: "0.01", label: "Improdutivo Área (%)" },
  { key: "meta_improdutivo_gerencial_pct", step: "0.01", label: "Improdutivo Gerencial (%)" },
];

export function useMetasMaquinas() {
  const [metas, setMetas] = useState<MetaMaquina[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await sbRpc<MetaMaquina[]>("printag_get_metas_maquinas");
      setMetas(data || []);
    } catch (err) {
      setError((err as Error).message || "Erro ao carregar metas");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const save = useCallback(
    async (payload: Record<string, unknown>) => {
      await sbRpc("printag_update_metas_maquina", payload);
      await load();
    },
    [load],
  );

  return { metas, loading, error, reload: load, save };
}
