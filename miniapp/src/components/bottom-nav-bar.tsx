import { useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { cn, faNum } from "@/lib/utils";

export type BottomNavItem = {
  id: string;
  label: string;
  icon: ReactNode;
  badge?: boolean;
  badgeCount?: number;
  adminOnly?: boolean;
};

export function BottomNavBar({
  items,
  activeId,
  onChange,
  isAdmin,
}: {
  items: BottomNavItem[];
  activeId: string;
  onChange: (id: string) => void;
  isAdmin?: boolean;
}) {
  const visible = items.filter((t) => !t.adminOnly || isAdmin);
  const activeIndex = Math.max(
    0,
    visible.findIndex((t) => t.id === activeId),
  );
  const [pill, setPill] = useState<{ left: number; width: number } | null>(null);
  const rowRefs = useRef<(HTMLButtonElement | null)[]>([]);
  const trackRef = useRef<HTMLDivElement>(null);

  useLayoutEffect(() => {
    const btn = rowRefs.current[activeIndex];
    const track = trackRef.current;
    if (!btn || !track) return;
    const trackRect = track.getBoundingClientRect();
    const btnRect = btn.getBoundingClientRect();
    setPill({
      left: btnRect.left - trackRect.left,
      width: btnRect.width,
    });
  }, [activeIndex, visible.length, activeId]);

  return (
    <nav
      className="relative z-10 shrink-0 border-t border-white/10 bg-black/75 px-2 pt-1.5 backdrop-blur-md"
      style={{ paddingBottom: "max(0.45rem, env(safe-area-inset-bottom))" }}
    >
      <div ref={trackRef} className="relative grid gap-1" style={{ gridTemplateColumns: `repeat(${visible.length}, minmax(0, 1fr))` }}>
        <span
          aria-hidden
          className="pointer-events-none absolute top-0.5 bottom-0.5 rounded-xl bg-white/12"
          style={{
            left: pill?.left ?? 0,
            width: pill?.width ?? 0,
            opacity: pill ? 1 : 0,
            transition: "left 260ms cubic-bezier(0.23,1,0.32,1), width 260ms cubic-bezier(0.23,1,0.32,1), opacity 120ms ease",
          }}
        />
        {visible.map((t, i) => {
          const active = t.id === activeId;
          const count = t.badgeCount ?? 0;
          return (
            <button
              key={t.id}
              type="button"
              ref={(el) => {
                rowRefs.current[i] = el;
              }}
              onClick={() => onChange(t.id)}
              className={cn(
                "relative z-10 flex min-h-[3rem] flex-col items-center justify-center gap-0.5 rounded-xl px-1 text-[10.5px] font-medium transition-colors duration-150",
                active ? "text-white" : "text-neutral-500 active:text-neutral-300",
              )}
            >
              <span className="relative">
                {t.icon}
                {t.badge && (
                  <span
                    className={cn(
                      "absolute -end-1.5 -top-1 rounded-full bg-primary text-primary-foreground",
                      count > 0 ? "min-w-[0.9rem] px-0.5 text-[8px] font-bold leading-4" : "size-1.5",
                    )}
                  >
                    {count > 0 ? faNum(Math.min(count, 99)) : null}
                  </span>
                )}
              </span>
              <span>{t.label}</span>
            </button>
          );
        })}
      </div>
    </nav>
  );
}
