import { useEffect, useMemo, useState } from "react";
import { Check, Clock, Download, Eye, Shield, ShieldOff, UserRound, Users } from "lucide-react";
import { api, haptic, type SubscriptionDetail } from "@/api";
import { TgButton } from "@/components/tg-button";
import { TgSheet } from "@/components/tg-sheet";
import { cn, faNum } from "@/lib/utils";

type FamilyInfo = NonNullable<SubscriptionDetail["family"]>;
type Member = FamilyInfo["members"][number];
type Category = FamilyInfo["parental"]["categories"][number];

function RoleBadge({ role }: { role: "parent" | "child" }) {
  if (role === "parent") {
    return (
      <span className="inline-flex items-center gap-1 rounded-md border border-sky-500/30 bg-sky-500/10 px-1.5 py-0.5 text-[10px] font-medium text-sky-200">
        <UserRound className="size-3" />
        والد
      </span>
    );
  }
  return (
    <span className="inline-flex items-center gap-1 rounded-md border border-white/12 bg-white/5 px-1.5 py-0.5 text-[10px] font-medium text-neutral-300">
      فرزند
    </span>
  );
}

function CategoryChip({
  cat,
  active,
  disabled,
  onToggle,
}: {
  cat: Category;
  active: boolean;
  disabled?: boolean;
  onToggle: () => void;
}) {
  return (
    <button
      type="button"
      disabled={disabled}
      onClick={onToggle}
      className={cn(
        "flex min-h-11 flex-col items-start rounded-xl border px-2.5 py-2 text-start transition-colors disabled:opacity-50",
        active
          ? "border-rose-400/35 bg-rose-500/15 text-rose-100"
          : "border-white/10 bg-black/35 text-neutral-300 active:bg-white/8",
      )}
    >
      <span className="inline-flex items-center gap-1 text-[12px] font-semibold">
        {active ? <ShieldOff className="size-3.5 shrink-0" /> : <Shield className="size-3.5 shrink-0 opacity-50" />}
        {cat.label}
      </span>
      <span className={cn("mt-0.5 text-[10px] leading-snug", active ? "text-rose-200/70" : "text-neutral-500")}>
        {cat.desc}
      </span>
    </button>
  );
}

