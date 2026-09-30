import { useRef, type ChangeEvent, type FormEvent, type KeyboardEvent } from "react";
import { Paperclip, Send, Square, X } from "lucide-react";
import { SuggestionBar } from "./SuggestionBar";

interface ChatInputProps {
  value: string;
  onChange: (value: string) => void;
  onSubmit: () => void;
  isLoading: boolean;
  isEditing: boolean;
  onCancelEdit: () => void;
  onAttachFile: (file: File) => void;
  onStop: () => void;
  statusMessage: string;
  statusType: string;
  onSuggestionSelect: (prompt: string) => void;
}

export function ChatInput({
  value,
  onChange,
  onSubmit,
  isLoading,
  isEditing,
  onCancelEdit,
  onAttachFile,
  onStop,
  statusMessage,
  statusType,
  onSuggestionSelect,
}: ChatInputProps) {
  const fileInputRef = useRef<HTMLInputElement>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  function handleInput(e: ChangeEvent<HTMLTextAreaElement>) {
    onChange(e.target.value);
    const el = e.target;
    el.style.height = "auto";
    el.style.height = el.scrollHeight + "px";
  }

  function handleKeyDown(e: KeyboardEvent<HTMLTextAreaElement>) {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      if (isLoading) onStop();
      else onSubmit();
    }
  }

  function handleSubmit(e: FormEvent) {
    e.preventDefault();
    if (isLoading) onStop();
    else onSubmit();
  }

  function handleFileChange(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (file) onAttachFile(file);
    e.target.value = "";
  }

  return (
    <div id="inputArea">
      <SuggestionBar disabled={isLoading} onSelect={onSuggestionSelect} />
      <div className="status-info" style={{ color: statusType === "error" ? "#d32f2f" : statusType === "success" ? "#388e3c" : "#7A1818" }}>
        {statusMessage}
      </div>
      <form id="inputForm" onSubmit={handleSubmit}>
        <input type="file" ref={fileInputRef} style={{ display: "none" }} onChange={handleFileChange} />
        <textarea
          ref={textareaRef}
          id="messageInput"
          placeholder="Digite sua mensagem..."
          rows={1}
          value={value}
          disabled={isLoading}
          onChange={handleInput}
          onKeyDown={handleKeyDown}
        />
        <div className="controls">
          <button type="button" className="action-btn btn-attach" title="Anexar arquivo" disabled={isLoading} onClick={() => fileInputRef.current?.click()}>
            <Paperclip />
          </button>
          {isEditing && (
            <button type="button" className="action-btn" style={{ background: "#f0f0f0", color: "#666" }} title="Cancelar Edição" onClick={onCancelEdit}>
              <X />
            </button>
          )}
          <button
            type="submit"
            className="action-btn btn-send"
            title={isLoading ? "Parar Geração" : "Enviar"}
            style={isLoading ? { backgroundColor: "var(--text-secondary)" } : undefined}
          >
            {isLoading ? <Square fill="white" /> : <Send />}
          </button>
        </div>
      </form>
    </div>
  );
}
