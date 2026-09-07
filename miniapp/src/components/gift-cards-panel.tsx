import { useEffect, useState } from "react";
import { Check, Copy, Gift } from "lucide-react";
import { api, haptic, type GiftCardItem, type Plan } from "@/api";
import { TgButton } from "@/components/tg-button";
import { Input } from "@/components/ui/input";
import { cn, faNum } from "@/lib/utils";

function priceText(toman: number) {
  return `${faNum(toman)} تومان`;
}

async function copyText(text: string) {
  try {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(text);
      haptic();
      return true;
    }
  } catch {
    return false;
  }
  return false;
}

export function GiftCardsPanel({
  plans,
  busy,
  onBuy,
  onRedeemed,
}: {
  plans: Plan[];
  busy?: boolean;
  onBuy: (plan: Plan) => void;
  onRedeemed: () => void | Promise<void>;
}) {
  const [code, setCode] = useState("");
  const [cards, setCards] = useState<GiftCardItem[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [redeeming, setRedeeming] = useState(false);
  const [copied, setCopied] = useState<string | null>(null);

  const load = () => {
    void api
      .giftCards()
      .then((r) => setCards(r.items))
      .catch(() => undefined);
  };

  useEffect(() => {
    load();
  }, []);

  const redeem = async () => {
    const value = code.trim();
    if (!value) return;
    setRedeeming(true);
    setError(null);
    try {
      await api.redeemGiftCard(value);
      haptic("medium");
      setCode("");
      load();
      await onRedeemed();
    } catch (e) {
      setError(e instanceof Error ? e.message : "فعال‌سازی ناموفق");
    } finally {
      setRedeeming(false);
    }
  };

  return (
    <div className="space-y-3">
      <div className="rounded-2xl border border-amber-400/20 bg-amber-500/[0.06] p-3.5">
        <div className="flex items-start gap-2">
          <Gift className="mt-0.5 size-4 shrink-0 text-amber-200" />
          <div>
            <div className="text-[13px] font-semibold text-amber-50">کد هدیه داری؟</div>
            <p className="mt-1 text-[11px] leading-relaxed text-neutral-400">
              کد را وارد کن تا کانفیگ روی همین حساب ساخته شود.
            </p>
          </div>
        </div>
        <div className="mt-3 flex gap-2">
          <Input
            value={code}
            onChange={(e) => setCode(e.target.value.toUpperCase())}
            placeholder="BL-XXXX-XXXX-XXXX"
            dir="ltr"
            className="h-10 flex-1 rounded-xl border-white/15 bg-black/40 font-mono text-sm"
          />
          <TgButton className="h-10 px-3 text-xs" disabled={redeeming || !code.trim()} onClick={() => void redeem()}>
            فعال کن
          </TgButton>
        </div>
        {error ? <p className="mt-2 text-[11px] text-red-200">{error}</p> : null}
      </div>

      <div>
        <h3 className="text-[13px] font-semibold text-white">خرید کارت هدیه</h3>
        <p className="mt-0.5 text-[11px] leading-relaxed text-neutral-500">
          پلن را بخر، کد بگیر، در تلگرام برای دوستت بفرست. نامحدود و Pro در کارت هدیه نیست.
        </p>
      </div>

      <div className="space-y-2">
        {plans.map((plan) => (
          <button
            key={plan.id}
            type="button"
            disabled={busy}
            onClick={() => {
              haptic();
              onBuy(plan);
            }}
            className="flex w-full items-center justify-between gap-3 rounded-2xl border border-white/10 bg-black/30 px-3.5 py-3 text-start active:bg-white/5"
          >
            <span>
              <span className="block text-[13px] font-semibold text-neutral-50">{plan.title}</span>
              <span className="mt-0.5 block text-[11px] text-neutral-500">
                {faNum(plan.duration_days)} روز
                {plan.traffic_gb > 0 ? ` · ${faNum(plan.traffic_gb)} گیگ` : ""}
              </span>
            </span>
            <span className="shrink-0 text-[13px] font-bold tabular-nums text-white">
              {priceText(plan.charge_toman ?? plan.price_toman)}
            </span>
          </button>
        ))}
      </div>

      {cards.length > 0 ? (
        <div className="space-y-2">
          <div className="text-[12px] font-semibold text-neutral-300">کارت‌های تو</div>
          {cards.map((card) => (
            <div key={card.id} className="rounded-xl border border-white/10 bg-black/30 px-3 py-2.5">
              <div className="flex items-start justify-between gap-2">
                <div className="min-w-0">
                  <div className="text-[13px] font-semibold text-neutral-100">{card.plan_title}</div>
                  <div className="mt-1 font-mono text-[12px] text-neutral-200" dir="ltr">
                    {card.code}
                  </div>
                </div>
                <span
                  className={cn(
                    "shrink-0 rounded-md border px-1.5 py-0.5 text-[10px]",
                    card.status === "available"
                      ? "border-emerald-500/25 bg-emerald-500/10 text-emerald-200"
                      : "border-white/10 bg-white/5 text-neutral-400",
                  )}
                >
                  {card.status_label}
                </span>
              </div>
              {card.status === "available" && card.code ? (
                <button
                  type="button"
                  className="mt-2 inline-flex items-center gap-1 text-[11px] text-neutral-300"
                  onClick={() => void copyText(card.code!).then((ok) => ok && setCopied(card.code))}
                >
                  {copied === card.code ? <Check className="size-3.5 text-emerald-300" /> : <Copy className="size-3.5" />}
                  کپی کد
                </button>
              ) : null}
            </div>
          ))}
        </div>
      ) : null}
    </div>
  );
}
