import { useEffect, useState, type ReactNode } from "react";
import { ChevronDown, Copy, Gift, MessageCircle, Plus, Shield, Star, Trash2, Wallet } from "lucide-react";
import {
  api,
  haptic,
  type AdminGiftPlan,
  type AdminUserDetail,
  type AdminUserSubscription,
  type TrialGrantResult,
} from "@/api";
import { TgButton } from "@/components/tg-button";
import { TgSheet } from "@/components/tg-sheet";
import { Input } from "@/components/ui/input";
import { cn, faNum } from "@/lib/utils";

function priceText(toman: number) {
  return `${faNum(toman)} تومان`;
}

function statusFa(status: string) {
  if (status === "online") return "آنلاین";
  if (status === "expired") return "منقضی";
  if (status === "disabled") return "غیرفعال";
  if (status === "pending") return "در انتظار";
  if (status === "approved" || status === "paid") return "تایید شده";
  if (status === "rejected") return "رد شده";
  if (status === "cancelled") return "لغو";
  return "آفلاین";
}

function formatDate(iso: string | null | undefined) {
  if (!iso) return "—";
  try {
    return new Intl.DateTimeFormat("fa-IR", { dateStyle: "medium" }).format(new Date(iso));
  } catch {
    return "—";
  }
}

function statusChipClass(status: string) {
  if (status === "online") return "border-emerald-500/30 bg-emerald-500/15 text-emerald-200";
  if (status === "expired") return "border-red-500/30 bg-red-500/15 text-red-200";
  if (status === "disabled") return "border-neutral-500/30 bg-neutral-500/15 text-neutral-300";
  if (status === "pending") return "border-amber-400/30 bg-amber-500/10 text-amber-200";
  if (status === "approved" || status === "paid") return "border-sky-500/25 bg-sky-500/10 text-sky-100";
  if (status === "rejected" || status === "cancelled") return "border-red-500/30 bg-red-500/10 text-red-200";
  return "border-white/10 bg-white/5 text-neutral-300";
}

function DetailRow({ label, value }: { label: string; value: ReactNode }) {
  return (
    <div className="flex items-start justify-between gap-3 py-1">
      <span className="shrink-0 text-neutral-500">{label}</span>
      <span className="min-w-0 text-end text-neutral-100">{value}</span>
    </div>
  );
}

