import { SUPABASE_ANON_KEY, SUPABASE_URL } from "../config/constants";
import { getValidAccessToken, refreshAccessToken } from "../lib/authToken";

interface SupabaseErrorBody {
  error_description?: string;
  msg?: string;
  message?: string;
  hint?: string;
}

// POST to the Supabase GoTrue auth endpoint (login, signup, logout...).
export async function sbAuth<T = unknown>(path: string, body: unknown): Promise<T> {
  const res = await fetch(`${SUPABASE_URL}/auth/v1/${path}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: SUPABASE_ANON_KEY,
    },
    body: JSON.stringify(body),
  });
  const data = (await res.json().catch(() => ({}))) as SupabaseErrorBody & T;
  if (!res.ok) {
    const msg = data?.error_description || data?.msg || data?.message || `Erro ${res.status}`;
    throw new Error(msg);
  }
  return data;
}

// Call a Postgres RPC (SECURITY DEFINER function) with the user's JWT.
export async function sbRpc<T = unknown>(fnName: string, args: Record<string, unknown> = {}): Promise<T> {
  const token = await getValidAccessToken();
  if (!token) throw new Error("Sessão expirada. Faça login novamente.");

  const call = (jwt: string) =>
    fetch(`${SUPABASE_URL}/rest/v1/rpc/${fnName}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: SUPABASE_ANON_KEY,
        Authorization: `Bearer ${jwt}`,
      },
      body: JSON.stringify(args),
    });

  let res = await call(token);
  // O JWT pode ter expirado entre a checagem local e a chamada (relógio fora de
  // sincronia, requisição longa). Renova uma vez e repete antes de desistir.
  if (res.status === 401) {
    const renewed = await refreshAccessToken();
    if (renewed) res = await call(renewed);
  }

  const data = await res.json().catch(() => null);
  if (!res.ok) {
    const err = data as SupabaseErrorBody | null;
    const msg = err?.message || err?.error_description || err?.hint || `Erro ${res.status}`;
    if (res.status === 401) throw new Error("Sessão expirada. Faça login novamente.");
    throw new Error(msg);
  }
  return data as T;
}