function MemberCard({
  member,
  categories,
  isParentViewer,
  editing,
  editCats,
  busy,
  onStartEdit,
  onCancel,
  onToggleCat,
  onSave,
  onClear,
  onOpenActivity,
  scheduleEnabled,
  scheduleStart,
  scheduleEnd,
  onScheduleEnabled,
  onScheduleStart,
  onScheduleEnd,
  vpnScheduleEnabled,
  vpnScheduleStart,
  vpnScheduleEnd,
  onVpnScheduleEnabled,
  onVpnScheduleStart,
  onVpnScheduleEnd,
}: {
  member: Member;
  categories: Category[];
  isParentViewer: boolean;
  editing: boolean;
  editCats: string[];
  busy: boolean;
  onStartEdit: () => void;
  onCancel: () => void;
  onToggleCat: (key: string) => void;
  onSave: () => void;
  onClear: () => void;
  onOpenActivity?: () => void;
  scheduleEnabled: boolean;
  scheduleStart: string;
  scheduleEnd: string;
  onScheduleEnabled: (v: boolean) => void;
  onScheduleStart: (v: string) => void;
  onScheduleEnd: (v: string) => void;
  vpnScheduleEnabled: boolean;
  vpnScheduleStart: string;
  vpnScheduleEnd: string;
  onVpnScheduleEnabled: (v: boolean) => void;
  onVpnScheduleStart: (v: string) => void;
  onVpnScheduleEnd: (v: string) => void;
}) {
  const labels = useMemo(
    () =>
      member.parental_categories
        .map((k) => categories.find((c) => c.key === k)?.label || k)
        .filter(Boolean),
    [member.parental_categories, categories],
  );

  return (
    <div
      className={cn(
        "overflow-hidden rounded-2xl border",
        member.is_parent
          ? "border-sky-500/20 bg-sky-500/10"
          : member.restricted
            ? "border-rose-500/20 bg-rose-500/[0.05]"
            : "border-white/10 bg-black/30",
      )}
    >
      <div className="flex items-start gap-3 px-3 py-3">
        <div
          className={cn(
            "mt-0.5 flex size-9 shrink-0 items-center justify-center rounded-xl border",
            member.is_parent
              ? "border-sky-500/25 bg-sky-500/15 text-sky-200"
              : "border-white/10 bg-white/5 text-neutral-300",
          )}
        >
          {member.is_parent ? <UserRound className="size-4" /> : <Shield className="size-4" />}
        </div>
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-1.5">
            <h4 className="truncate text-[13px] font-semibold text-neutral-50">
              {member.label || member.email}
            </h4>
            <RoleBadge role={member.is_parent ? "parent" : "child"} />
          </div>
          <p className="mt-0.5 truncate font-mono text-[10px] text-neutral-500" dir="ltr">
            {member.email}
          </p>
          <div className="mt-1 flex flex-wrap items-center gap-1.5 text-[11px] text-neutral-300">
            <span className="tabular-nums">
              مصرف: {member.used_label || "۰"}
              {member.total_label ? ` / ${member.total_label}` : ""}
            </span>
            {member.online ? (
              <span className="rounded-md border border-emerald-500/25 bg-emerald-500/10 px-1.5 py-px text-[10px] text-emerald-200">
                آنلاین
              </span>
            ) : null}
          </div>
          {!member.is_parent ? (
            <div className="mt-2">
              {labels.length > 0 ? (
                <div className="flex flex-wrap gap-1">
                  {labels.map((label) => (
                    <span
                      key={label}
                      className="rounded-md border border-rose-500/25 bg-rose-500/10 px-1.5 py-0.5 text-[10px] text-rose-200"
                    >
                      مسدود · {label}
                    </span>
                  ))}
                </div>
              ) : (
                <p className="text-[11px] text-emerald-300/90">دسترسی آزاد — محدودیتی نیست</p>
              )}
              {member.vpn_schedule_label ? (
                <p className="mt-1 inline-flex items-center gap-1 text-[10px] text-sky-200/90">
                  <Clock className="size-3 shrink-0" />
                  VPN فقط {member.vpn_schedule_label}
                  {member.vpn_allowed_now === false
                    ? " · الان قطع"
                    : " · الان مجاز"}
                </p>
              ) : null}
              {member.schedule_label ? (
                <p className="mt-1 text-[10px] text-amber-200/80">
                  ساعت مسدودی سایت: {member.schedule_label}
                  {member.schedule_active === false ? " · الان آزاد" : " · الان فعال"}
                </p>
              ) : null}
            </div>
          ) : (
            <p className="mt-1.5 text-[11px] text-sky-200/80">این کانفیگ کنترل محدودیت‌ها را دارد</p>
          )}
        </div>
        {isParentViewer && !member.is_parent && !editing ? (
          <div className="flex shrink-0 flex-col gap-1.5">
            <button
              type="button"
              onClick={(e) => {
                e.preventDefault();
                e.stopPropagation();
                haptic();
                onOpenActivity?.();
              }}
              className="rounded-xl border border-white/15 bg-white/5 px-2.5 py-1.5 text-[11px] font-medium text-neutral-100 active:bg-white/10"
            >
              گزارش
            </button>
            <button
              type="button"
              onClick={onStartEdit}
              className="rounded-xl border border-white/15 bg-white/5 px-2.5 py-1.5 text-[11px] font-medium text-neutral-100 active:bg-white/10"
            >
              محدودیت
            </button>
          </div>
        ) : null}
      </div>

      {isParentViewer && !member.is_parent && editing ? (
        <div className="space-y-3 border-t border-white/8 bg-black/25 px-3 py-3">
          <div>
            <div className="text-[12px] font-semibold text-neutral-100">چه چیزهایی مسدود شود؟</div>
            <p className="mt-0.5 text-[10px] leading-relaxed text-neutral-500">
              موارد انتخاب‌شده روی سرور برای این فرزند قطع می‌شوند.
            </p>
          </div>
          <div className="grid grid-cols-1 gap-1.5 sm:grid-cols-2">
            {categories.map((cat) => (
              <CategoryChip
                key={cat.key}
                cat={cat}
                active={editCats.includes(cat.key)}
                disabled={busy}
                onToggle={() => onToggleCat(cat.key)}
              />
            ))}
          </div>
          <div className="rounded-xl border border-sky-500/20 bg-sky-500/10 px-2.5 py-2">
            <label className="flex items-center gap-2 text-[12px] text-sky-50">
              <input
                type="checkbox"
                checked={vpnScheduleEnabled}
                onChange={(e) => onVpnScheduleEnabled(e.target.checked)}
                className="size-4 rounded border-white/20 bg-black/40"
              />
              <span className="inline-flex items-center gap-1">
                <Clock className="size-3.5" />
                VPN فقط در این ساعت‌ها کار کند
              </span>
            </label>
            {vpnScheduleEnabled ? (
              <div className="mt-2 grid grid-cols-2 gap-2">
                <label className="space-y-1">
                  <span className="text-[10px] text-neutral-500">از</span>
                  <input
                    type="time"
                    value={vpnScheduleStart}
                    onChange={(e) => onVpnScheduleStart(e.target.value)}
                    className="h-9 w-full rounded-lg border border-white/12 bg-black/40 px-2 text-sm text-white"
                  />
                </label>
                <label className="space-y-1">
                  <span className="text-[10px] text-neutral-500">تا</span>
                  <input
                    type="time"
                    value={vpnScheduleEnd}
                    onChange={(e) => onVpnScheduleEnd(e.target.value)}
                    className="h-9 w-full rounded-lg border border-white/12 bg-black/40 px-2 text-sm text-white"
                  />
                </label>
              </div>
            ) : null}
            {vpnScheduleEnabled ? (
              <p className="mt-1.5 text-[10px] leading-relaxed text-sky-100/70">
                مثلاً ۰۸:۰۰ تا ۲۱:۰۰ — بیرون از این بازه VPN فرزند کلاً قطع می‌شود (ساعت تهران).
              </p>
            ) : (
              <p className="mt-1.5 text-[10px] leading-relaxed text-neutral-500">
                بدون این گزینه، VPN فرزند همیشه روشن است (مگر منقضی یا قطع‌شده).
              </p>
            )}
          </div>
          <div className="rounded-xl border border-white/10 bg-black/30 px-2.5 py-2">
            <label className="flex items-center gap-2 text-[12px] text-neutral-200">
              <input
                type="checkbox"
                checked={scheduleEnabled}
                onChange={(e) => onScheduleEnabled(e.target.checked)}
                className="size-4 rounded border-white/20 bg-black/40"
              />
              فقط در این ساعت‌ها سایت‌ها مسدود شوند
            </label>
            {scheduleEnabled ? (
              <div className="mt-2 grid grid-cols-2 gap-2">
                <label className="space-y-1">
                  <span className="text-[10px] text-neutral-500">از</span>
                  <input
                    type="time"
                    value={scheduleStart}
                    onChange={(e) => onScheduleStart(e.target.value)}
                    className="h-9 w-full rounded-lg border border-white/12 bg-black/40 px-2 text-sm text-white"
                  />
                </label>
                <label className="space-y-1">
                  <span className="text-[10px] text-neutral-500">تا</span>
                  <input
                    type="time"
                    value={scheduleEnd}
                    onChange={(e) => onScheduleEnd(e.target.value)}
                    className="h-9 w-full rounded-lg border border-white/12 bg-black/40 px-2 text-sm text-white"
                  />
                </label>
              </div>
            ) : null}
            {scheduleEnabled ? (
              <p className="mt-1.5 text-[10px] leading-relaxed text-neutral-500">
                مثلاً ۲۱:۰۰ تا ۰۷:۰۰ یعنی شب اینستاگرام قطع؛ بیرون از این ساعت سایت‌ها آزادند. VPN خودش روشن می‌ماند مگر گزینه بالا را زده باشی.
              </p>
            ) : null}
          </div>
          <div className="flex items-center justify-between gap-2 text-[10px] text-neutral-500">
            <span>{faNum(editCats.length)} مورد انتخاب شده</span>
            {editCats.length > 0 ? (
              <button type="button" className="text-rose-300/90" onClick={onClear} disabled={busy}>
                پاک کردن همه
              </button>
            ) : null}
          </div>
          <div className="grid grid-cols-[1fr_auto] gap-2">
            <TgButton className="h-10 text-xs" disabled={busy} onClick={onSave}>
              {busy ? "در حال اعمال…" : "اعمال محدودیت"}
            </TgButton>
            <TgButton variant="outline" className="h-10 px-3 text-xs" disabled={busy} onClick={onCancel}>
              انصراف
            </TgButton>
          </div>
        </div>
      ) : null}
    </div>
  );
}

