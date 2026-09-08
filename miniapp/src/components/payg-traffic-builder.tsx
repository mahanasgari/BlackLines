import { useCallback, useEffect, useMemo, useState } from "react";
import { Gauge } from "lucide-react";
import { api, haptic, type PaygOptions, type PaygQuote } from "@/api";
import { TgButton } from "@/components/tg-button";
import { cn, faNum } from "@/lib/utils";

function priceText(toman: number) {
  return `${faNum(toman)} تومان`;
}

function clamp(n: number, min: number, max: number) {
  return Math.min(max, Math.max(min, n));
}

function PresetChip({
  label,
  active,
  onClick,
}: {
  label: string;
  active?: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "h-8 rounded-lg border px-2.5 text-[11px] font-medium transition-colors",
        active
          ? "border-white/30 bg-white/15 text-white"
          : "border-white/10 bg-black/30 text-neutral-400 active:bg-white/10",
      )}
    >
      {label}
    </button>
  );
}

export function PaygTrafficBuilder({
  busy,
  isPro,
  lockTargetId,
  submitLabel,
  customerMeta,
  recipientIncomplete,
  onReview,
  onCheckout,
}: {
  busy?: boolean;
  isPro?: boolean;
  lockTargetId?: number;
  submitLabel?: string;
  customerMeta?: import("@/api").CustomerMeta;
  recipientIncomplete?: boolean;
  onReview?: (draft: {
    title: string;
    traffic_gb: number;
    limit_ip: number;
    charge_label?: string;
  }) => void;
  onCheckout: (order: Awaited<ReturnType<typeof api.paygOrder>>) => void | Promise<void>;
}) {
  const [opts, setOpts] = useState<PaygOptions | null>(null);
  const [gb, setGb] = useState(10);
  const [limitIp, setLimitIp] = useState(1);
  const [targetId, setTargetId] = useState<number | 0>(0);
  const [quote, setQuote] = useState<PaygQuote | null>(null);
  const [quoteLoading, setQuoteLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    void api.paygOptions().then((data) => {
      setOpts(data);
      setGb(clamp(10, data.min_gb, data.max_gb));
      setLimitIp(clamp(1, data.min_ip, data.max_ip));
      if (lockTargetId) setTargetId(lockTargetId);
    });
  }, [lockTargetId]);

  const gbPresets = useMemo(() => {
    if (!opts) return [];
    return [5, 10, 20, 50, 100].filter((g) => g >= opts.min_gb && g <= opts.max_gb);
  }, [opts]);

  const fetchQuote = useCallback(async () => {
    if (!opts?.enabled) return;
    setQuoteLoading(true);
    setError(null);
    try {
      setQuote(
        await api.paygQuote({
          traffic_gb: gb,
          limit_ip: limitIp,
          target_subscription_id: targetId || lockTargetId || undefined,
        }),
      );
    } catch (e) {
      setQuote(null);
      setError(e instanceof Error ? e.message : "خطا در محاسبه قیمت");
    } finally {
      setQuoteLoading(false);
    }
  }, [opts?.enabled, gb, limitIp, targetId, lockTargetId]);

  useEffect(() => {
    if (!opts?.enabled) return;
    const t = window.setTimeout(() => void fetchQuote(), 250);
    return () => window.clearTimeout(t);
  }, [opts?.enabled, fetchQuote]);

  const buy = async () => {
    if (!opts?.enabled) return;
    if (recipientIncomplete) {
      setError("بالا مشخص کن این کانفیگ برای کیست و نام مشتری را بنویس.");
      return;
    }
    haptic("medium");
    if (onReview && !targetId && !lockTargetId) {
      onReview({
        title: quote?.title || "خرید حجم",
        traffic_gb: gb,
        limit_ip: limitIp,
        charge_label: quote?.charge_label,
      });
      return;
    }
    try {
      const order = await api.paygOrder({
        traffic_gb: gb,
        limit_ip: limitIp,
        target_subscription_id: targetId || undefined,
        ...(targetId ? {} : customerMeta || {}),
      });
      await onCheckout(order);
    } catch (e) {
      setError(e instanceof Error ? e.message : "خرید ناموفق");
    }
  };

  if (!opts) {
    return <div className="py-8 text-center text-sm text-neutral-500">در حال بارگذاری…</div>;
  }

  if (!opts.enabled) {
    return (
      <div className="rounded-xl border border-white/10 bg-black/30 px-4 py-6 text-center text-sm text-neutral-400">
        خرید حجم فعلاً غیرفعال است.
      </div>
    );
  }

  const existing = opts.existing || [];

  return (
    <div className="space-y-4 rounded-2xl border border-white/12 bg-black/45 p-4">
      <div className="flex items-start gap-2">
        <Gauge className="mt-0.5 size-4 shrink-0 text-violet-300" />
        <div>
          <h3 className="font-semibold text-white">خرید حجم</h3>
          <p className="mt-0.5 text-[11px] leading-relaxed text-neutral-400">
            فقط ترافیک بخرید — بدون محدودیت زمانی (قیمت بالاتر از مصرف ابری). هر وقت تمام شد دوباره شارژ کنید.
          </p>
        </div>
      </div>

      {!lockTargetId && existing.length > 0 && (
        <div className="space-y-1.5">
          <div className="text-[12px] text-neutral-400">افزودن به کانفیگ فعلی</div>
          <select
            value={targetId}
            onChange={(e) => setTargetId(Number(e.target.value))}
            className="w-full rounded-lg border border-white/12 bg-black/40 px-3 py-2.5 text-sm text-white outline-none focus:border-white/25"
          >
            <option value={0}>کانفیگ حجم‌دار جدید</option>
            {existing.map((s) => (
              <option key={s.id} value={s.id}>
                {(s.label?.trim() || s.plan_title) + " · " + s.email}
              </option>
            ))}
          </select>
        </div>
      )}

      <div className="space-y-2">
        <div className="flex flex-wrap gap-1.5">
          {gbPresets.map((g) => (
            <PresetChip key={g} label={`${faNum(g)} GB`} active={gb === g} onClick={() => setGb(g)} />
          ))}
        </div>
        <div className="flex items-center justify-between gap-2">
          <span className="text-[12px] text-neutral-400">حجم ترافیک</span>
          <div className="flex items-center gap-1.5">
            <input
              type="number"
              inputMode="numeric"
              min={opts.min_gb}
              max={opts.max_gb}
              step={1}
              value={gb}
              onChange={(e) => setGb(clamp(Number(e.target.value) || opts.min_gb, opts.min_gb, opts.max_gb))}
              className="h-8 w-16 rounded-lg border border-white/12 bg-black/40 px-2 text-center text-sm tabular-nums text-white outline-none focus:border-white/25"
              dir="ltr"
            />
            <span className="text-[11px] text-neutral-500">GB</span>
          </div>
        </div>
        <input
          type="range"
          min={opts.min_gb}
          max={opts.max_gb}
          step={1}
          value={gb}
          onChange={(e) => setGb(Number(e.target.value))}
          className="h-1.5 w-full cursor-pointer accent-violet-300"
        />
      </div>

      {!targetId && (
        <div className="space-y-2">
          <div className="text-[12px] text-neutral-400">تعداد دستگاه (IP)</div>
          <div className="flex flex-wrap gap-1.5">
            {Array.from({ length: opts.max_ip - opts.min_ip + 1 }, (_, i) => opts.min_ip + i).map((n) => (
              <PresetChip key={n} label={faNum(n)} active={limitIp === n} onClick={() => setLimitIp(n)} />
            ))}
          </div>
        </div>
      )}

      <div className="rounded-xl border border-white/10 bg-black/30 px-3 py-3">
        {quoteLoading && !quote ? (
          <p className="text-center text-[11px] text-neutral-500">در حال محاسبه قیمت…</p>
        ) : quote ? (
          <div className="space-y-1">
            <div className="text-[11px] text-neutral-500">
              {targetId ? `شارژ ${faNum(gb)} گیگ روی کانفیگ فعلی` : quote.title}
            </div>
            <div className="flex items-end justify-between gap-2">
              <div>
                {quote.pro_discount_percent > 0 && quote.charge_toman < quote.price_toman ? (
                  <>
                    <div className="text-[10px] text-neutral-500 line-through">{quote.price_label}</div>
                    <div className="text-lg font-bold tabular-nums text-emerald-300">{quote.charge_label}</div>
                  </>
                ) : (
                  <div className="text-lg font-bold tabular-nums">{quote.charge_label}</div>
                )}
              </div>
              {quote.pay_after_wallet < quote.charge_toman && (
                <div className="text-end text-[10px] text-neutral-500">با کیف‌پول: {priceText(quote.pay_after_wallet)}</div>
              )}
            </div>
          </div>
        ) : null}
        {error ? <p className="mt-2 text-[11px] text-red-300">{error}</p> : null}
      </div>

      {!isPro && (quote?.pro_discount_percent ?? 0) > 0 && (
        <p className="text-[11px] text-amber-400/90">با Pro ارزان‌تر — دکمه Pro در بالا</p>
      )}

      <TgButton disabled={busy || quoteLoading || !quote || recipientIncomplete} onClick={() => void buy()}>
        {submitLabel || (targetId ? "شارژ ترافیک و پرداخت" : "خرید کانفیگ حجم‌دار")}
      </TgButton>
    </div>
  );
}
