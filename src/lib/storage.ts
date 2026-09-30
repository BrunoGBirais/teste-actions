// Safe localStorage wrapper: falls back to an in-memory store when
// localStorage is unavailable (sandboxed iframe, disabled storage, etc).
class SafeStorage {
  private memory: Record<string, string> = {};
  isAvailable = false;

  constructor() {
    // Also evaluated during Next.js server rendering, where there is no storage.
    if (typeof window === "undefined") return;
    try {
      const testKey = "__storage_test__";
      localStorage.setItem(testKey, testKey);
      localStorage.removeItem(testKey);
      this.isAvailable = true;
    } catch {
      this.isAvailable = false;
      console.warn(
        "LocalStorage is not available (Sandboxed or disabled). Using in-memory storage.",
      );
    }
  }

  get(key: string): string | null {
    if (this.isAvailable) {
      try {
        return localStorage.getItem(key);
      } catch {
        return this.memory[key] || null;
      }
    }
    return this.memory[key] || null;
  }

  set(key: string, value: string): void {
    if (this.isAvailable) {
      try {
        localStorage.setItem(key, value);
      } catch {
        /* ignore quota / access errors */
      }
    }
    this.memory[key] = value;
  }

  remove(key: string): void {
    if (this.isAvailable) {
      try {
        localStorage.removeItem(key);
      } catch {
        /* ignore */
      }
    }
    delete this.memory[key];
  }
}

export const storage = new SafeStorage();
