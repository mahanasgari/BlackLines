import { useState } from "react";
import { api, haptic, type WalletTransferItem } from "@/api";
import { TgButton } from "@/components/tg-button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { cn, faNum, formatAmountInput, parseAmountInput } from "@/lib/utils";

function priceText(toman: number) {
  return `${faNum(toman)} تومان`;
}

export function WalletTransferPanel({
  busy,
  balance,
  minTransfer,
  minTransferLabel,
  transfers,
  onBusy,
  onNotify,
  onDone,
}: {
  busy: boolean;
  balance: number;
  minTransfer: number;
  minTransferLabel: string;
  transfers: WalletTransferItem[];
  onBusy: (v: boolean) => void;
  onNotify: (message: string, kind?: "success" | "error" | "info") => void;
  onDone: (walletBalance: number) => void | Promise<void>;
}) {
  const [target, setTarget] = useState("");
  const [preview, setPreview] = useState<{
    telegram_id: number;
    username: string | null;
    full_name: string | null;
  } | null>(null);
  const [amount, setAmount] = useState(0);
  const [confirm, setConfirm] = useState(false);

  const lookup = async () => {
    const q = target.trim();
    if (!q) return;
    onBusy(true);
    try {
      const res = await api.lookupTransferTarget(q);
      setPreview(res.user);
      setConfirm(false);
      haptic();
    } catch (e) {
      setPreview(null);
      onNotify(e instanceof Error ? e.message : "کاربر پیدا نشد", "error");
    } finally {
      onBusy(false);
    }
  };

  const send = async () => {
    if (!preview || amount < minTransfer || amount > balance) return;
    onBusy(true);
    try {
      const res = await api.walletTransfer(String(preview.telegram_id), amount);
      haptic("medium");
      onNotify(`${res.amount_label} منتقل شد`, "success");
      setTarget("");
      setPreview(null);
      setAmount(0);
      setConfirm(false);
      await onDone(res.wallet_balance);
    } catch (e) {
      onNotify(e instanceof Error ? e.message : "انتقال ناموفق", "error");
    } finally {
      onBusy(false);
    }
  };

  const canSend = Boolean(preview) && amount >= minTransfer && amount <= balance;

  return (
    <div className="space-y-2">
      <Label className="text-neutral-300">انتقال به کیف‌پول کاربر دیگر</Label>
      <Input
        placeholder="@username یا آی‌دی تلگرام"
        value={target}
        onChange={(e) => {
          setTarget(e.target.value);
          setPreview(null);
          setConfirm(false);
        }}
        dir="ltr"
        className="h-11 rounded-xl border-white/15 bg-black/40 text-base"
        autoComplete="off"
      />
      <p className="text-[11px] text-neutral-500">
        مقصد باید حداقل یک‌بار فروشگاه را از داخل ربات باز کرده باشد.
      </p>

      {preview ? (
        <div className="rounded-xl border border-white/10 bg-black/30 px-3 py-2.5">
          <div className="text-[10px] text-neutral-500">انتقال به</div>
          <div className="mt-0.5 text-[13px] font-semibold text-neutral-100">
            {preview.full_name?.trim() || "کاربر"}
          </div>
          <div className="mt-0.5 font-mono text-[11px] text-neutral-400" dir="ltr">
            {preview.username ? `@${preview.username}` : ""}
            {preview.username ? " · " : ""}
            {preview.telegram_id}
          </div>
        </div>
      ) : (
        <TgButton variant="outline" disabled={busy || !target.trim()} onClick={() => void lookup()}>
          {busy ? "در حال بررسی…" : "بررسی حساب مقصد"}
        </TgButton>
      )}

      {preview ? (
        <>
          <div className="flex items-center gap-2">
            <Input
              type="text"
              inputMode="numeric"
              dir="ltr"
              value={formatAmountInput(amount)}
              onChange={(e) => {
                setAmount(parseAmountInput(e.target.value));
                setConfirm(false);
              }}
              placeholder="100,000"
              className="h-11 flex-1 rounded-xl border-white/15 bg-black/40 text-base tabular-nums"
            />
            <span className="shrink-0 text-sm font-medium text-neutral-300">تومان</span>
          </div>
          <div className="flex flex-wrap gap-1.5">
            {[10_000, 50_000, 100_000].filter((p) => p <= balance).map((p) => (
              <button
                key={p}
                type="button"
                onClick={() => {
                  setAmount(p);
                  setConfirm(false);
                }}
                className={cn(
                  "h-8 rounded-full border px-3 text-xs font-medium",
                  amount === p
                    ? "border-primary bg-primary text-primary-foreground"
                    : "border-white/15 bg-black/40 text-neutral-300",
                )}
              >
                {priceText(p)}
              </button>
            ))}
            <button
              type="button"
              onClick={() => {
                setAmount(balance);
                setConfirm(false);
              }}
              className="h-8 rounded-full border border-white/15 bg-black/40 px-3 text-xs font-medium text-neutral-300"
            >
              کل موجودی
            </button>
          </div>
          <p className="text-[11px] text-neutral-500">
            حداقل {minTransferLabel} · فوری از کیف‌پول شما کم و به مقصد اضافه می‌شود
          </p>
          {amount > balance ? (
            <p className="text-[11px] text-red-300">مبلغ بیشتر از موجودی است</p>
          ) : null}
          {!confirm ? (
            <TgButton disabled={busy || !canSend} onClick={() => { haptic(); setConfirm(true); }}>
              ادامه انتقال
            </TgButton>
          ) : (
            <div className="space-y-2 rounded-xl border border-amber-400/20 bg-amber-500/10 px-3 py-2.5">
              <p className="text-[11px] leading-relaxed text-amber-100/90">
                {priceText(amount)} به {preview.full_name?.trim() || "این کاربر"} منتقل می‌شود. برگشت ندارد.
              </p>
              <div className="grid grid-cols-2 gap-2">
                <TgButton variant="outline" disabled={busy} onClick={() => setConfirm(false)}>
                  انصراف
                </TgButton>
                <TgButton disabled={busy || !canSend} onClick={() => void send()}>
                  {busy ? "در حال انتقال…" : "تایید و ارسال"}
                </TgButton>
              </div>
            </div>
          )}
        </>
      ) : null}

      {transfers.length > 0 ? (
        <div className="space-y-1.5 border-t border-white/10 pt-3">
          <Label className="text-neutral-300">تاریخچه انتقال</Label>
          {transfers.slice(0, 8).map((t) => (
            <div
              key={t.id}
              className="flex items-center justify-between gap-2 rounded-xl border border-white/10 bg-black/30 px-3 py-2 text-xs"
            >
              <span className="min-w-0 truncate">
                {t.direction === "out" ? "به" : "از"} {t.other_name}
              </span>
              <span
                className={cn(
                  "shrink-0 tabular-nums",
                  t.direction === "in" ? "text-emerald-300" : "text-neutral-200",
                )}
              >
                {t.direction === "in" ? "+" : "−"}
                {t.amount_label}
              </span>
            </div>
          ))}
        </div>
      ) : null}
    </div>
  );
}
