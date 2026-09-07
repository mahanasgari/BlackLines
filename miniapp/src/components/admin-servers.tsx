import { useEffect, useMemo, useState } from "react";
import { api, type VpnConfigFlags, type VpnConfigType, type VpnServer } from "@/api";
import { TgButton } from "@/components/tg-button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { cn, faNum } from "@/lib/utils";

const emptyDraft = {
  name: "",
  country_code: "",
  xui_base_url: "",
  xui_api_token: "",
  inbound_ids: "",
  public_host: "",
  public_ip: "",
};

const defaultFlags: VpnConfigFlags = {
  reality: true,
  ws: true,
  http: true,
  ws_tls: true,
  http_ms: true,
  telegram: true,
};

const defaultTypes: VpnConfigType[] = [
  { key: "reality", label: "Reality" },
  { key: "ws", label: "WS / 443" },
  { key: "http", label: "HTTP" },
  { key: "ws_tls", label: "WS-TLS" },
  { key: "http_ms", label: "HTTP-MS" },
  { key: "telegram", label: "پروکسی تلگرام" },
];

function flagsOf(server: VpnServer): VpnConfigFlags {
  return { ...defaultFlags, ...(server.config_flags || {}) };
}

function sameFlags(a: VpnConfigFlags, b: VpnConfigFlags) {
  return (Object.keys(defaultFlags) as (keyof VpnConfigFlags)[]).every((k) => Boolean(a[k]) === Boolean(b[k]));
}

function ServerConfigEditor({
  server,
  configTypes,
  busy,
  onSaved,
}: {
  server: VpnServer;
  configTypes: VpnConfigType[];
  busy?: boolean;
  onSaved: (res: { items: VpnServer[]; config_types?: VpnConfigType[] }, msg: string) => void;
}) {
  const savedFlags = useMemo(() => flagsOf(server), [server]);
  const [draftFlags, setDraftFlags] = useState<VpnConfigFlags>(savedFlags);
  const [serverOn, setServerOn] = useState(Boolean(server.enabled));
  const [saving, setSaving] = useState(false);

  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setDraftFlags(flagsOf(server));
    setServerOn(Boolean(server.enabled));
    setError(null);
  }, [server]);

  const dirty = serverOn !== Boolean(server.enabled) || !sameFlags(draftFlags, savedFlags);

  const toggleFlag = (key: keyof VpnConfigFlags) => {
    setDraftFlags((prev) => ({ ...prev, [key]: !prev[key] }));
  };

  const save = async () => {
    setSaving(true);
    setError(null);
    try {
      const body: { enabled?: boolean; configs?: VpnConfigFlags } = {};
      if (serverOn !== Boolean(server.enabled)) body.enabled = serverOn;
      if (!sameFlags(draftFlags, savedFlags)) body.configs = draftFlags;
      if (body.enabled === undefined && !body.configs) return;
      const res = await api.adminSetServerVisibility(server.id, body);
      onSaved(res, "ذخیره شد — فقط کانفیگ‌های تیک‌خورده برای کاربر نمایش داده می‌شود.");
    } catch (e) {
      setError(e instanceof Error ? e.message : "ذخیره ناموفق بود");
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="mt-2.5 space-y-2 border-t border-white/8 pt-2.5">
      <label className="flex items-center gap-2 rounded-lg border border-white/10 bg-black/25 px-2.5 py-2">
        <input
          type="checkbox"
          className="size-4 accent-emerald-400"
          checked={serverOn}
          disabled={busy || saving}
          onChange={(e) => setServerOn(e.target.checked)}
        />
        <span className="text-[12px] text-neutral-100">
          این سرور برای کاربران فعال باشد
          {!serverOn ? <span className="text-amber-300"> (مخفی + قطع اتصال)</span> : null}
        </span>
      </label>

      <div className={cn("space-y-1.5", !serverOn && "opacity-45")}>
        <div className="text-[10px] text-neutral-500">کدام کانفیگ‌ها در پنل کاربر نشان داده شوند؟</div>
        <div className="grid grid-cols-1 gap-1.5">
          {configTypes.map((ct) => {
            const key = ct.key as keyof VpnConfigFlags;
            const checked = Boolean(draftFlags[key]);
            return (
              <label
                key={`${server.id}-${ct.key}`}
                className={cn(
                  "flex items-center gap-2 rounded-lg border px-2.5 py-2",
                  checked ? "border-emerald-500/30 bg-emerald-500/10" : "border-white/10 bg-black/20",
                  (!serverOn || busy || saving) && "pointer-events-none",
                )}
              >
                <input
                  type="checkbox"
                  className="size-4 accent-emerald-400"
                  checked={checked}
                  disabled={!serverOn || busy || saving}
                  onChange={() => toggleFlag(key)}
                />
                <span className="text-[12px] text-neutral-100">{ct.label}</span>
              </label>
            );
          })}
        </div>
      </div>

      <TgButton
        className="h-9 text-xs"
        disabled={!dirty || busy || saving}
        onClick={() => void save()}
      >
        {saving ? "در حال ذخیره…" : "ذخیره تنظیمات این سرور"}
      </TgButton>
      {error ? <p className="text-[11px] text-red-300">{error}</p> : null}
    </div>
  );
}

