type TelegramWebApp = NonNullable<NonNullable<Window["Telegram"]>["WebApp"]>;

let viewportBound = false;

function webApp(): TelegramWebApp | undefined {
  return window.Telegram?.WebApp;
}

function exitImmersiveFullscreen(tg: TelegramWebApp) {
  try {
    if (tg.isFullscreen) tg.exitFullscreen?.();
  } catch {
    /* older clients */
  }
}

function syncViewportCss(tg: TelegramWebApp) {
  const root = document.documentElement;
  const height = tg.viewportStableHeight || tg.viewportHeight;
  if (height && height > 0) {
    root.style.setProperty("--app-height", `${Math.round(height)}px`);
  }
  const safe = tg.safeAreaInset;
  const content = tg.contentSafeAreaInset;
  const top = Math.max(safe?.top ?? 0, content?.top ?? 0);
  const bottom = Math.max(safe?.bottom ?? 0, content?.bottom ?? 0);
  if (top) root.style.setProperty("--app-safe-top", `${top}px`);
  if (bottom) root.style.setProperty("--app-safe-bottom", `${bottom}px`);
}

/** Main Mini App from the bot profile opens fullscreen; this shop is built for expanded height. */
export function initTelegramViewport() {
  const tg = webApp();
  if (!tg) return;

  try {
    tg.ready();
    tg.expand();
  } catch {
    /* ignore */
  }
  exitImmersiveFullscreen(tg);
  try {
    tg.disableVerticalSwipes?.();
  } catch {
    /* older clients */
  }
  syncViewportCss(tg);

  if (viewportBound) return;
  viewportBound = true;

  const onViewport = () => {
    exitImmersiveFullscreen(tg);
    syncViewportCss(tg);
  };
  try {
    tg.onEvent?.("viewportChanged", onViewport);
    tg.onEvent?.("fullscreenChanged", onViewport);
    tg.onEvent?.("safeAreaChanged", onViewport);
    tg.onEvent?.("contentSafeAreaChanged", onViewport);
  } catch {
    /* older clients */
  }
}
