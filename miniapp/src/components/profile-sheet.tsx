import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import {
  Cake,
  Calendar,
  Check,
  ChevronLeft,
  CircleHelp,
  Copy,
  History,
  Mail,
  ScrollText,
  Moon,
  Package,
  Phone,
  Store,
  Sun,
  User as UserIcon,
} from "lucide-react";
import { api, haptic, type ActivityLogItem, type BirthdayGift, type TrialAccount, type UserProfile } from "@/api";
import { ActivityLogRows } from "@/components/admin-activity-log";
import { HelpGuideSheet } from "@/components/help-guide-sheet";
import { TgButton } from "@/components/tg-button";
import { TgSheet } from "@/components/tg-sheet";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useTheme } from "@/lib/theme";
import { cn, faNum } from "@/lib/utils";

function initials(name: string | null | undefined) {
  const n = (name || "").trim();
  if (!n) return "?";
  const parts = n.split(/\s+/).filter(Boolean);
  if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
  return n.slice(0, 2).toUpperCase();
}

function formatMemberSince(iso: string | null) {
  if (!iso) return "—";
  try {
    return new Intl.DateTimeFormat("fa-IR", { dateStyle: "medium" }).format(new Date(iso));
  } catch {
    return "—";
  }
}

function birthdayCountdownLabel(profile: UserProfile | null) {
  if (!profile?.has_birth_date) return null;
  if (profile.is_birthday_today) return "امروز تولد شماست 🎂";
  if (profile.days_until_birthday === 0) return "امروز تولد شماست 🎂";
  if (profile.days_until_birthday != null) {
    return `${faNum(profile.days_until_birthday)} روز تا تولد بعدی`;
  }
  return null;
}

function telegramPhotoUrl() {
  return window.Telegram?.WebApp?.initDataUnsafe?.user?.photo_url || null;
}

function SectionLabel({ children }: { children: ReactNode }) {
  return <h3 className="px-1 text-[11px] font-semibold text-neutral-500">{children}</h3>;
}

function SettingsGroup({ children }: { children: ReactNode }) {
  return (
    <div className="overflow-hidden rounded-2xl border border-white/12 bg-black/40 backdrop-blur-md">
      <div className="divide-y divide-white/8">{children}</div>
    </div>
  );
}

function SettingsRow({
  icon,
  label,
  value,
  hint,
  empty,
  ltr,
  onClick,
  trailing,
  warn,
}: {
  icon: ReactNode;
  label: string;
  value?: string | number | null;
  hint?: string | null;
  empty?: string;
  ltr?: boolean;
  onClick?: () => void;
  trailing?: ReactNode;
  warn?: boolean;
}) {
  const filled = value != null && String(value).trim() !== "";
  const inner = (
    <>
      <div
        className={cn(
          "grid size-9 shrink-0 place-items-center rounded-xl border text-neutral-300",
          warn ? "border-amber-400/25 bg-amber-500/10 text-amber-200" : "border-white/10 bg-white/5",
        )}
      >
        {icon}
      </div>
      <div className="min-w-0 flex-1">
        <div className="text-[11px] text-neutral-500">{label}</div>
        <div
          className={cn(
            "truncate text-[13px]",
            filled ? "font-medium text-neutral-100" : warn ? "text-amber-200/90" : "text-neutral-500",
          )}
          dir={ltr ? "ltr" : undefined}
        >
          {filled ? value : empty || "ثبت نشده"}
        </div>
        {hint ? <div className="mt-0.5 truncate text-[10px] text-neutral-500">{hint}</div> : null}
      </div>
      {trailing}
    </>
  );

  if (onClick) {
    return (
      <button
        type="button"
        onClick={onClick}
        className="flex min-h-14 w-full items-center gap-3 px-3.5 py-2.5 text-start active:bg-white/6"
      >
        {inner}
      </button>
    );
  }

  return <div className="flex min-h-14 items-center gap-3 px-3.5 py-2.5">{inner}</div>;
}