export function AdminServersPanel({ busy }: { busy?: boolean }) {
  const [items, setItems] = useState<VpnServer[]>([]);
  const [configTypes, setConfigTypes] = useState<VpnConfigType[]>(defaultTypes);
  const [draft, setDraft] = useState(emptyDraft);
  const [loading, setLoading] = useState(true);
  const [acting, setActing] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    void api
      .adminServers()
      .then((res) => {
        if (cancelled) return;
        setItems(res.items);
        if (res.config_types?.length) setConfigTypes(res.config_types);
      })
      .catch((e) => {
        if (!cancelled) setMessage(e instanceof Error ? e.message : "بارگذاری سرورها ناموفق");
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const run = async (fn: () => Promise<void>) => {
    setActing(true);
    setMessage(null);
    try {
      await fn();
    } catch (e) {
      setMessage(e instanceof Error ? e.message : "عملیات ناموفق");
    } finally {
      setActing(false);
    }
  };

  const applyResult = (res: { items: VpnServer[]; config_types?: VpnConfigType[] }) => {
    setItems(res.items);
    if (res.config_types?.length) setConfigTypes(res.config_types);
  };

  const extras = items.filter((s) => !s.primary);

  return (
    <div className="space-y-3">
      <p className="text-[11px] leading-relaxed text-neutral-400">
        برای هر سرور تیک بزنید کدام کانفیگ‌ها برای کاربر فعال باشد، بعد «ذخیره تنظیمات این سرور» را بزنید.
        اگر خود سرور را خاموش کنید، همه‌ی لینک‌هایش از پنل کاربر حذف و اتصال قطع می‌شود.
      </p>

      {loading && <p className="text-center text-[11px] text-neutral-500">در حال بارگذاری…</p>}

      <div className="space-y-2">
        {items.map((s) => (
          <div key={`${s.primary ? "p" : "s"}-${s.id}`} className="rounded-xl border border-white/10 bg-black/30 px-3 py-2.5">
            <div className="flex items-start justify-between gap-2">
              <div className="min-w-0">
                <div className="truncate text-sm font-semibold">
                  {s.name}
                  {s.country_code ? ` · ${s.country_code}` : ""}
                </div>
                <div className="mt-0.5 truncate font-mono text-[10px] text-neutral-500" dir="ltr">
                  {s.public_host || s.public_ip || s.xui_base_url}
                </div>
                <div className="mt-1 text-[10px] text-neutral-500">
                  اینباند {s.inbound_ids || "—"}
                  {s.primary ? " · سرور اصلی" : ""}
                  {!s.enabled ? " · الان مخفی است" : ""}
                </div>
                <div className="mt-1 flex flex-wrap gap-1.5 text-[10px]">
                  <span
                    className={cn(
                      "rounded-md border px-1.5 py-0.5",
                      s.health_ok === false
                        ? "border-red-500/30 bg-red-500/10 text-red-300"
                        : "border-emerald-500/30 bg-emerald-500/10 text-emerald-300",
                    )}
                  >
                    {s.health_ok === false ? "سلامت: قطع" : "سلامت: OK"}
                    {s.last_ping_ms != null ? ` · ${faNum(s.last_ping_ms)}ms` : ""}
                  </span>
                  {s.links_visible === false ? (
                    <span className="rounded-md border border-amber-500/30 bg-amber-500/10 px-1.5 py-0.5 text-amber-200">
                      لینک‌ها مخفی
                    </span>
                  ) : (
                    <span className="rounded-md border border-white/10 bg-white/5 px-1.5 py-0.5 text-neutral-400">
                      لینک‌ها فعال
                    </span>
                  )}
                  {(s.health_fail_count || 0) > 0 ? (
                    <span className="text-neutral-500">خطا: {faNum(s.health_fail_count || 0)}</span>
                  ) : null}
                </div>
              </div>
              {!s.primary && (
                <div className="flex shrink-0 flex-col gap-1">
                  <TgButton
                    variant="outline"
                    className="h-7 w-auto px-2 text-[10px]"
                    disabled={acting || busy}
                    onClick={() =>
                      void run(async () => {
                        const res = await api.adminSyncServer(s.id);
                        const tgPart =
                          (res.telegram_attached ?? 0) + (res.telegram_skipped ?? 0) + (res.telegram_failed ?? 0) > 0
                            ? ` · تلگرام: ${faNum(res.telegram_attached ?? 0)} وصل · ${faNum(res.telegram_skipped ?? 0)} موجود · ${faNum(res.telegram_failed ?? 0)} خطا`
                            : "";
                        setMessage(
                          `همگام‌سازی: ${faNum(res.synced)} اضافه · ${faNum(res.skipped)} موجود · ${faNum(res.failed)} خطا${tgPart}`,
                        );
                      })
                    }
                  >
                    همگام‌سازی
                  </TgButton>
                  <TgButton
                    variant="outline"
                    className="h-7 w-auto px-2 text-[10px]"
                    disabled={acting || busy}
                    onClick={() => {
                      if (!window.confirm("این سرور از فروشگاه حذف شود؟ کانفیگ‌های روی خود سرور پاک نمی‌شوند.")) return;
                      void run(async () => {
                        const res = await api.adminDeleteServer(s.id);
                        applyResult(res);
                      });
                    }}
                  >
                    حذف
                  </TgButton>
                </div>
              )}
            </div>

            <ServerConfigEditor
              server={s}
              configTypes={configTypes}
              busy={busy || acting}
              onSaved={(res, msg) => {
                applyResult(res);
                setMessage(msg);
              }}
            />
          </div>
        ))}
      </div>

      <div className="space-y-2 border-t border-white/10 pt-3">
        <p className="text-[11px] font-semibold text-neutral-300">افزودن سرور کشور جدید</p>
        {(
          [
            ["name", "نام (مثلاً آلمان)", false],
            ["country_code", "کد روی کانفیگ (DE)", true],
            ["xui_base_url", "آدرس پنل 3x-ui", true],
            ["xui_api_token", "توکن API", true],
            ["inbound_ids", "شناسه اینباندها (1,2,3)", true],
            ["public_host", "دامنه عمومی", true],
            ["public_ip", "آی‌پی عمومی", true],
          ] as const
        ).map(([key, label, ltr]) => (
          <div key={key} className="space-y-1">
            <Label className="text-[10px] text-neutral-500">{label}</Label>
            <Input
              value={draft[key]}
              onChange={(e) => setDraft((d) => ({ ...d, [key]: e.target.value }))}
              dir={ltr ? "ltr" : "rtl"}
              className={cn("h-9 rounded-lg border-white/15 bg-black/40 text-sm", ltr && "font-mono")}
            />
          </div>
        ))}
        <TgButton
          disabled={acting || busy || !draft.name.trim() || !draft.xui_base_url.trim() || !draft.xui_api_token.trim()}
          className="h-10"
          onClick={() =>
            void run(async () => {
              const res = await api.adminAddServer(draft);
              applyResult(res);
              setDraft(emptyDraft);
              setMessage("سرور اضافه شد. همگام‌سازی را بزنید تا کاربران فعلی هم روی این سرور ساخته شوند.");
            })
          }
        >
          اتصال و ذخیره
        </TgButton>
      </div>

      {message && <p className="text-[11px] leading-relaxed text-neutral-400">{message}</p>}
      {extras.length === 0 && !loading && (
        <p className="text-[11px] text-neutral-500">هنوز سرور اضافه‌ای ندارید — فقط سرور اصلی فعال است.</p>
      )}
    </div>
  );
}
