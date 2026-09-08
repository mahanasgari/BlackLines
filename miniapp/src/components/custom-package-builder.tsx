import { useCallback, useEffect, useMemo, useState } from "react";
import { Sparkles } from "lucide-react";
import { api, haptic, type CustomPackageOptions, type CustomPackageQuote } from "@/api";
import { FamilyPackPanel } from "@/components/family-pack-panel";
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

function FieldControl({
  label,
  value,
  min,
  max,
  step,
  suffix,
  onChange,
}: {
  label: string;
  value: number;
  min: number;
  max: number;
  step: number;
  suffix: string;
  onChange: (v: number) => void;
}) {
  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between gap-2">
        <span className="text-[12px] text-neutral-400">{label}</span>
        <div className="flex items-center gap-1.5">
          <input
            type="number"
            inputMode="numeric"
            min={min}
            max={max}
            step={step}
            value={value}
            onChange={(e) => onChange(clamp(Number(e.target.value) || min, min, max))}
            className="h-8 w-16 rounded-lg border border-white/12 bg-black/40 px-2 text-center text-sm tabular-nums text-white outline-none focus:border-white/25"
            dir="ltr"
          />
          <span className="text-[11px] text-neutral-500">{suffix}</span>
        </div>
      </div>
      <input
        type="range"
        min={min}
        max={max}
        step={step}
        value={value}
        onChange={(e) => onChange(Number(e.target.value))}
        className="h-1.5 w-full cursor-pointer accent-white"
      />
      <div className="flex justify-between text-[10px] text-neutral-600">
        <span>
          {faNum(min)} {suffix}
        </span>
        <span>
          {faNum(max)} {suffix}
        </span>
      </div>
    </div>
  );
}

