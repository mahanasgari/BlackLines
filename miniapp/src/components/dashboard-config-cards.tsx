import { useMemo, useState, type ReactNode } from "react";
import { Check, ChevronDown, Copy, KeyRound, Trash2, Users } from "lucide-react";
import type { DashboardItem } from "@/api";
import { haptic } from "@/api";
import { EditableConfigName } from "@/components/editable-config-name";
import { TgButton } from "@/components/tg-button";
import { cn, faNum } from "@/lib/utils";

type StatusMeta = { text: string; className: string };

export type DashGroup =
  | { type: "family"; key: string; members: DashboardItem[] }
  | { type: "solo"; item: DashboardItem };

function itemMatches(s: DashboardItem, query: string) {
  const hay = [
    s.label,
    s.plan_title,
    s.email,
    s.status,
    s.customer_name,
    s.customer_email,
    s.customer_phone,
    s.customer_telegram_id,
    s.family_role === "parent" ? "والد خانواده" : "",
    s.family_role === "child" ? "فرزند خانواده" : "",
    s.family_group ? "خانواده" : "",
  ]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();
  return hay.includes(query);
}

export function filterAndGroupDashboardItems(items: DashboardItem[], query: string): DashGroup[] {
  const q = query.trim().toLowerCase();
  const matched = q ? items.filter((s) => itemMatches(s, q)) : items;
  const keep = new Set(matched.map((s) => s.id));
  if (q) {
    const groups = new Set(matched.map((s) => s.family_group?.trim()).filter(Boolean) as string[]);
    for (const s of items) {
      const g = s.family_group?.trim();
      if (g && groups.has(g)) keep.add(s.id);
    }
  }
  const visible = items.filter((s) => keep.has(s.id));
  const families = new Map<string, DashboardItem[]>();
  const solos: DashboardItem[] = [];
  for (const item of visible) {
    const g = item.family_group?.trim();
    if (g) {
      const list = families.get(g) || [];
      list.push(item);
      families.set(g, list);
    } else {
      solos.push(item);
    }
  }
  const groups: DashGroup[] = [];
  for (const [key, members] of families) {
    members.sort((a, b) => {
      const ar = a.family_role === "parent" ? 0 : 1;
      const br = b.family_role === "parent" ? 0 : 1;
      if (ar !== br) return ar - br;
      return (a.family_index || 99) - (b.family_index || 99);
    });
    groups.push({ type: "family", key, members });
  }
  groups.push(...solos.map((item) => ({ type: "solo" as const, item })));
  return groups;
}

function Card({
  children,
  className,
  onClick,
}: {
  children: ReactNode;
  className?: string;
  onClick?: () => void;
}) {
  return (
    <div
      className={cn("rounded-2xl border border-white/12 bg-black/45 p-4 backdrop-blur-md", className)}
      onClick={onClick}
      role={onClick ? "button" : undefined}
      tabIndex={onClick ? 0 : undefined}
      onKeyDown={
        onClick
          ? (e) => {
              if (e.key === "Enter" || e.key === " ") {
                e.preventDefault();
                onClick();
              }
            }
          : undefined
      }
    >
      {children}
    </div>
  );
}

function UsageBar({ item }: { item: DashboardItem }) {
  const usagePct = item.total_bytes > 0 ? Math.min(100, item.usage_percent) : 0;
  return (
    <div>
      <div className="mb-1 flex items-center justify-between text-[11px] text-neutral-400">
        <span>
          {item.used_label} / {item.total_label}
        </span>
      </div>
      <div className="h-1.5 overflow-hidden rounded-full bg-white/10">
        <div
          className={cn(
            "h-full rounded-full transition-[width]",
            usagePct >= 90 ? "bg-red-400/90" : usagePct >= 70 ? "bg-amber-400/85" : "bg-white/80",
          )}
          style={{ width: `${usagePct}%` }}
        />
      </div>
    </div>
  );
}

function CopyLinkButton({
  url,
  copied,
  busy,
  onCopy,
  compact,
}: {
  url?: string | null;
  copied: string | null;
  busy: boolean;
  onCopy: (url: string) => void;
  compact?: boolean;
}) {
  if (!url) return null;
  return (
    <TgButton
      variant="outline"
      disabled={busy}
      className={cn("text-xs", compact ? "h-8 flex-1" : "h-9 flex-1")}
      onClick={() => onCopy(url)}
      aria-label="کپی لینک Subscription"
    >
      {copied === url ? (
        <span className="inline-flex items-center gap-1.5">
          <Check className="size-3.5 shrink-0" />
          کپی شد
        </span>
      ) : (
        <span className="inline-flex items-center gap-1.5">
          <Copy className="size-3.5 shrink-0" />
          {compact ? "کپی" : "کپی لینک"}
        </span>
      )}
    </TgButton>
  );
}

