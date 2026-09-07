import { useEffect, useState } from "react";
import { Check, Copy, KeyRound, RefreshCw, Stethoscope, WifiOff } from "lucide-react";
import { api, haptic, type SubscriptionDiagnose } from "@/api";
import { TgButton } from "@/components/tg-button";
import { TgSheet } from "@/components/tg-sheet";
import { cn, faNum } from "@/lib/utils";

async function copyText(text: string) {
  try {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(text);
      haptic();
      return true;
    }
  } catch {
    /* ignore */
  }
  return false;
}

export function SelfFixSheet({
  open,
  onClose,
  subId,
  onRenew,
  onRotated,
}: {
  open: boolean;
  onClose: () => void;
  subId: number | null;
  onRenew?: () => void;
  onRotated?: (subscriptionUrl: string | null) => void;
}) {
  const [data, setData] = useState<SubscriptionDiagnose | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [copied, setCopied] = useState<string | null>(null);

  const run = async () => {
    if (!subId) return;
    setLoading(true);
    setError(null);
    try {
      setData(await api.diagnoseSubscription(subId));
    } catch (e) {
      setError(e instanceof Error ? e.message : "تست ناموفق بود");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (!open || !subId) {
      setData(null);
      setError(null);
      return;
    }
    void run();
  }, [open, subId]);

  const flash = (key: string) => {
    setCopied(key);
    window.setTimeout(() => setCopied(null), 1600);
  };

  const rotate = async () => {
    if (!subId) return;
    setBusy(true);
    try {
      const res = await api.rotateSubscriptionLink(subId);
      haptic();
      onRotated?.(res.subscription_url);
      if (res.subscription_url) {
        const ok = await copyText(res.subscription_url);
        if (ok) flash("sub");
      }
      setData(await api.diagnoseSubscription(subId));
    } catch (e) {
      setError(e instanceof Error ? e.message : "ساخت لینک جدید ناموفق بود");
    } finally {
      setBusy(false);
    }
  };

  return (
    <TgSheet open={open} onClose={onClose} title="وصل نمیشه؟" layer={160}>
      <div className="space-y-3">
        <p className="text-[11px] leading-relaxed text-neutral-400">
          سرورها را دوباره تست می‌کنیم و می‌گوییم قدم بعدی چیست — معمولاً بدون پشتیبانی حل می‌شود.
        </p>
        {loading ? (
          <p className="py-8 text-center text-sm text-neutral-400">در حال تست سرورها…</p>
        ) : null}
        {error ? (
          <p className="rounded-xl border border-red-500/25 bg-red-500/10 px-3 py-2 text-[12px] text-red-200">{error}</p>
        ) : null}
        {data && !loading ? (
          <>
            <div className="grid grid-cols-3 gap-1.5">
              <div className="rounded-xl border border-white/10 bg-black/30 px-2 py-2 text-center">
                <div className="text-[15px] font-bold tabular-nums text-emerald-200">{faNum(data.reachable_count)}</div>
                <div className="text-[9px] text-neutral-500">سرور سالم</div>
              </div>
              <div className="rounded-xl border border-white/10 bg-black/30 px-2 py-2 text-center">
                <div className="text-[15px] font-bold tabular-nums">{faNum(data.server_count)}</div>
                <div className="text-[9px] text-neutral-500">کل سرور</div>
              </div>
              <div className="rounded-xl border border-white/10 bg-black/30 px-2 py-2 text-center">
                <div className="text-[15px] font-bold tabular-nums text-sky-200">
                  {data.best?.ping_ms != null ? `${faNum(data.best.ping_ms)}ms` : "—"}
                </div>
                <div className="text-[9px] text-neutral-500">بهترین پینگ</div>
              </div>
            </div>

            <div className="space-y-2">
              {data.issues.map((issue) => (
                <div
                  key={issue.code}
                  className={cn(
                    "rounded-xl border px-3 py-2.5",
                    issue.code === "ok"
                      ? "border-emerald-500/25 bg-emerald-500/10"
                      : "border-amber-400/25 bg-amber-500/10",
                  )}
                >
                  <div className="flex items-start gap-2">
                    {issue.code === "ok" ? (
                      <Check className="mt-0.5 size-4 shrink-0 text-emerald-300" />
                    ) : (
                      <WifiOff className="mt-0.5 size-4 shrink-0 text-amber-200" />
                    )}
                    <div>
                      <div className="text-[13px] font-semibold text-neutral-50">{issue.title}</div>
                      <p className="mt-1 text-[11px] leading-relaxed text-neutral-300">{issue.hint}</p>
                    </div>
                  </div>
                </div>
              ))}
            </div>

            {data.best ? (
              <div className="rounded-xl border border-white/10 bg-black/30 px-3 py-2.5">
                <div className="text-[11px] text-neutral-500">بهترین سرور الان</div>
                <div className="mt-0.5 truncate text-[13px] font-medium text-neutral-100">{data.best.label}</div>
                {data.best.host ? (
                  <div className="truncate font-mono text-[10px] text-neutral-500" dir="ltr">
                    {data.best.host}:{data.best.port}
                  </div>
                ) : null}
              </div>
            ) : null}

            <div className="grid grid-cols-2 gap-2">
              {data.subscription_url ? (
                <TgButton
                  variant="outline"
                  className="h-10 text-xs"
                  onClick={() =>
                    void copyText(data.subscription_url!).then((ok) => ok && flash("sub"))
                  }
                >
                  {copied === "sub" ? <Check className="size-3.5" /> : <Copy className="size-3.5" />}
                  کپی Subscription
                </TgButton>
              ) : null}
              {data.best ? (
                <TgButton
                  variant="outline"
                  className="h-10 text-xs"
                  onClick={() => void copyText(data.best!.link).then((ok) => ok && flash("best"))}
                >
                  {copied === "best" ? <Check className="size-3.5" /> : <Copy className="size-3.5" />}
                  کپی بهترین سرور
                </TgButton>
              ) : null}
            </div>

            <div className="grid grid-cols-2 gap-2">
              <TgButton variant="outline" className="h-10 text-xs" disabled={loading || busy} onClick={() => void run()}>
                <RefreshCw className="size-3.5" />
                تست دوباره
              </TgButton>
              {data.can_rotate ? (
                <TgButton className="h-10 text-xs" disabled={busy} onClick={() => void rotate()}>
                  <KeyRound className="size-3.5" />
                  {busy ? "در حال ساخت…" : "لینک جدید"}
                </TgButton>
              ) : (
                <TgButton
                  className="h-10 text-xs"
                  onClick={() => {
                    onRenew?.();
                    onClose();
                  }}
                >
                  تمدید
                </TgButton>
              )}
            </div>
          </>
        ) : null}
        {!loading && !data && !error ? (
          <div className="flex justify-center py-6">
            <Stethoscope className="size-6 text-neutral-500" />
          </div>
        ) : null}
      </div>
    </TgSheet>
  );
}
