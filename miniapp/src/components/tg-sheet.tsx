import { useEffect, useRef, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { X } from "lucide-react";
import { cn } from "@/lib/utils";

export function TgSheet({
  open,
  onClose,
  title,
  description,
  children,
  layer = 120,
}: {
  open: boolean;
  onClose: () => void;
  title: ReactNode;
  description?: string | null;
  children: ReactNode;
  layer?: number;
}) {
  const openedAt = useRef(0);

  useEffect(() => {
    if (!open) return;
    openedAt.current = Date.now();
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, onClose]);

  useEffect(() => {
    if (!open) return;
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = prev;
    };
  }, [open]);

  if (!open) return null;

  const closeFromBackdrop = () => {
    if (Date.now() - openedAt.current < 400) return;
    onClose();
  };

  return createPortal(
    <div className="fixed inset-0 flex items-end justify-center" style={{ zIndex: layer }}>
      <button
        type="button"
        aria-label="بستن"
        className="absolute inset-0 bg-black/65"
        onClick={closeFromBackdrop}
      />
      <div
        role="dialog"
        aria-modal="true"
        className={cn(
          "relative z-10 flex max-h-[85dvh] w-full max-w-lg flex-col",
          "rounded-t-2xl border border-white/15 border-b-0 bg-sheet shadow-2xl",
        )}
        style={{ paddingBottom: "max(0.75rem, env(safe-area-inset-bottom))" }}
      >
        <div className="flex items-start justify-between gap-3 border-b border-white/10 px-4 py-3">
          <div className="min-w-0">
            <h2 className="text-sm font-semibold text-white">{title}</h2>
            {description ? (
              <p className="mt-0.5 truncate font-mono text-[11px] text-neutral-400" dir="ltr">
                {description}
              </p>
            ) : null}
          </div>
          <button
            type="button"
            onClick={onClose}
            className="inline-flex size-9 shrink-0 items-center justify-center rounded-xl border border-white/15 text-neutral-300 active:bg-white/10"
          >
            <X className="size-4" />
          </button>
        </div>
        <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-3 py-3 [-webkit-overflow-scrolling:touch]">
          {children}
        </div>
      </div>
    </div>,
    document.body,
  );
}