export function CustomPackageBuilder({
  busy,
  isPro,
  targetSubscriptionId,
  submitLabel,
  customerMeta,
  recipientIncomplete,
  onReview,
  onCheckout,
}: {
  busy: boolean;
  isPro?: boolean;
  targetSubscriptionId?: number;
  submitLabel?: string;
  customerMeta?: import("@/api").CustomerMeta;
  recipientIncomplete?: boolean;
  onReview?: (draft: {
    title: string;
    duration_days: number;
    traffic_gb: number;
    limit_ip: number;
    unlimited: boolean;
    familySize: number;
    charge_label?: string;
  }) => void;
  onCheckout: (order: Awaited<ReturnType<typeof api.customOrder>>) => void | Promise<void>;
}) {
  const [opts, setOpts] = useState<CustomPackageOptions | null>(null);
  const [days, setDays] = useState(30);
  const [gb, setGb] = useState(50);
  const [limitIp, setLimitIp] = useState(2);
  const [unlimited, setUnlimited] = useState(false);
  const [quote, setQuote] = useState<CustomPackageQuote | null>(null);
  const [quoteLoading, setQuoteLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [familySize, setFamilySize] = useState(1);
  const isRenew = Boolean(targetSubscriptionId);

  useEffect(() => {
    void api.customOptions().then((data) => {
      setOpts(data);
      setDays(clamp(30, data.min_days, data.max_days));
      setGb(clamp(50, data.min_gb, data.max_gb));
      setLimitIp(clamp(2, data.min_ip, data.max_ip));
      if (!data.unlimited_allowed) setUnlimited(false);
    });
  }, []);

  const dayPresets = useMemo(() => {
    if (!opts) return [];
    return [7, 30, 90, 180].filter((d) => d >= opts.min_days && d <= opts.max_days);
  }, [opts]);

  const gbPresets = useMemo(() => {
    if (!opts) return [];
    return [1, 5, 10, 50, 100, 200, 500].filter((g) => g >= opts.min_gb && g <= opts.max_gb);
  }, [opts]);

  const fetchQuote = useCallback(async () => {
    if (!opts?.enabled) return;
    setQuoteLoading(true);
    setError(null);
    try {
      const data = await api.customQuote({
        duration_days: days,
        traffic_gb: gb,
        limit_ip: limitIp,
        unlimited,
        family_size: isRenew ? 1 : familySize,
      });
      setQuote(data);
    } catch (e) {
      setQuote(null);
      setError(e instanceof Error ? e.message : "خطا در محاسبه قیمت");
    } finally {
      setQuoteLoading(false);
    }
  }, [opts?.enabled, days, gb, limitIp, unlimited, familySize, isRenew]);

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
    if (onReview && !isRenew) {
      onReview({
        title: quote?.title || "پکیج سفارشی",
        duration_days: days,
        traffic_gb: gb,
        limit_ip: limitIp,
        unlimited,
        familySize,
        charge_label: quote?.charge_label,
      });
      return;
    }
    try {
      const order = await api.customOrder({
        duration_days: days,
        traffic_gb: gb,
        limit_ip: limitIp,
        unlimited,
        target_subscription_id: targetSubscriptionId,
        family_size: isRenew ? 1 : familySize,
        ...(isRenew ? {} : customerMeta || {}),
      });
      setFamilySize(1);
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
        ساخت پکیج سفارشی فعلاً غیرفعال است.
      </div>
    );
  }

  return (
    <div className="space-y-4 rounded-2xl border border-white/12 bg-black/45 p-4">
      <div className="flex items-start gap-2">
        <Sparkles className="mt-0.5 size-4 shrink-0 text-amber-300" />
        <div>
          <h3 className="font-semibold text-white">
            {targetSubscriptionId ? "تمدید با پکیج دلخواه" : "ساخت پکیج دلخواه"}
          </h3>
          <p className="mt-0.5 text-[11px] leading-relaxed text-neutral-400">
            مدت، حجم و تعداد دستگاه را خودتان انتخاب کنید. قیمت لحظه‌ای محاسبه می‌شود.
          </p>
        </div>
      </div>

      <div className="space-y-2">
        <div className="flex flex-wrap gap-1.5">
          {dayPresets.map((d) => (
            <PresetChip
              key={d}
              label={`${faNum(d)} روز`}
              active={days === d}
              onClick={() => setDays(d)}
            />
          ))}
        </div>
        <FieldControl
          label="مدت اشتراک"
          value={days}
          min={opts.min_days}
          max={opts.max_days}
          step={1}
          suffix="روز"
          onChange={setDays}
        />
      </div>

      <div className="space-y-2">
        <div className="flex flex-wrap gap-1.5">
          {gbPresets.map((g) => (
            <PresetChip
              key={g}
              label={`${faNum(g)} GB`}
              active={!unlimited && gb === g}
              onClick={() => {
                setUnlimited(false);
                setGb(g);
              }}
            />
          ))}
          {(opts.unlimited_allowed || isPro) && (
            <PresetChip
              label="نامحدود"
              active={unlimited}
              onClick={() => setUnlimited((v) => !v)}
            />
          )}
        </div>
        {unlimited ? (
          <div className="rounded-lg border border-amber-300/20 bg-amber-300/8 px-3 py-2 text-[11px] text-amber-200/90">
            حجم نامحدود فعال است — مخصوص اعضای Pro
          </div>
        ) : (
          <FieldControl
            label="حجم ترافیک"
            value={gb}
            min={opts.min_gb}
            max={opts.max_gb}
            step={1}
            suffix="GB"
            onChange={(v) => {
              setUnlimited(false);
              setGb(v);
            }}
          />
        )}
      </div>

      <FieldControl
        label="تعداد دستگاه (IP)"
        value={limitIp}
        min={opts.min_ip}
        max={opts.max_ip}
        step={1}
        suffix="دستگاه"
        onChange={setLimitIp}
      />

      {!isRenew ? (
        <FamilyPackPanel
          familySize={familySize}
          onFamilySizeChange={setFamilySize}
          disabled={busy}
        />
      ) : null}

      <div className="rounded-xl border border-white/10 bg-black/30 px-3 py-3">
        {quoteLoading && !quote ? (
          <p className="text-center text-[11px] text-neutral-500">در حال محاسبه قیمت…</p>
        ) : quote ? (
          <div className="space-y-1">
            <div className="text-[11px] text-neutral-500">{quote.title}</div>
            <div className="flex items-end justify-between gap-2">
              <div>
                {(quote.pro_discount_percent ?? 0) > 0 && quote.charge_toman < quote.price_toman ? (
                  <>
                    <div className="text-[10px] text-neutral-500 line-through">{quote.price_label}</div>
                    <div className="text-lg font-bold tabular-nums text-emerald-300">{quote.charge_label}</div>
                    <div className="text-[10px] text-emerald-400/90">
                      Pro · {faNum(quote.pro_discount_percent)}٪ تخفیف
                    </div>
                  </>
                ) : (
                  <div className="text-lg font-bold tabular-nums">{quote.charge_label}</div>
                )}
              </div>
              {quote.pay_after_wallet < quote.charge_toman && (
                <div className="text-end text-[10px] text-neutral-500">
                  با کیف‌پول: {priceText(quote.pay_after_wallet)}
                </div>
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
        {submitLabel
          ? familySize > 1
            ? `${submitLabel} · خانواده ${faNum(familySize)} کانفیگ`
            : submitLabel
          : targetSubscriptionId
            ? "تمدید سفارشی و پرداخت"
            : familySize > 1
              ? `خرید پکیج خانواده · ${faNum(familySize)} کانفیگ`
              : "خرید پکیج سفارشی"}
      </TgButton>
    </div>
  );
}
