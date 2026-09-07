import type { ReactNode } from "react";
import { Bell, MessageCircle, ShoppingBag, Wallet } from "lucide-react";
import { TgButton } from "@/components/tg-button";
import { TgSheet } from "@/components/tg-sheet";
import { cn, faNum } from "@/lib/utils";
import type { ChatMessage, ChatThread, PendingOrder } from "@/api";

type AdminOrder = {
  id: number;
  user: string;
  plan: string;
  amount_label: string;
  has_receipt: boolean;
  is_wallet_topup?: boolean;
};

type AdminWd = {
  id: number;
  user: string;
  amount_label: string;
};

function formatNotifTime(iso: string | null) {
  if (!iso) return "";
  try {
    return new Intl.DateTimeFormat("fa-IR", {
      hour: "2-digit",
      minute: "2-digit",
      day: "numeric",
      month: "short",
    }).format(new Date(iso));
  } catch {
    return "";
  }
}

function messagePreview(msg: ChatMessage) {
  const body = msg.body?.trim();
  if (body) return body.length > 120 ? `${body.slice(0, 117)}…` : body;
  const att = msg.attachments?.[0];
  if (!att) return "پیام";
  if (att.type === "order") return `فاکتور · ${att.plan_title || "سفارش"}`;
  if (att.type === "link") return `لینک · ${att.label?.trim() || att.email || "کانفیگ"}`;
  return `کانفیگ · ${att.label?.trim() || att.email || "—"}`;
}

function threadTitle(t: ChatThread) {
  return t.full_name || (t.username ? `@${t.username}` : faNum(t.telegram_id));
}

function InboxHeader({
  count,
  title,
  subtitle,
}: {
  count: number;
  title: string;
  subtitle?: string;
}) {
  return (
    <div className="flex items-center gap-2 rounded-xl border border-white/10 bg-black/30 px-3 py-2">
      <div className="relative grid size-7 shrink-0 place-items-center rounded-lg bg-white/8 text-neutral-400">
        <Bell className="size-3.5" aria-hidden />
        {count > 0 && (
          <span className="absolute -top-1 -end-1 flex min-w-[0.875rem] items-center justify-center rounded-full bg-orange-500 px-0.5 text-[9px] font-bold leading-4 text-white">
            {faNum(Math.min(count, 99))}
          </span>
        )}
      </div>
      <div className="min-w-0 flex-1">
        <div className="text-xs font-semibold">{title}</div>
        {subtitle ? <p className="truncate text-[10px] text-neutral-500">{subtitle}</p> : null}
      </div>
    </div>
  );
}

function SectionLabel({ icon, children }: { icon: ReactNode; children: ReactNode }) {
  return (
    <h4 className="flex items-center gap-1 px-0.5 text-[11px] font-semibold text-neutral-500">
      {icon}
      {children}
    </h4>
  );
}

function CompactActionRow({
  title,
  body,
  meta,
  onClick,
  accent,
}: {
  title: string;
  body: string;
  meta?: string;
  onClick: () => void;
  accent?: boolean;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "w-full rounded-xl border px-3 py-2 text-start transition-opacity active:opacity-80",
        accent ? "border-orange-400/20 bg-orange-500/8" : "border-white/10 bg-black/35",
      )}
    >
      <div className="flex items-start justify-between gap-2">
        <span className="text-xs font-semibold">{title}</span>
        {meta ? <span className="shrink-0 text-[10px] text-neutral-500">{meta}</span> : null}
      </div>
      <p className="mt-0.5 line-clamp-2 text-[11px] leading-relaxed text-neutral-400">{body}</p>
    </button>
  );
}

function CompactNotice({
  title,
  body,
  actionLabel,
  onAction,
}: {
  title: string;
  body: string;
  actionLabel: string;
  onAction: () => void;
}) {
  return (
    <div className="rounded-xl border border-white/10 bg-black/35 px-3 py-2.5">
      <div className="text-xs font-semibold">{title}</div>
      <p className="mt-0.5 text-[11px] leading-relaxed text-neutral-400">{body}</p>
      <button
        type="button"
        onClick={onAction}
        className="mt-2 text-[11px] font-semibold text-orange-300 active:opacity-70"
      >
        {actionLabel} ←
      </button>
    </div>
  );
}

