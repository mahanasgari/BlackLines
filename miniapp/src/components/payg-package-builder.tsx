import { useCallback, useEffect, useState } from "react";
import { Gauge, Wallet } from "lucide-react";
import { api, haptic, type PaygStatus } from "@/api";
import { TgButton } from "@/components/tg-button";
import { faNum } from "@/lib/utils";

export function PaygPackageBuilder({
  busy,
  isPro,
  compact,
  onActivated,
  onTopup,
}: {
  busy?: boolean;
  isPro?: boolean;
  compact?: boolean;
  onActivated?: () => void | Promise<void>;
  onTopup?: () => void;
}) {
  const [status, setStatus] = useState<PaygStatus | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [acting, setActing] = useState(false);

  const load = useCallback(async () => {
    setError(null);
    try {
      setStatus(await api.paygStatus());
    } catch (e) {
      setError(e instanceof Error ? e.message : "خطا در بارگذاری مصرفی");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const activate = async () => {
    haptic("medium");
    setActing(true);
    setError(null);
    try {
      const result = await api.paygActivate();
      setStatus(result);
      await onActivated?.();
    } catch (e) {
      setError(e instanceof Error ? e.message : "فعال‌سازی ناموفق");
    } finally {
      setActing(false);
    }
  };

  const setEnabled = async (enabled: boolean) => {
    haptic("medium");
    setActing(true);
    setError(null);
    try {
      const result = await api.paygSetEnabled(enabled);
      setStatus(result);
    } catch (e) {
      setError(e instanceof Error ? e.message : enabled ? "فعال‌سازی ناموفق" : "غیرفعال‌سازی ناموفق");
    } finally {
      setActing(false);
    }
  };

  if (loading && !status) {
    return <div className="py-8 text-center text-sm text-neutral-500">در حال بارگذاری…</div>;
  }

  if (!status?.enabled) {
    return (
      <div className="rounded-xl border border-white/10 bg-black/30 px-4 py-6 text-center text-sm text-neutral-400">
        پرداخت مصرفی فعلاً غیرفعال است.
      </div>
    );
  }

  const sub = status.subscription;
  const disabled = busy || acting;

  return (
    <div className="space-y-4 rounded-2xl border border-white/12 bg-black/45 p-4">
      {!compact ? (
        <div className="flex items-start gap-2">
          <Gauge className="mt-0.5 size-4 shrink-0 text-sky-300" />
          <div>
            <h3 className="font-semibold text-white">مصرفی ابری</h3>
            <p className="mt-0.5 text-[11px] leading-relaxed text-neutral-400">
              کیف‌پول را شارژ کنید، کانفیگ بگیرید، و فقط به‌اندازه مصرف واقعی پرداخت کنید.
              اگر ۱۰۰ مگ استفاده کنید، فقط قیمت همان ۱۰۰ مگ کسر می‌شود.
            </p>
          </div>
        </div>
      ) : null}

      <div className="grid grid-cols-2 gap-2">
        <div className="rounded-xl border border-white/10 bg-black/30 px-3 py-2.5">
          <div className="text-[10px] text-neutral-500">قیمت هر گیگ</div>
          <div className="mt-0.5 text-sm font-semibold tabular-nums text-sky-100">
            {status.unit_price_label}
          </div>
          {status.pro_discount_percent > 0 && status.unit_price_toman < status.price_per_gb_toman ? (
            <div className="text-[10px] text-neutral-500 line-through">{status.price_per_gb_label}</div>
          ) : null}
        </div>
        <div className="rounded-xl border border-white/10 bg-black/30 px-3 py-2.5">
          <div className="text-[10px] text-neutral-500">مثال ۱۰۰ مگ</div>
          <div className="mt-0.5 text-sm font-semibold tabular-nums text-emerald-200">
            {status.example_100mb_label}
          </div>
        </div>
        <div className="rounded-xl border border-white/10 bg-black/30 px-3 py-2.5">
          <div className="text-[10px] text-neutral-500">موجودی کیف‌پول</div>
          <div className="mt-0.5 text-sm font-semibold tabular-nums">{status.wallet_label}</div>
        </div>
        <div className="rounded-xl border border-white/10 bg-black/30 px-3 py-2.5">
          <div className="text-[10px] text-neutral-500">حجم تقریبی باقی‌مانده</div>
          <div className="mt-0.5 text-sm font-semibold tabular-nums">{status.remaining_label}</div>
        </div>
      </div>

      {sub ? (
        <div className="space-y-2 rounded-xl border border-sky-500/20 bg-sky-500/8 px-3 py-3">
          <div className="flex items-center justify-between gap-2">
            <div className="text-xs font-semibold text-sky-100">
              {sub.label?.trim() || sub.plan_title}
            </div>
            <span className="text-[10px] text-neutral-400">
              {status.user_paused
                ? "غیرفعال (دستی)"
                : status.suspended
                  ? "قطع شده"
                  : sub.enabled
                    ? "فعال"
                    : "غیرفعال"}
            </span>
          </div>
          <div className="grid grid-cols-2 gap-2 text-[11px] text-neutral-300">
            <div>
              مصرف شده: <span className="tabular-nums text-white">{status.used_label}</span>
            </div>
            <div>
              کسر شده: <span className="tabular-nums text-white">{status.billed_label}</span>
            </div>
          </div>
          <p className="text-[10px] leading-relaxed text-neutral-500">
            لینک کانفیگ در داشبورد است. با هر مصرف، مبلغ همان حجم از کیف‌پول کم می‌شود.
          </p>
          {status.suspended ? (
            <p className="text-[11px] text-amber-300">
              کانفیگ به‌خاطر موجودی ناکافی قطع شده. بعد از شارژ کیف‌پول دوباره وصل می‌شود.
            </p>
          ) : null}
          {status.user_paused ? (
            <p className="text-[11px] text-neutral-400">
              خودتان غیرفعال کرده‌اید — با دکمه فعال‌سازی دوباره وصل می‌شود.
            </p>
          ) : null}
          <div className="grid grid-cols-2 gap-2">
            {sub.enabled ? (
              <TgButton
                variant="outline"
                disabled={disabled}
                className="border-red-500/25 text-red-300"
                onClick={() => void setEnabled(false)}
              >
                غیرفعال کردن
              </TgButton>
            ) : (
              <TgButton disabled={disabled || status.needs_topup} onClick={() => void setEnabled(true)}>
                فعال کردن
              </TgButton>
            )}
            <TgButton variant="outline" disabled={disabled} onClick={() => onTopup?.()}>
              <Wallet className="size-3.5" />
              شارژ کیف‌پول
            </TgButton>
          </div>
        </div>
      ) : (
        <div className="rounded-xl border border-white/10 bg-black/30 px-3 py-3 text-[11px] leading-relaxed text-neutral-400">
          حداقل موجودی برای فعال‌سازی: {status.min_wallet_label} · حداکثر {faNum(status.limit_ip)} دستگاه
        </div>
      )}

      {!isPro && status.pro_discount_percent > 0 ? (
        <p className="text-[11px] text-amber-400/90">با Pro هر گیگ ارزان‌تر حساب می‌شود</p>
      ) : null}

      {error ? <p className="text-[11px] text-red-300">{error}</p> : null}

      {!sub ? (
        status.can_activate ? (
          <TgButton disabled={disabled} onClick={() => void activate()}>
            فعال‌سازی کانفیگ مصرفی
          </TgButton>
        ) : (
          <TgButton disabled={disabled} onClick={() => onTopup?.()}>
            <Wallet className="size-3.5" />
            شارژ کیف‌پول و ادامه
          </TgButton>
        )
      ) : null}
    </div>
  );
}
