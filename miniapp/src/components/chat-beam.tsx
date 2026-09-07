import { useEffect, useState, type ReactNode } from "react";
import { BorderBeam } from "border-beam";
import { cn } from "@/lib/utils";

const ROTATE_MS = 2200;

/** One rotating border round on composer — triggered by `roundKey` (tab/thread open or send). */
export function ChatComposerRotateBeam({
  roundKey,
  children,
  className,
}: {
  roundKey: number;
  children: ReactNode;
  className?: string;
}) {
  const [active, setActive] = useState(false);

  useEffect(() => {
    if (roundKey <= 0) return;
    setActive(true);
    const t = window.setTimeout(() => setActive(false), ROTATE_MS);
    return () => window.clearTimeout(t);
  }, [roundKey]);

  if (roundKey <= 0) {
    return <div className={className}>{children}</div>;
  }

  return (
    <BorderBeam
      key={roundKey}
      size="md"
      colorVariant="colorful"
      theme="dark"
      strength={0.72}
      duration={2.2}
      active={active}
      className={cn("rounded-[18px]", className)}
    >
      {children}
    </BorderBeam>
  );
}
