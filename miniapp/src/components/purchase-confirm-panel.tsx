import { useEffect, useState } from "react";
import { ArrowRight, BadgePercent, Pencil, ReceiptText } from "lucide-react";
import { api, type CustomerMeta, type Plan } from "@/api";
import {
  BuyForOthersPanel,
  customerMetaPayload,
  emptyCustomerMeta,
  isBuyForOthersComplete,
  recipientNameOf,
} from "@/components/buy-for-others-panel";
import { ShopGrowthControls } from "@/components/shop-growth-controls";
import { TgButton } from "@/components/tg-button";
import { faNum } from "@/lib/utils";

export type PurchaseDraft =
  | {
      kind: "plan";
      plan: Plan;
      familySize: number;
      giftCard?: boolean;
    }
  | {
      kind: "custom";
      title: string;
      duration_days: number;
      traffic_gb: number;
      limit_ip: number;
      unlimited: boolean;
      familySize: number;
      charge_label?: string;
    }
  | {
      kind: "payg";
      title: string;
      traffic_gb: number;
      limit_ip: number;
      charge_label?: string;
    };

export type PurchaseConfirmPayload = {
  promo_code?: string;
  config_label?: string;
  family_size: number;
  customer?: CustomerMeta;
  recipientName: string | null;
};

function priceText(toman: number) {
  return `${faNum(toman)} تومان`;
}

