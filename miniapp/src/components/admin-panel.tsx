import { useEffect, useState, type ReactNode } from "react";
import {
  Bell,
  Cake,
  ChevronDown,
  CreditCard,
  Gauge,
  Gift,
  Globe,
  Inbox,
  BarChart3,
  Search,
  Settings2,
  Sparkles,
  History,
  Megaphone,
  ScrollText,
  TicketPercent,
  Users,
} from "lucide-react";
import { AdminActivityLogPanel } from "@/components/admin-activity-log";
import { AdminAnalyticsPanel } from "@/components/admin-analytics";
import { AdminServersPanel } from "@/components/admin-servers";
import { AdminUserSheet } from "@/components/admin-user-sheet";
import { GrowthAdminPanel } from "@/components/growth-admin";
import type {
  AdminPendingOrder,
  AdminUser,
  CustomBuilderAdminSettings,
  PaygAdminSettings,
  PaymentCard,
  TrialGrantResult,
  TrialSettings,
} from "@/api";
import { AdminPaymentCardsPanel } from "@/components/checkout-panel";
import { OrbLoader, OrbLoaderPanel } from "@/components/orb-loader";
import { TgButton } from "@/components/tg-button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { cn, faNum } from "@/lib/utils";

type AdminWithdrawal = {
  id: number;
  user: string;
  telegram_id: number;
  amount_label: string;
  card_number: string;
};

type AdminSection = "queue" | "stats" | "users" | "logs" | "settings";

function priceText(toman: number) {
  return `${faNum(toman)} تومان`;
}

function Chip({ children }: { children: ReactNode }) {
  return (
    <span className="inline-flex h-5 items-center rounded-md border border-white/10 bg-white/5 px-1.5 text-[10px] text-neutral-300">
      {children}
    </span>
  );
}

function SectionTabs({
  value,
  onChange,
  queueCount,
}: {
  value: AdminSection;
  onChange: (v: AdminSection) => void;
  queueCount: number;
}) {
  const tabs: { id: AdminSection; label: string; icon: ReactNode }[] = [
    {
      id: "queue",
      label: queueCount > 0 ? `صف · ${faNum(queueCount)}` : "صف",
      icon: <Inbox className="size-3.5" />,
    },
    { id: "stats", label: "آمار", icon: <BarChart3 className="size-3.5" /> },
    { id: "users", label: "کاربران", icon: <Users className="size-3.5" /> },
    { id: "logs", label: "لاگ", icon: <ScrollText className="size-3.5" /> },
    { id: "settings", label: "تنظیمات", icon: <Settings2 className="size-3.5" /> },
  ];

  return (
    <div className="grid grid-cols-5 gap-0.5 rounded-xl border border-white/10 bg-black/40 p-1">
      {tabs.map((t) => {
        const active = value === t.id;
        return (
          <button
            key={t.id}
            type="button"
            onClick={() => onChange(t.id)}
            className={cn(
              "inline-flex flex-col items-center justify-center gap-0.5 rounded-lg px-1 py-2 text-[10px] font-semibold transition-colors sm:flex-row sm:gap-1.5",
              active ? "bg-primary text-primary-foreground" : "text-neutral-400 active:bg-white/10",
            )}
          >
            {t.icon}
            {t.label}
          </button>
        );
      })}
    </div>
  );
}

function AccordionSection({
  icon,
  title,
  summary,
  open,
  onToggle,
  children,
}: {
  icon: ReactNode;
  title: string;
  summary: string;
  open: boolean;
  onToggle: () => void;
  children: ReactNode;
}) {
  return (
    <div className="overflow-hidden rounded-2xl border border-white/12 bg-black/45">
      <button
        type="button"
        onClick={onToggle}
        className="flex w-full items-start gap-3 px-3 py-3 text-start active:bg-white/5"
      >
        <span className="mt-0.5 grid size-8 shrink-0 place-items-center rounded-lg bg-white/8 text-neutral-300">
          {icon}
        </span>
        <span className="min-w-0 flex-1">
          <span className="block text-sm font-semibold">{title}</span>
          <span className="mt-0.5 block text-[11px] leading-relaxed text-neutral-400">{summary}</span>
        </span>
        <ChevronDown
          className={cn("mt-1 size-4 shrink-0 text-neutral-500 transition-transform", open && "rotate-180")}
        />
      </button>
      {open && <div className="border-t border-white/8 px-3 py-3">{children}</div>}
    </div>
  );
}

function EmptyQueue({ message }: { message: string }) {
  return (
    <div className="flex flex-col items-center gap-2 rounded-2xl border border-dashed border-white/12 py-10 text-center">
      <OrbLoader variant="empty" className="opacity-50" />
      <p className="text-sm text-neutral-400">{message}</p>
    </div>
  );
}

