import { Crown, Sparkles } from "lucide-react";
import { MetalFx } from "metal-fx";
import { cn } from "@/lib/utils";
import { useTheme } from "@/lib/theme";

export function ProHeaderEntry({
  isPro,
  onClick,
}: {
  isPro?: boolean;
  onClick: () => void;
}) {
  const { theme } = useTheme();
  const light = theme === "light";

  if (isPro) {
    const button = (
      <button
        type="button"
        onClick={onClick}
        aria-label="Black Lines Pro — جزئیات اشتراک"
        data-keep-dark
        className={cn(
          "relative inline-flex h-9 items-center gap-1.5 overflow-hidden rounded-full px-3",
          "border border-white/20 bg-gradient-to-b from-neutral-800 to-black",
          "text-[11px] font-extrabold uppercase tracking-[0.12em] text-white",
          "active:scale-[0.97] transition-transform",
          light && "shadow-[0_1px_6px_rgba(0,0,0,0.16)]",
        )}
      >
        <span
          aria-hidden
          className="pointer-events-none absolute inset-0 bg-[linear-gradient(105deg,transparent_35%,rgba(255,255,255,0.16)_50%,transparent_65%)]"
        />
        <Crown className="relative size-3.5 text-amber-300" aria-hidden />
        <span className="relative">Pro</span>
        <Sparkles className="relative size-3 text-neutral-300" aria-hidden />
      </button>
    );

    if (light) return button;
    return (
      <MetalFx preset="silver" strength={1} theme="dark" className="rounded-full">
        {button}
      </MetalFx>
    );
  }

  const upgrade = (
    <button
      type="button"
      onClick={onClick}
      aria-label="ارتقا به Pro"
      {...(!light ? { "data-keep-dark": true } : {})}
      className={cn(
        "inline-flex h-9 items-center gap-1 rounded-full px-2.5",
        "text-[11px] font-bold active:scale-[0.97] transition-transform",
        light
          ? "border border-neutral-300 bg-white text-neutral-900 shadow-[0_1px_4px_rgba(0,0,0,0.08)]"
          : "border border-white/15 bg-gradient-to-b from-neutral-900 to-black text-white",
      )}
    >
      <Crown
        className={cn("size-3.5", light ? "text-[#eab308]" : "text-amber-300")}
        aria-hidden
      />
      Pro
    </button>
  );

  if (light) return upgrade;
  return (
    <MetalFx preset="silver" strength={0.8} theme="dark" className="rounded-full">
      {upgrade}
    </MetalFx>
  );
}
