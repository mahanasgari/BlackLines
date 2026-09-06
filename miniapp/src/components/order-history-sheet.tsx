import { useCallback, useEffect, useState } from "react";
import { ChevronLeft, FileText, RefreshCw, Search } from "lucide-react";
import { api, type OrderHistoryItem } from "@/api";
import { OrderReceiptViewer } from "@/components/order-receipt-viewer";
import { OrbLoaderPanel } from "@/components/orb-loader";
import { TgButton } from "@/components/tg-button";
import { TgSheet } from "@/components/tg-sheet";
import { Input } from "@/components/ui/input";
import { cn, faNum } from "@/lib/utils";

function statusTone(status: string) {
  if (status === "approved") return "text-emerald-400";
  if (status === "pending") return "text-amber-400";
  if (status === "rejected" || status === "cancelled") return "text-red-400";
  return "text-neutral-400";
}

function formatDate(iso: string | null | undefined) {
  if (!iso) return "—";
  try {
    return new Intl.DateTimeFormat("fa-IR", { dateStyle: "medium", timeStyle: "short" }).format(new Date(iso));
  } catch {
    return "—";
  }
}

const STATUS_FILTERS = [
  { id: "", label: "همه" },
  { id: "pending", label: "در انتظار" },
  { id: "approved", label: "تایید شده" },
  { id: "rejected", label: "رد شده" },
  { id: "cancelled", label: "لغو شده" },
] as const;

function OrderRow({
  item,
  isAdmin,
  onSelect,
}: {
  item: OrderHistoryItem;
  isAdmin: boolean;
  onSelect: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onSelect}
      className="flex w-full items-start gap-2 rounded-xl border border-white/10 bg-black/30 px-3 py-2.5 text-start active:bg-white/5"
    >
      <span className="inline-flex size-8 shrink-0 items-center justify-center rounded-lg bg-white/10">
        <FileText className="size-3.5" />
      </span>
      <div className="min-w-0 flex-1">
        <div className="flex items-start justify-between gap-2">
          <div className="min-w-0">
            <div className="truncate text-sm font-semibold">
              {item.kind_label} · {item.plan_title}
            </div>
            {isAdmin && (
              <div className="mt-0.5 truncate text-[10px] text-neutral-500">
                {item.user || "—"}
                {item.telegram_id ? ` · ${item.telegram_id}` : ""}
              </div>
            )}
          </div>
          <span className={cn("shrink-0 text-[11px] font-medium", statusTone(item.status))}>
            {item.status_label}
          </span>
        </div>
        <div className="mt-1 flex flex-wrap gap-x-2 text-[10px] text-neutral-500">
          <span>#{faNum(item.id)}</span>
          <span>{item.amount_label}</span>
          {item.has_receipt && <span>· رسید ✓</span>}
          {item.created_at && <span>· {formatDate(item.created_at)}</span>}
        </div>
      </div>
    </button>
  );
}

function OrderDetail({
  item,
  isAdmin,
  onBack,
  onRefresh,
}: {
  item: OrderHistoryItem;
  isAdmin: boolean;
  onBack: () => void;
  onRefresh: () => void;
}) {
  return (
    <div className="space-y-4">
      <button
        type="button"
        onClick={onBack}
        className="inline-flex items-center gap-1 text-[11px] text-neutral-400 active:text-neutral-200"
      >
        <ChevronLeft className="size-3.5" />
        بازگشت به لیست
      </button>

      <div className="rounded-xl border border-white/10 bg-black/30 px-3">
        {[
          ["شماره", `#${faNum(item.id)}`],
          ...(isAdmin
            ? [
                ["کاربر", item.user || "—"],
                ["آیدی تلگرام", item.telegram_id ? String(item.telegram_id) : "—"],
              ]
            : []),
          ["نوع", item.kind_label],
          ["شرح", item.plan_title],
          ["مبلغ", item.amount_label],
          ["وضعیت", item.status_label],
          ["تاریخ ثبت", formatDate(item.created_at)],
          ["تاریخ بررسی", formatDate(item.reviewed_at)],
        ].map(([label, value]) => (
          <div key={label} className="flex items-start justify-between gap-3 border-b border-white/8 py-2.5 last:border-0">
            <span className="shrink-0 text-[11px] text-neutral-500">{label}</span>
            <span
              className={cn(
                "min-w-0 text-end text-[12px]",
                label === "وضعیت" ? statusTone(item.status) : "text-neutral-100",
                (label === "آیدی تلگرام") && "font-mono text-[11px]",
              )}
              dir={label === "آیدی تلگرام" ? "ltr" : undefined}
            >
              {value}
            </span>
          </div>
        ))}
      </div>

      {item.wallet_used_label && item.wallet_used > 0 && (
        <div className="rounded-xl border border-white/10 bg-black/25 px-3 py-2 text-[11px] text-neutral-400">
          از کیف‌پول: {item.wallet_used_label}
        </div>
      )}

      {item.has_receipt && (
        <div className="space-y-2">
          <div className="text-[11px] font-medium text-neutral-300">رسید پرداخت</div>
          <OrderReceiptViewer orderId={item.id} enabled />
        </div>
      )}

      <TgButton variant="outline" className="h-10" onClick={onRefresh}>
        <span className="inline-flex items-center gap-1.5">
          <RefreshCw className="size-3.5" />
          بروزرسانی
        </span>
      </TgButton>
    </div>
  );
}

