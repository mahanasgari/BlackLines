export type Plan = {
  id: number;
  title: string;
  description: string;
  price_toman: number;
  price_label: string;
  charge_toman?: number;
  charge_label?: string;
  pro_discount_percent?: number;
  duration_days: number;
  traffic_gb: number;
  traffic_label: string;
  limit_ip: number;
  pro_only?: boolean;
  pay_after_wallet: number;
};

export type ProBenefit = {
  id: string;
  title: string;
  description: string;
  active: boolean;
  coming_soon?: boolean;
};

export type ProInfo = {
  is_pro: boolean;
  pro_until: string | null;
  pro_until_label: string | null;
  discount_percent: number;
  config_count: number;
  plan: {
    id: number;
    title: string;
    description: string;
    price_toman: number;
    price_label: string;
    duration_days: number;
  };
  benefits: ProBenefit[];
};

export type PaymentCard = {
  id: number;
  card: string;
  name: string;
  note?: string;
  label?: string;
};

export type PaymentInfo = {
  card: string;
  name: string;
  note: string;
  cards?: PaymentCard[];
};

export function paymentCardsFrom(info: PaymentInfo): PaymentCard[] {
  if (info.cards?.length) return info.cards;
  if (!info.card) return [];
  return [
    {
      id: 1,
      card: info.card,
      name: info.name,
      note: info.note,
      label: "کارت اصلی",
    },
  ];
}

export type BirthdayGift = {
  granted: boolean;
  amount_toman: number;
  amount_label: string;
  year: number;
  message: string;
};

export type TrialAccount = {
  granted: boolean;
  subscription_id: number;
  email: string;
  links: string[];
  duration_days: number;
  traffic_label: string;
  expires_at: string | null;
  message: string;
};

export type TrialOffer = {
  available: boolean;
  reason?: string | null;
  duration_days: number;
  traffic_gb: number;
  traffic_label: string;
  limit_ip: number;
};

export type TrialSettings = {
  enabled: boolean;
  duration_days: number;
  traffic_gb: number;
  limit_ip: number;
  traffic_label: string;
  send_links?: boolean;
};

export type TrialGrantResult = {
  ok: boolean;
  granted_count: number;
  skipped_count: number;
  failed_count: number;
  total_targets: number;
  not_found: string[];
  granted: { telegram_id: number; username: string | null; email: string }[];
  skipped: { telegram_id: number; username: string | null; reason: string }[];
  failed: { telegram_id: number; username: string | null; error: string }[];
};

export type AdminUser = {
  id: number;
  telegram_id: number;
  username: string | null;
  full_name: string | null;
  role: "user" | "admin";
  is_admin: boolean;
  is_super_admin: boolean;
  wallet_balance: number;
  wallet_label?: string;
  wallet_credit_limit?: number;
  wallet_credit_limit_label?: string | null;
  wallet_debt?: number;
  wallet_debt_label?: string | null;
  wallet_spendable?: number;
  is_pro?: boolean;
  pro_until?: string | null;
  trial_granted?: boolean;
  is_test?: boolean;
  subscription_count: number;
  active_subscription_count?: number;
  pending_order_count?: number;
  chat_unread?: number;
  has_issue?: boolean;
  created_at: string | null;
};

export type AdminUserSubscription = {
  id: number;
  email: string;
  label: string | null;
  plan_title: string;
  created_at?: string | null;
  expires_at: string | null;
  enabled: boolean;
  online?: boolean;
  expired?: boolean;
  is_payg?: boolean;
  is_metered?: boolean;
  status: string;
  used_bytes?: number;
  total_bytes?: number;
  used_label: string;
  total_label?: string;
  remaining_label?: string | null;
  usage_percent?: number;
  remaining_days?: number | null;
  last_online_at?: string | null;
  traffic_label: string;
  limit_ip?: number | null;
  family_role?: string | null;
  customer_name?: string | null;
  source?: "trial" | "gift" | "payg" | "purchase" | string;
  source_label?: string;
  order_id?: number | null;
  order_status?: string | null;
  order_status_label?: string | null;
  order_amount_label?: string | null;
  order_kind_label?: string | null;
  renew_order_id?: number | null;
  renew_status?: string | null;
  renew_status_label?: string | null;
  renew_amount_label?: string | null;
};

export type AdminUserWithdrawal = {
  id: number;
  amount_toman: number;
  amount_label: string;
  card_number: string;
  status: string;
  created_at: string | null;
};

export type AdminUserDetail = AdminUser & {
  subscriptions: AdminUserSubscription[];
  orders: ChatOrderItem[];
  withdrawals: AdminUserWithdrawal[];
};

export type AdminGiftPlan = {
  id: number;
  code: string;
  title: string;
  duration_days: number;
  traffic_gb: number;
  traffic_label: string;
  limit_ip: number;
  price_toman: number;
  price_label: string;
};

export type MoneyStat = {
  toman: number;
  label: string;
};

export type AnalyticsPoint = {
  date: string;
  label: string;
  count: number;
  toman?: number;
  label_money?: string;
};

export type AnalyticsDelta = {
  current: number;
  previous: number;
  delta: number;
  delta_pct: number;
  current_label?: string;
  previous_label?: string;
  delta_label?: string;
};

export type ExpiringItem = {
  user_id: number;
  telegram_id: number;
  username: string | null;
  full_name: string | null;
  subscription_id: number;
  label: string;
  expires_at: string;
  days_left: number;
  days_left_label: string;
  reminded_3d: boolean;
  reminded_1d: boolean;
  is_test?: boolean;
};

export type AnalyticsKindRow = {
  key: string;
  title: string;
  count: number;
  card: number;
  wallet: number;
  toman: number;
  card_label: string;
  wallet_label: string;
  label: string;
  share: number;
};

export type AnalyticsPlanRow = {
  title: string;
  count: number;
  toman: number;
  label: string;
  share: number;
};

export type VpnConfigFlags = {
  reality: boolean;
  ws: boolean;
  http: boolean;
  ws_tls: boolean;
  http_ms: boolean;
  telegram: boolean;
};

export type VpnConfigType = {
  key: keyof VpnConfigFlags | string;
  label: string;
};

export type VpnServer = {
  id: number;
  name: string;
  country_code: string;
  xui_base_url: string;
  token_masked: string;
  inbound_ids: string;
  public_host: string;
  public_ip: string;
  enabled: boolean;
  primary: boolean;
  config_flags?: VpnConfigFlags;
  config_flags_raw?: string;
  health_ok?: boolean;
  health_fail_count?: number;
  last_ping_ms?: number | null;
  last_health_at?: string | null;
  links_visible?: boolean;
};

