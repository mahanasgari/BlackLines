import type { ReactNode } from "react";
import { Gift, Send, User, Users, Wallet } from "lucide-react";
import type { CustomerMeta } from "@/api";
import { cn } from "@/lib/utils";

export const emptyCustomerMeta = (): CustomerMeta => ({
  customer_name: "",
  customer_email: "",
  customer_phone: "",
  customer_telegram_id: "",
});

export function customerMetaPayload(meta: CustomerMeta, enabled: boolean): CustomerMeta | undefined {
  if (!enabled) return undefined;
  const name = meta.customer_name?.trim();
  if (!name) return undefined;
  return {
    customer_name: name,
    customer_email: meta.customer_email?.trim() || undefined,
    customer_phone: meta.customer_phone?.trim() || undefined,
    customer_telegram_id: meta.customer_telegram_id?.trim().replace(/^@/, "") || undefined,
  };
}

export function recipientNameOf(meta: CustomerMeta, enabled: boolean): string | null {
  if (!enabled) return null;
  return meta.customer_name?.trim() || null;
}

export function isBuyForOthersComplete(enabled: boolean, meta: CustomerMeta): boolean {
  return !enabled || Boolean(meta.customer_name?.trim());
}

export function BuyForOthersPanel({
  enabled,
  onEnabledChange,
  value,
  onChange,
  disabled,
  error,
}: {
  enabled: boolean;
  onEnabledChange: (v: boolean) => void;
  value: CustomerMeta;
  onChange: (next: CustomerMeta) => void;
  disabled?: boolean;
  error?: string | null;
}) {
  const set = (key: keyof CustomerMeta, raw: string) => {
    onChange({ ...value, [key]: raw });
  };
  const name = value.customer_name?.trim() || "";

  return (
    <section className="space-y-3 rounded-2xl border border-white/12 bg-black/35 p-3.5">
      <div>
        <h3 className="text-sm font-semibold text-white">این کانفیگ مال کیه؟</h3>
        <p className="mt-0.5 text-[11px] leading-relaxed text-neutral-400">
          اول مشخص کن برای خودت می‌خری یا برای کس دیگری.
        </p>
      </div>

      <div className="grid grid-cols-2 gap-1 rounded-xl border border-white/10 bg-black/40 p-1">
        <button
          type="button"
          disabled={disabled}
          onClick={() => onEnabledChange(false)}
          className={cn(
            "flex h-10 items-center justify-center gap-1.5 rounded-lg text-[12px] font-semibold disabled:opacity-50",
            !enabled ? "bg-white text-black" : "text-neutral-400 active:bg-white/8",
          )}
        >
          <User className="size-3.5" />
          برای خودم
        </button>
        <button
          type="button"
          disabled={disabled}
          onClick={() => onEnabledChange(true)}
          className={cn(
            "flex h-10 items-center justify-center gap-1.5 rounded-lg text-[12px] font-semibold disabled:opacity-50",
            enabled ? "bg-white text-black" : "text-neutral-400 active:bg-white/8",
          )}
        >
          <Gift className="size-3.5" />
          برای کس دیگری
        </button>
      </div>

      {!enabled ? (
        <p className="text-[11px] leading-relaxed text-neutral-500">
          کانفیگ روی همین حساب ساخته می‌شود و لینک‌ها مال خودت است.
        </p>
      ) : (
        <div className="space-y-3">
          <ol className="space-y-2 rounded-xl border border-teal-500/20 bg-teal-500/8 px-3 py-2.5">
            <Step n={1} icon={<Users className="size-3.5" />} text="اسم مشتری را بنویس تا بعداً پیدایش کنی" />
            <Step n={2} icon={<Wallet className="size-3.5" />} text="خودت پرداخت می‌کنی — مشتری پولی نمی‌دهد" />
            <Step n={3} icon={<Send className="size-3.5" />} text="بعد از تایید، از میز فروش لینک را کپی کن و برایش بفرست" />
          </ol>

          <div className="space-y-2">
            <Field
              label="نام مشتری"
              required
              value={value.customer_name || ""}
              onChange={(v) => set("customer_name", v)}
              placeholder="مثلاً علی رضایی"
              disabled={disabled}
              invalid={Boolean(error) && !name}
            />
            <Field
              label="موبایل (اختیاری)"
              value={value.customer_phone || ""}
              onChange={(v) => set("customer_phone", v)}
              placeholder="0912…"
              dir="ltr"
              inputMode="tel"
              disabled={disabled}
            />
            <Field
              label="تلگرام (اختیاری)"
              value={value.customer_telegram_id || ""}
              onChange={(v) => set("customer_telegram_id", v)}
              placeholder="@username یا عدد"
              dir="ltr"
              disabled={disabled}
            />
            <Field
              label="ایمیل (اختیاری)"
              value={value.customer_email || ""}
              onChange={(v) => set("customer_email", v)}
              placeholder="customer@email.com"
              dir="ltr"
              inputMode="email"
              disabled={disabled}
            />
          </div>

          {error ? (
            <p className="text-[11px] text-red-300">{error}</p>
          ) : name ? (
            <div className="rounded-xl border border-white/10 bg-white/5 px-3 py-2.5">
              <div className="text-[10px] text-neutral-500">الان می‌خری برای</div>
              <div className="mt-0.5 text-sm font-semibold text-white">{name}</div>
              <p className="mt-1 text-[11px] leading-relaxed text-neutral-400">
                کانفیگ مال حساب تو می‌ماند. مشتری فقط لینکی را می‌گیرد که بعداً برایش می‌فرستی.
              </p>
            </div>
          ) : (
            <p className="text-[11px] text-amber-200/90">برای ادامه، حداقل نام مشتری لازم است.</p>
          )}
        </div>
      )}
    </section>
  );
}

