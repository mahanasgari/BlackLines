import { memo, useCallback, useEffect, useRef, useState } from "react";
import { ArrowRight, Copy, FileText, Link2, MessageCircle, Package } from "lucide-react";
import {
  api,
  haptic,
  type ChatAttachment,
  type ChatAttachmentInput,
  type ChatMessage,
  type ChatThread,
} from "@/api";
import type { ChatAttachmentDraft } from "@/components/chat-attachment-picker";
import {
  ChatAttachmentDetailSheet,
  type AttachmentDetailTarget,
} from "@/components/chat-attachment-detail-sheet";
import { ChatComposerBar } from "@/components/chat-composer-bar";
import { cn, faNum } from "@/lib/utils";
import { OrbLoaderPanel } from "@/components/orb-loader";
import { TgButton } from "@/components/tg-button";

const POLL_MS = 2500;
const SCROLL_NEAR_PX = 96;

type ChatMsg = ChatMessage & { pending?: boolean };

function formatChatTime(iso: string | null) {
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

function threadTitle(t: ChatThread) {
  return t.full_name || (t.username ? `@${t.username}` : faNum(t.telegram_id));
}

function mergeMessages(prev: ChatMsg[], incoming: ChatMessage[]) {
  if (!incoming.length) return prev;
  const byId = new Map<number, ChatMsg>();
  for (const m of prev) {
    if (m.id > 0) byId.set(m.id, m);
  }
  for (const m of incoming) {
    byId.set(m.id, m);
  }
  return [...byId.values()].sort((a, b) => a.id - b.id);
}

function draftToInput(drafts: ChatAttachmentDraft[]): ChatAttachmentInput[] {
  return drafts.map((d) => {
    if (d.type === "link") {
      return { type: "link", subscription_id: d.subscription_id, link_index: d.link_index };
    }
    if (d.type === "order") {
      return { type: "order", order_id: d.order_id };
    }
    return { type: "subscription", subscription_id: d.subscription_id };
  });
}

function draftToAttachment(d: ChatAttachmentDraft): ChatAttachment {
  if (d.type === "link") {
    return {
      type: "link",
      subscription_id: d.subscription_id,
      email: d.email,
      label: d.label,
      plan_title: d.plan_title,
      link_preview: d.link_preview,
      link_index: d.link_index,
    };
  }
  if (d.type === "order") {
    return {
      type: "order",
      order_id: d.order_id,
      plan_title: d.plan_title,
      kind: d.kind,
      kind_label: d.kind_label,
      amount_label: d.amount_label,
      status_label: d.status_label,
      has_receipt: d.has_receipt,
    };
  }
  return {
    type: "subscription",
    subscription_id: d.subscription_id,
    email: d.email,
    label: d.label,
    plan_title: d.plan_title,
  };
}

async function copyLink(text: string) {
  try {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(text);
      haptic();
      return;
    }
  } catch {
    /* fallback */
  }
  const el = document.createElement("textarea");
  el.value = text;
  el.setAttribute("readonly", "");
  el.style.position = "fixed";
  el.style.opacity = "0";
  document.body.appendChild(el);
  el.select();
  document.execCommand("copy");
  document.body.removeChild(el);
  haptic();
}

function mergeLiveOrder(att: ChatAttachment, live?: import("@/api").ChatOrderItem): ChatAttachment {
  if (att.type !== "order" || !att.order_id || !live) return att;
  return {
    ...att,
    status: live.status,
    status_label: live.status_label,
    has_receipt: live.has_receipt,
    amount_label: live.amount_label,
    wallet_used: live.wallet_used,
    wallet_used_label: live.wallet_used_label,
  };
}

