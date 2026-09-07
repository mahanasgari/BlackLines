import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { ArrowUp, FileText, Link2, Package, Plus, X } from "lucide-react";
import { api, haptic, type ChatOrderItem, type Sub } from "@/api";
import { ChatComposerRotateBeam } from "@/components/chat-beam";
import { cn, faNum } from "@/lib/utils";
import type { ChatAttachmentDraft } from "@/components/chat-attachment-picker";
import { ChatAttachmentDetailSheet } from "@/components/chat-attachment-detail-sheet";

const MAX_ATTACHMENTS = 3;

type MenuStep = "root" | "subs" | "links" | "orders";

type MenuRow = {
  key: string;
  name: string;
  desc: string;
  icon: ReactNode;
  disabled?: boolean;
};

function subTitle(sub: Sub) {
  return sub.label?.trim() || sub.plan_title || sub.email;
}

function orderTitle(order: ChatOrderItem) {
  return `${order.kind_label} · ${order.plan_title}`;
}

function GlideHighlight({
  box,
  visible,
}: {
  box: { top: number; height: number } | null;
  visible: boolean;
}) {
  return (
    <span
      aria-hidden
      className="pointer-events-none absolute inset-x-1 rounded-lg bg-white/10"
      style={{
        top: box?.top ?? 0,
        height: box?.height ?? 0,
        opacity: visible && box ? 1 : 0,
        transition:
          "top 220ms cubic-bezier(0.23,1,0.32,1), height 220ms cubic-bezier(0.23,1,0.32,1), opacity 150ms ease",
      }}
    />
  );
}

function chipLabel(item: ChatAttachmentDraft) {
  if (item.type === "order") return `فاکتور #${faNum(item.order_id)}`;
  if (item.type === "link") return `لینک · ${item.label || item.plan_title}`;
  return item.label || item.plan_title;
}