export function UserNotificationCenterSheet({
  open,
  onClose,
  count,
  chatUnread,
  unreadMessages,
  pendingOrder,
  walletPending,
  loading,
  onOpenChat,
  onOpenSubs,
  onOpenWallet,
}: {
  open: boolean;
  onClose: () => void;
  count: number;
  chatUnread: number;
  unreadMessages: ChatMessage[];
  pendingOrder: PendingOrder | null;
  walletPending: { id: number; amount_label: string; has_receipt: boolean } | null;
  loading: boolean;
  onOpenChat: () => void;
  onOpenSubs: () => void;
  onOpenWallet: () => void;
}) {
  const empty = !loading && count === 0;

  return (
    <TgSheet
      open={open}
      onClose={onClose}
      title="مرکز اعلان"
      description="پیام‌ها و وضعیت سفارش‌های شما"
    >
      <div className="space-y-3">
        <InboxHeader
          count={count}
          title="اعلان‌های شما"
          subtitle={
            loading
              ? "در حال بروزرسانی…"
              : count > 0
                ? `${faNum(count)} مورد`
                : "همه چیز مرتب است"
          }
        />

        {loading && (
          <div className="rounded-xl border border-dashed border-white/10 px-3 py-6 text-center text-xs text-neutral-400">
            در حال بارگذاری…
          </div>
        )}

        {!loading && chatUnread > 0 && (
          <section className="space-y-1.5">
            <SectionLabel icon={<MessageCircle className="size-3" />}>
              {faNum(chatUnread)} پیام خوانده‌نشده
            </SectionLabel>
            <div className="space-y-1.5">
              {unreadMessages.slice(0, 5).map((msg) => (
                <CompactActionRow
                  key={msg.id}
                  accent
                  title="پشتیبانی"
                  meta={formatNotifTime(msg.created_at)}
                  body={messagePreview(msg)}
                  onClick={onOpenChat}
                />
              ))}
              {chatUnread > unreadMessages.length && unreadMessages.length > 0 && (
                <p className="px-0.5 text-[10px] text-neutral-500">
                  و {faNum(chatUnread - unreadMessages.length)} پیام دیگر…
                </p>
              )}
            </div>
            <button
              type="button"
              onClick={onOpenChat}
              className="w-full rounded-lg border border-white/10 py-2 text-[11px] font-semibold text-neutral-300 active:bg-white/5"
            >
              باز کردن گفتگو
            </button>
          </section>
        )}

        {!loading && pendingOrder && (
          <section className="space-y-1.5">
            <SectionLabel icon={<ShoppingBag className="size-3" />}>سفارش در انتظار</SectionLabel>
            <CompactNotice
              title={pendingOrder.plan_title}
              body={`سفارش #${faNum(pendingOrder.id)} · ${pendingOrder.amount_label}${
                pendingOrder.has_receipt ? " · رسید ارسال شده" : " · رسید را ارسال کنید"
              }`}
              actionLabel="مشاهده در داشبورد"
              onAction={onOpenSubs}
            />
          </section>
        )}

        {!loading && walletPending && (
          <section className="space-y-1.5">
            <SectionLabel icon={<Wallet className="size-3" />}>شارژ کیف‌پول</SectionLabel>
            <CompactNotice
              title={`شارژ ${walletPending.amount_label}`}
              body={
                walletPending.has_receipt
                  ? "رسید ارسال شده — پس از تایید موجودی به‌روز می‌شود."
                  : "شارژ ثبت شده — لطفاً رسید پرداخت را ارسال کنید."
              }
              actionLabel="باز کردن کیف‌پول"
              onAction={onOpenWallet}
            />
          </section>
        )}

        {empty && (
          <div className="rounded-xl border border-dashed border-white/10 px-3 py-8 text-center">
            <Bell className="mx-auto size-6 text-neutral-600" aria-hidden />
            <p className="mt-2 text-xs text-neutral-400">اعلان فعالی ندارید</p>
          </div>
        )}
      </div>
    </TgSheet>
  );
}