export function AdminUserSheet({
  open,
  onClose,
  userId,
  busy,
  onOpenChat,
  onSetRole,
  onGrantTrial,
  onOpenSubscription,
  onNotify,
}: {
  open: boolean;
  onClose: () => void;
  userId: number | null;
  busy?: boolean;
  onOpenChat: (userId: number) => void;
  onOpenSubscription?: (subId: number) => void;
  onSetRole: (userId: number, role: "user" | "admin") => Promise<unknown>;
  onGrantTrial?: (opts: {
    targets_text?: string;
    all_users?: boolean;
    skip_existing_trial?: boolean;
    notify_users?: boolean;
  }) => Promise<TrialGrantResult>;
  onNotify: (message: string, kind?: "success" | "error" | "info") => void;
}) {
  const [detail, setDetail] = useState<AdminUserDetail | null>(null);
  const [loading, setLoading] = useState(false);
  const [walletAmount, setWalletAmount] = useState("");
  const [creditLimit, setCreditLimit] = useState("");
  const [convertTopup, setConvertTopup] = useState("");
  const [acting, setActing] = useState(false);
  const [giftPlans, setGiftPlans] = useState<AdminGiftPlan[]>([]);
  const [selectedPlanId, setSelectedPlanId] = useState<number | "">("");
  const [proDays, setProDays] = useState("");
  const [openSubId, setOpenSubId] = useState<number | null>(null);

  useEffect(() => {
    if (!open || !userId) {
      setDetail(null);
      setWalletAmount("");
      setCreditLimit("");
      setConvertTopup("");
      setSelectedPlanId("");
      setProDays("");
      setOpenSubId(null);
      return;
    }
    let cancelled = false;
    setLoading(true);
    void Promise.all([api.adminUserDetail(userId), api.adminGiftPlans()])
      .then(([data, plans]) => {
        if (cancelled) return;
        setDetail(data);
        setCreditLimit(String(data.wallet_credit_limit || 0));
        setGiftPlans(plans.items);
        if (plans.items.length && selectedPlanId === "") {
          setSelectedPlanId(plans.items[0]!.id);
        }
      })
      .catch((e) => {
        if (!cancelled) onNotify(e instanceof Error ? e.message : "بارگذاری ناموفق", "error");
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [open, userId]); // eslint-disable-line react-hooks/exhaustive-deps

  const run = async (fn: () => Promise<AdminUserDetail>) => {
    setActing(true);
    try {
      const next = await fn();
      setDetail(next);
    } catch (e) {
      onNotify(e instanceof Error ? e.message : "عملیات ناموفق", "error");
    } finally {
      setActing(false);
    }
  };

  const adjustWallet = async (sign: 1 | -1) => {
    if (!detail) return;
    const amount = Number(walletAmount.replace(/\D/g, ""));
    if (!amount) {
      onNotify("مبلغ را وارد کنید", "error");
      return;
    }
    await run(async () => {
      const res = await api.adminAdjustWallet(detail.id, sign * amount);
      setWalletAmount("");
      onNotify(sign > 0 ? "کیف‌پول شارژ شد" : "از کیف‌پول کسر شد", "success");
      return res.user;
    });
  };

  const title = detail?.full_name || (detail?.username ? `@${detail.username}` : "کاربر");

  return (
    <TgSheet open={open} onClose={onClose} title={title} description={detail ? String(detail.telegram_id) : "پرونده کاربر"}>
      {loading && <p className="py-8 text-center text-sm text-neutral-400">در حال بارگذاری پرونده…</p>}
      {!loading && detail && (
        <div className="space-y-4">
          <div className="rounded-2xl border border-white/10 bg-black/30 p-3">
            <div className="flex items-start justify-between gap-2">
              <div className="min-w-0">
                <div className="truncate text-sm font-semibold">{title}</div>
                <div className="mt-0.5 font-mono text-[11px] text-neutral-500" dir="ltr">
                  {detail.username ? `@${detail.username} · ` : ""}
                  {detail.telegram_id}
                </div>
              </div>
              <button
                type="button"
                className="inline-flex size-9 items-center justify-center rounded-xl border border-white/12 text-neutral-400 active:bg-white/10"
                onClick={() => {
                  void navigator.clipboard?.writeText(String(detail.telegram_id));
                  haptic();
                  onNotify("آیدی کپی شد", "success");
                }}
                aria-label="کپی آیدی"
              >
                <Copy className="size-3.5" />
              </button>
            </div>
            <div className="mt-2 flex flex-wrap gap-1">
              <Chip tone={detail.is_admin ? "amber" : "muted"}>
                {detail.is_super_admin ? "ادمین اصلی" : detail.is_admin ? "ادمین" : "کاربر"}
              </Chip>
              {detail.is_pro ? <Chip tone="amber">Pro</Chip> : null}
              {detail.trial_granted ? <Chip>تست گرفته</Chip> : null}
              {detail.is_test ? <Chip tone="amber">کاربر تست</Chip> : null}
              {(detail.chat_unread || 0) > 0 ? <Chip tone="orange">{faNum(detail.chat_unread!)} پیام</Chip> : null}
              {(detail.pending_order_count || 0) > 0 ? (
                <Chip tone="orange">{faNum(detail.pending_order_count!)} سفارش باز</Chip>
              ) : null}
            </div>
            {detail.pro_until ? (
              <p className="mt-2 text-[10px] text-neutral-500">
                Pro تا {new Date(detail.pro_until).toLocaleDateString("fa-IR")}
              </p>
            ) : null}
          </div>

          <section className="space-y-2">
            <div className="flex items-center gap-1.5 text-xs font-semibold text-neutral-400">
              <Wallet className="size-3.5" />
              کیف‌پول · {detail.wallet_label || priceText(detail.wallet_balance)}
            </div>
            {(detail.wallet_debt || 0) > 0 ? (
              <p className="rounded-xl border border-rose-500/25 bg-rose-500/10 px-2.5 py-1.5 text-[11px] text-rose-100">
                بدهی: {detail.wallet_debt_label || priceText(detail.wallet_debt || 0)}
                {(detail.wallet_credit_limit || 0) > 0
                  ? ` · سقف اعتبار ${detail.wallet_credit_limit_label || priceText(detail.wallet_credit_limit || 0)}`
                  : ""}
              </p>
            ) : (detail.wallet_credit_limit || 0) > 0 ? (
              <p className="rounded-xl border border-sky-500/20 bg-sky-500/10 px-2.5 py-1.5 text-[11px] text-sky-100">
                اعتبار خرید تا {detail.wallet_credit_limit_label || priceText(detail.wallet_credit_limit || 0)}
              </p>
            ) : null}
            <div className="flex gap-2">
              <Input
                value={walletAmount}
                onChange={(e) => setWalletAmount(e.target.value.replace(/\D/g, ""))}
                placeholder="مبلغ (تومان)"
                dir="ltr"
                inputMode="numeric"
                className="h-10 flex-1 rounded-xl border-white/15 bg-black/40"
              />
              <TgButton
                className="h-10 w-auto shrink-0 px-3 text-xs"
                disabled={acting || busy}
                onClick={() => void adjustWallet(1)}
              >
                شارژ
              </TgButton>
              <TgButton
                variant="outline"
                className="h-10 w-auto shrink-0 px-3 text-xs"
                disabled={acting || busy}
                onClick={() => void adjustWallet(-1)}
              >
                کسر / بدهکار
              </TgButton>
            </div>
            <p className="text-[10px] leading-relaxed text-neutral-500">
              کسر ادمین می‌تواند موجودی را منفی کند؛ در این حالت سقف اعتبار خودکار تا حد بدهی بالا می‌رود.
            </p>
            <div className="rounded-xl border border-amber-500/20 bg-amber-500/5 px-2.5 py-2.5 space-y-2">
              <div className="text-[11px] font-semibold text-amber-100">تبدیل شارژ قبلی به نسیه</div>
              <p className="text-[10px] leading-relaxed text-neutral-500">
                اگر قبلاً مثلاً ۱٬۰۰۰٬۰۰۰ شارژ کردی و بخشی مصرف شده: مبلغ همان شارژ اولیه را بزن. باقیمانده هدیه حذف
                می‌شود و مبلغ مصرف‌شده به بدهی تبدیل می‌شود تا بعداً با شارژ کیف‌پول بپردازد.
              </p>
              <div className="flex gap-2">
                <Input
                  value={convertTopup}
                  onChange={(e) => setConvertTopup(e.target.value.replace(/\D/g, ""))}
                  placeholder="مبلغ شارژ اولیه"
                  dir="ltr"
                  inputMode="numeric"
                  className="h-10 flex-1 rounded-xl border-white/15 bg-black/40"
                />
                <TgButton
                  variant="outline"
                  className="h-10 w-auto shrink-0 px-3 text-xs"
                  disabled={acting || busy || !convertTopup}
                  onClick={() => {
                    const amount = Number(convertTopup.replace(/\D/g, "") || 0);
                    if (!amount) {
                      onNotify("مبلغ شارژ اولیه را وارد کنید", "error");
                      return;
                    }
                    void run(async () => {
                      const res = await api.adminConvertWalletToCredit(detail.id, amount);
                      setConvertTopup("");
                      setCreditLimit(String(res.user.wallet_credit_limit || 0));
                      const debt = res.user.wallet_debt || 0;
                      onNotify(
                        debt > 0 ? `تبدیل شد — بدهی ${priceText(debt)}` : "تبدیل شد",
                        "success",
                      );
                      return res.user;
                    });
                  }}
                >
                  تبدیل به نسیه
                </TgButton>
              </div>
            </div>
            <div className="rounded-xl border border-white/10 bg-black/30 px-2.5 py-2.5 space-y-2">
              <div className="text-[11px] font-semibold text-neutral-200">سقف اعتبار خرید (نسیه)</div>
              <p className="text-[10px] leading-relaxed text-neutral-500">
                اگر بیشتر از موجودی بخرد، کیف‌پول منفی می‌شود تا همین سقف. با شارژ کیف‌پول بدهی کم می‌شود.
              </p>
              <div className="flex flex-wrap gap-1.5">
                {[0, 100_000, 200_000, 500_000, 1_000_000].map((p) => (
                  <button
                    key={p}
                    type="button"
                    onClick={() => setCreditLimit(String(p))}
                    className={cn(
                      "h-7 rounded-full border px-2.5 text-[10px]",
                      Number(creditLimit) === p
                        ? "border-sky-400/40 bg-sky-500/15 text-sky-100"
                        : "border-white/12 bg-black/40 text-neutral-400",
                    )}
                  >
                    {p === 0 ? "بدون اعتبار" : priceText(p)}
                  </button>
                ))}
              </div>
              <div className="flex gap-2">
                <Input
                  value={creditLimit}
                  onChange={(e) => setCreditLimit(e.target.value.replace(/\D/g, ""))}
                  placeholder="سقف اعتبار"
                  dir="ltr"
                  inputMode="numeric"
                  className="h-10 flex-1 rounded-xl border-white/15 bg-black/40"
                />
                <TgButton
                  variant="outline"
                  className="h-10 w-auto shrink-0 px-3 text-xs"
                  disabled={acting || busy}
                  onClick={() =>
                    void run(async () => {
                      const limit = Number(creditLimit.replace(/\D/g, "") || 0);
                      const res = await api.adminSetWalletCredit(detail.id, limit);
                      onNotify(limit > 0 ? "سقف اعتبار ذخیره شد" : "اعتبار غیرفعال شد", "success");
                      return res.user;
                    })
                  }
                >
                  ذخیره اعتبار
                </TgButton>
              </div>
            </div>
          </section>

          <section className="space-y-2 rounded-2xl border border-amber-500/20 bg-amber-500/5 p-3">
            <div className="flex items-center gap-1.5 text-xs font-semibold text-amber-200">
              <Star className="size-3.5" />
              اشتراک Pro
            </div>
            <div className="flex gap-2">
              <Input
                value={proDays}
                onChange={(e) => setProDays(e.target.value.replace(/\D/g, ""))}
                placeholder="روز (خالی = پیش‌فرض)"
                dir="ltr"
                inputMode="numeric"
                className="h-10 flex-1 rounded-xl border-white/15 bg-black/40"
              />
              <TgButton
                className="h-10 w-auto shrink-0 px-3 text-xs"
                disabled={acting || busy}
                onClick={() =>
                  void run(async () => {
                    const days = proDays ? Number(proDays) : undefined;
                    const res = await api.adminGrantPro(detail.id, days);
                    setProDays("");
                    onNotify("Pro اعطا شد", "success");
                    return res.user;
                  })
                }
              >
                اعطای Pro
              </TgButton>
            </div>
          </section>

          <div className="grid grid-cols-2 gap-2">
            <TgButton
              variant="outline"
              className="h-10 text-xs"
              onClick={() => {
                onClose();
                onOpenChat(detail.id);
              }}
            >
              <MessageCircle className="size-3.5" />
              گفتگو
            </TgButton>
            {!detail.is_super_admin && (
              <TgButton
                variant={detail.is_admin ? "outline" : "primary"}
                className="h-10 text-xs"
                disabled={acting || busy}
                onClick={() =>
                  void run(async () => {
                    await onSetRole(detail.id, detail.is_admin ? "user" : "admin");
                    return api.adminUserDetail(detail.id);
                  })
                }
              >
                <Shield className="size-3.5" />
                {detail.is_admin ? "حذف ادمین" : "ادمین کن"}
              </TgButton>
            )}
          </div>

          <TgButton
            variant={detail.is_test ? "outline" : "primary"}
            className="h-10 text-xs"
            disabled={acting || busy}
            onClick={() =>
              void run(async () => {
                await api.adminSetUserTest(detail.id, !detail.is_test);
                onNotify(
                  detail.is_test ? "این کاربر دیگر تست نیست" : "کاربر تست شد و از آمار ادمین مخفی می‌شود",
                  "success",
                );
                return api.adminUserDetail(detail.id);
              })
            }
          >
            {detail.is_test ? "حذف پرچم تست" : "علامت کاربر تست"}
          </TgButton>

          {onGrantTrial && !detail.trial_granted && (
            <TgButton
              variant="outline"
              className="h-10 text-xs"
              disabled={acting || busy}
              onClick={() =>
                void run(async () => {
                  await onGrantTrial({
                    targets_text: String(detail.telegram_id),
                    skip_existing_trial: true,
                    notify_users: true,
                  });
                  return api.adminUserDetail(detail.id);
                })
              }
            >
              <Gift className="size-3.5" />
              اعطای VPN تست
            </TgButton>
          )}

          <section className="space-y-2 rounded-2xl border border-white/10 bg-black/25 p-3">
            <div className="flex items-center gap-1.5 text-xs font-semibold text-neutral-300">
              <Plus className="size-3.5" />
              افزودن کانفیگ
            </div>
            <select
              value={selectedPlanId === "" ? "" : String(selectedPlanId)}
              onChange={(e) => setSelectedPlanId(e.target.value ? Number(e.target.value) : "")}
              className="h-10 w-full rounded-xl border border-white/15 bg-black/40 px-3 text-sm text-white outline-none"
            >
              {giftPlans.length === 0 ? <option value="">پلنی نیست</option> : null}
              {giftPlans.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.title} · {p.traffic_label} · {faNum(p.limit_ip)} IP
                </option>
              ))}
            </select>
            <TgButton
              className="h-10 w-full text-xs"
              disabled={acting || busy || !selectedPlanId}
              onClick={() => {
                if (!selectedPlanId) return;
                void run(async () => {
                  const res = await api.adminGiftSubscription(detail.id, selectedPlanId);
                  onNotify("کانفیگ اضافه شد", "success");
                  return res.user;
                });
              }}
            >
              ساخت و اختصاص کانفیگ
            </TgButton>
          </section>

          <section className="space-y-1.5">
            <h4 className="text-xs font-semibold text-neutral-400">
              کانفیگ‌ها · {faNum(detail.subscriptions.length)}
            </h4>
            {detail.subscriptions.length === 0 ? (
              <p className="rounded-xl border border-dashed border-white/10 px-3 py-4 text-center text-xs text-neutral-500">
                کانفیگی ندارد
              </p>
            ) : (
              detail.subscriptions.map((s) => (
                <AdminUserSubCard
                  key={s.id}
                  sub={s}
                  expanded={openSubId === s.id}
                  acting={acting || Boolean(busy)}
                  onToggle={() => {
                    haptic();
                    setOpenSubId((id) => (id === s.id ? null : s.id));
                  }}
                  onOpenFull={() => onOpenSubscription?.(s.id)}
                  onToggleEnabled={() =>
                    void run(async () => {
                      const res = await api.adminSetSubEnabled(detail.id, s.id, !s.enabled);
                      onNotify(s.enabled ? "کانفیگ غیرفعال شد" : "کانفیگ فعال شد", "success");
                      return res.user;
                    })
                  }
                  onDelete={() => {
                    if (!window.confirm(`حذف کامل کانفیگ «${s.label?.trim() || s.plan_title}»؟`)) return;
                    void run(async () => {
                      const res = await api.adminDeleteSubscription(detail.id, s.id);
                      onNotify("کانفیگ حذف شد", "success");
                      return res.user;
                    });
                  }}
                />
              ))
            )}
          </section>

          <section className="space-y-1.5">
            <h4 className="text-xs font-semibold text-neutral-400">سفارش‌های اخیر</h4>
            {detail.orders.length === 0 ? (
              <p className="text-[11px] text-neutral-500">سفارشی نیست</p>
            ) : (
              detail.orders.slice(0, 8).map((o) => (
                <div key={o.id} className="flex items-center justify-between gap-2 rounded-xl border border-white/8 bg-black/25 px-3 py-2 text-xs">
                  <span className="min-w-0 truncate">
                    #{faNum(o.id)} · {o.plan_title || o.kind_label || "سفارش"}
                  </span>
                  <span className="shrink-0 text-neutral-400">
                    {o.amount_label} · {o.status_label || statusFa(o.status || "")}
                  </span>
                </div>
              ))
            )}
          </section>

          {detail.withdrawals.length > 0 && (
            <section className="space-y-1.5">
              <h4 className="text-xs font-semibold text-neutral-400">برداشت‌ها</h4>
              {detail.withdrawals.map((w) => (
                <div key={w.id} className="flex items-center justify-between gap-2 rounded-xl border border-white/8 bg-black/25 px-3 py-2 text-xs">
                  <span>
                    #{faNum(w.id)} · {w.amount_label}
                  </span>
                  <span className="text-neutral-400">{statusFa(w.status)}</span>
                </div>
              ))}
            </section>
          )}
        </div>
      )}
    </TgSheet>
  );
}

