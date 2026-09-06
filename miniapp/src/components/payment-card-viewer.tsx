"use client";

import { Check, Copy, Eye, EyeOff, RotateCcw } from "lucide-react";
import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import { useRef, useState, type PointerEvent } from "react";
import { DigitSwap } from "@/components/motion/digit-swap";
import { EASE_OUT, SPRING_PRESS } from "@/lib/ease";
import { cn, faNum } from "@/lib/utils";

export type PaymentCardOption = {
  id: number;
  card: string;
  name: string;
  note?: string;
  label?: string;
};

function formatCardNumber(raw: string) {
  const digits = raw.replace(/\D/g, "");
  return digits.match(/.{1,4}/g)?.join(" ") ?? digits;
}

function maskCardNumber(raw: string) {
  const digits = raw.replace(/\D/g, "");
  const last4 = digits.slice(-4).padStart(4, "•");
  const groups = Math.max(1, Math.ceil(digits.length / 4));
  const masked = Array.from({ length: groups - 1 }, () => "••••").join(" ");
  return masked ? `${masked} ${last4}` : last4;
}

async function writeClipboard(text: string) {
  try {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(text);
      return true;
    }
  } catch {
    /* fallback */
  }
  try {
    const el = document.createElement("textarea");
    el.value = text;
    el.setAttribute("readonly", "");
    el.style.position = "fixed";
    el.style.opacity = "0";
    document.body.appendChild(el);
    el.select();
    const ok = document.execCommand("copy");
    document.body.removeChild(el);
    return ok;
  } catch {
    return false;
  }
}

function CopyChip({
  copied,
  label,
  doneLabel,
  disabled,
  onClick,
}: {
  copied: boolean;
  label: string;
  doneLabel: string;
  disabled?: boolean;
  onClick: () => void;
}) {
  return (
    <motion.button
      type="button"
      disabled={disabled}
      onClick={onClick}
      whileTap={disabled ? undefined : { scale: 0.96 }}
      transition={SPRING_PRESS}
      className={cn(
        "inline-flex h-9 shrink-0 items-center gap-1.5 rounded-lg border px-2.5 text-[11px] font-semibold",
        copied
          ? "border-emerald-400/30 bg-emerald-500/15 text-emerald-200"
          : "border-white/12 bg-white/5 text-neutral-200 active:bg-white/10",
        disabled && "opacity-45",
      )}
    >
      <AnimatePresence initial={false} mode="popLayout">
        <motion.span
          key={copied ? "ok" : "copy"}
          initial={{ opacity: 0, scale: 0.7 }}
          animate={{ opacity: 1, scale: 1 }}
          exit={{ opacity: 0, scale: 0.7 }}
          transition={{ duration: 0.16, ease: EASE_OUT }}
          className="inline-flex items-center gap-1.5"
        >
          {copied ? <Check className="size-3.5" /> : <Copy className="size-3.5" />}
          {copied ? doneLabel : label}
        </motion.span>
      </AnimatePresence>
    </motion.button>
  );
}

