import { Check, Crown, Lock, Sparkles } from "lucide-react";
import { MetalFx } from "metal-fx";
import type { ProInfo } from "@/api";
import { TgButton } from "@/components/tg-button";
import { cn, faNum } from "@/lib/utils";
import { useTheme } from "@/lib/theme";

function Panel({
  children,
  className,
  tone = "default",
}: {
  children: React.ReactNode;
  className?: string;
  tone?: "default" | "hero" | "muted";
}) {
  const { theme } = useTheme();
  const light = theme === "light";

  return (
    <div
      className={cn(
        "rounded-2xl border p-4 backdrop-blur-md",
        light
          ? cn(
              tone === "hero" &&
                "border-neutral-900/15 bg-gradient-to-b from-neutral-100 to-white shadow-[0_2px_12px_rgba(0,0,0,0.06)]",
              tone === "default" &&
                "border-neutral-900/12 bg-white shadow-[0_1px_3px_rgba(0,0,0,0.04)]",
              tone === "muted" && "border-neutral-300 bg-neutral-50 text-neutral-600 shadow-sm",
            )
          : cn(
              "border-white/12 bg-black/45",
              tone === "hero" && "border-white/18",
              tone === "muted" && "text-neutral-400",
            ),
        className,
      )}
    >
      {children}
    </div>
  );
}

export function ProUpgradeButton({
  label,
  disabled,
  onClick,
}: {
  label: string;
  disabled?: boolean;
  onClick: () => void;
}) {
  const { theme } = useTheme();
  const light = theme === "light";

  const button = (
    <button
      type="button"
      disabled={disabled}
      onClick={onClick}
      data-keep-dark
      className={cn(
        "relative w-full rounded-2xl border border-white/15 bg-gradient-to-b from-neutral-900 to-black px-4 py-3.5",
        "text-sm font-bold tracking-wide text-white shadow-lg",
        "disabled:cursor-not-allowed disabled:opacity-50",
        "active:scale-[0.99] transition-transform",
        light && "shadow-[0_4px_14px_rgba(0,0,0,0.18)]",
      )}
    >
      <span className="inline-flex items-center justify-center gap-2">
        <Crown className="size-4 text-amber-300" aria-hidden />
        {label}
      </span>
    </button>
  );

  if (light) return <div className="block w-full">{button}</div>;

  return (
    <MetalFx preset="silver" strength={0.85} theme="dark" className="block w-full">
      {button}
    </MetalFx>
  );
}

