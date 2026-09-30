import { useEffect, useRef, useState } from "react";
import { API_BASE } from "../config/constants";
import { checkHealth } from "../services/n8n";

// Mirrors the legacy global `fetch` interceptor: watches every request to
// API_BASE (except the health check itself) and flips to "offline" on
// network errors or 5xx responses, then polls printag_health until it
// recovers.
export function useConnectionStatus(): boolean {
  const [isOffline, setIsOffline] = useState(false);
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  useEffect(() => {
    checkHealth().then((ok) => setIsOffline(!ok));

    const originalFetch = window.fetch;
    window.fetch = async (...args: Parameters<typeof fetch>) => {
      const input = args[0];
      const url =
        typeof input === "string" ? input : input instanceof Request ? input.url : (input as URL).toString();
      try {
        const response = await originalFetch(...args);
        if (url.startsWith(API_BASE) && !url.includes("printag_health")) {
          if (response.ok) setIsOffline(false);
          else if (response.status >= 500) setIsOffline(true);
        }
        return response;
      } catch (error) {
        if (url.startsWith(API_BASE) && !url.includes("printag_health")) {
          if (!(error instanceof DOMException && error.name === "AbortError")) {
            setIsOffline(true);
          }
        }
        throw error;
      }
    };

    return () => {
      window.fetch = originalFetch;
    };
  }, []);

  useEffect(() => {
    if (isOffline) {
      if (!intervalRef.current) {
        intervalRef.current = setInterval(async () => {
          const ok = await checkHealth();
          if (ok) setIsOffline(false);
        }, 10000);
      }
    } else if (intervalRef.current) {
      clearInterval(intervalRef.current);
      intervalRef.current = null;
    }
    return () => {
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
        intervalRef.current = null;
      }
    };
  }, [isOffline]);

  return isOffline;
}