export type AdminAnalytics = {
  days: number;
  period_label: string;
  include_test?: boolean;
  hidden_test_users?: number;
  compare?: {
    label: string;
    new_users: AnalyticsDelta;
    cash_in: AnalyticsDelta;
    trial_converted: AnalyticsDelta;
  };
  users: {
    kpis: {
      total_users: number;
      new_users: number;
      paying_users: number;
      active_customers: number;
      pro_users: number;
      referred_users: number;
      admins: number;
      with_wallet: number;
      trial_granted: number;
      trial_converted: number;
      expiring?: number;
    };
    signups: AnalyticsPoint[];
    funnel: { key: string; title: string; count: number }[];
    configs: {
      total: number;
      active: number;
      expired: number;
      disabled: number;
      trial: number;
      metered: number;
      prepaid: number;
      regular: number;
      new: number;
      active_share: number;
    };
    activity: {
      online_now: number;
      used_24h: number;
      orders_new: number;
      pending_orders: number;
      chat_total: number;
      chat_from_users: number;
      chat_from_admins: number;
      chat_unread: number;
    };
  };
  finance: {
    kpis: {
      cash_in: MoneyStat;
      product_revenue: MoneyStat;
      wallet_topups: MoneyStat;
      wallet_spent: MoneyStat;
      metered_billed: MoneyStat;
      commissions: MoneyStat;
      withdrawals_paid: MoneyStat;
      withdrawals_pending: MoneyStat;
      pending_orders: MoneyStat;
      wallet_liability: MoneyStat;
      net_cash: MoneyStat;
      estimate_owned: MoneyStat;
      order_count: number;
    };
    kinds: AnalyticsKindRow[];
    plans: AnalyticsPlanRow[];
    daily: AnalyticsPoint[];
    daily_cash: AnalyticsPoint[];
    notes: Record<string, string>;
    pending_order_count: number;
    generated_at: string;
  };
};

export type Me = {
  telegram_id: number;
  username: string | null;
  full_name: string | null;
  wallet_balance: number;
  wallet_debt?: number;
  wallet_credit_limit?: number;
  wallet_spendable?: number;
  is_admin: boolean;
  role?: "user" | "admin";
  shop_name: string;
  payment: PaymentInfo;
  has_birth_date?: boolean;
  birthday_gift?: BirthdayGift | null;
  trial_account?: TrialAccount | null;
  trial_offer?: TrialOffer | null;
  is_pro?: boolean;
  pro_until?: string | null;
};

export type UserProfile = {
  telegram_id: number;
  username: string | null;
  full_name: string | null;
  has_photo: boolean;
  email: string | null;
  phone: string | null;
  has_email: boolean;
  has_phone: boolean;
  birth_date: string | null;
  birth_date_label: string | null;
  birth_date_source: "telegram" | "manual" | string | null;
  birth_date_year_hidden: boolean;
  has_birth_date: boolean;
  needs_birth_date: boolean;
  is_birthday_today: boolean;
  days_until_birthday: number | null;
  birthday_gift_received_year: number | null;
  birthday_gift_amount_toman: number;
  birthday_gift_amount_label: string | null;
  member_since: string | null;
  wallet_balance: number;
  birthday_gift?: BirthdayGift | null;
};

export type Sub = {
  id: number;
  email: string;
  plan_title: string;
  label?: string | null;
  expires_at: string | null;
  traffic_label: string;
  status?: string;
};

export type CustomerMeta = {
  customer_name?: string | null;
  customer_email?: string | null;
  customer_phone?: string | null;
  customer_telegram_id?: string | null;
};

export type DashboardItem = {
  id: number;
  email: string;
  label: string | null;
  plan_title: string;
  expires_at: string | null;
  enabled: boolean;
  online: boolean;
  status: string;
  up_bytes: number;
  down_bytes: number;
  used_bytes: number;
  total_bytes: number;
  used_label: string;
  total_label: string;
  usage_percent: number;
  last_online_ms: number;
  last_online_at: string | null;
  last_seen_label?: string | null;
  limit_ip: number | null;
  traffic_label: string;
  is_payg?: boolean;
  is_metered?: boolean;
  up_label?: string;
  down_label?: string;
  remaining_bytes?: number | null;
  remaining_label?: string;
  today_bytes?: number;
  today_label?: string;
  week_label?: string;
  avg_daily_label?: string;
  days_left?: number | null;
  sparkline?: number[];
  customer_name?: string | null;
  customer_email?: string | null;
  customer_phone?: string | null;
  customer_telegram_id?: string | null;
  family_role?: string | null;
  family_index?: number | null;
  family_group?: string | null;
  subscription_url?: string | null;
  link_shared?: boolean;
};

export type ResellerDeskItem = {
  id: number;
  customer_name: string | null;
  customer_email?: string | null;
  customer_phone?: string | null;
  customer_telegram_id?: string | null;
  label: string | null;
  plan_title: string;
  traffic_label?: string | null;
  expires_at: string | null;
  days_left: number | null;
  expired: boolean;
  enabled: boolean;
  is_payg?: boolean;
  subscription_url: string | null;
  link_shared: boolean;
  link_shared_at: string | null;
  family_role?: string | null;
  hidden?: boolean;
};

export type ResellerDeskSummary = {
  total: number;
  unsent: number;
  expiring_soon: number;
  expired: number;
};

export type ResellerDeskResponse = {
  items: ResellerDeskItem[];
  summary: ResellerDeskSummary;
};

export type UsageDay = {
  day: string;
  label: string;
  used_bytes: number;
  used_label: string;
};

export type UsageAnalytics = {
  today_bytes: number;
  today_label: string;
  week_bytes: number;
  week_label: string;
  avg_daily_bytes: number;
  avg_daily_label: string;
  days_left: number | null;
  peak_day: string | null;
  peak_label: string | null;
  daily: UsageDay[];
  sparkline: number[];
  last_seen_label: string | null;
  remaining_bytes: number | null;
  remaining_label: string;
};

export type ChatOrderItem = {
  id: number;
  plan_title: string;
  kind: "vpn_purchase" | "wallet_topup" | "platform_pro";
  kind_label: string;
  amount_toman: number;
  amount_label: string;
  wallet_used: number;
  wallet_used_label: string | null;
  status: string;
  status_label: string;
  has_receipt: boolean;
  created_at: string | null;
  reviewed_at?: string | null;
  admin_note?: string | null;
  is_wallet_topup?: boolean;
  is_platform_pro?: boolean;
};

export type OrderHistoryItem = ChatOrderItem & {
  user?: string;
  telegram_id?: number;
  username?: string | null;
};

export type ChatAttachment = {
  type: "subscription" | "link" | "order";
  subscription_id?: number;
  email?: string;
  label?: string | null;
  plan_title?: string;
  status?: string | null;
  link?: string | null;
  link_preview?: string | null;
  link_index?: number | null;
  order_id?: number;
  kind?: "vpn_purchase" | "wallet_topup";
  kind_label?: string;
  amount_label?: string;
  wallet_used?: number;
  wallet_used_label?: string | null;
  status?: string | null;
  status_label?: string;
  has_receipt?: boolean;
  created_at?: string | null;
  wallet_used?: number;
  wallet_used_label?: string | null;
};

export type ChatAttachmentInput = {
  type: "subscription" | "link" | "order";
  subscription_id?: number;
  link_index?: number;
  order_id?: number;
};

export type ChatMessage = {
  id: number;
  user_id: number;
  sender: "user" | "admin";
  body: string;
  attachments?: ChatAttachment[];
  created_at: string | null;
  read_at: string | null;
};

export type ChatThread = {
  user_id: number;
  telegram_id: number;
  username: string | null;
  full_name: string | null;
  last_message: string;
  last_message_at: string | null;
  last_sender: "user" | "admin" | null;
  unread_count: number;
};

export type DashboardSummary = {
  total: number;
  online: number;
  offline: number;
  used_bytes?: number;
  used_label?: string;
  up_label?: string;
  down_label?: string;
  today_label?: string;
  week_label?: string;
  remaining_label?: string;
  last_seen_label?: string | null;
  daily?: UsageDay[];
};