const AttachmentCard = memo(function AttachmentCard({
  att,
  isMine,
  onOpen,
}: {
  att: ChatAttachment;
  isMine: boolean;
  onOpen?: () => void;
}) {
  const isLink = att.type === "link";
  const isOrder = att.type === "order";
  const title = isOrder
    ? `${att.kind_label || "فاکتور"} · ${att.plan_title || "—"}`
    : att.label?.trim() || att.plan_title || att.email;

  const cardClass = cn(
    "rounded-xl border px-2.5 py-2 text-[11px] transition-opacity",
    isMine ? "border-black/15 bg-black/5 text-black/80" : "border-white/15 bg-black/25 text-neutral-200",
  );

  const body = (
    <>
      <span className="inline-flex size-7 shrink-0 items-center justify-center rounded-lg bg-white/10">
        {isOrder ? <FileText className="size-3.5" /> : isLink ? <Link2 className="size-3.5" /> : <Package className="size-3.5" />}
      </span>
      <div className="min-w-0 flex-1">
        <div className="font-semibold">{isLink ? `لینک · ${title}` : title}</div>
        {isOrder && (
          <div className="mt-0.5 text-[10px] opacity-80">فاکتور #{att.order_id ? faNum(att.order_id) : "—"}</div>
        )}
        {att.email && (
          <div className="mt-0.5 truncate font-mono text-[10px] opacity-70" dir="ltr">
            {att.email}
          </div>
        )}
        {isLink && (att.link_preview || att.link) && (
          <div className="mt-1 truncate font-mono text-[10px] opacity-60" dir="ltr">
            {att.link_preview || att.link}
          </div>
        )}
        {isOrder && att.amount_label && <div className="mt-1 text-xs tabular-nums">{att.amount_label}</div>}
        {!isOrder && att.plan_title && <div className="mt-1 text-[10px] opacity-70">{att.plan_title}</div>}
        {isOrder && (
          <div className="mt-1 flex flex-wrap gap-x-2 text-[10px] opacity-70">
            {att.status_label && <span>{att.status_label}</span>}
            {att.has_receipt && <span>· رسید دارد</span>}
            {att.wallet_used_label && att.wallet_used! > 0 && <span>· کیف‌پول {att.wallet_used_label}</span>}
          </div>
        )}
        <div className="mt-1 text-[10px] opacity-45">برای جزئیات بزنید</div>
      </div>
    </>
  );

  if (isLink && att.link) {
    return (
      <div className={cn(cardClass, "flex items-start gap-2")}>
        <button type="button" onClick={onOpen} className="flex min-w-0 flex-1 items-start gap-2 text-start active:opacity-80">
          {body}
        </button>
        <button
          type="button"
          onClick={(e) => {
            e.stopPropagation();
            void copyLink(att.link!);
          }}
          className={cn(
            "inline-flex size-8 shrink-0 items-center justify-center rounded-lg active:opacity-70",
            isMine ? "bg-black/10" : "bg-white/10",
          )}
          aria-label="کپی لینک"
        >
          <Copy className="size-3.5" />
        </button>
      </div>
    );
  }

  return (
    <button type="button" onClick={onOpen} className={cn(cardClass, "flex w-full items-start gap-2 text-start active:opacity-80")}>
      {body}
    </button>
  );
});

const Bubble = memo(function Bubble({
  msg,
  isMine,
  onAttachmentOpen,
  orderLiveMap,
}: {
  msg: ChatMsg;
  isMine: boolean;
  onAttachmentOpen?: (att: ChatAttachment) => void;
  orderLiveMap?: Map<number, import("@/api").ChatOrderItem>;
}) {
  const attachments = msg.attachments ?? [];
  const hasBody = Boolean(msg.body?.trim());

  return (
    <div className={cn("flex max-w-[85%] flex-col gap-0.5", isMine ? "self-end" : "self-start")}>
      <div
        className={cn(
          "rounded-2xl px-3 py-2 text-sm leading-relaxed break-words whitespace-pre-wrap",
          isMine
            ? "rounded-ee-md bg-white text-black"
            : "rounded-es-md border border-white/12 bg-white/10 text-neutral-100",
          msg.pending && "opacity-70",
        )}
      >
        {hasBody && <div>{msg.body}</div>}
        {attachments.length > 0 && (
          <div className={cn("flex flex-col gap-1.5", hasBody && "mt-2")}>
            {attachments.map((att, i) => {
              const live =
                att.type === "order" && att.order_id ? orderLiveMap?.get(att.order_id) : undefined;
              const resolved = mergeLiveOrder(att, live);
              return (
              <AttachmentCard
                key={`${att.type}-${att.subscription_id ?? att.order_id ?? i}-${att.link_index ?? i}`}
                att={resolved}
                isMine={isMine}
                onOpen={() => {
                  haptic();
                  onAttachmentOpen?.(resolved);
                }}
              />
            );
            })}
          </div>
        )}
      </div>
      <span className={cn("text-[10px] text-neutral-500", isMine ? "text-end" : "text-start")}>
        {msg.pending ? "در حال ارسال…" : formatChatTime(msg.created_at)}
      </span>
    </div>
  );
});

