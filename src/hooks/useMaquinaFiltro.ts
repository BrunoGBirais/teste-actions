import { useCallback, useMemo, useState } from "react";
import type { MaquinaFiltro } from "../types/dashboard";

const AREA_PADRAO_FILTRO = "Acabamento";

// Filtro de máquina com seleção múltipla travada numa única área: somar
// máquinas de áreas diferentes juntaria processos distintos contra uma meta
// só, então a primeira marcada trava a área. Sem nada marcado, o dashboard
// assume a área padrão (Acabamento) em vez de "todas as áreas".
export function useMaquinaFiltro(maquinas: MaquinaFiltro[]) {
  const [selected, setSelected] = useState<Set<string>>(new Set());

  const lockedArea = useMemo(() => {
    for (const m of maquinas) {
      if (selected.has(String(m.id))) return m.area;
    }
    return null;
  }, [maquinas, selected]);

  const porArea = useMemo(() => {
    const map = new Map<string, MaquinaFiltro[]>();
    maquinas.forEach((m) => {
      const area = m.area || "Sem área";
      if (!map.has(area)) map.set(area, []);
      map.get(area)!.push(m);
    });
    return map;
  }, [maquinas]);

  const toggle = useCallback((id: string) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }, []);

  const bulk = useCallback(
    (acao: "todas" | "limpar") => {
      if (acao === "limpar") {
        setSelected(new Set());
        return;
      }
      const alvo = lockedArea || AREA_PADRAO_FILTRO;
      setSelected(new Set(maquinas.filter((m) => m.area === alvo).map((m) => String(m.id))));
    },
    [lockedArea, maquinas],
  );

  const label = useMemo(() => {
    const marcadas = maquinas.filter((m) => selected.has(String(m.id)));
    if (marcadas.length === 0) return `Todas (${AREA_PADRAO_FILTRO})`;
    if (marcadas.length === 1) return marcadas[0].nome;
    return `${marcadas.length} máquinas · ${lockedArea}`;
  }, [maquinas, selected, lockedArea]);

  // Sem nada marcado, usa os ids da área padrão (não "todas as áreas").
  const rpcIds = useMemo(() => {
    const marcadas = maquinas.filter((m) => selected.has(String(m.id))).map((m) => Number(m.id));
    if (marcadas.length) return marcadas;
    const padrao = maquinas.filter((m) => m.area === AREA_PADRAO_FILTRO).map((m) => Number(m.id));
    return padrao.length ? padrao : null;
  }, [maquinas, selected]);

  return { selected, lockedArea, porArea, toggle, bulk, label, rpcIds };
}
