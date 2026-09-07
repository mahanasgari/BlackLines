import { useCallback, useEffect, useState } from "react";
import { Check, Copy, ExternalLink, FileText, Link2, Package, RefreshCw, Trash2 } from "lucide-react";
import {
  api,
  haptic,
  type ChatAttachment,
  type ChatOrderItem,
  type DashboardItem,
} from "@/api";
import type { ChatAttachmentDraft } from "@/components/chat-attachment-picker";
import { OrderReceiptViewer } from "@/components/order-receipt-viewer";
import { TgButton } from "@/components/tg-button";
import { TgSheet } from "@/components/tg-sheet";
import { cn, faNum } from "@/lib/utils";

export type AttachmentDetailTarget = ChatAttachment | ChatAttachmentDraft;

type DetailContext = {
  isAdmin: boolean;
  threadUserId?: number;
  mode: "message" | "composer";
  onNavigate?: (tab: "subs" | "shop" | "admin") => void;
  onComposerRemove?: () => void;
  onOrderAction?: () => void;
  onNotify?: (message: string, kind?: "success" | "error" | "info") => void;
};

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

function statusTone(status?: string | null) {
  if (status === "approved" || status === "active") return "text-emerald-400";
  if (status === "pending") return "text-amber-400";
  if (status === "rejected" || status === "expired" || status === "disabled") return "text-red-400";
  return "text-neutral-400";
}

function DetailRow({ label, value, mono }: { label: string; value: React.ReactNode; mono?: boolean }) {
  return (
    <div className="flex items-start justify-between gap-3 border-b border-white/8 py-2.5 last:border-0">
      <span className="shrink-0 text-[11px] text-neutral-500">{label}</span>
      <span className={cn("min-w-0 text-end text-[12px] text-neutral-100", mono && "font-mono text-[11px]")} dir={mono ? "ltr" : undefined}>
        {value}
      </span>
    </div>
  );
}

function ActionBtn({
  children,
  onClick,
  variant = "outline",
  disabled,
}: {
  children: React.ReactNode;
  onClick: () => void;
  variant?: "outline" | "primary" | "danger";
  disabled?: boolean;
}) {
  return (
    <TgButton
      variant={variant === "primary" ? "default" : variant === "danger" ? "outline" : "outline"}
      disabled={disabled}
      className={cn(
        "w-full justify-center text-xs",
        variant === "danger" && "border-red-500/40 text-red-300",
      )}
      onClick={onClick}
    >
      {children}
    </TgButton>
  );
}

