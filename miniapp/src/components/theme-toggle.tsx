import { Moon, Sun } from "lucide-react";
import { haptic } from "@/api";
import { useTheme } from "@/lib/theme";
import { cn } from "@/lib/utils";

export function ThemeToggle({
  className,
  variant = "icon",
}: {
  className?: string;
  variant?: "icon" | "row";
}) {
  const { theme, toggleTheme } = useTheme();
  const isLight = theme === "light";

  if (variant === "row") {
    return (
      <button
        type="button"
        onClick={() => {
          haptic();
          toggleTheme();
        }}
        className={cn(
          "flex w-full items-center justify-between gap-3 rounded-2xl border border-white/12 bg-white/5 px-4 py-3.5 text-start active:bg-white/10",
          className,
        )}
        aria-label={isLight ? "حالت تاریک" : "حالت روشن"}
      >
        <span className="min-w-0">
          <span className="block text-sm font-semibold">ظاهر برنامه</span>
          <span className="mt-0.5 block text-[11px] text-neutral-400">
            {isLight ? "حالت روشن فعال است" : "حالت تاریک فعال است"}
          </span>
        </span>
        <span className="inline-flex size-9 shrink-0 items-center justify-center rounded-full border border-white/15 bg-black/40 text-neutral-200">
          {isLight ? <Moon className="size-4" aria-hidden /> : <Sun className="size-4" aria-hidden />}
        </span>
      </button>
    );
  }

  return (
    <button
      type="button"
      onClick={() => {
        haptic();
        toggleTheme();
      }}
      className={cn(
        "inline-flex size-9 items-center justify-center rounded-full border bg-black/60 text-neutral-300 active:bg-white/10",
        "border-white/15",
        className,
      )}
      aria-label={isLight ? "حالت تاریک" : "حالت روشن"}
      title={isLight ? "حالت تاریک" : "حالت روشن"}
    >
      {isLight ? <Moon className="size-4" aria-hidden /> : <Sun className="size-4" aria-hidden />}
    </button>
  );
}