function MessageList({
  messages,
  isMine,
  emptyText,
  scrollRef,
  onScroll,
  onAttachmentOpen,
  orderLiveMap,
}: {
  messages: ChatMsg[];
  isMine: (m: ChatMsg) => boolean;
  emptyText: string;
  scrollRef: React.RefObject<HTMLDivElement | null>;
  onScroll: () => void;
  onAttachmentOpen?: (att: ChatAttachment) => void;
  orderLiveMap?: Map<number, import("@/api").ChatOrderItem>;
}) {
  return (
    <div
      ref={scrollRef}
      onScroll={onScroll}
      className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-4 py-4 [-webkit-overflow-scrolling:touch]"
    >
      <div className="flex min-h-full flex-col justify-end gap-2">
        {messages.length === 0 && (
          <div className="mx-auto my-auto max-w-xs rounded-2xl border border-dashed border-white/15 px-4 py-6 text-center text-sm text-neutral-400">
            {emptyText}
          </div>
        )}
        {messages.map((m) => (
          <Bubble key={m.id} msg={m} isMine={isMine(m)} onAttachmentOpen={onAttachmentOpen} orderLiveMap={orderLiveMap} />
        ))}
      </div>
    </div>
  );
}

function useNearBottom(scrollRef: React.RefObject<HTMLDivElement | null>) {
  const nearBottomRef = useRef(true);

  const onScroll = useCallback(() => {
    const el = scrollRef.current;
    if (!el) return;
    nearBottomRef.current = el.scrollHeight - el.scrollTop - el.clientHeight < SCROLL_NEAR_PX;
  }, [scrollRef]);

  const scrollToBottom = useCallback(
    (smooth: boolean) => {
      const el = scrollRef.current;
      if (!el) return;
      el.scrollTo({ top: el.scrollHeight, behavior: smooth ? "smooth" : "auto" });
      nearBottomRef.current = true;
    },
    [scrollRef],
  );

  return { nearBottomRef, onScroll, scrollToBottom };
}