export function ChatAttachmentDetailSheet({
  open,
  onClose,
  attachment,
  context,
}: {
  open: boolean;
  onClose: () => void;
  attachment: AttachmentDetailTarget | null;
  context: DetailContext;
}) {
  const [loading, setLoading] = useState(false);
  const [links, setLinks] = useState<string[]>([]);
  const [dashItem, setDashItem] = useState<DashboardItem | null>(null);
  const [orderFresh, setOrderFresh] = useState<ChatOrderItem | null>(null);
  const [adminPending, setAdminPending] = useState<{
    id: number;
    has_receipt: boolean;
    is_wallet_topup?: boolean;
  } | null>(null);
  const [labelDraft, setLabelDraft] = useState("");
  const [labelBusy, setLabelBusy] = useState(false);
  const [orderBusy, setOrderBusy] = useState(false);
  const [receiptUploading, setReceiptUploading] = useState(false);
  const [copied, setCopied] = useState<string | null>(null);

  const subId =
    attachment && (attachment.type === "subscription" || attachment.type === "link")
      ? attachment.subscription_id
      : null;
  const orderId = attachment?.type === "order" ? attachment.order_id : null;

  const loadDetails = useCallback(async () => {
    if (!attachment) return;
    setLoading(true);
    setLinks([]);
    setDashItem(null);
    setOrderFresh(null);
    setAdminPending(null);
    try {
      if (attachment.type === "subscription" || attachment.type === "link") {
        if (subId) {
          const linkData = await api.links(subId);
          setLinks(linkData.links);
          if (!context.isAdmin) {
            try {
              const dash = await api.dashboard();
              setDashItem(dash.items.find((i) => i.id === subId) ?? null);
            } catch {
              setDashItem(null);
            }
          }
        }
      }
      if (attachment.type === "order" && orderId) {
        if (context.isAdmin) {
          const pending = await api.adminPending();
          const p = pending.find((o) => o.id === orderId);
          if (p) setAdminPending({ id: p.id, has_receipt: p.has_receipt, is_wallet_topup: p.is_wallet_topup });
          if (context.threadUserId) {
            const ordersRes = await api.adminThreadOrders(context.threadUserId);
            setOrderFresh(ordersRes.items.find((o) => o.id === orderId) ?? null);
          }
        } else {
          const [ordersRes, subs] = await Promise.all([api.chatOrders(), api.subscriptions()]);
          setOrderFresh(ordersRes.items.find((o) => o.id === orderId) ?? null);
          if (subs.pending?.id === orderId) {
            setAdminPending({
              id: subs.pending.id,
              has_receipt: subs.pending.has_receipt,
              is_wallet_topup: subs.pending.is_wallet_topup,
            });
          }
        }
      }
      if (attachment.type === "subscription" && "label" in attachment) {
        setLabelDraft(attachment.label?.trim() || "");
      }
    } finally {
      setLoading(false);
    }
  }, [attachment, context.isAdmin, context.threadUserId, orderId, subId]);

  useEffect(() => {
    if (!open || !attachment) return;
    void loadDetails();
  }, [open, attachment, loadDetails]);

  const flashCopied = (key: string) => {
    setCopied(key);
    window.setTimeout(() => setCopied(null), 1500);
  };

  const resolvedLink =
    attachment?.type === "link"
      ? attachment.link ||
        (typeof attachment.link_index === "number" ? links[attachment.link_index] : undefined)
      : undefined;

  const title =
    attachment?.type === "order"
      ? "جزئیات فاکتور"
      : attachment?.type === "link"
        ? "جزئیات لینک VPN"
        : "جزئیات اشتراک";

  const description =
    attachment?.type === "order"
      ? `#${orderId ? faNum(orderId) : "—"}`
      : attachment && "email" in attachment && attachment.email
        ? attachment.email
        : null;

  const saveLabel = async () => {
    if (!subId || context.isAdmin) return;
    setLabelBusy(true);
    try {
      await api.setLabel(subId, labelDraft.trim());
      haptic();
      void loadDetails();
    } finally {
      setLabelBusy(false);
    }
  };

  const approveOrder = async () => {
    if (!orderId) return;
    setOrderBusy(true);
    try {
      await api.adminApprove(orderId);
      haptic();
      context.onNotify?.("فاکتور تایید شد", "success");
      context.onOrderAction?.();
      void loadDetails();
    } catch (e) {
      context.onNotify?.(e instanceof Error ? e.message : "تایید ناموفق", "error");
    } finally {
      setOrderBusy(false);
    }
  };

  const rejectOrder = async () => {
    if (!orderId) return;
    setOrderBusy(true);
    try {
      await api.adminReject(orderId);
      haptic();
      context.onNotify?.("فاکتور رد شد", "info");
      context.onOrderAction?.();
      onClose();
    } catch (e) {
      context.onNotify?.(e instanceof Error ? e.message : "رد ناموفق", "error");
    } finally {
      setOrderBusy(false);
    }
  };

  const uploadAdminReceipt = async (file: File) => {
    if (!orderId) return;
    setReceiptUploading(true);
    try {
      await api.adminUploadReceipt(orderId, file);
      haptic();
      context.onNotify?.("رسید ثبت شد", "success");
      context.onOrderAction?.();
      void loadDetails();
    } catch (e) {
      context.onNotify?.(e instanceof Error ? e.message : "ثبت رسید ناموفق", "error");
    } finally {
      setReceiptUploading(false);
    }
  };

  if (!attachment) return null;

  const order = orderFresh;
  const orderMeta = attachment.type === "order" ? attachment : null;
  const orderStatus =
    orderFresh?.status ??
    (orderMeta && "status" in orderMeta ? (orderMeta as { status?: string }).status : null) ??
    null;
  const isPendingOrder = orderStatus === "pending";
  const hasReceipt = Boolean(orderFresh?.has_receipt ?? orderMeta?.has_receipt);
  const needsBankReceipt =
    (orderFresh?.amount_toman ?? (orderMeta as { amount_toman?: number })?.amount_toman ?? 0) > 0;
  const canAdminAct = context.isAdmin && isPendingOrder;
  const canAdminApprove = canAdminAct && (hasReceipt || !needsBankReceipt);

  return (
    <TgSheet open={open} onClose={onClose} title={title} description={description}>
      <div className="space-y-4">
        {loading && (
          <div className="rounded-xl border border-white/10 bg-white/5 px-3 py-4 text-center text-xs text-neutral-400">
            در حال بارگذاری جزئیات…
          </div>
        )}

        {!loading && attachment.type === "subscription" && (
          <>
            <div className="rounded-xl border border-white/10 bg-black/30 px-3">
              <DetailRow label="نام / برچسب" value={attachment.label?.trim() || "—"} />
              <DetailRow label="پلن" value={attachment.plan_title || "—"} />
              <DetailRow label="ایمیل" value={attachment.email || "—"} mono />
              {attachment.status && (
                <DetailRow
                  label="وضعیت"
                  value={<span className={statusTone(attachment.status)}>{attachment.status}</span>}
                />
              )}
              {dashItem && (
                <>
                  <DetailRow
                    label="مصرف"
                    value={`${faNum(Math.round(dashItem.usage_percent))}٪ · ${dashItem.used_label} / ${dashItem.total_label}`}
                  />
                  <DetailRow label="اتصال" value={dashItem.online ? "آنلاین" : "آفلاین"} />
                  <DetailRow
                    label="انقضا"
                    value={
                      dashItem.expires_at
                        ? new Intl.DateTimeFormat("fa-IR", { dateStyle: "medium" }).format(new Date(dashItem.expires_at))
                        : "—"
                    }
                  />
                </>
              )}
            </div>

            {!context.isAdmin && (
              <div className="space-y-2">
                <label className="text-[11px] text-neutral-400">برچسب اشتراک</label>
                <input
                  value={labelDraft}
                  onChange={(e) => setLabelDraft(e.target.value)}
                  maxLength={64}
                  className="w-full rounded-xl border border-white/12 bg-black/40 px-3 py-2 text-sm text-white outline-none focus:border-white/25"
                  placeholder="مثلاً لپ‌تاپ"
                />
                <ActionBtn disabled={labelBusy} onClick={() => void saveLabel()}>
                  {labelBusy ? "در حال ذخیره…" : "ذخیره برچسب"}
                </ActionBtn>
              </div>
            )}

            {links.length > 0 && (
              <div className="space-y-2">
                <div className="text-[11px] font-medium text-neutral-300">لینک‌های VPN</div>
                {links.map((link, i) => (
                  <div key={i} className="flex items-center gap-2 rounded-xl border border-white/10 bg-black/30 p-2">
                    <span className="min-w-0 flex-1 truncate font-mono text-[10px] text-neutral-400" dir="ltr">
                      {link}
                    </span>
                    <button
                      type="button"
                      onClick={() => {
                        void copyText(link).then((ok) => ok && flashCopied(`link-${i}`));
                      }}
                      className="inline-flex size-8 shrink-0 items-center justify-center rounded-lg bg-white/10 active:bg-white/15"
                    >
                      {copied === `link-${i}` ? <Check className="size-3.5" /> : <Copy className="size-3.5" />}
                    </button>
                  </div>
                ))}
              </div>
            )}

            <div className="grid gap-2 sm:grid-cols-2">
              {attachment.email && (
                <ActionBtn
                  onClick={() => {
                    void copyText(attachment.email!).then((ok) => ok && flashCopied("email"));
                  }}
                >
                  {copied === "email" ? "کپی شد ✓" : "کپی ایمیل"}
                </ActionBtn>
              )}
              {!context.isAdmin && (
                <ActionBtn onClick={() => { onClose(); context.onNavigate?.("subs"); }}>
                  <span className="inline-flex items-center gap-1.5">
                    <ExternalLink className="size-3.5" />
                    باز کردن در داشبورد
                  </span>
                </ActionBtn>
              )}
              <ActionBtn onClick={() => void loadDetails()}>
                <span className="inline-flex items-center gap-1.5">
                  <RefreshCw className="size-3.5" />
                  بروزرسانی
                </span>
              </ActionBtn>
            </div>
          </>
        )}

        {!loading && attachment.type === "link" && (
          <>
            <div className="rounded-xl border border-white/10 bg-black/30 px-3">
              <DetailRow label="اشتراک" value={attachment.label?.trim() || attachment.plan_title || "—"} />
              <DetailRow label="پلن" value={attachment.plan_title || "—"} />
              <DetailRow label="ایمیل" value={attachment.email || "—"} mono />
              {typeof attachment.link_index === "number" && (
                <DetailRow label="شماره لینک" value={faNum(attachment.link_index + 1)} />
              )}
            </div>

            {resolvedLink && (
              <div className="rounded-xl border border-white/10 bg-black/40 p-3">
                <div className="mb-1 text-[10px] text-neutral-500">لینک کامل</div>
                <p className="break-all font-mono text-[11px] leading-relaxed text-neutral-200" dir="ltr">
                  {resolvedLink}
                </p>
              </div>
            )}

            <div className="grid gap-2 sm:grid-cols-2">
              {resolvedLink && (
                <ActionBtn
                  onClick={() => {
                    void copyText(resolvedLink).then((ok) => ok && flashCopied("link"));
                  }}
                >
                  {copied === "link" ? "کپی شد ✓" : "کپی لینک"}
                </ActionBtn>
              )}
              {attachment.email && (
                <ActionBtn
                  onClick={() => {
                    void copyText(attachment.email!).then((ok) => ok && flashCopied("email"));
                  }}
                >
                  کپی ایمیل
                </ActionBtn>
              )}
              {links.length > 1 && (
                <ActionBtn onClick={() => void loadDetails()}>مشاهده همه لینک‌ها</ActionBtn>
              )}
            </div>

            {links.length > 1 && (
              <div className="space-y-2">
                {links.map((link, i) => (
                  <button
                    key={i}
                    type="button"
                    onClick={() => void copyText(link)}
                    className={cn(
                      "flex w-full items-center gap-2 rounded-xl border px-3 py-2 text-start active:bg-white/5",
                      attachment.link_index === i ? "border-white/25 bg-white/8" : "border-white/10 bg-black/25",
                    )}
                  >
                    <Link2 className="size-3.5 shrink-0 text-neutral-400" />
                    <span className="min-w-0 flex-1 truncate font-mono text-[10px] text-neutral-300" dir="ltr">
                      {link}
                    </span>
                  </button>
                ))}
              </div>
            )}
          </>
        )}

        {!loading && attachment.type === "order" && orderMeta && (
          <>
            <div className="rounded-xl border border-white/10 bg-black/30 px-3">
              <DetailRow label="شماره" value={`#${faNum(orderFresh?.id ?? orderMeta.order_id)}`} />
              <DetailRow label="نوع" value={orderFresh?.kind_label ?? orderMeta.kind_label ?? "—"} />
              <DetailRow label="پلن / شرح" value={orderFresh?.plan_title ?? orderMeta.plan_title ?? "—"} />
              <DetailRow label="مبلغ" value={orderFresh?.amount_label ?? orderMeta.amount_label ?? "—"} />
              <DetailRow
                label="وضعیت"
                value={
                  <span className={statusTone(orderStatus)}>
                    {orderFresh?.status_label ?? orderMeta.status_label ?? "—"}
                  </span>
                }
              />
              {(orderFresh?.has_receipt ?? orderMeta.has_receipt) && <DetailRow label="رسید" value="ارسال شده ✓" />}
              {orderFresh?.wallet_used_label && orderFresh.wallet_used > 0 && (
                <DetailRow label="از کیف‌پول" value={orderFresh.wallet_used_label} />
              )}
              {orderFresh?.created_at && (
                <DetailRow
                  label="تاریخ"
                  value={new Intl.DateTimeFormat("fa-IR", { dateStyle: "medium", timeStyle: "short" }).format(
                    new Date(orderFresh.created_at),
                  )}
                />
              )}
            </div>

            {(orderFresh?.has_receipt ?? orderMeta.has_receipt) && orderId && (
              <div className="space-y-2">
                <div className="text-[11px] font-medium text-neutral-300">رسید پرداخت</div>
                <OrderReceiptViewer orderId={orderId} enabled={open} />
              </div>
            )}

            {context.isAdmin && canAdminAct && hasReceipt && (
              <div className="rounded-xl border border-amber-500/25 bg-amber-500/10 px-3 py-2.5 text-[11px] text-amber-200/90">
                این فاکتور در انتظار بررسی است — می‌توانید از همینجا تایید یا رد کنید.
              </div>
            )}

            {context.isAdmin && canAdminAct && !hasReceipt && needsBankReceipt && (
              <div className="space-y-2 rounded-xl border border-amber-500/25 bg-amber-500/10 px-3 py-2.5">
                <p className="text-[11px] text-amber-200/90">
                  رسید در سیستم ثبت نشده. اگر کاربر عکس را در تلگرام فرستاده، اینجا آپلود کنید یا بدون رسید تایید کنید.
                </p>
                <label className="flex cursor-pointer items-center justify-center gap-2 rounded-xl border border-dashed border-white/20 bg-black/30 px-3 py-2.5 text-[11px] text-neutral-300">
                  <input
                    type="file"
                    accept="image/*,.pdf"
                    className="hidden"
                    disabled={receiptUploading}
                    onChange={(e) => {
                      const file = e.target.files?.[0];
                      if (file) void uploadAdminReceipt(file);
                      e.target.value = "";
                    }}
                  />
                  {receiptUploading ? "در حال آپلود…" : "آپلود رسید برای این فاکتور"}
                </label>
              </div>
            )}

            {!context.isAdmin && isPendingOrder && !hasReceipt && (
              <div className="rounded-xl border border-amber-500/25 bg-amber-500/10 px-3 py-2.5 text-[11px] text-amber-200/90">
                رسید پرداخت هنوز ارسال نشده — از بخش فروشگاه رسید را آپلود کنید.
              </div>
            )}

            <div className="grid gap-2 sm:grid-cols-2">
              <ActionBtn
                onClick={() => {
                  void copyText(String(orderId)).then((ok) => ok && flashCopied("order"));
                }}
              >
                {copied === "order" ? "کپی شد ✓" : "کپی شماره فاکتور"}
              </ActionBtn>
              {!context.isAdmin && isPendingOrder && (
                <ActionBtn onClick={() => { onClose(); context.onNavigate?.("shop"); }}>
                  <span className="inline-flex items-center gap-1.5">
                    <ExternalLink className="size-3.5" />
                    رفتن به فروشگاه
                  </span>
                </ActionBtn>
              )}
              {context.isAdmin && (
                <ActionBtn onClick={() => { onClose(); context.onNavigate?.("admin"); }}>
                  <span className="inline-flex items-center gap-1.5">
                    <ExternalLink className="size-3.5" />
                    پنل ادمین
                  </span>
                </ActionBtn>
              )}
              <ActionBtn onClick={() => void loadDetails()}>
                <span className="inline-flex items-center gap-1.5">
                  <RefreshCw className="size-3.5" />
                  بروزرسانی
                </span>
              </ActionBtn>
            </div>

            {context.isAdmin && canAdminAct && (
              <div className="grid grid-cols-2 gap-2">
                <ActionBtn
                  disabled={orderBusy || (!hasReceipt && needsBankReceipt)}
                  variant="primary"
                  onClick={() => void approveOrder()}
                >
                  تایید فاکتور
                </ActionBtn>
                <ActionBtn disabled={orderBusy} variant="danger" onClick={() => void rejectOrder()}>
                  رد فاکتور
                </ActionBtn>
              </div>
            )}

            {context.isAdmin && canAdminAct && !hasReceipt && needsBankReceipt && (
              <ActionBtn disabled={orderBusy} variant="outline" onClick={() => void approveOrder()}>
                تایید بدون رسید (ادمین)
              </ActionBtn>
            )}

          </>
        )}

        {context.mode === "composer" && context.onComposerRemove && (
          <ActionBtn variant="danger" onClick={() => { context.onComposerRemove?.(); onClose(); }}>
            <span className="inline-flex items-center gap-1.5">
              <Trash2 className="size-3.5" />
              حذف از پیام
            </span>
          </ActionBtn>
        )}

        {context.mode === "message" && (
          <p className="text-center text-[10px] text-neutral-500">
            برای مشاهده جزئیات بیشتر، از دکمه‌های بالا استفاده کنید.
          </p>
        )}
      </div>
    </TgSheet>
  );
}

export function attachmentIcon(type: AttachmentDetailTarget["type"]) {
  if (type === "order") return FileText;
  if (type === "link") return Link2;
  return Package;
}
