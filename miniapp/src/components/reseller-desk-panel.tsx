import { useEffect, useMemo, useState } from "react";
import {
  ArrowRightLeft,
  Check,
  Copy,
  RefreshCw,
  Search,
  Send,
  Store,
  Users,
} from "lucide-react";
import { api, haptic, type ResellerDeskItem, type ResellerDeskResponse } from "@/api";
import { TgButton } from "@/components/tg-button";
import { TgSheet } from "@/components/tg-sheet";
import { Input } from "@/components/ui/input";
import { cn, faNum } from "@/lib/utils";

type FilterId = "all" | "unsent" | "expiring" | "expired";

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

function shareConfigLink(url: string, name: string) {
  const text = `لینک کانفیگ ${name}`;
  const shareUrl = `https://t.me/share/url?url=${encodeURIComponent(url)}&text=${encodeURIComponent(text)}`;
  const tg = window.Telegram?.WebApp;
  if (tg?.openTelegramLink) {
    tg.openTelegramLink(shareUrl);
    return;
  }
  if (navigator.share) {
    void navigator.share({ title: text, url }).catch(() => window.open(shareUrl, "_blank"));
    return;
  }
  window.open(shareUrl, "_blank");
}

function daysLeftLabel(item: ResellerDeskItem) {
  if (item.is_payg && !item.expires_at) return "بدون انقضا";
  if (item.expired) return "منقضی";
  if (item.days_left == null) return "بدون انقضا";
  if (item.days_left < 0) return "منقضی";
  if (item.days_left === 0) return "امروز تمام می‌شود";
  return `${faNum(item.days_left)} روز مانده`;
}

function contactLine(item: ResellerDeskItem) {
  const bits: string[] = [];
  if (item.customer_phone) bits.push(item.customer_phone);
  if (item.customer_telegram_id) {
    bits.push(
      item.customer_telegram_id.startsWith("@")
        ? item.customer_telegram_id
        : `@${item.customer_telegram_id}`,
    );
  }
  return bits.join(" · ");
}

export function ResellerDeskEntry({
  summary,
  onOpen,
}: {
  summary: ResellerDeskResponse["summary"] | null;
  onOpen: () => void;
}) {
  const total = summary?.total ?? 0;
  const unsent = summary?.unsent ?? 0;
  const expiring = summary?.expiring_soon ?? 0;
  if (total <= 0) return null;

  const hint = [
    unsent > 0 ? `${faNum(unsent)} لینک نرفته` : null,
    expiring > 0 ? `${faNum(expiring)} رو به اتمام` : null,
  ]
    .filter(Boolean)
    .join(" · ");

  return (
    <button
      type="button"
      onClick={() => {
        haptic();
        onOpen();
      }}
      className="flex w-full items-center gap-3 rounded-2xl border border-teal-500/25 bg-teal-500/[0.07] px-3.5 py-3 text-start active:bg-teal-500/12"
    >
      <span className="grid size-10 shrink-0 place-items-center rounded-xl border border-teal-400/25 bg-teal-500/15 text-teal-100">
        <Store className="size-5" aria-hidden />
      </span>
      <span className="min-w-0 flex-1">
        <span className="block text-[13px] font-semibold text-teal-50">میز فروش</span>
        <span className="mt-0.5 block text-[11px] leading-relaxed text-teal-100/70">
          {faNum(total)} مشتری
          {hint ? ` · ${hint}` : " · لینک، تمدید و انتقال"}
        </span>
      </span>
      <span className="shrink-0 rounded-lg border border-teal-400/20 bg-teal-500/10 px-2 py-1 text-[11px] font-medium text-teal-100">
        باز کردن
      </span>
    </button>
  );
}