function StatusChip({ ok, label }: { ok: boolean; label: string }) {
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-[10px]",
        ok
          ? "border-emerald-400/20 bg-emerald-500/10 text-emerald-200"
          : "border-amber-400/20 bg-amber-500/10 text-amber-200",
      )}
    >
      {ok ? <Check className="size-2.5" aria-hidden /> : null}
      {label}
    </span>
  );
}

function ProfileSkeleton() {
  return (
    <div className="space-y-4" aria-hidden>
      <div className="rounded-2xl border border-white/10 bg-black/35 p-5">
        <div className="flex items-center gap-3.5">
          <div className="size-[4.5rem] animate-pulse rounded-full bg-white/8" />
          <div className="min-w-0 flex-1 space-y-2">
            <div className="h-4 w-32 animate-pulse rounded bg-white/10" />
            <div className="h-3 w-24 animate-pulse rounded bg-white/8" />
            <div className="h-3 w-40 animate-pulse rounded bg-white/6" />
          </div>
        </div>
      </div>
      <div className="overflow-hidden rounded-2xl border border-white/10 bg-black/30">
        {[0, 1, 2, 3].map((i) => (
          <div key={i} className="flex items-center gap-3 border-t border-white/6 px-3.5 py-3.5 first:border-t-0">
            <div className="size-9 animate-pulse rounded-xl bg-white/8" />
            <div className="h-3 flex-1 animate-pulse rounded bg-white/8" />
          </div>
        ))}
      </div>
    </div>
  );
}

