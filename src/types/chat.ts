export interface ChatSession {
  session_id: string;
  titulo?: string | { content?: string };
  data_inicio: string;
  _isTemp?: boolean;
}

export interface ChatMessage {
  id?: number | string;
  role: "user" | "assistant";
  content: string;
  timestamp?: string | number;
  file?: string;
}

export interface QuickFormQuestion {
  q: string;
  placeholder?: string;
  options?: string[];
}

export interface ProductCard {
  nome: string;
  codigo?: string;
  tamanho?: string;
  peso?: string;
  material?: string;
  acabamento?: string;
  linha?: string;
  link?: string;
}

export interface ParsedAssistantContent {
  html: string;
  quickReplies: string[] | null;
  quickForm: QuickFormQuestion[] | null;
  products: ProductCard[] | null;
}