function AdminQueue({
  orders,
  withdrawals,
  busy,
  includeTest,
  onIncludeTestChange,
  onSelectOrder,
  onPayWithdrawal,
  onRejectWithdrawal,
}: {
  orders: AdminPendingOrder[];
  withdrawals: AdminWithdrawal[];
  busy: boolean;
  includeTest: boolean;
  onIncludeTestChange: (v: boolean) => void;
  onSelectOrder: (order: AdminPendingOrder) => void;
  onPayWithdrawal: (id: number) => void;
  onRejectWithdrawal: (id: number) => void;
}) {
  return (
    <div className="space-y-4">
      <label className="flex items-center gap-2 text-[11px] text-neutral-400">
        <input
          type="checkbox"
          checked={includeTest}
          onChange={(e) => onIncludeTestChange(e.target.checked)}
          className="size-3.5 rounded border-white/20 bg-black/40"
        />
        نمایش سفارش و برداشت کاربران تست
      </label>
      <div className="grid grid-cols-2 gap-2">
        <div className="rounded-xl border border-white/10 bg-white/5 px-3 py-2.5 text-center">
          <div className="text-[10px] text-neutral-500">سفارش</div>
          <div className="mt-0.5 text-xl font-bold tabular-nums">{faNum(orders.length)}</div>
        </div>
        <div className="rounded-xl border border-white/10 bg-white/5 px-3 py-2.5 text-center">
          <div className="text-[10px] text-neutral-500">برداشت</div>
          <div className="mt-0.5 text-xl font-bold tabular-nums">{faNum(withdrawals.length)}</div>
        </div>
      </div>

      <section className="space-y-2">
        <h3 className="px-0.5 text-xs font-semibold text-neutral-400">سفارش‌های در انتظار</h3>
        {orders.length === 0 ? (
          <EmptyQueue message="سفارشی در صف نیست" />
        ) : (
          orders.map((o) => (
            <button
              key={o.id}
              type="button"
              disabled={busy}
              onClick={() => onSelectOrder(o)}
              className="w-full rounded-xl border border-white/10 bg-black/35 px-3 py-3 text-start transition-opacity active:opacity-80 disabled:opacity-50"
            >
              <div className="flex items-start justify-between gap-2">
                <div className="min-w-0">
                  <div className="font-semibold">
                    #{faNum(o.id)} · {o.plan}
                  </div>
                  <div className="mt-0.5 truncate text-[11px] text-neutral-400">
                    {o.user || "—"} · {faNum(o.telegram_id)}
                  </div>
                </div>
                <span className="shrink-0 text-xs font-medium tabular-nums text-neutral-200">{o.amount_label}</span>
              </div>
              <div className="mt-2 flex flex-wrap gap-1">
                {o.is_wallet_topup && <Chip>شارژ</Chip>}
                {o.is_platform_pro && <Chip>Pro</Chip>}
                {o.wallet_used > 0 && <Chip>کیف‌پول</Chip>}
                {(o.family_size ?? 1) > 1 && <Chip>خانواده {faNum(o.family_size!)}</Chip>}
                {o.promo_code && <Chip>کد {o.promo_code}</Chip>}
                <Chip>{o.has_receipt ? "رسید ✓" : "بدون رسید"}</Chip>
                {o.is_test ? <Chip>تست</Chip> : null}
              </div>
            </button>
          ))
        )}
      </section>

      <section className="space-y-2">
        <h3 className="px-0.5 text-xs font-semibold text-neutral-400">برداشت‌ها</h3>
        {withdrawals.length === 0 ? (
          <EmptyQueue message="برداشتی در صف نیست" />
        ) : (
          withdrawals.map((w) => (
            <div key={w.id} className="rounded-xl border border-white/10 bg-black/35 px-3 py-3">
              <div className="flex items-start justify-between gap-2">
                <div className="min-w-0">
                  <div className="font-semibold">#{faNum(w.id)} · {w.amount_label}</div>
                  <div className="mt-0.5 text-[11px] text-neutral-400">{w.user || "—"}</div>
                  <div className="mt-1 truncate font-mono text-[10px] text-neutral-500" dir="ltr">
                    {w.card_number}
                  </div>
                </div>
              </div>
              <div className="mt-2.5 grid grid-cols-2 gap-2">
                <TgButton disabled={busy} className="h-9 text-xs" onClick={() => onPayWithdrawal(w.id)}>
                  پرداخت شد
                </TgButton>
                <TgButton
                  variant="outline"
                  disabled={busy}
                  className="h-9 text-xs"
                  onClick={() => onRejectWithdrawal(w.id)}
                >
                  رد
                </TgButton>
              </div>
            </div>
          ))
        )}
      </section>
    </div>
  );
}