export function ProPanel({
  data,
  busy,
  onBuy,
}: {
  data: ProInfo | null;
  busy?: boolean;
  onBuy: () => void;
}) {
  const { theme } = useTheme();
  const light = theme === "light";

  if (!data) {
    return (
      <Panel className={cn("py-10 text-center text-sm", light ? "text-neutral-500" : "text-neutral-400")}>
        در حال بارگذاری Pro…
      </Panel>
    );
  }

  const active = data.is_pro;
  const manyConfigs = data.config_count >= 3;

  return (
    <div className="space-y-3 pb-1">
      <Panel tone="hero" className="relative overflow-hidden">
        {!light && (
          <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_top,rgba(255,255,255,0.08),transparent_55%)]" />
        )}
        <div className="relative space-y-3">
          <div className="flex items-start justify-between gap-3">
            <div>
              <div
                className={cn(
                  "inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-[11px] font-semibold",
                  light
                    ? "border-neutral-300 bg-neutral-100 text-neutral-900"
                    : "border-white/20 bg-white/10 text-neutral-100",
                )}
              >
                <Crown className={cn("size-3.5", light ? "text-[#eab308]" : "text-amber-300")} aria-hidden />
                Black Lines Pro
              </div>
              <h2
                className={cn(
                  "mt-2 text-lg font-extrabold tracking-tight",
                  light ? "text-neutral-950" : "text-neutral-100",
                )}
              >
                {active ? "عضو Pro هستید" : "ارتقا به Pro"}
              </h2>
              <p
                className={cn(
                  "mt-1 text-xs leading-relaxed",
                  light ? "text-neutral-600" : "text-neutral-400",
                )}
              >
                {active
                  ? `اعتبار تا ${data.pro_until_label || "—"} · ${faNum(data.discount_percent)}٪ تخفیف فعال`
                  : manyConfigs
                    ? `شما ${faNum(data.config_count)} کانفیگ دارید — Pro برای مدیریت و تخفیف ${faNum(data.discount_percent)}٪ مناسب‌تر است.`
                    : `با Pro روی هر خرید کانفیگ ${faNum(data.discount_percent)}٪ تخفیف بگیرید.`}
              </p>
            </div>
            <Sparkles
              className={cn("size-8 shrink-0", light ? "text-neutral-400" : "text-neutral-300/80")}
              aria-hidden
            />
          </div>

          {!active && (
            <div
              className={cn(
                "rounded-xl border px-3 py-2.5 text-center",
                light ? "border-neutral-900/12 bg-neutral-50" : "border-white/12 bg-black/25",
              )}
            >
              <div className={cn("text-[11px]", light ? "text-neutral-500" : "text-neutral-500")}>
                قیمت اشتراک
              </div>
              <div
                className={cn(
                  "mt-0.5 text-xl font-extrabold tabular-nums",
                  light ? "text-neutral-950" : "text-neutral-100",
                )}
              >
                {data.plan.price_label}
              </div>
              <div className={cn("text-[11px]", light ? "text-neutral-500" : "text-neutral-400")}>
                {faNum(data.plan.duration_days)} روز
              </div>
            </div>
          )}

          {!active ? (
            <ProUpgradeButton label="خرید اشتراک Pro" disabled={busy} onClick={onBuy} />
          ) : (
            <TgButton variant="outline" disabled={busy} onClick={onBuy}>
              تمدید Pro
            </TgButton>
          )}
        </div>
      </Panel>

      <Panel tone="default" className="space-y-3">
        <h3 className={cn("text-sm font-semibold", light ? "text-neutral-950" : "text-neutral-100")}>
          مزایای Pro
        </h3>
        <div className="space-y-2">
          {data.benefits.map((b) => (
            <div
              key={b.id}
              className={cn(
                "flex items-start gap-3 rounded-xl border px-3 py-2.5",
                b.active
                  ? light
                    ? "border-neutral-900/20 bg-neutral-100"
                    : "border-white/18 bg-white/8"
                  : light
                    ? "border-neutral-200 bg-white"
                    : "border-white/10 bg-black/25",
              )}
            >
              <span
                className={cn(
                  "mt-0.5 grid size-7 shrink-0 place-items-center rounded-lg",
                  b.active
                    ? light
                      ? "bg-neutral-900 text-[#f5f5f5]"
                      : "bg-white/15 text-neutral-100"
                    : light
                      ? "bg-neutral-100 text-neutral-400"
                      : "bg-white/8 text-neutral-500",
                )}
              >
                {b.active ? <Check className="size-3.5" /> : <Lock className="size-3.5" />}
              </span>
              <div className="min-w-0 flex-1">
                <div className={cn("text-sm font-medium", light ? "text-neutral-900" : "text-neutral-100")}>
                  {b.title}
                </div>
                <div
                  className={cn(
                    "mt-0.5 text-[11px] leading-relaxed",
                    light ? "text-neutral-600" : "text-neutral-400",
                  )}
                >
                  {b.description}
                </div>
                {b.coming_soon && (
                  <div
                    className={cn(
                      "mt-1 text-[10px] font-medium",
                      light ? "text-neutral-500" : "text-neutral-400",
                    )}
                  >
                    با فعال‌سازی Pro
                  </div>
                )}
              </div>
            </div>
          ))}
        </div>
      </Panel>

      <Panel tone="muted" className="space-y-2 text-[11px] leading-relaxed">
        <p>
          <strong className={light ? "text-neutral-900" : "text-neutral-200"}>تخفیف کانفیگ:</strong> در
          فروشگاه، قیمت نهایی با {faNum(data.discount_percent)}٪ تخفیف برای اعضای Pro نمایش داده می‌شود.
        </p>
        <p>
          <strong className={light ? "text-neutral-900" : "text-neutral-200"}>برای همه:</strong> هر کاربری
          می‌تواند Pro بخرد؛ اگر کانفیگ‌های زیادی دارید بیشتر به‌صرفه است.
        </p>
      </Panel>
    </div>
  );
}