function RotateBlock({
  item,
  busy,
  confirm,
  onAsk,
  onCancel,
  onConfirm,
}: {
  item: DashboardItem;
  busy: boolean;
  confirm: boolean;
  onAsk: () => void;
  onCancel: () => void;
  onConfirm: () => void;
}) {
  if (item.status === "expired" || item.status === "disabled") return null;
  if (confirm) {
    return (
      <div className="space-y-2 rounded-lg border border-amber-400/20 bg-amber-500/10 px-2.5 py-2">
        <p className="text-[11px] leading-relaxed text-amber-100/90">
          لینک فعلی باطل می‌شود و لینک جدید کپی می‌شود. مطمئنی؟
        </p>
        <div className="grid grid-cols-2 gap-2">
          <TgButton variant="outline" disabled={busy} className="h-9 text-xs" onClick={onCancel}>
            انصراف
          </TgButton>
          <TgButton disabled={busy} className="h-9 text-xs" onClick={onConfirm}>
            {busy ? "در حال ساخت…" : "لینک جدید"}
          </TgButton>
        </div>
      </div>
    );
  }
  return (
    <TgButton
      variant="outline"
      disabled={busy}
      className="h-9 text-xs"
      onClick={onAsk}
    >
      <KeyRound className="size-3.5 shrink-0" />
      باطل کردن و لینک جدید
    </TgButton>
  );
}

function childSeatLabel(item: DashboardItem) {
  const n = item.family_index && item.family_index > 1 ? item.family_index - 1 : null;
  if (item.customer_name) return item.customer_name;
  if (item.label?.trim()) return item.label.trim();
  return n ? `فرزند ${faNum(n)}` : "فرزند";
}

function memberDisplayName(item: DashboardItem, role: "parent" | "child") {
  if (role === "parent") return item.label?.trim() || item.customer_name || "والد";
  return childSeatLabel(item);
}

export function SoloConfigCard({
  item,
  busy,
  copied,
  rotateConfirm,
  remainingHint,
  statusMeta,
  onOpen,
  onRename,
  onCopy,
  onHideExpired,
  onAskRotate,
  onCancelRotate,
  onConfirmRotate,
}: {
  item: DashboardItem;
  busy: boolean;
  copied: string | null;
  rotateConfirm: boolean;
  remainingHint: string;
  statusMeta: StatusMeta;
  onOpen: () => void;
  onRename: (label: string) => Promise<void>;
  onCopy: (url: string) => void;
  onHideExpired: () => void;
  onAskRotate: () => void;
  onCancelRotate: () => void;
  onConfirmRotate: () => void;
}) {
  const title = item.label?.trim() || item.plan_title;
  return (
    <Card className="cursor-pointer space-y-2.5 transition-colors hover:border-white/20" onClick={onOpen}>
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <EditableConfigName name={title} disabled={busy} onSave={onRename} />
          <p className="mt-0.5 truncate text-[11px] text-neutral-400">
            {item.is_metered ? "مصرفی ابری" : item.is_payg ? "خرید حجم" : item.plan_title}
          </p>
          {item.customer_name ? (
            <div className="mt-1">
              <span className="inline-flex items-center gap-1 rounded-lg border border-teal-500/25 bg-teal-500/10 px-2 py-0.5 text-[10px] font-medium text-teal-100">
                <Users className="size-3" />
                برای {item.customer_name}
              </span>
            </div>
          ) : null}
        </div>
        <span className={cn("shrink-0 rounded-lg border px-2 py-0.5 text-[11px] font-medium", statusMeta.className)}>
          {statusMeta.text}
        </span>
      </div>
      <div className="flex items-center justify-between gap-2 text-[11px] text-neutral-400">
        <span className="tabular-nums">{remainingHint}</span>
      </div>
      <UsageBar item={item} />
      <div className="space-y-2" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between gap-2">
          <TgButton disabled={busy} className="h-9 flex-1 text-xs" onClick={onOpen}>
            باز کردن
          </TgButton>
          <CopyLinkButton url={item.subscription_url} copied={copied} busy={busy} onCopy={onCopy} />
          {item.status === "expired" ? (
            <TgButton
              variant="outline"
              disabled={busy}
              className="h-9 shrink-0 border-red-500/25 px-3 text-xs text-red-300"
              onClick={onHideExpired}
            >
              <Trash2 className="size-3.5 shrink-0" />
              حذف
            </TgButton>
          ) : null}
        </div>
        <RotateBlock
          item={item}
          busy={busy}
          confirm={rotateConfirm}
          onAsk={onAskRotate}
          onCancel={onCancelRotate}
          onConfirm={onConfirmRotate}
        />
      </div>
    </Card>
  );
}

