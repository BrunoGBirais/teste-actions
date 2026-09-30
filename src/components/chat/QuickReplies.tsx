import { useState } from "react";

interface QuickRepliesProps {
  options: string[];
  onSelect: (label: string) => void;
}

export function QuickReplies({ options, onSelect }: QuickRepliesProps) {
  const [selected, setSelected] = useState<string | null>(null);

  return (
    <div className="quick-replies">
      {options.map((label) => (
        <button
          key={label}
          type="button"
          className={`quick-reply-chip${selected === label ? " selected" : ""}`}
          disabled={selected !== null}
          onClick={() => {
            setSelected(label);
            onSelect(label);
          }}
        >
          {label}
        </button>
      ))}
    </div>
  );
}
