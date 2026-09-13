import { useEffect, useState } from "react";
import { Search, ScrollText } from "lucide-react";
import { api, type ActivityLogItem } from "@/api";
import { OrbLoaderPanel } from "@/components/orb-loader";
import { TgButton } from "@/components/tg-button";
import { cn, faNum } from "@/lib/utils";

const ACTOR_FILTERS: { id: string; label: string }[] = [
  { id: "", label: "همه" },
  { id: "user", label: "کاربر" },
  { id: "admin", label: "ادمین" },
  { id: "system", label: "سیستم" },
];

const CAT_FILTERS: { id: string; label: string }[] = [
  { id: "", label: "همه" },
  { id: "shop", label: "فروشگاه" },
  { id: "config", label: "کانفیگ" },
  { id: "wallet", label: "کیف‌پول" },
  { id: "family", label: "خانواده" },
  { id: "chat", label: "گفتگو" },
  { id: "profile", label: "پروفایل" },
  { id: "admin", label: "تنظیمات" },
];

export function formatActivityWhen(iso: string | null | undefined) {
  if (!iso) return "—";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "—";
  const diff = (Date.now() - d.getTime()) / 1000;
  if (diff < 45) return "همین الان";
  if (diff < 3600) return `${faNum(Math.max(1, Math.floor(diff / 60)))} دقیقه پیش`;
  if (diff < 86400) return `${faNum(Math.floor(diff / 3600))} ساعت پیش`;
  if (diff < 86400 * 7) return `${faNum(Math.floor(diff / 86400))} روز پیش`;
  try {
    return new Intl.DateTimeFormat("fa-IR", { dateStyle: "medium", timeStyle: "short" }).format(d);
  } catch {
    return iso;
  }
}

function roleMeta(role: string) {
  if (role === "admin") return { label: "ادمین", className: "border-amber-400/30 bg-amber-500/15 text-amber-100" };
  if (role === "system") return { label: "سیستم", className: "border-white/10 bg-white/5 text-neutral-300" };
  return { label: "کاربر", className: "border-sky-400/25 bg-sky-500/10 text-sky-100" };
}

export function ActivityLogRows({ items, showActor = true }: { items: ActivityLogItem[]; showActor?: boolean }) {
  if (items.length === 0) return null;
  return (
    <div className="space-y-2">
      {items.map((item) => {
        const role = roleMeta(item.actor_role);
        return (
          <div key={item.id} className="rounded-xl border border-white/10 bg-black/35 px-3 py-2.5">
            <div className="flex items-start justify-between gap-2">
              <div className="min-w-0">
                <div className="flex flex-wrap items-center gap-1">
                  <span className={cn("rounded-md border px-1.5 py-px text-[10px] font-medium", role.className)}>
                    {role.label}
                  </span>
                  {item.category_label ? (
                    <span className="rounded-md border border-white/10 bg-white/5 px-1.5 py-px text-[10px] text-neutral-400">
                      {item.category_label}
                    </span>
                  ) : null}
                </div>
                <p className="mt-1 text-[13px] font-semibold text-neutral-50">{item.action_label}</p>
                {showActor ? (
                  <p className="mt-0.5 truncate text-[11px] text-neutral-400">{item.actor_name}</p>
                ) : null}
                {item.target_name ? (
                  <p className="truncate text-[11px] text-neutral-500">روی {item.target_name}</p>
                ) : null}
                {item.detail ? (
                  <p className="mt-1 break-all text-[10px] leading-relaxed text-neutral-500" dir="ltr">
                    {item.detail}
                  </p>
                ) : null}
              </div>
              <span className="shrink-0 text-[10px] text-neutral-500">{formatActivityWhen(item.created_at)}</span>
            </div>
          </div>
        );
      })}
    </div>
  );
}