export function FamilyParentalSection({
  detail,
  onDetailChange,
}: {
  detail: SubscriptionDetail;
  onDetailChange: (next: SubscriptionDetail) => void;
}) {
  const family = detail.family;
  const [editChildId, setEditChildId] = useState<number | null>(null);
  const [editCats, setEditCats] = useState<string[]>([]);
  const [editScheduleOn, setEditScheduleOn] = useState(false);
  const [editStart, setEditStart] = useState("21:00");
  const [editEnd, setEditEnd] = useState("07:00");
  const [editVpnOn, setEditVpnOn] = useState(false);
  const [editVpnStart, setEditVpnStart] = useState("08:00");
  const [editVpnEnd, setEditVpnEnd] = useState("21:00");
  const [busy, setBusy] = useState(false);
  const [toast, setToast] = useState<string | null>(null);
  const [activityChild, setActivityChild] = useState<Member | null>(null);

  if (!family || !family.parental?.enabled) return null;

  const children = family.members.filter((m) => !m.is_parent);
  const restrictedCount = children.filter((m) => m.restricted).length;
  const categories = family.parental.categories || [];

  const flash = (msg: string) => {
    setToast(msg);
    window.setTimeout(() => setToast(null), 1800);
  };

  const save = async (childId: number) => {
    setBusy(true);
    try {
      const schedule = editScheduleOn
        ? { enabled: true, start: editStart || "21:00", end: editEnd || "07:00", days: [0, 1, 2, 3, 4, 5, 6] }
        : null;
      const vpnSchedule = editVpnOn
        ? {
            enabled: true,
            start: editVpnStart || "08:00",
            end: editVpnEnd || "21:00",
            days: [0, 1, 2, 3, 4, 5, 6],
          }
        : null;
      const res = await api.restrictFamilyChild(detail.id, childId, editCats, schedule, vpnSchedule);
      onDetailChange({
        ...detail,
        family: {
          ...family,
          members: family.members.map((row) =>
            row.id === childId
              ? {
                  ...row,
                  parental_categories: res.child.parental_categories,
                  restricted: res.child.restricted,
                  schedule: res.child.schedule,
                  schedule_label: res.child.schedule_label,
                  schedule_active: res.child.schedule_active,
                  vpn_schedule: res.child.vpn_schedule,
                  vpn_schedule_label: res.child.vpn_schedule_label,
                  vpn_allowed_now: res.child.vpn_allowed_now,
                  vpn_schedule_paused: res.child.vpn_schedule_paused,
                }
              : row,
          ),
        },
      });
      setEditChildId(null);
      haptic();
      const bits: string[] = [];
      if (res.child.vpn_schedule_label) bits.push(`VPN: ${res.child.vpn_schedule_label}`);
      if (res.child.restricted) bits.push("سایت‌ها محدود شد");
      else if (!res.child.vpn_schedule_label) bits.push("محدودیت برداشته شد");
      flash(bits.join(" · ") || "ذخیره شد");
    } catch (e) {
      flash(e instanceof Error ? e.message : "خطا در ذخیره");
    } finally {
      setBusy(false);
    }
  };

  return (
    <section className="overflow-hidden rounded-2xl border border-white/10 bg-gradient-to-b from-white/[0.04] to-black/30">
      <div className="border-b border-white/8 px-3 py-3">
        <div className="flex items-start gap-2.5">
          <div className="flex size-9 shrink-0 items-center justify-center rounded-xl border border-white/12 bg-white/5 text-neutral-200">
            <Users className="size-4" />
          </div>
          <div className="min-w-0 flex-1">
            <div className="flex flex-wrap items-center gap-2">
              <h3 className="text-[14px] font-bold text-neutral-50">کنترل والدین</h3>
              {family.is_parent ? (
                <span className="rounded-md border border-emerald-500/25 bg-emerald-500/10 px-1.5 py-0.5 text-[10px] text-emerald-300">
                  مدیریت فعال
                </span>
              ) : (
                <span className="rounded-md border border-white/12 bg-white/5 px-1.5 py-0.5 text-[10px] text-neutral-400">
                  کانفیگ فرزند
                </span>
              )}
            </div>
            <p className="mt-1 text-[11px] leading-relaxed text-neutral-400">
              {family.is_parent
                ? "برای هر فرزند سایت‌ها را محدود کنید، ساعت مجاز VPN بگذارید، و گزارش بازدید را ببینید."
                : "محدودیت‌ها و گزارش این کانفیگ فقط برای والد خانواده است."}
            </p>
          </div>
        </div>

        <div className="mt-3 grid grid-cols-3 gap-1.5">
          <div className="rounded-xl border border-white/8 bg-black/30 px-2 py-2 text-center">
            <div className="text-[13px] font-bold tabular-nums text-neutral-100">{family.used_label || "—"}</div>
            <div className="text-[9px] text-neutral-500">مصرف کل</div>
          </div>
          <div className="rounded-xl border border-white/8 bg-black/30 px-2 py-2 text-center">
            <div className="text-[15px] font-bold tabular-nums text-neutral-100">{faNum(children.length)}</div>
            <div className="text-[9px] text-neutral-500">فرزند</div>
          </div>
          <div className="rounded-xl border border-white/8 bg-black/30 px-2 py-2 text-center">
            <div
              className={cn(
                "text-[15px] font-bold tabular-nums",
                restrictedCount > 0 ? "text-rose-300" : "text-emerald-300",
              )}
            >
              {faNum(restrictedCount)}
            </div>
            <div className="text-[9px] text-neutral-500">محدود شده</div>
          </div>
        </div>
      </div>

      <div className="space-y-2 px-3 py-3">
        {family.members.map((m) => (
          <MemberCard
            key={m.id}
            member={m}
            categories={categories}
            isParentViewer={family.is_parent}
            editing={editChildId === m.id}
            editCats={editCats}
            busy={busy}
            onStartEdit={() => {
              setEditChildId(m.id);
              setEditCats([...m.parental_categories]);
              setEditScheduleOn(Boolean(m.schedule?.enabled));
              setEditStart(m.schedule?.start || "21:00");
              setEditEnd(m.schedule?.end || "07:00");
              setEditVpnOn(Boolean(m.vpn_schedule?.enabled));
              setEditVpnStart(m.vpn_schedule?.start || "08:00");
              setEditVpnEnd(m.vpn_schedule?.end || "21:00");
            }}
            scheduleEnabled={editScheduleOn}
            scheduleStart={editStart}
            scheduleEnd={editEnd}
            onScheduleEnabled={setEditScheduleOn}
            onScheduleStart={setEditStart}
            onScheduleEnd={setEditEnd}
            vpnScheduleEnabled={editVpnOn}
            vpnScheduleStart={editVpnStart}
            vpnScheduleEnd={editVpnEnd}
            onVpnScheduleEnabled={setEditVpnOn}
            onVpnScheduleStart={setEditVpnStart}
            onVpnScheduleEnd={setEditVpnEnd}
            onCancel={() => setEditChildId(null)}
            onToggleCat={(key) =>
              setEditCats((prev) => (prev.includes(key) ? prev.filter((k) => k !== key) : [...prev, key]))
            }
            onSave={() => void save(m.id)}
            onClear={() => setEditCats([])}
            onOpenActivity={() => setActivityChild(m)}
          />
        ))}

        <FamilyActivitySheet
          open={activityChild != null}
          onClose={() => setActivityChild(null)}
          parentId={detail.id}
          child={activityChild}
        />

        {!family.is_parent ? (
          <div className="flex items-start gap-2 rounded-xl border border-white/8 bg-black/25 px-3 py-2.5">
            <Check className="mt-0.5 size-3.5 shrink-0 text-neutral-400" />
            <p className="text-[11px] leading-relaxed text-neutral-400">
              برای تغییر محدودیت‌ها، کانفیگ والد را از لیست اشتراک‌ها باز کنید.
            </p>
          </div>
        ) : null}

        {toast ? (
          <p className="text-center text-[11px] text-emerald-300">{toast}</p>
        ) : null}
      </div>
    </section>
  );
}