function FamilyMemberRow({
  item,
  role,
  busy,
  copied,
  statusMeta,
  onOpen,
  onRename,
  onCopy,
}: {
  item: DashboardItem;
  role: "parent" | "child";
  busy: boolean;
  copied: string | null;
  statusMeta: StatusMeta;
  onOpen: () => void;
  onRename: (label: string) => Promise<void>;
  onCopy: (url: string) => void;
}) {
  const title = role === "parent" ? item.label?.trim() || "کانفیگ والد" : childSeatLabel(item);
  return (
    <div
      className={cn(
        "space-y-1.5 rounded-xl border px-3 py-2",
        role === "parent" ? "border-sky-400/20 bg-sky-500/[0.07]" : "border-white/8 bg-black/30",
      )}
    >
      <div className="flex items-center justify-between gap-2">
        <div className="min-w-0 flex-1">
          <div className="mb-0.5 flex flex-wrap items-center gap-1">
            <span
              className={cn(
                "rounded-md border px-1.5 py-px text-[10px] font-medium",
                role === "parent"
                  ? "border-sky-400/30 bg-sky-500/15 text-sky-100"
                  : "border-white/10 bg-white/5 text-neutral-300",
              )}
            >
              {role === "parent" ? "والد" : "فرزند"}
            </span>
            {item.customer_name && role === "parent" ? (
              <span className="truncate text-[10px] text-teal-200">برای {item.customer_name}</span>
            ) : null}
          </div>
          <EditableConfigName
            name={title}
            disabled={busy}
            nameClassName="text-[13px] font-medium text-neutral-100"
            onSave={onRename}
          />
        </div>
        <span className={cn("shrink-0 rounded-md border px-1.5 py-0.5 text-[10px] font-medium", statusMeta.className)}>
          {statusMeta.text}
        </span>
      </div>
      <UsageBar item={item} />
      <div className="flex gap-2" onClick={(e) => e.stopPropagation()}>
        <TgButton disabled={busy} className="h-8 flex-1 text-[11px]" onClick={onOpen}>
          باز کردن
        </TgButton>
        <CopyLinkButton url={item.subscription_url} copied={copied} busy={busy} onCopy={onCopy} compact />
      </div>
    </div>
  );
}

