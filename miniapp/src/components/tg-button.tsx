import { cn } from "@/lib/utils";
import type { ButtonHTMLAttributes, ReactNode } from "react";

type Variant = "primary" | "outline" | "ghost";

const variants: Record<Variant, string> = {
  primary: "bg-primary text-primary-foreground active:opacity-90",
  outline: "border border-border bg-transparent text-foreground active:bg-accent",
  ghost: "bg-transparent text-muted-foreground active:bg-accent active:text-foreground",
};

export function TgButton({
  className,
  variant = "primary",
  children,
  type = "button",
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: Variant; children?: ReactNode }) {
  return (
    <button
      type={type}
      className={cn(
        "inline-flex h-11 w-full items-center justify-center gap-2 rounded-xl px-4 text-sm font-semibold transition-colors",
        "disabled:pointer-events-none disabled:opacity-45",
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
        variants[variant],
        className
      )}
      {...props}
    >
      {children}
    </button>
  );
}