export type DashboardArchivedItem = {
  id: number;
  email: string;
  label: string | null;
  plan_title: string;
  expires_at: string | null;
  status: string;
  traffic_label?: string;
  customer_name?: string | null;
  customer_email?: string | null;
  customer_phone?: string | null;
  customer_telegram_id?: string | null;
};

export type DashboardResponse = {
  summary: DashboardSummary;
  items: DashboardItem[];
  archived?: DashboardArchivedItem[];
};

export type PendingOrder = {
  id: number;
  plan_title: string;
  amount_toman: number;
  amount_label: string;
  wallet_used: number;
  has_receipt: boolean;
  is_wallet_topup?: boolean;
  payment: PaymentInfo;
  recipientName?: string | null;
  familySize?: number | null;
};

export type SubscriptionsResponse = {
  items: Sub[];
  pending: PendingOrder | null;
};

export type SubscriptionLinkItem = {
  index: number;
  label: string;
  link: string;
  kind?: "vless" | "telegram" | string;
  host: string | null;
  port: number | null;
  ping_ms: number | null;
  reachable: boolean;
};

export type SubscriptionDetail = {
  id: number;
  email: string;
  label: string | null;
  plan_id: number;
  plan_title: string;
  plan_duration_days: number;
  traffic_label: string;
  limit_ip: number | null;
  customer_name?: string | null;
  customer_email?: string | null;
  customer_phone?: string | null;
  customer_telegram_id?: string | null;
  created_at: string | null;
  expires_at: string | null;
  xui_sub_id: string | null;
  subscription_url: string | null;
  subscription_import: string;
  auto_renew?: boolean;
  family_group?: string | null;
  family_index?: number | null;
  family_role?: string | null;
  parental_categories?: string[];
  family?: {
    group: string;
    is_parent: boolean;
    members: {
      id: number;
      label: string | null;
      email: string;
      family_index: number | null;
      family_role: string;
      is_parent: boolean;
      parental_categories: string[];
      restricted: boolean;
      enabled: boolean;
      used_bytes?: number;
      used_label?: string;
      total_label?: string;
      up_label?: string;
      down_label?: string;
      online?: boolean;
      status?: string;
      last_online_at?: string | null;
      schedule?: ParentalSchedule | null;
      schedule_label?: string | null;
      schedule_active?: boolean;
      vpn_schedule?: ParentalSchedule | null;
      vpn_schedule_label?: string | null;
      vpn_allowed_now?: boolean;
      vpn_schedule_paused?: boolean;
    }[];
    used_bytes?: number;
    used_label?: string;
    parental: {
      enabled: boolean;
      categories: { key: string; label: string; desc: string; domain_count: number }[];
      custom_domains: string[];
      custom_domain_count: number;
    };
  } | null;
  links: SubscriptionLinkItem[];
  links_text: string;
  connection: {
    online: boolean;
    connected_ip_count: number;
    limit_ip: number;
    connected_ips: { ip: string; at: string | null; node: string | null; nickname?: string | null }[];
    ip_available: boolean;
    nickname_presets?: string[];
    last_online_at: string | null;
    history: { at: string | null; event: string; ip?: string }[];
  };
  enabled: boolean;
  online: boolean;
  status: string;
  up_bytes: number;
  down_bytes: number;
  used_bytes: number;
  total_bytes: number;
  used_label: string;
  total_label: string;
  remaining_bytes: number | null;
  remaining_label: string;
  usage_percent: number;
  last_online_ms: number;
  last_online_at: string | null;
  remaining_days: number | null;
  expired: boolean;
  is_payg?: boolean;
  is_metered?: boolean;
  billed_toman?: number;
  billed_label?: string | null;
  up_label?: string;
  down_label?: string;
  usage?: UsageAnalytics;
  source?: string;
  source_label?: string;
  order_id?: number | null;
  order_status?: string | null;
  order_status_label?: string | null;
  order_amount_label?: string | null;
  order_kind_label?: string | null;
  renew_order_id?: number | null;
  renew_status?: string | null;
  renew_status_label?: string | null;
  renew_amount_label?: string | null;
};

export type RenewOrderResponse = {
  id: number;
  amount_toman: number;
  amount_label: string;
  wallet_used: number;
  needs_receipt: boolean;
  wallet_balance: number;
  resumed: boolean;
  renew: boolean;
  target_subscription_id?: number;
  payment: PaymentInfo;
  auto_approved?: boolean;
  status?: string;
};

export type CustomPackageOptions = {
  enabled: boolean;
  min_days: number;
  max_days: number;
  min_gb: number;
  max_gb: number;
  min_ip: number;
  max_ip: number;
  unlimited_allowed?: boolean;
};

export type CustomPackageInput = {
  duration_days: number;
  traffic_gb: number;
  limit_ip: number;
  unlimited: boolean;
  target_subscription_id?: number;
  promo_code?: string;
  family_size?: number;
  config_label?: string;
} & CustomerMeta;

export type CustomPackageQuote = {
  duration_days: number;
  traffic_gb: number;
  limit_ip: number;
  unlimited: boolean;
  title: string;
  traffic_label: string;
  price_toman: number;
  price_label: string;
  charge_toman: number;
  charge_label: string;
  pay_after_wallet: number;
  pro_discount_percent: number;
  discount_toman?: number;
  bonus_days?: number;
  family_size?: number;
  promo_code?: string | null;
};

export type CustomBuilderAdminSettings = CustomPackageOptions & {
  base_fee_toman: number;
  price_per_day_toman: number;
  price_per_gb_toman: number;
  unlimited_day_fee_toman: number;
  price_per_ip_toman: number;
  min_price_toman: number;
};

export type PaygSubscriptionInfo = {
  id: number;
  email: string;
  label: string | null;
  enabled: boolean;
  paused_by_user?: boolean;
  plan_title: string;
};

export type PaygStatus = {
  enabled: boolean;
  price_per_gb_toman: number;
  price_per_gb_label: string;
  unit_price_toman: number;
  unit_price_label: string;
  min_wallet_toman: number;
  min_wallet_label: string;
  limit_ip: number;
  example_100mb_toman: number;
  example_100mb_label: string;
  wallet_balance: number;
  wallet_label: string;
  can_activate: boolean;
  needs_topup: boolean;
  pro_discount_percent: number;
  remaining_bytes: number;
  remaining_label: string;
  used_bytes: number;
  used_label: string;
  billed_toman: number;
  billed_label: string;
  suspended: boolean;
  user_paused?: boolean;
  can_set_enabled?: boolean;
  subscription: PaygSubscriptionInfo | null;
  links?: string[];
  created?: boolean;
  email?: string;
};

export type PaygExisting = {
  id: number;
  email: string;
  label: string | null;
  plan_title: string;
};

export type PaygOptions = {
  enabled: boolean;
  min_gb: number;
  max_gb: number;
  min_ip: number;
  max_ip: number;
  price_per_gb_toman?: number;
  price_per_ip_toman?: number;
  min_price_toman?: number;
  existing?: PaygExisting[];
};

export type PaygQuote = {
  traffic_gb: number;
  limit_ip: number;
  title: string;
  traffic_label: string;
  price_toman: number;
  price_label: string;
  charge_toman: number;
  charge_label: string;
  pay_after_wallet: number;
  pro_discount_percent: number;
};

export type PaygInput = {
  traffic_gb: number;
  limit_ip: number;
  target_subscription_id?: number;
  config_label?: string;
} & CustomerMeta;

