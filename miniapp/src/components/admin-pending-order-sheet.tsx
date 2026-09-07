import { useState } from "react";
import { Check, Copy, RefreshCw, Upload } from "lucide-react";
import { api, haptic, type AdminPendingOrder } from "@/api";
import { OrderReceiptViewer } from "@/components/order-receipt-viewer";
import { TgButton } from "@/components/tg-button";
import { TgSheet } from "@/components/tg-sheet";
import { cn, faNum } from "@/lib/utils";

async function copyText(text: string) {
  try {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(text);
      haptic();
      return true;
    }
  } catch {
    /* fallback */
  }
  try {
    const el = document.createElement("textarea");
    el.value = text;
    el.setAttribute("readonly", "");
    el.style.position = "fixed";
    el.style.opacity = "0";
    document.body.appendChild(el);
    el.select();
    const ok = document.execCommand("copy");
    document.body.removeChild(el);
    if (ok) haptic();
    return ok;
  } catch {
    return false;
  }
}

export function AdminPendingOrderSheet({
  open,
  onClose,
  order,
  busy,
  onApprove,
  onReject,
  onRefresh,
  onNotify,
}: {
  open: boolean;
  onClose: () => void;
  order: AdminPendingOrder | null;
  busy?: boolean;
  onApprove: (id: number) => Promise<void>;
  onReject: (id: number) => Promise<void>;
  onRefresh?: () => void;
  onNotify?: (message: string, kind?: "success" | "error" | "info") => void;
}) {
  const [copied, setCopied] = useState(false);
  const [actionBusy, setActionBusy] = useState(false);
  const [uploading, setUploading] = useState(false);

  if (!order) return null;

  const handleApprove = async () => {
    setActionBusy(true);
    try {
      await onApprove(order.id);
      onClose();
    } finally {
      setActionBusy(false);
    }
  };

  const handleReject = async () => {
    setActionBusy(true);
    try {
      await onReject(order.id);
      onClose();
    } finally {
      setActionBusy(false);
    }
  };

  const disabled = busy || actionBusy;

  return (
    <TgSheet
      open={open}
      onClose={onClose}
      title={`سفارش #${faNum(order.id)}`}
      description={order.plan}
    >
      <div className="space-y-4">
        <div className="rounded-xl border border-white/10 bg-black/30 px-3 py-2 text-sm">
          <div className="flex justify-between gap-3 border-b border-white/8 py-2">
            <span className="text-[11px] text-neutral-500">کاربر</span>
            <span className="text-[12px] text-neutral-100">{order.user || "—"}</span>
          </div>
          <div className="flex justify-between gap-3 border-b border-white/8 py-2">
            <span className="text-[11px] text-neutral-500">آیدی تلگرام</span>
            <span className="font-mono text-[11px] text-neutral-100" dir="ltr">
              {order.telegram_id}
            </span>
          </div>
          <div className="flex justify-between gap-3 border-b border-white/8 py-2">
            <span className="text-[11px] text-neutral-500">مبلغ</span>
            <span className="text-[12px] text-neutral-100">{order.amount_label}</span>
          </div>
          {(order.family_size ?? 1) > 1 ? (
            <div className="flex justify-between gap-3 border-b border-white/8 py-2">
              <span className="text-[11px] text-neutral-500">پکیج خانواده</span>
              <span className="text-[12px] text-neutral-100">{faNum(order.family_size!)} کانفیگ</span>
            </div>
          ) : null}
          {order.promo_code ? (
            <div className="flex justify-between gap-3 border-b border-white/8 py-2">
              <span className="text-[11px] text-neutral-500">کد تخفیف</span>
              <span className="font-mono text-[11px] text-emerald-300" dir="ltr">
                {order.promo_code}
                {(order.bonus_days ?? 0) > 0 ? ` · +${faNum(order.bonus_days!)} روز` : ""}
                {(order.discount_toman ?? 0) > 0 ? ` · −${faNum(order.discount_toman!)}` : ""}
              </span>
            </div>
          ) : null}
          <div className="flex justify-between gap-3 py-2">
            <span className="text-[11px] text-neutral-500">رسید</span>
            <span className={cn("text-[12px]", order.has_receipt ? "text-emerald-400" : "text-amber-400")}>
              {order.has_receipt ? "ارسال شده" : "ارسال نشده"}
            </span>
          </div>
        </div>

        {order.has_receipt ? (
          <div className="space-y-2">
            <h4 className="text-xs font-semibold text-neutral-300">تصویر رسید</h4>
            <OrderReceiptViewer orderId={order.id} enabled={open} />
          </div>
        ) : (
          <div className="space-y-2">
            <div className="rounded-xl border border-amber-500/25 bg-amber-500/10 px-3 py-3 text-center text-xs text-amber-200/90">
              کاربر هنوز رسید را در اپ آپلود نکرده — می‌توانید اینجا ثبت کنید یا بدون رسید تایید کنید.
            </div>
            <label className="flex cursor-pointer items-center justify-center gap-2 rounded-xl border border-dashed border-white/20 bg-black/30 px-3 py-3 text-xs text-neutral-300">
              <input
                type="file"
                accept="image/*,.pdf"
                className="hidden"
                disabled={disabled || uploading}
                onChange={(e) => {
                  const file = e.target.files?.[0];
                  if (!file) return;
                  setUploading(true);
                  void api
                    .adminUploadReceipt(order.id, file)
                    .then(() => {
                      haptic();
                      onNotify?.("رسید ثبت شد", "success");
                      onRefresh?.();
                    })
                    .catch((err) =>
                      onNotify?.(err instanceof Error ? err.message : "خطا", "error"),
                    )
                    .finally(() => setUploading(false));
                  e.target.value = "";
                }}
              />
              <Upload className="size-3.5" />
              {uploading ? "در حال آپلود…" : "آپلود رسید"}
            </label>
          </div>
        )}

        <div className="grid gap-2 sm:grid-cols-2">
          <TgButton
            variant="outline"
            disabled={disabled}
            onClick={() => {
              void copyText(String(order.id)).then((ok) => {
                if (ok) {
                  setCopied(true);
                  window.setTimeout(() => setCopied(false), 1500);
                }
              });
            }}
          >
            {copied ? (
              <span className="inline-flex items-center gap-1.5">
                <Check className="size-3.5" />
                کپی شد
              </span>
            ) : (
              <span className="inline-flex items-center gap-1.5">
                <Copy className="size-3.5" />
                کپی شماره
              </span>
            )}
          </TgButton>
          {onRefresh && (
            <TgButton variant="outline" disabled={disabled} onClick={onRefresh}>
              <span className="inline-flex items-center gap-1.5">
                <RefreshCw className="size-3.5" />
                بروزرسانی
              </span>
            </TgButton>
          )}
        </div>

        <div className="grid grid-cols-2 gap-2">
          <TgButton disabled={disabled || !order.has_receipt} onClick={() => void handleApprove()}>
            تایید
          </TgButton>
          <TgButton variant="outline" disabled={disabled} onClick={() => void handleReject()}>
            رد
          </TgButton>
        </div>

        {!order.has_receipt && (
          <TgButton variant="outline" disabled={disabled} onClick={() => void handleApprove()}>
            تایید بدون رسید (ادمین)
          </TgButton>
        )}
      </div>
    </TgSheet>
  );
}
