import { useState, type ReactNode } from "react";
import {
  ChevronDown,
  CircleHelp,
  Gift,
  Link2,
  MessageCircle,
  Shield,
  Smartphone,
  Sparkles,
  Store,
  Wallet,
  Users,
} from "lucide-react";
import { TgSheet } from "@/components/tg-sheet";
import { cn } from "@/lib/utils";

type HelpSectionId = "start" | "apps" | "config" | "features" | "bot" | "faq";

function Accordion({
  id,
  openId,
  onToggle,
  icon,
  title,
  summary,
  children,
}: {
  id: HelpSectionId;
  openId: HelpSectionId | null;
  onToggle: (id: HelpSectionId) => void;
  icon: ReactNode;
  title: string;
  summary: string;
  children: ReactNode;
}) {
  const open = openId === id;
  return (
    <section className="overflow-hidden rounded-2xl border border-white/10 bg-black/30">
      <button
        type="button"
        onClick={() => onToggle(id)}
        className="flex w-full items-start gap-2.5 px-3 py-3 text-start active:bg-white/5"
      >
        <span className="mt-0.5 inline-flex size-8 shrink-0 items-center justify-center rounded-xl border border-white/12 bg-white/5 text-neutral-200">
          {icon}
        </span>
        <span className="min-w-0 flex-1">
          <span className="block text-[13px] font-semibold text-neutral-50">{title}</span>
          <span className="mt-0.5 block text-[11px] leading-relaxed text-neutral-500">{summary}</span>
        </span>
        <ChevronDown
          className={cn(
            "mt-1 size-4 shrink-0 text-neutral-500 transition-transform",
            open && "rotate-180",
          )}
        />
      </button>
      {open ? <div className="space-y-3 border-t border-white/8 px-3 py-3">{children}</div> : null}
    </section>
  );
}

function Step({ n, title, body }: { n: number; title: string; body: string }) {
  return (
    <div className="flex gap-2.5">
      <span className="inline-flex size-6 shrink-0 items-center justify-center rounded-full border border-white/15 bg-white/5 text-[11px] font-bold tabular-nums text-neutral-200">
        {n}
      </span>
      <div className="min-w-0">
        <div className="text-[12px] font-semibold text-neutral-100">{title}</div>
        <p className="mt-0.5 text-[11px] leading-relaxed text-neutral-400">{body}</p>
      </div>
    </div>
  );
}

function AppRow({ name, platforms, hint }: { name: string; platforms: string; hint: string }) {
  return (
    <div className="rounded-xl border border-white/10 bg-black/35 px-3 py-2.5">
      <div className="flex items-center justify-between gap-2">
        <div className="text-[13px] font-semibold text-neutral-50">{name}</div>
        <span className="shrink-0 rounded-md border border-white/10 bg-white/5 px-1.5 py-0.5 text-[10px] text-neutral-400">
          {platforms}
        </span>
      </div>
      <p className="mt-1 text-[11px] leading-relaxed text-neutral-400">{hint}</p>
    </div>
  );
}

function FaqItem({ q, a }: { q: string; a: string }) {
  return (
    <div className="rounded-xl border border-white/8 bg-black/25 px-3 py-2.5">
      <div className="text-[12px] font-semibold text-neutral-100">{q}</div>
      <p className="mt-1 text-[11px] leading-relaxed text-neutral-400">{a}</p>
    </div>
  );
}

function FeatureRow({ icon, title, body }: { icon: ReactNode; title: string; body: string }) {
  return (
    <div className="flex gap-2.5 rounded-xl border border-white/8 bg-black/25 px-3 py-2.5">
      <span className="mt-0.5 text-neutral-300">{icon}</span>
      <div>
        <div className="text-[12px] font-semibold text-neutral-100">{title}</div>
        <p className="mt-0.5 text-[11px] leading-relaxed text-neutral-400">{body}</p>
      </div>
    </div>
  );
}