export type PaygAdminSettings = {
  enabled: boolean;
  price_per_gb_toman: number;
  prepaid_price_per_gb_toman?: number;
  min_wallet_toman: number;
  limit_ip: number;
  example_100mb_toman?: number;
  min_gb: number;
  max_gb: number;
  min_ip: number;
  max_ip: number;
  price_per_ip_toman: number;
  min_price_toman: number;
};

export type ReferralInvitee = {
  full_name: string | null;
  username: string | null;
  joined_at: string | null;
  vpn_purchase_count: number;
  vpn_purchase_total: number;
  vpn_purchase_label: string;
  commission_earned: number;
  commission_label: string;
  has_purchased: boolean;
};

export type ReferralLeaderboardRow = {
  rank: number;
  display_name: string;
  earned_total: number;
  earned_label: string;
  sales_count: number;
  is_self?: boolean;
};

export type UserWithdrawal = {
  id: number;
  amount_toman: number;
  amount_label: string;
  card_number: string;
  status: string;
  status_label: string;
  created_at: string | null;
  reviewed_at: string | null;
};

export type Referral = {
  invited: number;
  paid_referrals: number;
  earned_total: number;
  wallet: number;
  percent: number;
  min_withdraw: number;
  code: string;
  invite_link: string;
  invite_miniapp?: string;
  earned_label: string;
  wallet_label: string;
  min_withdraw_label: string;
  invitees?: ReferralInvitee[];
  leaderboard?: ReferralLeaderboardRow[];
  withdrawals?: UserWithdrawal[];
};

export type WalletTransferItem = {
  id: number;
  direction: "in" | "out";
  amount_toman: number;
  amount_label: string;
  other_name: string;
  other_telegram_id: number | null;
  created_at: string | null;
};

export type OrderCreated = {
  id: number;
  amount_toman: number;
  amount_label: string;
  wallet_used: number;
  needs_receipt: boolean;
  wallet_balance?: number;
  resumed?: boolean;
  payment: PaymentInfo;
  family_size?: number;
  auto_approved?: boolean;
  status?: string;
  renew?: boolean;
  plan_title?: string;
  is_gift_card?: boolean;
  gift_code?: string;
  kind?: string;
};

export type GiftCardItem = {
  id: number;
  code: string | null;
  plan_id: number;
  plan_title: string;
  status: "available" | "redeemed" | string;
  status_label: string;
  created_at: string | null;
  redeemed_at: string | null;
};

export type ParentalSchedule = {
  enabled: boolean;
  start: string;
  end: string;
  days: number[];
};

export type SubscriptionDiagnose = {
  ok: boolean;
  subscription_id: number;
  enabled: boolean;
  expired: boolean;
  panel_ok: boolean;
  reachable_count: number;
  server_count: number;
  subscription_url: string | null;
  best: { label: string; link: string; host: string | null; port: number | null; ping_ms: number | null } | null;
  issues: { code: string; title: string; hint: string; action: string }[];
  can_rotate: boolean;
  can_renew: boolean;
};

declare global {
  interface Window {
    Telegram?: {
      WebApp?: {
        initData: string;
        initDataUnsafe: {
          start_param?: string;
          user?: {
            id: number;
            first_name?: string;
            last_name?: string;
            username?: string;
            photo_url?: string;
          };
        };
        ready: () => void;
        expand: () => void;
        close: () => void;
        setHeaderColor?: (color: string) => void;
        setBackgroundColor?: (color: string) => void;
        disableVerticalSwipes?: () => void;
        HapticFeedback?: { impactOccurred: (s: string) => void; notificationOccurred?: (s: string) => void };
        themeParams?: Record<string, string>;
        colorScheme?: string;
        MainButton: {
          text: string;
          show: () => void;
          hide: () => void;
          onClick: (cb: () => void) => void;
          offClick: (cb: () => void) => void;
          showProgress: (leaveActive?: boolean) => void;
          hideProgress: () => void;
          setText: (t: string) => void;
          enable: () => void;
          disable: () => void;
        };
        openLink: (url: string) => void;
        openTelegramLink: (url: string) => void;
        showAlert: (msg: string) => void;
        showConfirm: (msg: string, cb: (ok: boolean) => void) => void;
      };
    };
  }
}

export class ApiError extends Error {
  status: number;
  code?: string;
  inviteUrl?: string;
  channel?: string;

  constructor(
    message: string,
    opts?: { status?: number; code?: string; inviteUrl?: string; channel?: string },
  ) {
    super(message);
    this.name = "ApiError";
    this.status = opts?.status ?? 0;
    this.code = opts?.code;
    this.inviteUrl = opts?.inviteUrl;
    this.channel = opts?.channel;
  }
}

function initData(): string {
  return window.Telegram?.WebApp?.initData || "";
}

async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
  const headers = new Headers(init.headers || {});
  const data = initData();
  if (data) headers.set("X-Telegram-Init-Data", data);
  if (!(init.body instanceof FormData) && !headers.has("Content-Type") && init.body) {
    headers.set("Content-Type", "application/json");
  }
  let res: Response;
  try {
    res = await fetch(`/shop/api${path}`, { ...init, headers });
  } catch (e) {
    if (e instanceof DOMException && e.name === "AbortError") {
      throw new ApiError("آپلود طولانی شد — اگر فیلترشکن روشن است خاموش کنید و دوباره بفرستید");
    }
    throw new ApiError("خطا در ارتباط با سرور");
  }
  if (!res.ok) {
    let detail = res.statusText || "request failed";
    if (res.status === 400 && (init.body instanceof FormData)) {
      detail = "ارسال رسید به سرور نرسید. فیلترشکن را خاموش کنید و همان عکس را دوباره بفرستید.";
    }
    let code: string | undefined;
    let inviteUrl: string | undefined;
    let channel: string | undefined;
    try {
      const j = await res.json();
      if (typeof j.detail === "string") {
        detail = j.detail;
      } else if (Array.isArray(j.detail)) {
        detail = j.detail
          .map((d: { msg?: string }) => d?.msg)
          .filter(Boolean)
          .join(" · ") || "request failed";
      } else if (j.detail && typeof j.detail === "object") {
        const d = j.detail as {
          code?: string;
          message?: string;
          invite_url?: string;
          channel?: string;
        };
        code = d.code;
        inviteUrl = d.invite_url;
        channel = d.channel;
        detail = d.message || d.code || JSON.stringify(j.detail);
      } else if (j.detail != null) {
        detail = JSON.stringify(j.detail);
      }
    } catch {
      /* ignore */
    }
    throw new ApiError(detail, { status: res.status, code, inviteUrl, channel });
  }
  return res.json() as Promise<T>;
}

export type AdminPendingOrder = {
  id: number;
  user: string;
  telegram_id: number;
  plan: string;
  amount_toman: number;
  amount_label: string;
  wallet_used: number;
  has_receipt: boolean;
  is_wallet_topup?: boolean;
  is_platform_pro?: boolean;
  promo_code?: string | null;
  discount_toman?: number;
  bonus_days?: number;
  family_size?: number;
  is_test?: boolean;
};

async function fetchBlob(path: string): Promise<Blob> {
  const headers = new Headers();
  const data = initData();
  if (data) headers.set("X-Telegram-Init-Data", data);
  const res = await fetch(`/shop/api${path}`, { headers });
  if (!res.ok) {
    let detail = res.statusText || "request failed";
    try {
      const j = await res.json();
      if (typeof j.detail === "string") detail = j.detail;
    } catch {
      /* ignore */
    }
    throw new Error(detail);
  }
  return res.blob();
}

