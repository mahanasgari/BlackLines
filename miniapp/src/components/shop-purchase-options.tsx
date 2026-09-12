import { useState, type ReactNode } from "react";
import { ChevronDown, SlidersHorizontal } from "lucide-react";
import { cn } from "@/lib/utils";

/** Collapsible bucket for promo / family / buy-for-others so the shop stays scannable. */
export function ShopPurchaseOptions({
  children,
  defaultOpen = false,
  badge,
  title = "گزینه‌های خرید",
  hint = "تخفیف، پکیج خانواده، یا خرید برای مشتری دیگر",
}: {
  children: ReactNode;
  defaultOpen?: boolean;
  badge?: string | null;
  title?: string;
  hint?: string;
}) {
  const [open, setOpen] = useState(defaultOpen);

  return (
    <section className="overflow-hidden rounded-xl border border-white/10 bg-black/25">
      <button
        type="button"
        className="flex w-full items-center justify-between gap-2 px-3 py-2.5 text-start active:bg-white/5"
        onClick={() => setOpen((v) => !v)}
        aria-expanded={open}
      >
        <span className="min-w-0">
          <span className="inline-flex items-center gap-1.5 text-xs font-semibold text-neutral-200">
            <SlidersHorizontal className="size-3.5 text-neutral-400" />
            {title}
            {badge ? (
              <span className="rounded-md border border-emerald-500/30 bg-emerald-500/10 px-1.5 py-0.5 text-[10px] font-medium text-emerald-200">
                {badge}
              </span>
            ) : null}
          </span>
          {!open ? <span className="mt-0.5 block text-[10px] text-neutral-500">{hint}</span> : null}
        </span>
        <ChevronDown className={cn("size-4 shrink-0 text-neutral-500 transition-transform", open && "rotate-180")} />
      </button>
      {open ? <div className="space-y-2.5 border-t border-white/8 px-3 pb-3 pt-2.5">{children}</div> : null}
    </section>
  );
}

export function ShopSectionIntro({
  title,
  description,
}: {
  title: string;
  description: string;
}) {
  return (
    <div className="px-0.5 pb-0.5">
      <h2 className="text-sm font-semibold text-white">{title}</h2>
      <p className="mt-0.5 text-[11px] leading-relaxed text-neutral-400">{description}</p>
    </div>
  );
}
