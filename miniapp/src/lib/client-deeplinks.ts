/** Deep-link builders to open subscription/config in popular VPN clients. */

export type ClientDeepLink = {
  id: "hiddify" | "v2rayng" | "streisand" | "v2box";
  label: string;
  hint: string;
  href: string;
};

function encodeName(name: string) {
  return encodeURIComponent((name || "BlackLines").trim() || "BlackLines");
}

/** Open via Telegram WebApp when available (leaves miniapp safely). */
export function openExternalUrl(url: string): boolean {
  try {
    const tg = window.Telegram?.WebApp;
    if (tg && typeof tg.openLink === "function") {
      tg.openLink(url);
      return true;
    }
  } catch {
    /* fall through */
  }
  try {
    window.open(url, "_blank", "noopener,noreferrer");
    return true;
  } catch {
    return false;
  }
}

/**
 * Build import deep links for a subscription URL (preferred) or a single share link.
 * Hiddify: https://hiddify.com/app/URL-Scheme/
 * v2rayNG: v2rayng://install-sub|install-config
 */
export function buildClientDeepLinks(opts: {
  subscriptionUrl?: string | null;
  shareLink?: string | null;
  name?: string | null;
}): ClientDeepLink[] {
  const name = encodeName(opts.name || "BlackLines");
  const sub = (opts.subscriptionUrl || "").trim();
  const share = (opts.shareLink || "").trim();
  const out: ClientDeepLink[] = [];

  if (sub) {
    const encSub = encodeURIComponent(sub);
    out.push({
      id: "hiddify",
      label: "Hiddify",
      hint: "پیشنهادی",
      href: `hiddify://import/${sub}#${name}`,
    });
    out.push({
      id: "v2rayng",
      label: "v2rayNG",
      hint: "اندروید",
      href: `v2rayng://install-sub?url=${encSub}`,
    });
    out.push({
      id: "streisand",
      label: "Streisand",
      hint: "آیفون",
      href: `streisand://import/${sub}`,
    });
    out.push({
      id: "v2box",
      label: "V2Box",
      hint: "iOS / Android",
      href: `v2box://install-sub?url=${encSub}`,
    });
    return out;
  }

  if (share) {
    const encShare = encodeURIComponent(share);
    out.push({
      id: "hiddify",
      label: "Hiddify",
      hint: "پیشنهادی",
      href: `hiddify://import/${share}#${name}`,
    });
    out.push({
      id: "v2rayng",
      label: "v2rayNG",
      hint: "اندروید",
      href: `v2rayng://install-config?url=${encShare}`,
    });
    out.push({
      id: "streisand",
      label: "Streisand",
      hint: "آیفون",
      href: `streisand://import/${share}`,
    });
    out.push({
      id: "v2box",
      label: "V2Box",
      hint: "iOS / Android",
      href: `v2box://install-config?url=${encShare}`,
    });
  }

  return out;
}
