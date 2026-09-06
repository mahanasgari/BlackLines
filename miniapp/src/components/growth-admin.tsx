import { useCallback, useEffect, useState } from "react";
import { api } from "@/api";
import { TgButton } from "@/components/tg-button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { cn, faNum } from "@/lib/utils";

type PromoItem = {
  id: number;
  code: string;
  kind: string;
  value: number;
  max_uses: number;
  used_count: number;
  per_user_limit: number;
  enabled: boolean;
  kind_label: string;
  value_label: string;
  note: string | null;
};

export function GrowthAdminPanel({
  busy,
  onNotify,
}: {
  busy?: boolean;
  onNotify?: (message: string, kind?: "success" | "error" | "info") => void;
}) {
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [promos, setPromos] = useState<PromoItem[]>([]);
  const [familyEnabled, setFamilyEnabled] = useState(true);
  const [familyMax, setFamilyMax] = useState("5");
  const [familyDisc, setFamilyDisc] = useState("10");
  const [purchaseDisc, setPurchaseDisc] = useState("0");
  const [code, setCode] = useState("");
  const [kind, setKind] = useState<"percent" | "free_days">("percent");
  const [value, setValue] = useState("20");
  const [maxUses, setMaxUses] = useState("0");
  const [perUser, setPerUser] = useState("1");
  const [note, setNote] = useState("");
  const [parentalEnabled, setParentalEnabled] = useState(true);
  const [customDomainsText, setCustomDomainsText] = useState("");
  const [parentalCats, setParentalCats] = useState<{ key: string; label: string; desc: string }[]>([]);

  const reload = useCallback(async () => {
    setLoading(true);
    try {
      const [p, f, d, parental] = await Promise.all([
        api.adminPromoCodes(),
        api.adminFamilySettings(),
        api.adminDiscountSettings(),
        api.adminParentalSettings(),
      ]);
      setPromos(p.items || []);
      setFamilyEnabled(Boolean(f.enabled));
      setFamilyMax(String(f.max_size ?? 5));
      setFamilyDisc(String(d.family_extra_discount_percent ?? f.extra_discount_percent ?? 10));
      setPurchaseDisc(String(d.purchase_discount_percent ?? 0));
      setParentalEnabled(Boolean(parental.enabled));
      setCustomDomainsText((parental.custom_domains || []).join("\n"));
      setParentalCats(parental.categories || []);
    } catch (e) {
      onNotify?.(e instanceof Error ? e.message : "خطا در بارگذاری", "error");
    } finally {
      setLoading(false);
    }
  }, [onNotify]);

  useEffect(() => {
    void reload();
  }, [reload]);

  const saveDiscounts = async () => {
    setSaving(true);
    try {
      const res = await api.adminSetDiscountSettings({
        purchase_discount_percent: Math.max(0, Math.min(90, parseInt(purchaseDisc, 10) || 0)),
        family_extra_discount_percent: Math.max(0, Math.min(50, parseInt(familyDisc, 10) || 0)),
      });
      setPurchaseDisc(String(res.purchase_discount_percent));
      setFamilyDisc(String(res.family_extra_discount_percent));
      onNotify?.("تخفیف خرید ذخیره شد", "success");
    } catch (e) {
      onNotify?.(e instanceof Error ? e.message : "ذخیره ناموفق", "error");
    } finally {
      setSaving(false);
    }
  };

  const saveFamily = async () => {
    setSaving(true);
    try {
      const res = await api.adminSetFamilySettings({
        enabled: familyEnabled,
        max_size: Math.max(1, Math.min(10, parseInt(familyMax, 10) || 5)),
        extra_discount_percent: Math.max(0, Math.min(50, parseInt(familyDisc, 10) || 0)),
      });
      setFamilyEnabled(Boolean(res.enabled));
      setFamilyMax(String(res.max_size));
      onNotify?.("تنظیمات پکیج خانواده ذخیره شد", "success");
    } catch (e) {
      onNotify?.(e instanceof Error ? e.message : "ذخیره ناموفق", "error");
    } finally {
      setSaving(false);
    }
  };

  const createPromo = async () => {
    setSaving(true);
    try {
      await api.adminCreatePromo({
        code: code.trim(),
        kind,
        value: parseInt(value, 10) || 0,
        max_uses: parseInt(maxUses, 10) || 0,
        per_user_limit: parseInt(perUser, 10) || 1,
        enabled: true,
        note: note.trim() || undefined,
      });
      setCode("");
      setNote("");
      onNotify?.("کد تخفیف ساخته شد", "success");
      await reload();
    } catch (e) {
      onNotify?.(e instanceof Error ? e.message : "ساخت کد ناموفق", "error");
    } finally {
      setSaving(false);
    }
  };

  const togglePromo = async (item: PromoItem) => {
    setSaving(true);
    try {
      await api.adminSetPromoEnabled(item.id, !item.enabled);
      await reload();
    } catch (e) {
      onNotify?.(e instanceof Error ? e.message : "تغییر وضعیت ناموفق", "error");
    } finally {
      setSaving(false);
    }
  };

  if (loading) {
    return <p className="text-[11px] text-neutral-500">در حال بارگذاری…</p>;
  }

  const locked = busy || saving;

  return (
    <div className="space-y-4">
      <div className="space-y-2">
        <p className="text-[11px] leading-relaxed text-neutral-400">
          تخفیف فقط هنگام خرید اعمال می‌شود، نه وقتی کاربر تعداد نفر یا پلن را انتخاب می‌کند.
        </p>
        <div className="grid grid-cols-2 gap-2">
          <div className="space-y-1">
            <Label className="text-neutral-400">تخفیف روی مبلغ خرید ٪</Label>
            <Input
              value={purchaseDisc}
              onChange={(e) => setPurchaseDisc(e.target.value.replace(/[^\d]/g, ""))}
              dir="ltr"
              inputMode="numeric"
              disabled={locked}
              className="h-9 rounded-lg border-white/15 bg-black/40 text-sm"
            />
          </div>
          <div className="space-y-1">
            <Label className="text-neutral-400">تخفیف عضو اضافه خانواده ٪</Label>
            <Input
              value={familyDisc}
              onChange={(e) => setFamilyDisc(e.target.value.replace(/[^\d]/g, ""))}
              dir="ltr"
              inputMode="numeric"
              disabled={locked}
              className="h-9 rounded-lg border-white/15 bg-black/40 text-sm"
            />
          </div>
        </div>
        <TgButton disabled={locked} className="h-9 text-xs" onClick={() => void saveDiscounts()}>
          ذخیره تخفیف خرید
        </TgButton>
      </div>

      <div className="border-t border-white/10 pt-3 space-y-2">
        <p className="text-[11px] leading-relaxed text-neutral-400">
          پکیج خانواده: یک پرداخت برای چند کانفیگ (اولی والد، بقیه فرزند). والد می‌تواند دسترسی فرزند را محدود کند.
        </p>
        <label className="flex items-center gap-2 text-sm text-neutral-200">
          <input
            type="checkbox"
            checked={familyEnabled}
            onChange={(e) => setFamilyEnabled(e.target.checked)}
            disabled={locked}
            className="size-4 rounded border-white/20"
          />
          فعال بودن پکیج خانواده
        </label>
        <div className="space-y-1">
          <Label className="text-neutral-400">حداکثر اعضا</Label>
          <Input
            value={familyMax}
            onChange={(e) => setFamilyMax(e.target.value.replace(/[^\d]/g, ""))}
            dir="ltr"
            inputMode="numeric"
            disabled={locked}
            className="h-9 rounded-lg border-white/15 bg-black/40 text-sm"
          />
        </div>
        <TgButton disabled={locked} className="h-9 text-xs" onClick={() => void saveFamily()}>
          ذخیره خانواده
        </TgButton>
      </div>

      <div className="border-t border-white/10 pt-3 space-y-2">
        <p className="text-[11px] leading-relaxed text-neutral-400">
          محدودیت والدین: والد روی کانفیگ فرزند سایت‌هایی مثل تیک‌تاک یا بازی را مسدود می‌کند (روی سرور).
        </p>
        <label className="flex items-center gap-2 text-sm text-neutral-200">
          <input
            type="checkbox"
            checked={parentalEnabled}
            onChange={(e) => setParentalEnabled(e.target.checked)}
            disabled={locked}
            className="size-4 rounded border-white/20"
          />
          فعال بودن محدودیت والدین
        </label>
        {parentalCats.length > 0 ? (
          <ul className="space-y-1 text-[10px] text-neutral-400">
            {parentalCats.map((c) => (
              <li key={c.key}>
                · {c.label} — {c.desc}
              </li>
            ))}
          </ul>
        ) : null}
        <div className="space-y-1">
          <Label className="text-neutral-400">دامنه‌های سفارشی (هر خط یکی)</Label>
          <textarea
            value={customDomainsText}
            onChange={(e) => setCustomDomainsText(e.target.value)}
            rows={3}
            dir="ltr"
            placeholder={"example.com\ndomain:blocked.net"}
            disabled={locked}
            className="w-full resize-none rounded-lg border border-white/15 bg-black/40 px-2.5 py-2 font-mono text-xs outline-none"
          />
        </div>
        <TgButton
          disabled={locked}
          className="h-9 text-xs"
          onClick={() => {
            void (async () => {
              setSaving(true);
              try {
                const domains = customDomainsText
                  .split(/\n|,/)
                  .map((s) => s.trim())
                  .filter(Boolean);
                const res = await api.adminSetParentalSettings({
                  enabled: parentalEnabled,
                  custom_domains: domains,
                });
                setParentalEnabled(Boolean(res.enabled));
                setCustomDomainsText((res.custom_domains || []).join("\n"));
                setParentalCats(res.categories || []);
                onNotify?.(
                  res.sync?.ok === false
                    ? "ذخیره شد ولی همگام‌سازی پنل کامل نشد"
                    : "محدودیت والدین ذخیره و روی سرور اعمال شد",
                  res.sync?.ok === false ? "error" : "success",
                );
              } catch (e) {
                onNotify?.(e instanceof Error ? e.message : "ذخیره ناموفق", "error");
              } finally {
                setSaving(false);
              }
            })();
          }}
        >
          ذخیره محدودیت والدین
        </TgButton>
      </div>

      <div className="border-t border-white/10 pt-3 space-y-2">
        <p className="text-[11px] leading-relaxed text-neutral-400">
          کد تخفیف: درصد از مبلغ یا روز رایگان اضافه روی مدت اشتراک.
        </p>
        <div className="grid grid-cols-2 gap-2">
          <div className="col-span-2 space-y-1">
            <Label className="text-neutral-400">کد</Label>
            <Input
              value={code}
              onChange={(e) => setCode(e.target.value.toUpperCase())}
              dir="ltr"
              placeholder="SUMMER20"
              disabled={locked}
              className="h-9 rounded-lg border-white/15 bg-black/40 text-sm font-mono"
            />
          </div>
          <div className="space-y-1">
            <Label className="text-neutral-400">نوع</Label>
            <select
              value={kind}
              onChange={(e) => setKind(e.target.value as "percent" | "free_days")}
              disabled={locked}
              className="h-9 w-full rounded-lg border border-white/15 bg-black/40 px-2 text-sm"
            >
              <option value="percent">درصد تخفیف</option>
              <option value="free_days">روز رایگان</option>
            </select>
          </div>
          <div className="space-y-1">
            <Label className="text-neutral-400">{kind === "percent" ? "درصد" : "روز"}</Label>
            <Input
              value={value}
              onChange={(e) => setValue(e.target.value.replace(/[^\d]/g, ""))}
              dir="ltr"
              inputMode="numeric"
              disabled={locked}
              className="h-9 rounded-lg border-white/15 bg-black/40 text-sm"
            />
          </div>
          <div className="space-y-1">
            <Label className="text-neutral-400">سقف کل (۰=بی‌حد)</Label>
            <Input
              value={maxUses}
              onChange={(e) => setMaxUses(e.target.value.replace(/[^\d]/g, ""))}
              dir="ltr"
              inputMode="numeric"
              disabled={locked}
              className="h-9 rounded-lg border-white/15 bg-black/40 text-sm"
            />
          </div>
          <div className="space-y-1">
            <Label className="text-neutral-400">سقف هر کاربر</Label>
            <Input
              value={perUser}
              onChange={(e) => setPerUser(e.target.value.replace(/[^\d]/g, ""))}
              dir="ltr"
              inputMode="numeric"
              disabled={locked}
              className="h-9 rounded-lg border-white/15 bg-black/40 text-sm"
            />
          </div>
          <div className="col-span-2 space-y-1">
            <Label className="text-neutral-400">یادداشت</Label>
            <Input
              value={note}
              onChange={(e) => setNote(e.target.value)}
              disabled={locked}
              className="h-9 rounded-lg border-white/15 bg-black/40 text-sm"
            />
          </div>
        </div>
        <TgButton
          disabled={locked || code.trim().length < 3}
          className="h-9 text-xs"
          onClick={() => void createPromo()}
        >
          ساخت کد تخفیف
        </TgButton>
      </div>

      <div className="space-y-1.5">
        {promos.length === 0 ? (
          <p className="text-[11px] text-neutral-500">هنوز کدی ساخته نشده.</p>
        ) : (
          promos.map((p) => (
            <div
              key={p.id}
              className="flex items-center justify-between gap-2 rounded-xl border border-white/10 bg-black/30 px-3 py-2"
            >
              <div className="min-w-0">
                <div className="flex items-center gap-2">
                  <span className="font-mono text-sm font-semibold" dir="ltr">
                    {p.code}
                  </span>
                  <span
                    className={cn(
                      "rounded px-1.5 py-0.5 text-[9px] font-medium",
                      p.enabled ? "bg-emerald-500/15 text-emerald-300" : "bg-white/10 text-neutral-400",
                    )}
                  >
                    {p.enabled ? "فعال" : "خاموش"}
                  </span>
                </div>
                <p className="mt-0.5 text-[10px] text-neutral-400">
                  {p.kind_label} · {p.value_label} · استفاده {faNum(p.used_count)}
                  {p.max_uses > 0 ? `/${faNum(p.max_uses)}` : ""}
                  {p.note ? ` · ${p.note}` : ""}
                </p>
              </div>
              <TgButton
                variant="outline"
                disabled={locked}
                className="h-8 shrink-0 px-2 text-[10px]"
                onClick={() => void togglePromo(p)}
              >
                {p.enabled ? "خاموش" : "روشن"}
              </TgButton>
            </div>
          ))
        )}
      </div>
    </div>
  );
}
