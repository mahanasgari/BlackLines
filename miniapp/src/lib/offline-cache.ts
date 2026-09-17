/** Lightweight localStorage cache so wallet/configs still open if Telegram WebView flakes. */

const PREFIX = "vpnshop:cache:v1:";
const DEFAULT_TTL_MS = 15 * 60 * 1000;

type CacheEnvelope<T> = {
  saved_at: number;
  ttl_ms: number;
  data: T;
};

function key(part: string) {
  return `${PREFIX}${part}`;
}

export function cacheSet<T>(part: string, data: T, ttlMs = DEFAULT_TTL_MS): void {
  try {
    const envelope: CacheEnvelope<T> = {
      saved_at: Date.now(),
      ttl_ms: ttlMs,
      data,
    };
    localStorage.setItem(key(part), JSON.stringify(envelope));
  } catch {
    /* quota / private mode */
  }
}

export function cacheGet<T>(part: string): { data: T; stale: boolean; age_ms: number } | null {
  try {
    const raw = localStorage.getItem(key(part));
    if (!raw) return null;
    const envelope = JSON.parse(raw) as CacheEnvelope<T>;
    if (!envelope || typeof envelope.saved_at !== "number") return null;
    const age = Date.now() - envelope.saved_at;
    const stale = age > (envelope.ttl_ms || DEFAULT_TTL_MS);
    return { data: envelope.data, stale, age_ms: age };
  } catch {
    return null;
  }
}

export function cacheClear(...parts: string[]): void {
  try {
    if (!parts.length) {
      const kill: string[] = [];
      for (let i = 0; i < localStorage.length; i++) {
        const k = localStorage.key(i);
        if (k?.startsWith(PREFIX)) kill.push(k);
      }
      kill.forEach((k) => localStorage.removeItem(k));
      return;
    }
    for (const part of parts) {
      localStorage.removeItem(key(part));
    }
  } catch {
    /* ignore */
  }
}

export const CacheKeys = {
  me: "me",
  plans: "plans",
  wallet: "wallet",
  subscriptions: "subscriptions",
  dashboard: "dashboard",
} as const;