function AdminUserSubCard({
  sub,
  expanded,
  acting,
  onToggle,
  onOpenFull,
  onToggleEnabled,
  onDelete,
}: {
  sub: AdminUserSubscription;
  expanded: boolean;
  acting: boolean;
  onToggle: () => void;
  onOpenFull?: () => void;
  onToggleEnabled: () => void;
  onDelete: () => void;
}) {
  const usagePct = Math.min(100, sub.usage_percent || 0);
  const buyText = [sub.source_label, sub.order_status_label].filter(Boolean).join(" · ");
  return (
    <div className="overflow-hidden rounded-xl border border-white/10 bg-black/30">
      <button type="button" onClick={onToggle} className="flex w-full items-start gap-2 px-3 py-2.5 text-start active:bg-white/5">
        <div className="min-w-0 flex-1">
          <div className="truncate text-sm font-semibold">{sub.label?.trim() || sub.plan_title}</div>
          <div className="mt-0.5 truncate font-mono text-[10px] text-neutral-500" dir="ltr">
            {sub.email}
          </div>
          <div className="mt-1.5 flex flex-wrap gap-1">
            <span className={cn("rounded-md border px-1.5 py-0.5 text-[10px] font-medium", statusChipClass(sub.status))}>
              {statusFa(sub.status)}
            </span>
            {buyText ? (
              <span
                className={cn(
                  "rounded-md border px-1.5 py-0.5 text-[10px] font-medium",
                  statusChipClass(sub.order_status || sub.source || ""),
                )}
              >
                {buyText}
              </span>
            ) : null}
          </div>
        </div>
        <ChevronDown className={cn("mt-1 size-4 shrink-0 text-neutral-500 transition-transform", expanded && "rotate-180")} />
      </button>
      {expanded ? (
        <div className="space-y-2.5 border-t border-white/8 px-3 pb-3 pt-2.5">
          <div className="text-[12px] leading-relaxed">
            <DetailRow label="پلن" value={sub.plan_title} />
            <DetailRow
              label="وضعیت خرید"
              value={
                buyText || "—"
              }
            />
            {sub.order_amount_label ? (
              <DetailRow
                label="مبلغ"
                value={`${sub.order_amount_label}${sub.order_id ? ` · #${faNum(sub.order_id)}` : ""}`}
              />
            ) : null}
            {sub.renew_status_label ? (
              <DetailRow
                label="آخرین تمدید"
                value={`${sub.renew_status_label}${sub.renew_amount_label ? ` · ${sub.renew_amount_label}` : ""}`}
              />
            ) : null}
            <DetailRow label="انقضا" value={sub.expired ? "منقضی" : formatDate(sub.expires_at)} />
            <DetailRow
              label="باقی‌مانده"
              value={
                sub.remaining_days != null && !sub.expired
                  ? `${faNum(sub.remaining_days)} روز`
                  : sub.expired
                    ? "منقضی"
                    : "بدون انقضا"
              }
            />
            <DetailRow label="مصرف" value={`${sub.used_label} / ${sub.total_label || sub.traffic_label}`} />
            {sub.remaining_label ? <DetailRow label="حجم مانده" value={sub.remaining_label} /> : null}
            {sub.limit_ip ? <DetailRow label="محدودیت IP" value={faNum(sub.limit_ip)} /> : null}
            {sub.customer_name ? <DetailRow label="گیرنده" value={sub.customer_name} /> : null}
            {sub.family_role ? (
              <DetailRow label="خانواده" value={sub.family_role === "parent" ? "والد" : "فرزند"} />
            ) : null}
            <DetailRow label="شروع" value={formatDate(sub.created_at)} />
          </div>
          {sub.total_bytes && sub.total_bytes > 0 ? (
            <div>
              <div className="mb-1 flex justify-between text-[10px] text-neutral-500">
                <span>مصرف</span>
                <span className="tabular-nums">{faNum(Math.round(usagePct))}٪</span>
              </div>
              <div className="h-1.5 overflow-hidden rounded-full bg-white/10">
                <div
                  className={cn(
                    "h-full rounded-full",
                    usagePct >= 90 ? "bg-red-400/90" : usagePct >= 70 ? "bg-amber-400/85" : "bg-white/75",
                  )}
                  style={{ width: `${usagePct}%` }}
                />
              </div>
            </div>
          ) : null}
          <div className="grid grid-cols-2 gap-2">
            <TgButton variant="outline" className="h-8 text-[11px]" disabled={acting} onClick={onToggleEnabled}>
              {sub.enabled ? "قطع" : "وصل"}
            </TgButton>
            <TgButton variant="outline" className="h-8 text-[11px] text-red-300" disabled={acting} onClick={onDelete}>
              <Trash2 className="size-3" />
              حذف
            </TgButton>
          </div>
          {onOpenFull ? (
            <TgButton className="h-9 text-xs" onClick={onOpenFull}>
              جزئیات کامل کانفیگ
            </TgButton>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}

function Chip({
  children,
  tone = "muted",
}: {
  children: ReactNode;
  tone?: "muted" | "amber" | "orange";
}) {
  return (
    <span
      className={cn(
        "inline-flex h-5 items-center rounded-md border px-1.5 text-[10px]",
        tone === "amber" && "border-amber-400/30 bg-amber-500/10 text-amber-200",
        tone === "orange" && "border-orange-400/30 bg-orange-500/10 text-orange-200",
        tone === "muted" && "border-white/10 bg-white/5 text-neutral-400",
      )}
    >
      {children}
    </span>
  );
}
