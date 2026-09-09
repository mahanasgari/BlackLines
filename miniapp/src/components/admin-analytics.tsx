import { useEffect, useState, type ReactNode } from "react";
import { Activity, BarChart3, Clock, Users, Wallet } from "lucide-react";
import {
  api,
  type AdminAnalytics,
  type AdminUser,
  type AnalyticsDelta,
  type AnalyticsPoint,
  type ExpiringItem,
  type TrialGrantResult,
} from "@/api";
import { AdminUserSheet } from "@/components/admin-user-sheet";
import { TgSheet } from "@/components/tg-sheet";
import { cn, faNum } from "@/lib/utils";

const PERIODS: { id: number; label: string }[] = [
  { id: 1, label: "امروز" },
  { id: 7, label: "۷ روز" },
  { id: 30, label: "۳۰ روز" },
  { id: 0, label: "کل" },
];

const FUNNEL_SLICE: Record<string, string> = {
  registered: "all",
  config: "active",
  paying: "paying",
  pro: "pro",
};

type DashPage = "users" | "finance";

export function AdminAnalyticsPanel({
  onOpenChat,
  onSetRole,
  onGrantTrial,
  onOpenSubscription,
  onNotify,
}: {
  onOpenChat: (userId: number) => void;
  onSetRole: (userId: number, role: "user" | "admin") => Promise<unknown>;
  onGrantTrial?: (opts: {
    targets_text?: string;
    all_users?: boolean;
    skip_existing_trial?: boolean;
    notify_users?: boolean;
  }) => Promise<TrialGrantResult>;
  onOpenSubscription?: (subId: number) => void;
  onNotify: (message: string, kind?: "success" | "error" | "info") => void;
}) {
  const [days, setDays] = useState(30);
  const [page, setPage] = useState<DashPage>("users");
  const [includeTest, setIncludeTest] = useState(false);
  const [data, setData] = useState<AdminAnalytics | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [slice, setSlice] = useState<{ key: string; title: string } | null>(null);
  const [sliceItems, setSliceItems] = useState<AdminUser[]>([]);
  const [sliceLoading, setSliceLoading] = useState(false);
  const [openUserId, setOpenUserId] = useState<number | null>(null);
  const [expiring, setExpiring] = useState<ExpiringItem[]>([]);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    void api
      .adminAnalytics(days, includeTest)
      .then((res) => {
        if (!cancelled) setData(res);
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
  }, [days, includeTest]);

  useEffect(() => {
    let cancelled = false;
    void api
      .adminExpiring(3, includeTest)
      .then((res) => {
        if (!cancelled) setExpiring(res.items);
      })
      .catch(() => undefined);
    return () => {
      cancelled = true;
    };
  }, [includeTest]);

  const openSlice = (key: string, title?: string) => {
    setSlice({ key, title: title || "کاربران" });
    setSliceLoading(true);
    void api
      .adminUsers("", includeTest, key, days)
      .then((res) => {
        setSliceItems(res.items);
        setSlice((cur) => (cur ? { ...cur, title: res.title || title || "کاربران" } : cur));
      })
      .catch((e) => onNotify(e instanceof Error ? e.message : "بارگذاری ناموفق", "error"))
      .finally(() => setSliceLoading(false));
  };

  return (
    <div className="space-y-3">
      <div className="grid grid-cols-2 gap-1 rounded-xl border border-white/10 bg-black/40 p-1">
        {(
          [
            { id: "users" as const, label: "کاربران", icon: <Users className="size-3.5" /> },
            { id: "finance" as const, label: "مالی", icon: <Wallet className="size-3.5" /> },
          ] as const
        ).map((t) => (
          <button
            key={t.id}
            type="button"
            onClick={() => setPage(t.id)}
            className={cn(
              "inline-flex items-center justify-center gap-1.5 rounded-lg px-2 py-2.5 text-xs font-semibold",
              page === t.id ? "bg-primary text-primary-foreground" : "text-neutral-400 active:bg-white/10",
            )}
          >
            {t.icon}
            {t.label}
          </button>
        ))}
      </div>

      <label className="flex items-center gap-2 text-[11px] text-neutral-400">
        <input
          type="checkbox"
          checked={includeTest}
          onChange={(e) => setIncludeTest(e.target.checked)}
          className="size-3.5 rounded border-white/20 bg-black/40"
        />
        نمایش کاربران تست در آمار
        {!includeTest && (data?.hidden_test_users || 0) > 0 ? (
          <span className="text-neutral-600">· {faNum(data!.hidden_test_users!)} مخفی</span>
        ) : null}
      </label>

      <div className="flex gap-1.5">
        {PERIODS.map((p) => (
          <button
            key={p.id}
            type="button"
            onClick={() => setDays(p.id)}
            className={cn(
              "h-8 flex-1 rounded-lg border text-[11px] font-semibold",
              days === p.id
                ? "border-white/20 bg-white/12 text-white"
                : "border-white/10 bg-black/30 text-neutral-400",
            )}
          >
            {p.label}
          </button>
        ))}
      </div>

      {data?.compare ? <CompareRow compare={data.compare} onSlice={openSlice} /> : null}

      {loading && <p className="py-8 text-center text-xs text-neutral-500">در حال جمع‌آوری آمار…</p>}
      {error && !loading && <p className="py-6 text-center text-xs text-orange-300">{error}</p>}
      {!loading && data && page === "users" && (
        <UsersPage
          data={data}
          expiring={expiring}
          onSlice={openSlice}
          onOpenUser={setOpenUserId}
          onRemind={(subId) =>
            api
              .adminRemindExpiry(subId)
              .then(() => {
                onNotify("یادآوری ارسال شد", "success");
                setExpiring((rows) =>
                  rows.map((r) =>
                    r.subscription_id === subId ? { ...r, reminded_3d: true } : r,
                  ),
                );
              })
              .catch((e) => onNotify(e instanceof Error ? e.message : "ارسال ناموفق", "error"))
          }
        />
      )}
      {!loading && data && page === "finance" && <FinancePage data={data} onSlice={openSlice} />}

      <TgSheet
        open={slice != null}
        onClose={() => setSlice(null)}
        title={slice?.title || "کاربران"}
        description="برای دیدن پرونده لمس کنید"
      >
        {sliceLoading ? (
          <p className="py-8 text-center text-sm text-neutral-400">در حال بارگذاری…</p>
        ) : sliceItems.length === 0 ? (
          <p className="py-8 text-center text-sm text-neutral-500">کسی در این فیلتر نیست</p>
        ) : (
          <div className="space-y-2">
            {sliceItems.map((u) => {
              const title = u.full_name || (u.username ? `@${u.username}` : faNum(u.telegram_id));
              return (
                <button
                  key={u.id}
                  type="button"
                  onClick={() => setOpenUserId(u.id)}
                  className="w-full rounded-xl border border-white/10 bg-black/30 px-3 py-2.5 text-start active:bg-white/8"
                >
                  <div className="truncate text-sm font-semibold">{title}</div>
                  <div className="mt-0.5 font-mono text-[10px] text-neutral-500" dir="ltr">
                    {u.username ? `@${u.username} · ` : ""}
                    {u.telegram_id}
                  </div>
                </button>
              );
            })}
          </div>
        )}
      </TgSheet>

      <AdminUserSheet
        open={openUserId != null}
        onClose={() => setOpenUserId(null)}
        userId={openUserId}
        onOpenChat={(id) => {
          setOpenUserId(null);
          setSlice(null);
          onOpenChat(id);
        }}
        onOpenSubscription={onOpenSubscription}
        onSetRole={onSetRole}
        onGrantTrial={onGrantTrial}
        onNotify={onNotify}
      />
    </div>
  );
}

