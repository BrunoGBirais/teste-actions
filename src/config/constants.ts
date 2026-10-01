// Per-environment values come from NEXT_PUBLIC_* env vars (see .env.example).
// Next.js inlines them at build time, so they must be referenced literally.
// n8n webhooks are called on this site's own origin and proxied to the
// environment's n8n by the rewrite in next.config.ts (N8N_WEBHOOK_ORIGIN).
export const API_BASE = "/n8n";
export const CHAT_URL = `${API_BASE}/printag-AgentRag`;
export const UPLOAD_URL = `${API_BASE}/printag-index-drive`;
export const UPLOAD_DATASET_URL = `${API_BASE}/printag-upload-dataset`;
export const SESSIONS_URL = `${API_BASE}/printag-sessions`;
export const HISTORY_URL = `${API_BASE}/printag-history`;
export const DELETE_URL = `${API_BASE}/printag-session`;
export const HEALTH_URL = `${API_BASE}/printag_health`;

export const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";
export const SUPABASE_ANON_KEY = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "";
export const COMPANY_NAME = "printag";

export const AUTH_KEY = "chat_auth_v2";
export const AUTH_EXPIRY_MS = 12 * 60 * 60 * 1000; // 12 Hours