function AdminSettings({
  busy,
  adminBirthdayGift,
  adminBirthdayEnabled,
  birthdayDraft,
  onBirthdayEnabledChange,
  onBirthdayDraftChange,
  onSaveBirthday,
  adminTrialSettings,
  trialDraft,
  onTrialDraftChange,
  onSaveTrial,
  adminCustomSettings,
  customDraft,
  onCustomDraftChange,
  onSaveCustom,
  adminPaygSettings,
  paygDraft,
  onPaygDraftChange,
  onSavePayg,
  onGrantTrial,
  adminPaymentCards,
  paymentCardDraft,
  onPaymentCardDraftChange,
  onAddPaymentCard,
  onRemovePaymentCard,
  broadcastText,
  onBroadcastTextChange,
  onBroadcast,
  onNotify,
}: {
  busy: boolean;
  adminBirthdayGift: number | null;
  adminBirthdayEnabled: boolean;
  birthdayDraft: string;
  onBirthdayEnabledChange: (v: boolean) => void;
  onBirthdayDraftChange: (v: string) => void;
  onSaveBirthday: () => void;
  adminTrialSettings: TrialSettings | null;
  trialDraft: { enabled: boolean; duration_days: string; traffic_gb: string; limit_ip: string; send_links: boolean };
  onTrialDraftChange: (patch: Partial<typeof trialDraft>) => void;
  onSaveTrial: () => void;
  adminCustomSettings: CustomBuilderAdminSettings | null;
  customDraft: {
    enabled: boolean;
    min_days: string;
    max_days: string;
    min_gb: string;
    max_gb: string;
    min_ip: string;
    max_ip: string;
    base_fee_toman: string;
    price_per_day_toman: string;
    price_per_gb_toman: string;
    unlimited_day_fee_toman: string;
    price_per_ip_toman: string;
    min_price_toman: string;
  };
  onCustomDraftChange: (patch: Partial<typeof customDraft>) => void;
  onSaveCustom: () => void;
  adminPaygSettings: PaygAdminSettings | null;
  paygDraft: {
    enabled: boolean;
    price_per_gb_toman: string;
    prepaid_price_per_gb_toman: string;
    min_wallet_toman: string;
    limit_ip: string;
    min_gb: string;
    max_gb: string;
    min_ip: string;
    max_ip: string;
    price_per_ip_toman: string;
    min_price_toman: string;
  };
  onPaygDraftChange: (patch: Partial<typeof paygDraft>) => void;
  onSavePayg: () => void;
  onGrantTrial: (opts: {
    targets_text?: string;
    all_users?: boolean;
    skip_existing_trial?: boolean;
    notify_users?: boolean;
  }) => Promise<TrialGrantResult>;
  adminPaymentCards: PaymentCard[];
  paymentCardDraft: { card: string; name: string; label: string; note: string };
  onPaymentCardDraftChange: (field: keyof typeof paymentCardDraft, value: string) => void;
  onAddPaymentCard: () => void;
  onRemovePaymentCard: (id: number) => void;
  broadcastText: string;
  onBroadcastTextChange: (v: string) => void;
  onBroadcast: () => void;
  onNotify?: (message: string, kind?: "success" | "error" | "info") => void;
}) {
  const [openSection, setOpenSection] = useState<string | null>(null);
  const [grantTargets, setGrantTargets] = useState("");
  const [skipExisting, setSkipExisting] = useState(true);
  const [notifyUsers, setNotifyUsers] = useState(true);
  const [grantResult, setGrantResult] = useState<TrialGrantResult | null>(null);
  const toggle = (id: string) => setOpenSection((prev) => (prev === id ? null : id));

  const trialSummary = adminTrialSettings
    ? adminTrialSettings.enabled
      ? `${faNum(adminTrialSettings.duration_days)} روز · ${adminTrialSettings.traffic_label}`
      : "غیرفعال"
    : "در حال بارگذاری…";

  const customSummary = adminCustomSettings
    ? adminCustomSettings.enabled
      ? `${faNum(adminCustomSettings.min_days)}–${faNum(adminCustomSettings.max_days)} روز`
      : "غیرفعال"
    : "در حال بارگذاری…";

  const paygSummary = adminPaygSettings
    ? adminPaygSettings.enabled
      ? `${faNum(adminPaygSettings.price_per_gb_toman)} تومان / GB`
      : "غیرفعال"
    : "در حال بارگذاری…";

  return (
    <div className="space-y-2">
      <AccordionSection
        icon={<Cake className="size-4" />}
        title="هدیه تولد"
        summary={
          adminBirthdayEnabled
            ? adminBirthdayGift != null
              ? priceText(adminBirthdayGift)
              : "فعال"
            : "غیرفعال"
        }
        open={openSection === "birthday"}
        onToggle={() => toggle("birthday")}
      >
        <div className="space-y-3">
          <p className="text-[11px] leading-relaxed text-neutral-400">
            اگر فعال باشد، در روز تولد اعتبار به کیف‌پول اضافه می‌شود. به کاربر اعلام نمی‌شود
            و این مبلغ فقط برای خرید داخل فروشگاه قابل استفاده است — برداشت و انتقال ندارد.
          </p>
          <label className="flex items-center gap-2 text-sm text-neutral-300">
            <input
              type="checkbox"
              checked={adminBirthdayEnabled}
              onChange={(e) => onBirthdayEnabledChange(e.target.checked)}
              className="size-4 rounded border-white/20 bg-black/40"
            />
            فعال باشد
          </label>
          <Label className="text-neutral-300">مبلغ (تومان)</Label>
          <Input
            value={birthdayDraft}
            onChange={(e) => onBirthdayDraftChange(e.target.value.replace(/[^\d]/g, ""))}
            dir="ltr"
            inputMode="numeric"
            placeholder="50000"
            className="h-10 rounded-xl border-white/15 bg-black/40"
          />
          <TgButton disabled={busy || birthdayDraft === ""} className="h-10" onClick={onSaveBirthday}>
            ذخیره
          </TgButton>
        </div>
      </AccordionSection>

      <AccordionSection
        icon={<Gift className="size-4" />}
        title="VPN رایگان"
        summary={trialSummary}
        open={openSection === "trial"}
        onToggle={() => toggle("trial")}
      >
        <div className="space-y-4">
          <div className="space-y-3">
            <p className="text-[11px] font-semibold text-neutral-300">پیشنهاد تست — کاربران جدید</p>
            <label className="flex items-center gap-2 text-sm text-neutral-300">
              <input
                type="checkbox"
                checked={trialDraft.enabled}
                onChange={(e) => onTrialDraftChange({ enabled: e.target.checked })}
                className="size-4 rounded border-white/20 bg-black/40"
              />
              نمایش دکمه دریافت تست
            </label>
            <label className="flex items-center gap-2 text-sm text-neutral-300">
              <input
                type="checkbox"
                checked={trialDraft.send_links}
                onChange={(e) => onTrialDraftChange({ send_links: e.target.checked })}
                className="size-4 rounded border-white/20 bg-black/40"
              />
              ارسال لینک کانفیگ داخل ربات
            </label>
            <p className="text-[11px] leading-relaxed text-neutral-500">
              کاربر باید خودش دکمه را در ربات یا فروشگاه بزند. لینک‌ها داخل مینی‌اپ هستند.
            </p>
            <div className="grid grid-cols-3 gap-2">
              {(
                [
                  ["duration_days", "روز"],
                  ["traffic_gb", "گیگ"],
                  ["limit_ip", "دستگاه"],
                ] as const
              ).map(([key, label]) => (
                <div key={key} className="space-y-1">
                  <Label className="text-[10px] text-neutral-500">{label}</Label>
                  <Input
                    value={trialDraft[key]}
                    onChange={(e) =>
                      onTrialDraftChange({ [key]: e.target.value.replace(/[^\d]/g, "") } as Partial<typeof trialDraft>)
                    }
                    dir="ltr"
                    inputMode="numeric"
                    className="h-9 rounded-lg border-white/15 bg-black/40 text-sm"
                  />
                </div>
              ))}
            </div>
            <TgButton disabled={busy} className="h-10" onClick={onSaveTrial}>
              ذخیره تنظیمات
            </TgButton>
          </div>

          <div className="space-y-3 border-t border-white/10 pt-3">
            <p className="text-[11px] font-semibold text-neutral-300">دستی — اعطا به کاربران</p>
            <p className="text-[11px] leading-relaxed text-neutral-500">
              آیدی تلگرام یا @username — هر خط یا با کاما جدا کنید. از تنظیمات بالا برای مدت و ترافیک استفاده می‌شود.
            </p>
            <textarea
              value={grantTargets}
              onChange={(e) => setGrantTargets(e.target.value)}
              rows={3}
              placeholder={"123456789\n@username"}
              dir="ltr"
              className="w-full resize-none rounded-xl border border-white/15 bg-black/40 px-3 py-2.5 font-mono text-xs outline-none focus-visible:ring-2 focus-visible:ring-white/20"
            />
            <label className="flex items-center gap-2 text-[11px] text-neutral-400">
              <input
                type="checkbox"
                checked={skipExisting}
                onChange={(e) => setSkipExisting(e.target.checked)}
                className="size-3.5 rounded border-white/20 bg-black/40"
              />
              رد کردن کسانی که قبلاً VPN تست دارند
            </label>
            <label className="flex items-center gap-2 text-[11px] text-neutral-400">
              <input
                type="checkbox"
                checked={notifyUsers}
                onChange={(e) => setNotifyUsers(e.target.checked)}
                className="size-3.5 rounded border-white/20 bg-black/40"
              />
              ارسال لینک در تلگرام
            </label>
            <div className="grid grid-cols-2 gap-2">
              <TgButton
                disabled={busy || !grantTargets.trim()}
                className="h-10 text-xs"
                onClick={async () => {
                  const res = await onGrantTrial({
                    targets_text: grantTargets,
                    skip_existing_trial: skipExisting,
                    notify_users: notifyUsers,
                  });
                  setGrantResult(res);
                }}
              >
                اعطا به انتخاب‌شده
              </TgButton>
              <TgButton
                variant="outline"
                disabled={busy}
                className="h-10 text-xs"
                onClick={async () => {
                  if (!window.confirm("VPN رایگان به همه کاربران پلتفرم داده شود؟")) return;
                  const res = await onGrantTrial({
                    all_users: true,
                    skip_existing_trial: skipExisting,
                    notify_users: notifyUsers,
                  });
                  setGrantResult(res);
                }}
              >
                اعطا به همه
              </TgButton>
            </div>
            {grantResult && (
              <div className="rounded-xl border border-white/10 bg-black/30 px-3 py-2.5 text-[11px] text-neutral-300">
                <div>
                  موفق: <strong className="text-emerald-300">{faNum(grantResult.granted_count)}</strong>
                  {" · "}
                  رد شده: {faNum(grantResult.skipped_count)}
                  {" · "}
                  خطا: {faNum(grantResult.failed_count)}
                </div>
                {grantResult.not_found.length > 0 && (
                  <div className="mt-1 text-amber-400/90">
                    پیدا نشد: {grantResult.not_found.join(", ")}
                  </div>
                )}
              </div>
            )}
          </div>
        </div>
      </AccordionSection>

      <AccordionSection
        icon={<Sparkles className="size-4" />}
        title="ساخت پکیج سفارشی"
        summary={customSummary}
        open={openSection === "custom"}
        onToggle={() => toggle("custom")}
      >
        <div className="space-y-3">
          <p className="text-[11px] leading-relaxed text-neutral-400">
            محدوده و قیمت ساخت پکیج دلخواه کاربران. قیمت نهایی به نزدیک ۵۰۰۰ تومان گرد می‌شود.
          </p>
          <label className="flex items-center gap-2 text-sm text-neutral-300">
            <input
              type="checkbox"
              checked={customDraft.enabled}
              onChange={(e) => onCustomDraftChange({ enabled: e.target.checked })}
              className="size-4 rounded border-white/20 bg-black/40"
            />
            فعال برای کاربران
          </label>
          <div className="grid grid-cols-2 gap-2">
            {(
              [
                ["min_days", "حداقل روز"],
                ["max_days", "حداکثر روز"],
                ["min_gb", "حداقل GB"],
                ["max_gb", "حداکثر GB"],
                ["min_ip", "حداقل دستگاه"],
                ["max_ip", "حداکثر دستگاه"],
              ] as const
            ).map(([key, label]) => (
              <div key={key} className="space-y-1">
                <Label className="text-[10px] text-neutral-500">{label}</Label>
                <Input
                  value={customDraft[key]}
                  onChange={(e) =>
                    onCustomDraftChange({ [key]: e.target.value.replace(/[^\d]/g, "") } as Partial<typeof customDraft>)
                  }
                  dir="ltr"
                  inputMode="numeric"
                  className="h-9 rounded-lg border-white/15 bg-black/40 text-sm"
                />
              </div>
            ))}
          </div>
          <p className="pt-1 text-[11px] font-semibold text-neutral-300">قیمت‌گذاری (تومان)</p>
          <div className="grid grid-cols-2 gap-2">
            {(
              [
                ["base_fee_toman", "هزینه پایه"],
                ["price_per_day_toman", "هر روز"],
                ["price_per_gb_toman", "هر گیگ"],
                ["unlimited_day_fee_toman", "نامحدود / روز"],
                ["price_per_ip_toman", "هر دستگاه"],
                ["min_price_toman", "حداقل قیمت"],
              ] as const
            ).map(([key, label]) => (
              <div key={key} className="space-y-1">
                <Label className="text-[10px] text-neutral-500">{label}</Label>
                <Input
                  value={customDraft[key]}
                  onChange={(e) =>
                    onCustomDraftChange({ [key]: e.target.value.replace(/[^\d]/g, "") } as Partial<typeof customDraft>)
                  }
                  dir="ltr"
                  inputMode="numeric"
                  className="h-9 rounded-lg border-white/15 bg-black/40 text-sm"
                />
              </div>
            ))}
          </div>
          <TgButton disabled={busy} className="h-10" onClick={onSaveCustom}>
            ذخیره تنظیمات پکیج
          </TgButton>
        </div>
      </AccordionSection>

      <AccordionSection
        icon={<Gauge className="size-4" />}
        title="پرداخت مصرفی"
        summary={paygSummary}
        open={openSection === "payg"}
        onToggle={() => toggle("payg")}
      >
        <div className="space-y-3">
          <p className="text-[11px] leading-relaxed text-neutral-400">
            ابری: شارژ کیف‌پول و پرداخت بر اساس مصرف واقعی. خرید حجم: پکیج گیگ بدون محدودیت زمان.
          </p>
          <label className="flex items-center gap-2 text-sm text-neutral-300">
            <input
              type="checkbox"
              checked={paygDraft.enabled}
              onChange={(e) => onPaygDraftChange({ enabled: e.target.checked })}
              className="size-4 rounded border-white/20 bg-black/40"
            />
            فعال برای کاربران
          </label>
          <div className="grid grid-cols-2 gap-2">
            {(
              [
                ["price_per_gb_toman", "قیمت هر گیگ ابری"],
                ["prepaid_price_per_gb_toman", "قیمت هر گیگ حجم"],
                ["min_wallet_toman", "حداقل موجودی ابری"],
                ["limit_ip", "دستگاه ابری"],
                ["min_gb", "حداقل GB حجم"],
                ["max_gb", "حداکثر GB حجم"],
                ["min_ip", "حداقل دستگاه حجم"],
                ["max_ip", "حداکثر دستگاه حجم"],
                ["price_per_ip_toman", "قیمت هر دستگاه حجم"],
                ["min_price_toman", "حداقل قیمت حجم"],
              ] as const
            ).map(([key, label]) => (
              <div key={key} className="space-y-1">
                <Label className="text-[10px] text-neutral-500">{label}</Label>
                <Input
                  value={paygDraft[key]}
                  onChange={(e) =>
                    onPaygDraftChange({ [key]: e.target.value.replace(/[^\d]/g, "") } as Partial<typeof paygDraft>)
                  }
                  dir="ltr"
                  inputMode="numeric"
                  className="h-9 rounded-lg border-white/15 bg-black/40 text-sm"
                />
              </div>
            ))}
          </div>
          <TgButton disabled={busy} className="h-10" onClick={onSavePayg}>
            ذخیره تنظیمات مصرفی
          </TgButton>
        </div>
      </AccordionSection>

      <AccordionSection
        icon={<TicketPercent className="size-4" />}
        title="تخفیف خرید و خانواده"
        summary="تخفیف هنگام خرید، کد، پکیج خانواده"
        open={openSection === "growth"}
        onToggle={() => toggle("growth")}
      >
        <GrowthAdminPanel busy={busy} onNotify={onNotify} />
      </AccordionSection>

      <AccordionSection
        icon={<Globe className="size-4" />}
        title="سرورهای کشورها"
        summary={ "پنل‌های 3x-ui برای اشتراک کاربران" }
        open={openSection === "servers"}
        onToggle={() => toggle("servers")}
      >
        <AdminServersPanel busy={busy} />
      </AccordionSection>

      <AccordionSection
        icon={<CreditCard className="size-4" />}
        title="کارت‌های پرداخت"
        summary={`${faNum(adminPaymentCards.length)} کارت فعال`}
        open={openSection === "cards"}
        onToggle={() => toggle("cards")}
      >
        <AdminPaymentCardsPanel
          cards={adminPaymentCards}
          busy={busy}
          draft={paymentCardDraft}
          onDraftChange={onPaymentCardDraftChange}
          onAdd={onAddPaymentCard}
          onRemove={onRemovePaymentCard}
          hideTitle
        />
      </AccordionSection>

      <AccordionSection
        icon={<Megaphone className="size-4" />}
        title="پیام همگانی"
        summary="ارسال اعلان به همه کاربران"
        open={openSection === "broadcast"}
        onToggle={() => toggle("broadcast")}
      >
        <div className="space-y-2">
          <textarea
            value={broadcastText}
            onChange={(e) => onBroadcastTextChange(e.target.value)}
            rows={4}
            placeholder="متن پیام…"
            className="w-full resize-none rounded-xl border border-white/15 bg-black/40 px-3 py-2.5 text-sm leading-relaxed outline-none focus-visible:ring-2 focus-visible:ring-white/20"
          />
          <TgButton disabled={busy || broadcastText.trim().length < 2} className="h-10" onClick={onBroadcast}>
            ارسال
          </TgButton>
        </div>
      </AccordionSection>
    </div>
  );
}

