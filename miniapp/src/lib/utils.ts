import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function faNum(n: number): string {
  return Math.round(n).toLocaleString("fa-IR");
}

/** Group digits with commas for amount fields (800,000). */
export function formatAmountInput(n: number): string {
  if (!n || n <= 0) return "";
  return Math.round(n).toLocaleString("en-US");
}

/** Parse a typed amount; keeps only digits (ASCII or Persian). */
export function parseAmountInput(raw: string): number {
  const mapped = raw
    .replace(/[۰-۹]/g, (d) => String("۰۱۲۳۴۵۶۷۸۹".indexOf(d)))
    .replace(/[٠-٩]/g, (d) => String("٠١٢٣٤٥٦٧٨٩".indexOf(d)))
    .replace(/\D/g, "");
  return mapped ? Number(mapped) : 0;
}
