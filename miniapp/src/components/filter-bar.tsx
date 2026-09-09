import { motion, useReducedMotion } from "motion/react";
import { cn } from "@/lib/utils";

export function FilterBar<T extends string | number>({
  items,
  value,
  onChange,
}: {
  items: { id: T; label: string }[];
  value: T;
  onChange: (id: T) => void;
}) {
  const reduce = useReducedMotion() ?? false;

  return (
    <div
      role="tablist"
      aria-label="فیلتر پلن‌ها"
      className="flex gap-1.5 overflow-x-auto py-0.5 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
    >
      {items.map((item) => {
        const active = item.id === value;
        return (
          <button
            key={String(item.id)}
            type="button"
            role="tab"
            aria-selected={active}
            onClick={() => onChange(item.id)}
            className={cn(
              "relative h-8 shrink-0 rounded-full px-3.5 text-xs font-semibold",
              active ? "text-primary-foreground" : "border border-white/15 bg-black/40 text-neutral-400",
            )}
          >
            {active &&
              (reduce ? (
                <span className="absolute inset-0 rounded-full bg-primary" />
              ) : (
                <motion.span
                  layoutId="shop-filter-pill"
                  className="absolute inset-0 rounded-full bg-primary shadow-[0_0_12px_rgba(26,24,22,0.12)]"
                  transition={{ type: "spring", stiffness: 420, damping: 34, mass: 0.55 }}
                />
              ))}
            <span className="relative z-10 whitespace-nowrap">{item.label}</span>
          </button>
        );
      })}
    </div>
  );
}