export function ResellerDeskSheet({
  open,
  onClose,
  data,
  onRefresh,
  onOpenDetail,
  onBuyForCustomer,
}: {
  open: boolean;
  onClose: () => void;
  data: ResellerDeskResponse | null;
  onRefresh: () => void | Promise<void>;
  onOpenDetail: (subId: number, tab?: "renew" | "more") => void;
  onBuyForCustomer: () => void;
}) {
  const [query, setQuery] = useState("");
  const [filter, setFilter] = useState<FilterId>("all");
  const [copiedId, setCopiedId] = useState<number | null>(null);
  const [busyId, setBusyId] = useState<number | null>(null);
  const items = data?.items || [];
  const summary = data?.summary;

  useEffect(() => {
    if (!open) return;
    void onRefresh();
  }, [open, onRefresh]);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return items.filter((item) => {
      if (filter === "unsent" && (item.link_shared || item.expired)) return false;
      if (filter === "expiring" && (item.expired || item.days_left == null || item.days_left > 7)) return false;
      if (filter === "expired" && !item.expired) return false;
      if (!q) return true;
      const blob = [
        item.customer_name,
        item.customer_phone,
        item.customer_telegram_id,
        item.plan_title,
        item.label,
      ]
        .filter(Boolean)
        .join(" ")
        .toLowerCase();
      return blob.includes(q);
    });
  }, [items, query, filter]);

  const markShared = async (item: ResellerDeskItem, shared: boolean) => {
    setBusyId(item.id);
    try {
      await api.markLinkShared(item.id, shared);
      haptic();
      await onRefresh();
    } catch {
      /* ignore — list stays as-is */
    } finally {
      setBusyId(null);
    }
  };

  const copyLink = async (item: ResellerDeskItem) => {
    if (!item.subscription_url) return;
    const ok = await copyText(item.subscription_url);
    if (!ok) return;
    setCopiedId(item.id);
    window.setTimeout(() => setCopiedId((id) => (id === item.id ? null : id)), 1400);
    if (!item.link_shared) void markShared(item, true);
  };

  const sendLink = async (item: ResellerDeskItem) => {
    if (!item.subscription_url) return;
    shareConfigLink(item.subscription_url, item.customer_name || "کانفیگ");
    haptic("medium");
    if (!item.link_shared) void markShared(item, true);
  };

  const filters: { id: FilterId; label: string; count?: number }[] = [
    { id: "all", label: "همه", count: summary?.total },
    { id: "unsent", label: "لینک نرفته", count: summary?.unsent },
    { id: "expiring", label: "رو به اتمام", count: summary?.expiring_soon },
    { id: "expired", label: "منقضی", count: summary?.expired },
  ];

  return (
    <TgSheet open={open} onClose={onClose} title="میز فروش" layer={120}>
      <div className="space-y-3">
        <p className="text-[12px] leading-relaxed text-neutral-400">
          مشتری‌هایی که برایشان کانفیگ خریدی. لینک را بفرست، تمدید کن، یا مالکیت را منتقل کن — قیمت همان فروشگاه است.
        </p>

        {items.length > 0 ? (
          <>
            <div className="relative">
              <Search className="pointer-events-none absolute end-3 top-1/2 size-4 -translate-y-1/2 text-neutral-500" />
              <Input
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder="جستجوی نام، موبایل یا تلگرام"
                className="h-10 rounded-xl border-white/12 bg-black/40 pe-10 text-sm"
              />
            </div>
            <div className="flex gap-1 overflow-x-auto pb-0.5">
              {filters.map((f) => (
                <button
                  key={f.id}
                  type="button"
                  onClick={() => {
                    haptic();
                    setFilter(f.id);
                  }}
                  className={cn(
                    "h-8 shrink-0 rounded-full border px-3 text-[11px] font-medium",
                    filter === f.id
                      ? "border-white bg-white text-black"
                      : "border-white/12 bg-black/30 text-neutral-400",
                  )}
                >
                  {f.label}
                  {f.count ? ` · ${faNum(f.count)}` : ""}
                </button>
              ))}
            </div>
          </>
        ) : null}

        {items.length === 0 ? (
          <div className="space-y-3 rounded-2xl border border-white/10 bg-black/30 px-4 py-6 text-center">
            <Users className="mx-auto size-8 text-neutral-500" aria-hidden />
            <div className="text-sm font-semibold text-neutral-100">هنوز مشتری‌ای نداری</div>
            <p className="text-[12px] leading-relaxed text-neutral-500">
              در فروشگاه «برای کس دیگری» را بزن، اسم مشتری را بنویس و خودت پرداخت کن. بعد از تایید اینجا دیده می‌شود.
            </p>
            <TgButton
              onClick={() => {
                haptic();
                onBuyForCustomer();
              }}
            >
              خرید برای مشتری
            </TgButton>
          </div>
        ) : filtered.length === 0 ? (
          <p className="py-6 text-center text-xs text-neutral-500">با این فیلتر کسی پیدا نشد.</p>
        ) : (
          <div className="space-y-2">
            {filtered.map((item) => {
              const name = item.customer_name?.trim() || item.label?.trim() || "مشتری";
              const contact = contactLine(item);
              const copied = copiedId === item.id;
              const busy = busyId === item.id;
              return (
                <article
                  key={item.id}
                  className="space-y-2.5 rounded-2xl border border-white/10 bg-black/35 px-3.5 py-3"
                >
                  <div className="flex items-start justify-between gap-2">
                    <div className="min-w-0">
                      <div className="truncate text-[14px] font-semibold text-white">{name}</div>
                      <div className="mt-0.5 text-[11px] leading-relaxed text-neutral-400">
                        {item.plan_title}
                        {item.traffic_label ? ` · ${item.traffic_label}` : ""}
                        {item.family_role === "parent"
                          ? " · والد"
                          : item.family_role === "child"
                            ? " · فرزند"
                            : ""}
                      </div>
                      {contact ? (
                        <div className="mt-0.5 truncate font-mono text-[11px] text-neutral-500" dir="ltr">
                          {contact}
                        </div>
                      ) : null}
                    </div>
                    <div className="flex shrink-0 flex-col items-end gap-1">
                      <span
                        className={cn(
                          "rounded-md border px-1.5 py-0.5 text-[10px] font-medium",
                          item.expired
                            ? "border-red-500/30 bg-red-500/10 text-red-200"
                            : item.days_left != null && item.days_left <= 7
                              ? "border-amber-400/30 bg-amber-500/10 text-amber-100"
                              : "border-white/12 bg-white/5 text-neutral-300",
                        )}
                      >
                        {daysLeftLabel(item)}
                      </span>
                      <button
                        type="button"
                        disabled={busy}
                        onClick={() => void markShared(item, !item.link_shared)}
                        className={cn(
                          "rounded-md border px-1.5 py-0.5 text-[10px]",
                          item.link_shared
                            ? "border-emerald-500/25 bg-emerald-500/10 text-emerald-200"
                            : "border-white/12 bg-black/40 text-neutral-400",
                        )}
                      >
                        {item.link_shared ? "لینک ارسال شد" : "لینک نرفته"}
                      </button>
                    </div>
                  </div>

                  <div className="grid grid-cols-2 gap-1.5">
                    <TgButton
                      disabled={!item.subscription_url}
                      className="h-9 text-xs"
                      onClick={() => void copyLink(item)}
                    >
                      {copied ? (
                        <span className="inline-flex items-center gap-1">
                          <Check className="size-3.5" />
                          کپی شد
                        </span>
                      ) : (
                        <span className="inline-flex items-center gap-1">
                          <Copy className="size-3.5" />
                          کپی لینک
                        </span>
                      )}
                    </TgButton>
                    <TgButton
                      variant="outline"
                      disabled={!item.subscription_url}
                      className="h-9 text-xs"
                      onClick={() => void sendLink(item)}
                    >
                      <Send className="size-3.5" />
                      ارسال
                    </TgButton>
                    <TgButton
                      variant="outline"
                      className="h-9 text-xs"
                      onClick={() => {
                        haptic();
                        onOpenDetail(item.id, "renew");
                      }}
                    >
                      <RefreshCw className="size-3.5" />
                      تمدید
                    </TgButton>
                    <TgButton
                      variant="outline"
                      className="h-9 text-xs"
                      onClick={() => {
                        haptic();
                        onOpenDetail(item.id, "more");
                      }}
                    >
                      <ArrowRightLeft className="size-3.5" />
                      انتقال
                    </TgButton>
                  </div>
                </article>
              );
            })}
          </div>
        )}
      </div>
    </TgSheet>
  );
}
