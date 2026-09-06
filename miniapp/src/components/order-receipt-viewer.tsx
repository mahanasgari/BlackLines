import { useCallback, useEffect, useState } from "react";
import { Maximize2, RefreshCw } from "lucide-react";
import { api } from "@/api";
import { cn } from "@/lib/utils";
import { TgSheet } from "@/components/tg-sheet";

export function useOrderReceiptUrl(orderId: number | null, enabled: boolean) {
  const [url, setUrl] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [isPdf, setIsPdf] = useState(false);

  const load = useCallback(async () => {
    if (!orderId || !enabled) {
      setUrl(null);
      setError(null);
      setIsPdf(false);
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const { url: blobUrl, isPdf: pdf } = await api.fetchOrderReceiptBlob(orderId);
      setUrl((prev) => {
        if (prev) URL.revokeObjectURL(prev);
        return blobUrl;
      });
      setIsPdf(pdf);
    } catch (e) {
      setUrl((prev) => {
        if (prev) URL.revokeObjectURL(prev);
        return null;
      });
      setError(e instanceof Error ? e.message : "خطا در بارگذاری رسید");
    } finally {
      setLoading(false);
    }
  }, [orderId, enabled]);

  useEffect(() => {
    void load();
    return () => {
      setUrl((prev) => {
        if (prev) URL.revokeObjectURL(prev);
        return null;
      });
    };
  }, [load]);

  return { url, loading, error, isPdf, reload: load };
}

export function OrderReceiptViewer({
  orderId,
  enabled = true,
  className,
}: {
  orderId: number;
  enabled?: boolean;
  className?: string;
}) {
  const { url, loading, error, isPdf, reload } = useOrderReceiptUrl(orderId, enabled);
  const [zoomOpen, setZoomOpen] = useState(false);

  if (loading) {
    return (
      <div className={cn("rounded-xl border border-white/10 bg-black/30 px-3 py-8 text-center text-xs text-neutral-400", className)}>
        در حال بارگذاری رسید…
      </div>
    );
  }

  if (error) {
    return (
      <div className={cn("space-y-2", className)}>
        <div className="rounded-xl border border-red-500/25 bg-red-500/10 px-3 py-3 text-center text-xs text-red-200/90">
          {error}
        </div>
        <button
          type="button"
          onClick={() => void reload()}
          className="inline-flex w-full items-center justify-center gap-1.5 rounded-xl border border-white/12 bg-white/5 py-2 text-xs text-neutral-300 active:bg-white/10"
        >
          <RefreshCw className="size-3.5" />
          تلاش مجدد
        </button>
      </div>
    );
  }

  if (!url) return null;

  if (isPdf) {
    return (
      <div className={cn("rounded-xl border border-white/10 bg-black/30 p-3", className)}>
        <p className="mb-2 text-[11px] text-neutral-400">رسید به صورت PDF است</p>
        <a
          href={url}
          target="_blank"
          rel="noopener noreferrer"
          className="inline-flex w-full items-center justify-center rounded-xl border border-white/15 bg-white/10 py-2.5 text-xs text-white active:bg-white/15"
        >
          باز کردن رسید
        </a>
      </div>
    );
  }

  return (
    <>
      <button
        type="button"
        onClick={() => setZoomOpen(true)}
        className={cn(
          "group relative block w-full overflow-hidden rounded-xl border border-white/12 bg-black/40 active:opacity-90",
          className,
        )}
      >
        <img src={url} alt="رسید پرداخت" className="max-h-64 w-full object-contain" />
        <span className="absolute bottom-2 end-2 inline-flex items-center gap-1 rounded-lg bg-black/60 px-2 py-1 text-[10px] text-neutral-200 backdrop-blur-sm">
          <Maximize2 className="size-3" />
          بزرگ‌نمایی
        </span>
      </button>

      <TgSheet open={zoomOpen} onClose={() => setZoomOpen(false)} title="رسید پرداخت">
        <div className="overflow-auto rounded-xl border border-white/10 bg-black/50 p-2">
          <img src={url} alt="رسید پرداخت" className="mx-auto max-h-[70vh] w-full object-contain" />
        </div>
      </TgSheet>
    </>
  );
}