function UserChat({
  active,
  onUnreadChange,
  onAttachmentOpen,
  onNavigate,
  orderRefreshRef,
}: {
  active: boolean;
  onUnreadChange?: (n: number) => void;
  onAttachmentOpen?: (att: ChatAttachment) => void;
  onNavigate?: (tab: "subs" | "shop" | "admin") => void;
  orderRefreshRef?: React.MutableRefObject<(() => void) | null>;
}) {
  const [messages, setMessages] = useState<ChatMsg[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [orderLiveMap, setOrderLiveMap] = useState<Map<number, import("@/api").ChatOrderItem>>(new Map());
  const scrollRef = useRef<HTMLDivElement>(null);
  const lastIdRef = useRef(0);
  const latestServerIdRef = useRef(0);
  const inflightRef = useRef(false);
  const onUnreadRef = useRef(onUnreadChange);
  onUnreadRef.current = onUnreadChange;
  const { nearBottomRef, onScroll, scrollToBottom } = useNearBottom(scrollRef);
  const [composerBeamKey, setComposerBeamKey] = useState(0);
  const prevActiveRef = useRef(false);

  const pulseComposerBeam = useCallback(() => {
    setComposerBeamKey((k) => k + 1);
  }, []);

  const refreshOrders = useCallback(async () => {
    try {
      const data = await api.chatOrders();
      setOrderLiveMap(new Map(data.items.map((o) => [o.id, o])));
    } catch {
      /* optional */
    }
  }, []);

  useEffect(() => {
    if (!active) return;
    void refreshOrders();
  }, [active, refreshOrders]);

  useEffect(() => {
    if (!orderRefreshRef) return;
    orderRefreshRef.current = () => {
      void refreshOrders();
    };
    return () => {
      orderRefreshRef.current = null;
    };
  }, [orderRefreshRef, refreshOrders]);

  useEffect(() => {
    if (active && !prevActiveRef.current) {
      pulseComposerBeam();
    }
    prevActiveRef.current = active;
  }, [active, pulseComposerBeam]);

  const poll = useCallback(
    async (initial = false) => {
      if (!active && !initial) return;
      if (inflightRef.current) return;
      inflightRef.current = true;
      try {
        const after = initial ? 0 : lastIdRef.current;
        const data = await api.chatMessages(after, false);
        onUnreadRef.current?.(data.unread_count);
        if (initial) {
          setMessages(data.messages);
          if (data.messages.length) lastIdRef.current = data.messages[data.messages.length - 1]!.id;
          latestServerIdRef.current = data.latest_id;
          requestAnimationFrame(() => scrollToBottom(false));
          setError(null);
          return;
        }
        if (data.latest_id <= lastIdRef.current) return;
        setMessages((prev) => {
          const merged = mergeMessages(prev.filter((m) => m.id > 0), data.messages);
          if (merged.length) lastIdRef.current = merged[merged.length - 1]!.id;
          return merged;
        });
        latestServerIdRef.current = data.latest_id;
        if (nearBottomRef.current) {
          requestAnimationFrame(() => scrollToBottom(true));
        }
        setError(null);
      } catch (e) {
        if (initial) setError(e instanceof Error ? e.message : "خطا");
      } finally {
        inflightRef.current = false;
        if (initial) setLoading(false);
      }
    },
    [active, scrollToBottom, nearBottomRef],
  );

  useEffect(() => {
    if (!active) return;
    lastIdRef.current = 0;
    latestServerIdRef.current = 0;
    setLoading(true);
    void api.chatMarkRead().catch(() => undefined);
    void poll(true);
    const t = window.setInterval(() => void poll(false), POLL_MS);
    return () => window.clearInterval(t);
  }, [active, poll]);

  const loadUserSubs = useCallback(async () => {
    const data = await api.subscriptions();
    return data.items;
  }, []);

  const loadUserOrders = useCallback(async () => {
    const data = await api.chatOrders();
    return data.items;
  }, []);

  const send = async (body: string, attachmentDrafts: ChatAttachmentDraft[]) => {
    const tempId = -Date.now();
    const optimisticAttachments = attachmentDrafts.map(draftToAttachment);
    const optimistic: ChatMsg = {
      id: tempId,
      user_id: 0,
      sender: "user",
      body,
      attachments: optimisticAttachments,
      created_at: new Date().toISOString(),
      read_at: null,
      pending: true,
    };
    setMessages((prev) => [...prev, optimistic]);
    requestAnimationFrame(() => scrollToBottom(true));
    pulseComposerBeam();
    setBusy(true);
    try {
      const res = await api.chatSend(body, draftToInput(attachmentDrafts));
      setMessages((prev) =>
        mergeMessages(
          prev.filter((m) => m.id !== tempId),
          [res.message],
        ),
      );
      lastIdRef.current = res.message.id;
      latestServerIdRef.current = Math.max(latestServerIdRef.current, res.message.id);
    } catch {
      setMessages((prev) => prev.filter((m) => m.id !== tempId));
      throw new Error("send failed");
    } finally {
      setBusy(false);
    }
  };

  if (!active && loading) {
    return <OrbLoaderPanel variant="dashboard" message="در حال بارگذاری گفتگو…" />;
  }

  if (loading) {
    return <OrbLoaderPanel variant="dashboard" message="در حال بارگذاری گفتگو…" />;
  }

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <div className="shrink-0 border-b border-white/10 px-4 py-3">
        <div className="flex items-center gap-2">
          <MessageCircle className="size-4 text-neutral-400" />
          <div>
            <div className="text-sm font-semibold">گفتگو با پشتیبانی</div>
            <p className="text-[11px] text-neutral-400">پیام خود را بنویسید — تیم ما پاسخ می‌دهد</p>
          </div>
        </div>
      </div>

      {error ? (
        <div className="flex flex-1 flex-col items-center justify-center gap-3 p-6 text-center">
          <p className="text-sm text-neutral-400">{error}</p>
          <TgButton className="max-w-xs" onClick={() => void poll(true)}>
            تلاش دوباره
          </TgButton>
        </div>
      ) : (
        <MessageList
          messages={messages}
          isMine={(m) => m.sender === "user"}
          emptyText="هنوز پیامی ندارید. سوال یا درخواست خود را اینجا بنویسید."
          scrollRef={scrollRef}
          onScroll={onScroll}
          onAttachmentOpen={onAttachmentOpen}
          orderLiveMap={orderLiveMap}
        />
      )}

      <ChatComposerBar
        busy={busy}
        onSend={send}
        placeholder="پیام خود را بنویسید…"
        beamRoundKey={composerBeamKey}
        loadSubs={loadUserSubs}
        loadOrders={loadUserOrders}
        isAdmin={false}
        onNavigate={onNavigate}
      />
    </div>
  );
}