export function FamilyPackCard({
  members,
  busy,
  copied,
  remainingHint,
  statusOf,
  onOpen,
  onRename,
  onCopy,
}: {
  members: DashboardItem[];
  busy: boolean;
  copied: string | null;
  remainingHint: (item: DashboardItem) => string;
  statusOf: (status: string) => StatusMeta;
  onOpen: (id: number) => void;
  onRename: (id: number, label: string) => Promise<void>;
  onCopy: (url: string) => void;
}) {
  const [open, setOpen] = useState(true);
  const parent = members.find((m) => m.family_role === "parent") || members[0];
  const children = members.filter((m) => m.id !== parent.id);
  const online = members.filter((m) => m.status === "online").length;
  const plan = parent.plan_title;
  const packTitle =
    parent.label?.trim() && parent.family_role === "parent" ? parent.label.trim() : plan || "پکیج خانواده";
  const preview = members
    .map((m) => memberDisplayName(m, m.id === parent.id ? "parent" : "child"))
    .filter(Boolean)
    .slice(0, 4)
    .join(" · ");
  const extra = members.length > 4 ? ` +${faNum(members.length - 4)}` : "";

  return (
    <div className="overflow-hidden rounded-2xl border border-sky-500/25 bg-gradient-to-b from-sky-500/[0.08] to-black/20">
      <button
        type="button"
        className="flex w-full items-start gap-3 px-3.5 py-3 text-start active:bg-white/5"
        onClick={() => {
          haptic();
          setOpen((v) => !v);
        }}
      >
        <span className="grid size-10 shrink-0 place-items-center rounded-xl border border-sky-400/25 bg-sky-500/15 text-sky-100">
          <Users className="size-5" />
        </span>
        <span className="min-w-0 flex-1">
          <span className="block text-sm font-semibold text-neutral-50">{packTitle}</span>
          <span className="mt-0.5 block text-[11px] text-neutral-400">
            {faNum(members.length)} نفر · {faNum(online)} آنلاین
            {plan && packTitle !== plan ? ` · ${plan}` : ""}
          </span>
          {preview ? (
            <span className="mt-1 block truncate text-[11px] text-neutral-300">
              {preview}
              {extra}
            </span>
          ) : null}
          <span className="mt-1 block text-[10px] text-neutral-500">{remainingHint(parent)}</span>
        </span>
        <ChevronDown className={cn("mt-1 size-4 shrink-0 text-neutral-500 transition-transform", open && "rotate-180")} />
      </button>
      {open ? (
        <div className="space-y-2 border-t border-sky-500/15 px-3 pb-3 pt-2.5">
          <p className="text-[10px] leading-relaxed text-neutral-500">
            هر نفر لینک جدا دارد. والد را برای خودت نگه دار و لینک هر فرزند را برای همان نفر بفرست.
          </p>
          <FamilyMemberRow
            item={parent}
            role="parent"
            busy={busy}
            copied={copied}
            statusMeta={statusOf(parent.status)}
            onOpen={() => onOpen(parent.id)}
            onRename={(label) => onRename(parent.id, label)}
            onCopy={onCopy}
          />
          {children.length > 0 ? (
            <div className="space-y-1.5">
              <div className="px-0.5 text-[10px] font-semibold text-neutral-500">فرزندان</div>
              {children.map((child) => (
                <FamilyMemberRow
                  key={child.id}
                  item={child}
                  role="child"
                  busy={busy}
                  copied={copied}
                  statusMeta={statusOf(child.status)}
                  onOpen={() => onOpen(child.id)}
                  onRename={(label) => onRename(child.id, label)}
                  onCopy={onCopy}
                />
              ))}
            </div>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}

export function DashboardConfigList({
  items,
  query,
  busy,
  copied,
  rotateConfirmId,
  remainingHint,
  statusOf,
  onOpen,
  onRename,
  onCopy,
  onHideExpired,
  onAskRotate,
  onCancelRotate,
  onConfirmRotate,
}: {
  items: DashboardItem[];
  query: string;
  busy: boolean;
  copied: string | null;
  rotateConfirmId: number | null;
  remainingHint: (item: DashboardItem) => string;
  statusOf: (status: string) => StatusMeta;
  onOpen: (id: number) => void;
  onRename: (id: number, label: string) => Promise<void>;
  onCopy: (url: string) => void;
  onHideExpired: (id: number) => void;
  onAskRotate: (id: number) => void;
  onCancelRotate: () => void;
  onConfirmRotate: (id: number) => void;
}) {
  const groups = useMemo(() => filterAndGroupDashboardItems(items, query), [items, query]);
  const families = groups.filter((g): g is Extract<DashGroup, { type: "family" }> => g.type === "family");
  const solos = groups.filter((g): g is Extract<DashGroup, { type: "solo" }> => g.type === "solo");

  if (groups.length === 0) return null;

  return (
    <div className="space-y-4">
      {families.length > 0 ? (
        <section className="space-y-2.5">
          <div className="px-0.5">
            <div className="flex items-center justify-between gap-2">
              <h3 className="text-[11px] font-semibold text-sky-200/80">خانواده</h3>
              <span className="text-[10px] text-neutral-600">{faNum(families.length)} پکیج</span>
            </div>
            <p className="mt-0.5 text-[10px] text-neutral-500">همه اعضای یک پکیج کنار هم هستند.</p>
          </div>
          {families.map((g) => (
            <FamilyPackCard
              key={g.key}
              members={g.members}
              busy={busy}
              copied={copied}
              remainingHint={remainingHint}
              statusOf={statusOf}
              onOpen={onOpen}
              onRename={onRename}
              onCopy={onCopy}
            />
          ))}
        </section>
      ) : null}

      {solos.length > 0 ? (
        <section className="space-y-2.5">
          {families.length > 0 ? (
            <h3 className="px-0.5 text-[11px] font-semibold text-neutral-400">کانفیگ‌های دیگر</h3>
          ) : null}
          {solos.map(({ item }) => (
            <SoloConfigCard
              key={item.id}
              item={item}
              busy={busy}
              copied={copied}
              rotateConfirm={rotateConfirmId === item.id}
              remainingHint={remainingHint(item)}
              statusMeta={statusOf(item.status)}
              onOpen={() => onOpen(item.id)}
              onRename={(label) => onRename(item.id, label)}
              onCopy={onCopy}
              onHideExpired={() => onHideExpired(item.id)}
              onAskRotate={() => onAskRotate(item.id)}
              onCancelRotate={onCancelRotate}
              onConfirmRotate={() => onConfirmRotate(item.id)}
            />
          ))}
        </section>
      ) : null}
    </div>
  );
}
