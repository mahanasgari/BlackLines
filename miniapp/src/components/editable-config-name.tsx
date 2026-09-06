import { useEffect, useRef, useState } from "react";
import { Check, Pencil, X } from "lucide-react";
import { cn } from "@/lib/utils";

export function EditableConfigName({
  name,
  onSave,
  disabled,
  className,
  nameClassName,
}: {
  name: string;
  onSave: (label: string) => Promise<void>;
  disabled?: boolean;
  className?: string;
  nameClassName?: string;
}) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(name);
  const [saving, setSaving] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (!editing) setDraft(name);
  }, [name, editing]);

  useEffect(() => {
    if (editing) inputRef.current?.focus();
  }, [editing]);

  const cancel = () => {
    setDraft(name);
    setEditing(false);
  };

  const commit = async () => {
    const next = draft.trim();
    if (next === name.trim()) {
      setEditing(false);
      return;
    }
    setSaving(true);
    try {
      await onSave(next);
      setEditing(false);
    } finally {
      setSaving(false);
    }
  };

  if (editing) {
    return (
      <div className={cn("flex min-w-0 items-center gap-1", className)} onClick={(e) => e.stopPropagation()}>
        <Pencil className="size-3.5 shrink-0 text-sky-300" />
        <input
          ref={inputRef}
          value={draft}
          maxLength={64}
          disabled={saving || disabled}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter") {
              e.preventDefault();
              void commit();
            }
            if (e.key === "Escape") {
              e.preventDefault();
              cancel();
            }
          }}
          aria-label="نام کانفیگ"
          className="h-8 min-w-0 flex-1 rounded-lg border border-white/20 bg-black/50 px-2 text-sm font-semibold text-white outline-none focus:border-sky-400/50"
        />
        <button
          type="button"
          disabled={saving || disabled}
          onClick={() => void commit()}
          aria-label="ذخیره نام"
          className="inline-flex size-7 shrink-0 items-center justify-center rounded-lg border border-white/15 text-emerald-300 active:bg-white/10 disabled:opacity-45"
        >
          <Check className="size-3.5" />
        </button>
        <button
          type="button"
          disabled={saving}
          onClick={cancel}
          aria-label="انصراف"
          className="inline-flex size-7 shrink-0 items-center justify-center rounded-lg border border-white/15 text-neutral-400 active:bg-white/10"
        >
          <X className="size-3.5" />
        </button>
      </div>
    );
  }

  return (
    <div className={cn("flex min-w-0 items-center gap-1.5", className)}>
      <button
        type="button"
        disabled={disabled}
        onClick={(e) => {
          e.stopPropagation();
          setEditing(true);
        }}
        aria-label="ویرایش نام کانفیگ"
        className="inline-flex size-7 shrink-0 items-center justify-center rounded-lg text-neutral-400 active:bg-white/10 active:text-sky-200 disabled:opacity-45"
      >
        <Pencil className="size-3.5" />
      </button>
      <span className={cn("min-w-0 truncate font-semibold text-white", nameClassName)}>{name || "بدون نام"}</span>
    </div>
  );
}