function AdminThreadList({
  threads,
  loading,
  onSelect,
}: {
  threads: ChatThread[];
  loading: boolean;
  onSelect: (t: ChatThread) => void;
}) {
  if (loading) {
    return <OrbLoaderPanel variant="admin" message="در حال بارگذاری گفتگوها…" />;
  }

  if (!threads.length) {
    return (
      <div className="flex flex-1 flex-col items-center justify-center gap-2 p-8 text-center">
        <MessageCircle className="size-10 text-neutral-600" />
        <p className="text-sm text-neutral-400">هنوز گفتگویی ثبت نشده</p>
      </div>
    );
  }

  return (
    <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain [-webkit-overflow-scrolling:touch]">
      {threads.map((t) => (
        <button
          key={t.user_id}
          type="button"
          onClick={() => {
            haptic();
            onSelect(t);
          }}
          className="flex w-full items-start gap-3 border-b border-white/8 px-4 py-3 text-start active:bg-white/5"
        >
          <div className="flex size-10 shrink-0 items-center justify-center rounded-full bg-white/10 text-xs font-bold">
            {(threadTitle(t)[0] || "?").toUpperCase()}
          </div>
          <div className="min-w-0 flex-1">
            <div className="flex items-center justify-between gap-2">
              <span className="truncate text-sm font-semibold">{threadTitle(t)}</span>
              {t.last_message_at && (
                <span className="shrink-0 text-[10px] text-neutral-500">{formatChatTime(t.last_message_at)}</span>
              )}
            </div>
            <p className="mt-0.5 truncate text-xs text-neutral-400">
              {t.last_sender === "admin" ? "شما: " : ""}
              {t.last_message || "—"}
            </p>
            {t.assigned_name ? (
              <p className="mt-0.5 text-[10px] text-sky-300/80">مسئول: {t.assigned_name}</p>
            ) : (
              <p className="mt-0.5 text-[10px] text-neutral-600">بدون مسئول شیفت</p>
            )}
          </div>
          {t.unread_count > 0 && (
            <span className="mt-1 flex size-5 shrink-0 items-center justify-center rounded-full bg-white text-[10px] font-bold text-black">
              {faNum(Math.min(t.unread_count, 9))}
            </span>
          )}
        </button>
      ))}
    </div>
  );
}