function CompareRow({
  compare,
  onSlice,
}: {
  compare: NonNullable<AdminAnalytics["compare"]>;
  onSlice: (key: string, title?: string) => void;
}) {
  return (
    <div className="space-y-1.5">
      <p className="px-0.5 text-[10px] text-neutral-500">{compare.label}</p>
      <div className="grid grid-cols-3 gap-1.5">
        <DeltaCard
          label="کاربران جدید"
          row={compare.new_users}
          onClick={() => onSlice("new", "کاربران جدید")}
        />
        <DeltaCard
          label="واریز کارت"
          row={compare.cash_in}
          money
          onClick={() => onSlice("paying_period", "خرید در این بازه")}
        />
        <DeltaCard
          label="تبدیل تست"
          row={compare.trial_converted}
          onClick={() => onSlice("trial_converted", "تبدیل تست به خرید")}
        />
      </div>
    </div>
  );
}

function DeltaCard({
  label,
  row,
  money,
  onClick,
}: {
  label: string;
  row: AnalyticsDelta;
  money?: boolean;
  onClick: () => void;
}) {
  const up = row.delta > 0;
  const down = row.delta < 0;
  return (
    <button
      type="button"
      onClick={onClick}
      className="rounded-xl border border-white/10 bg-black/30 px-2 py-2 text-start active:bg-white/8"
    >
      <div className="text-[10px] text-neutral-500">{label}</div>
      <div className="mt-0.5 text-xs font-bold tabular-nums">
        {money ? row.current_label || faNum(row.current) : faNum(row.current)}
      </div>
      <div
        className={cn(
          "mt-0.5 text-[10px] tabular-nums",
          up && "text-emerald-300",
          down && "text-orange-300",
          !up && !down && "text-neutral-500",
        )}
      >
        {up ? "+" : ""}
        {money ? row.delta_label || faNum(row.delta) : faNum(row.delta)}
        {row.delta !== 0 ? ` · ${faNum(Math.abs(row.delta_pct))}٪` : ""}
      </div>
    </button>
  );
}

