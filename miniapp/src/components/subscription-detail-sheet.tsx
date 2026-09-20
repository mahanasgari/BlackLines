import { useCallback, useEffect, useMemo, useState, type ReactNode } from "react";
import {
  ArrowRightLeft,
  Check,
  Copy,
  ExternalLink,
  KeyRound,
  RefreshCw,
  ShieldOff,
  CalendarClock,
  Wifi,
  WifiOff,
  Link2,
  Info,
  Tag,
  ChevronDown,
  Users,
  Sparkles,
} from "lucide-react";
import { api, haptic, type OrderCreated, type Plan, type RenewOrderResponse, type SubscriptionDetail } from "@/api";
import { CustomPackageBuilder } from "@/components/custom-package-builder";
import { EditableConfigName } from "@/components/editable-config-name";
import { FamilyParentalSection } from "@/components/family-parental-section";
import { SelfFixSheet } from "@/components/self-fix-sheet";
import { PaygTrafficBuilder } from "@/components/payg-traffic-builder";
import { TgButton } from "@/components/tg-button";
import { TgSheet } from "@/components/tg-sheet";
import { cn, faNum } from "@/lib/utils";
import { OrbLoaderPanel } from "@/components/orb-loader";
import { buildClientDeepLinks, openExternalUrl } from "@/lib/client-deeplinks";

type DetailTab = "connect" | "usage" | "renew" | "more";

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

function formatDate(iso: string | null | undefined, short = false) {
  if (!iso) return "—";
  try {
    return new Intl.DateTimeFormat("fa-IR", {
      dateStyle: short ? "short" : "medium",
      ...(short ? {} : { timeStyle: "short" }),
    }).format(new Date(iso));
  } catch {
    return iso.slice(0, short ? 10 : 16).replace("T", " ");
  }
}

function statusMeta(detail: SubscriptionDetail) {
  if (detail.online) {
    return { text: "آنلاین", className: "border-emerald-500/30 bg-emerald-500/15 text-emerald-300" };
  }
  if (detail.status === "expired") {
    return { text: "منقضی", className: "border-red-500/30 bg-red-500/15 text-red-300" };
  }
  if (detail.status === "disabled") {
    return { text: "غیرفعال", className: "border-neutral-500/30 bg-neutral-500/15 text-neutral-400" };
  }
  return { text: "آفلاین", className: "border-amber-500/25 bg-amber-500/10 text-amber-200" };
}

function ipLimitLabel(connected: number, limit: number) {
  if (limit > 0) return `${faNum(connected)} / ${faNum(limit)}`;
  return connected > 0 ? faNum(connected) : "۰";
}

function Section({
  title,
  icon,
  children,
  className,
  defaultOpen = false,
}: {
  title: string;
  icon: ReactNode;
  children: ReactNode;
  className?: string;
  defaultOpen?: boolean;
}) {
  const [open, setOpen] = useState(defaultOpen);
  return (
    <section className={cn("overflow-hidden rounded-xl border border-white/10 bg-black/25", className)}>
      <button
        type="button"
        className="flex w-full items-center justify-between gap-2 px-3 py-2.5 text-start active:bg-white/5"
        onClick={() => setOpen((v) => !v)}
      >
        <span className="inline-flex items-center gap-1.5 text-xs font-semibold text-neutral-200">
          {icon}
          {title}
        </span>
        <ChevronDown className={cn("size-4 shrink-0 text-neutral-500 transition-transform", open && "rotate-180")} />
      </button>
      {open ? <div className="space-y-2.5 border-t border-white/8 px-3 pb-3 pt-2.5">{children}</div> : null}
    </section>
  );
}

function StatTile({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="rounded-lg border border-white/8 bg-black/30 px-2 py-2 text-center">
      <div className="text-[10px] text-neutral-500">{label}</div>
      <div className="mt-0.5 text-xs font-semibold tabular-nums text-neutral-100">{value}</div>
    </div>
  );
}

function IconCopyBtn({ active, onClick }: { active?: boolean; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="inline-flex size-8 shrink-0 items-center justify-center rounded-lg border border-white/10 bg-white/5 text-neutral-300 active:bg-white/10"
    >
      {active ? <Check className="size-3.5 text-emerald-400" /> : <Copy className="size-3.5" />}
    </button>
  );
}

function TabBtn({
  active,
  label,
  onClick,
}: {
  active: boolean;
  label: string;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "min-w-0 flex-1 rounded-lg px-1.5 py-2 text-[11px] font-medium transition-colors",
        active ? "bg-white text-black" : "text-neutral-400 active:bg-white/8",
      )}
    >
      {label}
    </button>
  );
}