export type ActivityLogItem = {
  id: number;
  action: string;
  action_label: string;
  category: string;
  category_label: string;
  actor_role: string;
  actor_user_id: number | null;
  actor_telegram_id: number | null;
  actor_name: string;
  target_user_id: number | null;
  target_name: string | null;
  target_subscription_id: number | null;
  detail: string | null;
  path: string | null;
  created_at: string | null;
};

export type ActivityLogPage = {
  items: ActivityLogItem[];
  total: number;
  limit: number;
  offset: number;
};

export const api = {
  me: () => request<Me>("/me"),
  channelStatus: () =>
    request<{
      required: boolean;
      member: boolean;
      channel: string | null;
      invite_url: string | null;
      message?: string;
    }>("/channel"),
  profile: () => request<UserProfile>("/profile"),
  profilePhoto: () => fetchBlob("/profile/photo"),
  saveBirthDate: (birth_date: string) =>
    request<UserProfile>("/profile/birth-date", {
      method: "POST",
      body: JSON.stringify({ birth_date }),
    }),
  saveProfileContact: (body: { email?: string; phone?: string }) =>
    request<UserProfile>("/profile/contact", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  adminBirthdayGift: () =>
    request<{ enabled: boolean; amount_toman: number; amount_label: string }>("/admin/birthday-gift"),
  adminSetBirthdayGift: (body: { enabled: boolean; amount_toman: number }) =>
    request<{ ok: boolean; enabled: boolean; amount_toman: number; amount_label: string }>(
      "/admin/birthday-gift",
      {
        method: "POST",
        body: JSON.stringify(body),
      },
    ),
  adminTrialSettings: () => request<TrialSettings>("/admin/trial-settings"),
  adminCustomSettings: () => request<CustomBuilderAdminSettings>("/admin/custom-settings"),
  adminSetCustomSettings: (body: CustomBuilderAdminSettings) =>
    request<CustomBuilderAdminSettings>("/admin/custom-settings", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  adminSetTrialSettings: (body: TrialSettings) =>
    request<TrialSettings>("/admin/trial-settings", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  adminGrantTrial: (body: {
    targets_text?: string;
    all_users?: boolean;
    skip_existing_trial?: boolean;
    notify_users?: boolean;
    duration_days?: number;
    traffic_gb?: number;
    limit_ip?: number;
  }) =>
    request<TrialGrantResult>("/admin/trial-grant", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  adminUsers: (q = "", includeTest = false, slice = "", days = 0) =>
    request<{ items: AdminUser[]; title?: string; key?: string }>(
      `/admin/users?q=${encodeURIComponent(q)}&include_test=${includeTest ? "true" : "false"}&slice=${encodeURIComponent(slice)}&days=${days}`,
    ),
  adminAnalytics: (days = 30, includeTest = false) =>
    request<AdminAnalytics>(`/admin/analytics?days=${days}&include_test=${includeTest ? "true" : "false"}`),
  adminExpiring: (days = 3, includeTest = false) =>
    request<{ items: ExpiringItem[]; count: number; days: number }>(
      `/admin/expiring?days=${days}&include_test=${includeTest ? "true" : "false"}`,
    ),
  adminRemindExpiry: (subId: number) =>
    request<{ ok: boolean; subscription_id: number }>(`/admin/subscriptions/${subId}/remind-expiry`, {
      method: "POST",
      body: "{}",
    }),
  adminSetUserTest: (userId: number, is_test: boolean) =>
    request<{ ok: boolean; user: AdminUser }>(`/admin/users/${userId}/test-flag`, {
      method: "POST",
      body: JSON.stringify({ is_test }),
    }),
  adminServers: () => request<{ items: VpnServer[]; config_types: VpnConfigType[] }>("/admin/servers"),
  adminAddServer: (body: {
    name: string;
    country_code: string;
    xui_base_url: string;
    xui_api_token: string;
    inbound_ids: string;
    public_host: string;
    public_ip: string;
  }) =>
    request<{ ok: boolean; items: VpnServer[]; config_types: VpnConfigType[] }>("/admin/servers", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  adminSetServerEnabled: (id: number, enabled: boolean) =>
    request<{ ok: boolean; items: VpnServer[]; config_types: VpnConfigType[] }>(`/admin/servers/${id}/enabled`, {
      method: "POST",
      body: JSON.stringify({ enabled }),
    }),
  adminSetServerVisibility: (
    id: number,
    body: { enabled?: boolean; configs?: Partial<VpnConfigFlags> },
  ) =>
    request<{ ok: boolean; items: VpnServer[]; config_types: VpnConfigType[] }>(
      `/admin/servers/${id}/visibility`,
      { method: "POST", body: JSON.stringify(body) },
    ),
  adminSyncServer: (id: number) =>
    request<{
      ok: boolean;
      synced: number;
      skipped: number;
      failed: number;
      telegram_attached?: number;
      telegram_skipped?: number;
      telegram_failed?: number;
      errors: string[];
    }>(`/admin/servers/${id}/sync`, { method: "POST", body: "{}" }),
  adminDeleteServer: (id: number) =>
    request<{ ok: boolean; items: VpnServer[]; config_types: VpnConfigType[] }>(`/admin/servers/${id}/delete`, {
      method: "POST",
      body: "{}",
    }),
  adminUserDetail: (userId: number) => request<AdminUserDetail>(`/admin/users/${userId}`),
  adminSetUserRole: (userId: number, role: "user" | "admin") =>
    request<{ ok: boolean; user: AdminUser }>(`/admin/users/${userId}/role`, {
      method: "POST",
      body: JSON.stringify({ role }),
    }),
  adminAdjustWallet: (userId: number, amount_toman: number, note = "") =>
    request<{ ok: boolean; user: AdminUserDetail }>(`/admin/users/${userId}/wallet`, {
      method: "POST",
      body: JSON.stringify({ amount_toman, note }),
    }),
  adminSetWalletCredit: (userId: number, credit_limit_toman: number) =>
    request<{ ok: boolean; user: AdminUserDetail }>(`/admin/users/${userId}/wallet-credit`, {
      method: "POST",
      body: JSON.stringify({ credit_limit_toman }),
    }),
  adminConvertWalletToCredit: (userId: number, original_topup_toman: number) =>
    request<{ ok: boolean; user: AdminUserDetail }>(`/admin/users/${userId}/wallet-convert-credit`, {
      method: "POST",
      body: JSON.stringify({ original_topup_toman }),
    }),
  adminSetSubEnabled: (userId: number, subId: number, enabled: boolean) =>
    request<{ ok: boolean; user: AdminUserDetail }>(
      `/admin/users/${userId}/subscriptions/${subId}/enabled`,
      { method: "POST", body: JSON.stringify({ enabled }) },
    ),
  adminGiftPlans: () =>
    request<{ items: AdminGiftPlan[] }>("/admin/gift-plans"),
  adminGrantPro: (userId: number, days?: number) =>
    request<{ ok: boolean; user: AdminUserDetail }>(`/admin/users/${userId}/pro`, {
      method: "POST",
      body: JSON.stringify(days != null ? { days } : {}),
    }),
  adminGiftSubscription: (userId: number, planId: number) =>
    request<{ ok: boolean; subscription_id: number; user: AdminUserDetail }>(
      `/admin/users/${userId}/subscriptions`,
      { method: "POST", body: JSON.stringify({ plan_id: planId }) },
    ),
  adminDeleteSubscription: (userId: number, subId: number) =>
    request<{ ok: boolean; user: AdminUserDetail }>(
      `/admin/users/${userId}/subscriptions/${subId}/delete`,
      { method: "POST", body: "{}" },
    ),
  proInfo: () => request<ProInfo>("/pro"),
  proOrder: () =>
    request<OrderCreated & { is_platform_pro?: boolean }>("/pro/order", { method: "POST", body: "{}" }),
  plans: () => request<Plan[]>("/plans"),
  claimTrial: () => request<TrialAccount>("/trial/claim", { method: "POST", body: "{}" }),
  customOptions: () => request<CustomPackageOptions>("/custom/options"),
  customQuote: (body: CustomPackageInput) =>
    request<CustomPackageQuote>("/custom/quote", { method: "POST", body: JSON.stringify(body) }),
  customOrder: (body: CustomPackageInput) =>
    request<OrderCreated & { custom?: boolean; plan_title?: string }>("/custom/order", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  paygStatus: () => request<PaygStatus>("/payg/status"),
  paygActivate: () => request<PaygStatus>("/payg/activate", { method: "POST", body: "{}" }),
  paygSetEnabled: (enabled: boolean) =>
    request<PaygStatus>("/payg/set-enabled", {
      method: "POST",
      body: JSON.stringify({ enabled }),
    }),
  paygOptions: () => request<PaygOptions>("/payg/options"),
  paygQuote: (body: PaygInput) =>
    request<PaygQuote>("/payg/quote", { method: "POST", body: JSON.stringify(body) }),
  paygOrder: (body: PaygInput) =>
    request<OrderCreated & { payg?: boolean; plan_title?: string; renew?: boolean }>("/payg/order", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  adminPaygSettings: () => request<PaygAdminSettings>("/admin/payg-settings"),
  adminSetPaygSettings: (body: PaygAdminSettings) =>
    request<PaygAdminSettings>("/admin/payg-settings", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  createOrder: (
    plan_id: number,
    opts?: { promo_code?: string; family_size?: number; config_label?: string; gift_card?: boolean } & CustomerMeta,
  ) =>
    request<
      OrderCreated & {
        promo_code?: string | null;
        discount_toman?: number;
        bonus_days?: number;
        family_size?: number;
      }
    >("/orders", {
      method: "POST",
      body: JSON.stringify({
        plan_id,
        promo_code: opts?.promo_code || undefined,
        family_size: opts?.family_size || 1,
        config_label: opts?.config_label || undefined,
        gift_card: opts?.gift_card || undefined,
        customer_name: opts?.customer_name || undefined,
        customer_email: opts?.customer_email || undefined,
        customer_phone: opts?.customer_phone || undefined,
        customer_telegram_id: opts?.customer_telegram_id || undefined,
      }),
    }),
  growthOptions: () =>
    request<{
      family: { enabled: boolean; min_size: number; max_size: number; extra_discount_percent?: number };
      purchase_discount_percent?: number;
    }>("/growth/options"),
  adminDiscountSettings: () =>
    request<{ purchase_discount_percent: number; family_extra_discount_percent: number }>(
      "/admin/discount-settings",
    ),
  adminSetDiscountSettings: (body: {
    purchase_discount_percent: number;
    family_extra_discount_percent: number;
  }) =>
    request<{ purchase_discount_percent: number; family_extra_discount_percent: number }>(
      "/admin/discount-settings",
      { method: "POST", body: JSON.stringify(body) },
    ),
  validatePromo: (body: {
    code: string;
    plan_id?: number;
    family_size?: number;
    duration_days?: number;
    traffic_gb?: number;
    limit_ip?: number;
    unlimited?: boolean;
  }) =>
    request<{
      charge_toman: number;
      charge_label: string;
      discount_toman: number;
      bonus_days: number;
      family_size: number;
      promo_code: string | null;
      promo_kind: string | null;
      promo_value: number | null;
    }>("/promo/validate", { method: "POST", body: JSON.stringify(body) }),
  adminPromoCodes: () =>
    request<{
      items: {
        id: number;
        code: string;
        kind: string;
        value: number;
        max_uses: number;
        used_count: number;
        per_user_limit: number;
        enabled: boolean;
        kind_label: string;
        value_label: string;
        note: string | null;
      }[];
    }>("/admin/promo-codes"),
  adminCreatePromo: (body: {
    code: string;
    kind: "percent" | "free_days";
    value: number;
    max_uses?: number;
    per_user_limit?: number;
    enabled?: boolean;
    note?: string;
  }) =>
    request<{ ok: boolean }>("/admin/promo-codes", { method: "POST", body: JSON.stringify(body) }),
  adminSetPromoEnabled: (id: number, enabled: boolean) =>
    request<{ ok: boolean }>(`/admin/promo-codes/${id}/enabled`, {
      method: "POST",
      body: JSON.stringify({ enabled }),
    }),
  adminFamilySettings: () =>
    request<{ enabled: boolean; min_size: number; max_size: number; extra_discount_percent: number }>(
      "/admin/family-settings",
    ),
  adminSetFamilySettings: (body: {
    enabled: boolean;
    max_size: number;
    extra_discount_percent: number;
  }) =>
    request<{ enabled: boolean; min_size: number; max_size: number; extra_discount_percent: number }>(
      "/admin/family-settings",
      { method: "POST", body: JSON.stringify(body) },
    ),
  cancelOrder: (orderId: number) =>
    request<{ ok: boolean; wallet_balance: number }>(`/orders/${orderId}/cancel`, {
      method: "POST",
      body: "{}",
    }),
  uploadReceipt: async (orderId: number, file: File) => {
    const { prepareReceiptFile } = await import("@/lib/receipt-file");
    const prepared = await prepareReceiptFile(file);
    const fd = new FormData();
    fd.append("file", prepared, prepared.name || "receipt.jpg");
    const ctrl = new AbortController();
    const timer = window.setTimeout(() => ctrl.abort(), 45_000);
    try {
      return await request<{ ok: boolean }>(`/orders/${orderId}/receipt`, {
        method: "POST",
        body: fd,
        signal: ctrl.signal,
      });
    } finally {
      window.clearTimeout(timer);
    }
  },
  fetchOrderReceiptBlob: async (orderId: number) => {
    const blob = await fetchBlob(`/orders/${orderId}/receipt`);
    return {
      url: URL.createObjectURL(blob),
      isPdf: blob.type === "application/pdf",
    };
  },
  confirmWallet: (orderId: number) =>
    request<{ ok: boolean }>(`/orders/${orderId}/confirm-wallet`, { method: "POST", body: "{}" }),
  subscriptions: () => request<SubscriptionsResponse>("/subscriptions"),
  dashboard: () => request<DashboardResponse>("/dashboard"),
  setLabel: (subId: number, label: string) =>
    request<{ ok: boolean; id: number; label: string | null }>(`/subscriptions/${subId}/label`, {
      method: "POST",
      body: JSON.stringify({ label }),
    }),
  setCustomer: (subId: number, body: CustomerMeta) =>
    request<{ ok: boolean; id: number } & CustomerMeta>(`/subscriptions/${subId}/customer`, {
      method: "POST",
      body: JSON.stringify(body),
    }),
  links: (subId: number) => request<{ email: string; links: string[] }>(`/subscriptions/${subId}/links`),
  subscriptionDetail: (subId: number) => request<SubscriptionDetail>(`/subscriptions/${subId}/detail`),
  setAutoRenew: (subId: number, enabled: boolean) =>
    request<{ ok: boolean; auto_renew: boolean }>(`/subscriptions/${subId}/auto-renew`, {
      method: "POST",
      body: JSON.stringify({ enabled }),
    }),
  setIpNickname: (subId: number, ip: string, nickname: string) =>
    request<{ ok: boolean; ip: string; nickname: string | null; nicknames: Record<string, string> }>(
      `/subscriptions/${subId}/ip-nickname`,
      { method: "POST", body: JSON.stringify({ ip, nickname }) },
    ),
  adminBulkGift: (body: {
    kind: "pro" | "plan";
    plan_id?: number;
    pro_days?: number;
    targets_text?: string;
    all_users?: boolean;
    notify_users?: boolean;
  }) =>
    request<{
      granted_count: number;
      failed_count: number;
      not_found: string[];
      total_targets: number;
      granted: unknown[];
      failed: unknown[];
    }>("/admin/bulk-gift", { method: "POST", body: JSON.stringify(body) }),
  adminTransferSubscription: (subId: number, target: string, notify = true) =>
    request<{ ok: boolean; subscription_id: number; email: string }>(
      `/admin/subscriptions/${subId}/transfer`,
      { method: "POST", body: JSON.stringify({ target, notify }) },
    ),
  myActivity: (limit = 40, offset = 0) =>
    request<ActivityLogPage>(`/activity?limit=${limit}&offset=${offset}`),
  adminAuditLog: (opts?: {
    limit?: number;
    offset?: number;
    q?: string;
    actorKind?: string;
    category?: string;
    includeTest?: boolean;
  }) => {
    const limit = opts?.limit ?? 80;
    const offset = opts?.offset ?? 0;
    const q = encodeURIComponent(opts?.q || "");
    const actorKind = encodeURIComponent(opts?.actorKind || "");
    const category = encodeURIComponent(opts?.category || "");
    const includeTest = opts?.includeTest ? "true" : "false";
    return request<ActivityLogPage>(
      `/admin/audit-log?limit=${limit}&offset=${offset}&q=${q}&actor_kind=${actorKind}&category=${category}&include_test=${includeTest}`,
    );
  },
  familyChildActivity: (parentSubId: number, childId: number, limit = 80) =>
    request<{
      child: {
        id: number;
        label: string | null;
        email: string;
        family_role: string;
        parental_categories: string[];
        restricted: boolean;
      };
      logging: { ready: boolean; note: string };
      summary: { domains: number; hits: number; blocked: number; downloads: number };
      sites: {
        domain: string;
        category: string;
        category_label: string;
        verdict: string;
        verdict_label: string;
        hit_count: number;
        first_seen: string | null;
        last_seen: string | null;
      }[];
      recent: {
        domain: string;
        category: string;
        category_label: string;
        verdict: string;
        verdict_label: string;
        seen_at: string | null;
      }[];
      disclaimer: string;
    }>(`/subscriptions/${parentSubId}/family/${childId}/activity?limit=${limit}`),
  restrictFamilyChild: (
    parentSubId: number,
    childId: number,
    categories: string[],
    schedule?: ParentalSchedule | null,
    vpnSchedule?: ParentalSchedule | null,
  ) =>
    request<{
      ok: boolean;
      child: {
        id: number;
        label: string | null;
        parental_categories: string[];
        restricted: boolean;
        schedule?: ParentalSchedule | null;
        schedule_label?: string | null;
        schedule_active?: boolean;
        vpn_schedule?: ParentalSchedule | null;
        vpn_schedule_label?: string | null;
        vpn_allowed_now?: boolean;
        vpn_schedule_paused?: boolean;
      };
    }>(`/subscriptions/${parentSubId}/family/${childId}/restrict`, {
      method: "POST",
      body: JSON.stringify({
        categories,
        schedule: schedule || null,
        vpn_schedule: vpnSchedule || null,
      }),
    }),
  diagnoseSubscription: (subId: number) =>
    request<SubscriptionDiagnose>(`/subscriptions/${subId}/diagnose`, { method: "POST", body: "{}" }),
  giftCards: () => request<{ items: GiftCardItem[] }>("/gift-cards"),
  resellerDesk: () => request<ResellerDeskResponse>("/reseller-desk"),
  markLinkShared: (subId: number, shared = true) =>
    request<{ ok: boolean; id: number; link_shared: boolean; link_shared_at: string | null }>(
      `/subscriptions/${subId}/link-shared`,
      { method: "POST", body: JSON.stringify({ shared }) },
    ),
  redeemGiftCard: (code: string) =>
    request<{
      ok: boolean;
      subscription_id: number;
      plan_title: string;
      subscription_url: string | null;
    }>("/gift-cards/redeem", {
      method: "POST",
      body: JSON.stringify({ code }),
    }),
  parentalOptions: () =>
    request<{
      enabled: boolean;
      categories: { key: string; label: string; desc: string; domain_count: number }[];
      custom_domains: string[];
    }>("/parental/options"),
  adminParentalSettings: () =>
    request<{
      enabled: boolean;
      categories: { key: string; label: string; desc: string; domain_count: number }[];
      custom_domains: string[];
    }>("/admin/parental-settings"),
  adminSetParentalSettings: (body: { enabled: boolean; custom_domains: string[] }) =>
    request<{
      enabled: boolean;
      categories: { key: string; label: string; desc: string; domain_count: number }[];
      custom_domains: string[];
      sync?: { ok: boolean; panels: number; rule_groups: number };
    }>("/admin/parental-settings", { method: "POST", body: JSON.stringify(body) }),
  renewSubscription: (subId: number, planId: number) =>
    request<RenewOrderResponse>(`/subscriptions/${subId}/renew`, {
      method: "POST",
      body: JSON.stringify({ plan_id: planId }),
    }),
  revokeSubscription: (subId: number) =>
    request<{ ok: boolean; enabled: boolean }>(`/subscriptions/${subId}/revoke`, {
      method: "POST",
      body: "{}",
    }),
  rotateSubscriptionLink: (subId: number) =>
    request<{
      ok: boolean;
      id: number;
      xui_uuid: string | null;
      xui_sub_id: string | null;
      subscription_url: string | null;
      subscription_import: string;
      links: string[];
    }>(`/subscriptions/${subId}/rotate-link`, {
      method: "POST",
      body: "{}",
    }),
  lookupTransferTarget: (q: string) =>
    request<{
      ok: boolean;
      user: { telegram_id: number; username: string | null; full_name: string | null };
    }>(`/transfer/lookup?q=${encodeURIComponent(q.trim())}`),
  transferSubscription: (subId: number, target: string) =>
    request<{
      ok: boolean;
      subscription_id: number;
      moved_ids: number[];
      moved_count: number;
      family_moved: boolean;
      email: string;
      target: { telegram_id: number; username: string | null; full_name: string | null };
    }>(`/subscriptions/${subId}/transfer`, {
      method: "POST",
      body: JSON.stringify({ target, notify: true }),
    }),
  hideSubscription: (subId: number) =>
    request<{ ok: boolean; hidden: boolean }>(`/subscriptions/${subId}/hide`, {
      method: "POST",
      body: "{}",
    }),
  unhideSubscription: (subId: number) =>
    request<{ ok: boolean; hidden: boolean }>(`/subscriptions/${subId}/unhide`, {
      method: "POST",
      body: "{}",
    }),
  referral: () => request<Referral>("/referral"),
  withdraw: (card_number: string, amount?: number) =>
    request<{ ok: boolean; id: number }>("/withdraw", {
      method: "POST",
      body: JSON.stringify({ card_number, amount }),
    }),
  adminPending: (includeTest = false) =>
    request<AdminPendingOrder[]>(`/admin/pending-orders?include_test=${includeTest ? "true" : "false"}`),
  adminApprove: (id: number) => request<{ ok: boolean }>(`/admin/orders/${id}/approve`, { method: "POST", body: "{}" }),
  adminReject: (id: number) => request<{ ok: boolean }>(`/admin/orders/${id}/reject`, { method: "POST", body: "{}" }),
  adminUploadReceipt: async (orderId: number, file: File) => {
    const fd = new FormData();
    fd.append("file", file);
    return request<{ ok: boolean; has_receipt: boolean }>(`/admin/orders/${orderId}/receipt`, {
      method: "POST",
      body: fd,
    });
  },
  orderHistory: (opts?: { status?: string; limit?: number; offset?: number }) => {
    const p = new URLSearchParams();
    if (opts?.status) p.set("status", opts.status);
    if (opts?.limit != null) p.set("limit", String(opts.limit));
    if (opts?.offset != null) p.set("offset", String(opts.offset));
    const q = p.toString();
    return request<{ items: OrderHistoryItem[]; total: number }>(`/orders/history${q ? `?${q}` : ""}`);
  },
  adminOrderHistory: (opts?: { q?: string; status?: string; user_id?: number; limit?: number; offset?: number }) => {
    const p = new URLSearchParams();
    if (opts?.q) p.set("q", opts.q);
    if (opts?.status) p.set("status", opts.status);
    if (opts?.user_id != null) p.set("user_id", String(opts.user_id));
    if (opts?.limit != null) p.set("limit", String(opts.limit));
    if (opts?.offset != null) p.set("offset", String(opts.offset));
    const q = p.toString();
    return request<{ items: OrderHistoryItem[]; total: number }>(`/admin/orders/history${q ? `?${q}` : ""}`);
  },
  adminWithdrawals: (includeTest = false) =>
    request<{ id: number; user: string; telegram_id: number; amount_label: string; card_number: string; is_test?: boolean }[]>(
      `/admin/withdrawals?include_test=${includeTest ? "true" : "false"}`,
    ),
  adminPayWd: (id: number) => request<{ ok: boolean }>(`/admin/withdrawals/${id}/pay`, { method: "POST", body: "{}" }),
  adminRejectWd: (id: number) =>
    request<{ ok: boolean }>(`/admin/withdrawals/${id}/reject`, { method: "POST", body: "{}" }),
  adminBroadcast: (message: string) =>
    request<{ ok: boolean; sent: number; total: number }>("/admin/broadcast", {
      method: "POST",
      body: JSON.stringify({ message }),
    }),
  adminPaymentCards: () => request<PaymentCard[]>("/admin/payment-cards"),
  adminAddPaymentCard: (body: { card: string; name: string; label?: string; note?: string }) =>
    request<{ ok: boolean; cards: PaymentCard[] }>("/admin/payment-cards", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  adminRemovePaymentCard: (id: number) =>
    request<{ ok: boolean; cards: PaymentCard[] }>(`/admin/payment-cards/${id}`, {
      method: "DELETE",
    }),
  chatMessages: (after_id = 0, mark_read = false) =>
    request<{ messages: ChatMessage[]; unread_count: number; latest_id: number }>(
      `/chat/messages?after_id=${after_id}${mark_read ? "&mark_read=1" : ""}`,
    ),
  chatMarkRead: () =>
    request<{ ok: boolean; marked: number; unread_count: number }>("/chat/read", {
      method: "POST",
      body: "{}",
    }),
  chatSend: (body: string, attachments: ChatAttachmentInput[] = []) =>
    request<{ ok: boolean; message: ChatMessage }>("/chat/messages", {
      method: "POST",
      body: JSON.stringify({ body, attachments }),
    }),
  chatUnread: () => request<{ unread_count: number }>("/chat/unread"),
  chatOrders: () => request<{ items: ChatOrderItem[] }>("/chat/orders"),
  adminChatThreads: () =>
    request<{ threads: ChatThread[]; unread_total: number }>("/admin/chat/threads"),
  adminChatMessages: (userId: number, after_id = 0, mark_read = false) =>
    request<{
      user: { id: number; telegram_id: number; username: string | null; full_name: string | null };
      messages: ChatMessage[];
      unread_count: number;
      latest_id: number;
      unread_total: number;
    }>(
      `/admin/chat/threads/${userId}/messages?after_id=${after_id}${mark_read ? "&mark_read=1" : ""}`,
    ),
  adminChatMarkRead: (userId: number) =>
    request<{ ok: boolean; marked: number; unread_total: number }>(
      `/admin/chat/threads/${userId}/read`,
      { method: "POST", body: "{}" },
    ),
  adminChatSend: (userId: number, body: string, attachments: ChatAttachmentInput[] = []) =>
    request<{ ok: boolean; message: ChatMessage }>(`/admin/chat/threads/${userId}/messages`, {
      method: "POST",
      body: JSON.stringify({ body, attachments }),
    }),
  adminThreadSubscriptions: (userId: number) =>
    request<{ items: Sub[] }>(`/admin/chat/threads/${userId}/subscriptions`),
  adminThreadOrders: (userId: number) =>
    request<{ items: ChatOrderItem[] }>(`/admin/chat/threads/${userId}/orders`),
  wallet: () =>
    request<{
      balance: number;
      balance_label: string;
      locked?: number;
      locked_label?: string | null;
      withdrawable?: number;
      withdrawable_label?: string;
      credit_limit?: number;
      credit_limit_label?: string | null;
      debt?: number;
      debt_label?: string | null;
      spendable?: number;
      spendable_label?: string;
      credit_remaining?: number;
      credit_remaining_label?: string | null;
      min_deposit: number;
      min_deposit_label: string;
      max_deposit: number;
      max_deposit_label: string;
      min_withdraw: number;
      min_withdraw_label: string;
      min_transfer?: number;
      min_transfer_label?: string;
      presets: number[];
      transfers?: WalletTransferItem[];
      payment: PaymentInfo;
      pending_deposit: { id: number; amount_toman: number; amount_label: string; has_receipt: boolean } | null;
      pending_withdrawal: {
        id: number;
        amount_toman: number;
        amount_label: string;
        card_number: string;
      } | null;
      withdrawals?: UserWithdrawal[];
    }>("/wallet"),
  walletDeposit: (amount_toman: number) =>
    request<OrderCreated>("/wallet/deposit", {
      method: "POST",
      body: JSON.stringify({ amount_toman }),
    }),
  walletTransfer: (target: string, amount_toman: number) =>
    request<{
      ok: boolean;
      id: number;
      amount_toman: number;
      amount_label: string;
      wallet_balance: number;
      wallet_label: string;
      target: { telegram_id: number; username: string | null; full_name: string | null };
    }>("/wallet/transfer", {
      method: "POST",
      body: JSON.stringify({ target, amount_toman }),
    }),
};

export function haptic(kind: "light" | "medium" | "heavy" = "light") {
  window.Telegram?.WebApp?.HapticFeedback?.impactOccurred(kind);
}

export function toast(msg: string) {
  window.Telegram?.WebApp?.showAlert(msg);
}