function UsersPage({
  data,
  expiring,
  onSlice,
  onOpenUser,
  onRemind,
}: {
  data: AdminAnalytics;
  expiring: ExpiringItem[];
  onSlice: (key: string, title?: string) => void;
  onOpenUser: (id: number) => void;
  onRemind: (subId: number) => void;
}) {
  const k = data.users.kpis;
  const c = data.users.configs;
  const a = data.users.activity;
  const maxFunnel = Math.max(1, ...data.users.funnel.map((f) => f.count));

  return (
    <div className="space-y-4">
      <ExpiringBoard items={expiring} onOpenUser={onOpenUser} onRemind={onRemind} />

      <SectionTitle icon={<Users className="size-3.5" />} title="پایگاه کاربران" hint={`${data.period_label} · لمس کنید`} />
      <div className="grid grid-cols-2 gap-2">
        <Kpi label="کل کاربران" value={faNum(k.total_users)} hint={`${faNum(k.new_users)} جدید`} onClick={() => onSlice("all", "همه کاربران")} />
        <Kpi
          label="مشتری خرید کرده"
          value={faNum(k.paying_users)}
          hint={`${faNum(k.active_customers)} کانفیگ فعال`}
          onClick={() => onSlice("paying", "خرید کرده‌اند")}
        />
        <Kpi
          label="دعوت‌شده"
          value={faNum(k.referred_users)}
          hint={`${faNum(k.pro_users)} کاربر Pro`}
          onClick={() => onSlice("referred", "دعوت‌شده")}
        />
        <Kpi
          label="تست گرفته"
          value={faNum(k.trial_granted)}
          hint={`${faNum(k.trial_converted)} تبدیل به خرید`}
          onClick={() => onSlice("trial", "تست گرفته")}
        />
        <Kpi
          label="در حال انقضا"
          value={faNum(k.expiring || 0)}
          hint="۳ روز آینده"
          onClick={() => onSlice("expiring", "در حال انقضا")}
        />
        <Kpi
          label="کیف‌پول"
          value={faNum(k.with_wallet)}
          hint={`${faNum(k.admins)} ادمین`}
          onClick={() => onSlice("wallet", "کیف‌پول دارند")}
        />
      </div>

      <SectionTitle icon={<BarChart3 className="size-3.5" />} title="مسیر تبدیل" />
      <Card>
        <div className="space-y-2.5">
          {data.users.funnel.map((f) => (
            <MixRow
              key={f.key}
              title={f.title}
              value={faNum(f.count)}
              share={Math.round((f.count / maxFunnel) * 100)}
              onClick={() => onSlice(FUNNEL_SLICE[f.key] || f.key, f.title)}
            />
          ))}
        </div>
      </Card>

      <SectionTitle icon={<BarChart3 className="size-3.5" />} title="ثبت‌نام روزانه" />
      <Card>
        <MiniBars points={data.users.signups} />
      </Card>

      <SectionTitle icon={<Activity className="size-3.5" />} title="کانفیگ‌ها" hint={`${faNum(c.active_share)}٪ فعال`} />
      <div className="grid grid-cols-2 gap-2">
        <Kpi label="کل کانفیگ" value={faNum(c.total)} hint={`${faNum(c.new)} در این بازه`} onClick={() => onSlice("has_config", "دارای کانفیگ")} />
        <Kpi
          label="فعال"
          value={faNum(c.active)}
          hint={`${faNum(c.expired)} منقضی · ${faNum(c.disabled)} قطع`}
          onClick={() => onSlice("active", "کانفیگ فعال")}
        />
        <Kpi label="عادی / سفارشی" value={faNum(c.regular)} onClick={() => onSlice("has_config", "دارای کانفیگ")} />
        <Kpi
          label="ابری + حجم"
          value={faNum(c.metered + c.prepaid)}
          hint={`${faNum(c.trial)} تست`}
          onClick={() => onSlice("payg", "ابری / حجم")}
        />
      </div>
      <Card>
        <div className="space-y-2.5">
          <MixRow title="فعال" value={faNum(c.active)} share={pct(c.active, c.total)} onClick={() => onSlice("active", "فعال")} />
          <MixRow title="منقضی" value={faNum(c.expired)} share={pct(c.expired, c.total)} onClick={() => onSlice("expired", "منقضی")} />
          <MixRow title="غیرفعال" value={faNum(c.disabled)} share={pct(c.disabled, c.total)} onClick={() => onSlice("disabled", "قطع")} />
          <MixRow title="حساب تست" value={faNum(c.trial)} share={pct(c.trial, c.total)} onClick={() => onSlice("trial_config", "حساب تست")} />
        </div>
      </Card>

      <SectionTitle icon={<Activity className="size-3.5" />} title="فعالیت" />
      <div className="grid grid-cols-2 gap-2">
        <Kpi
          label="آنلاین الان"
          value={faNum(a.online_now)}
          hint={`${faNum(a.used_24h)} مصرف ۲۴ساعت`}
          onClick={() => onSlice("online", "آنلاین الان")}
        />
        <Kpi
          label="سفارش بازه"
          value={faNum(a.orders_new)}
          hint={`${faNum(a.pending_orders)} در انتظار`}
          onClick={() => onSlice("pending", "سفارش باز")}
        />
        <Kpi label="پیام‌ها" value={faNum(a.chat_total)} hint={`${faNum(a.chat_from_users)} از کاربر`} onClick={() => onSlice("unread", "پیام خوانده‌نشده")} />
        <Kpi
          label="خوانده‌نشده"
          value={faNum(a.chat_unread)}
          hint={`${faNum(a.chat_from_admins)} پاسخ ادمین`}
          onClick={() => onSlice("unread", "پیام خوانده‌نشده")}
        />
      </div>
    </div>
  );
}