export function OrderHistorySheet({
  open,
  onClose,
  isAdmin = false,
}: {
  open: boolean;
  onClose: () => void;
  isAdmin?: boolean;
}) {
  const [items, setItems] = useState<OrderHistoryItem[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(false);
  const [statusFilter, setStatusFilter] = useState("");
  const [query, setQuery] = useState("");
  const [searchDraft, setSearchDraft] = useState("");
  const [selected, setSelected] = useState<OrderHistoryItem | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = isAdmin
        ? await api.adminOrderHistory({ q: query, status: statusFilter || undefined, limit: 50 })
        : await api.orderHistory({ status: statusFilter || undefined, limit: 50 });
      setItems(res.items);
      setTotal(res.total);
      setSelected((prev) => (prev ? res.items.find((o) => o.id === prev.id) ?? prev : null));
    } finally {
      setLoading(false);
    }
  }, [isAdmin, query, statusFilter]);

  useEffect(() => {
    if (!open) return;
    setSelected(null);
    void load();
  }, [open, load]);

  return (
    <TgSheet
      open={open}
      onClose={() => {
        setSelected(null);
        onClose();
      }}
      title={isAdmin ? "تاریخچه سفارشات" : "تاریخچه خرید"}
      description={isAdmin ? `${faNum(total)} سفارش` : "پرداخت‌ها و سفارش‌های شما"}
    >
      {selected ? (
        <OrderDetail item={selected} isAdmin={isAdmin} onBack={() => setSelected(null)} onRefresh={() => void load()} />
      ) : (
        <div className="space-y-3">
          {isAdmin && (
            <div className="flex gap-2">
              <Input
                value={searchDraft}
                onChange={(e) => setSearchDraft(e.target.value)}
                placeholder="شماره، آیدی یا @username"
                dir="ltr"
                className="h-10 flex-1 rounded-xl border-white/15 bg-black/40 font-mono text-sm"
              />
              <TgButton
                variant="outline"
                disabled={loading}
                className="h-10 w-auto shrink-0 px-3"
                onClick={() => setQuery(searchDraft.trim())}
              >
                <Search className="size-4" />
              </TgButton>
            </div>
          )}

          <div className="flex flex-wrap gap-1.5">
            {STATUS_FILTERS.map((f) => (
              <button
                key={f.id || "all"}
                type="button"
                onClick={() => setStatusFilter(f.id)}
                className={cn(
                  "rounded-lg px-2.5 py-1 text-[11px] transition-colors",
                  statusFilter === f.id
                    ? "bg-primary text-primary-foreground"
                    : "border border-white/12 bg-white/5 text-neutral-400",
                )}
              >
                {f.label}
              </button>
            ))}
          </div>

          {loading && items.length === 0 ? (
            <OrbLoaderPanel variant="admin" message="در حال بارگذاری…" />
          ) : items.length === 0 ? (
            <div className="rounded-xl border border-dashed border-white/15 px-4 py-8 text-center text-sm text-neutral-500">
              سفارشی پیدا نشد
            </div>
          ) : (
            <div className="space-y-2">
              {items.map((item) => (
                <OrderRow key={item.id} item={item} isAdmin={isAdmin} onSelect={() => setSelected(item)} />
              ))}
              {total > items.length && (
                <p className="pt-1 text-center text-[10px] text-neutral-500">
                  نمایش {faNum(items.length)} از {faNum(total)}
                </p>
              )}
            </div>
          )}

          <TgButton variant="outline" disabled={loading} className="h-10" onClick={() => void load()}>
            <span className="inline-flex items-center gap-1.5">
              {loading ? "در حال بارگذاری…" : (
                <>
                  <RefreshCw className="size-3.5" />
                  بروزرسانی
                </>
              )}
            </span>
          </TgButton>
        </div>
      )}
    </TgSheet>
  );
}
