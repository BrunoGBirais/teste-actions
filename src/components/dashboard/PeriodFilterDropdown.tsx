import { useEffect, useRef, useState } from "react";

interface PeriodFilterDropdownProps {
  options: number[];
  selected: number[];
  onChange: (next: number[]) => void;
  labelFor: (n: number) => string;
  maxSelected?: number;
}

// Multi-seleção de semana/mês em painel de checkboxes, usada tanto no
// dashboard semanal quanto no mensal.
export function PeriodFilterDropdown({ options, selected, onChange, labelFor, maxSelected = 10 }: PeriodFilterDropdownProps) {
  const [open, setOpen] = useState(false);
  const wrapRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function onDocClick(e: MouseEvent) {
      if (wrapRef.current && !wrapRef.current.contains(e.target as Node)) setOpen(false);
    }
    document.addEventListener("click", onDocClick);
    return () => document.removeEventListener("click", onDocClick);
  }, []);

  function toggle(n: number) {
    const isChecked = selected.includes(n);
    if (!isChecked && selected.length >= maxSelected) return;
    onChange(isChecked ? selected.filter((v) => v !== n) : [...selected, n]);
  }

  const label = selected.length ? selected.map(labelFor).join(", ") : "Todas";

  return (
    <div style={{ position: "relative" }} ref={wrapRef}>
      <button
        type="button"
        className="filter-select"
        style={{ minWidth: 130, textAlign: "left", display: "flex", justifyContent: "space-between", alignItems: "center", gap: 6, cursor: "pointer" }}
        onClick={() => setOpen((v) => !v)}
      >
        <span>{label}</span>
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
            minWidth: 200,
            maxHeight: 220,
            overflowY: "auto",
            display: "flex",
            flexWrap: "wrap",
            gap: 5,
          }}
        >
          {options.map((n) => (
            <label
              key={n}
              style={{
                display: "inline-flex",
                alignItems: "center",
                gap: 3,
                padding: "3px 8px",
                border: "1px solid var(--border,#ccc)",
                borderRadius: 4,
                fontSize: 12,
                cursor: "pointer",
                userSelect: "none",
                background: "var(--card-bg,#fff)",
                color: "var(--text,#333)",
              }}
            >
              <input type="checkbox" checked={selected.includes(n)} onChange={() => toggle(n)} style={{ accentColor: "var(--accent,#2563eb)" }} />
              {labelFor(n)}
            </label>
          ))}
        </div>
      )}
    </div>
  );
}
