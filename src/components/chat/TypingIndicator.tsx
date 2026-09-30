import { Bot } from "lucide-react";

export function TypingIndicator() {
  return (
    <div className="typing-indicator">
      <div className="message-avatar">
        <Bot />
      </div>
      <div className="typing-dots">
        <span></span>
        <span></span>
        <span></span>
      </div>
    </div>
  );
}
