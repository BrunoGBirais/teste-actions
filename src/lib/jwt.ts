export function decodeJwtPayload<T = unknown>(token: string): T | null {
  try {
    const base = token.split(".")[1];
    const padded = base.replace(/-/g, "+").replace(/_/g, "/");
    const json = atob(padded + "=".repeat((4 - (padded.length % 4)) % 4));
    return JSON.parse(decodeURIComponent(escape(json))) as T;
  } catch (e) {
    console.warn("Failed to decode JWT payload:", e);
    return null;
  }
}
