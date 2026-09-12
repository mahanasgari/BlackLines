import { useEffect, useState } from "react";
import { api } from "@/api";
import { Input } from "@/components/ui/input";
import { cn, faNum } from "@/lib/utils";

export type FamilyOptions = {
  enabled: boolean;
  min_size: number;
  max_size: number;
  extra_discount_percent: number;
};

export type GrowthQuotePreview = {
  charge_toman: number;
  charge_label: string;
  discount_toman: number;
  bonus_days: number;
  family_size: number;
  promo_code: string | null;
};

export function ShopGrowthControls({
  planId,
  custom,
  familySize,
  onFamilySizeChange: _onFamilySizeChange,
  promoCode,
  onPromoCodeChange,
  onPreview,
  disabled,
  embedded,
}: {
  planId?: number;
  custom?: {
    duration_days: number;
    traffic_gb: number;
    limit_ip: number;
    unlimited: boolean;
  };
  familySize: number;
  onFamilySizeChange: (n: number) => void;
  promoCode: string;
  onPromoCodeChange: (v: string) => void;
  onPreview?: (preview: GrowthQuotePreview | null, error?: string | null) => void;
  disabled?: boolean;
  embedded?: boolean;
}) {
  const [checking, setChecking] = useState(false);
  const [hint, setHint] = useState<string | null>(null);
  const [hintError, setHintError] = useState(false);

  useEffect(() => {
    const code = promoCode.trim();
    if (!code) {
      setHint(familySize > 1 ? `پکیج خانواده: ${faNum(familySize)} کانفیگ` : null);
      setHintError(false);
      onPreview?.(null, null);
      return;
    }
    if (!planId && !custom) return;
    const t = window.setTimeout(() => {
      void (async () => {
        setChecking(true);
        try {
          const res = await api.validatePromo({
            code,
            plan_id: planId,
            family_size: familySize,
            ...(custom || {}),
          });
          const parts: string[] = [];
          if (res.discount_toman > 0) parts.push(`تخفیف ${faNum(res.discount_toman)} تومان`);
          if (res.bonus_days > 0) parts.push(`${faNum(res.bonus_days)} روز هدیه`);
          if (res.family_size > 1) parts.push(`${faNum(res.family_size)} کانفیگ`);
          parts.push(`مبلغ: ${res.charge_label}`);
          setHint(parts.join(" · "));
          setHintError(false);
          onPreview?.(
            {
              charge_toman: res.charge_toman,
              charge_label: res.charge_label,
              discount_toman: res.discount_toman,
              bonus_days: res.bonus_days,
              family_size: res.family_size,
              promo_code: res.promo_code,
            },
            null,
          );
        } catch (e) {
          const msg = e instanceof Error ? e.message : "کد نامعتبر";
          setHint(msg);
          setHintError(true);
          onPreview?.(null, msg);
        } finally {
          setChecking(false);
        }
      })();
    }, 350);
    return () => window.clearTimeout(t);
  }, [promoCode, familySize, planId, custom?.duration_days, custom?.traffic_gb, custom?.limit_ip, custom?.unlimited]);

  return (
    <div className={cn("space-y-2", !embedded && "rounded-xl border border-white/10 bg-black/25 px-3 py-2.5")}>
      <div className="space-y-1">
        <div className="text-[12px] font-medium text-neutral-200">کد تخفیف هنگام خرید</div>
        <Input
          value={promoCode}
          onChange={(e) => onPromoCodeChange(e.target.value.toUpperCase())}
          dir="ltr"
          placeholder="اختیاری"
          disabled={disabled}
          className="h-9 rounded-lg border-white/15 bg-black/40 font-mono text-sm"
        />
      </div>

      {checking ? (
        <p className="text-[10px] text-neutral-500">در حال بررسی…</p>
      ) : hint ? (
        <p className={cn("text-[10px]", hintError ? "text-rose-300" : "text-emerald-300/90")}>{hint}</p>
      ) : null}
    </div>
  );
}
