import type { ReactNode } from "react";
import { cn } from "@/lib/utils";

/** FeralUI-style sky/flow field — pure CSS, grayscale, low CPU. */
export function GradientField({ className, children }: { className?: string; children?: ReactNode }) {
  return (
    <div className={cn("relative isolate overflow-hidden bg-background", className)}>
      <div aria-hidden className="pointer-events-none absolute inset-0 z-0 overflow-hidden">
        <div className="feral-blob feral-blob-a" />
        <div className="feral-blob feral-blob-b" />
        <div className="feral-blob feral-blob-c" />
        <div className="feral-veil" />
        <div className="feral-noise" />
      </div>
      {children}
    </div>
  );
}