export function PaymentCardViewerCarousel({
  cards,
  amountToman,
  orderId,
  disabled,
  onCopy,
  onCopyAmount,
}: {
  cards: PaymentCardOption[];
  amountToman: number;
  orderId: number;
  disabled?: boolean;
  onCopy?: (card: PaymentCardOption) => void;
  onCopyAmount?: (amountToman: number) => void;
}) {
  const reduce = useReducedMotion();
  const [index, setIndex] = useState(0);
  const [flipped, setFlipped] = useState(false);
  const [copied, setCopied] = useState<"card" | "amount" | null>(null);
  const [direction, setDirection] = useState(1);
  const dragX = useRef<number | null>(null);
  const safeIndex = cards.length ? Math.min(index, cards.length - 1) : 0;
  const active = cards[safeIndex];

  if (!active) {
    return (
      <div className="rounded-2xl border border-white/12 bg-white/5 px-4 py-8 text-center text-sm text-neutral-400">
        کارت پرداخت تنظیم نشده است
      </div>
    );
  }

  const digits = active.card.replace(/\D/g, "");
  const formatted = formatCardNumber(digits);
  const masked = maskCardNumber(digits);
  const holderName = active.name?.trim() || "دریافت‌کننده";
  const cardLabel = active.label?.trim() || `کارت ${faNum(safeIndex + 1)}`;

  const flash = (kind: "card" | "amount") => {
    setCopied(kind);
    window.setTimeout(() => setCopied((c) => (c === kind ? null : c)), 1600);
  };

  const copyCard = async () => {
    const ok = await writeClipboard(digits);
    if (ok) {
      onCopy?.(active);
      flash("card");
    }
  };

  const copyAmount = async () => {
    const ok = await writeClipboard(String(amountToman));
    if (ok) {
      onCopyAmount?.(amountToman);
      flash("amount");
    }
  };

  const selectCard = (i: number) => {
    if (i === safeIndex || i < 0 || i >= cards.length) return;
    setDirection(i > safeIndex ? 1 : -1);
    setIndex(i);
    setFlipped(false);
    setCopied(null);
  };

  const onPointerDown = (e: PointerEvent) => {
    dragX.current = e.clientX;
  };

  const onPointerUp = (e: PointerEvent) => {
    if (dragX.current == null || cards.length < 2) {
      dragX.current = null;
      return;
    }
    const dx = e.clientX - dragX.current;
    dragX.current = null;
    if (Math.abs(dx) < 48) return;
    const goingNext = dx < 0;
    selectCard(goingNext ? safeIndex + 1 : safeIndex - 1);
  };

  const slip = (
    <div className="space-y-3 p-3.5">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="text-[10px] text-neutral-500">واریز به این کارت</div>
          <div className="mt-0.5 truncate text-sm font-semibold text-white">{cardLabel}</div>
          <div className="truncate text-[12px] text-neutral-400">به نام {holderName}</div>
        </div>
        <div className="shrink-0 rounded-lg border border-white/10 bg-white/5 px-2 py-1 text-[11px] tabular-nums text-neutral-300">
          #{faNum(orderId)}
        </div>
      </div>

      <div className="flex items-center justify-between gap-2 rounded-xl border border-white/10 bg-white/5 px-3 py-2.5">
        <div className="min-w-0">
          <div className="text-[10px] text-neutral-500">مبلغ قابل پرداخت</div>
          <div className="mt-0.5 text-base font-bold tabular-nums text-white">
            {faNum(amountToman)} تومان
          </div>
        </div>
        <CopyChip
          copied={copied === "amount"}
          label="کپی مبلغ"
          doneLabel="کپی شد"
          disabled={disabled}
          onClick={() => void copyAmount()}
        />
      </div>

      <div className="[perspective:1000px]">
        <motion.div
          animate={{ rotateY: flipped ? 180 : 0 }}
          transition={reduce ? { duration: 0 } : { duration: 0.42, ease: EASE_OUT }}
          className="relative min-h-[6.5rem] [transform-style:preserve-3d]"
        >
          <div className="space-y-2 [backface-visibility:hidden]">
            <div className="flex items-center justify-between gap-2 rounded-xl border border-white/10 bg-black/30 px-3 py-2.5">
              <button
                type="button"
                disabled={disabled}
                onClick={() => setFlipped(true)}
                className="min-w-0 text-start"
              >
                <div className="text-[10px] text-neutral-500">شماره کارت</div>
                <DigitSwap
                  value={masked}
                  animationKey={`mask-${active.id}`}
                  direction="down"
                  suffixLength={4}
                  glyphClassName="text-white/45"
                  suffixClassName="text-white"
                  className="mt-0.5 font-mono text-sm tracking-[0.14em] tabular-nums"
                />
              </button>
              <CopyChip
                copied={copied === "card"}
                label="کپی شماره"
                doneLabel="کپی شد"
                disabled={disabled}
                onClick={() => void copyCard()}
              />
            </div>
            <button
              type="button"
              disabled={disabled}
              onClick={() => setFlipped(true)}
              className="inline-flex items-center gap-1.5 text-[11px] text-neutral-500"
            >
              <Eye className="size-3.5" />
              برای دیدن شماره کامل بزنید
            </button>
          </div>

          <div className="absolute inset-0 space-y-2 [backface-visibility:hidden] [transform:rotateY(180deg)]">
            <div className="flex items-center justify-between gap-2 rounded-xl border border-white/10 bg-black/30 px-3 py-2.5">
              <div className="min-w-0">
                <div className="text-[10px] text-neutral-500">شماره کامل</div>
                <div className="mt-0.5 font-mono text-sm tracking-[0.12em] text-white tabular-nums" dir="ltr">
                  {formatted}
                </div>
              </div>
              <CopyChip
                copied={copied === "card"}
                label="کپی شماره"
                doneLabel="کپی شد"
                disabled={disabled}
                onClick={() => void copyCard()}
              />
            </div>
            <button
              type="button"
              disabled={disabled}
              onClick={() => setFlipped(false)}
              className="inline-flex items-center gap-1.5 text-[11px] text-neutral-500"
            >
              <EyeOff className="size-3.5" />
              مخفی کردن شماره
              <RotateCcw className="size-3" />
            </button>
          </div>
        </motion.div>
      </div>
    </div>
  );

  return (
    <div className="space-y-3">
      {cards.length > 1 ? (
        <div className="flex flex-wrap gap-1.5">
          {cards.map((c, i) => {
            const selected = i === safeIndex;
            return (
              <button
                key={c.id}
                type="button"
                disabled={disabled}
                onClick={() => selectCard(i)}
                className={cn(
                  "h-9 rounded-full border px-3 text-[11px] font-semibold",
                  selected
                    ? "border-white/25 bg-white text-black"
                    : "border-white/12 bg-black/30 text-neutral-400 active:bg-white/10",
                )}
              >
                {c.label?.trim() || c.name?.trim() || `کارت ${faNum(i + 1)}`}
              </button>
            );
          })}
        </div>
      ) : null}

      <div
        className="overflow-hidden rounded-2xl border border-white/12 bg-black/40"
        onPointerDown={onPointerDown}
        onPointerUp={onPointerUp}
      >
        <div className="relative overflow-hidden">
          <AnimatePresence initial={false} mode="popLayout">
            <motion.div
              key={active.id}
              initial={reduce ? { opacity: 0 } : { opacity: 0, x: direction * 32 }}
              animate={{ opacity: 1, x: 0 }}
              exit={reduce ? { opacity: 0 } : { opacity: 0, x: direction * -32 }}
              transition={{ duration: 0.26, ease: EASE_OUT }}
            >
              {slip}
            </motion.div>
          </AnimatePresence>
        </div>

        {cards.length > 1 ? (
          <div className="flex items-center justify-center gap-1.5 border-t border-white/8 py-2.5">
            {cards.map((c, i) => (
              <button
                key={c.id}
                type="button"
                aria-label={`کارت ${faNum(i + 1)}`}
                onClick={() => selectCard(i)}
                className={cn(
                  "h-1.5 rounded-full transition-all",
                  i === safeIndex ? "w-5 bg-white" : "w-1.5 bg-white/25",
                )}
              />
            ))}
          </div>
        ) : null}
      </div>

      {active.note ? (
        <p className="rounded-xl border border-amber-400/20 bg-amber-500/10 px-3 py-2 text-xs leading-relaxed text-amber-100/90">
          {active.note}
        </p>
      ) : null}
    </div>
  );
}