export function ProfilePanel({
  active,
  shopName,
  focusHelp,
  onWalletUpdate,
  onOpenHistory,
  onOpenResellerDesk,
  resellerHint,
}: {
  active: boolean;
  shopName?: string | null;
  focusHelp?: boolean;
  onWalletUpdate?: (balance: number) => void;
  onBirthdayGift?: (gift: BirthdayGift) => void;
  onOpenHistory?: () => void;
  onOpenResellerDesk?: () => void;
  resellerHint?: string | null;
}) {
  const { theme, toggleTheme } = useTheme();
  const [profile, setProfile] = useState<UserProfile | null>(null);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [savingContact, setSavingContact] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [birthDraft, setBirthDraft] = useState("");
  const [emailDraft, setEmailDraft] = useState("");
  const [phoneDraft, setPhoneDraft] = useState("");
  const [contactOpen, setContactOpen] = useState(false);
  const [birthdayOpen, setBirthdayOpen] = useState(false);
  const [helpOpen, setHelpOpen] = useState(!!focusHelp);
  const [activityOpen, setActivityOpen] = useState(false);
  const [activity, setActivity] = useState<ActivityLogItem[]>([]);
  const [activityLoading, setActivityLoading] = useState(false);
  const [copied, setCopied] = useState(false);
  const [photoUrl, setPhotoUrl] = useState<string | null>(() => telegramPhotoUrl());
  const photoObjectUrl = useRef<string | null>(null);
  const walletCb = useRef(onWalletUpdate);
  walletCb.current = onWalletUpdate;

  const applyProfile = useCallback((data: UserProfile, notifyParent = true) => {
    setProfile(data);
    setBirthDraft(data.birth_date || "");
    setEmailDraft(data.email || "");
    setPhoneDraft(data.phone || "");
    if (!notifyParent) return;
    if (data.has_birth_date) {
      walletCb.current?.(data.wallet_balance);
    }
  }, []);

  useEffect(() => {
    if (!active) return;
    let cancelled = false;
    setLoading(true);
    setError(null);
    void api
      .profile()
      .then((data) => {
        if (cancelled) return;
        applyProfile(data);
      })
      .catch((e) => {
        if (cancelled) return;
        setError(e instanceof Error ? e.message : "خطا در بارگذاری پروفایل");
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [active, applyProfile]);

  useEffect(() => {
    if (!active) return;
    const fallback = telegramPhotoUrl();
    if (fallback) setPhotoUrl(fallback);
    let cancelled = false;
    void api
      .profilePhoto()
      .then((blob) => {
        if (cancelled) return;
        if (photoObjectUrl.current) URL.revokeObjectURL(photoObjectUrl.current);
        const url = URL.createObjectURL(blob);
        photoObjectUrl.current = url;
        setPhotoUrl(url);
      })
      .catch(() => {
        if (!cancelled && fallback) setPhotoUrl(fallback);
      });
    return () => {
      cancelled = true;
    };
  }, [active, profile?.has_photo, profile?.telegram_id]);

  useEffect(() => {
    return () => {
      if (photoObjectUrl.current) URL.revokeObjectURL(photoObjectUrl.current);
    };
  }, []);

  useEffect(() => {
    if (!active || !focusHelp) return;
    setHelpOpen(true);
  }, [active, focusHelp]);

  const countdown = useMemo(() => birthdayCountdownLabel(profile), [profile]);

  const saveBirthDate = async () => {
    if (!birthDraft) {
      setError("لطفاً تاریخ تولد را انتخاب کنید");
      return;
    }
    setSaving(true);
    setError(null);
    try {
      applyProfile(await api.saveBirthDate(birthDraft));
      setBirthdayOpen(false);
      haptic();
    } catch (e) {
      const msg = e instanceof Error ? e.message : "ذخیره ناموفق";
      const map: Record<string, string> = {
        future_date: "تاریخ نمی‌تواند در آینده باشد",
        too_young: "حداقل سن ۱۰ سال است",
        invalid_date: "فرمت تاریخ نامعتبر است",
      };
      setError(map[msg] || msg);
    } finally {
      setSaving(false);
    }
  };

  const saveContact = async () => {
    setSavingContact(true);
    setError(null);
    try {
      applyProfile(await api.saveProfileContact({ email: emailDraft, phone: phoneDraft }));
      setContactOpen(false);
      haptic();
    } catch (e) {
      const msg = e instanceof Error ? e.message : "ذخیره ناموفق";
      const map: Record<string, string> = {
        invalid_email: "ایمیل معتبر نیست",
        invalid_phone: "شماره موبایل معتبر نیست",
      };
      setError(map[msg] || msg);
    } finally {
      setSavingContact(false);
    }
  };

  const copyTelegramId = async () => {
    if (!profile) return;
    try {
      await navigator.clipboard?.writeText(String(profile.telegram_id));
      haptic();
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1400);
    } catch {
      /* ignore */
    }
  };

  if (!active) return null;

  const birthdayComplete = Boolean(profile?.has_birth_date && !profile?.birth_date_year_hidden);
  const birthdayFromTelegram = profile?.birth_date_source === "telegram";
  const contactComplete = Boolean(profile?.has_email && profile?.has_phone);
  const filledCount = [Boolean(profile?.has_email), Boolean(profile?.has_phone), birthdayComplete].filter(Boolean).length;
  const profileComplete = filledCount === 3;
  const birthdayNeedsYear = Boolean(profile?.has_birth_date && profile?.birth_date_year_hidden);
  const isLight = theme === "light";

  return (
    <div className="space-y-5 pb-3">
      <div className="px-0.5">
        <h2 className="text-base font-bold tracking-tight">پروفایل</h2>
        <p className="mt-0.5 text-[11px] text-neutral-400">حساب، تماس، تولد و تنظیمات</p>
      </div>

      {loading && <ProfileSkeleton />}

      {!loading && profile && (
        <>
          <section className="relative overflow-hidden rounded-2xl border border-white/12 bg-black/45 p-4 backdrop-blur-md">
            <div
              aria-hidden
              className="pointer-events-none absolute -start-8 -top-10 size-36 rounded-full bg-white/[0.06] blur-2xl"
            />
            <div className="relative flex items-center gap-3.5">
              <div className="relative size-[4.5rem] shrink-0 overflow-hidden rounded-full border border-white/20 bg-black/50 shadow-[0_0_0_4px_rgba(255,255,255,0.04)]">
                {photoUrl ? (
                  <img
                    src={photoUrl}
                    alt=""
                    className="size-full object-cover"
                    onError={() => setPhotoUrl(null)}
                  />
                ) : (
                  <div className="grid size-full place-items-center text-lg font-bold text-white">
                    {initials(profile.full_name)}
                  </div>
                )}
              </div>
              <div className="min-w-0 flex-1">
                <div className="truncate text-lg font-semibold leading-tight">{profile.full_name || "کاربر"}</div>
                {profile.username ? (
                  <div className="mt-0.5 truncate text-[12px] text-neutral-400" dir="ltr">
                    @{profile.username}
                  </div>
                ) : null}
                <div className="mt-1.5 text-[11px] text-neutral-500">
                  عضو از {formatMemberSince(profile.member_since)}
                </div>
              </div>
            </div>

            <div className="relative mt-3.5 flex flex-wrap gap-1.5">
              <StatusChip ok={Boolean(profile.has_email)} label="ایمیل" />
              <StatusChip ok={Boolean(profile.has_phone)} label="موبایل" />
              <StatusChip ok={birthdayComplete} label="تولد" />
            </div>

            {profileComplete && countdown && !profile.is_birthday_today ? (
              <p className="relative mt-3 text-[11px] text-neutral-400">{countdown}</p>
            ) : null}

            {!profileComplete ? (
              <div className="relative mt-3">
                <div className="h-1 overflow-hidden rounded-full bg-white/8">
                  <div
                    className="h-full rounded-full bg-emerald-400/85 transition-[width] duration-300"
                    style={{ width: `${(filledCount / 3) * 100}%` }}
                  />
                </div>
                <p className="mt-1.5 text-[11px] text-neutral-500">
                  {faNum(filledCount)} از {faNum(3)} مورد تکمیل شده
                </p>
              </div>
            ) : null}
          </section>

          {profile.is_birthday_today ? (
            <div className="rounded-2xl border border-amber-400/30 bg-gradient-to-br from-amber-500/15 to-orange-500/10 px-4 py-3.5 text-center">
              <Cake className="mx-auto mb-1 size-6 text-amber-300" aria-hidden />
              <div className="text-sm font-semibold text-amber-100">تولدت مبارک!</div>
            </div>
          ) : !birthdayComplete ? (
            <button
              type="button"
              onClick={() => {
                haptic();
                setBirthdayOpen(true);
              }}
              className="flex w-full items-center gap-3 rounded-2xl border border-amber-400/20 bg-amber-500/10 px-3.5 py-3 text-start active:bg-amber-500/15"
            >
              <span className="grid size-10 shrink-0 place-items-center rounded-xl border border-amber-400/25 bg-amber-500/15 text-amber-200">
                <Cake className="size-5" aria-hidden />
              </span>
              <span className="min-w-0 flex-1">
                <span className="block text-[13px] font-semibold text-amber-100">
                  {birthdayNeedsYear ? "سال تولد را کامل کن" : "تاریخ تولد را ثبت کن"}
                </span>
                <span className="mt-0.5 block text-[11px] leading-relaxed text-amber-200/75">
                  {birthdayNeedsYear
                    ? `روز تولد از تلگرام خوانده شد (${profile.birth_date_label}). سال را وارد کن.`
                    : "تاریخ تولدت را برای تکمیل پروفایل ثبت کن."}
                </span>
              </span>
              <ChevronLeft className="size-4 shrink-0 text-amber-200/70" aria-hidden />
            </button>
          ) : null}

          {error && !contactOpen && !birthdayOpen ? (
            <div className="rounded-xl border border-red-500/25 bg-red-500/10 px-3 py-2.5 text-center text-xs text-red-200">
              {error}
            </div>
          ) : null}

          <div className="space-y-2">
            <SectionLabel>اطلاعات حساب</SectionLabel>
            <SettingsGroup>
              <SettingsRow
                icon={<UserIcon className="size-4" />}
                label="آیدی تلگرام"
                value={profile.telegram_id}
                ltr
                onClick={() => void copyTelegramId()}
                trailing={
                  copied ? (
                    <Check className="size-4 shrink-0 text-emerald-300" aria-hidden />
                  ) : (
                    <Copy className="size-4 shrink-0 text-neutral-500" aria-hidden />
                  )
                }
              />
              <SettingsRow
                icon={<Mail className="size-4" />}
                label="ایمیل"
                value={profile.email}
                empty="برای پشتیبانی ثبت کن"
                ltr
                warn={!profile.has_email}
                onClick={() => {
                  haptic();
                  setContactOpen(true);
                }}
                trailing={<ChevronLeft className="size-4 shrink-0 text-neutral-600" aria-hidden />}
              />
              <SettingsRow
                icon={<Phone className="size-4" />}
                label="شماره موبایل"
                value={profile.phone}
                empty="برای پشتیبانی ثبت کن"
                ltr
                warn={!profile.has_phone}
                onClick={() => {
                  haptic();
                  setContactOpen(true);
                }}
                trailing={<ChevronLeft className="size-4 shrink-0 text-neutral-600" aria-hidden />}
              />
              <SettingsRow
                icon={<Calendar className="size-4" />}
                label="تاریخ تولد"
                value={birthdayComplete ? profile.birth_date_label : null}
                empty={birthdayNeedsYear ? profile.birth_date_label || "سال مشخص نیست" : "برای تکمیل پروفایل ثبت کن"}
                ltr={birthdayComplete}
                hint={
                  birthdayComplete
                    ? birthdayFromTelegram
                      ? countdown && !profile.is_birthday_today
                        ? countdown
                        : "از پروفایل تلگرام"
                      : countdown && !profile.is_birthday_today
                        ? countdown
                        : null
                    : null
                }
                warn={!birthdayComplete}
                onClick={() => {
                  haptic();
                  setBirthdayOpen(true);
                }}
                trailing={<ChevronLeft className="size-4 shrink-0 text-neutral-600" aria-hidden />}
              />
            </SettingsGroup>
          </div>

          <div className="space-y-2">
            <SectionLabel>تنظیمات و راهنما</SectionLabel>
            <SettingsGroup>
              {onOpenResellerDesk ? (
                <SettingsRow
                  icon={<Store className="size-4" />}
                  label="میز فروش"
                  value={resellerHint || "کانفیگ‌هایی که برای کس دیگری خریدی"}
                  onClick={onOpenResellerDesk}
                  trailing={<ChevronLeft className="size-4 shrink-0 text-neutral-600" aria-hidden />}
                />
              ) : null}
              <SettingsRow
                icon={isLight ? <Moon className="size-4" /> : <Sun className="size-4" />}
                label="ظاهر برنامه"
                value={isLight ? "حالت روشن" : "حالت تاریک"}
                onClick={() => {
                  haptic();
                  toggleTheme();
                }}
                trailing={
                  <span className="grid size-8 place-items-center rounded-full border border-white/12 bg-white/5 text-neutral-300">
                    {isLight ? <Moon className="size-3.5" aria-hidden /> : <Sun className="size-3.5" aria-hidden />}
                  </span>
                }
              />
              {onOpenHistory ? (
                <SettingsRow
                  icon={<History className="size-4" />}
                  label="تاریخچه"
                  value="خرید و پرداخت"
                  onClick={onOpenHistory}
                  trailing={<ChevronLeft className="size-4 shrink-0 text-neutral-600" aria-hidden />}
                />
              ) : null}
              <SettingsRow
                icon={<ScrollText className="size-4" />}
                label="فعالیت‌های من"
                value="گزارش کارهای اخیر"
                onClick={() => {
                  haptic();
                  setActivityOpen(true);
                  setActivityLoading(true);
                  void api
                    .myActivity(40, 0)
                    .then((res) => setActivity(res.items))
                    .catch(() => setActivity([]))
                    .finally(() => setActivityLoading(false));
                }}
                trailing={<ChevronLeft className="size-4 shrink-0 text-neutral-600" aria-hidden />}
              />
              <SettingsRow
                icon={<CircleHelp className="size-4" />}
                label="راهنمای استفاده"
                value="آموزش، اپ‌ها و سوالات متداول"
                onClick={() => {
                  haptic();
                  setHelpOpen(true);
                }}
                trailing={<ChevronLeft className="size-4 shrink-0 text-neutral-600" aria-hidden />}
              />
            </SettingsGroup>
          </div>
        </>
      )}

      {!loading && !profile && error ? (
        <div className="rounded-xl border border-red-500/25 bg-red-500/10 px-3 py-2.5 text-center text-xs text-red-200">
          {error}
        </div>
      ) : null}

      <TgSheet
        open={contactOpen}
        onClose={() => setContactOpen(false)}
        title="اطلاعات تماس"
      >
        <div className="space-y-4">
          <p className="text-[12px] leading-relaxed text-neutral-400">
            ایمیل و شماره برای پشتیبانی و پیگیری سفارش استفاده می‌شود.
          </p>
          {error ? (
            <div className="rounded-xl border border-red-500/25 bg-red-500/10 px-3 py-2 text-center text-xs text-red-200">
              {error}
            </div>
          ) : null}
          <div className="space-y-1.5">
            <Label className="text-neutral-300">ایمیل</Label>
            <Input
              type="email"
              dir="ltr"
              inputMode="email"
              autoComplete="email"
              placeholder="name@email.com"
              value={emailDraft}
              onChange={(e) => setEmailDraft(e.target.value)}
            />
          </div>
          <div className="space-y-1.5">
            <Label className="text-neutral-300">شماره موبایل</Label>
            <Input
              type="tel"
              dir="ltr"
              inputMode="tel"
              autoComplete="tel"
              placeholder="0912…"
              value={phoneDraft}
              onChange={(e) => setPhoneDraft(e.target.value)}
            />
          </div>
          <TgButton disabled={savingContact} onClick={() => void saveContact()}>
            {savingContact ? "در حال ذخیره…" : contactComplete ? "بروزرسانی اطلاعات" : "ذخیره اطلاعات تماس"}
          </TgButton>
        </div>
      </TgSheet>

      <TgSheet open={birthdayOpen} onClose={() => setBirthdayOpen(false)} title="تاریخ تولد">
        <div className="space-y-4">
          {error ? (
            <div className="rounded-xl border border-red-500/25 bg-red-500/10 px-3 py-2 text-center text-xs text-red-200">
              {error}
            </div>
          ) : null}
          {birthdayComplete ? (
            <p className="text-[12px] leading-relaxed text-neutral-400">
              {birthdayFromTelegram
                ? "این تاریخ از پروفایل تلگرام خوانده شده. در صورت نیاز می‌توانی عوضش کنی."
                : "تاریخ ثبت‌شده را در صورت نیاز تغییر بده."}
            </p>
          ) : birthdayNeedsYear ? (
            <p className="text-[12px] leading-relaxed text-neutral-400">
              روز تولد از تلگرام خوانده شد ({profile?.birth_date_label})، ولی سال مشخص نیست. تاریخ کامل را وارد کن.
            </p>
          ) : (
            <p className="text-[12px] leading-relaxed text-neutral-400">
              تاریخ تولد در پروفایل تلگرام دیده نشد. در صورت تمایل واردش کن.
            </p>
          )}
          <div className="space-y-1.5">
            <Label className="text-neutral-300">تاریخ تولد (میلادی)</Label>
            <input
              type="date"
              value={birthDraft}
              onChange={(e) => setBirthDraft(e.target.value)}
              max={new Date().toISOString().slice(0, 10)}
              className="w-full rounded-xl border border-white/12 bg-black/40 px-3 py-2.5 text-sm text-white outline-none focus:border-white/25"
            />
          </div>
          <TgButton disabled={saving || !birthDraft} onClick={() => void saveBirthDate()}>
            {saving ? "در حال ذخیره…" : birthdayComplete ? "بروزرسانی تاریخ تولد" : "ثبت تاریخ تولد"}
          </TgButton>
        </div>
      </TgSheet>

      <TgSheet open={activityOpen} onClose={() => setActivityOpen(false)} title="فعالیت‌های من">
        <div className="space-y-3">
          <p className="text-[12px] leading-relaxed text-neutral-400">
            خرید، تغییر کانفیگ، انتقال و بقیه کارهایی که از حسابت انجام شده.
          </p>
          {activityLoading ? (
            <p className="py-6 text-center text-xs text-neutral-500">در حال بارگذاری…</p>
          ) : activity.length === 0 ? (
            <p className="py-6 text-center text-xs text-neutral-500">هنوز فعالیتی ثبت نشده.</p>
          ) : (
            <ActivityLogRows items={activity} showActor={false} />
          )}
        </div>
      </TgSheet>

      <HelpGuideSheet
        open={helpOpen}
        onClose={() => setHelpOpen(false)}
        shopName={shopName || undefined}
        initialSection={focusHelp ? "start" : undefined}
      />
    </div>
  );
}

export function BirthdayGiftSheet({
  open,
  onClose,
  gift,
}: {
  open: boolean;
  onClose: () => void;
  gift: BirthdayGift | null;
}) {
  if (!gift) return null;
  return (
    <TgSheet open={open} onClose={onClose} title="تولدت مبارک! 🎂">
      <div className="space-y-4 text-center">
        <div className="mx-auto grid size-20 place-items-center rounded-full border border-amber-400/30 bg-gradient-to-br from-amber-500/20 to-orange-600/10">
          <Cake className="size-10 text-amber-300" aria-hidden />
        </div>
        <p className="text-sm leading-relaxed text-neutral-200">{gift.message}</p>
        <div className="rounded-2xl border border-white/12 bg-white/5 py-4">
          <div className="text-[11px] text-neutral-400">اعتبار هدیه</div>
          <div className="mt-1 text-2xl font-extrabold tabular-nums text-emerald-300">{gift.amount_label}</div>
        </div>
        <TgButton onClick={onClose}>
          <span className="inline-flex items-center gap-1.5">
            <Check className="size-4" />
            ممنون!
          </span>
        </TgButton>
      </div>
    </TgSheet>
  );
}

export function TrialAccountSheet({
  open,
  onClose,
  trial,
  onOpenDashboard,
}: {
  open: boolean;
  onClose: () => void;
  trial: TrialAccount | null;
  onOpenDashboard?: () => void;
}) {
  const [copied, setCopied] = useState<string | null>(null);

  if (!trial) return null;

  const copyLink = async (link: string) => {
    try {
      if (navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(link);
        haptic();
        setCopied(link);
        window.setTimeout(() => setCopied(null), 1500);
      }
    } catch {
      /* ignore */
    }
  };

  return (
    <TgSheet open={open} onClose={onClose} title="حساب تست رایگان 🎁">
      <div className="space-y-4">
        <div className="rounded-2xl border border-emerald-500/25 bg-emerald-500/10 px-4 py-4 text-center">
          <div className="mx-auto mb-3 grid size-16 place-items-center rounded-full border border-emerald-400/30 bg-emerald-500/15">
            <Package className="size-8 text-emerald-300" aria-hidden />
          </div>
          <p className="text-sm leading-relaxed text-neutral-100">{trial.message}</p>
          <div className="mt-3 flex flex-wrap justify-center gap-2 text-[11px] text-neutral-300">
            <span className="rounded-full border border-white/10 px-2.5 py-1">{faNum(trial.duration_days)} روز</span>
            <span className="rounded-full border border-white/10 px-2.5 py-1">{trial.traffic_label}</span>
          </div>
        </div>

        <div className="rounded-xl border border-white/10 bg-black/30 px-3 py-2.5">
          <div className="text-[11px] text-neutral-500">شناسه کانفیگ</div>
          <div className="mt-0.5 font-mono text-xs text-neutral-100" dir="ltr">
            {trial.email}
          </div>
        </div>

        {trial.links.length > 0 && (
          <div className="space-y-2">
            <div className="text-xs font-semibold text-neutral-300">لینک‌های اتصال</div>
            {trial.links.map((link) => (
              <TgButton
                key={link}
                variant="outline"
                className="h-auto justify-between gap-2 whitespace-normal py-2.5 text-right text-[11px] font-normal"
                onClick={() => void copyLink(link)}
              >
                <span className="min-w-0 break-all" dir="ltr">
                  {link}
                </span>
                {copied === link ? <Check className="size-3.5 shrink-0" /> : <Copy className="size-3.5 shrink-0" />}
              </TgButton>
            ))}
          </div>
        )}

        <div className="grid grid-cols-2 gap-2">
          {onOpenDashboard && (
            <TgButton
              onClick={() => {
                onClose();
                onOpenDashboard();
              }}
            >
              داشبورد
            </TgButton>
          )}
          <TgButton variant={onOpenDashboard ? "outline" : "primary"} onClick={onClose}>
            باشه
          </TgButton>
        </div>
      </div>
    </TgSheet>
  );
}