type ActivityPayload = Awaited<ReturnType<typeof api.familyChildActivity>>;

function formatWhen(iso: string | null | undefined) {
  if (!iso) return "—";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "—";
  const diff = (Date.now() - d.getTime()) / 1000;
  if (diff < 60) return "همین الان";
  if (diff < 3600) return `${faNum(Math.max(1, Math.floor(diff / 60)))} دقیقه پیش`;
  if (diff < 86400) return `${faNum(Math.floor(diff / 3600))} ساعت پیش`;
  try {
    return new Intl.DateTimeFormat("fa-IR", { dateStyle: "medium", timeStyle: "short" }).format(d);
  } catch {
    return iso;
  }
}

function FamilyActivitySheet({
  open,
  onClose,
  parentId,
  child,
}: {
  open: boolean;
  onClose: () => void;
  parentId: number;
  child: Member | null;
}) {
  const [data, setData] = useState<ActivityPayload | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [tab, setTab] = useState<"all" | "blocked" | "download">("all");

  const title = child?.label || child?.email || "فرزند";

  useEffect(() => {
    if (!open || !child) {
      setData(null);
      setError(null);
      setTab("all");
      return;
    }
    let cancelled = false;
    setLoading(true);
    setError(null);
    void api
      .familyChildActivity(parentId, child.id)
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
  }, [open, parentId, child]);

  const sites = (data?.sites || []).filter((s) => {
    if (tab === "blocked") return s.verdict === "blocked";
    if (tab === "download") return s.category === "download";
    return true;
  });
  const recent = (data?.recent || []).filter((s) => {
    if (tab === "blocked") return s.verdict === "blocked";
    if (tab === "download") return s.category === "download";
    return true;
  });

  return (
    <TgSheet
      open={open}
      onClose={onClose}
      title={`گزارش ${title}`}
      layer={160}
    >
      {loading ? <p className="py-8 text-center text-sm text-neutral-400">در حال جمع‌آوری گزارش…</p> : null}
      {error ? <p className="py-4 text-center text-sm text-orange-300">{error}</p> : null}
      {!loading && data ? (
        <div className="space-y-3">
          <div className="grid grid-cols-3 gap-1.5">
            <div className="rounded-xl border border-white/10 bg-black/30 px-2 py-2 text-center">
              <div className="text-[15px] font-bold tabular-nums">{faNum(data.summary.domains)}</div>
              <div className="text-[9px] text-neutral-500">سایت</div>
            </div>
            <div className="rounded-xl border border-white/10 bg-black/30 px-2 py-2 text-center">
              <div className="text-[15px] font-bold tabular-nums text-rose-200">{faNum(data.summary.blocked)}</div>
              <div className="text-[9px] text-neutral-500">مسدود</div>
            </div>
            <div className="rounded-xl border border-white/10 bg-black/30 px-2 py-2 text-center">
              <div className="text-[15px] font-bold tabular-nums text-sky-200">{faNum(data.summary.downloads)}</div>
              <div className="text-[9px] text-neutral-500">دانلود</div>
            </div>
          </div>

          <p className="text-[11px] leading-relaxed text-neutral-500">{data.disclaimer}</p>

          <div className="flex gap-1">
            {(
              [
                { id: "all" as const, label: "همه" },
                { id: "blocked" as const, label: "مسدود" },
                { id: "download" as const, label: "دانلود" },
              ] as const
            ).map((t) => (
              <button
                key={t.id}
                type="button"
                onClick={() => setTab(t.id)}
                className={cn(
                  "h-8 flex-1 rounded-lg border text-[11px] font-semibold",
                  tab === t.id ? "border-white/20 bg-white/12 text-white" : "border-white/10 bg-black/30 text-neutral-400",
                )}
              >
                {t.label}
              </button>
            ))}
          </div>

          {sites.length === 0 ? (
            <p className="rounded-xl border border-dashed border-white/10 px-3 py-6 text-center text-[12px] text-neutral-500">
              {data.logging.ready
                ? "هنوز اتصالی برای این فرزند ثبت نشده. بعد از استفاده از VPN اینجا پر می‌شود."
                : "گزارش‌گیری در حال فعال‌سازی است. چند دقیقه دیگر دوباره باز کنید."}
            </p>
          ) : (
            <div className="space-y-2">
              {sites.map((s) => (
                <div key={`${s.domain}-${s.verdict}`} className="rounded-xl border border-white/10 bg-black/30 px-3 py-2.5">
                  <div className="flex items-start justify-between gap-2">
                    <div className="min-w-0">
                      <div className="truncate font-mono text-[12px] text-neutral-100" dir="ltr">
                        {s.domain}
                      </div>
                      <div className="mt-1 flex flex-wrap items-center gap-1">
                        <span className="rounded-md border border-white/10 bg-white/5 px-1.5 py-px text-[10px] text-neutral-400">
                          {s.category_label}
                        </span>
                        <span
                          className={cn(
                            "rounded-md border px-1.5 py-px text-[10px]",
                            s.verdict === "blocked"
                              ? "border-rose-400/30 bg-rose-500/10 text-rose-200"
                              : "border-emerald-400/20 bg-emerald-500/10 text-emerald-200",
                          )}
                        >
                          {s.verdict_label}
                        </span>
                      </div>
                    </div>
                    <div className="shrink-0 text-end">
                      <div className="text-[12px] font-semibold tabular-nums">{faNum(s.hit_count)}</div>
                      <div className="text-[10px] text-neutral-500">بار</div>
                    </div>
                  </div>
                  <p className="mt-1.5 text-[10px] text-neutral-500">آخرین {formatWhen(s.last_seen)}</p>
                </div>
              ))}
            </div>
          )}

          {recent.length > 0 ? (
            <div className="space-y-1.5">
              <div className="flex items-center gap-1.5 text-[11px] font-semibold text-neutral-400">
                <Clock className="size-3.5" />
                فعالیت اخیر
              </div>
              {recent.slice(0, 20).map((h, idx) => (
                <div key={`${h.domain}-${h.seen_at}-${idx}`} className="flex items-center justify-between gap-2 text-[11px]">
                  <span className="min-w-0 truncate font-mono text-neutral-200" dir="ltr">
                    {h.verdict === "blocked" ? <ShieldOff className="me-1 inline size-3 text-rose-300" /> : null}
                    {h.category === "download" ? <Download className="me-1 inline size-3 text-sky-300" /> : null}
                    {h.verdict === "visit" && h.category !== "download" ? <Eye className="me-1 inline size-3 text-neutral-500" /> : null}
                    {h.domain}
                  </span>
                  <span className="shrink-0 text-neutral-500">{formatWhen(h.seen_at)}</span>
                </div>
              ))}
            </div>
          ) : null}
        </div>
      ) : null}
    </TgSheet>
  );
}
