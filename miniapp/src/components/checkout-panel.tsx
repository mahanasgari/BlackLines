import { Upload } from "lucide-react";
import { RecipientCheckoutBanner } from "@/components/buy-for-others-panel";
import { FamilyCheckoutBanner } from "@/components/family-pack-panel";
import { OrbLoader } from "@/components/orb-loader";
import {
  PaymentCardFolder,
  type PaymentCardOption,
} from "@/components/payment-card-folder";
import { TgButton } from "@/components/tg-button";
import { Label } from "@/components/ui/label";
import { cn, faNum } from "@/lib/utils";

function priceText(toman: number) {
  return `${faNum(toman)} تومان`;
}

export function CheckoutPanel({
  kind,
  orderId,
  amountToman,
  walletUsed,
  paymentNote,
  recipientName,
  familySize,
  cards,
  busy,
  onCopy,
  onCopyAmount,
  onReceipt,
  onCancel,
}: {
  kind?: "plan" | "wallet" | "pro";
  orderId: number;
  amountToman: number;
  walletUsed: number;
  paymentNote?: string;
  recipientName?: string | null;
  familySize?: number;
  cards: PaymentCardOption[];
  busy: boolean;
  onCopy: (card: PaymentCardOption) => void;
  onCopyAmount?: (amountToman: number) => void;
  onReceipt: (file: File | null) => void;
  onCancel: () => void;
}) {
  const title =
    kind === "wallet"
      ? `شارژ کیف‌پول · سفارش ${faNum(orderId)}`
      : kind === "pro"
        ? `اشتراک Pro · سفارش ${faNum(orderId)}`
        : `تسویه سفارش · ${faNum(orderId)}`;

  return (
    <div className="space-y-4" dir="rtl">
      <div className="space-y-1 text-right">
        <div className="inline-flex rounded-lg border border-white/15 bg-white/10 px-2 py-0.5 text-[11px] text-neutral-300">
          مرحله ۱ از ۲ · واریز
        </div>
        <h3 className="text-lg font-extrabold leading-snug">{title}</h3>
        <p className="text-sm leading-relaxed text-neutral-400">
          مبلغ و شماره را از فیش زیر کپی کنید، واریز کنید، بعد رسید را بفرستید.
        </p>
      </div>

      {recipientName ? <RecipientCheckoutBanner name={recipientName} /> : null}
      {familySize && familySize > 1 ? <FamilyCheckoutBanner size={familySize} /> : null}

      {walletUsed > 0 ? (
        <p className="rounded-xl border border-white/10 bg-white/5 px-3 py-2 text-xs text-neutral-400">
          {priceText(walletUsed)} از کیف‌پول شما کسر شده است
        </p>
      ) : null}

      <PaymentCardFolder
        cards={cards}
        amountToman={amountToman}
        orderId={orderId}
        disabled={busy}
        onCopy={onCopy}
        onCopyAmount={onCopyAmount}
      />

      {paymentNote && !cards.some((c) => c.note) ? (
        <p className="rounded-xl border border-white/10 bg-white/5 px-3 py-2 text-xs leading-relaxed text-neutral-300">
          {paymentNote}
        </p>
      ) : null}

      <div className="space-y-2 border-t border-white/10 pt-4">
        <div className="text-right">
          <div className="inline-flex rounded-lg border border-white/15 bg-white/10 px-2 py-0.5 text-[11px] text-neutral-300">
            مرحله ۲ از ۲ · رسید
          </div>
        </div>
        <Label
          htmlFor="receipt"
          className={cn(
            "flex h-12 w-full cursor-pointer items-center justify-center gap-2 rounded-xl bg-white text-sm font-bold text-black",
            busy && "pointer-events-none opacity-45",
          )}
        >
          {busy ? <OrbLoader variant="upload" /> : <Upload className="size-4" />}
          {busy ? "در حال ارسال رسید…" : "ارسال عکس رسید پرداخت"}
        </Label>
        <p className="text-center text-[11px] leading-relaxed text-neutral-500">
          یک عکس معمولی از گالری بفرستید. اگر روی لودینگ ماند، فیلترشکن را خاموش کنید و دوباره همان عکس را بفرستید.
        </p>
        <input
          id="receipt"
          type="file"
          accept="image/jpeg,image/png,image/webp,application/pdf,.jpg,.jpeg,.png,.webp,.pdf"
          className="hidden"
          disabled={busy}
          onChange={(e) => {
            const file = e.target.files?.[0] || null;
            e.target.value = "";
            onReceipt(file);
          }}
        />
        <TgButton variant="ghost" disabled={busy} onClick={onCancel}>
          لغو سفارش و بازگشت وجه به کیف‌پول
        </TgButton>
      </div>
    </div>
  );
}

