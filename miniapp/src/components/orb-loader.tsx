import { ThinkingOrb, type OrbSize, type OrbState } from "thinking-orbs";
import { useTheme } from "@/lib/theme";
import { cn } from "@/lib/utils";

export type OrbLoaderVariant =
  | "boot"
  | "busy"
  | "dashboard"
  | "invite"
  | "admin"
  | "empty"
  | "upload"
  | "links";

const PRESETS: Record<OrbLoaderVariant, { state: OrbState; size: OrbSize; label: string }> = {
  boot: { state: "connecting", size: 64, label: "در حال آماده‌سازی" },
  busy: { state: "working", size: 20, label: "در حال پردازش" },
  dashboard: { state: "searching", size: 64, label: "بارگذاری داشبورد" },
  invite: { state: "weaving", size: 64, label: "بارگذاری دعوت" },
  admin: { state: "solving", size: 64, label: "بارگذاری ادمین" },
  empty: { state: "breathing", size: 64, label: "خالی" },
  upload: { state: "composing", size: 20, label: "در حال آپلود" },
  links: { state: "shaping", size: 64, label: "دریافت لینک‌ها" },
};

export function OrbLoader({
  variant = "boot",
  state,
  size,
  label,
  className,
  speed,
}: {
  variant?: OrbLoaderVariant;
  state?: OrbState;
  size?: OrbSize;
  label?: string;
  className?: string;
  speed?: number;
}) {
  const preset = PRESETS[variant];
  const { theme } = useTheme();
  return (
    <ThinkingOrb
      state={state ?? preset.state}
      size={size ?? preset.size}
      theme={theme === "light" ? "light" : "dark"}
      speed={speed}
      aria-label={label ?? preset.label}
      className={cn("shrink-0", className)}
    />
  );
}

export function OrbLoaderPanel({
  variant,
  message,
  className,
}: {
  variant: OrbLoaderVariant;
  message?: string;
  className?: string;
}) {
  return (
    <div className={cn("flex flex-col items-center justify-center gap-3 py-8", className)}>
      <OrbLoader variant={variant} />
      {message ? <p className="text-sm text-neutral-400">{message}</p> : null}
    </div>
  );
}