export function HelpGuideContent({
  shopName = "Black Lines",
  initialSection = null,
}: {
  shopName?: string;
  initialSection?: HelpSectionId | null;
}) {
  const [openId, setOpenId] = useState<HelpSectionId | null>(initialSection);
  const brand = (shopName || "Black Lines").replace(/\s*VPN$/i, "").trim() || "Black Lines";
  const toggle = (id: HelpSectionId) => setOpenId((prev) => (prev === id ? null : id));

  return (
<div className="space-y-2.5 pb-2">
        <div className="px-0.5 pb-0.5">
          <h3 className="text-sm font-semibold text-white">راهنما</h3>
          <p className="mt-0.5 text-[11px] text-neutral-400">
            موضوع را باز کنید — بقیه بسته می‌ماند.
          </p>
        </div>

        <Accordion
          id="start"
          openId={openId}
          onToggle={toggle}
          icon={<Sparkles className="size-4" />}
          title="شروع سریع"
          summary="از خرید تا وصل شدن در چند قدم"
        >
          <Step
            n={1}
            title="خرید از فروشگاه"
            body="در تب فروشگاه یک پلن آماده، پکیج سفارشی یا مصرفی انتخاب کنید و پرداخت را کامل کنید."
          />
          <Step
            n={2}
            title="تایید سفارش"
            body="اگر رسید لازم است تصویر را آپلود کنید. بعد از تایید ادمین، کانفیگ روی داشبورد ظاهر می‌شود."
          />
          <Step
            n={3}
            title="باز کردن کانفیگ"
            body="در داشبورد روی کانفیگ بزنید و لینک Subscription یا بهترین لینک را کپی کنید."
          />
          <Step
            n={4}
            title="وارد کردن در اپ VPN"
            body="یکی از اپ‌های زیر را نصب کنید، Subscription را Add کنید و Connect بزنید."
          />
        </Accordion>

        <Accordion
          id="apps"
          openId={openId}
          onToggle={toggle}
          icon={<Smartphone className="size-4" />}
          title="اپ‌های پیشنهادی"
          summary="کدام برنامه برای گوشی و کامپیوتر"
        >
          <p className="text-[11px] leading-relaxed text-neutral-400">
            لینک Subscription با این اپ‌ها بهترین نتیجه را می‌دهد. لینک تکی (VLESS) هم در بیشترشان کار می‌کند.
          </p>
          <AppRow
            name="V2rayNG"
            platforms="اندروید"
            hint="رایج‌ترین گزینه اندروید. Subscription → + → URL را Paste کنید، سپس Update و Connect."
          />
          <AppRow
            name="V2Box"
            platforms="iOS / مک"
            hint="برای آیفون و مک مناسب است. از بخش Subscription لینک را اضافه کنید."
          />
          <AppRow
            name="Streisand"
            platforms="iOS"
            hint="رابط ساده. لینک Sub یا کانفیگ را Import کنید و پروفایل را فعال کنید."
          />
          <AppRow
            name="Hiddify"
            platforms="اندروید / دسکتاپ"
            hint="چندپلتفرمه. لینک Subscription را وارد کنید تا همه سرورها یکجا بیایند."
          />
          <AppRow
            name="v2rayN / Nekoray"
            platforms="ویندوز"
            hint="لینک Sub را در Subscriptions اضافه کنید یا لینک تکی را Import کنید."
          />
        </Accordion>

        <Accordion
          id="config"
          openId={openId}
          onToggle={toggle}
          icon={<Link2 className="size-4" />}
          title="کانفیگ و Subscription"
          summary="تفاوت لینک‌ها و نحوه استفاده"
        >
          <div className="space-y-2">
            <div className="rounded-xl border border-emerald-500/20 bg-emerald-500/8 px-3 py-2.5">
              <div className="text-[12px] font-semibold text-emerald-100">لینک Subscription (پیشنهادی)</div>
              <p className="mt-1 text-[11px] leading-relaxed text-neutral-300">
                یک آدرس ثابت که لیست کانفیگ‌های فعال را می‌دهد. با آپدیت در اپ، سرورهای جدید/حذف‌شده خودکار اعمال می‌شوند. در جزئیات کانفیگ دکمه «کپی لینک Subscription» را بزنید.
              </p>
            </div>
            <div className="rounded-xl border border-white/10 bg-black/30 px-3 py-2.5">
              <div className="text-[12px] font-semibold text-neutral-100">بهترین لینک (کم‌پینگ)</div>
              <p className="mt-1 text-[11px] leading-relaxed text-neutral-400">
                دکمه «کپی بهترین لینک» همان کانفیگی را کپی می‌کند که الان کم‌ترین پینگ را دارد — برای اتصال سریع مفید است.
              </p>
            </div>
            <div className="rounded-xl border border-white/10 bg-black/30 px-3 py-2.5">
              <div className="text-[12px] font-semibold text-neutral-100">لینک‌های تکی</div>
              <p className="mt-1 text-[11px] leading-relaxed text-neutral-400">
                هر ردیف یک سرور/پروتکل جداست (Reality، WS و …). اگر Sub کار نکرد، لینک تکی را امتحان کنید.
              </p>
            </div>
            <div className="rounded-xl border border-white/10 bg-black/30 px-3 py-2.5">
              <div className="text-[12px] font-semibold text-neutral-100">محدودیت IP و برچسب</div>
              <p className="mt-1 text-[11px] leading-relaxed text-neutral-400">
                تعداد دستگاه مجاز روی هر کانفیگ مشخص است. می‌توانید برای کانفیگ برچسب بگذارید و IPهای متصل را با نام دستگاه (موبایل/لپ‌تاپ) علامت بزنید.
              </p>
            </div>
          </div>
        </Accordion>

        <Accordion
          id="features"
          openId={openId}
          onToggle={toggle}
          icon={<Store className="size-4" />}
          title="امکانات فروشگاه"
          summary="چه چیزهایی در دسترس دارید"
        >
          <FeatureRow
            icon={<Store className="size-3.5" />}
            title="پلن آماده و پکیج سفارشی"
            body="مدت، حجم و تعداد دستگاه را از پلن‌های آماده یا سازنده سفارشی انتخاب کنید."
          />
          <FeatureRow
            icon={<Wallet className="size-3.5" />}
            title="کیف‌پول و تمدید خودکار"
            body="موجودی را شارژ کنید، به کیف‌پول کاربر دیگر منتقل کنید، یا برداشت بزنید. روی کانفیگ می‌توانید تمدید خودکار از کیف‌پول را روشن کنید."
          />
          <FeatureRow
            icon={<ActivityIcon />}
            title="مصرفی ابری و خرید حجم"
            body="پرداخت به‌اندازه مصرف از کیف‌پول، یا خرید فقط ترافیک بدون محدودیت زمان."
          />
          <FeatureRow
            icon={<Users className="size-3.5" />}
            title="خرید برای کس دیگری"
            body="در فروشگاه «برای کس دیگری» را بزن، اسم مشتری را بنویس و خودت پرداخت کن. بعد از تایید، از میز فروش لینک را کپی و برایش بفرست."
          />
          <FeatureRow
            icon={<Store className="size-3.5" />}
            title="میز فروش"
            body="لیست مشتری‌هایت: اسم، چند روز مانده، لینک رفته یا نه. از داشبورد یا پروفایل باز کن؛ کپی، ارسال، تمدید و انتقال یک‌جا است. قیمت نمایندگی جدا ندارد."
          />
          <FeatureRow
            icon={<Users className="size-3.5" />}
            title="پکیج خانواده"
            body="در فروشگاه «خانواده» را بزن. یک پرداخت، چند کانفیگ جدا (والد + فرزند). بعد از تایید همه روی داشبورد توست — هر لینک را به همان نفر بفرست. از کانفیگ والد می‌توانی سایت‌های فرزند را محدود کنی."
          />
          <FeatureRow
            icon={<Gift className="size-3.5" />}
            title="دعوت دوستان"
            body="لینک دعوت بگیرید؛ با خرید دوستانتان پورسانت به کیف‌پول شما می‌آید."
          />
          <FeatureRow
            icon={<Sparkles className="size-3.5" />}
            title="Pro و تخفیف خرید"
            body="عضویت Pro و تخفیف‌هایی که ادمین تنظیم کرده هنگام خرید اعمال می‌شوند. اگر کد تخفیف دارید همان لحظه خرید وارد کنید."
          />
          <FeatureRow
            icon={<Shield className="size-3.5" />}
            title="هشدار مصرف و انقضا"
            body="نزدیک پر شدن ترافیک یا انقضا، از طریق تلگرام یادآوری می‌گیرید."
          />
        </Accordion>

        <Accordion
          id="bot"
          openId={openId}
          onToggle={toggle}
          icon={<MessageCircle className="size-4" />}
          title="ربات تلگرام"
          summary="چطور با بات کار کنید"
        >
          <Step
            n={1}
            title="ورود با /start"
            body="ربات را استارت کنید. اگر تست رایگان فعال باشد، دکمه «دریافت VPN تست» را در ربات یا فروشگاه بزنید. لینک‌ها داخل مینی‌اپ هستند."
          />
          <Step
            n={2}
            title="باز کردن فروشگاه"
            body="از دکمه منو / Shop داخل بات، مینی‌اپ فروشگاه باز می‌شود — خرید و مدیریت کانفیگ آنجا انجام می‌شود."
          />
          <Step
            n={3}
            title="پرداخت و رسید"
            body="بعد از ثبت سفارش، مبلغ را واریز و رسید را در اپ یا چت ارسال کنید تا ادمین تایید کند."
          />
          <Step
            n={4}
            title="پشتیبانی"
            body="از تب گفتگو در مینی‌اپ با پشتیبانی پیام بدهید؛ فایل و تصویر هم قابل ارسال است."
          />
          <div className="rounded-xl border border-amber-500/20 bg-amber-500/8 px-3 py-2.5 text-[11px] leading-relaxed text-amber-100/90">
            نکته: کانفیگ‌ها و وضعیت مصرف همیشه در داشبورد مینی‌اپ به‌روزتر از پیام‌های متنی بات است.
          </div>
        </Accordion>

        <Accordion
          id="faq"
          openId={openId}
          onToggle={toggle}
          icon={<CircleHelp className="size-4" />}
          title="سوالات متداول"
          summary="مشکلات رایج و پاسخ سریع"
        >
          <FaqItem
            q="وصل نمی‌شود / تایم‌اوت می‌دهد"
            a="بهترین لینک را دوباره کپی کنید، Subscription را Update کنید، و چند سرور دیگر را امتحان کنید. اگر همه قطع بودند کمی صبر کنید یا به پشتیبانی پیام دهید."
          />
          <FaqItem
            q="تفاوت Subscription با لینک تکی چیست؟"
            a="Subscription لیست کامل کانفیگ‌های فعال را نگه می‌دارد و با آپدیت عوض می‌شود. لینک تکی فقط همان یک سرور است."
          />
          <FaqItem
            q="محدودیت دستگاه (IP) چیست؟"
            a="هر کانفیگ فقط به تعداد مجاز هم‌زمان وصل می‌شود. اگر بیش از حد وصل شوید اتصال جدید قطع یا محدود می‌شود."
          />
          <FaqItem
            q="چطور تمدید کنم؟"
            a="در جزئیات کانفیگ بخش تمدید را باز کنید، یا از فروشگاه همان پلن را بخرید. با روشن بودن تمدید خودکار، نزدیک انقضا از کیف‌پول کم می‌شود."
          />
          <FaqItem
            q="کیف‌پول چه کاربردی دارد؟"
            a="خرید سریع‌تر، تمدید خودکار، مصرفی ابری، و دریافت پورسانت دعوت. شارژ از بخش کیف‌پول بالای صفحه."
          />
          <FaqItem
            q="پکیج خانواده چطور کار می‌کند؟"
            a="یک پرداخت چند کانفیگ می‌سازد. کانفیگ اول والد است و می‌تواند برای فرزندها محدودیت سایت بگذارد."
          />
          <FaqItem
            q="رسید فرستادم ولی هنوز فعال نشده"
            a="تا تایید ادمین صبر کنید. وضعیت را در اعلان‌ها یا گفتگو ببینید؛ اگر طول کشید در تب گفتگو پیگیری کنید."
          />
        </Accordion>
      </div>
  );
}

