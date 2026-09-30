import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import { AUTH_KEY } from "../config/constants";
import { decodeJwtPayload } from "../lib/jwt";
import { storage } from "../lib/storage";
import { sbAuth } from "../services/supabase";
import { SUPABASE_ANON_KEY, SUPABASE_URL } from "../config/constants";
import type { AuthData, AuthUser } from "../types/auth";

interface LoginResult {
  ok: boolean;
  error?: string;
}

interface AuthContextValue {
  // False until the stored session has been read; lets the shell render nothing
  // instead of flashing the login page for an already logged-in user.
  ready: boolean;
  currentUser: AuthUser | null;
  isLoggedIn: boolean;
  isAdmin: boolean;
  storageAvailable: boolean;
  sessionPrefix: string | null;
  login: (email: string, password: string) => Promise<LoginResult>;
  logout: () => Promise<void>;
  sessionBelongsToCurrentUser: (sessionId: unknown) => boolean;
}

const AuthContext = createContext<AuthContextValue | null>(null);

function readAuthData(): AuthData | null {
  try {
    const raw = storage.get(AUTH_KEY);
    if (!raw) return null;
    return JSON.parse(raw) as AuthData;
  } catch {
    return null;
  }
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [currentUser, setCurrentUser] = useState<AuthUser | null>(null);
  const [checked, setChecked] = useState(false);

  const hydrateFromStorage = useCallback(() => {
    const authData = readAuthData();
    if (!authData) {
      setCurrentUser(null);
      setChecked(true);
      return;
    }
    const now = Date.now();
    if (!authData.expiry || now > authData.expiry) {
      storage.remove(AUTH_KEY);
      setCurrentUser(null);
      setChecked(true);
      return;
    }
    const user = authData.user || decodeJwtPayload<AuthUser>(authData.access_token) || null;
    setCurrentUser(user);
    setChecked(true);
  }, []);

  useEffect(() => {
    hydrateFromStorage();
  }, [hydrateFromStorage]);

  const login = useCallback(async (email: string, password: string): Promise<LoginResult> => {
    // ---- BYPASS DE LOGIN (admin/admin) ----
    // Login falso para desenvolvimento/demo. Remover em produção.
    if (email === "admin" && password === "admin") {
      const fakeUser: AuthUser = {
        id: "00000000-0000-0000-0000-000000000001",
        email: "admin@printiag.local",
        user_metadata: { full_name: "Administrador", role: "admin" },
        app_metadata: { role: "admin" },
      };
      const authData: AuthData = {
        access_token: "fake-admin-token",
        refresh_token: "fake-admin-refresh",
        user: fakeUser,
        expiry: Date.now() + 8 * 60 * 60 * 1000,
      };
      storage.set(AUTH_KEY, JSON.stringify(authData));
      setCurrentUser(fakeUser);
      return { ok: true };
    }

    try {
      const data = await sbAuth<{
        access_token: string;
        refresh_token: string;
        expires_in?: number;
        user: AuthUser;
      }>("token?grant_type=password", { email, password });
      const expiresInMs = (data.expires_in || 3600) * 1000;
      const authData: AuthData = {
        access_token: data.access_token,
        refresh_token: data.refresh_token,
        user: data.user,
        expiry: Date.now() + expiresInMs,
      };
      storage.set(AUTH_KEY, JSON.stringify(authData));
      setCurrentUser(data.user);
      return { ok: true };
    } catch (err) {
      return { ok: false, error: (err as Error).message || "Credenciais inválidas" };
    }
  }, []);

  const logout = useCallback(async () => {
    const authData = readAuthData();
    if (authData?.access_token && authData.access_token !== "fake-admin-token") {
      try {
        await fetch(`${SUPABASE_URL}/auth/v1/logout`, {
          method: "POST",
          headers: { apikey: SUPABASE_ANON_KEY, Authorization: `Bearer ${authData.access_token}` },
        });
      } catch (e) {
        console.warn("Supabase logout call failed (continuing):", e);
      }
    }
    storage.remove(AUTH_KEY);
    setCurrentUser(null);
  }, []);

  const userId = currentUser?.sub || currentUser?.id || null;
  const sessionPrefix = userId ? `u_${userId}__` : null;
  const isAdmin = !!currentUser && (currentUser.user_metadata?.role || currentUser.role) === "admin";

  const sessionBelongsToCurrentUser = useCallback(
    (sessionId: unknown) => {
      if (!sessionPrefix) return false;
      return typeof sessionId === "string" && sessionId.startsWith(sessionPrefix);
    },
    [sessionPrefix],
  );

  const value = useMemo<AuthContextValue>(
    () => ({
      ready: checked,
      currentUser,
      isLoggedIn: checked && !!currentUser,
      isAdmin,
      storageAvailable: storage.isAvailable,
      sessionPrefix,
      login,
      logout,
      sessionBelongsToCurrentUser,
    }),
    [currentUser, checked, isAdmin, sessionPrefix, login, logout, sessionBelongsToCurrentUser],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used within an AuthProvider");
  return ctx;
}
