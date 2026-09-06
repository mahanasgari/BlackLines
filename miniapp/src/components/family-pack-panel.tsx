import { useEffect, useState, type ReactNode } from "react";
import { Home, Send, Shield, User, Users, Wallet } from "lucide-react";
import { api } from "@/api";
import { cn, faNum } from "@/lib/utils";

export type FamilyPackOptions = {
  enabled: boolean;
  min_size: number;
  max_size: number;
  extra_discount_percent: number;
};

export function familySeatCharge(unit: number, size: number, extraDiscountPercent: number): number {
  const n = Math.max(1, size);
  if (n <= 1) return Math.max(0, unit);
  const extra = Math.max(0, Math.round((unit * (100 - extraDiscountPercent)) / 100));
  return unit + extra * (n - 1);
}

export function FamilyPackPanel({
  familySize,
  onFamilySizeChange,
  disabled,
}: {
  familySize: number;
  onFamilySizeChange: (n: number) => void;
  disabled?: boolean;
}) {
  const [opts, setOpts] = useState<FamilyPackOptions | null>(null);

  useEffect(() => {
    void api
      .growthOptions()
      .then((r) => setOpts(r.family))
      .catch(() => setOpts(null));
  }, []);

  const maxSize = opts?.enabled ? opts.max_size : 1;
  if (!opts?.enabled || maxSize <= 1) return null;

  const enabled = familySize > 1;
  const children = Math.max(0, familySize - 1);

  return (
    <section className="space-y-3 rounded-2xl border border-white/12 bg-black/35 p-3.5">
      <div>
        <h3 className="text-sm font-semibold text-white">چند نفر وصل می‌شوند؟</h3>
        <p className="mt-0.5 text-[11px] leading-relaxed text-neutral-400">
          یک کانفیگ برای خودت، یا چند کانفیگ جدا برای خانواده.
        </p>
      </div>

      <div className="grid grid-cols-2 gap-1 rounded-xl border border-white/10 bg-black/40 p-1">
        <button
          type="button"
          disabled={disabled}
          onClick={() => onFamilySizeChange(1)}
          className={cn(
            "flex h-10 items-center justify-center gap-1.5 rounded-lg text-[12px] font-semibold disabled:opacity-50",
            !enabled ? "bg-white text-black" : "text-neutral-400 active:bg-white/8",
          )}
        >
          <User className="size-3.5" />
          یک نفر
        </button>
        <button
          type="button"
          disabled={disabled}
          onClick={() => onFamilySizeChange(Math.max(2, familySize))}
          className={cn(
            "flex h-10 items-center justify-center gap-1.5 rounded-lg text-[12px] font-semibold disabled:opacity-50",
            enabled ? "bg-white text-black" : "text-neutral-400 active:bg-white/8",
          )}
        >
          <Home className="size-3.5" />
          خانواده
        </button>
      </div>

      {!enabled ? (
        <p className="text-[11px] leading-relaxed text-neutral-500">
          یک کانفیگ ساخته می‌شود و لینک‌ها مال همان نفر است.
        </p>
      ) : (
        <div className="space-y-3">
          <ol className="space-y-2 rounded-xl border border-sky-500/20 bg-sky-500/8 px-3 py-2.5">
            <Step n={1} icon={<Wallet className="size-3.5" />} text="یک‌بار پرداخت می‌کنی — به‌ازای هر نفر یک کانفیگ جدا می‌آید" />
            <Step n={2} icon={<Users className="size-3.5" />} text="اولی والد است، بقیه فرزند — همه روی داشبورد تو می‌مانند" />
            <Step n={3} icon={<Send className="size-3.5" />} text="هر لینک را جدا برای همان نفر بفرست" />
            <Step n={4} icon={<Shield className="size-3.5" />} text="از کانفیگ والد می‌توانی سایت‌های فرزند را محدود کنی" />
          </ol>

          <div className="flex items-center justify-between gap-2 rounded-xl border border-white/10 bg-white/5 px-3 py-2.5">
            <div>
              <div className="text-[12px] font-medium text-neutral-100">تعداد کانفیگ</div>
              <div className="text-[10px] text-neutral-500">
                ۱ والد + {faNum(children)} فرزند
              </div>
            </div>
            <div className="flex items-center gap-1.5">
              <button
                type="button"
                disabled={disabled || familySize <= 2}
                onClick={() => onFamilySizeChange(Math.max(2, familySize - 1))}
                className="inline-flex size-9 items-center justify-center rounded-lg border border-white/15 bg-black/40 text-sm disabled:opacity-40"
              >
                −
              </button>
              <span className="w-7 text-center text-sm font-semibold tabular-nums">{faNum(familySize)}</span>
              <button
                type="button"
                disabled={disabled || familySize >= maxSize}
                onClick={() => onFamilySizeChange(Math.min(maxSize, familySize + 1))}
                className="inline-flex size-9 items-center justify-center rounded-lg border border-white/15 bg-black/40 text-sm disabled:opacity-40"
              >
                +
              </button>
            </div>
          </div>

          <div className="rounded-xl border border-white/10 bg-white/5 px-3 py-2.5">
            <div className="text-[10px] text-neutral-500">بعد از تایید روی داشبورد تو</div>
            <div className="mt-0.5 text-sm font-semibold text-white">
              {faNum(familySize)} کانفیگ جدا · ۱ والد + {faNum(children)} فرزند
            </div>
            <p className="mt-1 text-[11px] leading-relaxed text-neutral-400">
              مبلغ نهایی و هر تخفیف، هنگام خرید محاسبه می‌شود.
            </p>
          </div>
        </div>
      )}
    </section>
  );
}

export function FamilyCheckoutBanner({ size }: { size: number }) {
  if (size <= 1) return null;
  const children = size - 1;
  return (
    <div className="rounded-xl border border-sky-500/25 bg-sky-500/10 px-3.5 py-3 text-right">
      <div className="text-[10px] text-sky-200/80">پکیج خانواده</div>
      <div className="mt-0.5 text-sm font-semibold text-white">
        {faNum(size)} کانفیگ جدا · ۱ والد + {faNum(children)} فرزند
      </div>
      <p className="mt-1 text-[11px] leading-relaxed text-neutral-300">
        بعد از تایید، همه روی داشبورد شما می‌آیند. هر لینک را برای همان نفر بفرستید. از کانفیگ «والد» می‌توانید سایت‌های فرزند را محدود کنید.
      </p>
    </div>
  );
}

function Step({ n, icon, text }: { n: number; icon: ReactNode; text: string }) {
  return (
    <li className="flex items-start gap-2 text-[11px] leading-relaxed text-neutral-200">
      <span className="mt-px inline-flex size-5 shrink-0 items-center justify-center rounded-full border border-sky-400/30 bg-sky-500/15 text-[10px] font-bold tabular-nums">
        {n}
      </span>
      <span className="mt-0.5 text-sky-100/80">{icon}</span>
      <span className="min-w-0">{text}</span>
    </li>
  );
}