export function AdminActivityLogPanel() {
  const [items, setItems] = useState<ActivityLogItem[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [q, setQ] = useState("");
  const [debounced, setDebounced] = useState("");
  const [actorKind, setActorKind] = useState("");
  const [category, setCategory] = useState("");
  const [includeTest, setIncludeTest] = useState(false);

  useEffect(() => {
    const t = window.setTimeout(() => setDebounced(q.trim()), 280);
    return () => window.clearTimeout(t);
  }, [q]);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    void api
      .adminAuditLog({ limit: 50, offset: 0, q: debounced, actorKind, category, includeTest })
      .then((res) => {
        if (cancelled) return;
        setItems(res.items);
        setTotal(res.total);
      })
      .catch((e) => {
        if (!cancelled) setError(e instanceof Error ? e.message : "بارگذاری ناموفق");
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [debounced, actorKind, category, includeTest]);

  const loadMore = () => {
    setLoadingMore(true);
    void api
      .adminAuditLog({ limit: 50, offset: items.length, q: debounced, actorKind, category, includeTest })
      .then((res) => {
        setItems((prev) => [...prev, ...res.items]);
        setTotal(res.total);
      })
      .catch((e) => setError(e instanceof Error ? e.message : "بارگذاری ناموفق"))
      .finally(() => setLoadingMore(false));
  };

  return (
    <div className="space-y-3">
      <div className="flex items-start gap-2">
        <span className="grid size-9 shrink-0 place-items-center rounded-xl border border-white/12 bg-white/5 text-neutral-200">
          <ScrollText className="size-4" />
        </span>
        <div className="min-w-0">
          <h3 className="text-sm font-semibold">گزارش فعالیت‌ها</h3>
          <p className="text-[11px] text-neutral-400">
            هر کار کاربر، ادمین یا ربات اینجا ثبت می‌شود
            {total > 0 ? ` · ${faNum(total)} مورد` : ""}
          </p>
        </div>
      </div>

      <div className="relative">
        <Search className="pointer-events-none absolute start-3 top-1/2 size-4 -translate-y-1/2 text-neutral-500" />
        <input
          type="search"
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder="جستجو: عمل، جزئیات، مسیر…"
          className="w-full rounded-xl border border-white/12 bg-black/40 py-2.5 pe-3 ps-10 text-sm text-white outline-none placeholder:text-neutral-500 focus:border-white/25"
        />
      </div>

      <label className="flex items-center gap-2 text-[11px] text-neutral-400">
        <input
          type="checkbox"
          checked={includeTest}
          onChange={(e) => setIncludeTest(e.target.checked)}
          className="size-3.5 rounded border-white/20 bg-black/40"
        />
        نمایش فعالیت کاربران تست
      </label>

      <div className="flex gap-1">
        {ACTOR_FILTERS.map((f) => (
          <button
            key={f.id || "all"}
            type="button"
            onClick={() => setActorKind(f.id)}
            className={cn(
              "h-8 flex-1 rounded-lg border text-[11px] font-semibold",
              actorKind === f.id
                ? "border-white/20 bg-white/12 text-white"
                : "border-white/10 bg-black/30 text-neutral-400",
            )}
          >
            {f.label}
          </button>
        ))}
      </div>

      <div className="flex gap-1 overflow-x-auto pb-0.5">
        {CAT_FILTERS.map((f) => (
          <button
            key={f.id || "all-cat"}
            type="button"
            onClick={() => setCategory(f.id)}
            className={cn(
              "h-7 shrink-0 rounded-lg border px-2.5 text-[10px] font-semibold",
              category === f.id
                ? "border-white/20 bg-white/12 text-white"
                : "border-white/10 bg-black/30 text-neutral-400",
            )}
          >
            {f.label}
          </button>
        ))}
      </div>

      {loading ? <OrbLoaderPanel variant="admin" message="در حال بارگذاری لاگ…" /> : null}
      {error ? (
        <div className="rounded-xl border border-red-500/25 bg-red-500/10 px-3 py-2 text-center text-xs text-red-200">
          {error}
        </div>
      ) : null}
      {!loading && items.length === 0 && !error ? (
        <div className="rounded-xl border border-white/10 bg-black/30 px-3 py-8 text-center text-sm text-neutral-400">
          هنوز فعالیتی ثبت نشده.
        </div>
      ) : null}
      {!loading ? <ActivityLogRows items={items} /> : null}
      {!loading && items.length < total ? (
        <TgButton variant="outline" disabled={loadingMore} onClick={loadMore}>
          {loadingMore ? "…" : `موارد بیشتر · ${faNum(total - items.length)} باقی`}
        </TgButton>
      ) : null}
    </div>
  );
}
