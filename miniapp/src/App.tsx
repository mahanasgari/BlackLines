import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import {
  Activity,
  Archive,
  Check,
  ChevronDown,
  Copy,
  Gift,
  MessageCircle,
  History,
  Search,
  Shield,
  Store,
  User,
  Wallet,
} from "lucide-react";
import {
  api,
  haptic,
  paymentCardsFrom,
  ApiError,
  type AdminPendingOrder,
  type TrialAccount,
  type CustomBuilderAdminSettings,
  type PaygAdminSettings,
  type TrialSettings,
  type DashboardArchivedItem,
  type DashboardItem,
  type DashboardSummary,
  type Me,
  type PaymentCard,
  type PaymentInfo,
  type ChatMessage,
  type ChatThread,
  type PendingOrder,
  type Plan,
  type ProInfo,
  type Referral,
  type ResellerDeskResponse,
} from "@/api";
import { ProPanel } from "@/components/pro-panel";
import { ProHeaderEntry } from "@/components/pro-header-entry";
import { AdminPendingOrderSheet } from "@/components/admin-pending-order-sheet";
import { AdminPanel } from "@/components/admin-panel";
import { CheckoutPanel } from "@/components/checkout-panel";
import { ChatPanel } from "@/components/chat-panel";
import { cn, faNum, formatAmountInput, parseAmountInput } from "@/lib/utils";
import { useTheme } from "@/lib/theme";
import { GradientField } from "@/components/gradient-field";
import { FilterBar } from "@/components/filter-bar";
import { NotificationBell } from "@/components/motion/notification-bell";
import {
  AdminNotificationCenterSheet,
  UserNotificationCenterSheet,
} from "@/components/notification-center-sheet";
import { ProfilePanel, TrialAccountSheet } from "@/components/profile-sheet";
import { OrderHistorySheet } from "@/components/order-history-sheet";
import { FamilyPackPanel } from "@/components/family-pack-panel";
import { GiftCardsPanel } from "@/components/gift-cards-panel";
import { EditableConfigName } from "@/components/editable-config-name";
import { DashboardConfigList, filterAndGroupDashboardItems } from "@/components/dashboard-config-cards";
import { SubscriptionDetailSheet } from "@/components/subscription-detail-sheet";
import { CustomPackageBuilder } from "@/components/custom-package-builder";
import { PurchaseConfirmPanel, type PurchaseDraft } from "@/components/purchase-confirm-panel";
import { ShopSectionIntro } from "@/components/shop-purchase-options";
import { PaygPackageBuilder } from "@/components/payg-package-builder";
import { PaygTrafficBuilder } from "@/components/payg-traffic-builder";
import { OrbLoader, OrbLoaderPanel } from "@/components/orb-loader";
import { ThemeToggle } from "@/components/theme-toggle";
import { TgButton } from "@/components/tg-button";
import { BottomNavBar } from "@/components/bottom-nav-bar";
import { TgSheet } from "@/components/tg-sheet";
import { ToastHost, useToasts } from "@/components/tg-toast";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/motion/tabs";
import { WalletTransferPanel } from "@/components/wallet-transfer-panel";
import { ResellerDeskEntry, ResellerDeskSheet } from "@/components/reseller-desk-panel";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

type Tab = "shop" | "subs" | "chat" | "invite" | "profile" | "admin";
type Filter = "all" | 30 | 90 | 180;
type ShopSection = "plans" | "custom" | "payg" | "gift";
type PaygShopMode = "cloud" | "traffic";

function Chip({ children }: { children: ReactNode }) {
  return (
    <span className="inline-flex h-6 items-center rounded-lg border border-white/12 bg-white/5 px-2 text-[11px] text-neutral-300">
      {children}
    </span>
  );
}

function remainingDaysHint(expiresAt: string | null | undefined, isPayg?: boolean) {
  if (isPayg && !expiresAt) return "بدون انقضا";
  if (!expiresAt) return "بدون انقضا";
  const days = Math.ceil((new Date(expiresAt).getTime() - Date.now()) / 86_400_000);
  if (days < 0) return "منقضی";
  if (days === 0) return "امروز";
  return `${faNum(days)} روز`;
}

function Panel({
  children,
  className,
  onClick,
}: {
  children: ReactNode;
  className?: string;
  onClick?: () => void;
}) {
  return (
    <div
      className={cn("rounded-2xl border border-white/12 bg-black/45 p-4 backdrop-blur-md", className)}
      onClick={onClick}
      role={onClick ? "button" : undefined}
      tabIndex={onClick ? 0 : undefined}
      onKeyDown={
        onClick
          ? (e) => {
              if (e.key === "Enter" || e.key === " ") {
                e.preventDefault();
                onClick();
              }
            }
          : undefined
      }
    >
      {children}
    </div>
  );
}

async function copyText(text: string): Promise<boolean> {
  try {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(text);
      return true;
    }
  } catch {
    /* fallback below */
  }
  try {
    const el = document.createElement("textarea");
    el.value = text;
    el.setAttribute("readonly", "");
    el.style.position = "fixed";
    el.style.opacity = "0";
    document.body.appendChild(el);
    el.select();
    el.setSelectionRange(0, text.length);
    const ok = document.execCommand("copy");
    document.body.removeChild(el);
    return ok;
  } catch {
    return false;
  }
}

function priceText(toman: number) {
  return `${faNum(toman)} تومان`;
}

function persianError(msg: string) {
  const map: Record<string, string> = {
    "Telegram auth required": "لطفاً مینی‌اپ را از داخل ربات تلگرام باز کنید",
    "plan not found": "پلن پیدا نشد",
    "order not found": "سفارش پیدا نشد",
    "request failed": "خطا در ارتباط با سرور",
    "Bad Request": "ارسال رسید به سرور نرسید. فیلترشکن را خاموش کنید و دوباره بفرستید.",
    "cannot withdraw": "برداشت ممکن نیست — موجودی یا کارت نامعتبر است، یا برداشت قبلی در انتظار است",
    "invalid card": "شماره کارت نامعتبر است",
    "me timed out": "اتصال به سرور طولانی شد — دوباره تلاش کنید",
    "plans timed out": "اتصال به سرور طولانی شد — دوباره تلاش کنید",
  };
  return map[msg] || msg;
}