export function PurchaseConfirmPanel({
  draft,
  busy,
  onBack,
  onConfirm,
}: {
  draft: PurchaseDraft;
  busy?: boolean;
  onBack: () => void;
  onConfirm: (payload: PurchaseConfirmPayload) => void | Promise<void>;
}) {
  const [buyForOthers, setBuyForOthers] = useState(false);
  const [customer, setCustomer] = useState(() => emptyCustomerMeta());
  const [promoCode, setPromoCode] = useState("");
  const [configName, setConfigName] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [priceHint, setPriceHint] = useState<string | null>(draft.kind === "plan" ? priceText(draft.plan.charge_toman ?? draft.plan.price_toman) : draft.charge_label || null);

  const isGift = draft.kind === "plan" && Boolean(draft.giftCard);
  const familySize = draft.kind === "payg" || isGift ? 1 : draft.familySize;
  const title = draft.kind === "plan" ? `${isGift ? "کارت هدیه · " : ""}${draft.plan.title}` : draft.title;
  const defaultName = title;

  useEffect(() => {
    setConfigName("");
    setPromoCode("");
    setBuyForOthers(false);
    setCustomer(emptyCustomerMeta());
    setError(null);
  }, [draft]);

  useEffect(() => {
    if (draft.kind === "payg" || promoCode.trim()) return;
    let cancelled = false;
    void (async () => {
      try {
        if (draft.kind === "plan") {
          const res = await api.validatePromo({
            code: "",
            plan_id: draft.plan.id,
            family_size: familySize,
          });
          if (!cancelled) setPriceHint(res.charge_label);
          return;
        }
        const res = await api.customQuote({
          duration_days: draft.duration_days,
          traffic_gb: draft.traffic_gb,
          limit_ip: draft.limit_ip,
          unlimited: draft.unlimited,
          family_size: familySize,
        });
        if (!cancelled) setPriceHint(res.charge_label);
      } catch {
        /* keep fallback */
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [draft, familySize, promoCode]);

  const submit = () => {
    if (!isGift && !isBuyForOthersComplete(buyForOthers, customer)) {
      setError("اگر برای کس دیگری می‌خری، نامش را بنویس.");
      return;
    }
    const name = configName.trim();
    void onConfirm({
      promo_code: promoCode.trim() || undefined,
      config_label: name || undefined,
      family_size: familySize,
      customer: customerMetaPayload(customer, buyForOthers),
      recipientName: recipientNameOf(customer, buyForOthers),
    });
  };

  return (
    <div className="space-y-3">
      <button
        type="button"
        onClick={onBack}
        className="inline-flex items-center gap-1 text-[12px] text-neutral-400 active:text-white"
      >
        <ArrowRight className="size-3.5" />
        بازگشت به فروشگاه
      </button>

      <div>
        <h2 className="text-sm font-semibold text-white">تأیید خرید</h2>
        <p className="mt-0.5 text-[11px] leading-relaxed text-neutral-400">
          {isGift
            ? "بعد از پرداخت یک کد می‌گیری و می‌توانی در تلگرام بفرستی."
            : "مشخصات را چک کنید، اگر کد تخفیف دارید وارد کنید، و برای کانفیگ اسم بگذارید."}
        </p>
      </div>

      <section className="space-y-2.5 rounded-2xl border border-white/12 bg-black/35 p-3.5">
        <div className="inline-flex items-center gap-1.5 text-[12px] font-semibold text-neutral-100">
          <ReceiptText className="size-3.5 text-neutral-400" />
          ۱. تأیید مشخصات
        </div>
        <div className="rounded-xl border border-white/10 bg-white/5 px-3 py-2.5">
          <div className="text-sm font-semibold text-white">{title}</div>
          <p className="mt-1 text-[11px] leading-relaxed text-neutral-400">
            {draft.kind === "plan"
              ? `${faNum(draft.plan.duration_days)} روز · ${draft.plan.traffic_gb > 0 ? `${faNum(draft.plan.traffic_gb)} گیگ` : "نامحدود"} · ${faNum(draft.plan.limit_ip)} دستگاه`
              : draft.kind === "custom"
                ? `${faNum(draft.duration_days)} روز · ${draft.unlimited ? "حجم نامحدود" : `${faNum(draft.traffic_gb)} گیگ`} · ${faNum(draft.limit_ip)} دستگاه`
                : `${faNum(draft.traffic_gb)} گیگ · ${faNum(draft.limit_ip)} دستگاه`}
            {familySize > 1 ? ` · خانواده ${faNum(familySize)} کانفیگ` : ""}
          </p>
          {priceHint ? <div className="mt-2 text-sm font-bold tabular-nums text-white">{priceHint}</div> : null}
        </div>
        {isGift ? (
          <p className="rounded-xl border border-amber-400/20 bg-amber-500/10 px-3 py-2 text-[11px] leading-relaxed text-amber-100">
            این خرید کانفیگ روی حساب تو نمی‌سازد — فقط یک کد هدیه می‌دهد.
          </p>
        ) : (
          <BuyForOthersPanel
            enabled={buyForOthers}
            onEnabledChange={(v) => {
              setBuyForOthers(v);
              setError(null);
            }}
            value={customer}
            onChange={(next) => {
              setCustomer(next);
              setError(null);
            }}
            disabled={busy}
            error={error}
          />
        )}
      </section>

      {draft.kind !== "payg" && !isGift ? (
        <section className="space-y-2.5 rounded-2xl border border-white/12 bg-black/35 p-3.5">
          <div className="inline-flex items-center gap-1.5 text-[12px] font-semibold text-neutral-100">
            <BadgePercent className="size-3.5 text-neutral-400" />
            ۲. تخفیف
          </div>
          <p className="text-[11px] leading-relaxed text-neutral-500">
            تخفیف فروشگاه خودکار است. کد تخفیف اختیاری است.
          </p>
          <ShopGrowthControls
            planId={draft.kind === "plan" ? draft.plan.id : undefined}
            custom={
              draft.kind === "custom"
                ? {
                    duration_days: draft.duration_days,
                    traffic_gb: draft.traffic_gb,
                    limit_ip: draft.limit_ip,
                    unlimited: draft.unlimited,
                  }
                : undefined
            }
            familySize={familySize}
            onFamilySizeChange={() => undefined}
            promoCode={promoCode}
            onPromoCodeChange={setPromoCode}
            onPreview={(preview, previewError) => {
              if (previewError) {
                setPriceHint(null);
                return;
              }
              if (preview?.charge_label) {
                setPriceHint(preview.charge_label);
                return;
              }
              if (draft.kind === "plan") {
                setPriceHint(priceText(draft.plan.charge_toman ?? draft.plan.price_toman));
              } else {
                setPriceHint(draft.charge_label || null);
              }
            }}
            disabled={busy}
            embedded
          />
        </section>
      ) : (
        <section className="rounded-2xl border border-white/12 bg-black/35 p-3.5 text-[11px] leading-relaxed text-neutral-500">
          خرید حجم کد تخفیف ندارد. مبلغ همان است که در مرحله قبل دیدید.
        </section>
      )}

      <section className="space-y-2.5 rounded-2xl border border-white/12 bg-black/35 p-3.5">
        <div className="inline-flex items-center gap-1.5 text-[12px] font-semibold text-neutral-100">
          <Pencil className="size-3.5 text-neutral-400" />
          {draft.kind === "payg" ? "۲" : "۳"}. نام کانفیگ
        </div>
        <p className="text-[11px] leading-relaxed text-neutral-500">
          این اسم روی داشبورد می‌آید. خالی بماند همان «{defaultName}» می‌ماند.
        </p>
        <input
          value={configName}
          maxLength={64}
          disabled={busy}
          onChange={(e) => setConfigName(e.target.value)}
          placeholder={defaultName}
          className="h-10 w-full rounded-xl border border-white/12 bg-black/40 px-3 text-sm text-white outline-none placeholder:text-neutral-600 focus:border-white/25"
        />
      </section>

      <TgButton disabled={busy} onClick={submit}>
        تأیید و ادامه پرداخت
      </TgButton>
    </div>
  );
}

export function purchaseDraftKey(draft: PurchaseDraft) {
  return draft.kind === "plan" ? `plan-${draft.plan.id}` : `${draft.kind}-${draft.title}`;
}
