export function EmptyState() {
  return (
    <div className="empty-state show">
      <div className="empty-icon">
        <svg viewBox="0 0 64 64" width="100%" height="100%" fill="none" xmlns="http://www.w3.org/2000/svg">
          <circle cx="32" cy="32" r="30" stroke="var(--color-accent)" strokeWidth={2} opacity={0.35} />
          <rect x="18" y="28" width="28" height="16" rx="2" stroke="var(--color-primary)" strokeWidth={2.5} fill="none" />
          <rect x="22" y="18" width="20" height="12" rx="1" stroke="var(--color-primary)" strokeWidth={2.5} fill="none" />
          <rect x="22" y="40" width="20" height="10" rx="1" stroke="var(--color-accent)" strokeWidth={2} fill="none" />
          <circle cx="40" cy="34" r="1.6" fill="var(--color-accent)" />
        </svg>
      </div>
      <div className="empty-title" style={{ fontFamily: '"Inter", sans-serif' }}>
        <span style={{ color: "var(--color-accent)", fontSize: "0.7em", letterSpacing: 3 }}>PRODUÇÃO</span>
        <br />
        Como posso ajudar?
      </div>
      <div className="empty-subtitle">
        Pergunte sobre o andamento de uma Ordem de Serviço (OS), tempo de parada de máquinas e indicadores de
        produção da PRINT IAG.
      </div>
    </div>
  );
}