function AdminThreadChat({
  thread,
  active,
  onBack,
  onUnreadChange,
  onAttachmentOpen,
  onNavigate,
  onOrderAction,
  orderRefreshRef,
  onThreadMeta,
}: {
  thread: ChatThread;
  active: boolean;
  onBack: () => void;
  onUnreadChange?: (n: number) => void;
  onAttachmentOpen?: (att: ChatAttachment) => void;
  onNavigate?: (tab: "subs" | "shop" | "admin") => void;
  onOrderAction?: () => void;
  orderRefreshRef?: React.MutableRefObject<(() => void) | null>;
  onThreadMeta?: (patch: Partial<ChatThread>) => void;
}) {
  const [messages, setMessages] = useState<ChatMsg[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [claimBusy, setClaimBusy] = useState(false);
  const [orderLiveMap, setOrderLiveMap] = useState<Map<number, import("@/api").ChatOrderItem>>(new Map());
  const scrollRef = useRef<HTMLDivElement>(null);
  const lastIdRef = useRef(0);
  const inflightRef = useRef(false);
  const onUnreadRef = useRef(onUnreadChange);
  onUnreadRef.current = onUnreadChange;
  const { nearBottomRef, onScroll, scrollToBottom } = useNearBottom(scrollRef);
  const [composerBeamKey, setComposerBeamKey] = useState(0);

  const pulseComposerBeam = useCallback(() => {
    setComposerBeamKey((k) => k + 1);
  }, []);

  const refreshOrders = useCallback(async () => {
    try {
      const data = await api.adminThreadOrders(thread.user_id);
      setOrderLiveMap(new Map(data.items.map((o) => [o.id, o])));
    } catch {
      /* optional */
    }
  }, [thread.user_id]);

  useEffect(() => {
    if (!active) return;
    void refreshOrders();
  }, [active, refreshOrders]);

  useEffect(() => {
    if (!orderRefreshRef) return;
    orderRefreshRef.current = () => {
      void refreshOrders();
    };
    return () => {
      orderRefreshRef.current = null;
    };
  }, [orderRefreshRef, refreshOrders]);

  useEffect(() => {
    if (!active) return;
    pulseComposerBeam();
  }, [active, thread.user_id, pulseComposerBeam]);

  const poll = useCallback(
    async (initial = false) => {
      if (!active && !initial) return;
      if (inflightRef.current) return;
      inflightRef.current = true;
      try {
        const after = initial ? 0 : lastIdRef.current;
        const data = await api.adminChatMessages(thread.user_id, after, false);
        onUnreadRef.current?.(data.unread_total);
        if (initial) {
          setMessages(data.messages);
          if (data.messages.length) lastIdRef.current = data.messages[data.messages.length - 1]!.id;
          requestAnimationFrame(() => scrollToBottom(false));
        } else if (data.latest_id > lastIdRef.current) {
          setMessages((prev) => {
            const merged = mergeMessages(prev.filter((m) => m.id > 0), data.messages);
            if (merged.length) lastIdRef.current = merged[merged.length - 1]!.id;
            return merged;
          });
          if (nearBottomRef.current) {
            requestAnimationFrame(() => scrollToBottom(true));
          }
        }
      } finally {
        inflightRef.current = false;
        if (initial) setLoading(false);
      }
    },
    [active, thread.user_id, scrollToBottom, nearBottomRef],
  );

  useEffect(() => {
    if (!active) return;
    lastIdRef.current = 0;
    setLoading(true);
    void api.adminChatMarkRead(thread.user_id).catch(() => undefined);
    void poll(true);
    const t = window.setInterval(() => void poll(false), POLL_MS);
    return () => window.clearInterval(t);
  }, [active, poll, thread.user_id]);

  const loadThreadSubs = useCallback(async () => {
    const data = await api.adminThreadSubscriptions(thread.user_id);
    return data.items;
  }, [thread.user_id]);

  const loadThreadOrders = useCallback(async () => {
    const data = await api.adminThreadOrders(thread.user_id);
    return data.items;
  }, [thread.user_id]);

  const send = async (body: string, attachmentDrafts: ChatAttachmentDraft[]) => {
    const tempId = -Date.now();
    const optimisticAttachments = attachmentDrafts.map(draftToAttachment);
    const optimistic: ChatMsg = {
      id: tempId,
      user_id: thread.user_id,
      sender: "admin",
      body,
      attachments: optimisticAttachments,
      created_at: new Date().toISOString(),
      read_at: null,
      pending: true,
    };
    setMessages((prev) => [...prev, optimistic]);
    requestAnimationFrame(() => scrollToBottom(true));
    pulseComposerBeam();
    setBusy(true);
    try {
      const res = await api.adminChatSend(thread.user_id, body, draftToInput(attachmentDrafts));
      setMessages((prev) =>
        mergeMessages(
          prev.filter((m) => m.id !== tempId),
          [res.message],
        ),
      );
      lastIdRef.current = res.message.id;
    } catch {
      setMessages((prev) => prev.filter((m) => m.id !== tempId));
      throw new Error("send failed");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <div className="shrink-0 border-b border-white/10 px-3 py-2.5">
        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={() => {
              haptic();
              onBack();
            }}
            className="inline-flex size-9 shrink-0 items-center justify-center rounded-xl active:bg-white/10"
            aria-label="بازگشت"
          >
            <ArrowRight className="size-5" />
          </button>
          <div className="min-w-0 flex-1">
            <div className="truncate text-sm font-semibold">{threadTitle(thread)}</div>
            <p className="text-[11px] text-neutral-400">
              {faNum(thread.telegram_id)}
              {thread.assigned_name ? ` · مسئول: ${thread.assigned_name}` : ""}
            </p>
          </div>
          <button
            type="button"
            disabled={claimBusy}
            onClick={() => {
              void (async () => {
                setClaimBusy(true);
                try {
                  if (thread.assigned_admin_id) {
                    await api.adminReleaseChat(thread.user_id);
                    onThreadMeta?.({ assigned_admin_id: null, assigned_name: null });
                  } else {
                    const res = await api.adminClaimChat(thread.user_id);
                    onThreadMeta?.({
                      assigned_admin_id: res.assigned_admin_id,
                      assigned_name: res.assigned_name,
                    });
                  }
                  haptic();
                } catch {
                  /* ignore */
                } finally {
                  setClaimBusy(false);
                }
              })();
            }}
            className="shrink-0 rounded-xl border border-white/15 bg-white/5 px-2.5 py-1.5 text-[11px] font-medium text-neutral-100 active:bg-white/10 disabled:opacity-50"
          >
            {thread.assigned_admin_id ? "آزاد کردن" : "قبول شیفت"}
          </button>
        </div>
      </div>

      {loading ? (
        <OrbLoaderPanel variant="admin" message="در حال بارگذاری…" />
      ) : (
        <MessageList
          messages={messages}
          isMine={(m) => m.sender === "admin"}
          emptyText="هنوز پیامی در این گفتگو نیست."
          scrollRef={scrollRef}
          onScroll={onScroll}
          onAttachmentOpen={onAttachmentOpen}
          orderLiveMap={orderLiveMap}
        />
      )}

      {!loading && (
        <ChatComposerBar
          busy={busy}
          onSend={send}
          placeholder="پاسخ به کاربر…"
          beamRoundKey={composerBeamKey}
          loadSubs={loadThreadSubs}
          loadOrders={loadThreadOrders}
          isAdmin
          threadUserId={thread.user_id}
          onNavigate={onNavigate}
          onOrderAction={onOrderAction}
        />
      )}
    </div>
  );
}

export function ChatPanel({
  isAdmin,
  active,
  openThreadUserId,
  onOpenThreadHandled,
  onUnreadChange,
  onNavigate,
  onOrderAction,
  onNotify,
}: {
  isAdmin: boolean;
  active: boolean;
  openThreadUserId?: number | null;
  onOpenThreadHandled?: () => void;
  onUnreadChange?: (n: number) => void;
  onNavigate?: (tab: "subs" | "shop" | "admin") => void;
  onOrderAction?: () => void;
  onNotify?: (message: string, kind?: "success" | "error" | "info") => void;
}) {
  const [threads, setThreads] = useState<ChatThread[]>([]);
  const [loadingThreads, setLoadingThreads] = useState(isAdmin);
  const [activeThread, setActiveThread] = useState<ChatThread | null>(null);
  const [onDuty, setOnDuty] = useState(false);
  const [dutyCount, setDutyCount] = useState(0);
  const [dutyBusy, setDutyBusy] = useState(false);
  const [detailAttachment, setDetailAttachment] = useState<AttachmentDetailTarget | null>(null);
  const inflightRef = useRef(false);
  const onUnreadRef = useRef(onUnreadChange);
  onUnreadRef.current = onUnreadChange;
  const orderRefreshRef = useRef<(() => void) | null>(null);

  const handleOrderAction = useCallback(() => {
    orderRefreshRef.current?.();
    onOrderAction?.();
  }, [onOrderAction]);

  const openAttachmentDetail = useCallback((att: ChatAttachment) => {
    setDetailAttachment(att);
  }, []);

  const refreshThreads = useCallback(async () => {
    if (!isAdmin || !active || activeThread) return;
    if (inflightRef.current) return;
    inflightRef.current = true;
    try {
      const data = await api.adminChatThreads();
      setThreads(data.threads);
      setOnDuty(Boolean(data.on_duty));
      setDutyCount(Number(data.duty_count || 0));
      onUnreadRef.current?.(data.unread_total);
    } finally {
      inflightRef.current = false;
      setLoadingThreads(false);
    }
  }, [isAdmin, active, activeThread]);

  useEffect(() => {
    if (!isAdmin || !active || activeThread) return;
    setLoadingThreads(true);
    void refreshThreads();
    const t = window.setInterval(() => void refreshThreads(), POLL_MS * 2);
    return () => window.clearInterval(t);
  }, [isAdmin, active, activeThread, refreshThreads]);

  useEffect(() => {
    if (!isAdmin || !active || !openThreadUserId) return;
    let cancelled = false;
    void (async () => {
      try {
        const data = await api.adminChatThreads();
        if (cancelled) return;
        setThreads(data.threads);
        onUnreadRef.current?.(data.unread_total);
        let thread = data.threads.find((t) => t.user_id === openThreadUserId) ?? null;
        if (!thread) {
          try {
            const u = await api.adminUserDetail(openThreadUserId);
            if (cancelled) return;
            thread = {
              user_id: u.id,
              telegram_id: u.telegram_id,
              username: u.username,
              full_name: u.full_name,
              last_message: "",
              last_message_at: null,
              last_sender: null,
              unread_count: u.chat_unread || 0,
            };
            setThreads((prev) => (prev.some((t) => t.user_id === thread!.user_id) ? prev : [thread!, ...prev]));
          } catch {
            thread = null;
          }
        }
        if (thread) setActiveThread(thread);
      } finally {
        if (!cancelled) onOpenThreadHandled?.();
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [isAdmin, active, openThreadUserId, onOpenThreadHandled]);

  if (!isAdmin) {
    return (
      <>
        <UserChat
          active={active}
          onUnreadChange={onUnreadChange}
          onAttachmentOpen={openAttachmentDetail}
          onNavigate={onNavigate}
          orderRefreshRef={orderRefreshRef}
        />
        <ChatAttachmentDetailSheet
          open={detailAttachment !== null}
          onClose={() => setDetailAttachment(null)}
          attachment={detailAttachment}
          context={{
            isAdmin: false,
            mode: "message",
            onNavigate,
            onOrderAction: handleOrderAction,
            onNotify,
          }}
        />
      </>
    );
  }

  if (activeThread) {
    return (
      <>
        <AdminThreadChat
          thread={activeThread}
          active={active}
          onBack={() => {
            setActiveThread(null);
            void refreshThreads();
          }}
          onUnreadChange={onUnreadChange}
          onAttachmentOpen={openAttachmentDetail}
          onNavigate={onNavigate}
          onOrderAction={handleOrderAction}
          orderRefreshRef={orderRefreshRef}
          onThreadMeta={(patch) => {
            setActiveThread((prev) => (prev ? { ...prev, ...patch } : prev));
            setThreads((prev) =>
              prev.map((t) => (t.user_id === activeThread.user_id ? { ...t, ...patch } : t)),
            );
          }}
        />
        <ChatAttachmentDetailSheet
          open={detailAttachment !== null}
          onClose={() => setDetailAttachment(null)}
          attachment={detailAttachment}
          context={{
            isAdmin: true,
            threadUserId: activeThread.user_id,
            mode: "message",
            onNavigate,
            onOrderAction: handleOrderAction,
            onNotify,
          }}
        />
      </>
    );
  }

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <div className="shrink-0 border-b border-white/10 px-3 py-2">
        <div className="flex items-center justify-between gap-2">
          <div className="flex items-center gap-1.5 text-xs font-semibold text-neutral-300">
            <MessageCircle className="size-3.5 text-neutral-500" />
            گفتگو با کاربران
          </div>
          <button
            type="button"
            disabled={dutyBusy}
            onClick={() => {
              void (async () => {
                setDutyBusy(true);
                try {
                  const res = await api.adminSetDuty(!onDuty);
                  setOnDuty(res.on_duty);
                  setDutyCount(res.duty_count);
                  haptic();
                } catch {
                  /* ignore */
                } finally {
                  setDutyBusy(false);
                }
              })();
            }}
            className={cn(
              "rounded-lg border px-2 py-1 text-[10px] font-medium disabled:opacity-50",
              onDuty
                ? "border-emerald-500/35 bg-emerald-500/15 text-emerald-100"
                : "border-white/12 bg-white/5 text-neutral-300",
            )}
          >
            {onDuty ? `آن‌دیوتی · ${faNum(dutyCount)}` : "شروع شیفت"}
          </button>
        </div>
      </div>
      <AdminThreadList threads={threads} loading={loadingThreads && active} onSelect={setActiveThread} />
    </div>
  );
}
