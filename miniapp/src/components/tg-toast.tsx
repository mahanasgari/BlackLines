import { useCallback, useState } from "react";
import { cn } from "@/lib/utils";

export type ToastItem = {
  id: string;
  title: string;
  status?: "success" | "error" | "info";
};

export function useToasts(limit = 2) {
  const [toasts, setToasts] = useState<ToastItem[]>([]);

  const dismiss = useCallback((id: string) => {
    setToasts((t) => t.filter((x) => x.id !== id));
  }, []);

  const push = useCallback(
    (title: string, status: ToastItem["status"] = "info") => {
      const id = `t-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
      setToasts((current) => [...current, { id, title, status }].slice(-limit));
      window.setTimeout(() => {
        setToasts((t) => t.filter((x) => x.id !== id));
      }, 2600);
      return id;
    },
    [limit]
  );

  return { toasts, push, dismiss };
}

export function ToastHost({
  toasts,
  onDismiss,
}: {
  toasts: ToastItem[];
  onDismiss: (id: string) => void;
}) {
  if (!toasts.length) return null;

  return (
    <div className="pointer-events-none fixed inset-x-0 top-3 z-[60] flex flex-col items-center gap-2 px-3">
      {toasts.map((t) => (
        <button
          key={t.id}
          type="button"
          onClick={() => onDismiss(t.id)}
          className={cn(
            "pointer-events-auto max-w-sm rounded-xl border px-3 py-2 text-center text-xs font-medium shadow-lg backdrop-blur-md",
            t.status === "error"
              ? "border-neutral-800 bg-neutral-900 text-[#fafafa]"
              : "border-border bg-primary text-primary-foreground"
          )}
        >
          {t.title}
        </button>
      ))}
    </div>
  );
}