export function AdminPaymentCardsPanel({
  cards,
  busy,
  draft,
  onDraftChange,
  onAdd,
  onRemove,
  hideTitle,
}: {
  cards: PaymentCardOption[];
  busy: boolean;
  draft: { card: string; name: string; label: string; note: string };
  onDraftChange: (field: keyof typeof draft, value: string) => void;
  onAdd: () => void;
  onRemove: (id: number) => void;
  hideTitle?: boolean;
}) {
  return (
    <div className="space-y-3 text-right" dir="rtl">
      {!hideTitle && (
        <div>
          <h3 className="font-semibold">کارت‌های پرداخت</h3>
          <p className="mt-1 text-xs text-neutral-400">کاربر هنگام خرید بین این کارت‌ها جابه‌جا می‌شود</p>
        </div>
      )}
      {cards.map((c) => (
        <CardRow key={c.id} card={c} busy={busy} onRemove={() => onRemove(c.id)} />
      ))}
      <div className="space-y-2 rounded-xl border border-white/12 bg-black/40 p-3">
        <Label className="text-neutral-300">افزودن کارت جدید</Label>
        <input
          dir="ltr"
          placeholder="6037-1234-5678-9012"
          value={draft.card}
          onChange={(e) => onDraftChange("card", e.target.value)}
          className="h-11 w-full rounded-xl border border-white/15 bg-black/50 px-3 font-mono text-sm"
        />
        <input
          placeholder="نام صاحب حساب"
          value={draft.name}
          onChange={(e) => onDraftChange("name", e.target.value)}
          className="h-11 w-full rounded-xl border border-white/15 bg-black/50 px-3 text-sm"
        />
        <input
          placeholder="برچسب (مثلاً بانک ملت)"
          value={draft.label}
          onChange={(e) => onDraftChange("label", e.target.value)}
          className="h-11 w-full rounded-xl border border-white/15 bg-black/50 px-3 text-sm"
        />
        <textarea
          placeholder="یادداشت برای کاربر (اختیاری)"
          value={draft.note}
          onChange={(e) => onDraftChange("note", e.target.value)}
          rows={2}
          className="w-full resize-none rounded-xl border border-white/15 bg-black/50 px-3 py-2 text-sm"
        />
        <TgButton disabled={busy || draft.card.replace(/\D/g, "").length < 16} onClick={onAdd}>
          افزودن کارت
        </TgButton>
      </div>
    </div>
  );
}

function CardRow({
  card,
  busy,
  onRemove,
}: {
  card: PaymentCardOption;
  busy: boolean;
  onRemove: () => void;
}) {
  return (
    <div className="flex items-start justify-between gap-3 rounded-xl border border-white/12 bg-white/5 p-3">
      <div className="min-w-0 text-right">
        <p className="font-semibold">{card.label || card.name || "کارت"}</p>
        <p className="mt-0.5 text-sm text-neutral-300">{card.name || "—"}</p>
        <p className="mt-1 font-mono text-xs text-neutral-400" dir="ltr">
          {card.card}
        </p>
      </div>
      <TgButton variant="outline" className="w-auto shrink-0 px-3 text-xs" disabled={busy} onClick={onRemove}>
        حذف
      </TgButton>
    </div>
  );
}
