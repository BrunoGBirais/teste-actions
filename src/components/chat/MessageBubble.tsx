import { useLayoutEffect, useMemo, useRef, useState } from "react";
import { User, Bot, Pencil, File as FileIcon, ChevronDown } from "lucide-react";
import type { DisplayMessage } from "../../hooks/useChat";
import { parseAssistantContent } from "../../lib/markdown";
import { QuickReplies } from "./QuickReplies";
import { QuickForm } from "./QuickForm";
import { ProductCards } from "./ProductCards";

const MSG_COLLAPSE_MAX_PX = 420;

interface MessageBubbleProps {
  message: DisplayMessage;
  onEdit: (message: DisplayMessage) => void;
  onQuickReply: (label: string) => void;
}

export function MessageBubble({ message, onEdit, onQuickReply }: MessageBubbleProps) {
  const isAssistant = message.role === "assistant";
  const parsed = useMemo(() => (isAssistant ? parseAssistantContent(message.content) : null), [isAssistant, message.content]);

  const bodyRef = useRef<HTMLDivElement>(null);
  const [collapsible, setCollapsible] = useState(false);
  const [collapsed, setCollapsed] = useState(false);

  useLayoutEffect(() => {
    if (!isAssistant || !bodyRef.current) return;
    const needsCollapse = bodyRef.current.scrollHeight > MSG_COLLAPSE_MAX_PX;
    setCollapsible(needsCollapse);
    setCollapsed(needsCollapse);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [parsed?.html]);

  const contentClass = `message-content${isAssistant && collapsible && collapsed ? " is-collapsed" : ""}`;

  return (
    <div className={`message ${message.role}`}>
      <div className="message-avatar">{isAssistant ? <Bot /> : <User />}</div>

      <div className={contentClass}>
        {isAssistant ? (
          <>
            <div className="msg-body" ref={bodyRef} dangerouslySetInnerHTML={{ __html: parsed!.html }} />
            {collapsible && (
              <button type="button" className="msg-toggle" onClick={() => setCollapsed((v) => !v)}>
                <span>{collapsed ? "Ver resposta completa" : "Recolher"}</span>
                <ChevronDown />
              </button>
            )}
            {parsed?.quickForm && parsed.quickForm.length > 0 ? (
              <QuickForm questions={parsed.quickForm} onSubmit={onQuickReply} />
            ) : (
              parsed?.quickReplies &&
              parsed.quickReplies.length > 0 && <QuickReplies options={parsed.quickReplies} onSelect={onQuickReply} />
            )}
            {parsed?.products && parsed.products.length > 0 && <ProductCards products={parsed.products} />}
          </>
        ) : message.file ? (
          <div className="file-attachment">
            <FileIcon style={{ width: 14, height: 14 }} />
            <span>{message.file}</span>
          </div>
        ) : (
          message.content
        )}
      </div>

      {!isAssistant && !message.file && (
        <button type="button" className="btn-edit" onClick={() => onEdit(message)}>
          <Pencil style={{ width: 14, height: 14 }} />
        </button>
      )}
    </div>
  );
}
