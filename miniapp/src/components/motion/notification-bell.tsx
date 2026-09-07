"use client";

import { useEffect, useRef } from "react";
import type { ComponentProps, ReactNode } from "react";
import { Slot, Slottable } from "@radix-ui/react-slot";
import {
  animate,
  AnimatePresence,
  motion,
  useMotionValue,
  useReducedMotion,
  useSpring,
  useTransform,
  useVelocity,
  type AnimationPlaybackControls,
  type MotionValue,
} from "motion/react";
import { cn } from "@/lib/utils";

const SURFACE = "bg-[#F4F4F9] dark:bg-[#262626]";
const GLYPH = "text-[#868593] dark:text-[#9B9AA7]";

const COLORS = {
  red: "bg-[#FF3B30] dark:bg-[#FF453A]",
  orange: "bg-[#FF9500] dark:bg-[#FF9F0A]",
  green: "bg-[#34C759] dark:bg-[#30D158]",
  blue: "bg-[#007AFF] dark:bg-[#0A84FF]",
  violet: "bg-[#AF52DE] dark:bg-[#BF5AF2]",
} as const;

const ICON = 0.56;
const BADGE = 0.38;
const DOT = 0.22;
const FONT = 0.21;
const PAD = 0.09;
const ORBIT = 0.9;

const SWING_SPRING = {
  type: "spring",
  stiffness: 220,
  damping: 10,
  mass: 1,
  restDelta: 0.01,
} as const;
const CLAPPER_SPRING = { stiffness: 300, damping: 14, mass: 1 };
const COLUMN_SPRING = { stiffness: 400, damping: 30, mass: 0.9 };
const ENTER_SPRING = { type: "spring", stiffness: 600, damping: 20 } as const;
const FADE = { duration: 0.15 } as const;

const IMPULSE = 500;
const MAX_VELOCITY = 900;
const BURST = 5;
const CLAPPER_SWEEP = 13;
const CLAPPER_VELOCITY = 450;
const WINDOW = 3;
const LAG = 2;
const ROLL_FADE = 34;
const ROLL_VELOCITY = 9;

const clamp = (value: number, limit: number) =>
  Math.max(-limit, Math.min(limit, value));

const digitOf = (value: number) => ((value % 10) + 10) % 10;

function badgeMetrics(size: number, dot: boolean) {
  const side = size * (dot ? DOT : BADGE);
  return {
    side,
    inset: size / 2 - (ORBIT * size * Math.SQRT1_2) / 2 - side / 2,
  };
}

function useBellRing(total: number, reduced: boolean) {
  const swing = useMotionValue(0);
  const swingVelocity = useVelocity(swing);
  const clapperLag = useTransform(
    swingVelocity,
    [-CLAPPER_VELOCITY, 0, CLAPPER_VELOCITY],
    [CLAPPER_SWEEP, 0, -CLAPPER_SWEEP],
    { clamp: true },
  );
  const clapper = useSpring(clapperLag, CLAPPER_SPRING);
  const previous = useRef(total);
  const ringing = useRef<AnimationPlaybackControls | null>(null);

  useEffect(() => {
    const delta = total - previous.current;
    previous.current = total;
    if (delta <= 0 || reduced) return;

    const weight = 0.7 + (0.6 * Math.min(delta, BURST)) / BURST;
    const moving = swing.getVelocity();
    const along = moving > 1 ? 1 : -1;

    ringing.current = animate(swing, 0, {
      ...SWING_SPRING,
      velocity: clamp(moving + along * IMPULSE * weight, MAX_VELOCITY),
    });
  }, [total, reduced, swing]);

  useEffect(() => () => ringing.current?.stop(), []);

  return { swing, clapper };
}

function BellIcon({
  side,
  swing,
  clapper,
}: {
  side: number;
  swing: MotionValue<number>;
  clapper: MotionValue<number>;
}) {
  return (
    <motion.svg
      viewBox="0 0 18 18"
      fill="currentColor"
      aria-hidden
      width={side}
      height={side}
      style={{ rotate: swing, transformOrigin: "50% 12%" }}
    >
      <path
        fillRule="evenodd"
        clipRule="evenodd"
        fillOpacity={0.55}
        d="M3.5 6.5C3.5 3.46279 5.96279 1 9 1C12.0372 1 14.5 3.46279 14.5 6.5V10.75C14.5 11.4408 15.0592 12 15.75 12C16.1642 12 16.5 12.3358 16.5 12.75C16.5 13.1642 16.1642 13.5 15.75 13.5H2.25C1.83579 13.5 1.5 13.1642 1.5 12.75C1.5 12.3358 1.83579 12 2.25 12C2.94079 12 3.5 11.4408 3.5 10.75V6.5Z"
      />
      <motion.path
        style={{
          rotate: clapper,
          transformBox: "fill-box",
          transformOrigin: "50% 0%",
        }}
        d="M10.2 15H7.80099C7.64999 15 7.50799 15.068 7.41299 15.185C7.31799 15.302 7.28099 15.456 7.31199 15.603C7.48499 16.425 8.17999 17 9.00099 17C9.82199 17 10.517 16.425 10.69 15.603C10.721 15.456 10.684 15.302 10.589 15.185C10.494 15.068 10.351 15 10.2 15Z"
      />
    </motion.svg>
  );
}

