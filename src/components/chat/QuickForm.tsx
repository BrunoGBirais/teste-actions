import { useState } from "react";
import type { QuickFormQuestion } from "../../types/chat";

interface QuickFormProps {
  questions: QuickFormQuestion[];
  onSubmit: (compiledText: string) => void;
}

export function QuickForm({ questions, onSubmit }: QuickFormProps) {
  const [values, setValues] = useState<string[]>(() => questions.map(() => ""));
  const [locked, setLocked] = useState(false);

  function setValue(idx: number, value: string) {
    setValues((prev) => {
      const next = [...prev];
      next[idx] = value;
      return next;
    });
  }

  function handleSubmit() {
    const lines = questions
      .map((q, i) => {
        const v = (values[i] || "").trim() || "Não sei";
        return `${i + 1}. ${q.q}\n   → ${v}`;
      })
      .join("\n\n");
    setLocked(true);
    onSubmit(`📋 Respostas do formulário:\n\n${lines}`);
  }

  return (
    <div className="quick-form">
      {questions.map((q, idx) => (
        <div className="qf-item" key={idx}>
          <div className="qf-q">
            {idx + 1}. {q.q}
          </div>
          <input
            type="text"
            className="qf-input"
            placeholder={q.placeholder || "Digite a resposta ou clique numa opção"}
            value={values[idx]}
            disabled={locked}
            onChange={(e) => setValue(idx, e.target.value)}
          />
          {q.options && (
            <div className="qf-chips">
              {q.options.map((opt) => (
                <button
                  key={opt}
                  type="button"
                  className={`quick-reply-chip${values[idx] === opt ? " selected" : ""}`}
                  disabled={locked}
                  onClick={() => setValue(idx, opt)}
                >
                  {opt}
                </button>
              ))}
            </div>
          )}
        </div>
      ))}
      <button type="button" className="qf-submit" disabled={locked} onClick={handleSubmit}>
        {locked ? "Enviado" : "Enviar respostas"}
      </button>
    </div>
  );
}