function ExpiringBoard({
  items,
  onOpenUser,
  onRemind,
}: {
  items: ExpiringItem[];
  onOpenUser: (id: number) => void;
  onRemind: (subId: number) => void;
}) {
  return (
    <div className="space-y-2">
      <SectionTitle icon={<Clock className="size-3.5" />} title="منقضی می‌شود" hint="۳ روز آینده" />
      {items.length === 0 ? (
        <p className="rounded-xl border border-dashed border-white/10 px-3 py-4 text-center text-[11px] text-neutral-500">
          کانفیگی در ۳ روز آینده تمام نمی‌شود
        </p>
      ) : (
        <div className="space-y-2">
          {items.map((row) => {
            const name = row.full_name || (row.username ? `@${row.username}` : faNum(row.telegram_id));
            return (
              <div key={row.subscription_id} className="rounded-xl border border-amber-400/20 bg-amber-500/5 px-3 py-2.5">
                <button type="button" className="w-full text-start" onClick={() => onOpenUser(row.user_id)}>
                  <div className="flex items-start justify-between gap-2">
                    <div className="min-w-0">
                      <div className="truncate text-sm font-semibold">{name}</div>
                      <div className="mt-0.5 truncate text-[11px] text-neutral-400">{row.label}</div>
                    </div>
                    <span className="shrink-0 text-[11px] font-semibold text-amber-200">{row.days_left_label}</span>
                  </div>
                </button>
                <button
                  type="button"
                  className="mt-2 h-8 rounded-lg border border-white/12 px-2.5 text-[11px] text-neutral-200 active:bg-white/10"
                  onClick={() => onRemind(row.subscription_id)}
                >
                  {row.reminded_1d || row.reminded_3d ? "ارسال دوباره یادآوری" : "ارسال یادآوری"}
                </button>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

function FinancePage({
  data,
  onSlice,
}: {
  data: AdminAnalytics;
  onSlice: (key: string, title?: string) => void;
}) {
  const k = data.finance.kpis;
  const notes = data.finance.notes;

  return (
    <div className="space-y-4">
      <SectionTitle icon={<Wallet className="size-3.5" />} title="خلاصه حساب" hint={`${faNum(k.order_count)} سفارش تاییدشده · لمس کنید`} />
      <div className="grid grid-cols-1 gap-2">
        <Kpi label="واریز به کارت" value={k.cash_in.label} accent onClick={() => onSlice("paying_period", "خرید در این بازه")} />
        <Kpi label="فروش محصول" value={k.product_revenue.label} hint="شامل مصرف ابری" onClick={() => onSlice("paying_period", "خرید در این بازه")} />
        <Kpi label="برآورد خالص شما" value={k.estimate_owned.label} hint="کارت − برداشت − مانده کیف‌پول" onClick={() => onSlice("wallet", "کیف‌پول دارند")} />
      </div>
      <div className="grid grid-cols-2 gap-2">
        <Kpi label="نقد پس از برداشت" value={k.net_cash.label} onClick={() => onSlice("paying_period", "خرید در این بازه")} />
        <Kpi label="مانده کیف‌پول کاربران" value={k.wallet_liability.label} onClick={() => onSlice("wallet", "کیف‌پول دارند")} />
        <Kpi label="پورسانت دعوت" value={k.commissions.label} onClick={() => onSlice("referred", "دعوت‌شده")} />
        <Kpi label="برداشت پرداخت‌شده" value={k.withdrawals_paid.label} onClick={() => onSlice("wallet", "کیف‌پول دارند")} />
      </div>

      <SectionTitle icon={<BarChart3 className="size-3.5" />} title="درآمد هر بخش" />
      <Card>
        <div className="space-y-3">
          {data.finance.kinds.map((row) => (
            <button
              key={row.key}
              type="button"
              className="block w-full text-start"
              onClick={() => onSlice(row.key === "wallet_topup" ? "wallet" : "paying_period", row.title)}
            >
              <div className="flex items-baseline justify-between gap-2 text-xs">
                <span className="text-neutral-200">{row.title}</span>
                <span className="tabular-nums text-neutral-300">{row.label}</span>
              </div>
              <div className="mt-1 flex items-center justify-between text-[10px] text-neutral-500">
                <span>{faNum(row.count)} سفارش</span>
                <span>
                  کارت {row.card_label}
                  {row.wallet > 0 ? ` · کیف‌پول ${row.wallet_label}` : ""}
                </span>
              </div>
              <Bar share={row.share} />
            </button>
          ))}
        </div>
      </Card>

      {data.finance.plans.length > 0 && (
        <>
          <SectionTitle icon={<BarChart3 className="size-3.5" />} title="فروش بر اساس پلن" />
          <Card>
            <div className="space-y-2.5">
              {data.finance.plans.map((p) => (
                <MixRow
                  key={p.title}
                  title={p.title}
                  value={p.label}
                  meta={`${faNum(p.count)} عدد`}
                  share={p.share}
                  onClick={() => onSlice("paying_period", p.title)}
                />
              ))}
            </div>
          </Card>
        </>
      )}

      <SectionTitle icon={<BarChart3 className="size-3.5" />} title="فروش روزانه" />
      <Card>
        <MiniBars points={data.finance.daily} money />
      </Card>

      <SectionTitle icon={<Wallet className="size-3.5" />} title="کیف‌پول و تعهدات" />
      <div className="grid grid-cols-2 gap-2">
        <Kpi label="شارژ کیف‌پول" value={k.wallet_topups.label} onClick={() => onSlice("wallet", "کیف‌پول دارند")} />
        <Kpi label="خرج از کیف‌پول" value={k.wallet_spent.label} onClick={() => onSlice("paying_period", "خرید در این بازه")} />
        <Kpi label="مصرف ابری" value={k.metered_billed.label} onClick={() => onSlice("payg", "ابری / حجم")} />
        <Kpi
          label="برداشت در انتظار"
          value={k.withdrawals_pending.label}
          hint={data.finance.pending_order_count ? `${faNum(data.finance.pending_order_count)} سفارش باز` : undefined}
          onClick={() => onSlice("pending", "سفارش باز")}
        />
      </div>
      {k.pending_orders.toman > 0 && (
        <Kpi label="مبلغ سفارش‌های در انتظار" value={k.pending_orders.label} onClick={() => onSlice("pending", "سفارش باز")} />
      )}

      <Card>
        <ul className="space-y-2 text-[11px] leading-relaxed text-neutral-400">
          <li>{notes.cash}</li>
          <li>{notes.product}</li>
          <li>{notes.wallet}</li>
          <li>{notes.metered}</li>
          <li>{notes.owned}</li>
        </ul>
      </Card>
    </div>
  );
}

function SectionTitle({ icon, title, hint }: { icon: ReactNode; title: string; hint?: string }) {
  return (
    <div className="flex items-center justify-between gap-2">
      <div className="flex items-center gap-1.5 text-xs font-semibold text-neutral-300">
        {icon}
        {title}
      </div>
      {hint ? <span className="text-[10px] text-neutral-500">{hint}</span> : null}
    </div>
  );
}

function Card({ children }: { children: ReactNode }) {
  return <div className="rounded-2xl border border-white/10 bg-black/30 px-3 py-3">{children}</div>;
}

function Kpi({
  label,
  value,
  hint,
  accent,
  onClick,
}: {
  label: string;
  value: string;
  hint?: string;
  accent?: boolean;
  onClick?: () => void;
}) {
  const cls = cn(
    "rounded-2xl border border-white/10 bg-black/30 px-3 py-2.5 text-start",
    onClick && "active:bg-white/8",
  );
  const inner = (
    <>
      <div className="text-[10px] text-neutral-500">{label}</div>
      <div className={cn("mt-0.5 font-bold tabular-nums leading-tight", accent ? "text-base text-emerald-200" : "text-sm")}>
        {value}
      </div>
      {hint ? <div className="mt-0.5 text-[10px] text-neutral-500">{hint}</div> : null}
    </>
  );
  if (onClick) {
    return (
      <button type="button" className={cls} onClick={onClick}>
        {inner}
      </button>
    );
  }
  return <div className={cls}>{inner}</div>;
}

function Bar({ share }: { share: number }) {
  return (
    <div className="mt-1.5 h-1.5 overflow-hidden rounded-full bg-white/8">
      <div
        className="h-full rounded-full bg-sky-300/75"
        style={{ width: `${Math.max(share > 0 ? 4 : 0, Math.min(100, share))}%` }}
      />
    </div>
  );
}

function MixRow({
  title,
  value,
  share,
  meta,
  onClick,
}: {
  title: string;
  value: string;
  share: number;
  meta?: string;
  onClick?: () => void;
}) {
  const inner = (
    <>
      <div className="flex items-baseline justify-between gap-2 text-xs">
        <span className="min-w-0 truncate text-neutral-200">{title}</span>
        <span className="shrink-0 tabular-nums text-neutral-300">
          {value}
          {meta ? <span className="ms-1 text-[10px] text-neutral-500">{meta}</span> : null}
        </span>
      </div>
      <Bar share={share} />
    </>
  );
  if (onClick) {
    return (
      <button type="button" className="block w-full text-start" onClick={onClick}>
        {inner}
      </button>
    );
  }
  return <div>{inner}</div>;
}

function MiniBars({ points, money }: { points: AnalyticsPoint[]; money?: boolean }) {
  const max = Math.max(1, ...points.map((p) => (money ? p.toman || 0 : p.count)));
  const has = points.some((p) => (money ? p.toman || 0 : p.count) > 0);
  if (!has) {
    return <p className="py-4 text-center text-[11px] text-neutral-500">در این بازه داده‌ای نیست</p>;
  }
  const slim = points.length > 14;
  return (
    <div className={cn("flex items-end", slim ? "h-20 gap-px" : "h-16 gap-1")}>
      {points.map((p) => {
        const v = money ? p.toman || 0 : p.count;
        return (
          <div key={p.date} className="flex min-w-0 flex-1 flex-col items-center gap-1">
            <div
              className="w-full rounded-sm bg-sky-300/80"
              style={{ height: `${Math.max(v > 0 ? 8 : 2, (v / max) * 100)}%` }}
              title={money ? p.label_money || p.label : `${p.label}: ${p.count}`}
            />
            {!slim && <div className="text-[8px] tabular-nums text-neutral-500">{p.label}</div>}
          </div>
        );
      })}
    </div>
  );
}

function pct(part: number, whole: number) {
  if (!whole) return 0;
  return Math.round((100 * part) / whole);
}