function AdminUsers({
  busy,
  onSearchUsers,
  onSetUserRole,
  onGrantTrial,
  onOpenChat,
  onOpenSubscription,
  onNotify,
}: {
  busy: boolean;
  onSearchUsers: (q: string, includeTest?: boolean, slice?: string) => Promise<AdminUser[]>;
  onSetUserRole: (userId: number, role: "user" | "admin") => Promise<AdminUser>;
  onGrantTrial: (opts: {
    targets_text?: string;
    all_users?: boolean;
    skip_existing_trial?: boolean;
    notify_users?: boolean;
  }) => Promise<TrialGrantResult>;
  onOpenChat: (userId: number) => void;
  onOpenSubscription?: (subId: number) => void;
  onNotify: (message: string, kind?: "success" | "error" | "info") => void;
}) {
  const [query, setQuery] = useState("");
  const [items, setItems] = useState<AdminUser[]>([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState("");
  const [includeTest, setIncludeTest] = useState(false);
  const [openUserId, setOpenUserId] = useState<number | null>(null);

  useEffect(() => {
    let cancelled = false;
    const delay = query.trim() ? 280 : 0;
    const timer = window.setTimeout(() => {
      setLoading(true);
      void onSearchUsers(query.trim(), includeTest, filter)
        .then((rows) => {
          if (!cancelled) setItems(rows);
        })
        .catch((e) => {
          if (!cancelled) onNotify(e instanceof Error ? e.message : "بارگذاری کاربران ناموفق", "error");
        })
        .finally(() => {
          if (!cancelled) setLoading(false);
        });
    }, delay);
    return () => {
      cancelled = true;
      window.clearTimeout(timer);
    };
  }, [query, includeTest, filter]); // eslint-disable-line react-hooks/exhaustive-deps

  const shown = items;
  const issueCount = items.filter((u) => u.has_issue).length;

  return (
    <div className="space-y-3">
      <div className="relative">
        <Search className="pointer-events-none absolute start-3 top-1/2 size-4 -translate-y-1/2 text-neutral-500" />
        <Input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="آیدی تلگرام، @username یا نام"
          dir="ltr"
          className="h-11 rounded-xl border-white/15 bg-black/40 ps-10 font-mono text-sm"
        />
      </div>
      <div className="flex gap-1.5 overflow-x-auto pb-0.5">
        {(
          [
            { id: "", label: "همه" },
            { id: "issues", label: issueCount > 0 ? `رسیدگی · ${faNum(issueCount)}` : "رسیدگی" },
            { id: "paying", label: "خرید کرده" },
            { id: "expired", label: "منقضی" },
            { id: "expiring", label: "در حال انقضا" },
            { id: "wallet", label: "کیف‌پول" },
            { id: "trial", label: "تست گرفته" },
            { id: "pending", label: "سفارش باز" },
          ] as const
        ).map((f) => (
          <button
            key={f.id || "all"}
            type="button"
            onClick={() => setFilter(f.id)}
            className={cn(
              "h-8 shrink-0 rounded-lg border px-3 text-[11px] font-semibold",
              filter === f.id
                ? f.id === "issues"
                  ? "border-orange-400/40 bg-orange-500/15 text-orange-100"
                  : "border-primary bg-primary text-primary-foreground"
                : "border-white/12 bg-black/30 text-neutral-400",
            )}
          >
            {f.label}
          </button>
        ))}
        <label className="ms-auto flex shrink-0 items-center gap-1.5 text-[11px] text-neutral-500">
          <input
            type="checkbox"
            checked={includeTest}
            onChange={(e) => setIncludeTest(e.target.checked)}
            className="size-3.5 rounded border-white/20 bg-black/40"
          />
          کاربران تست
        </label>
      </div>

      {loading && <p className="py-6 text-center text-xs text-neutral-500">در حال جستجو…</p>}
      {!loading && shown.length === 0 && (
        <p className="rounded-xl border border-dashed border-white/10 px-3 py-6 text-center text-xs text-neutral-500">
          {filter === "issues" ? "موردی برای رسیدگی نیست" : "کاربری پیدا نشد"}
        </p>
      )}
      <div className="space-y-2">
        {shown.map((u) => {
          const title = u.full_name || (u.username ? `@${u.username}` : faNum(u.telegram_id));
          return (
            <button
              key={u.id}
              type="button"
              onClick={() => setOpenUserId(u.id)}
              className="w-full rounded-xl border border-white/10 bg-black/30 px-3 py-2.5 text-start active:bg-white/8"
            >
              <div className="flex items-start justify-between gap-2">
                <div className="min-w-0">
                  <div className="truncate text-sm font-semibold">{title}</div>
                  <div className="mt-0.5 font-mono text-[10px] text-neutral-500" dir="ltr">
                    {u.username ? `@${u.username} · ` : ""}
                    {u.telegram_id}
                  </div>
                </div>
                {u.has_issue ? (
                  <span className="shrink-0 rounded-md border border-orange-400/30 bg-orange-500/10 px-1.5 py-0.5 text-[10px] text-orange-200">
                    باز
                  </span>
                ) : null}
              </div>
              <div className="mt-1.5 flex flex-wrap gap-1">
                <Chip>
                  {u.is_super_admin ? "ادمین اصلی" : u.is_admin ? "ادمین" : "کاربر"}
                </Chip>
                <Chip>{u.wallet_label || priceText(u.wallet_balance)}</Chip>
                <Chip>
                  {faNum(u.active_subscription_count ?? u.subscription_count)} کانفیگ
                </Chip>
                {(u.pending_order_count || 0) > 0 ? (
                  <Chip>{faNum(u.pending_order_count!)} سفارش باز</Chip>
                ) : null}
                {(u.chat_unread || 0) > 0 ? <Chip>{faNum(u.chat_unread!)} پیام</Chip> : null}
                {u.is_test ? <Chip>تست</Chip> : null}
              </div>
            </button>
          );
        })}
      </div>

      <AdminUserSheet
        open={openUserId != null}
        onClose={() => {
          setOpenUserId(null);
          void onSearchUsers(query.trim(), includeTest, filter).then(setItems).catch(() => undefined);
        }}
        userId={openUserId}
        busy={busy}
        onOpenChat={onOpenChat}
        onOpenSubscription={onOpenSubscription}
        onSetRole={onSetUserRole}
        onGrantTrial={onGrantTrial}
        onNotify={onNotify}
      />
    </div>
  );
}

export function AdminPanel({
  loading,
  busy,
  orders,
  withdrawals,
  pendingCount,
  onOpenNotifCenter,
  onOpenHistory,
  onSelectOrder,
  onPayWithdrawal,
  onRejectWithdrawal,
  adminBirthdayGift,
  adminBirthdayEnabled,
  birthdayDraft,
  onBirthdayEnabledChange,
  onBirthdayDraftChange,
  onSaveBirthday,
  adminTrialSettings,
  trialDraft,
  onTrialDraftChange,
  onSaveTrial,
  adminCustomSettings,
  customDraft,
  onCustomDraftChange,
  onSaveCustom,
  adminPaygSettings,
  paygDraft,
  onPaygDraftChange,
  onSavePayg,
  onGrantTrial,
  includeTestQueue,
  onIncludeTestQueueChange,
  onSearchUsers,
  onSetUserRole,
  onOpenChat,
  onOpenSubscription,
  onNotify,
  adminPaymentCards,
  paymentCardDraft,
  onPaymentCardDraftChange,
  onAddPaymentCard,
  onRemovePaymentCard,
  broadcastText,
  onBroadcastTextChange,
  onBroadcast,
}: {
  loading: boolean;
  busy: boolean;
  orders: AdminPendingOrder[];
  withdrawals: AdminWithdrawal[];
  pendingCount: number;
  onOpenNotifCenter: () => void;
  onOpenHistory?: () => void;
  onSelectOrder: (order: AdminPendingOrder) => void;
  onPayWithdrawal: (id: number) => void;
  onRejectWithdrawal: (id: number) => void;
  adminBirthdayGift: number | null;
  adminBirthdayEnabled: boolean;
  birthdayDraft: string;
  onBirthdayEnabledChange: (v: boolean) => void;
  onBirthdayDraftChange: (v: string) => void;
  onSaveBirthday: () => void;
  adminTrialSettings: TrialSettings | null;
  trialDraft: { enabled: boolean; duration_days: string; traffic_gb: string; limit_ip: string; send_links: boolean };
  onTrialDraftChange: (patch: Partial<typeof trialDraft>) => void;
  onSaveTrial: () => void;
  adminCustomSettings: CustomBuilderAdminSettings | null;
  customDraft: {
    enabled: boolean;
    min_days: string;
    max_days: string;
    min_gb: string;
    max_gb: string;
    min_ip: string;
    max_ip: string;
    base_fee_toman: string;
    price_per_day_toman: string;
    price_per_gb_toman: string;
    unlimited_day_fee_toman: string;
    price_per_ip_toman: string;
    min_price_toman: string;
  };
  onCustomDraftChange: (patch: Partial<typeof customDraft>) => void;
  onSaveCustom: () => void;
  adminPaygSettings: PaygAdminSettings | null;
  paygDraft: {
    enabled: boolean;
    price_per_gb_toman: string;
    prepaid_price_per_gb_toman: string;
    min_wallet_toman: string;
    limit_ip: string;
    min_gb: string;
    max_gb: string;
    min_ip: string;
    max_ip: string;
    price_per_ip_toman: string;
    min_price_toman: string;
  };
  onPaygDraftChange: (patch: Partial<typeof paygDraft>) => void;
  onSavePayg: () => void;
  onGrantTrial: (opts: {
    targets_text?: string;
    all_users?: boolean;
    skip_existing_trial?: boolean;
    notify_users?: boolean;
  }) => Promise<TrialGrantResult>;
  includeTestQueue: boolean;
  onIncludeTestQueueChange: (v: boolean) => void;
  onSearchUsers: (q: string, includeTest?: boolean, slice?: string) => Promise<AdminUser[]>;
  onSetUserRole: (userId: number, role: "user" | "admin") => Promise<AdminUser>;
  onOpenChat: (userId: number) => void;
  onOpenSubscription?: (subId: number) => void;
  onNotify: (message: string, kind?: "success" | "error" | "info") => void;
  adminPaymentCards: PaymentCard[];
  paymentCardDraft: { card: string; name: string; label: string; note: string };
  onPaymentCardDraftChange: (field: keyof typeof paymentCardDraft, value: string) => void;
  onAddPaymentCard: () => void;
  onRemovePaymentCard: (id: number) => void;
  broadcastText: string;
  onBroadcastTextChange: (v: string) => void;
  onBroadcast: () => void;
}) {
  const [section, setSection] = useState<AdminSection>("queue");

  if (loading) {
    return <OrbLoaderPanel variant="admin" message="در حال بارگذاری…" />;
  }

  return (
    <div className="space-y-3 pb-1">
      <div className="flex items-center justify-between gap-2">
        <div>
          <div className="flex items-center gap-1.5">
            <Sparkles className="size-4 text-neutral-400" aria-hidden />
            <h2 className="text-base font-bold">پنل ادمین</h2>
          </div>
          <p className="mt-0.5 text-[11px] text-neutral-400">
            {pendingCount > 0 ? `${faNum(pendingCount)} مورد نیاز به بررسی` : "همه چیز مرتب است"}
          </p>
        </div>
        <div className="flex items-center gap-2">
          {onOpenHistory && (
            <button
              type="button"
              onClick={onOpenHistory}
              className="inline-flex size-10 items-center justify-center rounded-xl border border-white/15 bg-black/50 text-neutral-300 active:bg-white/10"
              aria-label="تاریخچه سفارشات"
            >
              <History className="size-4" />
            </button>
          )}
          <button
            type="button"
            onClick={onOpenNotifCenter}
            className="relative inline-flex size-10 items-center justify-center rounded-xl border border-white/15 bg-black/50 text-neutral-300 active:bg-white/10"
            aria-label="مرکز اعلان"
          >
          <Bell className="size-4" />
          {pendingCount > 0 && (
            <span className="absolute -top-1 -end-1 flex min-w-[1rem] items-center justify-center rounded-full bg-orange-500 px-1 text-[9px] font-bold text-white">
              {faNum(Math.min(pendingCount, 99))}
            </span>
          )}
        </button>
        </div>
      </div>

      <SectionTabs value={section} onChange={setSection} queueCount={pendingCount} />

      {section === "queue" ? (
        <AdminQueue
          orders={orders}
          withdrawals={withdrawals}
          busy={busy}
          includeTest={includeTestQueue}
          onIncludeTestChange={onIncludeTestQueueChange}
          onSelectOrder={onSelectOrder}
          onPayWithdrawal={onPayWithdrawal}
          onRejectWithdrawal={onRejectWithdrawal}
        />
      ) : section === "stats" ? (
        <AdminAnalyticsPanel
          onOpenChat={onOpenChat}
          onSetRole={onSetUserRole}
          onGrantTrial={onGrantTrial}
          onOpenSubscription={onOpenSubscription}
          onNotify={onNotify}
        />
      ) : section === "users" ? (
        <AdminUsers
          busy={busy}
          onSearchUsers={onSearchUsers}
          onSetUserRole={onSetUserRole}
          onGrantTrial={onGrantTrial}
          onOpenChat={onOpenChat}
          onOpenSubscription={onOpenSubscription}
          onNotify={onNotify}
        />
      ) : section === "logs" ? (
        <AdminActivityLogPanel />
      ) : (
        <AdminSettings
          busy={busy}
          adminBirthdayGift={adminBirthdayGift}
          adminBirthdayEnabled={adminBirthdayEnabled}
          birthdayDraft={birthdayDraft}
          onBirthdayEnabledChange={onBirthdayEnabledChange}
          onBirthdayDraftChange={onBirthdayDraftChange}
          onSaveBirthday={onSaveBirthday}
          adminTrialSettings={adminTrialSettings}
          trialDraft={trialDraft}
          onTrialDraftChange={onTrialDraftChange}
          onSaveTrial={onSaveTrial}
          adminCustomSettings={adminCustomSettings}
          customDraft={customDraft}
          onCustomDraftChange={onCustomDraftChange}
          onSaveCustom={onSaveCustom}
          adminPaygSettings={adminPaygSettings}
          paygDraft={paygDraft}
          onPaygDraftChange={onPaygDraftChange}
          onSavePayg={onSavePayg}
          onGrantTrial={onGrantTrial}
          adminPaymentCards={adminPaymentCards}
          paymentCardDraft={paymentCardDraft}
          onPaymentCardDraftChange={onPaymentCardDraftChange}
          onAddPaymentCard={onAddPaymentCard}
          onRemovePaymentCard={onRemovePaymentCard}
          broadcastText={broadcastText}
          onBroadcastTextChange={onBroadcastTextChange}
          onBroadcast={onBroadcast}
          onNotify={onNotify}
        />
      )}
    </div>
  );
}
