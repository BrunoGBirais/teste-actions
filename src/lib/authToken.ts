import { storage } from "./storage";
import { AUTH_KEY, SUPABASE_ANON_KEY, SUPABASE_URL } from "../config/constants";
import type { AuthData } from "../types/auth";

// O JWT do Supabase expira em ~1h, mas a sessão local pode durar mais.
// Renovamos um pouco antes do vencimento para não estourar no meio de um upload.
const REFRESH_SKEW_MS = 60_000;

// Standalone (non-React) accessors so services/hooks can read the current
// Supabase session without needing to thread the auth context everywhere —
// mirrors the legacy vanilla-JS `getAccessToken()` helper.
export function getStoredAuthData(): AuthData | null {
  try {
    const raw = storage.get(AUTH_KEY);
    if (!raw) return null;
    return JSON.parse(raw) as AuthData;
  } catch {
    return null;
  }
}

export function getAccessToken(): string | null {
  const data = getStoredAuthData();
  if (!data?.access_token) return null;
  if (data.expiry && Date.now() > data.expiry) return null;
  return data.access_token;
}

let refreshInFlight: Promise<string | null> | null = null;

// Troca o refresh_token por um novo access_token e regrava a sessão.
// Chamadas concorrentes compartilham a mesma promise para não invalidar
// o refresh_token em corrida (o GoTrue rotaciona o token a cada uso).
export function refreshAccessToken(): Promise<string | null> {
  if (refreshInFlight) return refreshInFlight;
  const data = getStoredAuthData();
  if (!data?.refresh_token || data.access_token === "fake-admin-token") {
    return Promise.resolve(null);
  }
  refreshInFlight = (async () => {
    try {
      const res = await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=refresh_token`, {
        method: "POST",
        headers: { "Content-Type": "application/json", apikey: SUPABASE_ANON_KEY },
        body: JSON.stringify({ refresh_token: data.refresh_token }),
      });
      if (!res.ok) return null;
      const next = (await res.json()) as {
        access_token: string;
        refresh_token: string;
        expires_in?: number;
      };
      if (!next?.access_token) return null;
      const merged: AuthData = {
        ...data,
        access_token: next.access_token,
        refresh_token: next.refresh_token || data.refresh_token,
        expiry: Date.now() + (next.expires_in || 3600) * 1000,
      };
      storage.set(AUTH_KEY, JSON.stringify(merged));
      return merged.access_token;
    } catch {
      return null;
    } finally {
      refreshInFlight = null;
    }
  })();
  return refreshInFlight;
}

// Token pronto para uso: renova de forma transparente se estiver perto de expirar.
export async function getValidAccessToken(): Promise<string | null> {
  const data = getStoredAuthData();
  if (!data?.access_token) return null;
  if (data.access_token === "fake-admin-token") return data.access_token;
  if (!data.expiry || Date.now() < data.expiry - REFRESH_SKEW_MS) return data.access_token;
  return refreshAccessToken();
}

export function authHeaders(extra?: Record<string, string>): Record<string, string> {
  const token = getAccessToken();
  const h: Record<string, string> = { ...(extra || {}) };
  if (token) h.Authorization = `Bearer ${token}`;
  return h;
}