export function HelpGuideSheet({
  open,
  onClose,
  shopName = "Black Lines",
  initialSection = "start",
}: {
  open: boolean;
  onClose: () => void;
  shopName?: string;
  initialSection?: HelpSectionId;
}) {
  return (
    <TgSheet open={open} onClose={onClose} title="راهنمای استفاده" description="آموزش و سوالات متداول">
      {open ? <HelpGuideContent shopName={shopName} initialSection={initialSection} /> : null}
    </TgSheet>
  );
}

function ActivityIcon() {
  return (
    <svg viewBox="0 0 24 24" className="size-3.5" fill="none" stroke="currentColor" strokeWidth="2">
      <path d="M22 12h-4l-3 9L9 3l-3 9H2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

/** Compact entry card for dashboard / empty states */
export function HelpGuideCard({ onOpen }: { onOpen: () => void }) {
  return (
    <button
      type="button"
      onClick={onOpen}
      className="flex w-full items-center gap-3 rounded-2xl border border-sky-500/20 bg-sky-500/10 px-3.5 py-3 text-start active:bg-sky-500/12"
    >
      <span className="inline-flex size-10 shrink-0 items-center justify-center rounded-xl border border-sky-500/25 bg-sky-500/15 text-sky-200">
        <CircleHelp className="size-5" />
      </span>
      <span className="min-w-0 flex-1">
        <span className="block text-[13px] font-semibold text-sky-100">راهنمای استفاده</span>
        <span className="mt-0.5 block text-[11px] leading-relaxed text-sky-200/80">
          اپ‌ها، Subscription، امکانات فروشگاه و سوالات متداول
        </span>
      </span>
      <span className="shrink-0 text-[11px] font-medium text-sky-200">باز کردن</span>
    </button>
  );
}