export function RecipientCheckoutBanner({ name }: { name: string }) {
  return (
    <div className="rounded-xl border border-teal-500/25 bg-teal-500/10 px-3.5 py-3 text-right">
      <div className="text-[10px] text-teal-200/80">این سفارش برای مشتری است</div>
      <div className="mt-0.5 text-sm font-semibold text-white">{name}</div>
      <p className="mt-1 text-[11px] leading-relaxed text-neutral-300">
        بعد از تایید ادمین، کانفیگ روی میز فروش شما ظاهر می‌شود. همان‌جا لینک را کپی کنید و برای {name} بفرستید.
      </p>
    </div>
  );
}

function Step({ n, icon, text }: { n: number; icon: ReactNode; text: string }) {
  return (
    <li className="flex items-start gap-2 text-[11px] leading-relaxed text-neutral-200">
      <span className="mt-px inline-flex size-5 shrink-0 items-center justify-center rounded-full border border-teal-400/30 bg-teal-500/15 text-[10px] font-bold tabular-nums">
        {n}
      </span>
      <span className="mt-0.5 text-teal-100/80">{icon}</span>
      <span className="min-w-0">{text}</span>
    </li>
  );
}

function Field({
  label,
  value,
  onChange,
  placeholder,
  dir,
  inputMode,
  disabled,
  required,
  invalid,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
  dir?: "ltr" | "rtl";
  inputMode?: "tel" | "text" | "email";
  disabled?: boolean;
  required?: boolean;
  invalid?: boolean;
}) {
  return (
    <label className="block space-y-1">
      <span className="text-[10px] text-neutral-500">
        {label}
        {required ? <span className="text-amber-300"> *</span> : null}
      </span>
      <input
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        dir={dir}
        inputMode={inputMode}
        disabled={disabled}
        className={cn(
          "w-full rounded-xl border bg-black/40 px-3 py-2.5 text-sm text-white outline-none placeholder:text-neutral-600 disabled:opacity-50",
          invalid ? "border-red-400/50 focus:border-red-300/70" : "border-white/12 focus:border-white/25",
        )}
      />
    </label>
  );
}
