"use client";

import { useState } from "react";
import { useChat } from "../hooks/useChat";
import { ChatSidebar } from "../components/chat/ChatSidebar";
import { MessageList } from "../components/chat/MessageList";
import { ChatInput } from "../components/chat/ChatInput";
import { ConfirmModal } from "../components/modals/ConfirmModal";
import type { DisplayMessage } from "../hooks/useChat";
import { useShell } from "../layout/AppShell";

export function ChatPage() {
  const { chatSidebarOpen: sidebarOpen, closeChatSidebar: onCloseSidebar } = useShell();
  const chat = useChat();
  const [inputValue, setInputValue] = useState("");
  const [pendingDeleteId, setPendingDeleteId] = useState<string | null>(null);

  function handleSelectSession(sessionId: string) {
    chat.loadSession(sessionId);
    if (window.innerWidth <= 768) onCloseSidebar();
  }

  function handleNewChat() {
    chat.startNewChat();
    if (window.innerWidth <= 768) onCloseSidebar();
  }

  function handleEdit(message: DisplayMessage) {
    chat.startEdit(message);
    setInputValue(message.content);
  }

  function handleCancelEdit() {
    chat.cancelEdit();
    setInputValue("");
  }

  async function handleSubmit() {
    const text = inputValue;
    setInputValue("");
    await chat.send(text);
  }

  async function handleQuickReply(label: string) {
    await chat.send(label);
  }

  return (
    <div className={`main-grid${sidebarOpen ? "" : " sidebar-closed"}`}>
      <div className="sidebar-backdrop" onClick={onCloseSidebar} />
      <ChatSidebar
        sessions={chat.sessions}
        currentSessionId={chat.currentSessionId}
        loading={false}
        onNewChat={handleNewChat}
        onSelect={handleSelectSession}
        onDelete={(id) => setPendingDeleteId(id)}
      />
      <main id="chatArea">
        <MessageList
          messages={chat.messages}
          loading={chat.messagesLoading}
          isSending={chat.isLoading}
          onEdit={handleEdit}
          onQuickReply={handleQuickReply}
        />
        <ChatInput
          value={inputValue}
          onChange={setInputValue}
          onSubmit={handleSubmit}
          isLoading={chat.isLoading}
          isEditing={!!chat.editing}
          onCancelEdit={handleCancelEdit}
          onAttachFile={chat.uploadFile}
          onStop={chat.stopGeneration}
          statusMessage={chat.status.text}
          statusType={chat.status.type}
          onSuggestionSelect={(prompt) => chat.send(prompt)}
        />
      </main>

      <ConfirmModal
        open={!!pendingDeleteId}
        title="Excluir conversa"
        text="Tem certeza que deseja excluir esta conversa permanentemente? Esta ação não pode ser desfeita."
        confirmLabel="Excluir"
        onCancel={() => setPendingDeleteId(null)}
        onConfirm={async () => {
          if (pendingDeleteId) await chat.confirmDeleteSession(pendingDeleteId);
          setPendingDeleteId(null);
        }}
      />
    </div>
  );
}