function DigitColumn({ value, reduced }: { value: number; reduced: boolean }) {
  const position = useSpring(value, COLUMN_SPRING);
  const y = useTransform(position, (p) => `${-p * 100}%`);
  const velocity = useVelocity(position);
  const mask = useTransform(velocity, (v) => {
    const fade = Math.min(ROLL_FADE, (Math.abs(v) / ROLL_VELOCITY) * ROLL_FADE);
    return `linear-gradient(to bottom, transparent 0%, #000 ${fade}%, #000 ${100 - fade}%, transparent 100%)`;
  });

  useEffect(() => {
    const gap = value - position.get();
    if (Math.abs(gap) > LAG) position.jump(value - Math.sign(gap) * LAG);
    if (reduced) position.jump(value);
    else position.set(value);
  }, [value, reduced, position]);

  return (
    <motion.span
      className="relative inline-block h-[1em] overflow-hidden"
      style={{
        width: "1ch",
        maskImage: reduced ? undefined : mask,
        WebkitMaskImage: reduced ? undefined : mask,
      }}
    >
      <motion.span className="absolute inset-0" style={{ y }}>
        {Array.from({ length: WINDOW * 2 + 1 }, (_, i) => {
          const tile = value - WINDOW + i;
          return (
            <span
              key={tile}
              className="absolute inset-x-0 flex justify-center"
              style={{ top: `${tile * 100}%` }}
            >
              {digitOf(tile)}
            </span>
          );
        })}
      </motion.span>
    </motion.span>
  );
}

function CountBadge({
  total,
  max,
  size,
  color,
  dot,
  reduced,
}: {
  total: number;
  max: number;
  size: number;
  color: keyof typeof COLORS;
  dot: boolean;
  reduced: boolean;
}) {
  const { side, inset } = badgeMetrics(size, dot);
  const clamped = total > max;
  const places = clamped ? 0 : String(total).length;

  return (
    <AnimatePresence initial={false}>
      {total > 0 && (
        <motion.span
          key="badge"
          layout={!reduced}
          aria-hidden
          data-keep-dark
          className={cn(
            "pointer-events-none absolute z-10 grid place-items-center rounded-full",
            COLORS[color],
          )}
          style={{
            top: inset,
            insetInlineEnd: inset,
            height: side,
            minWidth: side,
            paddingInline: dot ? 0 : size * PAD,
            fontSize: size * FONT,
          }}
          initial={{ scale: 0, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          exit={{ scale: 0, opacity: 0 }}
          transition={reduced ? FADE : ENTER_SPRING}
        >
          {!dot && (
            <span
              className="flex font-semibold leading-none tracking-tight text-white"
              style={{ fontVariantNumeric: "tabular-nums" }}
            >
              {clamped
                ? `${max}+`
                : Array.from({ length: places }, (_, i) => {
                    const place = places - 1 - i;
                    return (
                      <DigitColumn
                        key={place}
                        value={Math.floor(total / 10 ** place)}
                        reduced={reduced}
                      />
                    );
                  })}
            </span>
          )}
        </motion.span>
      )}
    </AnimatePresence>
  );
}

export type NotificationBellProps = Omit<
  ComponentProps<"button">,
  | "children"
  | "color"
  | "onAnimationStart"
  | "onDrag"
  | "onDragStart"
  | "onDragEnd"
> & {
  count?: number;
  max?: number;
  variant?: "count" | "dot";
  size?: number;
  color?: keyof typeof COLORS;
  asChild?: boolean;
  children?: ReactNode;
  ariaLabel?: string;
};

export function NotificationBell({
  count = 0,
  max = 99,
  variant = "count",
  size = 48,
  color = "red",
  asChild = false,
  className,
  style,
  children,
  ariaLabel,
  ...props
}: NotificationBellProps) {
  const reduced = useReducedMotion() ?? false;
  const total = Number.isFinite(count) ? Math.max(0, Math.floor(count)) : 0;
  const { swing, clapper } = useBellRing(total, reduced);

  const badge = (
    <CountBadge
      total={total}
      max={max}
      size={size}
      color={color}
      dot={variant === "dot"}
      reduced={reduced}
    />
  );

  const label = (
    <span role="status" className="sr-only">
      {ariaLabel ??
        (total > 0 ? `اعلان‌ها، ${total} مورد جدید` : "اعلان‌ها")}
    </span>
  );

  if (asChild) {
    return (
      <Slot
        data-slot="notification-bell"
        className={cn("relative", className)}
        style={style}
        {...props}
      >
        <Slottable>{children}</Slottable>
        {label}
        {badge}
      </Slot>
    );
  }

  return (
    <button
      type="button"
      data-slot="notification-bell"
      className={cn(
        "relative grid place-items-center rounded-full outline-none transition-transform active:scale-90 focus-visible:ring-2 focus-visible:ring-ring motion-reduce:active:scale-100",
        SURFACE,
        GLYPH,
        className,
      )}
      style={{ width: size, height: size, ...style }}
      {...props}
    >
      {label}
      <BellIcon side={size * ICON} swing={swing} clapper={clapper} />
      {badge}
    </button>
  );
}

export default NotificationBell;