export function AdminNotificationCenterSheet({
  open,
  onClose,
  orders,
  withdrawals,
  pendingCount,
  chatUnread,
  unreadThreads,
  loading,
  onOpenAdmin,
  onOpenChat,
  onSelectOrder,
  onSelectThread,
}: {
  open: boolean;
  onClose: () => void;
  orders: AdminOrder[];
  withdrawals: AdminWd[];
  pendingCount: number;
  chatUnread: number;
  unreadThreads: ChatThread[];
  loading: boolean;
  onOpenAdmin: () => void;
  onOpenChat: () => void;
  onSelectOrder?: (order: AdminOrder) => void;
  onSelectThread?: (thread: ChatThread) => void;
}) {
  const totalCount = pendingCount + chatUnread;

  return (
    <TgSheet open={open} onClose={onClose} title="مرکز اعلان" description="خلاصه صف بررسی">
      <div className="space-y-3">
        <InboxHeader
          count={totalCount}
          title="صندوق ورود"
          subtitle={
            loading
              ? "در حال بروزرسانی…"
              : totalCount > 0
                ? `${faNum(orders.length)} سفارش · ${faNum(withdrawals.length)} برداشت · ${faNum(chatUnread)} پیام`
                : "همه چیز بررسی شده"
          }
        />

        {loading && (
          <div className="rounded-xl border border-dashed border-white/10 px-3 py-6 text-center text-xs text-neutral-400">
            در حال بارگذاری…
          </div>
        )}

        {!loading && chatUnread > 0 && (
          <section className="space-y-1.5">
            <SectionLabel icon={<MessageCircle className="size-3" />}>
              {faNum(chatUnread)} پیام خوانده‌نشده
            </SectionLabel>
            <div className="space-y-1.5">
              {unreadThreads.slice(0, 5).map((t) => (
                <CompactActionRow
                  key={t.user_id}
                  accent
                  title={threadTitle(t)}
                  meta={t.last_message_at ? formatNotifTime(t.last_message_at) : undefined}
                  body={t.last_message || "پیام جدید"}
                  onClick={() => onSelectThread?.(t)}
                />
              ))}
            </div>
            <button
              type="button"
              onClick={onOpenChat}
              className="w-full rounded-lg border border-white/10 py-2 text-[11px] font-semibold text-neutral-300 active:bg-white/5"
            >
              باز کردن گفتگوها
            </button>
          </section>
        )}

        {!loading && orders.length > 0 && (
          <section className="space-y-1.5">
            <SectionLabel icon={<ShoppingBag className="size-3" />}>سفارش‌های اخیر</SectionLabel>
            {orders.slice(0, 5).map((o) => (
              <button
                key={o.id}
                type="button"
                onClick={() => onSelectOrder?.(o)}
                className="w-full rounded-xl border border-white/10 bg-black/35 px-3 py-2 text-start text-xs transition-opacity active:opacity-80"
              >
                <div className="flex items-center justify-between gap-2">
                  <span className="font-semibold">
                    #{faNum(o.id)} · {o.plan}
                  </span>
                  <span className="shrink-0 text-[10px] text-neutral-400">{o.amount_label}</span>
                </div>
                <div className="mt-0.5 truncate text-[10px] text-neutral-500">
                  {o.user || "—"}
                  {o.has_receipt ? " · رسید ✓" : ""}
                </div>
              </button>
            ))}
          </section>
        )}

        {!loading && withdrawals.length > 0 && (
          <section className="space-y-1.5">
            <SectionLabel icon={<Wallet className="size-3" />}>برداشت‌های اخیر</SectionLabel>
            {withdrawals.slice(0, 3).map((w) => (
              <div key={w.id} className="rounded-xl border border-white/10 bg-black/35 px-3 py-2 text-xs">
                <div className="font-semibold">
                  #{faNum(w.id)} — {w.amount_label}
                </div>
                <div className="mt-0.5 text-[10px] text-neutral-500">{w.user || "—"}</div>
              </div>
            ))}
          </section>
        )}

        {!loading && totalCount === 0 && (
          <div className="rounded-xl border border-dashed border-white/10 px-3 py-8 text-center">
            <Bell className="mx-auto size-6 text-neutral-600" aria-hidden />
            <p className="mt-2 text-xs text-neutral-400">مورد جدیدی در صندوق ورود نیست</p>
          </div>
        )}

        <TgButton variant="outline" className="h-9 text-xs" onClick={onOpenAdmin}>
          پنل ادمین
        </TgButton>
      </div>
    </TgSheet>
  );
}

/** @deprecated use AdminNotificationCenterSheet or UserNotificationCenterSheet */
export const NotificationCenterSheet = AdminNotificationCenterSheet;
