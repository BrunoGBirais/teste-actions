import { useEffect, useRef, useState } from "react";
import type { MaquinaFiltro } from "../../types/dashboard";
import type { useMaquinaFiltro } from "../../hooks/useMaquinaFiltro";

interface MaquinaFilterDropdownProps {
  filtro: ReturnType<typeof useMaquinaFiltro>;
}

export function MaquinaFilterDropdown({ filtro }: MaquinaFilterDropdownProps) {
  const [open, setOpen] = useState(false);
  const wrapRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function onDocClick(e: MouseEvent) {
      if (wrapRef.current && !wrapRef.current.contains(e.target as Node)) setOpen(false);
    }
    document.addEventListener("click", onDocClick);
    return () => document.removeEventListener("click", onDocClick);
  }, []);

  return (
    <div style={{ position: "relative" }} ref={wrapRef}>
      <button
        type="button"
        className="filter-select"
        style={{ minWidth: 180, textAlign: "left", display: "flex", justifyContent: "space-between", alignItems: "center", gap: 6, cursor: "pointer" }}
        onClick={() => setOpen((v) => !v)}
      >
        <span>{filtro.label}</span>
        <span style={{ fontSize: 10 }}>&#9660;</span>
      </button>
      {open && (
        <div
          style={{
            position: "absolute",
            top: "calc(100% + 4px)",
            left: 0,
            zIndex: 999,
            background: "var(--card-bg,#fff)",
            border: "1px solid var(--border,#ccc)",
            borderRadius: 6,
            padding: 8,
            boxShadow: "0 4px 12px rgba(0,0,0,.15)",
            minWidth: 260,
            maxHeight: 300,
            overflowY: "auto",
          }}
        >
          <div style={{ display: "flex", gap: 6, marginBottom: 8 }}>
            <button type="button" className="maq-bulk-btn" onClick={() => filtro.bulk("todas")}>
              Marcar todas
            </button>
            <button type="button" className="maq-bulk-btn" onClick={() => filtro.bulk("limpar")}>
              Limpar
            </button>
          </div>
          {[...filtro.porArea.entries()].map(([area, lista]: [string, MaquinaFiltro[]]) => (
            <div key={area}>
              <div className="maq-area-titulo">{area}</div>
              {lista.map((m) => {
                const id = String(m.id);
                const bloqueado = !!filtro.lockedArea && area !== filtro.lockedArea;
                return (
                  <label className={`maq-item${bloqueado ? " is-bloqueado" : ""}`} key={id}>
                    <input
                      type="checkbox"
                      checked={filtro.selected.has(id)}
                      disabled={bloqueado}
                      onChange={() => filtro.toggle(id)}
                    />
                    {m.nome}
                  </label>
                );
              })}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