export function SubscriptionDetailSheet({
  open,
  onClose,
  subId,
  initialTab,
  plans,
  onRenewCheckout,
  onRevoked,
  onLinkRotated,
  onTransferred,
  onLabelSaved,
  onCustomerSaved,
  onLinkShared,
  onTopup,
}: {
  open: boolean;
  onClose: () => void;
  subId: number | null;
  initialTab?: "connect" | "usage" | "renew" | "more" | null;
  plans: Plan[];
  onRenewCheckout: (order: OrderCreated | RenewOrderResponse) => void | Promise<void>;
  onRevoked?: () => void;
  onLinkRotated?: (subId: number, subscriptionUrl: string | null) => void;
  onTransferred?: (info: { movedCount: number; familyMoved: boolean; targetName: string }) => void;
  onLabelSaved?: (subId: number, label: string | null) => void;
  onCustomerSaved?: (
    subId: number,
    customer: {
      customer_name: string | null;
      customer_email: string | null;
      customer_phone: string | null;
      customer_telegram_id: string | null;
    },
  ) => void;
  onLinkShared?: (subId: number) => void;
  onTopup?: () => void;
}) {
  const [detail, setDetail] = useState<SubscriptionDetail | null>(null);
  const [loading, setLoading] = useState(false);
  const [busy, setBusy] = useState(false);
  const [labelDraft, setLabelDraft] = useState("");
  const [customerDraft, setCustomerDraft] = useState({
    customer_name: "",
    customer_email: "",
    customer_phone: "",
    customer_telegram_id: "",
  });
  const [copied, setCopied] = useState<string | null>(null);
  const [renewPlanId, setRenewPlanId] = useState<number | null>(null);
  const [renewCustom, setRenewCustom] = useState(false);
  const [confirmRevoke, setConfirmRevoke] = useState(false);
  const [confirmRotate, setConfirmRotate] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);
  const [linkRotated, setLinkRotated] = useState(false);
  const [transferTarget, setTransferTarget] = useState("");
  const [transferPreview, setTransferPreview] = useState<{
    telegram_id: number;
    username: string | null;
    full_name: string | null;
  } | null>(null);
  const [confirmTransfer, setConfirmTransfer] = useState(false);
  const [tab, setTab] = useState<DetailTab>("connect");
  const [serversOpen, setServersOpen] = useState(false);
  const [diagnoseOpen, setDiagnoseOpen] = useState(false);

  const load = useCallback(async () => {
    if (!subId) return;
    setLoading(true);
    try {
      const data = await api.subscriptionDetail(subId);
      setDetail(data);
      setLabelDraft(data.label?.trim() || "");
      setCustomerDraft({
        customer_name: data.customer_name || "",
        customer_email: data.customer_email || "",
        customer_phone: data.customer_phone || "",
        customer_telegram_id: data.customer_telegram_id || "",
      });
      setRenewPlanId(data.plan_id);
      const nearExpiry = data.remaining_days != null && data.remaining_days <= 5;
      const expired = data.status === "expired" || data.expired;
      setTab(initialTab || (expired || nearExpiry ? "renew" : "connect"));
      setServersOpen(false);
    } finally {
      setLoading(false);
    }
  }, [subId, initialTab]);

  useEffect(() => {
    if (!open || !subId) return;
    setConfirmRevoke(false);
    setConfirmRotate(false);
    setActionError(null);
    setLinkRotated(false);
    setTransferTarget("");
    setTransferPreview(null);
    setConfirmTransfer(false);
    setRenewCustom(false);
    setTab("connect");
    setServersOpen(false);
    setDiagnoseOpen(false);
    void load();
  }, [open, subId, load]);

  const flashCopied = (key: string) => {
    setCopied(key);
    window.setTimeout(() => setCopied(null), 1500);
  };

  const markCustomerLinkShared = () => {
    if (!subId || !detail?.customer_name) return;
    void api
      .markLinkShared(subId, true)
      .then(() => onLinkShared?.(subId))
      .catch(() => undefined);
  };

  const openTelegramProxy = (url: string) => {
    const tg = window.Telegram?.WebApp;
    if (tg?.openTelegramLink) {
      tg.openTelegramLink(url);
      return;
    }
    window.open(url, "_blank", "noopener,noreferrer");
  };

  const saveLabel = async (next?: string) => {
    if (!subId) return;
    const value = (next ?? labelDraft).trim();
    setBusy(true);
    try {
      const res = await api.setLabel(subId, value);
      setLabelDraft(res.label?.trim() || "");
      setDetail((d) => (d ? { ...d, label: res.label } : d));
      onLabelSaved?.(subId, res.label);
    } finally {
      setBusy(false);
    }
  };

  const saveCustomer = async () => {
    if (!subId) return;
    setBusy(true);
    try {
      const res = await api.setCustomer(subId, {
        customer_name: customerDraft.customer_name.trim() || null,
        customer_email: customerDraft.customer_email.trim() || null,
        customer_phone: customerDraft.customer_phone.trim() || null,
        customer_telegram_id: customerDraft.customer_telegram_id.trim().replace(/^@/, "") || null,
      });
      onCustomerSaved?.(subId, {
        customer_name: res.customer_name ?? null,
        customer_email: res.customer_email ?? null,
        customer_phone: res.customer_phone ?? null,
        customer_telegram_id: res.customer_telegram_id ?? null,
      });
      void load();
    } finally {
      setBusy(false);
    }
  };

  const startRenew = async () => {
    if (!subId || !renewPlanId) return;
    setBusy(true);
    try {
      const order = await api.renewSubscription(subId, renewPlanId);
      await onRenewCheckout(order);
      onClose();
    } finally {
      setBusy(false);
    }
  };

  const revoke = async () => {
    if (!subId) return;
    setBusy(true);
    setActionError(null);
    try {
      await api.revokeSubscription(subId);
      haptic();
      onRevoked?.();
      onClose();
    } catch (e) {
      setActionError(e instanceof Error ? e.message : "غیرفعال‌سازی ناموفق بود");
    } finally {
      setBusy(false);
    }
  };

  const rotateLink = async () => {
    if (!subId) return;
    setBusy(true);
    setActionError(null);
    try {
      const res = await api.rotateSubscriptionLink(subId);
      haptic();
      setConfirmRotate(false);
      setLinkRotated(true);
      onLinkRotated?.(subId, res.subscription_url);
      const data = await api.subscriptionDetail(subId);
      setDetail(data);
      setTab("connect");
      if (res.subscription_url) {
        const ok = await copyText(res.subscription_url);
        if (ok) {
          flashCopied("sub-url");
          if (data.customer_name) {
            void api
              .markLinkShared(subId, true)
              .then(() => onLinkShared?.(subId))
              .catch(() => undefined);
          }
        }
      }
    } catch (e) {
      setActionError(e instanceof Error ? e.message : "ساخت لینک جدید ناموفق بود");
    } finally {
      setBusy(false);
    }
  };

  const lookupTransfer = async () => {
    const q = transferTarget.trim();
    if (!q) {
      setActionError("آیدی عددی تلگرام یا @username را وارد کن");
      return;
    }
    setBusy(true);
    setActionError(null);
    setConfirmTransfer(false);
    try {
      const res = await api.lookupTransferTarget(q);
      setTransferPreview(res.user);
      haptic();
    } catch (e) {
      setTransferPreview(null);
      setActionError(e instanceof Error ? e.message : "کاربر پیدا نشد");
    } finally {
      setBusy(false);
    }
  };

  const transferOwnership = async () => {
    if (!subId || !transferPreview) return;
    setBusy(true);
    setActionError(null);
    try {
      const res = await api.transferSubscription(subId, String(transferPreview.telegram_id));
      haptic();
      const targetName =
        res.target.full_name?.trim() ||
        (res.target.username ? `@${res.target.username}` : String(res.target.telegram_id));
      onTransferred?.({
        movedCount: res.moved_count,
        familyMoved: res.family_moved,
        targetName,
      });
      onClose();
    } catch (e) {
      setActionError(e instanceof Error ? e.message : "انتقال ناموفق بود");
    } finally {
      setBusy(false);
    }
  };

  const title = detail?.label?.trim() || detail?.plan_title || "جزئیات کانفیگ";
  const st = detail ? statusMeta(detail) : null;
  const usagePct = detail && detail.total_bytes > 0 ? Math.min(100, detail.usage_percent) : 0;

  const bestLink = useMemo(() => {
    if (!detail?.links?.length) return null;
    return (
      [...detail.links]
        .filter((l) => l.kind !== "telegram" && l.reachable && l.ping_ms != null)
        .sort((a, b) => (a.ping_ms ?? 99999) - (b.ping_ms ?? 99999))[0] ??
      detail.links.find((l) => l.kind !== "telegram") ??
      detail.links[0]
    );
  }, [detail]);

  const deepLinks = useMemo(
    () =>
      buildClientDeepLinks({
        subscriptionUrl: detail?.subscription_url,
        shareLink: bestLink?.link,
        name: detail?.label || detail?.plan_title || "BlackLines",
      }),
    [detail?.subscription_url, detail?.label, detail?.plan_title, bestLink?.link],
  );

  return (
    <>
    <TgSheet
      open={open}
      onClose={onClose}
      title={
        <EditableConfigName
          name={title}
          disabled={busy || loading}
          nameClassName="text-sm"
          onSave={(label) => saveLabel(label)}
        />
      }
      description={detail?.email}
      layer={140}
    >
      {loading && <OrbLoaderPanel variant="dashboard" message="در حال بارگذاری…" />}

      {!loading && detail && st && (
        <div className="space-y-3 pb-1">
          {/* Compact status */}
          <div className="rounded-xl border border-white/10 bg-gradient-to-b from-white/[0.05] to-black/40 p-3">
            <div className="flex items-center justify-between gap-2">
              <div className="flex min-w-0 flex-wrap items-center gap-1">
                <span className={cn("rounded-lg border px-2 py-0.5 text-[11px] font-medium", st.className)}>
                  {st.text}
                </span>
                {detail.source_label ? (
                  <span
                    className={cn(
                      "rounded-lg border px-2 py-0.5 text-[11px] font-medium",
                      detail.order_status === "pending"
                        ? "border-amber-400/30 bg-amber-500/10 text-amber-200"
                        : detail.order_status === "rejected" || detail.order_status === "cancelled"
                          ? "border-red-500/30 bg-red-500/10 text-red-200"
                          : "border-sky-500/25 bg-sky-500/10 text-sky-100",
                    )}
                  >
                    {detail.source_label}
                    {detail.order_status_label ? ` · ${detail.order_status_label}` : ""}
                  </span>
                ) : null}
              </div>
              <span className="inline-flex items-center gap-1 text-[11px] text-neutral-400">
                {detail.connection.online ? (
                  <Wifi className="size-3.5 text-emerald-400" />
                ) : (
                  <WifiOff className="size-3.5 text-neutral-500" />
                )}
                {detail.connection.online ? "متصل" : "قطع"}
                {detail.connection.ip_available ? (
                  <span className="tabular-nums text-neutral-500">
                    · IP {ipLimitLabel(detail.connection.connected_ip_count, detail.connection.limit_ip)}
                  </span>
                ) : null}
              </span>
            </div>

            {detail.abuse?.active ? (
              <div className="mt-2 rounded-xl border border-amber-500/30 bg-amber-500/10 px-2.5 py-2 text-[11px] leading-relaxed text-amber-100">
                محدودیت موقت فعال است
                {detail.abuse.notes ? ` · ${detail.abuse.notes}` : ""}
                {detail.abuse.throttled_until
                  ? ` · تا ${formatDate(detail.abuse.throttled_until)}`
                  : ""}
                . کانفیگ حذف نشده؛ بعد از رفع مشکل خودکار وصل می‌شود.
              </div>
            ) : null}

            <div className="mt-2.5">
              <div className="mb-1 flex items-center justify-between text-[11px] text-neutral-400">
                <span>ترافیک</span>
                <span className="tabular-nums">
                  {detail.used_label} / {detail.total_label}
                  {detail.total_bytes > 0 ? ` · ${faNum(Math.round(detail.usage_percent))}٪` : ""}
                </span>
              </div>
              <div className="h-1.5 overflow-hidden rounded-full bg-white/10">
                <div
                  className={cn(
                    "h-full rounded-full transition-[width]",
                    usagePct >= 90 ? "bg-red-400/90" : usagePct >= 70 ? "bg-amber-400/85" : "bg-emerald-400/85",
                  )}
                  style={{ width: `${usagePct}%` }}
                />
              </div>
            </div>

            <div className="mt-2.5 grid grid-cols-2 gap-2">
              <StatTile label="انقضا" value={formatDate(detail.expires_at, true)} />
              <StatTile
                label="باقی‌مانده"
                value={
                  detail.remaining_days != null
                    ? `${faNum(detail.remaining_days)} روز`
                    : detail.remaining_label
                }
              />
            </div>
          </div>

          {/* Navigation */}
          <div className="grid grid-cols-4 gap-1 rounded-xl border border-white/10 bg-black/35 p-1">
            <TabBtn active={tab === "connect"} label="اتصال" onClick={() => setTab("connect")} />
            <TabBtn active={tab === "usage"} label="مصرف" onClick={() => setTab("usage")} />
            <TabBtn
              active={tab === "renew"}
              label={detail.is_payg ? "شارژ" : "تمدید"}
              onClick={() => setTab("renew")}
            />
            <TabBtn active={tab === "more"} label="بیشتر" onClick={() => setTab("more")} />
          </div>

          {/* CONNECT */}
          {tab === "connect" ? (
            <div className="space-y-3">
              <div className="space-y-2.5 rounded-xl border border-emerald-500/25 bg-emerald-500/[0.06] p-3.5">
                <div className="flex items-start gap-2">
                  <Sparkles className="mt-0.5 size-4 shrink-0 text-emerald-300" />
                  <div className="min-w-0">
                    <p className="text-sm font-semibold text-emerald-100">اتصال سریع</p>
                    <p className="mt-1 text-[11px] leading-relaxed text-neutral-400">
                      {detail.subscription_url
                        ? "با یک ضربه در Hiddify / v2rayNG باز کن، یا لینک را کپی کن."
                        : "لینک کانفیگ را کپی کنید یا مستقیم در اپ کلاینت باز کنید."}
                    </p>
                    {detail.customer_name ? (
                      <p className="mt-2 rounded-lg border border-teal-500/20 bg-teal-500/10 px-2.5 py-1.5 text-[11px] leading-relaxed text-teal-100">
                        این کانفیگ برای <strong>{detail.customer_name}</strong> است. لینک را از همین‌جا یا میز فروش برایش بفرست.
                      </p>
                    ) : null}
                    {detail.family ? (
                      <p className="mt-2 rounded-lg border border-sky-500/20 bg-sky-500/10 px-2.5 py-1.5 text-[11px] leading-relaxed text-sky-100">
                        {detail.family.is_parent
                          ? "این کانفیگ والد خانواده است. لینک را برای خودت نگه دار و لینک هر فرزند را جدا بفرست."
                          : "این کانفیگ یکی از اعضای خانواده است. همین لینک را برای همان نفر بفرست — بقیه کانفیگ‌ها جدا هستند."}
                      </p>
                    ) : null}
                  </div>
                </div>

                {detail.subscription_url ? (
                  <TgButton
                    className="h-11 w-full text-sm"
                    onClick={() =>
                      void copyText(detail.subscription_url!).then((ok) => {
                        if (!ok) return;
                        flashCopied("sub-url");
                        markCustomerLinkShared();
                      })
                    }
                  >
                    {copied === "sub-url" ? (
                      <span className="inline-flex items-center gap-1.5">
                        <Check className="size-4" />
                        کپی شد
                      </span>
                    ) : (
                      <span className="inline-flex items-center gap-1.5">
                        <Copy className="size-4" />
                        کپی لینک Subscription
                      </span>
                    )}
                  </TgButton>
                ) : bestLink ? (
                  <TgButton
                    className="h-11 w-full text-sm"
                    onClick={() => void copyText(bestLink.link).then((ok) => ok && flashCopied("best-link"))}
                  >
                    {copied === "best-link" ? (
                      <span className="inline-flex items-center gap-1.5">
                        <Check className="size-4" />
                        کپی شد
                      </span>
                    ) : (
                      <span className="inline-flex items-center gap-1.5">
                        <Copy className="size-4" />
                        کپی لینک کانفیگ
                        {bestLink.ping_ms != null ? ` · ${faNum(bestLink.ping_ms)}ms` : ""}
                      </span>
                    )}
                  </TgButton>
                ) : (
                  <p className="text-[11px] text-neutral-500">لینکی برای این کانفیگ موجود نیست.</p>
                )}

                {deepLinks.length > 0 ? (
                  <div className="space-y-2">
                    <p className="text-[11px] font-medium text-neutral-300">باز کردن مستقیم در اپ</p>
                    <div className="grid grid-cols-2 gap-2">
                      {deepLinks.map((client) => (
                        <button
                          key={client.id}
                          type="button"
                          className="inline-flex h-11 flex-col items-center justify-center gap-0.5 rounded-xl border border-sky-500/25 bg-sky-500/10 px-2 text-sky-50 active:bg-sky-500/20"
                          onClick={() => {
                            haptic();
                            const ok = openExternalUrl(client.href);
                            if (ok) markCustomerLinkShared();
                          }}
                        >
                          <span className="inline-flex items-center gap-1 text-[11px] font-semibold">
                            <ExternalLink className="size-3 shrink-0" />
                            {client.label}
                          </span>
                          <span className="text-[9px] font-normal text-sky-200/70">{client.hint}</span>
                        </button>
                      ))}
                    </div>
                    <p className="text-[10px] leading-relaxed text-neutral-500">
                      اگر اپ نصب نباشد، چیزی باز نمی‌شود — اول Hiddify یا v2rayNG را نصب کن، بعد دوباره بزن.
                    </p>
                  </div>
                ) : null}

                <button
                  type="button"
                  className="inline-flex h-10 w-full items-center justify-center gap-1.5 rounded-xl border border-amber-400/25 bg-amber-500/10 text-[12px] font-semibold text-amber-100 active:bg-amber-500/15"
                  onClick={() => {
                    haptic();
                    setDiagnoseOpen(true);
                  }}
                >
                  <WifiOff className="size-3.5" />
                  وصل نمیشه؟ تست و تعمیر
                </button>

                <div className="grid grid-cols-2 gap-2">
                  {detail.subscription_url && bestLink ? (
                    <button
                      type="button"
                      className="inline-flex h-9 items-center justify-center gap-1.5 rounded-lg border border-white/12 bg-black/30 text-[11px] text-neutral-300 active:bg-white/10"
                      onClick={() => void copyText(bestLink.link).then((ok) => ok && flashCopied("best-link"))}
                    >
                      {copied === "best-link" ? <Check className="size-3.5 text-emerald-400" /> : <Copy className="size-3.5" />}
                      بهترین سرور
                    </button>
                  ) : null}
                  <button
                    type="button"
                    className={cn(
                      "inline-flex h-9 items-center justify-center gap-1.5 rounded-lg border border-white/12 bg-black/30 text-[11px] text-neutral-300 active:bg-white/10",
                      !(detail.subscription_url && bestLink) && "col-span-2",
                    )}
                    onClick={() => void copyText(detail.subscription_import).then((ok) => ok && flashCopied("sub-b64"))}
                  >
                    {copied === "sub-b64" ? <Check className="size-3.5 text-emerald-400" /> : <Copy className="size-3.5" />}
                    کپی Base64
                  </button>
                </div>
              </div>

              {linkRotated ? (
                <div className="rounded-xl border border-emerald-500/25 bg-emerald-500/10 px-3 py-2.5 text-[11px] leading-relaxed text-emerald-100">
                  لینک جدید ساخته شد و کپی شد. لینک قبلی دیگر کار نمی‌کند — در اپ Subscription را آپدیت کن.
                </div>
              ) : null}

              {detail.enabled && !detail.expired ? (
                <div className="space-y-2 rounded-xl border border-white/10 bg-black/25 p-3">
                  <div className="flex items-start gap-2">
                    <KeyRound className="mt-0.5 size-4 shrink-0 text-neutral-300" />
                    <div className="min-w-0">
                      <p className="text-[13px] font-semibold text-neutral-100">باطل کردن و لینک جدید</p>
                      <p className="mt-1 text-[11px] leading-relaxed text-neutral-400">
                        اگر لینک لو رفته، لینک فعلی را باطل کن و لینک تازه بگیر. حجم و تاریخ انقضا عوض نمی‌شود.
                      </p>
                    </div>
                  </div>
                  {actionError && tab === "connect" ? (
                    <p className="rounded-lg border border-red-500/25 bg-red-500/10 px-2.5 py-2 text-[11px] text-red-200">
                      {actionError}
                    </p>
                  ) : null}
                  {!confirmRotate ? (
                    <TgButton
                      variant="outline"
                      disabled={busy}
                      className="h-9 text-xs"
                      onClick={() => {
                        haptic();
                        setConfirmRotate(true);
                      }}
                    >
                      <KeyRound className="size-3.5" />
                      لینک جدید
                    </TgButton>
                  ) : (
                    <div className="space-y-2">
                      <p className="text-[11px] text-amber-100/90">لینک فعلی قطع می‌شود. مطمئنی؟</p>
                      <div className="grid grid-cols-2 gap-2">
                        <TgButton
                          variant="outline"
                          disabled={busy}
                          className="h-9 text-xs"
                          onClick={() => setConfirmRotate(false)}
                        >
                          انصراف
                        </TgButton>
                        <TgButton disabled={busy} className="h-9 text-xs" onClick={() => void rotateLink()}>
                          {busy ? "در حال ساخت…" : "تایید و لینک جدید"}
                        </TgButton>
                      </div>
                    </div>
                  )}
                </div>
              ) : null}

              <div className="overflow-hidden rounded-xl border border-white/10 bg-black/25">
                <button
                  type="button"
                  className="flex w-full items-center justify-between gap-2 px-3 py-2.5 text-start active:bg-white/5"
                  onClick={() => setServersOpen((v) => !v)}
                >
                  <span className="inline-flex items-center gap-1.5 text-xs font-semibold text-neutral-200">
                    <Link2 className="size-3.5 text-neutral-400" />
                    لیست سرورها · {faNum(detail.links.length)}
                  </span>
                  <ChevronDown
                    className={cn("size-4 shrink-0 text-neutral-500 transition-transform", serversOpen && "rotate-180")}
                  />
                </button>
                {serversOpen ? (
                  <div className="space-y-1.5 border-t border-white/8 px-3 pb-3 pt-2.5">
                    <button
                      type="button"
                      className="mb-1 w-full rounded-lg border border-white/10 bg-black/30 py-2 text-[11px] text-neutral-300 active:bg-white/8"
                      onClick={() => void copyText(detail.links_text).then((ok) => ok && flashCopied("all-links"))}
                    >
                      {copied === "all-links" ? "همه لینک‌ها کپی شد" : "کپی همه لینک‌ها"}
                    </button>
                    {detail.links.map((item) => (
                      <div
                        key={item.index}
                        className="flex items-center gap-2 rounded-lg border border-white/8 bg-black/20 px-2 py-2"
                      >
                        <span
                          className={cn(
                            "size-2 shrink-0 rounded-full",
                            item.reachable ? "bg-emerald-400" : "bg-neutral-600",
                          )}
                        />
                        <div className="min-w-0 flex-1">
                          <div className="truncate text-xs font-medium text-neutral-200">{item.label}</div>
                          {item.host ? (
                            <div className="truncate font-mono text-[10px] text-neutral-500" dir="ltr">
                              {item.host}:{item.port}
                            </div>
                          ) : null}
                        </div>
                        <span className="shrink-0 text-[10px] tabular-nums text-neutral-500">
                          {item.ping_ms != null ? `${faNum(item.ping_ms)}ms` : "—"}
                        </span>
                        {item.kind === "telegram" && (
                          <button
                            type="button"
                            onClick={() => openTelegramProxy(item.link)}
                            className="shrink-0 rounded-md border border-sky-500/35 bg-sky-500/10 px-2 py-1 text-[10px] text-sky-200 active:bg-sky-500/20"
                          >
                            باز کردن
                          </button>
                        )}
                        <IconCopyBtn
                          active={copied === `link-${item.index}`}
                          onClick={() => void copyText(item.link).then((ok) => ok && flashCopied(`link-${item.index}`))}
                        />
                      </div>
                    ))}
                  </div>
                ) : null}
              </div>
            </div>
          ) : null}

          {/* USAGE */}
          {tab === "usage" ? (
            <div className="space-y-3">
              {detail.family ? (
                <div className="space-y-2 rounded-xl border border-sky-500/20 bg-sky-500/[0.06] p-3">
                  <p className="text-xs font-semibold text-sky-100">مصرف اعضای خانواده</p>
                  {detail.family.used_label ? (
                    <p className="text-[11px] text-neutral-400">
                      جمع پکیج: <span className="tabular-nums text-neutral-200">{detail.family.used_label}</span>
                    </p>
                  ) : null}
                  <div className="space-y-1.5">
                    {detail.family.members.map((m) => (
                      <div
                        key={m.id}
                        className="flex items-center justify-between gap-2 rounded-lg border border-white/8 bg-black/25 px-2.5 py-2"
                      >
                        <div className="min-w-0">
                          <div className="truncate text-[12px] font-medium text-neutral-100">
                            {m.label || m.email}
                          </div>
                          <div className="text-[10px] text-neutral-500">{m.is_parent ? "والد" : "فرزند"}</div>
                        </div>
                        <div className="shrink-0 text-end">
                          <div className="text-[12px] font-semibold tabular-nums text-neutral-100">
                            {m.used_label || "۰"}
                          </div>
                          <div className="text-[10px] text-neutral-500">
                            {m.online ? "آنلاین" : m.total_label || "نامحدود"}
                          </div>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              ) : null}
              {detail.usage ? (
                <div className="space-y-2.5 rounded-xl border border-white/10 bg-black/25 p-3">
                  <p className="text-xs font-semibold text-neutral-200">تحلیل مصرف</p>
                  <div className="grid grid-cols-2 gap-2">
                    <StatTile label="امروز" value={detail.usage.today_label} />
                    <StatTile label="۷ روز" value={detail.usage.week_label} />
                    <StatTile label="میانگین روزانه" value={detail.usage.avg_daily_label} />
                    <StatTile label="آپلود / دانلود" value={`${detail.up_label || "۰"} / ${detail.down_label || "۰"}`} />
                  </div>
                  {detail.usage.last_seen_label ? (
                    <p className="text-[11px] text-neutral-400">آخرین فعالیت: {detail.usage.last_seen_label}</p>
                  ) : null}
                  {detail.usage.days_left != null ? (
                    <p className="text-[11px] text-neutral-400">
                      با همین روند حدود {faNum(detail.usage.days_left)} روز حجم می‌ماند
                    </p>
                  ) : null}
                  {detail.usage.daily.length > 0 ? (
                    <div className="flex h-16 items-end gap-1 pt-1">
                      {(() => {
                        const max = Math.max(1, ...detail.usage.daily.map((d) => d.used_bytes));
                        return detail.usage.daily.map((d) => (
                          <div key={d.day} className="flex min-w-0 flex-1 flex-col items-center gap-1">
                            <div
                              className="w-full rounded-sm bg-sky-300/80"
                              style={{ height: `${Math.max(6, (d.used_bytes / max) * 100)}%` }}
                              title={d.used_label}
                            />
                            <div className="text-[9px] tabular-nums text-neutral-500">{d.label}</div>
                          </div>
                        ));
                      })()}
                    </div>
                  ) : null}
                </div>
              ) : (
                <div className="rounded-xl border border-white/10 bg-black/25 px-3 py-4 text-center text-[11px] text-neutral-500">
                  هنوز آمار مصرفی ثبت نشده است.
                </div>
              )}

              <div className="space-y-2 rounded-xl border border-white/10 bg-black/25 p-3">
                <p className="text-xs font-semibold text-neutral-200">دستگاه‌های متصل</p>
                <div className="flex items-center justify-between gap-2 rounded-lg border border-white/8 bg-black/20 px-2.5 py-2">
                  <span className="inline-flex items-center gap-1.5 text-[11px] text-neutral-400">
                    {detail.connection.online ? (
                      <Wifi className="size-3.5 text-emerald-400" />
                    ) : (
                      <WifiOff className="size-3.5 text-neutral-500" />
                    )}
                    {detail.connection.online ? "هم‌اکنون متصل" : "قطع"}
                  </span>
                  {detail.connection.ip_available ? (
                    <span className="text-[10px] tabular-nums text-neutral-400">
                      IP: {ipLimitLabel(detail.connection.connected_ip_count, detail.connection.limit_ip)}
                    </span>
                  ) : null}
                </div>
                {detail.connection.connected_ips.length > 0 ? (
                  <div className="space-y-1.5">
                    <div className="text-[10px] text-neutral-500">با نام دستگاه برچسب بزنید</div>
                    {detail.connection.connected_ips.map((row) => (
                      <div key={row.ip} className="space-y-1 rounded-lg border border-white/8 bg-black/20 px-2.5 py-2">
                        <div className="flex items-center justify-between gap-2">
                          <span className="font-mono text-[11px] text-neutral-200" dir="ltr">
                            {row.ip}
                          </span>
                          {row.at ? <span className="shrink-0 text-[10px] text-neutral-500">{row.at}</span> : null}
                        </div>
                        <div className="flex flex-wrap gap-1">
                          {(detail.connection.nickname_presets || ["موبایل", "لپ‌تاپ", "تبلت", "کامپیوتر"]).map(
                            (preset) => {
                              const active = row.nickname === preset;
                              return (
                                <button
                                  key={preset}
                                  type="button"
                                  className={cn(
                                    "rounded-md border px-1.5 py-0.5 text-[10px]",
                                    active
                                      ? "border-emerald-500/40 bg-emerald-500/15 text-emerald-200"
                                      : "border-white/10 bg-black/30 text-neutral-400",
                                  )}
                                  onClick={() => {
                                    void (async () => {
                                      try {
                                        const nick = active ? "" : preset;
                                        await api.setIpNickname(detail.id, row.ip, nick);
                                        setDetail((prev) => {
                                          if (!prev) return prev;
                                          return {
                                            ...prev,
                                            connection: {
                                              ...prev.connection,
                                              connected_ips: prev.connection.connected_ips.map((ip) =>
                                                ip.ip === row.ip ? { ...ip, nickname: nick || null } : ip,
                                              ),
                                            },
                                          };
                                        });
                                        haptic();
                                      } catch {
                                        /* ignore */
                                      }
                                    })();
                                  }}
                                >
                                  {preset}
                                </button>
                              );
                            },
                          )}
                        </div>
                      </div>
                    ))}
                  </div>
                ) : detail.connection.online ? (
                  <p className="text-[10px] text-neutral-500">IP هنوز ثبت نشده — چند ثانیه بعد بروزرسانی کنید.</p>
                ) : (
                  <p className="text-[10px] text-neutral-500">دستگاهی آنلاین نیست.</p>
                )}
                {detail.connection.last_online_at ? (
                  <p className="text-[11px] text-neutral-500">آخرین اتصال: {formatDate(detail.connection.last_online_at)}</p>
                ) : null}
              </div>
            </div>
          ) : null}

          {/* RENEW */}
          {tab === "renew" ? (
            <div className="space-y-3">
              {detail.is_payg ? (
                <div className="space-y-3 rounded-xl border border-sky-500/15 bg-black/25 p-3">
                  <p className="inline-flex items-center gap-1.5 text-xs font-semibold text-neutral-200">
                    <CalendarClock className="size-3.5 text-sky-300/80" />
                    {detail.is_metered ? "مصرف ابری" : "شارژ ترافیک"}
                  </p>
                  {detail.is_metered ? (
                    <div className="space-y-2">
                      <div className="grid grid-cols-2 gap-2">
                        <StatTile label="مصرف شده" value={detail.used_label} />
                        <StatTile label="مانده از کیف‌پول" value={detail.remaining_label} />
                        <StatTile label="کسر شده" value={detail.billed_label || "۰ تومان"} />
                        <StatTile label="وضعیت" value={detail.enabled ? "فعال" : "قطع‌شده"} />
                      </div>
                      <p className="text-[11px] leading-relaxed text-neutral-400">
                        فقط حجم واقعی از کیف‌پول کسر می‌شود. اگر موجودی تمام شود کانفیگ قطع می‌شود.
                      </p>
                      <div className="grid grid-cols-2 gap-2">
                        {detail.enabled ? (
                          <TgButton
                            variant="outline"
                            disabled={busy}
                            className="border-red-500/25 text-red-300"
                            onClick={() => {
                              void (async () => {
                                setBusy(true);
                                try {
                                  await api.paygSetEnabled(false);
                                  setDetail((prev) => (prev ? { ...prev, enabled: false, online: false } : prev));
                                  haptic();
                                } catch {
                                  /* ignore */
                                } finally {
                                  setBusy(false);
                                }
                              })();
                            }}
                          >
                            غیرفعال کردن
                          </TgButton>
                        ) : (
                          <TgButton
                            disabled={busy}
                            onClick={() => {
                              void (async () => {
                                setBusy(true);
                                try {
                                  await api.paygSetEnabled(true);
                                  setDetail((prev) => (prev ? { ...prev, enabled: true } : prev));
                                  haptic();
                                } catch {
                                  /* ignore */
                                } finally {
                                  setBusy(false);
                                }
                              })();
                            }}
                          >
                            فعال کردن
                          </TgButton>
                        )}
                        <TgButton
                          variant="outline"
                          disabled={busy}
                          onClick={() => {
                            onClose();
                            onTopup?.();
                          }}
                        >
                          شارژ کیف‌پول
                        </TgButton>
                      </div>
                    </div>
                  ) : (
                    <PaygTrafficBuilder
                      busy={busy}
                      lockTargetId={detail.id}
                      submitLabel="شارژ ترافیک و پرداخت"
                      onCheckout={async (order) => {
                        await onRenewCheckout(order);
                        onClose();
                      }}
                    />
                  )}
                </div>
              ) : (
                <div className="space-y-3 rounded-xl border border-amber-500/15 bg-black/25 p-3">
                  <p className="inline-flex items-center gap-1.5 text-xs font-semibold text-neutral-200">
                    <CalendarClock className="size-3.5 text-amber-300/80" />
                    تمدید اشتراک
                  </p>
                  <label className="flex items-center justify-between gap-3 rounded-lg border border-white/10 bg-black/25 px-3 py-2.5">
                    <div className="min-w-0">
                      <div className="text-xs font-medium text-neutral-100">تمدید خودکار از کیف‌پول</div>
                      <p className="mt-0.5 text-[10px] leading-relaxed text-neutral-500">
                        نزدیک انقضا، اگر موجودی کافی باشد خودش تمدید می‌شود.
                      </p>
                    </div>
                    <input
                      type="checkbox"
                      className="size-4 shrink-0 accent-amber-400"
                      checked={Boolean(detail.auto_renew)}
                      disabled={busy}
                      onChange={(e) => {
                        const enabled = e.target.checked;
                        void (async () => {
                          try {
                            const res = await api.setAutoRenew(detail.id, enabled);
                            setDetail((prev) => (prev ? { ...prev, auto_renew: res.auto_renew } : prev));
                            setCopied(enabled ? "auto-on" : "auto-off");
                            window.setTimeout(() => setCopied(null), 1500);
                            haptic();
                          } catch {
                            /* ignore */
                          }
                        })();
                      }}
                    />
                  </label>
                  {(copied === "auto-on" || copied === "auto-off") && (
                    <p className="text-[10px] text-emerald-300">
                      {copied === "auto-on" ? "تمدید خودکار روشن شد" : "تمدید خودکار خاموش شد"}
                    </p>
                  )}
                  <div className="grid grid-cols-2 gap-2">
                    <button
                      type="button"
                      onClick={() => setRenewCustom(false)}
                      className={cn(
                        "h-8 rounded-lg border text-[11px] font-medium",
                        !renewCustom
                          ? "border-white/25 bg-white/10 text-white"
                          : "border-white/10 bg-black/30 text-neutral-400",
                      )}
                    >
                      پکیج آماده
                    </button>
                    <button
                      type="button"
                      onClick={() => setRenewCustom(true)}
                      className={cn(
                        "h-8 rounded-lg border text-[11px] font-medium",
                        renewCustom
                          ? "border-amber-500/30 bg-amber-500/10 text-amber-200"
                          : "border-white/10 bg-black/30 text-neutral-400",
                      )}
                    >
                      ساخت پکیج
                    </button>
                  </div>
                  {!renewCustom ? (
                    <>
                      <select
                        value={renewPlanId ?? ""}
                        onChange={(e) => setRenewPlanId(Number(e.target.value))}
                        className="w-full rounded-lg border border-white/12 bg-black/40 px-3 py-2.5 text-sm text-white outline-none focus:border-white/25"
                      >
                        {plans.map((p) => (
                          <option key={p.id} value={p.id}>
                            {p.title} — {p.price_label || faNum(p.price_toman)}
                          </option>
                        ))}
                      </select>
                      <TgButton disabled={busy || !renewPlanId} className="h-10 text-sm" onClick={() => void startRenew()}>
                        تمدید و پرداخت
                      </TgButton>
                    </>
                  ) : (
                    <CustomPackageBuilder
                      busy={busy}
                      targetSubscriptionId={detail.id}
                      onCheckout={async (order) => {
                        await onRenewCheckout(order);
                        onClose();
                      }}
                    />
                  )}
                </div>
              )}
            </div>
          ) : null}

          {/* MORE */}
          {tab === "more" ? (
            <div className="space-y-2.5">
              <div className="rounded-xl border border-white/10 bg-black/25 p-3">
                <p className="mb-2 inline-flex items-center gap-1.5 text-xs font-semibold text-neutral-200">
                  <Info className="size-3.5 text-neutral-400" />
                  مشخصات
                </p>
                <div className="space-y-1 text-[12px]">
                  <div className="flex justify-between gap-3 py-1">
                    <span className="text-neutral-500">ایمیل</span>
                    <span className="truncate font-mono text-[11px] text-neutral-100" dir="ltr">
                      {detail.email}
                    </span>
                  </div>
                  <div className="flex justify-between gap-3 py-1">
                    <span className="text-neutral-500">شروع</span>
                    <span className="text-neutral-100">{formatDate(detail.created_at)}</span>
                  </div>
                  <div className="flex justify-between gap-3 py-1">
                    <span className="text-neutral-500">پایان</span>
                    <span className="text-neutral-100">{formatDate(detail.expires_at)}</span>
                  </div>
                  <div className="flex justify-between gap-3 py-1">
                    <span className="text-neutral-500">حجم باقی‌مانده</span>
                    <span className="text-neutral-100">{detail.remaining_label}</span>
                  </div>
                  {detail.source_label ? (
                    <div className="flex justify-between gap-3 py-1">
                      <span className="text-neutral-500">وضعیت خرید</span>
                      <span className="text-neutral-100">
                        {detail.source_label}
                        {detail.order_status_label ? ` · ${detail.order_status_label}` : ""}
                      </span>
                    </div>
                  ) : null}
                  {detail.order_amount_label ? (
                    <div className="flex justify-between gap-3 py-1">
                      <span className="text-neutral-500">مبلغ سفارش</span>
                      <span className="text-neutral-100">
                        {detail.order_amount_label}
                        {detail.order_id ? ` · #${faNum(detail.order_id)}` : ""}
                      </span>
                    </div>
                  ) : null}
                  {detail.renew_status_label ? (
                    <div className="flex justify-between gap-3 py-1">
                      <span className="text-neutral-500">آخرین تمدید</span>
                      <span className="text-neutral-100">
                        {detail.renew_status_label}
                        {detail.renew_amount_label ? ` · ${detail.renew_amount_label}` : ""}
                      </span>
                    </div>
                  ) : null}
                </div>
              </div>

              <Section title="نام کانفیگ" icon={<Tag className="size-3.5 text-neutral-400" />} defaultOpen={!detail.label?.trim()}>
                <input
                  value={labelDraft}
                  onChange={(e) => setLabelDraft(e.target.value)}
                  maxLength={64}
                  className="w-full rounded-lg border border-white/12 bg-black/40 px-3 py-2.5 text-sm text-white outline-none placeholder:text-neutral-500 focus:border-white/25"
                  placeholder="مثلاً موبایل، لپ‌تاپ…"
                />
                <TgButton variant="outline" disabled={busy} className="h-9 text-xs" onClick={() => void saveLabel()}>
                  {busy ? "در حال ذخیره…" : "ذخیره نام"}
                </TgButton>
              </Section>

              <Section
                title="گیرنده این کانفیگ"
                icon={<Users className="size-3.5 text-teal-300/80" />}
                defaultOpen={Boolean(
                  detail.customer_name || detail.customer_phone || detail.customer_email || detail.customer_telegram_id,
                )}
              >
                <p className="text-[11px] leading-relaxed text-neutral-400">
                  اگر این کانفیگ را برای کس دیگری خریدی، اسمش اینجاست. لینک اتصال را از تب «اتصال» کپی کن و برای همان نفر بفرست — کانفیگ روی حساب تو می‌ماند.
                </p>
                {(
                  [
                    ["customer_name", "نام", "علی رضایی"],
                    ["customer_email", "ایمیل", "customer@email.com"],
                    ["customer_phone", "موبایل", "0912…"],
                    ["customer_telegram_id", "تلگرام", "@username"],
                  ] as const
                ).map(([key, label, ph]) => (
                  <label key={key} className="block space-y-1">
                    <span className="text-[10px] text-neutral-500">{label}</span>
                    <input
                      value={customerDraft[key]}
                      onChange={(e) => setCustomerDraft((d) => ({ ...d, [key]: e.target.value }))}
                      dir={key === "customer_name" ? undefined : "ltr"}
                      className="w-full rounded-lg border border-white/12 bg-black/40 px-3 py-2 text-sm text-white outline-none placeholder:text-neutral-600 focus:border-white/25"
                      placeholder={ph}
                    />
                  </label>
                ))}
                <TgButton variant="outline" disabled={busy} className="h-9 text-xs" onClick={() => void saveCustomer()}>
                  {busy ? "در حال ذخیره…" : "ذخیره اطلاعات مشتری"}
                </TgButton>
              </Section>

              {detail.family && detail.family.parental?.enabled ? (
                <FamilyParentalSection detail={detail} onDetailChange={setDetail} />
              ) : null}

              <Section
                title="انتقال مالکیت"
                icon={<ArrowRightLeft className="size-3.5 text-sky-300/80" />}
              >
                <p className="text-[11px] leading-relaxed text-neutral-400">
                  کانفیگ از حساب تو خارج می‌شود و به حساب مقصد می‌رود. لینک اتصال همان می‌ماند؛ تمدید خودکار خاموش می‌شود.
                </p>
                {detail.family?.is_parent ? (
                  <p className="rounded-lg border border-sky-500/20 bg-sky-500/10 px-2.5 py-1.5 text-[11px] leading-relaxed text-sky-100">
                    این کانفیگ والد خانواده است. همه {faNum(detail.family.members.length)} کانفیگ پکیج با هم منتقل می‌شوند.
                  </p>
                ) : detail.family ? (
                  <p className="rounded-lg border border-amber-400/20 bg-amber-500/10 px-2.5 py-1.5 text-[11px] leading-relaxed text-amber-100">
                    این صندلی از خانواده جدا می‌شود و فقط همین کانفیگ منتقل می‌گردد.
                  </p>
                ) : null}
                {detail.is_payg || detail.is_metered ? (
                  <p className="rounded-lg border border-white/10 bg-black/30 px-2.5 py-1.5 text-[11px] leading-relaxed text-neutral-400">
                    مصرفی از کیف‌پول صاحب جدید کسر می‌شود.
                  </p>
                ) : null}
                <label className="block space-y-1">
                  <span className="text-[10px] text-neutral-500">آیدی تلگرام یا یوزرنیم</span>
                  <input
                    value={transferTarget}
                    onChange={(e) => {
                      setTransferTarget(e.target.value);
                      setTransferPreview(null);
                      setConfirmTransfer(false);
                    }}
                    dir="ltr"
                    className="w-full rounded-lg border border-white/12 bg-black/40 px-3 py-2 text-sm text-white outline-none placeholder:text-neutral-600 focus:border-white/25"
                    placeholder="@username یا 123456789"
                    autoComplete="off"
                  />
                </label>
                <p className="text-[10px] leading-relaxed text-neutral-500">
                  مقصد باید حداقل یک‌بار فروشگاه را از داخل ربات باز کرده باشد.
                </p>
                {actionError && tab === "more" && !confirmRevoke ? (
                  <p className="rounded-lg border border-red-500/25 bg-red-500/10 px-2.5 py-2 text-[11px] text-red-200">
                    {actionError}
                  </p>
                ) : null}
                {transferPreview ? (
                  <div className="rounded-lg border border-white/10 bg-black/30 px-3 py-2.5">
                    <div className="text-[10px] text-neutral-500">انتقال به</div>
                    <div className="mt-0.5 text-[13px] font-semibold text-neutral-100">
                      {transferPreview.full_name?.trim() || "کاربر"}
                    </div>
                    <div className="mt-0.5 font-mono text-[11px] text-neutral-400" dir="ltr">
                      {transferPreview.username ? `@${transferPreview.username}` : ""}
                      {transferPreview.username ? " · " : ""}
                      {transferPreview.telegram_id}
                    </div>
                  </div>
                ) : null}
                {!transferPreview ? (
                  <TgButton variant="outline" disabled={busy || !transferTarget.trim()} className="h-9 text-xs" onClick={() => void lookupTransfer()}>
                    {busy ? "در حال بررسی…" : "بررسی حساب مقصد"}
                  </TgButton>
                ) : !confirmTransfer ? (
                  <div className="grid grid-cols-2 gap-2">
                    <TgButton
                      variant="outline"
                      disabled={busy}
                      className="h-9 text-xs"
                      onClick={() => {
                        setTransferPreview(null);
                        setConfirmTransfer(false);
                      }}
                    >
                      عوض کردن
                    </TgButton>
                    <TgButton
                      disabled={busy}
                      className="h-9 text-xs"
                      onClick={() => {
                        haptic();
                        setConfirmTransfer(true);
                      }}
                    >
                      ادامه انتقال
                    </TgButton>
                  </div>
                ) : (
                  <div className="space-y-2">
                    <p className="text-[11px] text-amber-100/90">
                      بعد از تایید، این کانفیگ از داشبورد تو حذف می‌شود. مطمئنی؟
                    </p>
                    <div className="grid grid-cols-2 gap-2">
                      <TgButton variant="outline" disabled={busy} className="h-9 text-xs" onClick={() => setConfirmTransfer(false)}>
                        انصراف
                      </TgButton>
                      <TgButton disabled={busy} className="h-9 text-xs" onClick={() => void transferOwnership()}>
                        {busy ? "در حال انتقال…" : "تایید انتقال"}
                      </TgButton>
                    </div>
                  </div>
                )}
              </Section>

              <Section
                title="غیرفعال‌سازی"
                icon={<ShieldOff className="size-3.5 text-red-300/80" />}
                className="border-red-500/15"
              >
                {!confirmRevoke ? (
                  <>
                    <p className="text-[11px] leading-relaxed text-neutral-500">
                      کل کانفیگ قطع می‌شود. برای فقط عوض کردن لینک، از تب اتصال «لینک جدید» را بزن.
                    </p>
                    {actionError && tab === "more" && confirmRevoke ? (
                      <p className="rounded-lg border border-red-500/25 bg-red-500/10 px-2.5 py-2 text-[11px] text-red-200">
                        {actionError}
                      </p>
                    ) : null}
                    <TgButton
                      variant="outline"
                      className="h-9 border-red-500/30 text-xs text-red-300"
                      onClick={() => setConfirmRevoke(true)}
                    >
                      غیرفعال کردن
                    </TgButton>
                  </>
                ) : (
                  <div className="space-y-2">
                    <p className="text-[11px] text-red-200/90">مطمئن هستید؟</p>
                    <div className="grid grid-cols-2 gap-2">
                      <TgButton variant="outline" disabled={busy} className="h-9 text-xs" onClick={() => setConfirmRevoke(false)}>
                        انصراف
                      </TgButton>
                      <TgButton disabled={busy} className="h-9 bg-red-600 text-xs hover:bg-red-500" onClick={() => void revoke()}>
                        تایید
                      </TgButton>
                    </div>
                  </div>
                )}
              </Section>

              <button
                type="button"
                disabled={loading}
                onClick={() => void load()}
                className="flex w-full items-center justify-center gap-1.5 py-2 text-[11px] text-neutral-500 active:text-neutral-300"
              >
                <RefreshCw className="size-3.5" />
                بروزرسانی اطلاعات
              </button>
            </div>
          ) : null}
        </div>
      )}
    </TgSheet>
      <SelfFixSheet
        open={diagnoseOpen}
        onClose={() => setDiagnoseOpen(false)}
        subId={subId}
        onRenew={() => setTab("renew")}
        onRotated={(url) => {
          setLinkRotated(true);
          onLinkRotated?.(subId!, url);
          void load();
        }}
      />
    </>
  );
}