export function ChatComposerBar({
  busy,
  placeholder,
  beamRoundKey = 0,
  onSend,
  loadSubs,
  loadOrders,
  isAdmin = false,
  threadUserId,
  onNavigate,
  onOrderAction,
}: {
  busy: boolean;
  placeholder: string;
  /** Increment to play one rotating border-beam round (tab/thread open or send). */
  beamRoundKey?: number;
  onSend: (text: string, attachments: ChatAttachmentDraft[]) => Promise<void>;
  loadSubs: () => Promise<Sub[]>;
  loadOrders: () => Promise<ChatOrderItem[]>;
  isAdmin?: boolean;
  threadUserId?: number;
  onNavigate?: (tab: "subs" | "shop" | "admin") => void;
  onOrderAction?: () => void;
}) {
  const [draft, setDraft] = useState("");
  const [attachments, setAttachments] = useState<ChatAttachmentDraft[]>([]);
  const [previewIndex, setPreviewIndex] = useState<number | null>(null);
  const [menuOpen, setMenuOpen] = useState(false);
  const [menuStep, setMenuStep] = useState<MenuStep>("root");
  const [linkPickMode, setLinkPickMode] = useState(false);
  const [subs, setSubs] = useState<Sub[]>([]);
  const [orders, setOrders] = useState<ChatOrderItem[]>([]);
  const [linksSub, setLinksSub] = useState<Sub | null>(null);
  const [links, setLinks] = useState<string[]>([]);
  const [loading, setLoading] = useState(false);
  const [linksLoading, setLinksLoading] = useState(false);
  const [active, setActive] = useState(0);
  const [engaged, setEngaged] = useState(false);
  const [expanded, setExpanded] = useState(false);
  const [rowBox, setRowBox] = useState<{ top: number; height: number } | null>(null);

  const anchorRef = useRef<HTMLDivElement>(null);
  const controlsRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);
  const measureRef = useRef<HTMLSpanElement>(null);
  const rowRefs = useRef<(HTMLButtonElement | null)[]>([]);

  const atMax = attachments.length >= MAX_ATTACHMENTS;
  const canSend = Boolean(draft.trim() || attachments.length) && !busy;
  const wide = expanded || draft.includes("\n");

  const rootRows: MenuRow[] = [
    {
      key: "sub",
      name: "اشتراک",
      desc: "ارسال اطلاعات یک اشتراک",
      icon: <Package className="size-4" />,
      disabled: atMax,
    },
    {
      key: "link",
      name: "لینک VPN",
      desc: "یک لینک vless از اشتراک",
      icon: <Link2 className="size-4" />,
      disabled: atMax,
    },
    {
      key: "order",
      name: "فاکتور",
      desc: "خرید VPN یا شارژ کیف‌پول",
      icon: <FileText className="size-4" />,
      disabled: atMax,
    },
  ];

  const rows: MenuRow[] =
    menuStep === "root"
      ? rootRows
      : menuStep === "subs"
        ? subs.map((s) => ({
            key: `sub-${s.id}`,
            name: subTitle(s),
            desc: `${s.plan_title}${s.traffic_label ? ` · ${s.traffic_label}` : ""}`,
            icon: (
              <span className="text-[10px] font-bold">{(subTitle(s)[0] || "?").toUpperCase()}</span>
            ),
          }))
        : menuStep === "orders"
          ? orders.map((o) => ({
              key: `ord-${o.id}`,
              name: orderTitle(o),
              desc: `${o.amount_label} · ${o.status_label}${o.has_receipt ? " · رسید" : ""}`,
              icon: <FileText className="size-3.5" />,
            }))
          : links.map((link, i) => ({
              key: `link-${i}`,
              name: `لینک ${faNum(i + 1)}`,
              desc: link.length > 48 ? `${link.slice(0, 47)}…` : link,
              icon: <Link2 className="size-3.5" />,
            }));

  const resetMenu = useCallback(() => {
    setMenuStep("root");
    setLinkPickMode(false);
    setLinksSub(null);
    setLinks([]);
    setLinksLoading(false);
    setActive(0);
    setEngaged(false);
  }, []);

  const closeMenu = useCallback(() => {
    setMenuOpen(false);
    resetMenu();
  }, [resetMenu]);

  const loadCatalog = useCallback(async () => {
    setLoading(true);
    try {
      const [subsData, ordersData] = await Promise.all([loadSubs(), loadOrders()]);
      setSubs(subsData);
      setOrders(ordersData);
    } catch {
      setSubs([]);
      setOrders([]);
    } finally {
      setLoading(false);
    }
  }, [loadSubs, loadOrders]);

  useEffect(() => {
    if (!menuOpen) return;
    if (menuStep === "root") return;
    if (menuStep === "subs" && subs.length === 0 && !loading) void loadCatalog();
    if (menuStep === "orders" && orders.length === 0 && !loading) void loadCatalog();
  }, [menuOpen, menuStep, subs.length, orders.length, loading, loadCatalog]);

  useEffect(() => {
    setActive(0);
    setEngaged(false);
  }, [menuStep, menuOpen, rows.length]);

  useLayoutEffect(() => {
    const target = rowRefs.current[active];
    if (target) setRowBox({ top: target.offsetTop, height: target.offsetHeight });
  }, [menuOpen, menuStep, active, engaged, rows.length, loading, linksLoading]);

  useLayoutEffect(() => {
    const input = inputRef.current;
    const controls = controlsRef.current;
    const measure = measureRef.current;
    if (!input || !controls || !measure) return;

    const sendWidth = 28;
    const plusWidth = 28;
    const gaps = 16;
    const inlineInputWidth = controls.clientWidth - sendWidth - plusWidth - gaps;
    const needsFullWidth = draft.includes("\n") || measure.offsetWidth + 8 > inlineInputWidth;
    if (needsFullWidth !== expanded) setExpanded(needsFullWidth);

    const minHeight = 28;
    const maxHeight = 100;
    input.style.height = "0px";
    const contentHeight = input.scrollHeight;
    input.style.height = `${Math.min(Math.max(contentHeight, minHeight), maxHeight)}px`;
    input.style.overflowY = contentHeight > maxHeight ? "auto" : "hidden";
  }, [draft, expanded]);

  useEffect(() => {
    if (!menuOpen) return;
    const close = (event: PointerEvent) => {
      if (!(event.target as Element).closest("[data-chat-composer]")) closeMenu();
    };
    document.addEventListener("pointerdown", close);
    return () => document.removeEventListener("pointerdown", close);
  }, [menuOpen, closeMenu]);

  const pickSub = (sub: Sub) => {
    if (atMax) return;
    haptic();
    setAttachments((prev) => [
      ...prev,
      {
        type: "subscription",
        subscription_id: sub.id,
        email: sub.email,
        label: sub.label ?? null,
        plan_title: sub.plan_title,
      },
    ]);
    closeMenu();
    inputRef.current?.focus();
  };

  const pickOrder = (order: ChatOrderItem) => {
    if (atMax) return;
    haptic();
    setAttachments((prev) => [
      ...prev,
      {
        type: "order",
        order_id: order.id,
        plan_title: order.plan_title,
        kind: order.kind,
        kind_label: order.kind_label,
        amount_label: order.amount_label,
        status_label: order.status_label,
        has_receipt: order.has_receipt,
      },
    ]);
    closeMenu();
    inputRef.current?.focus();
  };

  const openLinksFor = async (sub: Sub) => {
    haptic();
    setLinksSub(sub);
    setMenuStep("links");
    setLinksLoading(true);
    try {
      const data = await api.links(sub.id);
      setLinks(data.links);
    } catch {
      setLinks([]);
    } finally {
      setLinksLoading(false);
    }
  };

  const pickLink = (index: number, link: string) => {
    if (!linksSub || atMax) return;
    haptic();
    const preview = link.length > 52 ? `${link.slice(0, 51)}…` : link;
    setAttachments((prev) => [
      ...prev,
      {
        type: "link",
        subscription_id: linksSub.id,
        link_index: index,
        email: linksSub.email,
        label: linksSub.label ?? null,
        plan_title: linksSub.plan_title,
        link_preview: preview,
      },
    ]);
    closeMenu();
    inputRef.current?.focus();
  };

  const handleMenuPick = (row: MenuRow) => {
    if (row.disabled) return;
    if (menuStep === "root") {
      if (row.key === "sub") {
        setLinkPickMode(false);
        setMenuStep("subs");
        void loadCatalog();
        return;
      }
      if (row.key === "link") {
        setLinkPickMode(true);
        setMenuStep("subs");
        void loadCatalog();
        return;
      }
      if (row.key === "order") {
        setMenuStep("orders");
        void loadCatalog();
      }
      return;
    }
    if (menuStep === "subs") {
      const subId = Number(row.key.replace("sub-", ""));
      const sub = subs.find((s) => s.id === subId);
      if (!sub) return;
      if (linkPickMode) void openLinksFor(sub);
      else pickSub(sub);
      return;
    }
    if (menuStep === "orders") {
      const orderId = Number(row.key.replace("ord-", ""));
      const order = orders.find((o) => o.id === orderId);
      if (order) pickOrder(order);
      return;
    }
    if (menuStep === "links") {
      const linkIndex = Number(row.key.replace("link-", ""));
      const link = links[linkIndex];
      if (link) pickLink(linkIndex, link);
    }
  };

  const send = async () => {
    if (!canSend) return;
    haptic();
    const body = draft.trim();
    const toSend = attachments;
    setDraft("");
    setAttachments([]);
    if (inputRef.current) inputRef.current.style.height = "auto";
    closeMenu();
    try {
      await onSend(body, toSend);
    } finally {
      inputRef.current?.focus();
    }
  };

  const menuTitle =
    menuStep === "root"
      ? "افزودن پیوست"
      : menuStep === "subs"
        ? linkPickMode
          ? "انتخاب اشتراک برای لینک"
          : "انتخاب اشتراک"
        : menuStep === "orders"
          ? "انتخاب فاکتور"
          : linksSub
            ? `لینک‌های ${subTitle(linksSub)}`
            : "انتخاب لینک";

  return (
    <div
      data-chat-composer
      className="shrink-0 border-t border-white/10 bg-black/80 p-3 pb-[max(0.75rem,env(safe-area-inset-bottom))] backdrop-blur-md"
    >
      <div ref={anchorRef} className="relative">
        {menuOpen && (
          <div
            onMouseLeave={() => setEngaged(false)}
            className="absolute inset-x-0 bottom-full z-20 mb-2 overflow-hidden rounded-xl border border-white/12 bg-sheet-elevated p-1 shadow-[0_8px_32px_rgba(0,0,0,0.18)]"
            style={{
              animation: "pop-in 180ms cubic-bezier(0.23,1,0.32,1) both",
              transformOrigin: "bottom center",
            }}
          >
            {menuStep !== "root" && (
              <button
                type="button"
                onClick={() => {
                  haptic();
                  if (menuStep === "links") {
                    setMenuStep("subs");
                    setLinksSub(null);
                    setLinks([]);
                    return;
                  }
                  resetMenu();
                }}
                className="mb-0.5 flex h-8 w-full items-center px-2 text-[11px] text-neutral-400 active:text-white"
              >
                ← بازگشت
              </button>
            )}
            <div className="border-b border-white/8 px-2 py-1.5 text-[11px] font-medium text-neutral-300">
              {menuTitle}
            </div>
            <div className="relative max-h-[min(240px,40dvh)] overflow-y-auto overscroll-contain py-0.5">
              <GlideHighlight box={rowBox} visible={engaged && rows.length > 0 && !loading && !linksLoading} />
              {(loading || linksLoading) && (
                <div className="flex h-16 items-center justify-center text-[12px] text-neutral-500">
                  در حال بارگذاری…
                </div>
              )}
              {!loading &&
                !linksLoading &&
                rows.map((row, i) => (
                  <button
                    key={row.key}
                    type="button"
                    ref={(el) => {
                      rowRefs.current[i] = el;
                    }}
                    disabled={row.disabled}
                    onMouseDown={(e) => e.preventDefault()}
                    onMouseEnter={() => {
                      setActive(i);
                      setEngaged(true);
                    }}
                    onClick={() => handleMenuPick(row)}
                    className="relative z-10 flex min-h-9 w-full items-center gap-2.5 rounded-lg px-2 py-1.5 text-start disabled:opacity-40"
                  >
                    <span className="flex size-7 shrink-0 items-center justify-center rounded-lg bg-white/8 text-neutral-300">
                      {row.icon}
                    </span>
                    <span className="min-w-0 flex-1">
                      <span className="block truncate text-[12.5px] font-medium text-white">{row.name}</span>
                      <span className="mt-0.5 block truncate font-mono text-[10px] text-neutral-500" dir="ltr">
                        {row.desc}
                      </span>
                    </span>
                  </button>
                ))}
              {!loading && !linksLoading && rows.length === 0 && (
                <div className="flex h-16 items-center justify-center px-2 text-center text-[12px] text-neutral-500">
                  {menuStep === "subs" ? "اشتراکی پیدا نشد" : menuStep === "orders" ? "فاکتوری پیدا نشد" : "موردی نیست"}
                </div>
              )}
            </div>
            {atMax && (
              <div className="border-t border-white/8 px-2 py-1.5 text-center text-[10px] text-amber-400/90">
                حداکثر {faNum(MAX_ATTACHMENTS)} پیوست
              </div>
            )}
          </div>
        )}

        <ChatComposerRotateBeam roundKey={beamRoundKey}>
        <div
          className={cn(
            "relative isolate flex flex-col overflow-hidden rounded-[18px] border border-white/12 bg-sheet shadow-[0_2px_12px_rgba(0,0,0,0.12)] transition-[border-color] duration-150 focus-within:border-white/22",
            attachments.length > 0 || wide ? "gap-2 p-2.5" : "gap-1.5 p-1.5",
          )}
        >
          <span
            ref={measureRef}
            aria-hidden
            className="pointer-events-none invisible absolute whitespace-pre text-[13px] leading-[18px]"
          >
            {draft}
          </span>

          {attachments.length > 0 && (
            <div className="flex flex-wrap gap-1.5 px-0.5">
              {attachments.map((item, i) => (
                <span
                  key={`${item.type}-${item.type === "order" ? item.order_id : item.subscription_id}-${item.type === "link" ? item.link_index : i}`}
                  className="flex h-7 max-w-full items-center gap-1.5 rounded-full border border-white/12 bg-white/8 py-1 ps-2 pe-1 text-[11px] text-neutral-200"
                  style={{ animation: "pop-in 200ms cubic-bezier(0.23,1,0.32,1) both" }}
                >
                  {item.type === "order" ? (
                    <FileText className="size-3 shrink-0" />
                  ) : item.type === "link" ? (
                    <Link2 className="size-3 shrink-0" />
                  ) : (
                    <Package className="size-3 shrink-0" />
                  )}
                  <button
                    type="button"
                    onClick={() => {
                      haptic();
                      setPreviewIndex(i);
                    }}
                    className="min-w-0 truncate text-start active:opacity-70"
                  >
                    {chipLabel(item)}
                  </button>
                  <button
                    type="button"
                    aria-label="حذف پیوست"
                    onClick={() => setAttachments((prev) => prev.filter((_, idx) => idx !== i))}
                    className="flex size-5 shrink-0 items-center justify-center rounded-full text-neutral-400 transition-colors hover:bg-white/12 hover:text-white"
                  >
                    <X className="size-3" />
                  </button>
                </span>
              ))}
            </div>
          )}

          <div
            ref={controlsRef}
            className={cn(
              "grid items-end gap-x-1.5 gap-y-1.5",
              wide ? "grid-cols-[28px_minmax(0,1fr)_28px]" : "grid-cols-[28px_minmax(0,1fr)_28px]",
            )}
          >
            <button
              type="button"
              aria-label="افزودن پیوست"
              aria-expanded={menuOpen}
              disabled={busy}
              onClick={() => {
                haptic();
                setMenuOpen((o) => {
                  if (!o) resetMenu();
                  return !o;
                });
                inputRef.current?.focus();
              }}
              className={cn(
                "flex size-7 shrink-0 items-center justify-center text-neutral-400 transition-[background-color,color,transform] duration-150 hover:bg-white/10 hover:text-white active:scale-[0.94] rounded-lg",
                menuOpen && "bg-white/10 text-white",
                wide ? "col-start-1 row-start-2" : "col-start-1 row-start-1",
              )}
            >
              <Plus className="size-4" strokeWidth={2.2} />
            </button>

            <textarea
              ref={inputRef}
              rows={1}
              value={draft}
              disabled={busy}
              onChange={(e) => {
                setDraft(e.target.value);
                setMenuOpen(false);
              }}
              onKeyDown={(e) => {
                if (menuOpen && rows.length > 0) {
                  if (e.key === "ArrowDown" || e.key === "ArrowUp") {
                    e.preventDefault();
                    setEngaged(true);
                    setActive((c) => (c + (e.key === "ArrowDown" ? 1 : rows.length - 1)) % rows.length);
                    return;
                  }
                  if ((e.key === "Enter" && !e.shiftKey) || e.key === "Tab") {
                    e.preventDefault();
                    handleMenuPick(rows[active]!);
                    return;
                  }
                }
                if (e.key === "Escape") {
                  closeMenu();
                  return;
                }
                if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing) {
                  e.preventDefault();
                  void send();
                }
              }}
              placeholder={placeholder}
              aria-label="پیام"
              className={cn(
                "min-h-7 w-full min-w-0 resize-none bg-transparent px-1 py-[5px] text-[13px] leading-[18px] text-white outline-none [overflow-wrap:anywhere] placeholder:text-neutral-500",
                wide ? "col-span-full col-start-1 row-start-1 max-h-[100px]" : "col-start-2 row-start-1 max-h-[100px]",
              )}
            />

            <button
              type="button"
              aria-label="ارسال"
              disabled={!canSend}
              onClick={() => void send()}
              className={cn(
                "flex size-7 shrink-0 items-center justify-center rounded-lg transition-[background-color,color,transform] duration-200 enabled:active:scale-[0.94]",
                wide ? "col-start-3 row-start-2" : "col-start-3 row-start-1",
                canSend ? "bg-primary text-primary-foreground" : "bg-white/15 text-neutral-500",
              )}
            >
              <ArrowUp className="size-4" strokeWidth={2.4} />
            </button>
          </div>
        </div>
        </ChatComposerRotateBeam>
      </div>

      <ChatAttachmentDetailSheet
        open={previewIndex !== null && attachments[previewIndex] != null}
        onClose={() => setPreviewIndex(null)}
        attachment={previewIndex !== null ? attachments[previewIndex] ?? null : null}
        context={{
          isAdmin,
          threadUserId,
          mode: "composer",
          onNavigate,
          onOrderAction,
          onComposerRemove:
            previewIndex !== null
              ? () => setAttachments((prev) => prev.filter((_, idx) => idx !== previewIndex))
              : undefined,
        }}
      />
    </div>
  );
}