export default function App() {
  const { theme } = useTheme();
  const [tab, setTab] = useState<Tab>("subs");
  const [filter, setFilter] = useState<Filter>("all");
  const [shopSection, setShopSection] = useState<ShopSection>("plans");
  const [paygMode, setPaygMode] = useState<PaygShopMode>("cloud");
  const [me, setMe] = useState<Me | null>(null);
  const [plans, setPlans] = useState<Plan[]>([]);
  const [dashItems, setDashItems] = useState<DashboardItem[]>([]);
  const [dashArchived, setDashArchived] = useState<DashboardArchivedItem[]>([]);
  const [dashArchiveOpen, setDashArchiveOpen] = useState(false);
  const [dashUsageOpen, setDashUsageOpen] = useState(false);
  const [dashSummary, setDashSummary] = useState<DashboardSummary>({ total: 0, online: 0, offline: 0 });
  const [pendingOrder, setPendingOrder] = useState<PendingOrder | null>(null);
  const [refData, setRefData] = useState<Referral | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [copied, setCopied] = useState<string | null>(null);
  const { toasts, push, dismiss } = useToasts(2);
  const mainRef = useRef<HTMLElement>(null);

  const [checkout, setCheckout] = useState<{
    orderId: number;
    amountLabel: string;
    amountToman: number;
    walletUsed: number;
    payment: PaymentInfo;
    kind?: "plan" | "wallet" | "pro";
    recipientName?: string | null;
    familySize?: number;
  } | null>(null);
  const [purchaseDraft, setPurchaseDraft] = useState<PurchaseDraft | null>(null);
  const [proData, setProData] = useState<ProInfo | null>(null);
  const [configSearch, setConfigSearch] = useState("");
  const [detailSubId, setDetailSubId] = useState<number | null>(null);
  const [detailOpen, setDetailOpen] = useState(false);
  const [detailInitialTab, setDetailInitialTab] = useState<"connect" | "usage" | "renew" | "more" | null>(null);
  const [resellerOpen, setResellerOpen] = useState(false);
  const [resellerDesk, setResellerDesk] = useState<ResellerDeskResponse | null>(null);
  const [rotateConfirmId, setRotateConfirmId] = useState<number | null>(null);
  const [cardInput, setCardInput] = useState("");
  const [walletOpen, setWalletOpen] = useState(false);
  const [depositAmount, setDepositAmount] = useState(100_000);
  const [walletWithdrawCard, setWalletWithdrawCard] = useState("");
  const [walletWithdrawAmount, setWalletWithdrawAmount] = useState(0);
  const [walletTab, setWalletTab] = useState<"deposit" | "transfer" | "withdraw">("deposit");
  const [walletInfo, setWalletInfo] = useState<Awaited<ReturnType<typeof api.wallet>> | null>(null);
  const [adminOrders, setAdminOrders] = useState<Awaited<ReturnType<typeof api.adminPending>>>([]);
  const [adminWds, setAdminWds] = useState<Awaited<ReturnType<typeof api.adminWithdrawals>>>([]);
  const [adminIncludeTest, setAdminIncludeTest] = useState(false);
  const [broadcastText, setBroadcastText] = useState("");
  const [notifOpen, setNotifOpen] = useState(false);
  const [channelGate, setChannelGate] = useState<{
    channel: string;
    inviteUrl: string;
    message: string;
  } | null>(null);
  const [profileFocusHelp, setProfileFocusHelp] = useState(false);
  const [proOpen, setProOpen] = useState(false);
  const [proLoading, setProLoading] = useState(false);
  const [trialAccount, setTrialAccount] = useState<TrialAccount | null>(null);
  const [trialOpen, setTrialOpen] = useState(false);
  const [adminBirthdayGift, setAdminBirthdayGift] = useState<number | null>(null);
  const [adminBirthdayEnabled, setAdminBirthdayEnabled] = useState(false);
  const [adminBirthdayGiftDraft, setAdminBirthdayGiftDraft] = useState("");
  const [adminTrialSettings, setAdminTrialSettings] = useState<TrialSettings | null>(null);
  const [adminTrialDraft, setAdminTrialDraft] = useState({
    enabled: true,
    duration_days: "3",
    traffic_gb: "2",
    limit_ip: "1",
    send_links: false,
  });
  const emptyCustomDraft = {
    enabled: true,
    min_days: "7",
    max_days: "180",
    min_gb: "1",
    max_gb: "500",
    min_ip: "1",
    max_ip: "5",
    base_fee_toman: "30000",
    price_per_day_toman: "3500",
    price_per_gb_toman: "1000",
    unlimited_day_fee_toman: "8000",
    price_per_ip_toman: "20000",
    min_price_toman: "100000",
  };
  const [adminCustomSettings, setAdminCustomSettings] = useState<CustomBuilderAdminSettings | null>(null);
  const [adminCustomDraft, setAdminCustomDraft] = useState(emptyCustomDraft);
  const emptyPaygDraft = {
    enabled: true,
    price_per_gb_toman: "4000",
    prepaid_price_per_gb_toman: "7500",
    min_wallet_toman: "10000",
    limit_ip: "2",
    min_gb: "5",
    max_gb: "200",
    min_ip: "1",
    max_ip: "3",
    price_per_ip_toman: "25000",
    min_price_toman: "40000",
  };
  const [adminPaygSettings, setAdminPaygSettings] = useState<PaygAdminSettings | null>(null);
  const [adminPaygDraft, setAdminPaygDraft] = useState(emptyPaygDraft);
  const [shopFamilySize, setShopFamilySize] = useState(1);
  const [adminOrderDetail, setAdminOrderDetail] = useState<AdminPendingOrder | null>(null);
  const [userNotifLoading, setUserNotifLoading] = useState(false);
  const [userUnreadMessages, setUserUnreadMessages] = useState<ChatMessage[]>([]);
  const [adminNotifLoading, setAdminNotifLoading] = useState(false);
  const [adminUnreadThreads, setAdminUnreadThreads] = useState<ChatThread[]>([]);
  const [openChatThreadUserId, setOpenChatThreadUserId] = useState<number | null>(null);
  const [tabLoading, setTabLoading] = useState(false);
  const [adminPaymentCards, setAdminPaymentCards] = useState<PaymentCard[]>([]);
  const [paymentCardDraft, setPaymentCardDraft] = useState({
    card: "",
    name: "",
    label: "",
    note: "",
  });
  const [chatUnread, setChatUnread] = useState(0);
  const [orderHistoryOpen, setOrderHistoryOpen] = useState(false);
  const [adminOrderHistoryOpen, setAdminOrderHistoryOpen] = useState(false);

  const notify = useCallback(
    (title: string, status: "success" | "error" | "info" = "info") => {
      push(title, status);
      if (status === "success") {
        window.Telegram?.WebApp?.HapticFeedback?.notificationOccurred?.("success");
      } else if (status === "error") {
        window.Telegram?.WebApp?.HapticFeedback?.notificationOccurred?.("error");
      }
    },
    [push]
  );

  const searchAdminUsers = useCallback(async (q: string, includeTest = false, slice = "") => {
    const res = await api.adminUsers(q, includeTest, slice);
    return res.items;
  }, []);

  const refreshAdmin = useCallback(async () => {
    if (!me?.is_admin) return;
    const [o, w, cards] = await Promise.all([
      api.adminPending(adminIncludeTest),
      api.adminWithdrawals(adminIncludeTest),
      api.adminPaymentCards(),
    ]);
    setAdminOrders(o);
    setAdminWds(w);
    setAdminPaymentCards(cards);
  }, [me?.is_admin, adminIncludeTest]);

  const refreshUserNotifs = useCallback(async () => {
    if (me?.is_admin) return;
    const [subs, wallet, chatData] = await Promise.all([
      api.subscriptions(),
      api.wallet(),
      api.chatMessages(0, false),
    ]);
    setPendingOrder(subs.pending || null);
    setWalletInfo(wallet);
    setChatUnread(chatData.unread_count);
    setUserUnreadMessages(
      chatData.messages.filter((m) => m.sender === "admin" && !m.read_at),
    );
  }, [me?.is_admin]);

  const applyDashboard = useCallback((dash: Awaited<ReturnType<typeof api.dashboard>>) => {
    setDashItems(dash.items || []);
    setDashArchived(dash.archived || []);
    setDashSummary(dash.summary || { total: 0, online: 0, offline: 0 });
  }, []);

  const refreshResellerDesk = useCallback(async () => {
    try {
      setResellerDesk(await api.resellerDesk());
    } catch {
      /* optional */
    }
  }, []);

  const handleOrderAction = useCallback(async () => {
    if (me?.is_admin) {
      await refreshAdmin();
    } else {
      await refreshUserNotifs();
    }
    if (tab === "subs") {
      try {
        const [subsData, dash] = await Promise.all([api.subscriptions(), api.dashboard()]);
        setPendingOrder(subsData.pending || null);
        applyDashboard(dash);
      } catch {
        /* optional */
      }
    }
  }, [me?.is_admin, refreshAdmin, refreshUserNotifs, tab, applyDashboard]);

  const openProSheet = useCallback(async () => {
    haptic();
    setProOpen(true);
    if (proData) return;
    setProLoading(true);
    try {
      const data = await api.proInfo();
      setProData(data);
      setMe((m) => (m ? { ...m, is_pro: data.is_pro, pro_until: data.pro_until } : m));
    } catch (e) {
      notify(persianError(e instanceof Error ? e.message : "خطا"), "error");
    } finally {
      setProLoading(false);
    }
  }, [notify, proData]);

  const refreshProData = useCallback(async () => {
    try {
      const data = await api.proInfo();
      setProData(data);
      setMe((m) => (m ? { ...m, is_pro: data.is_pro, pro_until: data.pro_until } : m));
      return data;
    } catch {
      return null;
    }
  }, []);

  const openNotifCenter = useCallback(async () => {
    haptic();
    setNotifOpen(true);
    try {
      if (me?.is_admin) {
        setAdminNotifLoading(true);
        const [, chatData] = await Promise.all([refreshAdmin(), api.adminChatThreads()]);
        setChatUnread(chatData.unread_total);
        setAdminUnreadThreads(chatData.threads.filter((t) => t.unread_count > 0));
      } else {
        setUserNotifLoading(true);
        await refreshUserNotifs();
      }
    } catch (e) {
      notify(persianError(e instanceof Error ? e.message : "خطا"), "error");
    } finally {
      setUserNotifLoading(false);
      setAdminNotifLoading(false);
    }
  }, [me?.is_admin, refreshAdmin, refreshUserNotifs, notify]);

  const sendBroadcast = useCallback(async () => {
    const message = broadcastText.trim();
    if (message.length < 2) return;
    setBusy(true);
    try {
      const res = await api.adminBroadcast(message);
      setBroadcastText("");
      notify(`ارسال شد: ${faNum(res.sent)} از ${faNum(res.total)} کاربر`, "success");
    } catch (e) {
      notify(persianError(e instanceof Error ? e.message : "ارسال ناموفق"), "error");
    } finally {
      setBusy(false);
    }
  }, [broadcastText, notify]);

  const boot = useCallback(async () => {
    const tg = window.Telegram?.WebApp;
    tg?.ready();
    tg?.expand();
    try {
      tg?.disableVerticalSwipes?.();
    } catch {
      /* older clients */
    }

    try {
      setLoading(true);
      setError(null);
      setChannelGate(null);
      const rawInit = window.Telegram?.WebApp?.initData || "";
      if (!rawInit) {
        setError(
          "ورود از تلگرام ممکن نشد. از داخل خود ربات فروشگاه را باز کنید (نه مرورگر).",
        );
        return;
      }
      const bootTimeoutMs = 20_000;
      const withTimeout = <T,>(p: Promise<T>, label: string) =>
        Promise.race([
          p,
          new Promise<T>((_, reject) =>
            window.setTimeout(
              () => reject(new Error(`${label} timed out`)),
              bootTimeoutMs,
            ),
          ),
        ]);
      const [m, p] = await Promise.all([
        withTimeout(api.me(), "me"),
        withTimeout(api.plans(), "plans"),
      ]);
      setMe(m);
      setPlans(p);
      if (m.trial_account?.granted) {
        setTrialAccount(m.trial_account);
        setTrialOpen(true);
      }
    } catch (e) {
      if (e instanceof ApiError && e.code === "channel_required") {
        setChannelGate({
          channel: e.channel || "Blackliness",
          inviteUrl: e.inviteUrl || "https://t.me/Blackliness",
          message: e.message || "برای استفاده از سرویس باید عضو کانال شوید",
        });
        setError(null);
      } else {
        setError(persianError(e instanceof Error ? e.message : "خطا در اتصال"));
      }
    } finally {
      setLoading(false);
    }
  }, []);

  const recheckChannel = useCallback(async () => {
    setBusy(true);
    try {
      const status = await api.channelStatus();
      if (!status.required || status.member) {
        setChannelGate(null);
        await boot();
        return;
      }
      setChannelGate({
        channel: status.channel || "Blackliness",
        inviteUrl: status.invite_url || "https://t.me/Blackliness",
        message: status.message || "هنوز عضو کانال نیستید",
      });
      notify("هنوز عضو کانال نیستید — اول Join کنید", "error");
    } catch (e) {
      notify(persianError(e instanceof Error ? e.message : "خطا"), "error");
    } finally {
      setBusy(false);
    }
  }, [boot, notify]);

  useEffect(() => {
    void boot();
  }, [boot]);

  useEffect(() => {
    if (!me?.is_admin) return;
    void refreshAdmin().catch(() => {
      /* admin prefetch optional */
    });
    void api.adminBirthdayGift().then((r) => {
      setAdminBirthdayGift(r.amount_toman);
      setAdminBirthdayEnabled(Boolean(r.enabled));
      setAdminBirthdayGiftDraft(String(r.amount_toman));
    }).catch(() => {
      /* optional */
    });
    void api.adminTrialSettings().then((r) => {
      setAdminTrialSettings(r);
      setAdminTrialDraft({
        enabled: r.enabled,
        duration_days: String(r.duration_days),
        traffic_gb: String(r.traffic_gb),
        limit_ip: String(r.limit_ip),
        send_links: Boolean(r.send_links),
      });
    }).catch(() => {
      /* optional */
    });
    void api.adminCustomSettings().then((r) => {
      setAdminCustomSettings(r);
      setAdminCustomDraft({
        enabled: r.enabled,
        min_days: String(r.min_days),
        max_days: String(r.max_days),
        min_gb: String(r.min_gb),
        max_gb: String(r.max_gb),
        min_ip: String(r.min_ip),
        max_ip: String(r.max_ip),
        base_fee_toman: String(r.base_fee_toman),
        price_per_day_toman: String(r.price_per_day_toman),
        price_per_gb_toman: String(r.price_per_gb_toman),
        unlimited_day_fee_toman: String(r.unlimited_day_fee_toman),
        price_per_ip_toman: String(r.price_per_ip_toman),
        min_price_toman: String(r.min_price_toman),
      });
    }).catch(() => {
      /* optional */
    });
    void api.adminPaygSettings().then((r) => {
      setAdminPaygSettings(r);
      setAdminPaygDraft({
        enabled: r.enabled,
        price_per_gb_toman: String(r.price_per_gb_toman),
        prepaid_price_per_gb_toman: String(r.prepaid_price_per_gb_toman ?? r.price_per_gb_toman),
        min_wallet_toman: String(r.min_wallet_toman),
        limit_ip: String(r.limit_ip),
        min_gb: String(r.min_gb),
        max_gb: String(r.max_gb),
        min_ip: String(r.min_ip),
        max_ip: String(r.max_ip),
        price_per_ip_toman: String(r.price_per_ip_toman),
        min_price_toman: String(r.min_price_toman),
      });
    }).catch(() => {
      /* optional */
    });
  }, [me?.is_admin, refreshAdmin]);

  useEffect(() => {
    if (!me || me.is_admin) return;
    void refreshUserNotifs().catch(() => {
      /* optional prefetch for user badge */
    });
  }, [me, refreshUserNotifs]);

  useEffect(() => {
    if (!me) return;
    void refreshResellerDesk();
  }, [me?.telegram_id, refreshResellerDesk]);

  useEffect(() => {
    if (!me || me.is_admin) return;
    void refreshProData();
  }, [me?.telegram_id, me?.is_admin, refreshProData]);

  useEffect(() => {
    if (!me || tab === "chat") return;
    let cancelled = false;
    const poll = async () => {
      try {
        if (me.is_admin) {
          const data = await api.adminChatThreads();
          if (!cancelled) setChatUnread(data.unread_total);
        } else {
          const data = await api.chatUnread();
          if (!cancelled) setChatUnread(data.unread_count);
        }
      } catch {
        /* optional background poll */
      }
    };
    void poll();
    const t = window.setInterval(() => void poll(), 12000);
    return () => {
      cancelled = true;
      window.clearInterval(t);
    };
  }, [me, tab]);

  useEffect(() => {
    mainRef.current?.scrollTo({ top: 0 });
  }, [tab, checkout, filter]);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      if (tab !== "subs" && tab !== "invite" && !(tab === "admin" && me?.is_admin)) return;
      setTabLoading(true);
      try {
        if (tab === "subs") {
          const [subsData, dash] = await Promise.all([api.subscriptions(), api.dashboard()]);
          if (!cancelled) {
            setPendingOrder(subsData.pending || null);
            applyDashboard(dash);
          }
        } else if (tab === "invite") {
          const data = await api.referral();
          if (!cancelled) setRefData(data);
        } else if (tab === "admin" && me?.is_admin) {
          const [o, w] = await Promise.all([
            api.adminPending(adminIncludeTest),
            api.adminWithdrawals(adminIncludeTest),
          ]);
          if (!cancelled) {
            setAdminOrders(o);
            setAdminWds(w);
          }
        }
      } catch (e) {
        if (!cancelled) notify(persianError(e instanceof Error ? e.message : "خطا"), "error");
      } finally {
        if (!cancelled) setTabLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
    // notify intentionally omitted — unstable identity caused infinite refetch
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tab, me?.is_admin, adminIncludeTest]);

  const filteredPlans = useMemo(() => {
    if (filter === "all") return plans;
    return plans.filter((p) => {
      if (filter === 30) return p.duration_days <= 31;
      if (filter === 90) return p.duration_days > 31 && p.duration_days <= 93;
      if (filter === 180) return p.duration_days > 93 && p.duration_days <= 186;
      return p.duration_days > 186;
    });
  }, [plans, filter]);

  const copy = async (text: string, opts?: { subId?: number; markShared?: boolean }) => {
    const ok = await copyText(text);
    if (ok) {
      setCopied(text);
      haptic();
      notify("کپی شد", "success");
      window.setTimeout(() => setCopied((c) => (c === text ? null : c)), 1200);
      if (opts?.markShared && opts.subId) {
        void api
          .markLinkShared(opts.subId, true)
          .then(() => refreshResellerDesk())
          .catch(() => undefined);
      }
    } else {
      notify("کپی ممکن نشد — متن را نگه دارید و کپی کنید", "error");
    }
  };

  const renameConfig = async (subId: number, label: string) => {
    try {
      const res = await api.setLabel(subId, label);
      setDashItems((items) => items.map((it) => (it.id === subId ? { ...it, label: res.label } : it)));
      setDashArchived((items) => items.map((it) => (it.id === subId ? { ...it, label: res.label } : it)));
      haptic();
      notify("نام کانفیگ ذخیره شد", "success");
    } catch (e) {
      notify(e instanceof Error ? e.message : "ذخیره نام ناموفق", "error");
      throw e;
    }
  };

  const claimTrial = async () => {
    haptic("medium");
    setBusy(true);
    try {
      const trial = await api.claimTrial();
      setTrialAccount(trial);
      setTrialOpen(true);
      setMe((m) =>
        m
          ? {
              ...m,
              trial_offer: m.trial_offer ? { ...m.trial_offer, available: false } : m.trial_offer,
            }
          : m,
      );
      notify("کانفیگ تست فعال شد", "success");
      await refreshDashboard();
    } catch (e) {
      notify(persianError(e instanceof Error ? e.message : "دریافت تست ناموفق"), "error");
    } finally {
      setBusy(false);
    }
  };

  const buyPro = async () => {
    haptic("medium");
    setBusy(true);
    try {
      const order = await api.proOrder();
      if (typeof order.wallet_balance === "number") {
        setMe((m) => (m ? { ...m, wallet_balance: order.wallet_balance! } : m));
      } else {
        setMe(await api.me());
      }
      if (order.auto_approved) {
        notify("اشتراک Pro فعال شد", "success");
        setCheckout(null);
        void refreshProData();
      } else if (!order.needs_receipt) {
        await api.confirmWallet(order.id);
        notify(order.resumed ? "سفارش Pro قبلی ثبت شد" : "سفارش Pro ثبت شد — منتظر تایید", "success");
        setCheckout(null);
      } else {
        if (order.resumed) notify("سفارش Pro ناتمام قبلی باز شد", "info");
        setCheckout({
          orderId: order.id,
          amountLabel: order.amount_label,
          amountToman: order.amount_toman,
          walletUsed: order.wallet_used,
          payment: order.payment,
          kind: "pro",
        });
        setProOpen(false);
        setTab("shop");
      }
      void refreshProData();
    } catch (e) {
      notify(persianError(e instanceof Error ? e.message : "خرید Pro ناموفق"), "error");
    } finally {
      setBusy(false);
    }
  };

  const startPlanPurchase = (plan: Plan) => {
    haptic("medium");
    setPurchaseDraft({ kind: "plan", plan, familySize: shopFamilySize });
  };

  const confirmPurchase = async (payload: {
    promo_code?: string;
    config_label?: string;
    family_size: number;
    customer?: { customer_name?: string | null; customer_email?: string | null; customer_phone?: string | null; customer_telegram_id?: string | null };
    recipientName: string | null;
  }) => {
    if (!purchaseDraft) return;
    setBusy(true);
    try {
      if (purchaseDraft.kind === "plan") {
        const order = await api.createOrder(purchaseDraft.plan.id, {
          promo_code: payload.promo_code,
          family_size: payload.family_size,
          config_label: payload.config_label,
          gift_card: Boolean(purchaseDraft.giftCard),
          ...payload.customer,
        });
        setPurchaseDraft(null);
        setShopFamilySize(1);
        await completePlanOrder(order, payload.recipientName, payload.family_size);
        return;
      }
      if (purchaseDraft.kind === "custom") {
        const order = await api.customOrder({
          duration_days: purchaseDraft.duration_days,
          traffic_gb: purchaseDraft.traffic_gb,
          limit_ip: purchaseDraft.limit_ip,
          unlimited: purchaseDraft.unlimited,
          promo_code: payload.promo_code,
          family_size: payload.family_size,
          config_label: payload.config_label,
          ...payload.customer,
        });
        setPurchaseDraft(null);
        await completePlanOrder(order, payload.recipientName, payload.family_size);
        return;
      }
      const order = await api.paygOrder({
        traffic_gb: purchaseDraft.traffic_gb,
        limit_ip: purchaseDraft.limit_ip,
        config_label: payload.config_label,
        ...payload.customer,
      });
      setPurchaseDraft(null);
      await completePlanOrder(order, payload.recipientName, 1);
    } catch (e) {
      notify(persianError(e instanceof Error ? e.message : "خرید ناموفق"), "error");
    } finally {
      setBusy(false);
    }
  };

  const completePlanOrder = async (
    order: Awaited<ReturnType<typeof api.createOrder>> & {
      plan_title?: string;
      family_size?: number;
      renew?: boolean;
      auto_approved?: boolean;
    },
    recipientName?: string | null,
    familySize?: number,
  ) => {
    if (typeof order.wallet_balance === "number") {
      setMe((m) => (m ? { ...m, wallet_balance: order.wallet_balance! } : m));
    } else {
      setMe(await api.me());
    }
    const seats = familySize || order.family_size || 1;
    const forWho = recipientName ? ` برای ${recipientName}` : "";
    const familyNote = seats > 1 ? ` · ${seats} کانفیگ خانواده` : "";
    if (order.auto_approved) {
      if (order.gift_code) {
        notify(`کارت هدیه آماده شد: ${order.gift_code}`, "success");
        setCheckout(null);
        setPendingOrder(null);
        setShopSection("gift");
        switchTab("shop");
        return;
      }
      notify(
        order.renew
          ? `تمدید${forWho} با کیف‌پول انجام شد`
          : `خرید${forWho} با کیف‌پول انجام شد${familyNote}. کانفیگ فعال است.`,
        "success",
      );
      setCheckout(null);
      setPendingOrder(null);
      await refreshDashboard();
      if (!order.renew) switchTab("subs");
    } else if (!order.needs_receipt) {
      await api.confirmWallet(order.id);
      notify(
        order.resumed
          ? `سفارش قبلی${forWho} ثبت شد — منتظر تایید`
          : `سفارش${forWho} ثبت شد${familyNote}. بعد از تایید، لینک‌ها را از داشبورد بفرست.`,
        "success",
      );
      setCheckout(null);
      setPendingOrder({
        id: order.id,
        plan_title: order.plan_title || "خرید VPN",
        amount_toman: order.amount_toman,
        amount_label: order.amount_label,
        wallet_used: order.wallet_used,
        has_receipt: false,
        payment: order.payment,
        recipientName: recipientName || null,
        familySize: seats > 1 ? seats : null,
      });
    } else {
      if (order.resumed) notify("سفارش ناتمام قبلی باز شد", "info");
      setCheckout({
        orderId: order.id,
        amountLabel: order.amount_label,
        amountToman: order.amount_toman,
        walletUsed: order.wallet_used,
        payment: order.payment,
        kind: "plan",
        recipientName: recipientName || null,
        familySize: seats > 1 ? seats : undefined,
      });
    }
  };

  const buyCustom = async (order: Awaited<ReturnType<typeof api.customOrder>>) => {
    setBusy(true);
    try {
      await completePlanOrder(order, null, order.family_size);
    } catch (e) {
      notify(persianError(e instanceof Error ? e.message : "خرید ناموفق"), "error");
    } finally {
      setBusy(false);
    }
  };

  const handleDetailCheckout = async (
    order: Awaited<ReturnType<typeof api.createOrder>> & { renew?: boolean; plan_title?: string },
  ) => {
    setBusy(true);
    try {
      await completePlanOrder({
        ...order,
        plan_title: order.plan_title || (order.renew ? "تمدید اشتراک" : "خرید VPN"),
      });
      if (order.needs_receipt) {
        switchTab("shop");
      }
    } catch (e) {
      notify(persianError(e instanceof Error ? e.message : "خرید ناموفق"), "error");
    } finally {
      setBusy(false);
    }
  };

  const cancelCheckout = async () => {
    if (!checkout) return;
    setBusy(true);
    try {
      const res = await api.cancelOrder(checkout.orderId);
      setCheckout(null);
      setMe((m) => (m ? { ...m, wallet_balance: res.wallet_balance } : m));
      notify("سفارش لغو شد", "success");
    } catch (e) {
      notify(persianError(e instanceof Error ? e.message : "لغو ناموفق"), "error");
    } finally {
      setBusy(false);
    }
  };

  const onReceipt = async (file: File | null) => {
    if (!file || !checkout) return;
    setBusy(true);
    try {
      await api.uploadReceipt(checkout.orderId, file);
      notify("رسید ارسال شد — منتظر تایید", "success");
      setCheckout(null);
      setMe(await api.me());
    } catch (e) {
      notify(persianError(e instanceof Error ? e.message : "آپلود ناموفق"), "error");
    } finally {
      setBusy(false);
    }
  };

  const openSubDetail = (subId: number, tab?: "connect" | "usage" | "renew" | "more") => {
    setDetailSubId(subId);
    setDetailInitialTab(tab || null);
    setDetailOpen(true);
  };

  const refreshDashboard = async () => {
    const [subsData, dash] = await Promise.all([api.subscriptions(), api.dashboard()]);
    setPendingOrder(subsData.pending || null);
    applyDashboard(dash);
  };

  const rotateDashboardLink = async (subId: number) => {
    setBusy(true);
    try {
      const res = await api.rotateSubscriptionLink(subId);
      haptic();
      notify("لینک جدید ساخته شد. لینک قبلی دیگر کار نمی‌کند.", "success");
      await refreshDashboard();
      if (res.subscription_url) void copy(res.subscription_url);
      setRotateConfirmId(null);
    } catch (e) {
      notify(persianError(e instanceof Error ? e.message : "ساخت لینک جدید ناموفق بود"), "error");
    } finally {
      setBusy(false);
    }
  };

  const hideExpiredFromDashboard = async (subId: number) => {
    setBusy(true);
    try {
      await api.hideSubscription(subId);
      haptic();
      notify("از لیست کانفیگ‌ها حذف شد — در آرشیو می‌ماند", "success");
      await refreshDashboard();
    } catch (e) {
      notify(persianError(e instanceof Error ? e.message : "حذف ناموفق"), "error");
    } finally {
      setBusy(false);
    }
  };

  const restoreArchivedConfig = async (subId: number) => {
    setBusy(true);
    try {
      await api.unhideSubscription(subId);
      haptic();
      notify("به لیست کانفیگ‌ها برگشت", "success");
      await refreshDashboard();
    } catch (e) {
      notify(persianError(e instanceof Error ? e.message : "بازگردانی ناموفق"), "error");
    } finally {
      setBusy(false);
    }
  };

  const statusMeta = (status: string) => {
    if (status === "online") return { text: "آنلاین", className: "border-emerald-400/40 bg-emerald-500/15 text-emerald-200" };
    if (status === "expired") return { text: "منقضی", className: "border-red-400/40 bg-red-500/15 text-red-200" };
    if (status === "disabled") return { text: "غیرفعال", className: "border-amber-400/40 bg-amber-500/15 text-amber-200" };
    return { text: "آفلاین", className: "border-white/20 bg-white/10 text-neutral-300" };
  };

  const doWithdraw = async () => {
    if (!refData) return;
    setBusy(true);
    try {
      await api.withdraw(cardInput);
      notify("درخواست برداشت ثبت شد", "success");
      setCardInput("");
      setRefData(await api.referral());
      setMe(await api.me());
    } catch (e) {
      notify(persianError(e instanceof Error ? e.message : "برداشت ناموفق"), "error");
    } finally {
      setBusy(false);
    }
  };

  const openWallet = async () => {
    haptic();
    setWalletOpen(true);
    try {
      const info = await api.wallet();
      setWalletInfo(info);
      setDepositAmount(info.presets[1] || info.min_deposit);
      setWalletWithdrawAmount(info.withdrawable ?? info.balance);
      setWalletTab(info.pending_withdrawal ? "withdraw" : info.pending_deposit ? "deposit" : walletTab);
      if (me) setMe({ ...me, wallet_balance: info.balance });
    } catch (e) {
      notify(persianError(e instanceof Error ? e.message : "خطا"), "error");
    }
  };

  const doWalletWithdraw = async () => {
    const withdrawable = walletInfo?.withdrawable ?? walletInfo?.balance ?? me?.wallet_balance ?? 0;
    const minW = walletInfo?.min_withdraw ?? 100_000;
    const amount = walletWithdrawAmount || withdrawable;
    const cardDigits = walletWithdrawCard.replace(/\D/g, "");
    if (cardDigits.length < 16) {
      notify("شماره کارت باید ۱۶ رقم باشد", "error");
      return;
    }
    if (amount < minW) {
      notify(`حداقل برداشت ${walletInfo?.min_withdraw_label || priceText(minW)} است`, "error");
      return;
    }
    if (amount > withdrawable) {
      notify("این مبلغ قابل برداشت نیست", "error");
      return;
    }
    setBusy(true);
    try {
      await api.withdraw(cardDigits, amount);
      notify("درخواست برداشت ثبت شد — پس از بررسی واریز می‌شود", "success");
      setWalletWithdrawCard("");
      const info = await api.wallet();
      setWalletInfo(info);
      setWalletWithdrawAmount(info.withdrawable ?? info.balance);
      setMe(await api.me());
    } catch (e) {
      notify(persianError(e instanceof Error ? e.message : "برداشت ناموفق"), "error");
    } finally {
      setBusy(false);
    }
  };

  const startDeposit = async (amount: number) => {
    setBusy(true);
    try {
      const order = await api.walletDeposit(amount);
      setWalletOpen(false);
      setCheckout({
        orderId: order.id,
        amountLabel: order.amount_label,
        amountToman: order.amount_toman,
        walletUsed: 0,
        payment: order.payment,
        kind: "wallet",
      });
      setTab("shop");
      if (typeof order.wallet_balance === "number") {
        setMe((m) => (m ? { ...m, wallet_balance: order.wallet_balance! } : m));
      }
      notify(order.resumed ? "سفارش شارژ قبلی باز شد" : "سفارش شارژ ثبت شد — رسید را بفرستید", "info");
    } catch (e) {
      notify(persianError(e instanceof Error ? e.message : "شارژ ناموفق"), "error");
    } finally {
      setBusy(false);
    }
  };

  const openProfile = (opts?: { help?: boolean }) => {
    const wantHelp = Boolean(opts?.help);
    if (tab === "profile") {
      haptic();
      if (wantHelp) {
        setProfileFocusHelp(false);
        window.requestAnimationFrame(() => setProfileFocusHelp(true));
      }
      return;
    }
    setProfileFocusHelp(wantHelp);
    switchTab("profile");
  };

  const onProfileWalletUpdate = useCallback((balance: number) => {
    setMe((m) => (m ? { ...m, wallet_balance: balance, has_birth_date: true } : m));
  }, []);

  const onProfileOpenHistory = useCallback(() => {
    haptic();
    setOrderHistoryOpen(true);
  }, []);

  const switchTab = (id: Tab) => {
    if (id === tab) return;
    haptic();
    if (id !== "profile") setProfileFocusHelp(false);
    setTab(id);
  };

  const tabs: { id: Tab; label: string; icon: ReactNode; admin?: boolean }[] = [
    { id: "subs", label: "داشبورد", icon: <Activity className="size-[18px]" /> },
    { id: "shop", label: "فروشگاه", icon: <Store className="size-[18px]" /> },
    { id: "chat", label: "گفتگو", icon: <MessageCircle className="size-[18px]" /> },
    { id: "invite", label: "دعوت", icon: <Gift className="size-[18px]" /> },
    { id: "profile", label: "پروفایل", icon: <User className="size-[18px]" /> },
    { id: "admin", label: "ادمین", icon: <Shield className="size-[18px]" />, admin: true },
  ];

  const configQuery = configSearch.trim().toLowerCase();
  const dashGroups = useMemo(
    () => filterAndGroupDashboardItems(dashItems, configQuery),
    [dashItems, configQuery],
  );
  const archivedGroups = useMemo(
    () => filterAndGroupDashboardItems(dashArchived, ""),
    [dashArchived],
  );

  const filters: { id: Filter; label: string }[] = [
    { id: "all", label: "همه" },
    { id: 30, label: "۱ ماه" },
    { id: 90, label: "۳ ماه" },
    { id: 180, label: "۶ ماه" },
  ];

  const adminPendingCount = adminOrders.length + adminWds.length;
  const adminNotifCount = adminPendingCount + chatUnread;
  const walletPending = walletInfo?.pending_deposit ?? null;
  const userNotifCount =
    chatUnread + (pendingOrder ? 1 : 0) + (walletPending ? 1 : 0);
  const headerNotifCount = me?.is_admin ? adminNotifCount : userNotifCount;
  const proUntilLabel = proData?.pro_until_label ?? null;
  const isProMember = Boolean(me?.is_pro || proData?.is_pro);

  if (loading) {
    return (
      <GradientField className="flex min-h-dvh flex-col items-center justify-center gap-3 px-4">
        <OrbLoader variant="boot" />
        <p className="text-sm text-neutral-400">در حال آماده‌سازی…</p>
        <div className="absolute end-4 top-4">
          <ThemeToggle />
        </div>
      </GradientField>
    );
  }

  if (channelGate) {
    return (
      <GradientField className="mx-auto flex min-h-dvh max-w-lg items-center p-4">
        <div className="absolute end-4 top-4 z-10">
          <ThemeToggle />
        </div>
        <Panel className="w-full space-y-4">
          <div>
            <h2 className="text-base font-semibold">عضویت در کانال الزامی است</h2>
            <p className="mt-2 text-sm leading-relaxed text-neutral-300">{channelGate.message}</p>
            <p className="mt-2 text-xs text-neutral-400" dir="ltr">
              @{channelGate.channel}
            </p>
          </div>
          <TgButton
            onClick={() => {
              haptic();
              const url = channelGate.inviteUrl;
              try {
                window.Telegram?.WebApp?.openTelegramLink?.(url);
              } catch {
                window.open(url, "_blank");
              }
            }}
          >
            عضویت در کانال
          </TgButton>
          <TgButton variant="outline" disabled={busy} onClick={() => void recheckChannel()}>
            {busy ? "در حال بررسی…" : "عضو شدم — بررسی"}
          </TgButton>
        </Panel>
        <ToastHost toasts={toasts} onDismiss={dismiss} />
      </GradientField>
    );
  }

  if (error) {
    return (
      <GradientField className="mx-auto flex min-h-dvh max-w-lg items-center p-4">
        <div className="absolute end-4 top-4 z-10">
          <ThemeToggle />
        </div>
        <Panel className="w-full space-y-3">
          <h2 className="text-base font-semibold">ورود ممکن نشد</h2>
          <p className="text-sm leading-relaxed text-neutral-300">{error}</p>
          <TgButton onClick={() => void boot()}>تلاش دوباره</TgButton>
        </Panel>
        <ToastHost toasts={toasts} onDismiss={dismiss} />
      </GradientField>
    );
  }

  return (
    <GradientField className="mx-auto flex h-dvh max-w-lg flex-col overflow-hidden">
      <header
        className={cn(
          "relative z-10 shrink-0 border-b bg-black/50 backdrop-blur-md",
          isProMember ? "border-neutral-900/20" : "border-white/10",
        )}
      >
        {isProMember && (
          <div
            aria-hidden
            className="pointer-events-none absolute inset-x-0 top-0 h-16 bg-[radial-gradient(circle_at_top,rgba(0,0,0,0.06),transparent_70%)]"
          />
        )}
        <div className="relative grid grid-cols-[minmax(0,1fr)_auto_minmax(0,1fr)] items-center gap-2 px-3 pt-3 pb-3 sm:px-4">
          {me ? (
            <>
              <button
                type="button"
                onClick={() => void openWallet()}
                className={cn(
                  "min-w-0 justify-self-stretch flex items-center gap-2 rounded-xl border px-2.5 py-2 text-start active:bg-white/10 sm:px-3",
                  isProMember
                    ? "pro-wallet-chip border-white/20 bg-gradient-to-l from-neutral-900/40 to-black/60"
                    : "border-white/15 bg-black/60",
                )}
              >
                <span className="inline-flex size-8 shrink-0 items-center justify-center rounded-lg bg-white/10">
                  <Wallet className={cn("size-4 opacity-90", isProMember && "text-neutral-200")} aria-hidden />
                </span>
                  <span className="min-w-0 flex-1">
                  <span className="block text-[10px] text-neutral-500">
                    {me.wallet_balance < 0
                      ? "بدهی کیف‌پول"
                      : isProMember
                        ? "موجودی · Pro"
                        : "کیف پول"}
                  </span>
                  <span
                    className={cn(
                      "block truncate text-sm font-semibold tabular-nums leading-tight",
                      me.wallet_balance < 0 && "text-rose-300",
                    )}
                  >
                    {me.wallet_balance < 0
                      ? `${faNum(Math.abs(me.wallet_balance))} تومان بدهی`
                      : `${faNum(me.wallet_balance)} تومان`}
                  </span>
                </span>
              </button>

              <img
                src={`${import.meta.env.BASE_URL}brand-mark.png`}
                alt="Black Lines"
                className={cn(
                  "h-8 w-auto shrink-0 bg-transparent object-contain",
                  theme === "light" && "brightness-0",
                )}
                draggable={false}
              />

              <div className="flex shrink-0 items-center justify-end gap-1.5">
                {!me.is_admin && (
                  <ProHeaderEntry isPro={isProMember} onClick={() => void openProSheet()} />
                )}
                <NotificationBell
                  count={headerNotifCount}
                  size={36}
                  color="orange"
                  className="border border-white/15 bg-black/60 text-neutral-300"
                  ariaLabel={
                    headerNotifCount > 0
                      ? `${faNum(headerNotifCount)} مورد در مرکز اعلان`
                      : "مرکز اعلان"
                  }
                  onClick={() => void openNotifCenter()}
                />
              </div>
            </>
          ) : null}
        </div>
        {tab === "shop" && !checkout && !purchaseDraft && (
          <div className="border-t border-white/8 px-3 py-2">
            <div className="grid grid-cols-4 gap-1 rounded-xl border border-white/10 bg-black/35 p-1">
              {(
                [
                  { id: "plans" as const, label: "آماده" },
                  { id: "custom" as const, label: "سفارشی" },
                  { id: "payg" as const, label: "مصرفی" },
                  { id: "gift" as const, label: "هدیه" },
                ] as const
              ).map((item) => (
                <button
                  key={item.id}
                  type="button"
                  onClick={() => {
                    haptic();
                    setShopSection(item.id);
                  }}
                  className={cn(
                    "h-8 rounded-lg text-[11px] font-semibold transition-colors",
                    shopSection === item.id
                      ? "bg-white text-black"
                      : "text-neutral-400 active:bg-white/8",
                  )}
                >
                  {item.label}
                </button>
              ))}
            </div>
          </div>
        )}
      </header>

      {busy && (
        <div className="pointer-events-none absolute inset-x-0 top-[4.5rem] z-20 flex justify-center">
          <div className="mt-1 flex items-center gap-2 rounded-full border border-white/15 bg-black/80 px-3 py-1.5 text-[11px] text-neutral-300 shadow-lg backdrop-blur">
            <OrbLoader variant="busy" />
            در حال پردازش…
          </div>
        </div>
      )}

      <main
        ref={mainRef}
        className={cn(
          "relative z-10 min-h-0 flex-1 overscroll-contain [-webkit-overflow-scrolling:touch]",
          tab === "chat"
            ? "flex flex-col overflow-hidden"
            : "overflow-y-auto px-3 py-3",
        )}
      >
        {tab === "shop" && (
          <div className="space-y-3 pb-1">
            {!checkout && !purchaseDraft && me?.trial_offer?.available ? (
              <Panel className="space-y-3 border-amber-300/20 bg-amber-300/5">
                <div className="flex items-start gap-2">
                  <Gift className="mt-0.5 size-4 shrink-0 text-amber-300" />
                  <div className="min-w-0">
                    <h3 className="text-[15px] font-semibold text-white">کانفیگ تست رایگان</h3>
                    <p className="mt-0.5 text-[11px] leading-relaxed text-neutral-400">
                      {faNum(me.trial_offer.duration_days)} روز · {me.trial_offer.traffic_label} ·{" "}
                      {faNum(me.trial_offer.limit_ip)} دستگاه
                    </p>
                  </div>
                </div>
                <TgButton disabled={busy} onClick={() => void claimTrial()}>
                  دریافت VPN تست
                </TgButton>
              </Panel>
            ) : null}
            {!checkout && !purchaseDraft && shopSection === "custom" && (
              <div className="space-y-3">
                <ShopSectionIntro
                  title="پکیج سفارشی"
                  description="مدت، حجم و تعداد دستگاه را خودتان بسازید. تخفیف و نام کانفیگ در مرحله بعد است."
                />
                <CustomPackageBuilder
                  busy={busy}
                  isPro={me?.is_pro}
                  onReview={(draft) => setPurchaseDraft({ kind: "custom", ...draft })}
                  onCheckout={buyCustom}
                />
              </div>
            )}

            {!checkout && !purchaseDraft && shopSection === "payg" && (
              <div className="space-y-3">
                <ShopSectionIntro
                  title="پرداخت مصرفی"
                  description="یا کیف‌پول را شارژ کنید و فقط مصرف واقعی بپردازید، یا یکجا حجم بخرید."
                />
                <div className="grid grid-cols-2 gap-1 rounded-xl border border-white/10 bg-black/35 p-1">
                  <button
                    type="button"
                    onClick={() => {
                      haptic();
                      setPaygMode("cloud");
                    }}
                    className={cn(
                      "h-8 rounded-lg text-[11px] font-semibold",
                      paygMode === "cloud" ? "bg-white text-black" : "text-neutral-400 active:bg-white/8",
                    )}
                  >
                    ابری
                  </button>
                  <button
                    type="button"
                    onClick={() => {
                      haptic();
                      setPaygMode("traffic");
                    }}
                    className={cn(
                      "h-8 rounded-lg text-[11px] font-semibold",
                      paygMode === "traffic" ? "bg-white text-black" : "text-neutral-400 active:bg-white/8",
                    )}
                  >
                    خرید حجم
                  </button>
                </div>
                {paygMode === "cloud" ? (
                  <PaygPackageBuilder
                    busy={busy}
                    isPro={me?.is_pro}
                    onActivated={async () => {
                      notify("کانفیگ مصرفی فعال شد", "success");
                      await refreshDashboard();
                      switchTab("subs");
                    }}
                    onTopup={() => setWalletOpen(true)}
                  />
                ) : (
                  <PaygTrafficBuilder
                    busy={busy}
                    isPro={me?.is_pro}
                    onReview={(draft) => setPurchaseDraft({ kind: "payg", ...draft })}
                    onCheckout={buyCustom}
                  />
                )}
              </div>
            )}

            {!checkout && !purchaseDraft && shopSection === "plans" && (
              <div className="space-y-3">
                <ShopSectionIntro
                  title="پکیج‌های آماده"
                  description="پلن و تعداد نفر را انتخاب کنید. تخفیف، نام کانفیگ و تأیید مشخصات در مرحله بعد است."
                />
                <FilterBar
                  items={filters}
                  value={filter}
                  onChange={(id) => {
                    haptic();
                    setFilter(id);
                  }}
                />

                {filteredPlans.length > 0 ? (
                  <FamilyPackPanel
                    familySize={shopFamilySize}
                    onFamilySizeChange={setShopFamilySize}
                    disabled={busy}
                  />
                ) : null}

                {filteredPlans.length === 0 && (
                  <Panel className="space-y-3 py-10 text-center">
                    <OrbLoader variant="empty" className="mx-auto opacity-70" />
                    <p className="text-sm text-neutral-400">پلنی در این دسته نیست.</p>
                  </Panel>
                )}

                {filteredPlans.map((plan) => (
                  <Panel key={plan.id} className="space-y-3">
                    <div className="space-y-1">
                      <div className="flex items-start justify-between gap-3">
                        <h3 className="min-w-0 flex-1 text-[15px] font-semibold leading-snug">
                          {plan.title}
                          {(plan.pro_only || plan.traffic_gb <= 0) && (
                            <span className="ms-2 align-middle text-[10px] font-semibold text-amber-300">Pro</span>
                          )}
                        </h3>
                        <div className="shrink-0 text-end">
                          {(plan.pro_discount_percent ?? 0) > 0 &&
                          (plan.charge_toman ?? plan.price_toman) < plan.price_toman ? (
                            <>
                              <div className="text-[10px] text-neutral-500 line-through">
                                {priceText(plan.price_toman)}
                              </div>
                              <div className="text-sm font-bold tabular-nums leading-tight text-emerald-300">
                                {priceText(plan.charge_toman ?? plan.price_toman)}
                              </div>
                              <div className="text-[10px] text-emerald-400/90">
                                Pro · {faNum(plan.pro_discount_percent!)}٪ تخفیف
                              </div>
                            </>
                          ) : (
                            <div className="text-sm font-bold tabular-nums leading-tight">
                              {priceText(plan.price_toman)}
                            </div>
                          )}
                        </div>
                      </div>
                      {plan.description ? (
                        <p className="text-xs leading-relaxed text-neutral-400">{plan.description}</p>
                      ) : null}
                    </div>
                    <div className="flex flex-wrap gap-1.5">
                      <Chip>{faNum(plan.duration_days)} روز</Chip>
                      <Chip>
                        {plan.traffic_gb > 0 ? `${faNum(plan.traffic_gb)} گیگ` : "نامحدود"}
                      </Chip>
                      <Chip>{faNum(plan.limit_ip)} دستگاه</Chip>
                    </div>
                    {plan.pay_after_wallet < (plan.charge_toman ?? plan.price_toman) && (
                      <p className="text-[11px] text-neutral-400">
                        قابل پرداخت با کیف‌پول: {priceText(plan.pay_after_wallet)}
                      </p>
                    )}
                    {!me?.is_pro && (plan.pro_discount_percent ?? 0) > 0 && (
                      <p className="text-[11px] text-amber-400/90">
                        با Pro {faNum(plan.pro_discount_percent!)}٪ ارزان‌تر — دکمه Pro در بالا
                      </p>
                    )}
                    <TgButton disabled={busy} onClick={() => startPlanPurchase(plan)}>
                      {shopFamilySize > 1 ? `ادامه · خانواده ${faNum(shopFamilySize)} کانفیگ` : "ادامه خرید"}
                    </TgButton>
                  </Panel>
                ))}
              </div>
            )}

            {!checkout && !purchaseDraft && shopSection === "gift" && (
              <div className="space-y-3">
                <ShopSectionIntro
                  title="کارت هدیه"
                  description="یک پلن بخر و کد را برای دوستت بفرست، یا کدی که گرفته‌ای را اینجا فعال کن."
                />
                <GiftCardsPanel
                  plans={plans.filter((p) => (p.traffic_gb || 0) > 0 && !p.pro_only)}
                  busy={busy}
                  onBuy={(plan) => {
                    haptic("medium");
                    setPurchaseDraft({ kind: "plan", plan, familySize: 1, giftCard: true });
                  }}
                  onRedeemed={async () => {
                    notify("کارت هدیه فعال شد — کانفیگ در داشبورد است", "success");
                    await refreshDashboard();
                    switchTab("subs");
                  }}
                />
              </div>
            )}

            {!checkout && purchaseDraft ? (
              <PurchaseConfirmPanel
                draft={purchaseDraft}
                busy={busy}
                onBack={() => setPurchaseDraft(null)}
                onConfirm={(payload) => void confirmPurchase(payload)}
              />
            ) : null}

            {checkout && (
              <Panel>
                <CheckoutPanel
                  kind={checkout.kind}
                  orderId={checkout.orderId}
                  amountToman={checkout.amountToman}
                  walletUsed={checkout.walletUsed}
                  paymentNote={checkout.payment.note}
                  recipientName={checkout.recipientName}
                  familySize={checkout.familySize}
                  cards={paymentCardsFrom(checkout.payment)}
                  busy={busy}
                  onCopy={(card) => void copy(card.card)}
                  onCopyAmount={(amount) => void copy(String(amount))}
                  onReceipt={(file) => void onReceipt(file)}
                  onCancel={() => void cancelCheckout()}
                />
              </Panel>
            )}
          </div>
        )}

        {tab === "subs" && (
          <div className="space-y-3">
            {tabLoading && <OrbLoaderPanel variant="dashboard" message="در حال بارگذاری…" />}

            {!tabLoading && (
              <div className="space-y-2">
                <div className="grid grid-cols-3 gap-2">
                  <Panel className="space-y-1 px-3 py-3 text-center">
                    <div className="text-[10px] text-neutral-400">کل کانفیگ</div>
                    <div className="text-lg font-bold tabular-nums">{faNum(dashSummary.total)}</div>
                  </Panel>
                  <Panel className="space-y-1 px-3 py-3 text-center">
                    <div className="text-[10px] text-neutral-400">آنلاین</div>
                    <div className="text-lg font-bold tabular-nums text-emerald-300">
                      {faNum(dashSummary.online)}
                    </div>
                  </Panel>
                  <Panel className="space-y-1 px-3 py-3 text-center">
                    <div className="text-[10px] text-neutral-400">آفلاین</div>
                    <div className="text-lg font-bold tabular-nums text-neutral-300">
                      {faNum(dashSummary.offline)}
                    </div>
                  </Panel>
                </div>

                <ResellerDeskEntry
                  summary={resellerDesk?.summary || null}
                  onOpen={() => setResellerOpen(true)}
                />

                {dashItems.length > 0 && (
                  <div className="overflow-hidden rounded-xl border border-white/10 bg-black/25">
                    <button
                      type="button"
                      className="flex w-full items-center justify-between gap-2 px-3 py-2.5 text-start active:bg-white/5"
                      onClick={() => setDashUsageOpen((v) => !v)}
                    >
                      <span className="min-w-0">
                        <span className="block text-xs font-semibold text-neutral-200">خلاصه مصرف</span>
                        {!dashUsageOpen ? (
                          <span className="mt-0.5 block text-[10px] text-neutral-500">
                            امروز {dashSummary.today_label || "۰"}
                            {dashSummary.remaining_label ? ` · مانده ${dashSummary.remaining_label}` : ""}
                          </span>
                        ) : null}
                      </span>
                      <ChevronDown
                        className={cn(
                          "size-4 shrink-0 text-neutral-500 transition-transform",
                          dashUsageOpen && "rotate-180",
                        )}
                      />
                    </button>
                    {dashUsageOpen ? (
                      <div className="space-y-2.5 border-t border-white/8 px-3 pb-3 pt-2.5">
                        {dashSummary.last_seen_label ? (
                          <p className="text-[10px] text-neutral-500">آخرین فعالیت: {dashSummary.last_seen_label}</p>
                        ) : null}
                        <div className="grid grid-cols-2 gap-2">
                          <div className="rounded-lg border border-white/8 bg-black/25 px-3 py-2">
                            <div className="text-[10px] text-neutral-500">امروز</div>
                            <div className="text-sm font-semibold tabular-nums">{dashSummary.today_label || "۰ B"}</div>
                          </div>
                          <div className="rounded-lg border border-white/8 bg-black/25 px-3 py-2">
                            <div className="text-[10px] text-neutral-500">۷ روز</div>
                            <div className="text-sm font-semibold tabular-nums">{dashSummary.week_label || "۰ B"}</div>
                          </div>
                          <div className="rounded-lg border border-white/8 bg-black/25 px-3 py-2">
                            <div className="text-[10px] text-neutral-500">آپلود / دانلود</div>
                            <div className="text-[11px] font-semibold tabular-nums">
                              {dashSummary.up_label || "۰"} / {dashSummary.down_label || "۰"}
                            </div>
                          </div>
                          <div className="rounded-lg border border-white/8 bg-black/25 px-3 py-2">
                            <div className="text-[10px] text-neutral-500">کل مصرف</div>
                            <div className="text-sm font-semibold tabular-nums">{dashSummary.used_label || "۰ B"}</div>
                          </div>
                        </div>
                      </div>
                    ) : null}
                  </div>
                )}
              </div>
            )}

            {!tabLoading && pendingOrder && (
              <Panel className="space-y-3">
                <div>
                  <div className="mb-1 inline-flex rounded-lg border border-white/20 bg-white/10 px-2 py-0.5 text-[11px]">
                    در انتظار تایید
                  </div>
                  <h3 className="font-semibold">{pendingOrder.plan_title}</h3>
                  <p className="mt-1 text-xs text-neutral-400">
                    سفارش #{faNum(pendingOrder.id)} · {pendingOrder.amount_label}
                    {pendingOrder.has_receipt ? " · رسید ارسال شده" : " · منتظر رسید"}
                  </p>
                  {pendingOrder.recipientName ? (
                    <p className="mt-2 rounded-lg border border-teal-500/20 bg-teal-500/10 px-2.5 py-1.5 text-[11px] text-teal-100">
                      برای {pendingOrder.recipientName} — بعد از تایید، لینک را از میز فروش بفرست.
                    </p>
                  ) : null}
                  {(pendingOrder.familySize ?? 1) > 1 ? (
                    <p className="mt-2 rounded-lg border border-sky-500/20 bg-sky-500/10 px-2.5 py-1.5 text-[11px] text-sky-100">
                      پکیج خانواده · {faNum(pendingOrder.familySize!)} کانفیگ جدا (۱ والد + {faNum(pendingOrder.familySize! - 1)} فرزند)
                    </p>
                  ) : null}
                </div>
                {!pendingOrder.has_receipt && (
                  <TgButton
                    onClick={() => {
                      setCheckout({
                        orderId: pendingOrder.id,
                        amountLabel: pendingOrder.amount_label,
                        amountToman: pendingOrder.amount_toman,
                        walletUsed: pendingOrder.wallet_used,
                        payment: pendingOrder.payment,
                        kind: pendingOrder.is_wallet_topup ? "wallet" : "plan",
                        recipientName: pendingOrder.recipientName,
                        familySize: pendingOrder.familySize || undefined,
                      });
                      setTab("shop");
                    }}
                  >
                    ادامه پرداخت / ارسال رسید
                  </TgButton>
                )}
                <TgButton
                  variant="outline"
                  disabled={busy}
                  onClick={async () => {
                    setBusy(true);
                    try {
                      const res = await api.cancelOrder(pendingOrder.id);
                      setPendingOrder(null);
                      setMe((m) => (m ? { ...m, wallet_balance: res.wallet_balance } : m));
                      notify("سفارش لغو شد", "success");
                    } catch (e) {
                      notify(persianError(e instanceof Error ? e.message : "لغو ناموفق"), "error");
                    } finally {
                      setBusy(false);
                    }
                  }}
                >
                  لغو سفارش
                </TgButton>
              </Panel>
            )}

            {!tabLoading && dashItems.length === 0 && dashArchived.length === 0 && !pendingOrder && (
              <Panel className="space-y-3 py-8 text-center">
                <OrbLoader variant="empty" className="mx-auto opacity-60" />
                <p className="text-sm text-neutral-400">هنوز کانفیگی ندارید.</p>
                <TgButton onClick={() => switchTab("shop")}>رفتن به فروشگاه</TgButton>
                <TgButton variant="outline" onClick={() => openProfile({ help: true })}>
                  راهنمای استفاده
                </TgButton>
              </Panel>
            )}

            {!tabLoading && dashItems.length === 0 && dashArchived.length > 0 && !pendingOrder && (
              <Panel className="py-4 text-center text-[12px] text-neutral-400">
                کانفیگ فعالی در لیست نیست — منقضی‌ها در آرشیو پایین هستند.
              </Panel>
            )}

            {!tabLoading && dashItems.length > 0 && (
              <div className="relative">
                <Search className="pointer-events-none absolute start-3 top-1/2 size-4 -translate-y-1/2 text-neutral-500" aria-hidden />
                <input
                  type="search"
                  value={configSearch}
                  onChange={(e) => setConfigSearch(e.target.value)}
                  placeholder="جستجو: نام مشتری، موبایل، تلگرام، ایمیل، برچسب…"
                  className="w-full rounded-xl border border-white/12 bg-black/40 py-2.5 pe-3 ps-10 text-sm text-white outline-none placeholder:text-neutral-500 focus:border-white/25"
                />
              </div>
            )}

            {!tabLoading && dashItems.length > 0 && configQuery && dashGroups.length === 0 && (
              <Panel className="py-8 text-center text-sm text-neutral-400">نتیجه‌ای پیدا نشد.</Panel>
            )}

            {!tabLoading && dashGroups.length > 0 && (
              <DashboardConfigList
                items={dashItems}
                query={configQuery}
                busy={busy}
                copied={copied}
                rotateConfirmId={rotateConfirmId}
                remainingHint={(s) => remainingDaysHint(s.expires_at, s.is_payg)}
                statusOf={statusMeta}
                onOpen={openSubDetail}
                onRename={renameConfig}
                onCopy={(url) => {
                  const item = dashItems.find((it) => it.subscription_url === url);
                  void copy(url, {
                    subId: item?.id,
                    markShared: Boolean(item?.customer_name),
                  });
                }}
                onHideExpired={(id) => void hideExpiredFromDashboard(id)}
                onAskRotate={(id) => {
                  haptic();
                  setRotateConfirmId(id);
                }}
                onCancelRotate={() => setRotateConfirmId(null)}
                onConfirmRotate={(id) => void rotateDashboardLink(id)}
              />
            )}

            {!tabLoading && dashArchived.length > 0 && (
              <div className="overflow-hidden rounded-xl border border-white/10 bg-black/25">
                <button
                  type="button"
                  className="flex w-full items-center justify-between gap-2 px-3 py-2.5 text-start active:bg-white/5"
                  onClick={() => setDashArchiveOpen((v) => !v)}
                >
                  <span className="inline-flex items-center gap-1.5 text-xs font-semibold text-neutral-200">
                    <Archive className="size-3.5 text-neutral-400" />
                    آرشیو منقضی‌ها · {faNum(dashArchived.length)}
                  </span>
                  <span className="text-[10px] text-neutral-500">{dashArchiveOpen ? "بستن" : "نمایش"}</span>
                </button>
                {dashArchiveOpen ? (
                  <div className="space-y-2 border-t border-white/8 px-3 pb-3 pt-2.5">
                    <p className="text-[10px] leading-relaxed text-neutral-500">
                      از لیست اصلی حذف شده‌اند؛ برای تمدید یا بازگردانی اینجا هستند.
                    </p>
                    {archivedGroups.map((g) => {
                      if (g.type === "family") {
                        const parent = g.members.find((m) => m.family_role === "parent") || g.members[0];
                        return (
                          <div key={g.key} className="space-y-2 rounded-lg border border-sky-500/15 bg-sky-500/[0.04] px-3 py-2.5">
                            <div className="text-[11px] font-semibold text-sky-100">
                              خانواده · {faNum(g.members.length)} کانفیگ
                              {parent.plan_title ? ` · ${parent.plan_title}` : ""}
                            </div>
                            {g.members.map((s) => {
                              const title =
                                s.family_role === "parent"
                                  ? s.label?.trim() || "والد"
                                  : s.customer_name || s.label?.trim() || "فرزند";
                              return (
                                <div key={s.id} className="space-y-2 rounded-lg border border-white/8 bg-black/30 px-3 py-2">
                                  <div className="flex items-start justify-between gap-2">
                                    <div className="min-w-0">
                                      <div className="mb-0.5 text-[10px] text-neutral-500">
                                        {s.family_role === "parent" ? "والد" : "فرزند"}
                                      </div>
                                      <EditableConfigName
                                        name={title}
                                        disabled={busy}
                                        nameClassName="text-sm font-medium text-neutral-100"
                                        onSave={(label) => renameConfig(s.id, label)}
                                      />
                                    </div>
                                    <span className="shrink-0 rounded-md border border-red-500/30 bg-red-500/10 px-1.5 py-0.5 text-[10px] text-red-200">
                                      منقضی
                                    </span>
                                  </div>
                                  <div className="grid grid-cols-2 gap-2">
                                    <TgButton
                                      variant="outline"
                                      disabled={busy}
                                      className="h-8 text-xs"
                                      onClick={() => openSubDetail(s.id)}
                                    >
                                      جزئیات / تمدید
                                    </TgButton>
                                    <TgButton
                                      disabled={busy}
                                      className="h-8 text-xs"
                                      onClick={() => void restoreArchivedConfig(s.id)}
                                    >
                                      بازگردانی
                                    </TgButton>
                                  </div>
                                </div>
                              );
                            })}
                          </div>
                        );
                      }
                      const s = g.item;
                      const title = s.label?.trim() || s.plan_title;
                      return (
                        <div
                          key={s.id}
                          className="space-y-2 rounded-lg border border-white/8 bg-black/30 px-3 py-2.5"
                        >
                          <div className="flex items-start justify-between gap-2">
                            <div className="min-w-0">
                              <EditableConfigName
                                name={title}
                                disabled={busy}
                                nameClassName="text-sm font-medium text-neutral-100"
                                onSave={(label) => renameConfig(s.id, label)}
                              />
                              {s.label?.trim() ? (
                                <div className="truncate text-[11px] text-neutral-500">{s.plan_title}</div>
                              ) : null}
                              <div className="mt-0.5 truncate font-mono text-[10px] text-neutral-500" dir="ltr">
                                {s.email}
                              </div>
                            </div>
                            <span className="shrink-0 rounded-md border border-red-500/30 bg-red-500/10 px-1.5 py-0.5 text-[10px] text-red-200">
                              منقضی
                            </span>
                          </div>
                          <div className="grid grid-cols-2 gap-2">
                            <TgButton
                              variant="outline"
                              disabled={busy}
                              className="h-9 text-xs"
                              onClick={() => openSubDetail(s.id)}
                            >
                              جزئیات / تمدید
                            </TgButton>
                            <TgButton
                              disabled={busy}
                              className="h-9 text-xs"
                              onClick={() => void restoreArchivedConfig(s.id)}
                            >
                              بازگردانی
                            </TgButton>
                          </div>
                        </div>
                      );
                    })}
                  </div>
                ) : null}
              </div>
            )}
          </div>
        )}

        {tab === "chat" && me && (
          <ChatPanel
            isAdmin={me.is_admin}
            active={tab === "chat"}
            openThreadUserId={openChatThreadUserId}
            onOpenThreadHandled={() => setOpenChatThreadUserId(null)}
            onUnreadChange={setChatUnread}
            onNavigate={(t) => switchTab(t)}
            onOrderAction={() => void handleOrderAction()}
            onNotify={notify}
          />
        )}

        {tab === "invite" && (
          <div>
            {tabLoading || !refData ? (
              <Panel>
                <OrbLoaderPanel variant="invite" message="در حال بارگذاری…" />
              </Panel>
            ) : (
              <Panel className="space-y-4">
                <div>
                  <h3 className="font-semibold">دعوت دوستان</h3>
                  <p className="mt-1 text-sm leading-relaxed text-neutral-400">
                    از هر خرید موفق{" "}
                    <strong className="text-white">{faNum(refData.percent)}٪</strong> پورسانت بگیرید.
                  </p>
                </div>
                <div className="space-y-2">
                  <Label className="text-neutral-300">لینک دعوت</Label>
                  <TgButton
                    variant="outline"
                    className="h-auto justify-between gap-2 whitespace-normal py-3 text-right text-xs font-normal"
                    onClick={() => void copy(refData.invite_link)}
                  >
                    <span className="break-all" dir="ltr">
                      {refData.invite_link}
                    </span>
                    {copied === refData.invite_link ? (
                      <Check className="size-4 shrink-0" />
                    ) : (
                      <Copy className="size-4 shrink-0" />
                    )}
                  </TgButton>
                </div>
                <div className="grid grid-cols-2 gap-2">
                  {[
                    ["دعوت‌ها", faNum(refData.invited)],
                    ["خرید موفق", faNum(refData.paid_referrals)],
                    ["پورسانت", refData.earned_label],
                    ["کیف‌پول", refData.wallet_label],
                  ].map(([k, v]) => (
                    <div key={String(k)} className="rounded-xl border border-white/12 bg-white/5 p-3">
                      <div className="text-[11px] text-neutral-400">{k}</div>
                      <div className="mt-1 text-sm font-semibold tabular-nums">{v}</div>
                    </div>
                  ))}
                </div>

                {(refData.leaderboard?.length ?? 0) > 0 && (
                  <div className="space-y-2 border-t border-white/10 pt-3">
                    <Label className="text-neutral-300">جدول برترین معرف‌ها</Label>
                    <div className="space-y-1.5">
                      {refData.leaderboard!.map((row) => (
                        <div
                          key={`lb-${row.rank}`}
                          className={cn(
                            "flex items-center justify-between gap-2 rounded-xl border px-3 py-2 text-xs",
                            row.is_self
                              ? "border-amber-500/30 bg-amber-500/10"
                              : "border-white/10 bg-black/30",
                          )}
                        >
                          <span className="min-w-0 truncate">
                            <strong className="tabular-nums text-neutral-400">#{faNum(row.rank)}</strong>{" "}
                            {row.display_name}
                            {row.is_self ? " (شما)" : ""}
                          </span>
                          <span className="shrink-0 tabular-nums text-emerald-300">{row.earned_label}</span>
                        </div>
                      ))}
                    </div>
                  </div>
                )}

                {(refData.withdrawals?.length ?? 0) > 0 && (
                  <div className="space-y-2 border-t border-white/10 pt-3">
                    <Label className="text-neutral-300">وضعیت برداشت‌ها</Label>
                    <div className="space-y-1.5">
                      {refData.withdrawals!.slice(0, 8).map((w) => (
                        <div
                          key={w.id}
                          className="flex items-center justify-between gap-2 rounded-xl border border-white/10 bg-black/30 px-3 py-2 text-xs"
                        >
                          <span className="min-w-0 truncate">
                            #{faNum(w.id)} · {w.amount_label}
                          </span>
                          <span
                            className={cn(
                              "shrink-0 rounded-md px-1.5 py-0.5 text-[10px]",
                              w.status === "paid"
                                ? "bg-emerald-500/15 text-emerald-300"
                                : w.status === "rejected"
                                  ? "bg-red-500/15 text-red-300"
                                  : "bg-amber-500/15 text-amber-200",
                            )}
                          >
                            {w.status_label}
                          </span>
                        </div>
                      ))}
                    </div>
                  </div>
                )}

                {(refData.invitees?.length ?? 0) > 0 && (
                  <div className="space-y-2 border-t border-white/10 pt-3">
                    <Label className="text-neutral-300">افراد دعوت‌شده</Label>
                    <div className="space-y-2">
                      {refData.invitees!.map((inv, i) => (
                        <div
                          key={`${inv.username ?? inv.full_name ?? i}-${inv.joined_at ?? i}`}
                          className="rounded-xl border border-white/10 bg-black/30 px-3 py-2.5"
                        >
                          <div className="flex items-start justify-between gap-2">
                            <div className="min-w-0">
                              <div className="truncate text-sm font-semibold">
                                {inv.full_name || (inv.username ? `@${inv.username}` : "کاربر")}
                              </div>
                              {inv.full_name && inv.username && (
                                <div className="truncate text-[10px] text-neutral-500" dir="ltr">
                                  @{inv.username}
                                </div>
                              )}
                            </div>
                            <span
                              className={cn(
                                "shrink-0 rounded-md px-1.5 py-0.5 text-[10px]",
                                inv.has_purchased
                                  ? "bg-emerald-500/15 text-emerald-300"
                                  : "bg-white/5 text-neutral-500",
                              )}
                            >
                              {inv.has_purchased ? "خرید کرده" : "بدون خرید"}
                            </span>
                          </div>
                          <div className="mt-2 flex flex-wrap gap-x-3 text-[10px] text-neutral-400">
                            <span>
                              خرید VPN:{" "}
                              <strong className="text-neutral-200">{inv.vpn_purchase_label}</strong>
                              {inv.vpn_purchase_count > 0 && ` (${faNum(inv.vpn_purchase_count)} بار)`}
                            </span>
                            <span>
                              پورسانت شما:{" "}
                              <strong className="text-emerald-300/90">{inv.commission_label}</strong>
                            </span>
                          </div>
                        </div>
                      ))}
                    </div>
                  </div>
                )}

                {refData.invited === 0 && (
                  <p className="rounded-xl border border-dashed border-white/15 px-3 py-4 text-center text-xs text-neutral-500">
                    هنوز کسی با لینک شما ثبت‌نام نکرده — لینک را برای دوستان بفرستید.
                  </p>
                )}
                {refData.wallet >= refData.min_withdraw ? (
                  <div className="space-y-2 border-t border-white/10 pt-3">
                    <Label className="text-neutral-300">برداشت (حداقل {refData.min_withdraw_label})</Label>
                    <Input
                      placeholder="شماره کارت ۱۶ رقمی"
                      value={cardInput}
                      onChange={(e) => setCardInput(e.target.value)}
                      dir="ltr"
                      inputMode="numeric"
                      className="h-11 rounded-xl border-white/15 bg-black/40 text-base"
                    />
                    <TgButton
                      disabled={busy || cardInput.replace(/\D/g, "").length < 12}
                      onClick={() => void doWithdraw()}
                    >
                      درخواست برداشت
                    </TgButton>
                  </div>
                ) : (
                  <p className="text-xs text-neutral-400">حداقل برداشت: {refData.min_withdraw_label}</p>
                )}
              </Panel>
            )}
          </div>
        )}

        {tab === "profile" && (
          <ProfilePanel
            active={tab === "profile"}
            shopName={me?.shop_name}
            focusHelp={profileFocusHelp}
            onWalletUpdate={onProfileWalletUpdate}
            onOpenHistory={onProfileOpenHistory}
            onOpenResellerDesk={() => {
              haptic();
              setResellerOpen(true);
            }}
            resellerHint={
              resellerDesk?.summary?.total
                ? `${faNum(resellerDesk.summary.total)} مشتری`
                : "کانفیگ‌هایی که برای کس دیگری خریدی"
            }
          />
        )}

        {tab === "admin" && me?.is_admin && (
          <AdminPanel
            loading={tabLoading}
            busy={busy}
            orders={adminOrders}
            withdrawals={adminWds}
            pendingCount={adminPendingCount}
            onOpenNotifCenter={() => void openNotifCenter()}
            onOpenHistory={() => {
              haptic();
              setAdminOrderHistoryOpen(true);
            }}
            onSelectOrder={setAdminOrderDetail}
            onOpenSubscription={(subId) => {
              haptic();
              openSubDetail(subId);
            }}
            onPayWithdrawal={async (id) => {
              setBusy(true);
              try {
                await api.adminPayWd(id);
                setAdminWds(await api.adminWithdrawals());
                notify("پرداخت شد", "success");
              } catch (e) {
                notify(persianError(e instanceof Error ? e.message : "خطا"), "error");
              } finally {
                setBusy(false);
              }
            }}
            onRejectWithdrawal={async (id) => {
              setBusy(true);
              try {
                await api.adminRejectWd(id);
                setAdminWds(await api.adminWithdrawals());
                notify("رد شد", "info");
              } catch (e) {
                notify(persianError(e instanceof Error ? e.message : "خطا"), "error");
              } finally {
                setBusy(false);
              }
            }}
            adminBirthdayGift={adminBirthdayGift}
            adminBirthdayEnabled={adminBirthdayEnabled}
            birthdayDraft={adminBirthdayGiftDraft}
            onBirthdayEnabledChange={setAdminBirthdayEnabled}
            onBirthdayDraftChange={setAdminBirthdayGiftDraft}
            onSaveBirthday={async () => {
              const amount = parseInt(adminBirthdayGiftDraft, 10);
              if (Number.isNaN(amount) || amount < 0) return;
              setBusy(true);
              try {
                const res = await api.adminSetBirthdayGift({
                  enabled: adminBirthdayEnabled,
                  amount_toman: amount,
                });
                setAdminBirthdayGift(res.amount_toman);
                setAdminBirthdayEnabled(Boolean(res.enabled));
                setAdminBirthdayGiftDraft(String(res.amount_toman));
                notify(res.enabled ? `هدیه تولد فعال شد: ${res.amount_label}` : "هدیه تولد غیرفعال شد", "success");
              } catch (e) {
                notify(persianError(e instanceof Error ? e.message : "خطا"), "error");
              } finally {
                setBusy(false);
              }
            }}
            adminTrialSettings={adminTrialSettings}
            trialDraft={adminTrialDraft}
            onTrialDraftChange={(patch) => setAdminTrialDraft((d) => ({ ...d, ...patch }))}
            adminCustomSettings={adminCustomSettings}
            customDraft={adminCustomDraft}
            onCustomDraftChange={(patch) => setAdminCustomDraft((d) => ({ ...d, ...patch }))}
            adminPaygSettings={adminPaygSettings}
            paygDraft={adminPaygDraft}
            onPaygDraftChange={(patch) => setAdminPaygDraft((d) => ({ ...d, ...patch }))}
            onSavePayg={async () => {
              const n = (v: string) => parseInt(v, 10);
              const body = {
                enabled: adminPaygDraft.enabled,
                price_per_gb_toman: n(adminPaygDraft.price_per_gb_toman),
                prepaid_price_per_gb_toman: n(adminPaygDraft.prepaid_price_per_gb_toman),
                min_wallet_toman: n(adminPaygDraft.min_wallet_toman),
                limit_ip: n(adminPaygDraft.limit_ip),
                min_gb: n(adminPaygDraft.min_gb),
                max_gb: n(adminPaygDraft.max_gb),
                min_ip: n(adminPaygDraft.min_ip),
                max_ip: n(adminPaygDraft.max_ip),
                price_per_ip_toman: n(adminPaygDraft.price_per_ip_toman),
                min_price_toman: n(adminPaygDraft.min_price_toman),
              };
              if (Object.values(body).some((v) => typeof v === "number" && Number.isNaN(v))) return;
              setBusy(true);
              try {
                const res = await api.adminSetPaygSettings(body);
                setAdminPaygSettings(res);
                notify("تنظیمات پرداخت مصرفی ذخیره شد", "success");
              } catch (e) {
                notify(persianError(e instanceof Error ? e.message : "خطا"), "error");
              } finally {
                setBusy(false);
              }
            }}
            onSaveCustom={async () => {
              const n = (v: string) => parseInt(v, 10);
              const body = {
                enabled: adminCustomDraft.enabled,
                min_days: n(adminCustomDraft.min_days),
                max_days: n(adminCustomDraft.max_days),
                min_gb: n(adminCustomDraft.min_gb),
                max_gb: n(adminCustomDraft.max_gb),
                min_ip: n(adminCustomDraft.min_ip),
                max_ip: n(adminCustomDraft.max_ip),
                base_fee_toman: n(adminCustomDraft.base_fee_toman),
                price_per_day_toman: n(adminCustomDraft.price_per_day_toman),
                price_per_gb_toman: n(adminCustomDraft.price_per_gb_toman),
                unlimited_day_fee_toman: n(adminCustomDraft.unlimited_day_fee_toman),
                price_per_ip_toman: n(adminCustomDraft.price_per_ip_toman),
                min_price_toman: n(adminCustomDraft.min_price_toman),
              };
              if (Object.values(body).some((v) => typeof v === "number" && Number.isNaN(v))) return;
              setBusy(true);
              try {
                const res = await api.adminSetCustomSettings(body);
                setAdminCustomSettings(res);
                notify("تنظیمات ساخت پکیج ذخیره شد", "success");
              } catch (e) {
                notify(persianError(e instanceof Error ? e.message : "خطا"), "error");
              } finally {
                setBusy(false);
              }
            }}
            onSaveTrial={async () => {
              const duration = parseInt(adminTrialDraft.duration_days, 10);
              const traffic = parseInt(adminTrialDraft.traffic_gb, 10);
              const limitIp = parseInt(adminTrialDraft.limit_ip, 10);
              if (!duration || !traffic || !limitIp) return;
              setBusy(true);
              try {
                const res = await api.adminSetTrialSettings({
                  enabled: adminTrialDraft.enabled,
                  duration_days: duration,
                  traffic_gb: traffic,
                  limit_ip: limitIp,
                  send_links: adminTrialDraft.send_links,
                });
                setAdminTrialSettings(res);
                notify("تنظیمات حساب تست ذخیره شد", "success");
              } catch (e) {
                notify(persianError(e instanceof Error ? e.message : "خطا"), "error");
              } finally {
                setBusy(false);
              }
            }}
            onGrantTrial={async (opts) => {
              const duration = parseInt(adminTrialDraft.duration_days, 10);
              const traffic = parseInt(adminTrialDraft.traffic_gb, 10);
              const limitIp = parseInt(adminTrialDraft.limit_ip, 10);
              setBusy(true);
              try {
                const res = await api.adminGrantTrial({
                  ...opts,
                  duration_days: duration || undefined,
                  traffic_gb: traffic ?? undefined,
                  limit_ip: limitIp || undefined,
                });
                notify(
                  `اعطا شد: ${faNum(res.granted_count)} · رد: ${faNum(res.skipped_count)} · خطا: ${faNum(res.failed_count)}`,
                  res.failed_count > 0 ? "info" : "success",
                );
                return res;
              } catch (e) {
                notify(persianError(e instanceof Error ? e.message : "اعطا ناموفق"), "error");
                throw e;
              } finally {
                setBusy(false);
              }
            }}
            includeTestQueue={adminIncludeTest}
            onIncludeTestQueueChange={setAdminIncludeTest}
            onSearchUsers={searchAdminUsers}
            onSetUserRole={async (userId, role) => {
              setBusy(true);
              try {
                const res = await api.adminSetUserRole(userId, role);
                notify(role === "admin" ? "کاربر ادمین شد" : "نقش ادمین برداشته شد", "success");
                return res.user;
              } catch (e) {
                notify(persianError(e instanceof Error ? e.message : "خطا"), "error");
                throw e;
              } finally {
                setBusy(false);
              }
            }}
            onOpenChat={(userId) => {
              haptic();
              setOpenChatThreadUserId(userId);
              switchTab("chat");
            }}
            onNotify={notify}
            adminPaymentCards={adminPaymentCards}
            paymentCardDraft={paymentCardDraft}
            onPaymentCardDraftChange={(field, value) =>
              setPaymentCardDraft((d) => ({ ...d, [field]: value }))
            }
            onAddPaymentCard={async () => {
              setBusy(true);
              try {
                const res = await api.adminAddPaymentCard({
                  card: paymentCardDraft.card,
                  name: paymentCardDraft.name,
                  label: paymentCardDraft.label,
                  note: paymentCardDraft.note,
                });
                setAdminPaymentCards(res.cards);
                setPaymentCardDraft({ card: "", name: "", label: "", note: "" });
                notify("کارت اضافه شد", "success");
              } catch (e) {
                notify(persianError(e instanceof Error ? e.message : "خطا"), "error");
              } finally {
                setBusy(false);
              }
            }}
            onRemovePaymentCard={async (id) => {
              setBusy(true);
              try {
                const res = await api.adminRemovePaymentCard(id);
                setAdminPaymentCards(res.cards);
                notify("کارت حذف شد", "info");
              } catch (e) {
                notify(persianError(e instanceof Error ? e.message : "خطا"), "error");
              } finally {
                setBusy(false);
              }
            }}
            broadcastText={broadcastText}
            onBroadcastTextChange={setBroadcastText}
            onBroadcast={() => void sendBroadcast()}
          />
        )}
      </main>

      <BottomNavBar
        items={tabs.map((t) => ({
          id: t.id,
          label: t.label,
          icon: t.icon,
          adminOnly: t.admin,
          badge:
            (t.id === "shop" && (!!checkout || !!purchaseDraft)) ||
            (t.id === "chat" && chatUnread > 0) ||
            (t.id === "admin" && adminPendingCount > 0) ||
            (t.id === "profile" && !!me && !me.has_birth_date),
          badgeCount: t.id === "admin" ? adminPendingCount : t.id === "chat" ? chatUnread : 0,
        }))}
        activeId={tab}
        onChange={(id) => switchTab(id as Tab)}
        isAdmin={me?.is_admin}
      />

      <TgSheet
        open={walletOpen}
        onClose={() => setWalletOpen(false)}
        title="کیف‌پول"
        description="موجودی، شارژ، انتقال و برداشت"
      >
        <div className="space-y-4">
          <div className="rounded-2xl border border-white/12 bg-white/5 px-4 py-5 text-center">
            <div className="text-[11px] text-neutral-400">
              {(walletInfo?.debt || 0) > 0 || (me?.wallet_balance ?? 0) < 0 ? "بدهی کیف‌پول" : "موجودی فعلی"}
            </div>
            <div
              className={cn(
                "mt-1 text-3xl font-extrabold tabular-nums",
                ((walletInfo?.debt || 0) > 0 || (walletInfo?.balance ?? me?.wallet_balance ?? 0) < 0) &&
                  "text-rose-300",
              )}
            >
              {(walletInfo?.debt || 0) > 0
                ? walletInfo?.debt_label || priceText(walletInfo!.debt!)
                : (walletInfo?.balance ?? me?.wallet_balance ?? 0) < 0
                  ? `${priceText(Math.abs(walletInfo?.balance ?? me?.wallet_balance ?? 0))} بدهی`
                  : priceText(walletInfo?.balance ?? me?.wallet_balance ?? 0)}
            </div>
            {(walletInfo?.credit_limit || 0) > 0 ? (
              <p className="mt-2 text-[11px] leading-relaxed text-sky-200/90">
                اعتبار خرید: تا {walletInfo?.credit_limit_label || priceText(walletInfo!.credit_limit!)}
                {(walletInfo?.credit_remaining || 0) > 0
                  ? ` · باقی‌مانده ${walletInfo?.credit_remaining_label || priceText(walletInfo!.credit_remaining!)}`
                  : " · تمام شده"}
              </p>
            ) : null}
            {(walletInfo?.debt || 0) > 0 ? (
              <p className="mt-1.5 text-[11px] leading-relaxed text-amber-200/90">
                با شارژ کیف‌پول، بدهی اول تسویه می‌شود.
              </p>
            ) : (walletInfo?.locked || 0) > 0 ? (
              <p className="mt-2 text-[11px] leading-relaxed text-neutral-400">
                قابل برداشت و انتقال: {walletInfo?.withdrawable_label || priceText(walletInfo?.withdrawable || 0)}
              </p>
            ) : (
              <p className="mt-2 text-[11px] leading-relaxed text-neutral-400">
                از این موجودی می‌توانید بخرید، به کیف‌پول کس دیگری منتقل کنید، یا برداشت بزنید.
              </p>
            )}
          </div>

          <Tabs
            value={walletTab}
            onValueChange={(v) => {
              haptic();
              setWalletTab(v as "deposit" | "transfer" | "withdraw");
            }}
            variant="underline"
            className="w-full"
          >
            <TabsList className="w-full border-white/10">
              <TabsTrigger
                value="deposit"
                className="flex-1 justify-center text-xs sm:text-sm"
                indicatorClassName="h-0.5 bg-foreground"
              >
                شارژ
              </TabsTrigger>
              <TabsTrigger
                value="transfer"
                className="flex-1 justify-center text-xs sm:text-sm"
                indicatorClassName="h-0.5 bg-foreground"
              >
                انتقال
              </TabsTrigger>
              <TabsTrigger
                value="withdraw"
                className="flex-1 justify-center text-xs sm:text-sm"
                indicatorClassName="h-0.5 bg-foreground"
              >
                برداشت
              </TabsTrigger>
            </TabsList>

            <TabsContent value="deposit" className="mt-3 space-y-2">
              {walletInfo?.pending_deposit && (
                <Panel className="space-y-2 !bg-black/30">
                  <div className="text-xs text-neutral-300">
                    شارژ در انتظار تایید: {walletInfo.pending_deposit.amount_label}
                    {walletInfo.pending_deposit.has_receipt ? " · رسید ارسال شده" : " · منتظر رسید"}
                  </div>
                  {!walletInfo.pending_deposit.has_receipt && (
                    <TgButton
                      onClick={() =>
                        void startDeposit(walletInfo.pending_deposit!.amount_toman)
                      }
                    >
                      ادامه ارسال رسید
                    </TgButton>
                  )}
                </Panel>
              )}

              <Label className="text-neutral-300">شارژ کیف‌پول (کارت‌به‌کارت)</Label>
              <div className="flex flex-wrap gap-1.5">
                {(walletInfo?.debt || 0) > 0 ? (
                  <button
                    type="button"
                    onClick={() => setDepositAmount(walletInfo!.debt!)}
                    className={cn(
                      "h-8 rounded-full border px-3 text-xs font-medium",
                      depositAmount === walletInfo!.debt
                        ? "border-rose-400/50 bg-rose-500/20 text-rose-100"
                        : "border-rose-400/30 bg-rose-500/10 text-rose-200",
                    )}
                  >
                    تسویه بدهی · {priceText(walletInfo!.debt!)}
                  </button>
                ) : null}
                {(walletInfo?.presets || [50_000, 100_000, 200_000, 500_000, 1_000_000]).map((p) => (
                  <button
                    key={p}
                    type="button"
                    onClick={() => setDepositAmount(p)}
                    className={cn(
                      "h-8 rounded-full border px-3 text-xs font-medium",
                      depositAmount === p
                        ? "border-primary bg-primary text-primary-foreground"
                        : "border-white/15 bg-black/40 text-neutral-400",
                    )}
                  >
                    {priceText(p)}
                  </button>
                ))}
              </div>
              <div className="flex items-center gap-2">
                <Input
                  type="text"
                  inputMode="numeric"
                  dir="ltr"
                  value={formatAmountInput(depositAmount)}
                  onChange={(e) => setDepositAmount(parseAmountInput(e.target.value))}
                  placeholder="100,000"
                  className="h-11 flex-1 rounded-xl border-white/15 bg-black/40 text-base tabular-nums"
                />
                <span className="shrink-0 text-sm font-medium text-neutral-300">تومان</span>
              </div>
              <p className="text-[11px] text-neutral-500">
                حداقل {walletInfo?.min_deposit_label || priceText(50_000)}
              </p>
              <TgButton
                disabled={busy || depositAmount < (walletInfo?.min_deposit || 50_000)}
                onClick={() => void startDeposit(depositAmount)}
              >
                {depositAmount > 0 ? `شارژ ${priceText(depositAmount)}` : "شارژ / واریز"}
              </TgButton>
            </TabsContent>

            <TabsContent value="transfer" className="mt-3 space-y-2">
              <WalletTransferPanel
                busy={busy}
                balance={walletInfo?.withdrawable ?? walletInfo?.balance ?? me?.wallet_balance ?? 0}
                minTransfer={walletInfo?.min_transfer ?? 1_000}
                minTransferLabel={walletInfo?.min_transfer_label || priceText(1_000)}
                transfers={walletInfo?.transfers || []}
                onBusy={setBusy}
                onNotify={notify}
                onDone={async (walletBalance) => {
                  setMe((m) => (m ? { ...m, wallet_balance: walletBalance } : m));
                  try {
                    setWalletInfo(await api.wallet());
                  } catch {
                    /* ignore */
                  }
                }}
              />
            </TabsContent>

            <TabsContent value="withdraw" className="mt-3 space-y-2">
              {walletInfo?.pending_withdrawal ? (
                <Panel className="space-y-1 !bg-black/30">
                  <div className="text-xs font-semibold text-amber-200">برداشت در انتظار بررسی</div>
                  <div className="text-[11px] text-neutral-400">
                    {walletInfo.pending_withdrawal.amount_label} · کارت منتهی به{" "}
                    <span dir="ltr" className="font-mono">
                      {walletInfo.pending_withdrawal.card_number.replace(/\D/g, "").slice(-4)}
                    </span>
                  </div>
                </Panel>
              ) : (walletInfo?.withdrawable ?? walletInfo?.balance ?? me?.wallet_balance ?? 0) >=
                (walletInfo?.min_withdraw ?? 100_000) ? (
                <>
                  <Label className="text-neutral-300">برداشت به کارت</Label>
                  <Input
                    placeholder="شماره کارت ۱۶ رقمی"
                    value={walletWithdrawCard}
                    onChange={(e) => setWalletWithdrawCard(e.target.value)}
                    dir="ltr"
                    inputMode="numeric"
                    className="h-11 rounded-xl border-white/15 bg-black/40 text-base"
                  />
                  <div className="flex items-center gap-2">
                    <Input
                      type="text"
                      inputMode="numeric"
                      dir="ltr"
                      value={formatAmountInput(walletWithdrawAmount)}
                      onChange={(e) => setWalletWithdrawAmount(parseAmountInput(e.target.value))}
                      placeholder="100,000"
                      className="h-11 flex-1 rounded-xl border-white/15 bg-black/40 text-base tabular-nums"
                    />
                    <span className="shrink-0 text-sm font-medium text-neutral-300">تومان</span>
                  </div>
                  <div className="flex flex-wrap gap-1.5">
                    <button
                      type="button"
                      onClick={() =>
                        setWalletWithdrawAmount(
                          walletInfo?.withdrawable ?? walletInfo?.balance ?? me?.wallet_balance ?? 0,
                        )
                      }
                      className="h-8 rounded-full border border-white/15 bg-black/40 px-3 text-xs font-medium text-neutral-300"
                    >
                      کل موجودی
                    </button>
                  </div>
                  <p className="text-[11px] text-neutral-500">
                    حداقل {walletInfo?.min_withdraw_label || priceText(100_000)} · مبلغ از کیف‌پول کسر و پس از
                    تایید ادمین واریز می‌شود
                  </p>
                  <TgButton
                    variant="outline"
                    disabled={
                      busy ||
                      walletWithdrawCard.replace(/\D/g, "").length < 16 ||
                      walletWithdrawAmount < (walletInfo?.min_withdraw ?? 100_000)
                    }
                    onClick={() => void doWalletWithdraw()}
                  >
                    {walletWithdrawAmount > 0
                      ? `درخواست برداشت ${priceText(walletWithdrawAmount)}`
                      : "درخواست برداشت"}
                  </TgButton>
                </>
              ) : (
                <p className="text-xs text-neutral-400">
                  حداقل موجودی برای برداشت: {walletInfo?.min_withdraw_label || priceText(100_000)}
                </p>
              )}
              {(walletInfo?.withdrawals?.length ?? 0) > 0 && (
                <div className="space-y-1.5 border-t border-white/10 pt-3">
                  <Label className="text-neutral-300">تاریخچه برداشت</Label>
                  {walletInfo!.withdrawals!.slice(0, 8).map((w) => (
                    <div
                      key={w.id}
                      className="flex items-center justify-between gap-2 rounded-xl border border-white/10 bg-black/30 px-3 py-2 text-xs"
                    >
                      <span>
                        #{faNum(w.id)} · {w.amount_label}
                      </span>
                      <span
                        className={cn(
                          "rounded-md px-1.5 py-0.5 text-[10px]",
                          w.status === "paid"
                            ? "bg-emerald-500/15 text-emerald-300"
                            : w.status === "rejected"
                              ? "bg-red-500/15 text-red-300"
                              : "bg-amber-500/15 text-amber-200",
                        )}
                      >
                        {w.status_label}
                      </span>
                    </div>
                  ))}
                </div>
              )}
            </TabsContent>
          </Tabs>

          <TgButton
            variant="outline"
            onClick={() => {
              haptic();
              setOrderHistoryOpen(true);
            }}
          >
            <span className="inline-flex items-center gap-1.5">
              <History className="size-3.5" />
              تاریخچه پرداخت‌ها
            </span>
          </TgButton>

          <TgButton variant="outline" onClick={() => { setWalletOpen(false); switchTab("invite"); }}>
            کسب درآمد با دعوت دوستان
          </TgButton>
        </div>
      </TgSheet>

      <ResellerDeskSheet
        open={resellerOpen}
        onClose={() => setResellerOpen(false)}
        data={resellerDesk}
        onRefresh={refreshResellerDesk}
        onOpenDetail={(subId, tab) => {
          openSubDetail(subId, tab);
        }}
        onBuyForCustomer={() => {
          setResellerOpen(false);
          switchTab("shop");
        }}
      />

      <SubscriptionDetailSheet
        open={detailOpen}
        onClose={() => {
          setDetailOpen(false);
          setDetailSubId(null);
          setDetailInitialTab(null);
        }}
        subId={detailSubId}
        initialTab={detailInitialTab}
        plans={plans}
        onRenewCheckout={handleDetailCheckout}
        onTopup={() => setWalletOpen(true)}
        onRevoked={() => {
          notify("کانفیگ غیرفعال شد", "success");
          void refreshDashboard();
          void refreshResellerDesk();
        }}
        onLinkRotated={() => {
          notify("لینک جدید ساخته شد. لینک قبلی دیگر کار نمی‌کند.", "success");
          void refreshDashboard();
          void refreshResellerDesk();
        }}
        onTransferred={({ targetName, familyMoved, movedCount }) => {
          notify(
            familyMoved
              ? `پکیج خانواده (${faNum(movedCount)} کانفیگ) به ${targetName} منتقل شد`
              : `مالکیت کانفیگ به ${targetName} منتقل شد`,
            "success",
          );
          void refreshDashboard();
          void refreshResellerDesk();
        }}
        onLabelSaved={(subId, label) => {
          setDashItems((items) => items.map((it) => (it.id === subId ? { ...it, label } : it)));
        }}
        onCustomerSaved={(subId, customer) => {
          setDashItems((items) => items.map((it) => (it.id === subId ? { ...it, ...customer } : it)));
          void refreshResellerDesk();
        }}
        onLinkShared={() => {
          void refreshResellerDesk();
        }}
      />

      {me?.is_admin ? (
        <>
        <AdminNotificationCenterSheet
          open={notifOpen}
          onClose={() => setNotifOpen(false)}
          orders={adminOrders}
          withdrawals={adminWds}
          pendingCount={adminPendingCount}
          chatUnread={chatUnread}
          unreadThreads={adminUnreadThreads}
          loading={adminNotifLoading}
          onOpenAdmin={() => {
            setNotifOpen(false);
            switchTab("admin");
          }}
          onOpenChat={() => {
            setNotifOpen(false);
            switchTab("chat");
          }}
          onSelectThread={(t) => {
            setNotifOpen(false);
            setOpenChatThreadUserId(t.user_id);
            switchTab("chat");
          }}
          onSelectOrder={(o) => {
            const full = adminOrders.find((x) => x.id === o.id);
            if (full) {
              setNotifOpen(false);
              setAdminOrderDetail(full);
            }
          }}
        />
        <AdminPendingOrderSheet
          open={!!adminOrderDetail}
          onClose={() => setAdminOrderDetail(null)}
          order={adminOrderDetail}
          busy={busy}
          onApprove={async (id) => {
            setBusy(true);
            try {
              await api.adminApprove(id);
              setAdminOrders(await api.adminPending(adminIncludeTest));
              notify("تایید شد", "success");
            } catch (e) {
              notify(persianError(e instanceof Error ? e.message : "خطا"), "error");
              throw e;
            } finally {
              setBusy(false);
            }
          }}
          onReject={async (id) => {
            setBusy(true);
            try {
              await api.adminReject(id);
              setAdminOrders(await api.adminPending(adminIncludeTest));
              notify("رد شد", "info");
            } catch (e) {
              notify(persianError(e instanceof Error ? e.message : "خطا"), "error");
              throw e;
            } finally {
              setBusy(false);
            }
          }}
          onRefresh={() => {
            void api.adminPending(adminIncludeTest).then(setAdminOrders);
          }}
          onNotify={notify}
        />
        <OrderHistorySheet
          open={adminOrderHistoryOpen}
          onClose={() => setAdminOrderHistoryOpen(false)}
          isAdmin
        />
        </>
      ) : (
        me && (
          <UserNotificationCenterSheet
            open={notifOpen}
            onClose={() => setNotifOpen(false)}
            count={userNotifCount}
            chatUnread={chatUnread}
            unreadMessages={userUnreadMessages}
            pendingOrder={pendingOrder}
            walletPending={walletPending}
            loading={userNotifLoading}
            onOpenChat={() => {
              setNotifOpen(false);
              switchTab("chat");
            }}
            onOpenSubs={() => {
              setNotifOpen(false);
              switchTab("subs");
            }}
            onOpenWallet={() => {
              setNotifOpen(false);
              void openWallet();
            }}
          />
        )
      )}

      <TgSheet
        open={proOpen}
        onClose={() => setProOpen(false)}
        title="Black Lines Pro"
        description={isProMember ? proUntilLabel || "عضو فعال" : "ارتقا و مزایا"}
      >
        {proLoading && !proData ? (
          <OrbLoaderPanel variant="invite" message="در حال بارگذاری Pro…" />
        ) : (
          <ProPanel
            data={proData}
            busy={busy}
            onBuy={() => void buyPro()}
          />
        )}
      </TgSheet>

      <OrderHistorySheet open={orderHistoryOpen} onClose={() => setOrderHistoryOpen(false)} />

      <TrialAccountSheet
        open={trialOpen}
        onClose={() => setTrialOpen(false)}
        trial={trialAccount}
        onOpenDashboard={() => switchTab("subs")}
      />

      <ToastHost toasts={toasts} onDismiss={dismiss} />
    </GradientField>
  );
}
