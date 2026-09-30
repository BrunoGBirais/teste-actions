interface ConfirmModalProps {
  open: boolean;
  title: string;
  text: string;
  confirmLabel?: string;
  confirmColor?: string;
  onConfirm: () => void;
  onCancel: () => void;
}

export function ConfirmModal({ open, title, text, confirmLabel = "Confirmar", confirmColor, onConfirm, onCancel }: ConfirmModalProps) {
  return (
    <div className={`confirm-modal-backdrop${open ? " active" : ""}`}>
      <div className="confirm-modal">
        <h3 className="confirm-title">{title}</h3>
        <p className="confirm-text">{text}</p>
        <div className="confirm-actions">
          <button type="button" className="btn-modal btn-cancel" onClick={onCancel}>
            Cancelar
          </button>
          <button
            type="button"
            className="btn-modal btn-confirm"
            style={confirmColor ? { background: confirmColor } : undefined}
            onClick={onConfirm}
          >
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}
