import { useEffect, useRef } from "react";
import type { DisplayMessage } from "../../hooks/useChat";
import { MessageBubble } from "./MessageBubble";
import { EmptyState } from "./EmptyState";
import { TypingIndicator } from "./TypingIndicator";

interface MessageListProps {
  messages: DisplayMessage[];
  loading: boolean;
  isSending: boolean;
  onEdit: (message: DisplayMessage) => void;
  onQuickReply: (label: string) => void;
}

function SkeletonMessages() {
  return (
    <>
      {[0, 1, 2].map((i) => (
        <div className="skeleton-message" key={i}>
          <div className="skeleton skeleton-avatar" />
          <div className="skeleton-content">
            <div className="skeleton skeleton-text" />
            <div className="skeleton skeleton-text" />
            <div className="skeleton skeleton-text" />
          </div>
        </div>
      ))}
    </>
  );
}

export function MessageList({ messages, loading, isSending, onEdit, onQuickReply }: MessageListProps) {
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const el = containerRef.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, [messages.length, isSending]);

  if (loading) {
    return (
      <div id="messagesContainer" ref={containerRef}>
        <SkeletonMessages />
      </div>
    );
  }

  if (messages.length === 0 && !isSending) {
    return <EmptyState />;
  }

  return (
    <div id="messagesContainer" ref={containerRef}>
      {messages.map((m) => (
        <MessageBubble key={m.key} message={m} onEdit={onEdit} onQuickReply={onQuickReply} />
      ))}
      {isSending && <TypingIndicator />}
    </div>
  );
}
