import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from "react";

export type Theme = "light" | "dark";

const STORAGE_KEY = "black-lines-theme";
const LIGHT_BG = "#f0eee8";
const DARK_BG = "#050505";

function readStoredTheme(): Theme | null {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw === "light" || raw === "dark") return raw;
  } catch {
    /* private mode */
  }
  return null;
}

function detectTheme(): Theme {
  const stored = readStoredTheme();
  if (stored) return stored;
  const tg = window.Telegram?.WebApp?.colorScheme;
  if (tg === "light" || tg === "dark") return tg;
  if (window.matchMedia?.("(prefers-color-scheme: light)").matches) return "light";
  return "dark";
}

export function applyTheme(theme: Theme) {
  const root = document.documentElement;
  root.classList.toggle("dark", theme === "dark");
  root.classList.toggle("light", theme === "light");
  root.setAttribute("data-theme", theme);
  root.style.colorScheme = theme;
  const color = theme === "light" ? LIGHT_BG : DARK_BG;
  try {
    window.Telegram?.WebApp?.setHeaderColor?.(color);
    window.Telegram?.WebApp?.setBackgroundColor?.(color);
  } catch {
    /* older clients */
  }
}

export function getInitialTheme(): Theme {
  if (typeof document === "undefined") return "dark";
  if (document.documentElement.classList.contains("light")) return "light";
  if (document.documentElement.classList.contains("dark")) return "dark";
  return detectTheme();
}

type ThemeContextValue = {
  theme: Theme;
  setTheme: (theme: Theme) => void;
  toggleTheme: () => void;
};

const ThemeContext = createContext<ThemeContextValue | null>(null);

export function ThemeProvider({ children }: { children: ReactNode }) {
  const [theme, setThemeState] = useState<Theme>(getInitialTheme);

  useEffect(() => {
    applyTheme(theme);
    try {
      localStorage.setItem(STORAGE_KEY, theme);
    } catch {
      /* ignore */
    }
  }, [theme]);

  const value = useMemo<ThemeContextValue>(
    () => ({
      theme,
      setTheme: setThemeState,
      toggleTheme: () => setThemeState((t) => (t === "dark" ? "light" : "dark")),
    }),
    [theme],
  );

  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}

export function useTheme() {
  const ctx = useContext(ThemeContext);
  if (!ctx) {
    return {
      theme: getInitialTheme(),
      setTheme: () => undefined,
      toggleTheme: () => undefined,
    };
  }
  return ctx;
}
