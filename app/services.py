from __future__ import annotations

import json
import logging
import math
import secrets
import string
from datetime import date, datetime, timedelta
from typing import Any

from sqlalchemy import delete, func, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, aliased, selectinload

from app.models import (
    ChatMessage,
    Commission,
    Order,
    OrderStatus,
    Plan,
    ShopSetting,
    Subscription,
    UsageSample,
    User,
    WalletTransfer,
    WithdrawStatus,
    Withdrawal,
)
from app.panel import (
    PanelError,
    XUIPanel,
    build_subscription_url,
    public_links_for_email,
    sanitize_config_name,
    subscription_import_base64,
)

logger = logging.getLogger(__name__)

DEFAULT_REFERRAL_PERCENT = 15
DEFAULT_MIN_WITHDRAW = 100_000
DEFAULT_BIRTHDAY_GIFT = 50_000
DEFAULT_BIRTHDAY_GIFT_ENABLED = "0"
BIRTHDAY_GIFT_SETTING = "birthday_gift_toman"
BIRTHDAY_GIFT_ENABLED_SETTING = "birthday_gift_enabled"
WALLET_TOPUP_CODE = "wallet-topup"
PLATFORM_PRO_CODE = "platform-pro"
TRIAL_PLAN_CODE = "test-trial"
CUSTOM_PLAN_CODE = "custom-vpn"
PAYG_PLAN_CODE = "payg-vpn"
USER_ROLE_USER = "user"
USER_ROLE_ADMIN = "admin"
PRO_DISCOUNT_SETTING = "pro_discount_percent"
DEFAULT_PRO_DISCOUNT = 30
CUSTOM_BUILDER_ENABLED = "custom_builder_enabled"
CUSTOM_MIN_DAYS_SETTING = "custom_min_days"
CUSTOM_MAX_DAYS_SETTING = "custom_max_days"
CUSTOM_MIN_GB_SETTING = "custom_min_gb"
CUSTOM_MAX_GB_SETTING = "custom_max_gb"
CUSTOM_MIN_IP_SETTING = "custom_min_ip"
CUSTOM_MAX_IP_SETTING = "custom_max_ip"
CUSTOM_PRICE_PER_DAY_SETTING = "custom_price_per_day_toman"
CUSTOM_PRICE_PER_GB_SETTING = "custom_price_per_gb_toman"
CUSTOM_UNLIMITED_DAY_FEE_SETTING = "custom_unlimited_day_fee_toman"
CUSTOM_PRICE_PER_IP_SETTING = "custom_price_per_ip_toman"
CUSTOM_MIN_PRICE_SETTING = "custom_min_price_toman"
CUSTOM_BASE_FEE_SETTING = "custom_base_fee_toman"
DEFAULT_CUSTOM_BUILDER_ENABLED = "1"
DEFAULT_CUSTOM_MIN_DAYS = 7
DEFAULT_CUSTOM_MAX_DAYS = 180
DEFAULT_CUSTOM_MIN_GB = 1
DEFAULT_CUSTOM_MAX_GB = 500
DEFAULT_CUSTOM_MIN_IP = 1
DEFAULT_CUSTOM_MAX_IP = 5
DEFAULT_CUSTOM_PRICE_PER_DAY = 0
DEFAULT_CUSTOM_PRICE_PER_GB = 2_778
DEFAULT_CUSTOM_UNLIMITED_DAY_FEE = 9_000
DEFAULT_CUSTOM_PRICE_PER_IP = 20_000
DEFAULT_CUSTOM_MIN_PRICE = 30_000
DEFAULT_CUSTOM_BASE_FEE = 30_000
# Monthly usage fee ≈ intercept + slope * GB (excludes base_fee).
# Calibrated: 5GB → 55k total, 50GB → 180k total (with 30k base, 30 days).
CUSTOM_METERED_MONTHLY_INTERCEPT = 11_111
CUSTOM_METERED_MONTHLY_SLOPE = 2_778
CUSTOM_METERED_REF_IP = 2
CUSTOM_UNLIMITED_REF_IP = 3
PRICE_SCHEMA_VERSION_KEY = "price_schema_version"
PRICE_SCHEMA_VERSION = "2"
PAYG_BUILDER_ENABLED = "payg_builder_enabled"
PAYG_MIN_GB_SETTING = "payg_min_gb"
PAYG_MAX_GB_SETTING = "payg_max_gb"
PAYG_MIN_IP_SETTING = "payg_min_ip"
PAYG_MAX_IP_SETTING = "payg_max_ip"
PAYG_PRICE_PER_GB_SETTING = "payg_price_per_gb_toman"
PAYG_PREPAID_PRICE_PER_GB_SETTING = "payg_prepaid_price_per_gb_toman"
PAYG_PRICE_PER_IP_SETTING = "payg_price_per_ip_toman"
PAYG_MIN_PRICE_SETTING = "payg_min_price_toman"
PAYG_MIN_WALLET_SETTING = "payg_min_wallet_toman"
PAYG_LIMIT_IP_SETTING = "payg_limit_ip"
DEFAULT_PAYG_BUILDER_ENABLED = "1"
DEFAULT_PAYG_MIN_GB = 5
DEFAULT_PAYG_MAX_GB = 200
DEFAULT_PAYG_MIN_IP = 1
DEFAULT_PAYG_MAX_IP = 3
DEFAULT_PAYG_PRICE_PER_GB = 4_000
# Prepaid volume packs have no expiry — priced higher than metered cloud usage.
DEFAULT_PAYG_PREPAID_PRICE_PER_GB = 7_500
DEFAULT_PAYG_PRICE_PER_IP = 25_000
DEFAULT_PAYG_MIN_PRICE = 40_000
DEFAULT_PAYG_MIN_WALLET = 10_000
DEFAULT_PAYG_LIMIT_IP = 2
PAYG_PRICE_SCHEMA_VERSION_KEY = "payg_price_schema_version"
PAYG_PRICE_SCHEMA_VERSION = "2"
BYTES_PER_GB = 1024 * 1024 * 1024
TRIAL_ENABLED_SETTING = "trial_enabled"
TRIAL_DURATION_DAYS_SETTING = "trial_duration_days"
TRIAL_TRAFFIC_GB_SETTING = "trial_traffic_gb"
TRIAL_LIMIT_IP_SETTING = "trial_limit_ip"
TRIAL_SEND_LINKS_SETTING = "trial_send_links"
DEFAULT_TRIAL_ENABLED = "1"
DEFAULT_TRIAL_DURATION_DAYS = 3
DEFAULT_TRIAL_TRAFFIC_GB = 2
DEFAULT_TRIAL_LIMIT_IP = 1
MIN_WALLET_DEPOSIT = 50_000
MAX_WALLET_DEPOSIT = 20_000_000
MIN_WALLET_TRANSFER = 1_000

RETIRED_PLAN_CODES = (
    "1y-50gb",
    "1y-unlimited",
)
PRO_ONLY_PLAN_CODES = (
    "1m-unlimited",
    "3m-unlimited",
    "6m-unlimited",
)

DEFAULT_PLANS = [
    {
        "code": "1m-50gb",
        "title": "۱ ماهه — ۵۰ گیگ",
        "description": "مناسب استفاده روزمره",
        "price_toman": 180_000,
        "duration_days": 30,
        "traffic_gb": 50,
        "limit_ip": 2,
        "sort_order": 10,
    },
    {
        "code": "1m-100gb",
        "title": "۱ ماهه — ۱۰۰ گیگ",
        "description": "برای استفاده بیشتر در یک ماه",
        "price_toman": 240_000,
        "duration_days": 30,
        "traffic_gb": 100,
        "limit_ip": 2,
        "sort_order": 15,
    },
    {
        "code": "1m-unlimited",
        "title": "۱ ماهه — نامحدود",
        "description": "حجم نامحدود — مخصوص اعضای Pro",
        "price_toman": 300_000,
        "duration_days": 30,
        "traffic_gb": 0,
        "limit_ip": 2,
        "sort_order": 20,
    },
    {
        "code": "3m-50gb",
        "title": "۳ ماهه — ۵۰ گیگ",
        "description": "به‌صرفه‌تر از خرید ماهانه",
        "price_toman": 480_000,
        "duration_days": 90,
        "traffic_gb": 50,
        "limit_ip": 2,
        "sort_order": 30,
    },
    {
        "code": "3m-100gb",
        "title": "۳ ماهه — ۱۰۰ گیگ",
        "description": "حجم بیشتر، به‌صرفه‌تر از خرید ماهانه",
        "price_toman": 640_000,
        "duration_days": 90,
        "traffic_gb": 100,
        "limit_ip": 2,
        "sort_order": 35,
    },
    {
        "code": "3m-unlimited",
        "title": "۳ ماهه — نامحدود",
        "description": "حجم نامحدود — مخصوص اعضای Pro",
        "price_toman": 780_000,
        "duration_days": 90,
        "traffic_gb": 0,
        "limit_ip": 2,
        "sort_order": 40,
    },
    {
        "code": "6m-50gb",
        "title": "۶ ماهه — ۵۰ گیگ",
        "description": "تخفیف نسبت به خرید ماهانه",
        "price_toman": 900_000,
        "duration_days": 180,
        "traffic_gb": 50,
        "limit_ip": 2,
        "sort_order": 50,
    },
    {
        "code": "6m-100gb",
        "title": "۶ ماهه — ۱۰۰ گیگ",
        "description": "حجم بیشتر با تخفیف نسبت به خرید ماهانه",
        "price_toman": 1_200_000,
        "duration_days": 180,
        "traffic_gb": 100,
        "limit_ip": 2,
        "sort_order": 55,
    },
    {
        "code": "6m-unlimited",
        "title": "۶ ماهه — نامحدود",
        "description": "حجم نامحدود — مخصوص اعضای Pro",
        "price_toman": 1_440_000,
        "duration_days": 180,
        "traffic_gb": 0,
        "limit_ip": 2,
        "sort_order": 60,
    },
]


def ensure_plans_catalog(session: Session) -> None:
    """Insert missing plans and refresh catalog metadata by code."""
    catalog = list(DEFAULT_PLANS) + [
        {
            "code": PLATFORM_PRO_CODE,
            "title": "اشتراک Pro",
            "description": "۳۰٪ تخفیف کانفیگ + امکانات ویژه پلتفرم",
            "price_toman": 199_000,
            "duration_days": 30,
            "traffic_gb": 0,
            "limit_ip": 0,
            "sort_order": 9998,
        },
        {
            "code": WALLET_TOPUP_CODE,
            "title": "شارژ کیف‌پول",
            "description": "افزایش موجودی کیف‌پول فروشگاه",
            "price_toman": MIN_WALLET_DEPOSIT,
            "duration_days": 0,
            "traffic_gb": 0,
            "limit_ip": 0,
            "sort_order": 9999,
        },
        {
            "code": TRIAL_PLAN_CODE,
            "title": "حساب تست رایگان",
            "description": "اشتراک آزمایشی برای کاربران جدید",
            "price_toman": 0,
            "duration_days": DEFAULT_TRIAL_DURATION_DAYS,
            "traffic_gb": DEFAULT_TRIAL_TRAFFIC_GB,
            "limit_ip": DEFAULT_TRIAL_LIMIT_IP,
            "sort_order": 9997,
        },
        {
            "code": CUSTOM_PLAN_CODE,
            "title": "پکیج سفارشی",
            "description": "ساخت پکیج با زمان و حجم دلخواه",
            "price_toman": 0,
            "duration_days": 30,
            "traffic_gb": 50,
            "limit_ip": 2,
            "sort_order": 9996,
        },
        {
            "code": PAYG_PLAN_CODE,
            "title": "پرداخت مصرفی",
            "description": "شارژ کیف‌پول و پرداخت فقط به‌اندازه مصرف واقعی",
            "price_toman": 0,
            "duration_days": 0,
            "traffic_gb": 10,
            "limit_ip": 1,
            "sort_order": 9995,
        },
    ]
    hidden_codes = (WALLET_TOPUP_CODE, PLATFORM_PRO_CODE, TRIAL_PLAN_CODE, CUSTOM_PLAN_CODE, PAYG_PLAN_CODE)
    existing = {
        p.code: p for p in session.scalars(select(Plan)).all()
    }
    for item in catalog:
        row = existing.get(item["code"])
        if row is None:
            enabled = item["code"] not in hidden_codes
            row = Plan(**item, enabled=enabled)
            try:
                with session.begin_nested():
                    session.add(row)
            except IntegrityError:
                row = session.scalar(select(Plan).where(Plan.code == item["code"]))
                if row is None:
                    raise
            existing[item["code"]] = row
            continue
        row.title = item["title"]
        row.description = item["description"]
        if item["code"] not in hidden_codes:
            row.price_toman = item["price_toman"]
            row.duration_days = item["duration_days"]
            row.traffic_gb = item["traffic_gb"]
            row.limit_ip = item["limit_ip"]
            row.sort_order = item["sort_order"]
        elif item["code"] == WALLET_TOPUP_CODE:
            row.enabled = False
            row.sort_order = 9999
        elif item["code"] == TRIAL_PLAN_CODE:
            row.enabled = False
            row.sort_order = 9997
        elif item["code"] == CUSTOM_PLAN_CODE:
            row.enabled = False
            row.sort_order = 9996
        elif item["code"] == PAYG_PLAN_CODE:
            row.enabled = False
            row.sort_order = 9995
        else:
            row.enabled = False
            row.sort_order = 9998
    for code in RETIRED_PLAN_CODES:
        row = existing.get(code)
        if row is not None:
            row.enabled = False
    for code in PRO_ONLY_PLAN_CODES:
        row = existing.get(code)
        if row is not None and code not in RETIRED_PLAN_CODES:
            row.enabled = True
    for code in ("1m-100gb", "3m-100gb", "6m-100gb"):
        row = existing.get(code)
        if row is not None and code not in RETIRED_PLAN_CODES:
            row.enabled = True


def seed_defaults(session: Session) -> None:
    from app.config import get_settings

    settings = get_settings()
    ensure_plans_catalog(session)
    if get_setting(session, "referral_percent") == "":
        set_setting(session, "referral_percent", str(DEFAULT_REFERRAL_PERCENT))
    if get_setting(session, "min_withdraw") == "":
        set_setting(session, "min_withdraw", str(DEFAULT_MIN_WITHDRAW))
    if get_setting(session, BIRTHDAY_GIFT_SETTING) == "":
        set_setting(session, BIRTHDAY_GIFT_SETTING, str(DEFAULT_BIRTHDAY_GIFT))
    if get_setting(session, BIRTHDAY_GIFT_ENABLED_SETTING) == "":
        set_setting(session, BIRTHDAY_GIFT_ENABLED_SETTING, DEFAULT_BIRTHDAY_GIFT_ENABLED)
    if get_setting(session, PRO_DISCOUNT_SETTING) == "":
        set_setting(session, PRO_DISCOUNT_SETTING, str(DEFAULT_PRO_DISCOUNT))
    if get_setting(session, TRIAL_ENABLED_SETTING) == "":
        set_setting(session, TRIAL_ENABLED_SETTING, DEFAULT_TRIAL_ENABLED)
    if get_setting(session, TRIAL_DURATION_DAYS_SETTING) == "":
        set_setting(session, TRIAL_DURATION_DAYS_SETTING, str(DEFAULT_TRIAL_DURATION_DAYS))
    if get_setting(session, TRIAL_TRAFFIC_GB_SETTING) == "":
        set_setting(session, TRIAL_TRAFFIC_GB_SETTING, str(DEFAULT_TRIAL_TRAFFIC_GB))
    if get_setting(session, TRIAL_LIMIT_IP_SETTING) == "":
        set_setting(session, TRIAL_LIMIT_IP_SETTING, str(DEFAULT_TRIAL_LIMIT_IP))
    if get_setting(session, TRIAL_SEND_LINKS_SETTING) == "":
        set_setting(session, TRIAL_SEND_LINKS_SETTING, "0")
    custom_defaults = {
        CUSTOM_BUILDER_ENABLED: DEFAULT_CUSTOM_BUILDER_ENABLED,
        CUSTOM_MIN_DAYS_SETTING: str(DEFAULT_CUSTOM_MIN_DAYS),
        CUSTOM_MAX_DAYS_SETTING: str(DEFAULT_CUSTOM_MAX_DAYS),
        CUSTOM_MIN_GB_SETTING: str(DEFAULT_CUSTOM_MIN_GB),
        CUSTOM_MAX_GB_SETTING: str(DEFAULT_CUSTOM_MAX_GB),
        CUSTOM_MIN_IP_SETTING: str(DEFAULT_CUSTOM_MIN_IP),
        CUSTOM_MAX_IP_SETTING: str(DEFAULT_CUSTOM_MAX_IP),
        CUSTOM_PRICE_PER_DAY_SETTING: str(DEFAULT_CUSTOM_PRICE_PER_DAY),
        CUSTOM_PRICE_PER_GB_SETTING: str(DEFAULT_CUSTOM_PRICE_PER_GB),
        CUSTOM_UNLIMITED_DAY_FEE_SETTING: str(DEFAULT_CUSTOM_UNLIMITED_DAY_FEE),
        CUSTOM_PRICE_PER_IP_SETTING: str(DEFAULT_CUSTOM_PRICE_PER_IP),
        CUSTOM_MIN_PRICE_SETTING: str(DEFAULT_CUSTOM_MIN_PRICE),
        CUSTOM_BASE_FEE_SETTING: str(DEFAULT_CUSTOM_BASE_FEE),
    }
    for key, value in custom_defaults.items():
        if get_setting(session, key) == "":
            set_setting(session, key, value)
    if get_setting(session, PRICE_SCHEMA_VERSION_KEY) != PRICE_SCHEMA_VERSION:
        # Refresh commercial pricing: base 30k + usage curve, catalog bump.
        set_setting(session, CUSTOM_BASE_FEE_SETTING, str(DEFAULT_CUSTOM_BASE_FEE))
        set_setting(session, CUSTOM_MIN_PRICE_SETTING, str(DEFAULT_CUSTOM_MIN_PRICE))
        set_setting(session, CUSTOM_PRICE_PER_GB_SETTING, str(DEFAULT_CUSTOM_PRICE_PER_GB))
        set_setting(session, CUSTOM_PRICE_PER_DAY_SETTING, "0")
        set_setting(session, CUSTOM_MIN_GB_SETTING, "5")
        set_setting(session, PRICE_SCHEMA_VERSION_KEY, PRICE_SCHEMA_VERSION)
    payg_defaults = {
        PAYG_BUILDER_ENABLED: DEFAULT_PAYG_BUILDER_ENABLED,
        PAYG_MIN_GB_SETTING: str(DEFAULT_PAYG_MIN_GB),
        PAYG_MAX_GB_SETTING: str(DEFAULT_PAYG_MAX_GB),
        PAYG_MIN_IP_SETTING: str(DEFAULT_PAYG_MIN_IP),
        PAYG_MAX_IP_SETTING: str(DEFAULT_PAYG_MAX_IP),
        PAYG_PRICE_PER_GB_SETTING: str(DEFAULT_PAYG_PRICE_PER_GB),
        PAYG_PREPAID_PRICE_PER_GB_SETTING: str(DEFAULT_PAYG_PREPAID_PRICE_PER_GB),
        PAYG_PRICE_PER_IP_SETTING: str(DEFAULT_PAYG_PRICE_PER_IP),
        PAYG_MIN_PRICE_SETTING: str(DEFAULT_PAYG_MIN_PRICE),
        PAYG_MIN_WALLET_SETTING: str(DEFAULT_PAYG_MIN_WALLET),
        PAYG_LIMIT_IP_SETTING: str(DEFAULT_PAYG_LIMIT_IP),
    }
    for key, value in payg_defaults.items():
        if get_setting(session, key) == "":
            set_setting(session, key, value)
    if get_setting(session, PAYG_PRICE_SCHEMA_VERSION_KEY) != PAYG_PRICE_SCHEMA_VERSION:
        # Prepaid volume packs (no time limit) priced above metered cloud usage.
        set_setting(session, PAYG_PREPAID_PRICE_PER_GB_SETTING, str(DEFAULT_PAYG_PREPAID_PRICE_PER_GB))
        set_setting(session, PAYG_PRICE_PER_IP_SETTING, str(DEFAULT_PAYG_PRICE_PER_IP))
        set_setting(session, PAYG_MIN_PRICE_SETTING, str(DEFAULT_PAYG_MIN_PRICE))
        set_setting(session, PAYG_PRICE_SCHEMA_VERSION_KEY, PAYG_PRICE_SCHEMA_VERSION)
    for user in session.scalars(select(User).where(User.referral_code.is_(None))).all():
        user.referral_code = _unique_referral_code(session)
    sync_env_admin_roles(session, settings)
    session.commit()


def list_admin_telegram_ids(session: Session, settings) -> list[int]:
    ids = set(int(x) for x in settings.admin_ids)
    rows = session.scalars(select(User.telegram_id).where(User.role == USER_ROLE_ADMIN)).all()
    ids.update(int(x) for x in rows)
    return sorted(ids)


def sync_env_admin_roles(session: Session, settings) -> None:
    """Ensure env ADMIN_IDS always have admin role in DB; demote legacy removed env admins."""
    env_ids = set(int(x) for x in settings.admin_ids)
    for tg_id in env_ids:
        user = session.scalar(select(User).where(User.telegram_id == tg_id))
        if user and user.role != USER_ROLE_ADMIN:
            user.role = USER_ROLE_ADMIN
    # Former env admins removed from ADMIN_IDS keep DB role until demoted explicitly.
    for tg_id in (121766040,):
        if tg_id in env_ids:
            continue
        user = session.scalar(select(User).where(User.telegram_id == tg_id))
        if user and user.role == USER_ROLE_ADMIN:
            user.role = USER_ROLE_USER


def is_user_admin(user: User | None, settings) -> bool:
    if not user:
        return False
    if user.role == USER_ROLE_ADMIN:
        return True
    return settings.is_admin(user.telegram_id)


def is_telegram_admin(session: Session, telegram_id: int | None, settings) -> bool:
    if not telegram_id:
        return False
    if settings.is_admin(telegram_id):
        return True
    user = session.scalar(select(User).where(User.telegram_id == telegram_id))
    return bool(user and user.role == USER_ROLE_ADMIN)


def user_admin_dict(user: User, settings) -> dict[str, Any]:
    view = wallet_view(user)
    return {
        "id": user.id,
        "telegram_id": user.telegram_id,
        "username": user.username,
        "full_name": user.full_name,
        "role": user.role or USER_ROLE_USER,
        "is_admin": is_user_admin(user, settings),
        "is_super_admin": settings.is_admin(user.telegram_id),
        "wallet_balance": view["balance"],
        "wallet_label": format_price(view["balance"]),
        "wallet_credit_limit": view["credit_limit"],
        "wallet_credit_limit_label": format_price(view["credit_limit"]) if view["credit_limit"] else None,
        "wallet_debt": view["debt"],
        "wallet_debt_label": format_price(view["debt"]) if view["debt"] else None,
        "wallet_spendable": view["spendable"],
        "is_pro": is_user_pro(user),
        "pro_until": user.pro_until.isoformat() if user.pro_until else None,
        "trial_granted": bool(user.trial_granted),
        "is_test": bool(getattr(user, "is_test", False)),
        "created_at": user.created_at.isoformat() if user.created_at else None,
    }


def _admin_user_issue_counts(session: Session, user_id: int) -> dict[str, int]:
    now = datetime.utcnow()
    sub_count = session.scalar(
        select(func.count()).select_from(Subscription).where(Subscription.user_id == user_id)
    ) or 0
    active_count = session.scalar(
        select(func.count())
        .select_from(Subscription)
        .where(
            Subscription.user_id == user_id,
            Subscription.enabled.is_(True),
            (Subscription.expires_at.is_(None) | (Subscription.expires_at > now)),
        )
    ) or 0
    pending_orders = session.scalar(
        select(func.count())
        .select_from(Order)
        .where(Order.user_id == user_id, Order.status == OrderStatus.PENDING)
    ) or 0
    chat_unread = session.scalar(
        select(func.count())
        .select_from(ChatMessage)
        .where(
            ChatMessage.user_id == user_id,
            ChatMessage.sender == "user",
            ChatMessage.read_at.is_(None),
        )
    ) or 0
    return {
        "subscription_count": int(sub_count),
        "active_subscription_count": int(active_count),
        "pending_order_count": int(pending_orders),
        "chat_unread": int(chat_unread),
    }


def admin_user_overview(session: Session, user: User, settings) -> dict[str, Any]:
    data = user_admin_dict(user, settings)
    data.update(_admin_user_issue_counts(session, user.id))
    data["has_issue"] = data["pending_order_count"] > 0 or data["chat_unread"] > 0
    return data


def search_users_admin(
    session: Session,
    settings,
    query: str = "",
    *,
    limit: int = 40,
    include_test: bool = False,
) -> list[dict[str, Any]]:
    q = (query or "").strip()
    cap = max(1, min(limit, 100))
    stmt = select(User).order_by(User.id.desc()).limit(cap)
    if q:
        if q.isdigit():
            num = int(q)
            stmt = (
                select(User)
                .where((User.telegram_id == num) | (User.id == num))
                .order_by(User.id.desc())
                .limit(5)
            )
        elif q.startswith("@"):
            stmt = (
                select(User)
                .where(func.lower(User.username) == q[1:].lower())
                .limit(5)
            )
        else:
            like = f"%{q}%"
            stmt = (
                select(User)
                .where(
                    func.lower(User.username).like(like.lower())
                    | func.lower(User.full_name).like(like.lower())
                )
                .order_by(User.id.desc())
                .limit(cap)
            )
    if not include_test and not q:
        stmt = stmt.where(User.is_test.is_(False))
    users = list(session.scalars(stmt).all())
    return [admin_user_overview(session, u, settings) for u in users]


def subscription_buy_meta(session: Session, sub: Subscription) -> dict[str, Any]:
    """How this config was obtained, plus the latest related order status."""
    order = sub.order
    if order is None and sub.order_id:
        order = session.get(Order, sub.order_id)
    renew = session.scalar(
        select(Order)
        .where(Order.target_subscription_id == sub.id)
        .options(selectinload(Order.plan))
        .order_by(Order.id.desc())
        .limit(1)
    )
    if is_trial_plan(sub.plan):
        source = "trial"
        source_label = "تست رایگان"
    elif sub.payg_metered or (order and is_payg_order(order)) or is_payg_subscription(sub):
        source = "payg"
        source_label = "مصرفی"
    elif order is None:
        source = "gift"
        source_label = "هدیه ادمین"
    elif int(order.amount_toman or 0) <= 0 and int(order.wallet_used or 0) <= 0:
        source = "gift"
        source_label = "هدیه"
    else:
        source = "purchase"
        source_label = "خرید"
    snap = order_chat_dict(order) if order else None
    renew_snap = order_chat_dict(renew) if renew and (not order or renew.id != order.id) else None
    return {
        "source": source,
        "source_label": source_label,
        "order_id": snap["id"] if snap else None,
        "order_status": snap["status"] if snap else None,
        "order_status_label": snap["status_label"] if snap else None,
        "order_amount_label": snap["amount_label"] if snap else None,
        "order_kind_label": snap["kind_label"] if snap else source_label,
        "renew_order_id": renew_snap["id"] if renew_snap else None,
        "renew_status": renew_snap["status"] if renew_snap else None,
        "renew_status_label": renew_snap["status_label"] if renew_snap else None,
        "renew_amount_label": renew_snap["amount_label"] if renew_snap else None,
    }


def admin_user_detail(session: Session, user: User, settings, panel=None) -> dict[str, Any]:
    data = admin_user_overview(session, user, settings)
    now = datetime.utcnow()
    subs_out: list[dict[str, Any]] = []
    online_emails: set[str] | None = None
    last_map: dict[str, int] | None = None
    if panel is not None:
        try:
            online_emails = panel.online_emails()
        except Exception:
            online_emails = set()
        try:
            last_map = panel.last_online_map()
        except Exception:
            last_map = {}
    for sub in user_all_subscriptions(session, user.id):
        stats: dict[str, Any] = {}
        if panel is not None:
            try:
                stats = subscription_live_stats(
                    panel,
                    sub,
                    online_emails=online_emails,
                    last_map=last_map,
                )
            except Exception:
                logger.exception("admin user detail stats failed sub=%s", sub.id)
        expired = bool(stats.get("expired")) if stats else bool(sub.expires_at and sub.expires_at <= now)
        enabled = bool(stats.get("enabled", sub.enabled))
        used = int(stats.get("used_bytes") or 0)
        status = str(stats.get("status") or (
            "online" if stats.get("online") else ("expired" if expired else ("disabled" if not enabled else "offline"))
        ))
        cfg = subscription_config_dict(sub)
        buy = subscription_buy_meta(session, sub)
        remaining_days = stats.get("remaining_days")
        if remaining_days is None and sub.expires_at:
            remaining_days = max(0, (sub.expires_at - now).days)
        subs_out.append(
            {
                "id": sub.id,
                "email": sub.xui_email,
                "label": sub.label,
                "plan_title": cfg.get("plan_title") or (sub.plan.title if sub.plan else "—"),
                "created_at": sub.created_at.isoformat() if sub.created_at else None,
                "expires_at": sub.expires_at.isoformat() if sub.expires_at else None,
                "enabled": enabled,
                "online": bool(stats.get("online")),
                "expired": expired,
                "is_payg": bool(cfg.get("is_payg") or sub.is_payg),
                "is_metered": bool(cfg.get("is_metered") or sub.payg_metered),
                "status": status,
                "used_bytes": used,
                "total_bytes": int(stats.get("total_bytes") or 0),
                "used_label": stats.get("used_label") or (format_bytes(used) if used else "۰"),
                "total_label": stats.get("total_label") or cfg.get("traffic_label") or "—",
                "remaining_label": stats.get("remaining_label"),
                "usage_percent": float(stats.get("usage_percent") or 0),
                "remaining_days": remaining_days,
                "last_online_at": stats.get("last_online_at"),
                "traffic_label": cfg.get("traffic_label") or "—",
                "limit_ip": cfg.get("limit_ip"),
                "family_role": getattr(sub, "family_role", None),
                "customer_name": sub.customer_name,
                **buy,
            }
        )
    orders, _total = list_orders_history(session, user_id=user.id, limit=12, include_user=False)
    withdrawals = list(
        session.scalars(
            select(Withdrawal)
            .where(Withdrawal.user_id == user.id)
            .order_by(Withdrawal.id.desc())
            .limit(8)
        ).all()
    )
    data["subscriptions"] = subs_out
    data["orders"] = orders
    data["withdrawals"] = [
        {
            "id": w.id,
            "amount_toman": w.amount_toman,
            "amount_label": format_price(w.amount_toman),
            "card_number": w.card_number,
            "status": w.status,
            "created_at": w.created_at.isoformat() if w.created_at else None,
        }
        for w in withdrawals
    ]
    return data


def transfer_wallet_balance(
    session: Session,
    *,
    source: User,
    target: User,
    amount_toman: int,
    panel=None,
    settings=None,
) -> WalletTransfer:
    amount = int(amount_toman)
    if source.id == target.id:
        raise ValueError("same_user")
    if amount < MIN_WALLET_TRANSFER:
        raise ValueError("amount_too_low")
    if amount > MAX_WALLET_DEPOSIT:
        raise ValueError("amount_too_high")
    session.refresh(source)
    session.refresh(target)
    if wallet_withdrawable(source) < amount:
        raise ValueError("insufficient_wallet")
    source.wallet_balance = int(source.wallet_balance or 0) - amount
    target.wallet_balance = int(target.wallet_balance or 0) + amount
    row = WalletTransfer(from_user_id=source.id, to_user_id=target.id, amount_toman=amount)
    session.add(row)
    session.commit()
    session.refresh(source)
    session.refresh(target)
    session.refresh(row)
    if panel is not None:
        try:
            resume_metered_payg_if_funded(session, panel, target, settings)
        except Exception:
            logger.exception("payg resume after wallet transfer failed user=%s", target.id)
    return row


def list_user_wallet_transfers(session: Session, user: User, *, limit: int = 12) -> list[dict[str, Any]]:
    rows = list(
        session.scalars(
            select(WalletTransfer)
            .where((WalletTransfer.from_user_id == user.id) | (WalletTransfer.to_user_id == user.id))
            .order_by(WalletTransfer.id.desc())
            .limit(max(1, min(40, limit)))
            .options(
                selectinload(WalletTransfer.sender),
                selectinload(WalletTransfer.recipient),
            )
        ).all()
    )
    out: list[dict[str, Any]] = []
    for row in rows:
        incoming = row.to_user_id == user.id
        other = row.sender if incoming else row.recipient
        out.append(
            {
                "id": row.id,
                "direction": "in" if incoming else "out",
                "amount_toman": row.amount_toman,
                "amount_label": format_price(row.amount_toman),
                "other_name": (other.full_name if other else None)
                or (f"@{other.username}" if other and other.username else None)
                or (str(other.telegram_id) if other else "—"),
                "other_telegram_id": other.telegram_id if other else None,
                "created_at": row.created_at.isoformat() if row.created_at else None,
            }
        )
    return out


def adjust_user_wallet(
    session: Session,
    user: User,
    amount_toman: int,
    panel=None,
    settings=None,
    *,
    allow_negative: bool = False,
) -> User:
    """Change wallet balance. Admin may pass allow_negative to charge into debt (auto credit)."""
    amount = int(amount_toman)
    if amount == 0:
        raise ValueError("zero_amount")
    new_balance = int(user.wallet_balance or 0) + amount
    if new_balance < 0:
        if not allow_negative:
            floor = -wallet_credit_limit_of(user)
            if new_balance < floor:
                raise ValueError("insufficient_wallet")
        else:
            # Admin overdraft: raise credit ceiling so the debt is payable later
            debt = -new_balance
            if wallet_credit_limit_of(user) < debt:
                user.wallet_credit_limit = debt
    user.wallet_balance = new_balance
    clamp_wallet_locked(user)
    session.commit()
    session.refresh(user)
    if amount > 0 and panel is not None:
        try:
            resume_metered_payg_if_funded(session, panel, user, settings)
        except Exception:
            logger.exception("payg resume after admin wallet adjust failed user=%s", user.id)
    return user


def convert_wallet_topup_to_credit(
    session: Session,
    user: User,
    original_topup_toman: int,
    panel=None,
    settings=None,
) -> User:
    """Turn a prior admin/gift top-up into credit debt.

    Example: top-up 1_000_000, spent 300_000 → balance 700_000.
    After convert(1_000_000): balance -300_000 (debt = spent), credit_limit ≥ 1_000_000.
    Remaining unused gift is removed; spent amount becomes payable later via deposit.
    """
    original = max(0, int(original_topup_toman))
    if original <= 0:
        raise ValueError("zero_amount")
    balance = int(user.wallet_balance or 0)
    # Ensure credit covers at least the original facility (and any resulting debt)
    new_balance = balance - original
    debt = max(0, -new_balance)
    need_limit = max(original, debt, wallet_credit_limit_of(user))
    user.wallet_credit_limit = need_limit
    user.wallet_balance = new_balance
    clamp_wallet_locked(user)
    session.commit()
    session.refresh(user)
    if new_balance > 0 and panel is not None:
        try:
            resume_metered_payg_if_funded(session, panel, user, settings)
        except Exception:
            logger.exception("payg resume after credit convert failed user=%s", user.id)
    return user


def set_subscription_enabled(session: Session, panel, sub: Subscription, enabled: bool) -> Subscription:
    panel.set_enabled(sub.xui_email, bool(enabled))
    sub.enabled = bool(enabled)
    session.commit()
    session.refresh(sub)
    return sub


def grant_pro_to_user(session: Session, user: User, *, days: int | None = None) -> datetime:
    """Extend platform Pro for a user without creating an order."""
    plan = get_platform_pro_plan(session)
    add_days = int(days) if days is not None else int(plan.duration_days or 30)
    add_days = max(1, min(3650, add_days))
    now = datetime.utcnow()
    base = (
        user.pro_until.replace(tzinfo=None)
        if user.pro_until and user.pro_until.replace(tzinfo=None) > now
        else now
    )
    user.pro_until = base + timedelta(days=add_days)
    session.commit()
    session.refresh(user)
    return user.pro_until


def admin_giftable_plans(session: Session) -> list[Plan]:
    ensure_plans_catalog(session)
    rows = list(session.scalars(select(Plan).order_by(Plan.id)).all())
    return [
        p
        for p in rows
        if (is_vpn_plan(p) or is_trial_plan(p))
        and p.code not in RETIRED_PLAN_CODES
        and (is_trial_plan(p) or int(p.duration_days or 0) < 365)
    ]


def admin_gift_subscription(
    session: Session,
    user: User,
    panel,
    settings,
    *,
    plan_id: int,
) -> Subscription:
    """Provision a VPN config for a user as an admin gift (no payment order)."""
    plan = session.get(Plan, plan_id)
    if not plan or not (is_vpn_plan(plan) or is_trial_plan(plan)):
        raise ValueError("invalid_plan")
    if is_retired_shop_plan(plan):
        raise ValueError("plan_unavailable")
    duration = max(0, int(plan.duration_days or 0))
    traffic = max(0, int(plan.traffic_gb or 0))
    limit_ip = max(1, int(plan.limit_ip or 1))
    if is_trial_plan(plan):
        duration, traffic, limit_ip = _trial_provision_params(session, plan)

    prefix = "trial" if is_trial_plan(plan) else "tg"
    email = f"{prefix}{user.telegram_id}-{secrets.token_hex(3)}"
    client = panel.create_client(
        email=email,
        duration_days=duration,
        traffic_gb=traffic,
        limit_ip=limit_ip,
        tg_id=user.telegram_id,
        comment=f"admin-gift-{plan.code}",
    )
    label = (plan.title or "").strip() or "کانفیگ"
    sub = create_standalone_subscription(
        session,
        user=user,
        plan=plan,
        xui_email=email,
        xui_uuid=str(client.get("uuid") or client.get("id") or "") or None,
        xui_sub_id=str(client.get("subId") or client.get("sub_id") or "") or None,
        duration_days=duration,
        label=label,
    )
    if is_trial_plan(plan):
        user.trial_granted = True
        session.commit()
        session.refresh(user)
    # Ensure links are warm / multi-server attached (create_client already fans out).
    try:
        public_links_for_email(panel, email, settings, name=label)
    except Exception:
        logger.exception("admin gift links warm failed %s", email)
    return sub


def set_user_test_flag(session: Session, user: User, is_test: bool) -> User:
    user.is_test = bool(is_test)
    session.commit()
    session.refresh(user)
    return user


def purge_user_money_and_configs(session: Session, panel, user: User) -> dict[str, Any]:
    """Zero wallet and delete this user's configs, orders, and money movements."""
    from app.models import AdminAuditLog, PromoRedemption, WalletTransfer

    user_id = user.id
    username = user.username
    sub_ids = list(session.scalars(select(Subscription.id).where(Subscription.user_id == user_id)).all())
    deleted_subs = 0
    for sub in list(session.scalars(select(Subscription).where(Subscription.user_id == user_id)).all()):
        try:
            delete_user_subscription(session, panel, sub)
            deleted_subs += 1
        except Exception:
            logger.exception("purge delete sub failed user=%s sub=%s", user_id, sub.id)
            try:
                session.rollback()
            except Exception:
                pass

    user = session.get(User, user_id) or user
    order_ids = list(session.scalars(select(Order.id).where(Order.user_id == user_id)).all())
    if order_ids:
        session.execute(delete(PromoRedemption).where(PromoRedemption.order_id.in_(order_ids)))
        session.execute(delete(Commission).where(Commission.order_id.in_(order_ids)))
    session.execute(delete(PromoRedemption).where(PromoRedemption.user_id == user_id))
    session.execute(
        delete(Commission).where((Commission.referrer_id == user_id) | (Commission.referred_id == user_id))
    )
    session.execute(
        update(Order).where(Order.user_id == user_id).values(target_subscription_id=None)
    )
    deleted_orders = session.execute(delete(Order).where(Order.user_id == user_id)).rowcount or 0
    deleted_wd = session.execute(delete(Withdrawal).where(Withdrawal.user_id == user_id)).rowcount or 0
    deleted_xfers = (
        session.execute(
            delete(WalletTransfer).where(
                (WalletTransfer.from_user_id == user_id) | (WalletTransfer.to_user_id == user_id)
            )
        ).rowcount
        or 0
    )
    session.execute(
        delete(AdminAuditLog).where(
            (AdminAuditLog.actor_user_id == user_id) | (AdminAuditLog.target_user_id == user_id)
        )
    )
    user.wallet_balance = 0
    user.wallet_locked_toman = 0
    session.commit()
    return {
        "user_id": user_id,
        "username": username,
        "deleted_subs": deleted_subs,
        "deleted_orders": int(deleted_orders),
        "deleted_withdrawals": int(deleted_wd),
        "deleted_transfers": int(deleted_xfers),
        "cleared_sub_ids": sub_ids,
    }


def delete_user_subscription(session: Session, panel, sub: Subscription) -> None:
    """Hard-delete a config from the panel and shop database."""
    email = sub.xui_email
    try:
        panel.delete_client(email)
    except Exception:
        logger.exception("panel delete_client failed for %s", email)
    session.execute(
        update(Order).where(Order.target_subscription_id == sub.id).values(target_subscription_id=None)
    )
    session.execute(delete(UsageSample).where(UsageSample.subscription_id == sub.id))
    session.delete(sub)
    session.commit()


def set_user_role(
    session: Session,
    target: User,
    role: str,
    *,
    actor: User,
    settings,
) -> User:
    role = (role or USER_ROLE_USER).strip().lower()
    if role not in (USER_ROLE_USER, USER_ROLE_ADMIN):
        raise ValueError("invalid_role")
    if target.telegram_id in settings.admin_ids and role != USER_ROLE_ADMIN:
        raise ValueError("super_admin_locked")
    if target.id == actor.id and role != USER_ROLE_ADMIN:
        raise ValueError("cannot_demote_self")
    target.role = role
    session.commit()
    session.refresh(target)
    return target


def _unique_referral_code(session: Session, length: int = 8) -> str:
    alphabet = string.ascii_uppercase + string.digits
    while True:
        code = "".join(secrets.choice(alphabet) for _ in range(length))
        exists = session.scalar(select(User.id).where(User.referral_code == code))
        if not exists:
            return code


def ensure_referral_code(session: Session, user: User) -> str:
    if not user.referral_code:
        user.referral_code = _unique_referral_code(session)
        session.commit()
        session.refresh(user)
    return user.referral_code


def get_or_create_user(
    session: Session,
    telegram_id: int,
    username: str | None,
    full_name: str | None,
    *,
    referrer_code: str | None = None,
) -> tuple[User, bool]:
    user = session.scalar(select(User).where(User.telegram_id == telegram_id))
    is_new = user is None
    if user is None:
        user = User(
            telegram_id=telegram_id,
            username=username,
            full_name=full_name,
            referral_code=_unique_referral_code(session),
            wallet_balance=0,
        )
        session.add(user)
        session.commit()
        session.refresh(user)
    else:
        changed = False
        if username and user.username != username:
            user.username = username
            changed = True
        if full_name and user.full_name != full_name:
            user.full_name = full_name
            changed = True
        if not user.referral_code:
            user.referral_code = _unique_referral_code(session)
            changed = True
        if changed:
            session.commit()

    if is_new and referrer_code:
        bind_referrer(session, user, referrer_code)
    return user, is_new


def bind_referrer(session: Session, user: User, referrer_code: str) -> bool:
    """Bind referrer only once, for new users, no self-ref."""
    if user.referred_by_id:
        return False
    code = (referrer_code or "").strip().upper()
    if code.startswith("REF_"):
        code = code[4:]
    if not code:
        return False
    referrer = session.scalar(select(User).where(User.referral_code == code))
    if not referrer or referrer.id == user.id:
        return False
    user.referred_by_id = referrer.id
    session.commit()
    return True


def list_enabled_plans(session: Session, user: User | None = None) -> list[Plan]:
    include_unlimited = bool(user is not None and is_user_pro(user))
    rows = list(
        session.scalars(
            select(Plan)
            .where(
                Plan.enabled.is_(True),
                Plan.code != WALLET_TOPUP_CODE,
                Plan.code != PLATFORM_PRO_CODE,
                Plan.code != TRIAL_PLAN_CODE,
                Plan.code != PAYG_PLAN_CODE,
                Plan.code != CUSTOM_PLAN_CODE,
            )
            .order_by(Plan.sort_order, Plan.id)
        ).all()
    )
    out: list[Plan] = []
    for p in rows:
        if p.code in RETIRED_PLAN_CODES or int(p.duration_days or 0) >= 365:
            continue
        if is_pro_only_shop_plan(p) and not include_unlimited:
            continue
        out.append(p)
    return out


def is_wallet_topup(plan: Plan | None) -> bool:
    return bool(plan and plan.code == WALLET_TOPUP_CODE)


def is_platform_pro(plan: Plan | None) -> bool:
    return bool(plan and plan.code == PLATFORM_PRO_CODE)


def is_trial_plan(plan: Plan | None) -> bool:
    return bool(plan and plan.code == TRIAL_PLAN_CODE)


def is_vpn_plan(plan: Plan | None) -> bool:
    return bool(
        plan
        and not is_wallet_topup(plan)
        and not is_platform_pro(plan)
        and not is_trial_plan(plan)
        and plan.code != CUSTOM_PLAN_CODE
        and plan.code != PAYG_PLAN_CODE
    )


def is_retired_shop_plan(plan: Plan | None) -> bool:
    if not is_vpn_plan(plan):
        return False
    return plan.code in RETIRED_PLAN_CODES or int(plan.duration_days or 0) >= 365


def is_pro_only_shop_plan(plan: Plan | None) -> bool:
    if not is_vpn_plan(plan):
        return False
    return plan.code in PRO_ONLY_PLAN_CODES or int(plan.traffic_gb or 0) <= 0


def assert_shop_plan_available(user: User, plan: Plan) -> None:
    if is_retired_shop_plan(plan):
        raise ValueError("plan_unavailable")
    if is_pro_only_shop_plan(plan) and not is_user_pro(user):
        raise ValueError("plan_pro_only")


def is_custom_plan(plan: Plan | None) -> bool:
    return bool(plan and plan.code == CUSTOM_PLAN_CODE)


def is_custom_order(order: Order | None) -> bool:
    return bool(order and order.custom_duration_days)


def is_payg_plan(plan: Plan | None) -> bool:
    return bool(plan and plan.code == PAYG_PLAN_CODE)


def is_payg_order(order: Order | None) -> bool:
    return bool(order and is_payg_plan(order.plan))


def is_payg_subscription(sub: Subscription | None) -> bool:
    if not sub:
        return False
    if getattr(sub, "is_payg", False) or getattr(sub, "payg_metered", False):
        return True
    return is_payg_plan(sub.plan)


def is_metered_payg(sub: Subscription | None) -> bool:
    return bool(sub and getattr(sub, "payg_metered", False))


def _custom_int_setting(session: Session, key: str, default: int) -> int:
    raw = get_setting(session, key, str(default))
    try:
        return int(raw)
    except ValueError:
        return default


def custom_builder_enabled(session: Session) -> bool:
    return get_setting(session, CUSTOM_BUILDER_ENABLED, DEFAULT_CUSTOM_BUILDER_ENABLED) == "1"


def custom_builder_settings(session: Session, user: User | None = None) -> dict[str, Any]:
    return {
        "enabled": custom_builder_enabled(session),
        "min_days": _custom_int_setting(session, CUSTOM_MIN_DAYS_SETTING, DEFAULT_CUSTOM_MIN_DAYS),
        "max_days": min(180, _custom_int_setting(session, CUSTOM_MAX_DAYS_SETTING, DEFAULT_CUSTOM_MAX_DAYS)),
        "min_gb": _custom_int_setting(session, CUSTOM_MIN_GB_SETTING, DEFAULT_CUSTOM_MIN_GB),
        "max_gb": _custom_int_setting(session, CUSTOM_MAX_GB_SETTING, DEFAULT_CUSTOM_MAX_GB),
        "min_ip": _custom_int_setting(session, CUSTOM_MIN_IP_SETTING, DEFAULT_CUSTOM_MIN_IP),
        "max_ip": _custom_int_setting(session, CUSTOM_MAX_IP_SETTING, DEFAULT_CUSTOM_MAX_IP),
        "unlimited_allowed": bool(user is not None and is_user_pro(user)),
    }


def custom_builder_admin_settings(session: Session) -> dict[str, Any]:
    data = custom_builder_settings(session)
    data.update(
        {
            "base_fee_toman": _custom_int_setting(session, CUSTOM_BASE_FEE_SETTING, DEFAULT_CUSTOM_BASE_FEE),
            "price_per_day_toman": _custom_int_setting(session, CUSTOM_PRICE_PER_DAY_SETTING, DEFAULT_CUSTOM_PRICE_PER_DAY),
            "price_per_gb_toman": _custom_int_setting(session, CUSTOM_PRICE_PER_GB_SETTING, DEFAULT_CUSTOM_PRICE_PER_GB),
            "unlimited_day_fee_toman": _custom_int_setting(
                session, CUSTOM_UNLIMITED_DAY_FEE_SETTING, DEFAULT_CUSTOM_UNLIMITED_DAY_FEE
            ),
            "price_per_ip_toman": _custom_int_setting(session, CUSTOM_PRICE_PER_IP_SETTING, DEFAULT_CUSTOM_PRICE_PER_IP),
            "min_price_toman": _custom_int_setting(session, CUSTOM_MIN_PRICE_SETTING, DEFAULT_CUSTOM_MIN_PRICE),
        }
    )
    return data


def update_custom_builder_settings(
    session: Session,
    *,
    enabled: bool,
    min_days: int,
    max_days: int,
    min_gb: int,
    max_gb: int,
    min_ip: int,
    max_ip: int,
    base_fee_toman: int,
    price_per_day_toman: int,
    price_per_gb_toman: int,
    unlimited_day_fee_toman: int,
    price_per_ip_toman: int,
    min_price_toman: int,
) -> dict[str, Any]:
    if min_days < 1 or max_days < min_days or max_days > 730:
        raise ValueError("days_range_invalid")
    if min_gb < 1 or max_gb < min_gb or max_gb > 2000:
        raise ValueError("gb_range_invalid")
    if min_ip < 1 or max_ip < min_ip or max_ip > 10:
        raise ValueError("ip_range_invalid")
    set_setting(session, CUSTOM_BUILDER_ENABLED, "1" if enabled else "0")
    set_setting(session, CUSTOM_MIN_DAYS_SETTING, str(min_days))
    set_setting(session, CUSTOM_MAX_DAYS_SETTING, str(max_days))
    set_setting(session, CUSTOM_MIN_GB_SETTING, str(min_gb))
    set_setting(session, CUSTOM_MAX_GB_SETTING, str(max_gb))
    set_setting(session, CUSTOM_MIN_IP_SETTING, str(min_ip))
    set_setting(session, CUSTOM_MAX_IP_SETTING, str(max_ip))
    set_setting(session, CUSTOM_BASE_FEE_SETTING, str(max(0, base_fee_toman)))
    set_setting(session, CUSTOM_PRICE_PER_DAY_SETTING, str(max(0, price_per_day_toman)))
    set_setting(session, CUSTOM_PRICE_PER_GB_SETTING, str(max(0, price_per_gb_toman)))
    set_setting(session, CUSTOM_UNLIMITED_DAY_FEE_SETTING, str(max(0, unlimited_day_fee_toman)))
    set_setting(session, CUSTOM_PRICE_PER_IP_SETTING, str(max(0, price_per_ip_toman)))
    set_setting(session, CUSTOM_MIN_PRICE_SETTING, str(max(0, min_price_toman)))
    return custom_builder_admin_settings(session)


def payg_builder_enabled(session: Session) -> bool:
    return get_setting(session, PAYG_BUILDER_ENABLED, DEFAULT_PAYG_BUILDER_ENABLED) == "1"


def payg_list_price_per_gb(session: Session) -> int:
    return max(1, _custom_int_setting(session, PAYG_PRICE_PER_GB_SETTING, DEFAULT_PAYG_PRICE_PER_GB))


def payg_unit_price(session: Session, user: User | None = None) -> int:
    price = payg_list_price_per_gb(session)
    if user and is_user_pro(user):
        disc = pro_discount_percent(session)
        if disc:
            price = max(1, price * (100 - disc) // 100)
    return price


def toman_for_bytes(used_bytes: int, price_per_gb: int) -> int:
    return (max(0, int(used_bytes)) * max(0, int(price_per_gb))) // BYTES_PER_GB


def payg_prepaid_price_per_gb(session: Session) -> int:
    return max(
        1,
        _custom_int_setting(session, PAYG_PREPAID_PRICE_PER_GB_SETTING, DEFAULT_PAYG_PREPAID_PRICE_PER_GB),
    )


def payg_prepaid_settings(session: Session) -> dict[str, Any]:
    return {
        "min_gb": _custom_int_setting(session, PAYG_MIN_GB_SETTING, DEFAULT_PAYG_MIN_GB),
        "max_gb": _custom_int_setting(session, PAYG_MAX_GB_SETTING, DEFAULT_PAYG_MAX_GB),
        "min_ip": _custom_int_setting(session, PAYG_MIN_IP_SETTING, DEFAULT_PAYG_MIN_IP),
        "max_ip": _custom_int_setting(session, PAYG_MAX_IP_SETTING, DEFAULT_PAYG_MAX_IP),
        "price_per_gb_toman": payg_prepaid_price_per_gb(session),
        "price_per_ip_toman": _custom_int_setting(session, PAYG_PRICE_PER_IP_SETTING, DEFAULT_PAYG_PRICE_PER_IP),
        "min_price_toman": _custom_int_setting(session, PAYG_MIN_PRICE_SETTING, DEFAULT_PAYG_MIN_PRICE),
    }


def payg_builder_settings(session: Session) -> dict[str, Any]:
    cloud_price = payg_list_price_per_gb(session)
    prepaid = payg_prepaid_settings(session)
    return {
        "enabled": payg_builder_enabled(session),
        "price_per_gb_toman": cloud_price,
        "prepaid_price_per_gb_toman": prepaid["price_per_gb_toman"],
        "min_wallet_toman": max(0, _custom_int_setting(session, PAYG_MIN_WALLET_SETTING, DEFAULT_PAYG_MIN_WALLET)),
        "limit_ip": max(1, min(10, _custom_int_setting(session, PAYG_LIMIT_IP_SETTING, DEFAULT_PAYG_LIMIT_IP))),
        "example_100mb_toman": toman_for_bytes(100 * 1024 * 1024, cloud_price),
        **prepaid,
        "price_per_gb_toman": cloud_price,
        "prepaid_price_per_gb_toman": prepaid["price_per_gb_toman"],
    }


def payg_builder_admin_settings(session: Session) -> dict[str, Any]:
    return payg_builder_settings(session)


def update_payg_builder_settings(
    session: Session,
    *,
    enabled: bool,
    price_per_gb_toman: int,
    min_wallet_toman: int,
    limit_ip: int,
    min_gb: int | None = None,
    max_gb: int | None = None,
    min_ip: int | None = None,
    max_ip: int | None = None,
    price_per_ip_toman: int | None = None,
    min_price_toman: int | None = None,
    prepaid_price_per_gb_toman: int | None = None,
    **_legacy: Any,
) -> dict[str, Any]:
    if limit_ip < 1 or limit_ip > 10:
        raise ValueError("ip_range_invalid")
    if price_per_gb_toman < 1:
        raise ValueError("price_invalid")
    if min_wallet_toman < 0:
        raise ValueError("min_wallet_invalid")
    prepaid = payg_prepaid_settings(session)
    min_gb = prepaid["min_gb"] if min_gb is None else int(min_gb)
    max_gb = prepaid["max_gb"] if max_gb is None else int(max_gb)
    min_ip = prepaid["min_ip"] if min_ip is None else int(min_ip)
    max_ip = prepaid["max_ip"] if max_ip is None else int(max_ip)
    if min_gb < 1 or max_gb < min_gb or max_gb > 2000:
        raise ValueError("gb_range_invalid")
    if min_ip < 1 or max_ip < min_ip or max_ip > 10:
        raise ValueError("ip_range_invalid")
    set_setting(session, PAYG_BUILDER_ENABLED, "1" if enabled else "0")
    set_setting(session, PAYG_PRICE_PER_GB_SETTING, str(int(price_per_gb_toman)))
    set_setting(session, PAYG_MIN_WALLET_SETTING, str(int(min_wallet_toman)))
    set_setting(session, PAYG_LIMIT_IP_SETTING, str(int(limit_ip)))
    set_setting(session, PAYG_MIN_GB_SETTING, str(min_gb))
    set_setting(session, PAYG_MAX_GB_SETTING, str(max_gb))
    set_setting(session, PAYG_MIN_IP_SETTING, str(min_ip))
    set_setting(session, PAYG_MAX_IP_SETTING, str(max_ip))
    if prepaid_price_per_gb_toman is not None:
        if int(prepaid_price_per_gb_toman) < 1:
            raise ValueError("price_invalid")
        set_setting(session, PAYG_PREPAID_PRICE_PER_GB_SETTING, str(int(prepaid_price_per_gb_toman)))
    if price_per_ip_toman is not None:
        set_setting(session, PAYG_PRICE_PER_IP_SETTING, str(max(0, int(price_per_ip_toman))))
    if min_price_toman is not None:
        set_setting(session, PAYG_MIN_PRICE_SETTING, str(max(0, int(min_price_toman))))
    return payg_builder_admin_settings(session)


def get_payg_plan(session: Session) -> Plan:
    plan = session.scalar(select(Plan).where(Plan.code == PAYG_PLAN_CODE))
    if plan is None:
        ensure_plans_catalog(session)
        session.commit()
        plan = session.scalar(select(Plan).where(Plan.code == PAYG_PLAN_CODE))
    if plan is None:
        raise RuntimeError("payg plan missing")
    return plan


def format_payg_title(traffic_gb: int, limit_ip: int) -> str:
    if traffic_gb <= 0:
        return "مصرفی ابری"
    return f"مصرفی · {traffic_gb} گیگ · {limit_ip} دستگاه"


def format_metered_payg_title() -> str:
    return "مصرفی ابری"


def validate_payg_package(session: Session, *, traffic_gb: int, limit_ip: int) -> None:
    if not payg_builder_enabled(session):
        raise ValueError("payg_builder_disabled")
    min_gb = _custom_int_setting(session, PAYG_MIN_GB_SETTING, DEFAULT_PAYG_MIN_GB)
    max_gb = _custom_int_setting(session, PAYG_MAX_GB_SETTING, DEFAULT_PAYG_MAX_GB)
    min_ip = _custom_int_setting(session, PAYG_MIN_IP_SETTING, DEFAULT_PAYG_MIN_IP)
    max_ip = _custom_int_setting(session, PAYG_MAX_IP_SETTING, DEFAULT_PAYG_MAX_IP)
    if traffic_gb < min_gb or traffic_gb > max_gb:
        raise ValueError("traffic_out_of_range")
    if limit_ip < min_ip or limit_ip > max_ip:
        raise ValueError("ip_out_of_range")


def compute_payg_base_price(
    session: Session,
    *,
    traffic_gb: int,
    limit_ip: int,
    include_ip_fee: bool = True,
) -> int:
    per_gb = payg_prepaid_price_per_gb(session)
    per_ip = _custom_int_setting(session, PAYG_PRICE_PER_IP_SETTING, DEFAULT_PAYG_PRICE_PER_IP)
    min_price = _custom_int_setting(session, PAYG_MIN_PRICE_SETTING, DEFAULT_PAYG_MIN_PRICE)
    total = int(traffic_gb) * per_gb
    if include_ip_fee:
        total += int(limit_ip) * per_ip
    total = max(min_price, total)
    return ((total + 2_500) // 5_000) * 5_000


def quote_payg_package(
    session: Session,
    user: User,
    *,
    traffic_gb: int,
    limit_ip: int,
    target_subscription_id: int | None = None,
) -> dict[str, Any]:
    validate_payg_package(session, traffic_gb=traffic_gb, limit_ip=limit_ip)
    base_price = compute_payg_base_price(
        session,
        traffic_gb=traffic_gb,
        limit_ip=limit_ip,
        include_ip_fee=not bool(target_subscription_id),
    )
    charge = custom_charge_price(session, user, base_price)
    wallet = wallet_spendable(user)
    return {
        "traffic_gb": traffic_gb,
        "limit_ip": limit_ip,
        "title": format_payg_title(traffic_gb, limit_ip),
        "traffic_label": traffic_label(traffic_gb),
        "price_toman": base_price,
        "price_label": format_price(base_price),
        "charge_toman": charge,
        "charge_label": format_price(charge),
        "pay_after_wallet": max(0, charge - wallet),
        "pro_discount_percent": pro_discount_percent(session) if is_user_pro(user) else 0,
    }


def user_payg_subscriptions(session: Session, user_id: int) -> list[Subscription]:
    rows = user_all_subscriptions(session, user_id)
    return [s for s in rows if is_payg_subscription(s)]


def user_metered_payg_subscription(session: Session, user_id: int) -> Subscription | None:
    rows = user_payg_subscriptions(session, user_id)
    metered = [s for s in rows if is_metered_payg(s)]
    return metered[0] if metered else None


def user_prepaid_payg_subscriptions(session: Session, user_id: int) -> list[Subscription]:
    return [s for s in user_payg_subscriptions(session, user_id) if not is_metered_payg(s)]


def list_metered_payg_subscriptions(session: Session) -> list[Subscription]:
    return list(
        session.scalars(
            select(Subscription)
            .where(Subscription.payg_metered.is_(True))
            .options(
                selectinload(Subscription.user),
                selectinload(Subscription.plan),
                selectinload(Subscription.order),
            )
            .order_by(Subscription.id.asc())
        ).all()
    )


def get_custom_plan(session: Session) -> Plan:
    plan = session.scalar(select(Plan).where(Plan.code == CUSTOM_PLAN_CODE))
    if plan is None:
        ensure_plans_catalog(session)
        session.commit()
        plan = session.scalar(select(Plan).where(Plan.code == CUSTOM_PLAN_CODE))
    if plan is None:
        raise RuntimeError("custom plan missing")
    return plan


def format_custom_plan_title(
    duration_days: int,
    traffic_gb: int,
    limit_ip: int,
    *,
    unlimited: bool = False,
) -> str:
    traffic = "نامحدود" if unlimited or traffic_gb <= 0 else f"{traffic_gb} گیگ"
    return f"سفارشی · {duration_days} روز · {traffic} · {limit_ip} دستگاه"


def validate_custom_package(
    session: Session,
    *,
    duration_days: int,
    traffic_gb: int,
    limit_ip: int,
    unlimited: bool,
    user: User | None = None,
) -> None:
    if not custom_builder_enabled(session):
        raise ValueError("custom_builder_disabled")
    cfg = custom_builder_settings(session, user)
    if duration_days < cfg["min_days"] or duration_days > cfg["max_days"]:
        raise ValueError("duration_out_of_range")
    if limit_ip < cfg["min_ip"] or limit_ip > cfg["max_ip"]:
        raise ValueError("ip_out_of_range")
    if unlimited and not cfg["unlimited_allowed"]:
        raise ValueError("unlimited_pro_only")
    if duration_days >= 365:
        raise ValueError("duration_out_of_range")
    if not unlimited and (traffic_gb < cfg["min_gb"] or traffic_gb > cfg["max_gb"]):
        raise ValueError("traffic_out_of_range")


def _round_shop_price(toman: int) -> int:
    return max(0, ((int(toman) + 2_500) // 5_000) * 5_000)


def _catalog_vpn_plans(session: Session) -> list[Plan]:
    hidden = {
        WALLET_TOPUP_CODE,
        PLATFORM_PRO_CODE,
        TRIAL_PLAN_CODE,
        CUSTOM_PLAN_CODE,
        PAYG_PLAN_CODE,
    }
    return [
        p
        for p in session.scalars(
            select(Plan)
            .where(Plan.enabled.is_(True), Plan.code.not_in(tuple(hidden)))
            .order_by(Plan.duration_days, Plan.traffic_gb, Plan.id)
        ).all()
        if not is_retired_shop_plan(p)
    ]


def _adjust_plan_price_for_ip(plan: Plan, limit_ip: int, per_ip: int) -> int:
    return int(plan.price_toman) + (int(limit_ip) - int(plan.limit_ip or 1)) * max(0, int(per_ip))


def _interpolate_duration_price(
    plans: list[Plan],
    *,
    duration_days: int,
    limit_ip: int,
    per_ip: int,
) -> int | None:
    if not plans:
        return None
    pool = sorted(plans, key=lambda p: int(p.duration_days))
    for plan in pool:
        if int(plan.duration_days) == duration_days:
            return _round_shop_price(_adjust_plan_price_for_ip(plan, limit_ip, per_ip))

    if duration_days <= int(pool[0].duration_days):
        plan = pool[0]
        scaled = int(plan.price_toman) * duration_days / max(1, int(plan.duration_days))
        return _round_shop_price(scaled + (limit_ip - int(plan.limit_ip or 1)) * per_ip)

    if duration_days >= int(pool[-1].duration_days):
        plan = pool[-1]
        scaled = int(plan.price_toman) * duration_days / max(1, int(plan.duration_days))
        return _round_shop_price(scaled + (limit_ip - int(plan.limit_ip or 1)) * per_ip)

    for idx in range(len(pool) - 1):
        left, right = pool[idx], pool[idx + 1]
        left_days, right_days = int(left.duration_days), int(right.duration_days)
        if left_days <= duration_days <= right_days:
            span = max(1, right_days - left_days)
            t = (duration_days - left_days) / span
            left_price = _adjust_plan_price_for_ip(left, limit_ip, per_ip)
            right_price = _adjust_plan_price_for_ip(right, limit_ip, per_ip)
            return _round_shop_price(left_price + t * (right_price - left_price))
    return None


def _monthly_metered_usage_fee(traffic_gb: int) -> float:
    """Usage fee for one month of metered traffic (excludes config base fee)."""
    gb = max(0, int(traffic_gb))
    return CUSTOM_METERED_MONTHLY_INTERCEPT + CUSTOM_METERED_MONTHLY_SLOPE * gb


def _catalog_anchored_custom_price(
    session: Session,
    *,
    duration_days: int,
    traffic_gb: int,
    limit_ip: int,
    unlimited: bool,
) -> int | None:
    """Exact shop-package match only; other shapes use the base+usage formula."""
    plans = _catalog_vpn_plans(session)
    if not plans:
        return None
    for plan in plans:
        plan_unlimited = int(plan.traffic_gb or 0) <= 0
        if int(plan.duration_days) != duration_days:
            continue
        if int(plan.limit_ip or 1) != limit_ip:
            continue
        if unlimited != plan_unlimited:
            continue
        if not unlimited and int(plan.traffic_gb) != traffic_gb:
            continue
        return int(plan.price_toman)
    return None


def compute_custom_base_price(
    session: Session,
    *,
    duration_days: int,
    traffic_gb: int,
    limit_ip: int,
    unlimited: bool,
) -> int:
    """Price = config base fee + usage (duration/traffic) + extra IP.

    Calibrated anchors (default IP):
      - 5GB / 30 days → 55,000
      - 50GB / 30 days → 180,000 (same as ready package)
    Lower GB stays relatively expensive (not linear 50→5 discount).
    """
    matched = _catalog_anchored_custom_price(
        session,
        duration_days=duration_days,
        traffic_gb=traffic_gb,
        limit_ip=limit_ip,
        unlimited=unlimited,
    )
    if matched is not None:
        return matched

    base_fee = _custom_int_setting(session, CUSTOM_BASE_FEE_SETTING, DEFAULT_CUSTOM_BASE_FEE)
    per_ip = _custom_int_setting(session, CUSTOM_PRICE_PER_IP_SETTING, DEFAULT_CUSTOM_PRICE_PER_IP)
    min_price = _custom_int_setting(session, CUSTOM_MIN_PRICE_SETTING, DEFAULT_CUSTOM_MIN_PRICE)
    months = max(duration_days, 1) / 30.0
    plans = _catalog_vpn_plans(session)

    if unlimited:
        unlimited_plans = [p for p in plans if int(p.traffic_gb or 0) <= 0]
        interpolated = _interpolate_duration_price(
            unlimited_plans,
            duration_days=duration_days,
            limit_ip=limit_ip,
            per_ip=per_ip,
        )
        if interpolated is not None:
            return max(min_price, interpolated)
        ref = next((p for p in unlimited_plans if int(p.duration_days) == 30), None)
        monthly = float(int(ref.price_toman) - base_fee) if ref else 270_000.0
        total = base_fee + months * monthly + (limit_ip - CUSTOM_UNLIMITED_REF_IP) * per_ip
        return max(min_price, _round_shop_price(int(round(total))))

    monthly_usage = _monthly_metered_usage_fee(traffic_gb)
    total = base_fee + months * monthly_usage + (limit_ip - CUSTOM_METERED_REF_IP) * per_ip

    unlimited_price = _interpolate_duration_price(
        [p for p in plans if int(p.traffic_gb or 0) <= 0],
        duration_days=duration_days,
        limit_ip=max(limit_ip, CUSTOM_UNLIMITED_REF_IP),
        per_ip=per_ip,
    )
    if unlimited_price is not None and total >= unlimited_price:
        total = max(base_fee, unlimited_price - 5_000)

    return max(min_price, _round_shop_price(int(round(total))))


def custom_charge_price(session: Session, user: User, base_price: int) -> int:
    if is_user_pro(user):
        discount = pro_discount_percent(session)
        return max(0, int(base_price * (100 - discount) / 100))
    return base_price


def quote_custom_package(
    session: Session,
    user: User,
    *,
    duration_days: int,
    traffic_gb: int,
    limit_ip: int,
    unlimited: bool,
) -> dict[str, Any]:
    validate_custom_package(
        session,
        duration_days=duration_days,
        traffic_gb=traffic_gb,
        limit_ip=limit_ip,
        unlimited=unlimited,
        user=user,
    )
    effective_gb = 0 if unlimited else traffic_gb
    base_price = compute_custom_base_price(
        session,
        duration_days=duration_days,
        traffic_gb=effective_gb,
        limit_ip=limit_ip,
        unlimited=unlimited,
    )
    charge = custom_charge_price(session, user, base_price)
    wallet = wallet_spendable(user)
    return {
        "duration_days": duration_days,
        "traffic_gb": effective_gb,
        "limit_ip": limit_ip,
        "unlimited": unlimited,
        "title": format_custom_plan_title(
            duration_days,
            effective_gb,
            limit_ip,
            unlimited=unlimited,
        ),
        "traffic_label": traffic_label(effective_gb),
        "price_toman": base_price,
        "price_label": format_price(base_price),
        "charge_toman": charge,
        "charge_label": format_price(charge),
        "pay_after_wallet": max(0, charge - wallet),
        "pro_discount_percent": pro_discount_percent(session) if is_user_pro(user) else 0,
    }


def order_plan_title(order: Order) -> str:
    if is_payg_order(order):
        note = order.admin_note or ""
        gb = int(order.custom_traffic_gb or 0)
        if note == "payg_metered_activate" or gb <= 0:
            return format_metered_payg_title()
        return format_payg_title(gb, int(order.custom_limit_ip or 1))
    if is_custom_order(order):
        unlimited = (order.custom_traffic_gb or 0) <= 0
        return format_custom_plan_title(
            int(order.custom_duration_days or 0),
            int(order.custom_traffic_gb or 0),
            int(order.custom_limit_ip or 1),
            unlimited=unlimited,
        )
    return order.plan.title if order.plan else "—"


def order_provision_params(order: Order) -> tuple[int, int, int]:
    if is_payg_order(order):
        return (
            0,
            int(order.custom_traffic_gb or 0),
            int(order.custom_limit_ip or 1),
        )
    if is_custom_order(order):
        days = int(order.custom_duration_days or 30)
        days += max(0, int(getattr(order, "bonus_days", 0) or 0))
        return (
            days,
            int(order.custom_traffic_gb or 0),
            int(order.custom_limit_ip or 2),
        )
    plan = order.plan
    days = int(plan.duration_days)
    days += max(0, int(getattr(order, "bonus_days", 0) or 0))
    return days, int(plan.traffic_gb), int(plan.limit_ip)


def subscription_config_dict(sub: Subscription) -> dict[str, Any]:
    payg = is_payg_subscription(sub)
    metered = is_metered_payg(sub)
    order = sub.order
    if metered:
        limit_ip = int(order.custom_limit_ip or 0) if order else 0
        if limit_ip <= 0:
            limit_ip = DEFAULT_PAYG_LIMIT_IP
        return {
            "plan_title": format_metered_payg_title(),
            "duration_days": 0,
            "traffic_gb": 0,
            "traffic_label": "بر اساس مصرف",
            "limit_ip": limit_ip,
            "is_custom": False,
            "is_payg": True,
            "is_metered": True,
        }
    if order and is_payg_order(order):
        gb = int(order.custom_traffic_gb or 0)
        return {
            "plan_title": order_plan_title(order),
            "duration_days": 0,
            "traffic_gb": gb,
            "traffic_label": "بر اساس مصرف" if gb <= 0 else traffic_label(gb),
            "limit_ip": int(order.custom_limit_ip or 1),
            "is_custom": False,
            "is_payg": True,
            "is_metered": gb <= 0,
        }
    if order and is_custom_order(order):
        unlimited = (order.custom_traffic_gb or 0) <= 0
        gb = int(order.custom_traffic_gb or 0)
        return {
            "plan_title": order_plan_title(order),
            "duration_days": int(order.custom_duration_days or 0),
            "traffic_gb": gb,
            "traffic_label": traffic_label(gb),
            "limit_ip": int(order.custom_limit_ip or 1),
            "is_custom": True,
            "is_payg": False,
        }
    plan = sub.plan
    return {
        "plan_title": format_metered_payg_title() if payg else (plan.title if plan else "—"),
        "duration_days": 0 if payg else (plan.duration_days if plan else 0),
        "traffic_gb": 0 if payg else (plan.traffic_gb if plan else 0),
        "traffic_label": "بر اساس مصرف" if payg else (traffic_label(plan.traffic_gb) if plan else "—"),
        "limit_ip": plan.limit_ip if plan else None,
        "is_custom": False,
        "is_payg": payg,
        "is_metered": metered,
    }


def normalize_customer_meta(
    *,
    customer_name: str | None = None,
    customer_email: str | None = None,
    customer_phone: str | None = None,
    customer_telegram_id: str | None = None,
) -> dict[str, str | None]:
    """Sanitize optional end-customer fields for reseller / buy-for-others orders."""

    def _clean(value: str | None, max_len: int) -> str | None:
        if value is None:
            return None
        text = " ".join(str(value).strip().split())
        if not text:
            return None
        return text[:max_len]

    name = _clean(customer_name, 64)
    email = _clean(customer_email, 128)
    phone = _clean(customer_phone, 32)
    tg = _clean(customer_telegram_id, 64)
    if tg and tg.startswith("@"):
        tg = tg[1:].strip() or None
    return {
        "customer_name": name,
        "customer_email": email,
        "customer_phone": phone,
        "customer_telegram_id": tg,
    }


def customer_meta_dict(obj: Order | Subscription) -> dict[str, str | None]:
    return {
        "customer_name": getattr(obj, "customer_name", None) or None,
        "customer_email": getattr(obj, "customer_email", None) or None,
        "customer_phone": getattr(obj, "customer_phone", None) or None,
        "customer_telegram_id": getattr(obj, "customer_telegram_id", None) or None,
    }


def has_customer_meta(meta: dict[str, str | None]) -> bool:
    return any(meta.get(k) for k in ("customer_name", "customer_email", "customer_phone", "customer_telegram_id"))


def apply_customer_meta(target: Order | Subscription, meta: dict[str, str | None]) -> None:
    target.customer_name = meta.get("customer_name")
    target.customer_email = meta.get("customer_email")
    target.customer_phone = meta.get("customer_phone")
    target.customer_telegram_id = meta.get("customer_telegram_id")


def set_subscription_link_shared(session: Session, sub: Subscription, shared: bool) -> Subscription:
    sub.link_shared_at = datetime.utcnow() if shared else None
    session.commit()
    session.refresh(sub)
    return sub


def _reseller_days_left(sub: Subscription, *, now: datetime) -> int | None:
    if not sub.expires_at:
        return None
    return math.ceil((sub.expires_at - now).total_seconds() / 86400.0)


def reseller_desk_item(sub: Subscription, settings, *, now: datetime | None = None) -> dict[str, Any]:
    when = now or datetime.utcnow()
    cfg = subscription_config_dict(sub)
    expired = subscription_is_expired(sub, now=when)
    days_left = _reseller_days_left(sub, now=when)
    shared_at = getattr(sub, "link_shared_at", None)
    return {
        "id": sub.id,
        "label": sub.label,
        "plan_title": cfg.get("plan_title") or "—",
        "traffic_label": cfg.get("traffic_label"),
        "expires_at": sub.expires_at.isoformat() if sub.expires_at else None,
        "days_left": days_left,
        "expired": expired,
        "enabled": bool(sub.enabled),
        "is_payg": bool(cfg.get("is_payg")),
        "subscription_url": build_subscription_url(sub.xui_sub_id, settings),
        "link_shared": bool(shared_at),
        "link_shared_at": shared_at.isoformat() if shared_at else None,
        "family_role": getattr(sub, "family_role", None),
        "hidden": bool(getattr(sub, "hidden_from_dashboard", False)),
        **customer_meta_dict(sub),
    }


def list_reseller_desk(session: Session, user: User, settings) -> dict[str, Any]:
    """Configs this user bought for named end-customers — not wholesale pricing."""
    now = datetime.utcnow()
    items: list[dict[str, Any]] = []
    for sub in user_all_subscriptions(session, user.id):
        name = (getattr(sub, "customer_name", None) or "").strip()
        if not name:
            continue
        items.append(reseller_desk_item(sub, settings, now=now))
    items.sort(
        key=lambda row: (
            0 if not row["link_shared"] else 1,
            0 if row["expired"] else 1,
            row["days_left"] if row["days_left"] is not None else 10_000,
            (row["customer_name"] or "").lower(),
        )
    )
    return {
        "items": items,
        "summary": {
            "total": len(items),
            "unsent": sum(1 for row in items if not row["link_shared"] and not row["expired"]),
            "expiring_soon": sum(
                1
                for row in items
                if not row["expired"] and row["days_left"] is not None and int(row["days_left"]) <= 7
            ),
            "expired": sum(1 for row in items if row["expired"]),
        },
    }


def create_custom_order(
    session: Session,
    user: User,
    *,
    duration_days: int,
    traffic_gb: int,
    limit_ip: int,
    unlimited: bool,
    target_subscription_id: int | None = None,
    promo_code: str | None = None,
    family_size: int = 1,
    customer_name: str | None = None,
    customer_email: str | None = None,
    customer_phone: str | None = None,
    customer_telegram_id: str | None = None,
    config_label: str | None = None,
) -> Order:
    from app.growth import family_settings_dict, quote_growth_pricing

    if user_pending_order(session, user.id):
        raise PendingOrderError("pending_order_exists")
    if target_subscription_id:
        sub = get_user_subscription(session, user.id, target_subscription_id)
        if not sub:
            raise ValueError("not_owner")
        family_size = 1
    validate_custom_package(
        session,
        duration_days=duration_days,
        traffic_gb=traffic_gb,
        limit_ip=limit_ip,
        unlimited=unlimited,
        user=user,
    )
    effective_gb = 0 if unlimited else traffic_gb
    base_price = compute_custom_base_price(
        session,
        duration_days=duration_days,
        traffic_gb=effective_gb,
        limit_ip=limit_ip,
        unlimited=unlimited,
    )
    unit_charge = custom_charge_price(session, user, base_price)
    fam = family_settings_dict(session)
    size = 1 if target_subscription_id else max(1, int(family_size or 1))
    if fam["enabled"] and not target_subscription_id:
        size = min(size, int(fam["max_size"]))
    else:
        size = 1
    growth = quote_growth_pricing(session, user, unit_charge, promo_code=promo_code, family_size=size)
    if promo_code and not growth["promo_ok"]:
        raise ValueError(growth["promo_error"] or "promo_invalid")
    charge_price = int(growth["charge_toman"])
    wallet_used, locked_used = spend_wallet(user, charge_price)
    pay_amount = charge_price - wallet_used
    plan = get_custom_plan(session)
    order = Order(
        user_id=user.id,
        plan_id=plan.id,
        status=OrderStatus.PENDING,
        amount_toman=pay_amount,
        wallet_used=wallet_used,
        wallet_locked_used=locked_used,
        target_subscription_id=target_subscription_id,
        admin_note=f"renew_sub:{target_subscription_id}" if target_subscription_id else None,
        custom_duration_days=duration_days,
        custom_traffic_gb=effective_gb,
        custom_limit_ip=limit_ip,
        custom_price_toman=base_price,
        promo_code=growth.get("promo_code"),
        promo_kind=growth.get("promo_kind"),
        promo_value=growth.get("promo_value"),
        discount_toman=int(growth.get("discount_toman") or 0),
        bonus_days=int(growth.get("bonus_days") or 0),
        family_size=int(growth.get("family_size") or 1),
        config_label=(config_label or "").strip()[:64] or None,
    )
    if not target_subscription_id:
        apply_customer_meta(
            order,
            normalize_customer_meta(
                customer_name=customer_name,
                customer_email=customer_email,
                customer_phone=customer_phone,
                customer_telegram_id=customer_telegram_id,
            ),
        )
    session.add(order)
    session.commit()
    session.refresh(order)
    return order


def create_order(
    session: Session,
    user: User,
    plan: Plan,
    *,
    promo_code: str | None = None,
    family_size: int = 1,
    customer_name: str | None = None,
    customer_email: str | None = None,
    customer_phone: str | None = None,
    customer_telegram_id: str | None = None,
    config_label: str | None = None,
    gift_card: bool = False,
) -> Order:
    from app.growth import family_settings_dict, quote_growth_pricing

    if user_pending_order(session, user.id):
        raise PendingOrderError("pending_order_exists")
    if gift_card:
        from app.gifts import assert_giftable_shop_plan

        assert_giftable_shop_plan(user, plan)
    assert_shop_plan_available(user, plan)
    unit_charge = plan_charge_price(session, user, plan)
    allow_family = is_vpn_plan(plan) and not gift_card
    allow_promo = (is_vpn_plan(plan) or is_platform_pro(plan)) and not gift_card
    fam = family_settings_dict(session)
    size = 1
    if allow_family and fam["enabled"]:
        size = max(1, min(int(family_size or 1), int(fam["max_size"])))
    growth = quote_growth_pricing(
        session,
        user,
        unit_charge,
        promo_code=promo_code if allow_promo else None,
        family_size=size if allow_family else 1,
    )
    if allow_promo and promo_code and not growth["promo_ok"]:
        raise ValueError(growth["promo_error"] or "promo_invalid")
    if not allow_promo:
        growth = quote_growth_pricing(session, user, unit_charge, promo_code=None, family_size=1)

    charge_price = int(growth["charge_toman"])
    wallet_used, locked_used = spend_wallet(user, charge_price)
    pay_amount = charge_price - wallet_used
    order = Order(
        user_id=user.id,
        plan_id=plan.id,
        status=OrderStatus.PENDING,
        amount_toman=pay_amount,
        wallet_used=wallet_used,
        wallet_locked_used=locked_used,
        promo_code=growth.get("promo_code") if allow_promo else None,
        promo_kind=growth.get("promo_kind") if allow_promo else None,
        promo_value=growth.get("promo_value") if allow_promo else None,
        discount_toman=int(growth.get("discount_toman") or 0) if allow_promo else 0,
        bonus_days=int(growth.get("bonus_days") or 0) if is_vpn_plan(plan) else 0,
        family_size=int(growth.get("family_size") or 1) if allow_family else 1,
        config_label=(config_label or "").strip()[:64] or None,
        admin_note="gift_card" if gift_card else None,
    )
    if is_vpn_plan(plan) and not gift_card:
        apply_customer_meta(
            order,
            normalize_customer_meta(
                customer_name=customer_name,
                customer_email=customer_email,
                customer_phone=customer_phone,
                customer_telegram_id=customer_telegram_id,
            ),
        )
    session.add(order)
    session.commit()
    session.refresh(order)
    return order


def create_payg_order(
    session: Session,
    user: User,
    *,
    traffic_gb: int,
    limit_ip: int,
    target_subscription_id: int | None = None,
    customer_name: str | None = None,
    customer_email: str | None = None,
    customer_phone: str | None = None,
    customer_telegram_id: str | None = None,
    config_label: str | None = None,
) -> Order:
    if user_pending_order(session, user.id):
        raise PendingOrderError("pending_order_exists")
    if target_subscription_id:
        sub = get_user_subscription(session, user.id, target_subscription_id)
        if not sub or not is_payg_subscription(sub) or is_metered_payg(sub):
            raise ValueError("payg_target_invalid")
    validate_payg_package(session, traffic_gb=traffic_gb, limit_ip=limit_ip)
    base_price = compute_payg_base_price(
        session,
        traffic_gb=traffic_gb,
        limit_ip=limit_ip,
        include_ip_fee=not bool(target_subscription_id),
    )
    charge_price = custom_charge_price(session, user, base_price)
    wallet_used, locked_used = spend_wallet(user, charge_price)
    pay_amount = charge_price - wallet_used
    plan = get_payg_plan(session)
    order = Order(
        user_id=user.id,
        plan_id=plan.id,
        status=OrderStatus.PENDING,
        amount_toman=pay_amount,
        wallet_used=wallet_used,
        wallet_locked_used=locked_used,
        target_subscription_id=target_subscription_id,
        admin_note=f"payg_topup:{target_subscription_id}" if target_subscription_id else "payg_new",
        custom_traffic_gb=traffic_gb,
        custom_limit_ip=limit_ip,
        custom_price_toman=base_price,
        config_label=(config_label or "").strip()[:64] or None,
    )
    if not target_subscription_id:
        apply_customer_meta(
            order,
            normalize_customer_meta(
                customer_name=customer_name,
                customer_email=customer_email,
                customer_phone=customer_phone,
                customer_telegram_id=customer_telegram_id,
            ),
        )
    session.add(order)
    session.commit()
    session.refresh(order)
    return order


def approve_payg_topup(session: Session, panel, order: Order, sub: Subscription) -> Subscription:
    if order.status != OrderStatus.PENDING:
        raise ValueError("not_pending")
    if not is_payg_order(order):
        raise ValueError("not_payg_order")
    gb = int(order.custom_traffic_gb or 0)
    if gb <= 0:
        raise ValueError("invalid_traffic")
    panel.add_traffic_gb(sub.xui_email, gb)
    panel.set_enabled(sub.xui_email, True)
    sub.enabled = True
    sub.is_payg = True
    now = datetime.utcnow()
    order.status = OrderStatus.APPROVED
    order.reviewed_at = now
    session.commit()
    session.refresh(sub)
    return sub


def _notify_telegram(settings, telegram_id: int, text: str, **extra) -> None:
    if not settings or not telegram_id or not text:
        return
    from app.tg_http import send_telegram_message

    send_telegram_message(settings, telegram_id, text, extra=extra or None)


def payg_status_dict(session: Session, user: User, panel=None, *, bill: bool = False) -> dict[str, Any]:
    cfg = payg_builder_settings(session)
    list_price = cfg["price_per_gb_toman"]
    unit_price = payg_unit_price(session, user)
    wallet = int(user.wallet_balance or 0)
    remaining_bytes = (wallet * BYTES_PER_GB) // unit_price if unit_price else 0
    sub = user_metered_payg_subscription(session, user.id)
    if bill and sub and panel is not None:
        try:
            bill_payg_subscription(session, panel, sub)
            session.refresh(user)
            session.refresh(sub)
            wallet = int(user.wallet_balance or 0)
            remaining_bytes = (wallet * BYTES_PER_GB) // unit_price if unit_price else 0
        except Exception:
            logger.exception("payg status bill failed sub=%s", sub.id)
    used_bytes = int(sub.billed_bytes or 0) if sub else 0
    billed_toman = int(sub.billed_toman or 0) if sub else 0
    if sub and panel is not None:
        try:
            traffic = panel.get_traffic(sub.xui_email)
            used_bytes = int(traffic.get("up") or 0) + int(traffic.get("down") or 0)
        except Exception:
            pass
    example_100 = toman_for_bytes(100 * 1024 * 1024, unit_price)
    user_paused = bool(sub and getattr(sub, "payg_paused_by_user", False))
    suspended = bool(sub and not sub.enabled and not user_paused)
    return {
        "enabled": cfg["enabled"],
        "price_per_gb_toman": list_price,
        "price_per_gb_label": format_price(list_price),
        "unit_price_toman": unit_price,
        "unit_price_label": format_price(unit_price),
        "min_wallet_toman": cfg["min_wallet_toman"],
        "min_wallet_label": format_price(cfg["min_wallet_toman"]),
        "limit_ip": cfg["limit_ip"],
        "example_100mb_toman": example_100,
        "example_100mb_label": format_price(example_100),
        "wallet_balance": wallet,
        "wallet_label": format_price(wallet),
        "can_activate": cfg["enabled"] and sub is None and wallet >= cfg["min_wallet_toman"],
        "needs_topup": wallet < cfg["min_wallet_toman"],
        "pro_discount_percent": pro_discount_percent(session) if is_user_pro(user) else 0,
        "remaining_bytes": remaining_bytes,
        "remaining_label": format_bytes(remaining_bytes) if unit_price else "—",
        "used_bytes": used_bytes,
        "used_label": format_bytes(used_bytes),
        "billed_toman": billed_toman,
        "billed_label": format_price(billed_toman),
        "suspended": suspended,
        "user_paused": user_paused,
        "can_set_enabled": bool(sub),
        "subscription": (
            {
                "id": sub.id,
                "email": sub.xui_email,
                "label": sub.label,
                "enabled": bool(sub.enabled),
                "paused_by_user": user_paused,
                "plan_title": format_metered_payg_title(),
            }
            if sub
            else None
        ),
    }


def apply_metered_payg_stats(session: Session, user: User, sub: Subscription, stats: dict[str, Any]) -> dict[str, Any]:
    if not is_metered_payg(sub):
        return stats
    price = payg_unit_price(session, user)
    wallet = int(user.wallet_balance or 0)
    remaining_bytes = (wallet * BYTES_PER_GB) // price if price else 0
    stats["total_bytes"] = 0
    stats["total_label"] = "مصرف کیف‌پول"
    stats["remaining_bytes"] = remaining_bytes
    stats["remaining_label"] = format_bytes(remaining_bytes)
    stats["usage_percent"] = 0.0
    stats["billed_toman"] = int(sub.billed_toman or 0)
    stats["billed_label"] = format_price(int(sub.billed_toman or 0))
    stats["is_metered"] = True
    return stats


def bill_payg_subscription(session: Session, panel, sub: Subscription) -> dict[str, Any]:
    if not is_metered_payg(sub):
        return {}
    user = sub.user
    try:
        traffic = panel.get_traffic(sub.xui_email)
    except Exception as exc:
        logger.warning("payg traffic fetch failed %s: %s", sub.xui_email, exc)
        return {}
    used = int(traffic.get("up") or 0) + int(traffic.get("down") or 0)
    total = int(traffic.get("total") or 0)
    if total > 0:
        return {}
    price = payg_unit_price(session, user)
    billed_bytes = int(sub.billed_bytes or 0)
    billed_toman = int(sub.billed_toman or 0)
    if used + 8_388_608 < billed_bytes:
        billed_bytes = used
        billed_toman = toman_for_bytes(used, price)
        sub.billed_bytes = billed_bytes
        sub.billed_toman = billed_toman
        sub.last_billed_at = datetime.utcnow()
        session.commit()
        return {"reset": True, "used": used}
    target = toman_for_bytes(used, price)
    due = target - billed_toman
    now = datetime.utcnow()
    if due <= 0:
        sub.billed_bytes = used
        sub.last_billed_at = now
        session.commit()
        return {"due": 0, "used": used}
    charge, _ = spend_wallet(user, due)
    sub.billed_toman = billed_toman + charge
    sub.billed_bytes = used
    sub.last_billed_at = now
    unpaid = due - charge
    suspended = False
    if unpaid > 0 or wallet_spendable(user) <= 0:
        try:
            panel.set_enabled(sub.xui_email, False)
        except Exception:
            logger.exception("payg disable failed %s", sub.xui_email)
        sub.enabled = False
        suspended = True
    session.commit()
    return {"charged": charge, "suspended": suspended, "used": used, "unpaid": unpaid}


def resume_metered_payg_if_funded(session: Session, panel, user: User, settings=None) -> list[Subscription]:
    resumed: list[Subscription] = []
    min_wallet = int(payg_builder_settings(session).get("min_wallet_toman") or 0)
    for sub in user_payg_subscriptions(session, user.id):
        if not is_metered_payg(sub):
            continue
        try:
            bill_payg_subscription(session, panel, sub)
            session.refresh(user)
            session.refresh(sub)
        except Exception:
            logger.exception("payg bill-before-resume failed sub=%s", sub.id)
        if getattr(sub, "payg_paused_by_user", False):
            continue
        if wallet_spendable(user) < min_wallet:
            continue
        if sub.enabled:
            continue
        try:
            panel.set_enabled(sub.xui_email, True)
            sub.enabled = True
            session.commit()
            resumed.append(sub)
        except Exception:
            logger.exception("payg resume failed %s", sub.xui_email)
    return resumed


def bill_all_metered_payg(session: Session, panel, settings=None) -> None:
    for sub in list_metered_payg_subscriptions(session):
        try:
            result = bill_payg_subscription(session, panel, sub)
        except Exception:
            logger.exception("payg billing failed sub=%s", sub.id)
            continue
        if result.get("suspended") and settings and sub.user:
            _notify_telegram(
                settings,
                sub.user.telegram_id,
                (
                    "⏸ کانفیگ مصرفی قطع شد — موجودی کیف‌پول کافی نیست.\n"
                    f"آخرین کسر: {format_price(int(result.get('charged') or 0))}\n"
                    f"موجودی: {format_price(sub.user.wallet_balance or 0)}\n"
                    "کیف‌پول را شارژ کنید تا دوباره وصل شود."
                ),
            )
    try:
        sample_stale_subscriptions(session, panel)
    except Exception:
        logger.exception("usage sampling failed")


def set_metered_payg_enabled(session: Session, user: User, panel, *, enabled: bool, settings=None) -> dict[str, Any]:
    """User toggle for cloud PAYG — pause does not auto-resume on wallet top-up."""
    if not payg_builder_enabled(session):
        raise ValueError("payg_builder_disabled")
    sub = user_metered_payg_subscription(session, user.id)
    if not sub:
        raise ValueError("payg_not_found")
    cfg = payg_builder_settings(session)
    if enabled:
        wallet = wallet_spendable(user)
        if wallet < int(cfg["min_wallet_toman"] or 0):
            raise ValueError("insufficient_wallet")
        try:
            bill_payg_subscription(session, panel, sub)
            session.refresh(user)
            session.refresh(sub)
        except Exception:
            logger.exception("payg bill-before-enable failed sub=%s", sub.id)
        if wallet_spendable(user) < int(cfg["min_wallet_toman"] or 0):
            raise ValueError("insufficient_wallet")
        panel.set_enabled(sub.xui_email, True)
        sub.enabled = True
        sub.payg_paused_by_user = False
        session.commit()
    else:
        try:
            panel.set_enabled(sub.xui_email, False)
        except Exception:
            logger.exception("payg user-disable failed %s", sub.xui_email)
        sub.enabled = False
        sub.payg_paused_by_user = True
        session.commit()
    session.refresh(sub)
    session.refresh(user)
    return payg_status_dict(session, user, panel, bill=False)


def activate_metered_payg(session: Session, user: User, panel, settings) -> dict[str, Any]:
    if not payg_builder_enabled(session):
        raise ValueError("payg_builder_disabled")
    cfg = payg_builder_settings(session)
    wallet = wallet_spendable(user)
    existing = user_metered_payg_subscription(session, user.id)
    if existing:
        existing.payg_paused_by_user = False
        session.commit()
        resume_metered_payg_if_funded(session, panel, user, settings)
        session.refresh(user)
        session.refresh(existing)
        links = public_links_for_subscription(panel, existing, settings)
        status = payg_status_dict(session, user, panel, bill=True)
        status["links"] = links
        status["created"] = False
        return status
    if wallet < cfg["min_wallet_toman"]:
        raise ValueError("insufficient_wallet")
    plan = get_payg_plan(session)
    email = f"payg{user.telegram_id}-{secrets.token_hex(2)}"
    client = panel.create_client(
        email=email,
        duration_days=0,
        traffic_gb=0,
        limit_ip=cfg["limit_ip"],
        tg_id=user.telegram_id,
        comment="payg-metered",
    )
    links = public_links_for_email(panel, email, settings, name="مصرفی ابری")
    now = datetime.utcnow()
    order = Order(
        user_id=user.id,
        plan_id=plan.id,
        status=OrderStatus.APPROVED,
        amount_toman=0,
        wallet_used=0,
        custom_traffic_gb=0,
        custom_limit_ip=cfg["limit_ip"],
        custom_price_toman=0,
        admin_note="payg_metered_activate",
        reviewed_at=now,
    )
    session.add(order)
    session.flush()
    sub = Subscription(
        user_id=user.id,
        order_id=order.id,
        plan_id=plan.id,
        xui_email=email,
        xui_uuid=client.get("uuid") or client.get("id"),
        xui_sub_id=client.get("subId") or client.get("sub_id"),
        label="مصرفی ابری",
        enabled=True,
        is_payg=True,
        payg_metered=True,
        billed_bytes=0,
        billed_toman=0,
        expires_at=None,
    )
    session.add(sub)
    session.commit()
    session.refresh(sub)
    session.refresh(user)
    status = payg_status_dict(session, user, panel)
    status["links"] = links
    status["created"] = True
    status["email"] = email
    status["subscription_url"] = build_subscription_url(sub.xui_sub_id, settings)
    return status


def pro_discount_percent(session: Session) -> int:
    raw = get_setting(session, PRO_DISCOUNT_SETTING, str(DEFAULT_PRO_DISCOUNT))
    try:
        return max(0, min(90, int(raw)))
    except ValueError:
        return DEFAULT_PRO_DISCOUNT


def is_user_pro(user: User) -> bool:
    if not user.pro_until:
        return False
    return user.pro_until.replace(tzinfo=None) > datetime.utcnow()


def plan_charge_price(session: Session, user: User, plan: Plan) -> int:
    base = int(plan.price_toman or 0)
    if is_vpn_plan(plan) and is_user_pro(user):
        discount = pro_discount_percent(session)
        return max(0, int(base * (100 - discount) / 100))
    return base


def get_platform_pro_plan(session: Session) -> Plan:
    plan = session.scalar(select(Plan).where(Plan.code == PLATFORM_PRO_CODE))
    if plan is None:
        ensure_plans_catalog(session)
        session.commit()
        plan = session.scalar(select(Plan).where(Plan.code == PLATFORM_PRO_CODE))
    if plan is None:
        raise RuntimeError("platform pro plan missing")
    return plan


def approve_pro_subscription(session: Session, order: Order) -> datetime:
    if order.status != OrderStatus.PENDING:
        raise ValueError("not_pending")
    if not is_platform_pro(order.plan):
        raise ValueError("not_pro_plan")
    user = order.user
    plan = order.plan
    now = datetime.utcnow()
    base = user.pro_until.replace(tzinfo=None) if user.pro_until and user.pro_until.replace(tzinfo=None) > now else now
    user.pro_until = base + timedelta(days=max(1, plan.duration_days or 30))
    order.status = OrderStatus.APPROVED
    order.reviewed_at = now
    session.commit()
    session.refresh(user)
    return user.pro_until


def pro_status_dict(session: Session, user: User) -> dict[str, Any]:
    plan = get_platform_pro_plan(session)
    discount = pro_discount_percent(session)
    active = is_user_pro(user)
    return {
        "is_pro": active,
        "pro_until": user.pro_until.isoformat() if user.pro_until else None,
        "pro_until_label": (
            user.pro_until.strftime("%Y/%m/%d")
            if user.pro_until and active
            else None
        ),
        "discount_percent": discount,
        "plan": {
            "id": plan.id,
            "title": plan.title,
            "description": plan.description,
            "price_toman": plan.price_toman,
            "price_label": format_price(plan.price_toman),
            "duration_days": plan.duration_days,
        },
        "benefits": [
            {
                "id": "discount",
                "title": f"{discount}٪ تخفیف خرید کانفیگ",
                "description": "روی همه پلن‌های VPN در فروشگاه",
                "active": active,
            },
            {
                "id": "unlimited",
                "title": "کانفیگ نامحدود",
                "description": "خرید پلن و پکیج سفارشی با حجم نامحدود",
                "active": active,
            },
            {
                "id": "search",
                "title": "جستجو در کانفیگ‌ها",
                "description": "پیدا کردن سریع بین ده‌ها اشتراک",
                "active": True,
            },
            {
                "id": "manage",
                "title": "مدیریت پیشرفته",
                "description": "برچسب، فیلتر و داشبورد کامل بدون محدودیت",
                "active": active,
            },
            {
                "id": "badge",
                "title": "نشان Pro",
                "description": "نمایش وضعیت Pro در پروفایل",
                "active": active,
            },
            {
                "id": "early",
                "title": "دسترسی زودتر",
                "description": "امکانات جدید پلتفرم زودتر از بقیه",
                "active": active,
                "coming_soon": not active,
            },
        ],
    }


def get_wallet_topup_plan(session: Session) -> Plan:
    plan = session.scalar(select(Plan).where(Plan.code == WALLET_TOPUP_CODE))
    if plan is None:
        ensure_plans_catalog(session)
        session.commit()
        plan = session.scalar(select(Plan).where(Plan.code == WALLET_TOPUP_CODE))
    if plan is None:
        raise RuntimeError("wallet top-up plan missing")
    return plan


def create_wallet_deposit(session: Session, user: User, amount_toman: int) -> Order:
    amount = int(amount_toman)
    if amount < MIN_WALLET_DEPOSIT:
        raise ValueError("amount_too_low")
    if amount > MAX_WALLET_DEPOSIT:
        raise ValueError("amount_too_high")
    if user_pending_order(session, user.id):
        raise PendingOrderError("pending_order_exists")
    plan = get_wallet_topup_plan(session)
    order = Order(
        user_id=user.id,
        plan_id=plan.id,
        status=OrderStatus.PENDING,
        amount_toman=amount,
        wallet_used=0,
    )
    session.add(order)
    session.commit()
    session.refresh(order)
    return order


def approve_wallet_deposit(session: Session, order: Order, panel=None, settings=None) -> int:
    """Credit wallet for a top-up order. Returns credited amount."""
    if order.status != OrderStatus.PENDING:
        raise ValueError("not_pending")
    if not is_wallet_topup(order.plan):
        raise ValueError("not_wallet_topup")
    amount = int(order.amount_toman or 0)
    user = order.user
    user.wallet_balance = (user.wallet_balance or 0) + amount
    order.status = OrderStatus.APPROVED
    order.reviewed_at = datetime.utcnow()
    session.commit()
    if panel is not None:
        try:
            resume_metered_payg_if_funded(session, panel, user, settings)
        except Exception:
            logger.exception("resume payg after wallet credit failed user=%s", user.id)
    return amount


def get_plan(session: Session, plan_id: int) -> Plan | None:
    return session.get(Plan, plan_id)


class PendingOrderError(Exception):
    """User already has an unpaid pending order."""


def user_pending_order(session: Session, user_id: int) -> Order | None:
    return session.scalar(
        select(Order)
        .where(Order.user_id == user_id, Order.status == OrderStatus.PENDING)
        .options(selectinload(Order.plan))
        .order_by(Order.id.desc())
        .limit(1)
    )


def get_order(session: Session, order_id: int) -> Order | None:
    return session.scalar(
        select(Order)
        .where(Order.id == order_id)
        .options(selectinload(Order.user), selectinload(Order.plan), selectinload(Order.subscription))
    )


def list_pending_orders(session: Session, *, include_test: bool = False) -> list[Order]:
    rows = list(
        session.scalars(
            select(Order)
            .where(Order.status == OrderStatus.PENDING)
            .options(selectinload(Order.user), selectinload(Order.plan))
            .order_by(Order.id.desc())
        ).all()
    )
    if include_test:
        return rows
    return [o for o in rows if o.user and not bool(getattr(o.user, "is_test", False))]


def user_all_subscriptions(session: Session, user_id: int) -> list[Subscription]:
    return list(
        session.scalars(
            select(Subscription)
            .where(Subscription.user_id == user_id)
            .options(selectinload(Subscription.plan), selectinload(Subscription.order))
            .order_by(Subscription.id.desc())
        ).all()
    )


def set_subscription_label(session: Session, sub: Subscription, label: str | None) -> Subscription:
    cleaned = (label or "").strip()
    if len(cleaned) > 64:
        cleaned = cleaned[:64]
    sub.label = cleaned or None
    session.commit()
    session.refresh(sub)
    return sub


def subscription_config_name(sub: Subscription) -> str | None:
    """Name shown inside delivered VLESS configs: user label, else plan title."""
    label = sanitize_config_name(sub.label)
    if label:
        return label
    if sub.plan and sub.plan.title:
        return sanitize_config_name(sub.plan.title) or None
    return None


def public_links_for_subscription(panel, sub: Subscription, settings) -> list[str]:
    return public_links_for_email(
        panel,
        sub.xui_email,
        settings,
        name=subscription_config_name(sub),
    )


def get_user_subscription(session: Session, user_id: int, sub_id: int) -> Subscription | None:
    sub = session.scalar(
        select(Subscription)
        .where(Subscription.id == sub_id, Subscription.user_id == user_id)
        .options(selectinload(Subscription.plan), selectinload(Subscription.order))
    )
    return sub


def create_renew_order(session: Session, user: User, sub: Subscription, plan: Plan) -> Order:
    if sub.user_id != user.id:
        raise ValueError("not_owner")
    if not is_vpn_plan(plan):
        raise ValueError("not_vpn_plan")
    assert_shop_plan_available(user, plan)
    if user_pending_order(session, user.id):
        raise PendingOrderError("pending_order_exists")
    charge_price = plan_charge_price(session, user, plan)
    wallet_used, locked_used = spend_wallet(user, charge_price)
    pay_amount = charge_price - wallet_used
    order = Order(
        user_id=user.id,
        plan_id=plan.id,
        status=OrderStatus.PENDING,
        amount_toman=pay_amount,
        wallet_used=wallet_used,
        wallet_locked_used=locked_used,
        target_subscription_id=sub.id,
        admin_note=f"renew_sub:{sub.id}",
    )
    session.add(order)
    session.commit()
    session.refresh(order)
    return order


def is_prepaid_shop_order(order: Order | None) -> bool:
    """Card/receipt already settled (full wallet, promo, or free) — not a wallet top-up."""
    if not order or not order.plan:
        return False
    if is_wallet_topup(order.plan):
        return False
    return int(order.amount_toman or 0) <= 0


def fulfill_pending_order(
    session: Session,
    panel,
    settings,
    order: Order,
    *,
    actor: User | None = None,
    via: str = "admin",
    notify_user: bool = True,
    notify_admins: bool = False,
) -> dict[str, Any]:
    """Approve a pending shop order and provision the product."""
    if not order or order.status != OrderStatus.PENDING:
        raise ValueError("not_pending")
    plan = order.plan
    buyer = order.user
    from app.ops import record_audit

    def _audit(*, target_subscription_id: int | None = None, extra: str = "") -> None:
        record_audit(
            session,
            actor=actor,
            action="approve_order",
            target_user=buyer,
            target_subscription_id=target_subscription_id,
            detail=f"order_id={order.id} via={via} {extra}".strip(),
            category="shop",
            actor_role="admin" if actor else "system",
        )

    def _admin_auto_note(summary: str) -> None:
        if not notify_admins:
            return
        who = buyer.full_name or buyer.username or str(buyer.telegram_id)
        wallet = format_price(int(order.wallet_used or 0)) if order.wallet_used else "—"
        text = (
            f"✅ سفارش #{order.id} به‌صورت خودکار تایید شد\n"
            f"کاربر: {who}\n"
            f"{summary}\n"
            f"پرداخت از کیف‌پول: {wallet}"
        )
        for admin_id in list_admin_telegram_ids(session, settings):
            _notify_telegram(settings, admin_id, text)

    from app.gifts import is_gift_card_order, issue_gift_card_from_order

    if is_gift_card_order(order):
        if order.promo_code:
            try:
                from app.growth import record_promo_redemption, validate_promo_for_user

                promo = validate_promo_for_user(session, buyer, order.promo_code)
                record_promo_redemption(session, promo, buyer, order.id)
            except Exception:
                logger.exception("gift card promo redeem failed")
        card = issue_gift_card_from_order(session, order)
        order.status = OrderStatus.APPROVED
        order.reviewed_at = datetime.utcnow()
        session.commit()
        _audit(extra=f"gift_card={card.code}")
        commission = credit_referral_commission(session, order)
        if notify_user:
            _notify_telegram(
                settings,
                buyer.telegram_id,
                (
                    f"🎁 کارت هدیه آماده شد\n"
                    f"پلن: {order.plan.title if order.plan else '—'}\n"
                    f"کد: <code>{card.code}</code>\n"
                    f"این کد را برای دوستت بفرست تا در فروشگاه فعال کند."
                ),
                disable_web_page_preview=True,
            )
            if commission:
                referrer = session.get(User, commission.referrer_id)
                if referrer:
                    _notify_telegram(
                        settings,
                        referrer.telegram_id,
                        f"🎁 پورسانت جدید: {format_price(commission.amount_toman)}",
                    )
        _admin_auto_note(f"کارت هدیه {card.code}")
        return {
            "ok": True,
            "kind": "gift_card",
            "gift_code": card.code,
            "gift_card": {
                "id": card.id,
                "code": card.code,
                "plan_title": order.plan.title if order.plan else None,
            },
        }

    if is_wallet_topup(plan):
        amount = approve_wallet_deposit(session, order, panel, settings)
        _audit(extra=f"wallet={amount}")
        if notify_user:
            _notify_telegram(
                settings,
                buyer.telegram_id,
                f"✅ کیف‌پول شما {format_price(amount)} شارژ شد.\nموجودی فعلی: {format_price(buyer.wallet_balance or 0)}",
            )
        return {
            "ok": True,
            "kind": "wallet",
            "wallet_credited": amount,
            "wallet_balance": buyer.wallet_balance or 0,
        }

    if is_platform_pro(plan):
        if order.promo_code:
            try:
                from app.growth import record_promo_redemption, validate_promo_for_user

                promo = validate_promo_for_user(session, buyer, order.promo_code)
                record_promo_redemption(session, promo, buyer, order.id)
            except Exception:
                logger.exception("pro promo redeem failed")
        pro_until = approve_pro_subscription(session, order)
        _audit(extra=f"pro_until={pro_until.isoformat()}")
        if notify_user:
            _notify_telegram(
                settings,
                buyer.telegram_id,
                (
                    f"✅ اشتراک Pro فعال شد\n"
                    f"اعتبار تا: {pro_until.strftime('%Y/%m/%d')}\n"
                    f"از این پس {pro_discount_percent(session)}٪ تخفیف روی خرید کانفیگ دارید."
                ),
            )
        _admin_auto_note(f"Pro تا {pro_until.strftime('%Y/%m/%d')}")
        return {"ok": True, "kind": "pro", "pro_until": pro_until.isoformat()}

    if order.target_subscription_id:
        sub = session.get(Subscription, order.target_subscription_id)
        if not sub or sub.user_id != buyer.id:
            raise ValueError("renew_target_invalid")
        if is_payg_order(order):
            approve_payg_topup(session, panel, order, sub)
        else:
            approve_renew_subscription(session, panel, order, sub)
        _audit(target_subscription_id=sub.id, extra="renew")
        commission = credit_referral_commission(session, order)
        if is_payg_order(order):
            gb = int(order.custom_traffic_gb or 0)
            user_msg = f"✅ شارژ مصرفی انجام شد\nشناسه: <code>{sub.xui_email}</code>\n+{gb} گیگ به کانفیگ اضافه شد"
            admin_summary = f"شارژ مصرفی {sub.xui_email} (+{gb} گیگ)"
        else:
            exp = sub.expires_at.strftime("%Y/%m/%d") if sub.expires_at else "—"
            user_msg = f"✅ تمدید انجام شد\nشناسه: <code>{sub.xui_email}</code>\nاعتبار تا: {exp}"
            admin_summary = f"تمدید {sub.xui_email} تا {exp}"
        if notify_user:
            _notify_telegram(settings, buyer.telegram_id, user_msg)
            if commission:
                referrer = session.get(User, commission.referrer_id)
                if referrer:
                    _notify_telegram(
                        settings,
                        referrer.telegram_id,
                        f"🎁 پورسانت جدید: {format_price(commission.amount_toman)}",
                    )
        _admin_auto_note(admin_summary)
        return {
            "ok": True,
            "kind": "renew",
            "renewed": True,
            "subscription_id": sub.id,
            "expires_at": sub.expires_at.isoformat() if sub.expires_at else None,
        }

    duration_days, traffic_gb, limit_ip = order_provision_params(order)
    family_size = max(1, min(10, int(getattr(order, "family_size", 1) or 1)))
    family_group = secrets.token_hex(4) if family_size > 1 else None
    created_subs: list[Subscription] = []
    link_chunks: list[str] = []
    email = f"tg{buyer.telegram_id}-{secrets.token_hex(3)}"
    for idx in range(1, family_size + 1):
        email = f"tg{buyer.telegram_id}-{secrets.token_hex(3)}"
        chosen = (getattr(order, "config_label", None) or "").strip()
        base_title = chosen or (plan.title or "کانفیگ").strip()
        cust_name = (getattr(order, "customer_name", None) or "").strip()
        if family_size > 1:
            role = "parent" if idx == 1 else "child"
            if chosen:
                label = f"{chosen} · والد" if idx == 1 else f"{chosen} · فرزند {idx - 1}"
            elif cust_name:
                label = f"{cust_name} · والد" if idx == 1 else f"{cust_name} · فرزند {idx - 1}"
            else:
                label = f"{base_title} · والد" if idx == 1 else f"{base_title} · فرزند {idx - 1}"
        else:
            role = None
            label = chosen or cust_name or base_title
        client = panel.create_client(
            email=email,
            duration_days=duration_days,
            traffic_gb=traffic_gb,
            limit_ip=limit_ip,
            tg_id=buyer.telegram_id,
            comment=f"order-{order.id}-{idx}",
        )
        sub = attach_subscription(
            session,
            user=buyer,
            order=order,
            plan=plan,
            xui_email=email,
            xui_uuid=client.get("uuid") or client.get("id"),
            xui_sub_id=client.get("subId") or client.get("sub_id"),
            duration_days=duration_days,
            label=label,
            family_group=family_group,
            family_index=idx if family_size > 1 else None,
            family_role=role,
            finalize_order=(idx == family_size),
        )
        created_subs.append(sub)
        sub_url = build_subscription_url(sub.xui_sub_id, settings)
        link_chunks.append(
            f"<b>{label}</b>\nشناسه: <code>{email}</code>\n"
            + (f"لینک اشتراک:\n<code>{sub_url}</code>" if sub_url else "لینک اشتراک را در مینی‌اپ ببینید.")
        )
    if order.promo_code:
        try:
            from app.growth import record_promo_redemption, validate_promo_for_user

            promo = validate_promo_for_user(session, buyer, order.promo_code)
            record_promo_redemption(session, promo, buyer, order.id)
        except Exception:
            logger.exception("promo redeem on approve failed order=%s", order.id)
    _audit(
        target_subscription_id=created_subs[0].id if created_subs else None,
        extra=f"email={created_subs[0].xui_email if created_subs else email}",
    )
    commission = credit_referral_commission(session, order)
    body = "\n\n".join(link_chunks)
    fam_note = f"\nپکیج خانواده: {family_size} کانفیگ" if family_size > 1 else ""
    promo_note = ""
    if order.discount_toman:
        promo_note += f"\nتخفیف: {format_price(int(order.discount_toman))}"
    if order.bonus_days:
        promo_note += f"\nروز هدیه: {int(order.bonus_days)}"
    if notify_user:
        _notify_telegram(
            settings,
            buyer.telegram_id,
            f"✅ اشتراک فعال شد{fam_note}{promo_note}\n\n{body}\n\nکانفیگ‌های تکی فقط داخل مینی‌اپ هستند.",
            disable_web_page_preview=True,
        )
        if commission:
            referrer = session.get(User, commission.referrer_id)
            if referrer:
                _notify_telegram(
                    settings,
                    referrer.telegram_id,
                    f"🎁 پورسانت جدید: {format_price(commission.amount_toman)}",
                )
    title = order_plan_title(order)
    _admin_auto_note(f"{title} × {family_size}" if family_size > 1 else title)
    return {
        "ok": True,
        "kind": "vpn",
        "email": created_subs[0].xui_email if created_subs else email,
        "family_size": family_size,
        "subscription_ids": [s.id for s in created_subs],
        "expires_at": created_subs[0].expires_at.isoformat() if created_subs and created_subs[0].expires_at else None,
    }


def maybe_auto_fulfill_prepaid_order(session: Session, panel, settings, order: Order) -> dict[str, Any] | None:
    session.refresh(order)
    if order.status != OrderStatus.PENDING or not is_prepaid_shop_order(order):
        return None
    try:
        return fulfill_pending_order(
            session,
            panel,
            settings,
            order,
            via="wallet_auto",
            notify_user=True,
            notify_admins=True,
        )
    except Exception:
        logger.exception("auto fulfill failed order=%s", order.id)
        try:
            for admin_id in list_admin_telegram_ids(session, settings):
                _notify_telegram(
                    settings,
                    admin_id,
                    f"⚠️ تایید خودکار سفارش #{order.id} ناموفق بود. لطفاً دستی تایید کنید.",
                )
        except Exception:
            logger.exception("auto fulfill admin alert failed")
        return None


def approve_renew_subscription(session: Session, panel, order: Order, sub: Subscription) -> Subscription:
    if order.status != OrderStatus.PENDING:
        raise ValueError("not_pending")
    plan = order.plan
    if not is_vpn_plan(plan) and not is_custom_order(order):
        raise ValueError("not_vpn_plan")
    duration_days, _traffic_gb, _limit_ip = order_provision_params(order)
    if duration_days <= 0:
        raise ValueError("invalid_duration")
    panel.extend_days(sub.xui_email, duration_days)
    panel.set_enabled(sub.xui_email, True)
    now = datetime.utcnow()
    if sub.expires_at and sub.expires_at > now:
        sub.expires_at = sub.expires_at + timedelta(days=duration_days)
    else:
        sub.expires_at = now + timedelta(days=duration_days)
    sub.enabled = True
    clear_subscription_dashboard_hide(sub)
    if plan and not is_custom_plan(plan):
        sub.plan_id = plan.id
    order.status = OrderStatus.APPROVED
    order.reviewed_at = now
    session.commit()
    session.refresh(sub)
    return sub


def revoke_subscription(session: Session, panel, sub: Subscription) -> Subscription:
    panel.set_enabled(sub.xui_email, False)
    sub.enabled = False
    session.commit()
    session.refresh(sub)
    return sub


def diagnose_subscription(session: Session, panel, settings, sub: Subscription) -> dict[str, Any]:
    """Re-ping servers and explain why a config might not connect."""
    from app.panel import parse_share_link, ping_tcp

    expired = subscription_is_expired(sub)
    enabled = bool(sub.enabled)
    panel_ok = True
    panel_enabled = enabled
    try:
        client = panel.get_client(sub.xui_email)
        if isinstance(client, dict) and "enable" in client:
            panel_enabled = bool(client.get("enable"))
    except Exception:
        panel_ok = False
        logger.exception("diagnose get_client failed %s", sub.xui_email)
    links: list[str] = []
    try:
        links = public_links_for_subscription(panel, sub, settings)
    except Exception:
        logger.exception("diagnose links failed %s", sub.xui_email)
    items: list[dict[str, Any]] = []
    for i, link in enumerate(links):
        host, port, label, link_type = parse_share_link(link)
        ping_ms = ping_tcp(host, port) if host and port else None
        items.append(
            {
                "index": i,
                "label": label or f"سرور {i + 1}",
                "link": link,
                "kind": link_type,
                "host": host,
                "port": port,
                "ping_ms": ping_ms,
                "reachable": ping_ms is not None,
            }
        )
    vpn_items = [x for x in items if x.get("kind") != "telegram"]
    reachable = [x for x in vpn_items if x["reachable"]]
    best = min(reachable, key=lambda x: int(x["ping_ms"] or 99999)) if reachable else None
    issues: list[dict[str, str]] = []
    if expired:
        issues.append(
            {
                "code": "expired",
                "title": "اعتبار این کانفیگ تمام شده",
                "hint": "از تب تمدید، پلن را تمدید کن تا دوباره وصل شود.",
                "action": "renew",
            }
        )
    if not enabled or not panel_enabled:
        issues.append(
            {
                "code": "disabled",
                "title": "کانفیگ روی سرور خاموش است",
                "hint": "اگر تمدید نکرده‌ای تمدید کن. وگرنه از چت پشتیبانی بپرس.",
                "action": "chat",
            }
        )
    if not vpn_items:
        issues.append(
            {
                "code": "no_links",
                "title": "لینک سرور پیدا نشد",
                "hint": "لینک جدید بساز یا چند لحظه بعد دوباره تست کن.",
                "action": "rotate",
            }
        )
    elif not reachable:
        issues.append(
            {
                "code": "all_down",
                "title": "هیچ سروری الان پاسخ نمی‌دهد",
                "hint": "لینک اشتراک را در اپ آپدیت کن. اگر باز نشد لینک جدید بگیر.",
                "action": "rotate",
            }
        )
    elif len(reachable) < len(vpn_items):
        issues.append(
            {
                "code": "some_down",
                "title": "بعضی سرورها قطع‌اند",
                "hint": "بهترین سرور را کپی کن یا Subscription را در اپ رفرش کن تا سرور سالم بیاید.",
                "action": "copy_best",
            }
        )
    if not issues:
        issues.append(
            {
                "code": "ok",
                "title": "سرورها در دسترس‌اند",
                "hint": "لینک اشتراک را در V2rayNG / V2Box آپدیت کن. اگر باز وصل نشد لینک جدید بگیر.",
                "action": "update_sub",
            }
        )
    sub_url = build_subscription_url(sub.xui_sub_id, settings)
    return {
        "ok": True,
        "subscription_id": sub.id,
        "enabled": enabled,
        "expired": expired,
        "panel_ok": panel_ok,
        "panel_enabled": panel_enabled,
        "subscription_url": sub_url,
        "servers": items,
        "reachable_count": len(reachable),
        "server_count": len(vpn_items),
        "best": best,
        "issues": issues,
        "can_rotate": enabled and not expired,
        "can_renew": True,
    }


def rotate_subscription_link(session: Session, panel, sub: Subscription, settings) -> dict[str, Any]:
    """Invalidate the current UUID / subId and issue a fresh subscription URL."""
    client = panel.rotate_client_identity(sub.xui_email)
    sub.xui_uuid = str(client.get("uuid") or client.get("id") or "") or None
    sub.xui_sub_id = str(client.get("subId") or client.get("sub_id") or "") or None
    sub.link_shared_at = None
    session.commit()
    session.refresh(sub)
    links = public_links_for_subscription(panel, sub, settings)
    return {
        "ok": True,
        "id": sub.id,
        "xui_uuid": sub.xui_uuid,
        "xui_sub_id": sub.xui_sub_id,
        "subscription_url": build_subscription_url(sub.xui_sub_id, settings),
        "subscription_import": subscription_import_base64(links),
        "links": links,
    }


def subscription_is_expired(sub: Subscription, *, now: datetime | None = None) -> bool:
    when = now or datetime.utcnow()
    return bool(sub.expires_at and sub.expires_at <= when)


def hide_subscription_from_dashboard(session: Session, sub: Subscription) -> Subscription:
    """Remove an expired config from the main dashboard list (kept in archive)."""
    if not subscription_is_expired(sub):
        raise ValueError("only_expired")
    sub.hidden_from_dashboard = True
    session.commit()
    session.refresh(sub)
    return sub


def unhide_subscription_from_dashboard(session: Session, sub: Subscription) -> Subscription:
    sub.hidden_from_dashboard = False
    session.commit()
    session.refresh(sub)
    return sub


def clear_subscription_dashboard_hide(sub: Subscription) -> None:
    if getattr(sub, "hidden_from_dashboard", False):
        sub.hidden_from_dashboard = False


def client_connection_ips(panel, email: str) -> dict[str, Any]:
    raw: list[dict[str, Any]] = []
    try:
        raw = panel.get_client_ips(email)
    except Exception:
        raw = []
    connected_ips: list[dict[str, Any]] = []
    seen: set[str] = set()
    for item in raw:
        ip = str(item.get("ip") or "").strip()
        if not ip or ip in seen:
            continue
        seen.add(ip)
        connected_ips.append(
            {
                "ip": ip,
                "at": item.get("time"),
                "node": (str(item.get("node") or "").strip() or None),
            }
        )
    limit_ip = 0
    try:
        client = panel.get_client(email)
        limit_ip = int(client.get("limitIp") or 0)
    except Exception:
        pass
    return {
        "connected_ip_count": len(connected_ips),
        "limit_ip": limit_ip,
        "connected_ips": connected_ips,
        "ip_available": True,
    }


def subscription_live_stats(
    panel,
    sub: Subscription,
    *,
    online_emails: set[str] | None = None,
    last_map: dict[str, int] | None = None,
) -> dict[str, Any]:
    from app.panel import XUIPanel

    traffic: dict[str, Any] = {}
    try:
        traffic = panel.get_traffic(sub.xui_email)
    except Exception:
        traffic = {}
    up = int(traffic.get("up") or 0)
    down = int(traffic.get("down") or 0)
    used = up + down
    total = int(traffic.get("total") or 0)
    if (
        total <= 0
        and sub.plan
        and sub.plan.traffic_gb > 0
        and not is_metered_payg(sub)
        and not is_payg_subscription(sub)
    ):
        total = int(sub.plan.traffic_gb) * 1024 * 1024 * 1024
    panel_enable = traffic.get("enable")
    enabled = bool(panel_enable) if panel_enable is not None else bool(sub.enabled)
    last_ms = int(traffic.get("lastOnline") or (last_map or {}).get(sub.xui_email) or 0)
    if online_emails is None:
        try:
            online_emails = panel.online_emails()
        except Exception:
            online_emails = set()
    is_online = sub.xui_email in online_emails
    now = datetime.utcnow()
    expired = bool(sub.expires_at and sub.expires_at <= now)
    status = "online" if is_online else ("expired" if expired else ("disabled" if not enabled else "offline"))
    remaining_bytes = max(0, total - used) if total > 0 else None
    remaining_days = None
    if sub.expires_at:
        delta = sub.expires_at - now
        remaining_days = max(0, delta.days)
    return {
        "enabled": enabled,
        "online": is_online,
        "status": status,
        "up_bytes": up,
        "down_bytes": down,
        "used_bytes": used,
        "total_bytes": total,
        "used_label": format_bytes(used),
        "total_label": "نامحدود" if total <= 0 else format_bytes(total),
        "remaining_bytes": remaining_bytes,
        "remaining_label": "نامحدود" if remaining_bytes is None else format_bytes(remaining_bytes),
        "usage_percent": round(min(100.0, (used / total) * 100), 1) if total > 0 else 0.0,
        "last_online_ms": last_ms,
        "last_online_at": datetime.utcfromtimestamp(last_ms / 1000).isoformat() if last_ms > 0 else None,
        "remaining_days": remaining_days,
        "expired": expired,
    }


def format_bytes(num: int) -> str:
    n = float(max(0, int(num or 0)))
    units = ["B", "KB", "MB", "GB", "TB"]
    idx = 0
    while n >= 1024 and idx < len(units) - 1:
        n /= 1024
        idx += 1
    if idx == 0:
        return f"{int(n)} {units[idx]}"
    return f"{n:.1f} {units[idx]}"


def relative_time_fa(at: datetime | None) -> str | None:
    if not at:
        return None
    now = datetime.utcnow()
    seconds = max(0, int((now - at).total_seconds()))
    if seconds < 45:
        return "همین الان"
    if seconds < 3600:
        return f"{seconds // 60} دقیقه پیش"
    if seconds < 86400:
        return f"{seconds // 3600} ساعت پیش"
    days = seconds // 86400
    if days == 1:
        return "دیروز"
    return f"{days} روز پیش"


def record_usage_sample(
    session: Session,
    sub: Subscription,
    *,
    up_bytes: int,
    down_bytes: int,
    used_bytes: int,
    online: bool,
    min_interval_sec: int = 600,
) -> UsageSample | None:
    last = session.scalar(
        select(UsageSample)
        .where(UsageSample.subscription_id == sub.id)
        .order_by(UsageSample.recorded_at.desc())
        .limit(1)
    )
    now = datetime.utcnow()
    if last and last.recorded_at:
        age = (now - last.recorded_at).total_seconds()
        delta = abs(int(used_bytes) - int(last.used_bytes or 0))
        if age < min_interval_sec and delta < 256 * 1024 and bool(last.online) == bool(online):
            return None
    sample = UsageSample(
        subscription_id=sub.id,
        up_bytes=int(up_bytes),
        down_bytes=int(down_bytes),
        used_bytes=int(used_bytes),
        online=bool(online),
        recorded_at=now,
    )
    session.add(sample)
    return sample


def prune_usage_samples(session: Session, keep_days: int = 30) -> None:
    cutoff = datetime.utcnow() - timedelta(days=keep_days)
    session.execute(delete(UsageSample).where(UsageSample.recorded_at < cutoff))


def sample_stale_subscriptions(session: Session, panel, *, min_interval_sec: int = 900, limit: int = 40) -> None:
    cutoff = datetime.utcnow() - timedelta(seconds=min_interval_sec)
    # Snapshot ids first so we don't hold a long read while hammering the panel.
    sub_rows = list(
        session.execute(
            select(Subscription.id, Subscription.xui_email).order_by(Subscription.id.asc())
        ).all()
    )
    online: set[str] = set()
    try:
        online = panel.online_emails()
    except Exception:
        online = set()
    sampled = 0
    for sub_id, xui_email in sub_rows:
        if sampled >= limit:
            break
        last = session.scalar(
            select(UsageSample)
            .where(UsageSample.subscription_id == sub_id)
            .order_by(UsageSample.recorded_at.desc())
            .limit(1)
        )
        if last and last.recorded_at and last.recorded_at > cutoff:
            continue
        try:
            traffic = panel.get_traffic(xui_email)
        except Exception:
            continue
        sub = session.get(Subscription, sub_id)
        if not sub:
            continue
        up = int(traffic.get("up") or 0)
        down = int(traffic.get("down") or 0)
        try:
            record_usage_sample(
                session,
                sub,
                up_bytes=up,
                down_bytes=down,
                used_bytes=up + down,
                online=xui_email in online,
                min_interval_sec=min_interval_sec,
            )
            session.commit()
        except Exception:
            session.rollback()
            logger.exception("usage sample commit failed for %s", xui_email)
            continue
        sampled += 1
    try:
        prune_usage_samples(session)
        session.commit()
    except Exception:
        session.rollback()
        logger.exception("usage sample prune failed")


def _usage_day_buckets(
    samples: list[UsageSample],
    *,
    current_up: int,
    current_down: int,
    current_used: int,
    days: int = 7,
) -> list[dict[str, Any]]:
    now = datetime.utcnow()
    today = now.date()
    buckets = {
        today - timedelta(days=i): {"up": 0, "down": 0, "used": 0}
        for i in range(days)
    }
    points: list[tuple[datetime, int, int, int]] = [
        (s.recorded_at, int(s.up_bytes or 0), int(s.down_bytes or 0), int(s.used_bytes or 0))
        for s in samples
        if s.recorded_at
    ]
    points.append((now, current_up, current_down, current_used))
    points.sort(key=lambda p: p[0])
    for i in range(1, len(points)):
        _prev_at, prev_up, prev_down, prev_used = points[i - 1]
        at, up, down, used = points[i]
        day = at.date()
        if day not in buckets:
            continue
        d_used = used - prev_used
        d_up = up - prev_up
        d_down = down - prev_down
        if d_used < 0:
            d_used, d_up, d_down = used, up, down
        buckets[day]["used"] += max(0, d_used)
        buckets[day]["up"] += max(0, d_up)
        buckets[day]["down"] += max(0, d_down)
    out = []
    for i in range(days - 1, -1, -1):
        day = today - timedelta(days=i)
        row = buckets[day]
        out.append(
            {
                "day": day.isoformat(),
                "label": f"{day.month}/{day.day}",
                "used_bytes": row["used"],
                "up_bytes": row["up"],
                "down_bytes": row["down"],
                "used_label": format_bytes(row["used"]),
            }
        )
    return out


def subscription_usage_analytics(
    session: Session,
    sub: Subscription,
    *,
    up_bytes: int,
    down_bytes: int,
    used_bytes: int,
    total_bytes: int,
    last_online_at: datetime | None,
) -> dict[str, Any]:
    since = datetime.utcnow() - timedelta(days=8)
    samples = list(
        session.scalars(
            select(UsageSample)
            .where(UsageSample.subscription_id == sub.id, UsageSample.recorded_at >= since)
            .order_by(UsageSample.recorded_at.asc())
        ).all()
    )
    daily = _usage_day_buckets(
        samples,
        current_up=up_bytes,
        current_down=down_bytes,
        current_used=used_bytes,
    )
    today_bytes = daily[-1]["used_bytes"] if daily else 0
    week_bytes = sum(d["used_bytes"] for d in daily)
    active_days = sum(1 for d in daily if d["used_bytes"] > 0)
    avg_daily = week_bytes // max(1, active_days or len(daily) or 1)
    remaining = max(0, total_bytes - used_bytes) if total_bytes > 0 else None
    days_left = None
    if remaining is not None and avg_daily > 0:
        days_left = remaining // avg_daily
    peak = max(daily, key=lambda d: d["used_bytes"]) if daily else None
    return {
        "today_bytes": today_bytes,
        "today_label": format_bytes(today_bytes),
        "week_bytes": week_bytes,
        "week_label": format_bytes(week_bytes),
        "avg_daily_bytes": avg_daily,
        "avg_daily_label": format_bytes(avg_daily),
        "days_left": days_left,
        "peak_day": peak["label"] if peak and peak["used_bytes"] > 0 else None,
        "peak_label": peak["used_label"] if peak and peak["used_bytes"] > 0 else None,
        "daily": daily,
        "sparkline": [d["used_bytes"] for d in daily],
        "last_seen_label": relative_time_fa(last_online_at),
        "remaining_bytes": remaining,
        "remaining_label": "نامحدود" if remaining is None else format_bytes(remaining),
    }


def user_active_subscriptions(session: Session, user_id: int) -> list[Subscription]:
    now = datetime.utcnow()
    rows = list(
        session.scalars(
            select(Subscription)
            .where(Subscription.user_id == user_id, Subscription.enabled.is_(True))
            .options(selectinload(Subscription.plan), selectinload(Subscription.order))
            .order_by(Subscription.id.desc())
        ).all()
    )
    return [s for s in rows if s.expires_at is None or s.expires_at > now]


def get_setting(session: Session, key: str, default: str = "") -> str:
    row = session.get(ShopSetting, key)
    return row.value if row else default


def set_setting(session: Session, key: str, value: str) -> None:
    row = session.get(ShopSetting, key)
    if row is None:
        session.add(ShopSetting(key=key, value=value))
    else:
        row.value = value
    session.commit()


def birthday_gift_amount(session: Session) -> int:
    raw = get_setting(session, BIRTHDAY_GIFT_SETTING, str(DEFAULT_BIRTHDAY_GIFT))
    try:
        return max(0, int(raw))
    except ValueError:
        return DEFAULT_BIRTHDAY_GIFT


def birthday_gift_enabled(session: Session) -> bool:
    return get_setting(session, BIRTHDAY_GIFT_ENABLED_SETTING, DEFAULT_BIRTHDAY_GIFT_ENABLED) == "1"


def birthday_gift_settings_dict(session: Session) -> dict[str, Any]:
    amount = birthday_gift_amount(session)
    return {
        "enabled": birthday_gift_enabled(session),
        "amount_toman": amount,
        "amount_label": format_price(amount),
    }


def _days_until_birthday(birth_date: date, today: date | None = None) -> int:
    today = today or date.today()
    try:
        next_bday = date(today.year, birth_date.month, birth_date.day)
    except ValueError:
        # Feb 29 → Mar 1 on non-leap years
        next_bday = date(today.year, birth_date.month, min(birth_date.day, 28))
    if next_bday < today:
        try:
            next_bday = date(today.year + 1, birth_date.month, birth_date.day)
        except ValueError:
            next_bday = date(today.year + 1, birth_date.month, min(birth_date.day, 28))
    return (next_bday - today).days


def _format_birth_date_label(birth_date: date, year_hidden: bool = False) -> str:
    if year_hidden:
        return birth_date.strftime("%m/%d")
    return birth_date.strftime("%Y/%m/%d")


def user_profile_dict(session: Session, user: User) -> dict[str, Any]:
    today = date.today()
    birth_date = user.birth_date
    year_hidden = bool(getattr(user, "birth_date_year_hidden", False))
    is_birthday_today = False
    days_until: int | None = None
    if birth_date:
        is_birthday_today = (birth_date.month, birth_date.day) == (today.month, today.day)
        days_until = _days_until_birthday(birth_date, today)
    email = (getattr(user, "email", None) or "").strip() or None
    phone = (getattr(user, "phone", None) or "").strip() or None
    return {
        "telegram_id": user.telegram_id,
        "username": user.username,
        "full_name": user.full_name,
        "has_photo": bool(getattr(user, "photo_file_id", None)),
        "email": email,
        "phone": phone,
        "has_email": bool(email),
        "has_phone": bool(phone),
        "birth_date": None if (not birth_date or year_hidden) else birth_date.isoformat(),
        "birth_date_label": _format_birth_date_label(birth_date, year_hidden) if birth_date else None,
        "birth_date_source": getattr(user, "birth_date_source", None),
        "birth_date_year_hidden": year_hidden,
        "has_birth_date": bool(birth_date),
        "needs_birth_date": not bool(birth_date),
        "is_birthday_today": is_birthday_today,
        "days_until_birthday": days_until,
        "birthday_gift_received_year": None,
        "birthday_gift_amount_toman": 0,
        "birthday_gift_amount_label": None,
        "member_since": user.created_at.isoformat() if user.created_at else None,
    }


def set_user_birth_date(
    session: Session,
    user: User,
    birth_date: date,
    *,
    source: str = "manual",
    year_hidden: bool = False,
) -> None:
    today = date.today()
    if birth_date > today:
        raise ValueError("future_date")
    if not year_hidden:
        age = today.year - birth_date.year - (
            (today.month, today.day) < (birth_date.month, birth_date.day)
        )
        if age < 10:
            raise ValueError("too_young")
        if age > 120:
            raise ValueError("invalid_date")
    user.birth_date = birth_date
    user.birth_date_source = source
    user.birth_date_year_hidden = year_hidden
    session.commit()
    session.refresh(user)


def set_user_contact(
    session: Session,
    user: User,
    *,
    email: str | None = None,
    phone: str | None = None,
) -> None:
    import re

    if email is not None:
        cleaned = email.strip()
        if cleaned and not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", cleaned):
            raise ValueError("invalid_email")
        user.email = cleaned or None
    if phone is not None:
        cleaned = re.sub(r"[\s\-()]", "", phone.strip())
        if cleaned and not re.fullmatch(r"\+?[0-9]{8,15}", cleaned):
            raise ValueError("invalid_phone")
        user.phone = cleaned or None
    session.commit()
    session.refresh(user)


def sync_user_telegram_profile(session: Session, user: User, settings: Any) -> User:
    """Pull public Telegram photo and birthdate when the user has not filled them."""
    from app.tg_http import telegram_user_birthdate, telegram_user_photo_file_id

    changed = False
    if not getattr(user, "photo_file_id", None):
        try:
            file_id = telegram_user_photo_file_id(settings, user.telegram_id)
            if file_id:
                user.photo_file_id = file_id
                changed = True
        except Exception:
            logger.exception("telegram photo sync failed user=%s", user.telegram_id)

    if not user.birth_date:
        try:
            raw = telegram_user_birthdate(settings, user.telegram_id)
        except Exception:
            logger.exception("telegram birthdate sync failed user=%s", user.telegram_id)
            raw = None
        if isinstance(raw, dict):
            try:
                day = int(raw.get("day") or 0)
                month = int(raw.get("month") or 0)
                year_raw = raw.get("year")
            except (TypeError, ValueError):
                day = month = 0
                year_raw = None
            if 1 <= day <= 31 and 1 <= month <= 12:
                year_hidden = not year_raw
                year = int(year_raw) if year_raw else 2000
                try:
                    imported = date(year, month, day)
                except ValueError:
                    imported = None
                if imported and imported <= date.today():
                    user.birth_date = imported
                    user.birth_date_source = "telegram"
                    user.birth_date_year_hidden = year_hidden
                    changed = True
    if changed:
        session.commit()
        session.refresh(user)
    return user


def maybe_grant_birthday_gift(session: Session, user: User) -> dict[str, Any] | None:
    """Credit a silent, non-withdrawable wallet lock when enabled. Never announce it."""
    if not birthday_gift_enabled(session):
        return None
    if not user.birth_date:
        return None
    today = date.today()
    if (user.birth_date.month, user.birth_date.day) != (today.month, today.day):
        return None
    year = today.year
    if user.birthday_gift_year == year:
        return None
    amount = birthday_gift_amount(session)
    if amount <= 0:
        return None
    user.wallet_balance = (user.wallet_balance or 0) + amount
    user.wallet_locked_toman = wallet_locked_amount(user) + amount
    user.birthday_gift_year = year
    session.commit()
    session.refresh(user)
    return None


def trial_enabled(session: Session) -> bool:
    return get_setting(session, TRIAL_ENABLED_SETTING, DEFAULT_TRIAL_ENABLED) == "1"


def _trial_int_setting(session: Session, key: str, default: int) -> int:
    raw = get_setting(session, key, str(default))
    try:
        return max(0, int(raw))
    except ValueError:
        return default


def trial_send_links_enabled(session: Session) -> bool:
    return get_setting(session, TRIAL_SEND_LINKS_SETTING, "0") == "1"


def trial_settings_dict(session: Session) -> dict[str, Any]:
    duration = _trial_int_setting(session, TRIAL_DURATION_DAYS_SETTING, DEFAULT_TRIAL_DURATION_DAYS)
    traffic = _trial_int_setting(session, TRIAL_TRAFFIC_GB_SETTING, DEFAULT_TRIAL_TRAFFIC_GB)
    limit_ip = _trial_int_setting(session, TRIAL_LIMIT_IP_SETTING, DEFAULT_TRIAL_LIMIT_IP)
    return {
        "enabled": trial_enabled(session),
        "duration_days": duration,
        "traffic_gb": traffic,
        "limit_ip": limit_ip,
        "traffic_label": traffic_label(traffic),
        "send_links": trial_send_links_enabled(session),
    }


def get_trial_plan(session: Session) -> Plan | None:
    return session.scalar(select(Plan).where(Plan.code == TRIAL_PLAN_CODE))


def create_standalone_subscription(
    session: Session,
    *,
    user: User,
    plan: Plan,
    xui_email: str,
    xui_uuid: str | None,
    xui_sub_id: str | None,
    duration_days: int,
    label: str | None = None,
) -> Subscription:
    expires_at = None
    if duration_days > 0:
        expires_at = datetime.utcnow() + timedelta(days=duration_days)
    sub = Subscription(
        user_id=user.id,
        order_id=None,
        plan_id=plan.id,
        xui_email=xui_email,
        xui_uuid=xui_uuid,
        xui_sub_id=xui_sub_id,
        label=label or "حساب تست",
        enabled=True,
        expires_at=expires_at,
    )
    session.add(sub)
    session.commit()
    session.refresh(sub)
    return sub


def _trial_provision_params(
    session: Session,
    plan: Plan,
    *,
    duration_days: int | None = None,
    traffic_gb: int | None = None,
    limit_ip: int | None = None,
) -> tuple[int, int, int]:
    cfg = trial_settings_dict(session)
    duration = duration_days if duration_days is not None else (cfg["duration_days"] or plan.duration_days)
    traffic = traffic_gb if traffic_gb is not None else (cfg["traffic_gb"] if cfg["traffic_gb"] >= 0 else plan.traffic_gb)
    ip_limit = limit_ip if limit_ip is not None else (cfg["limit_ip"] or plan.limit_ip)
    return max(1, int(duration)), max(0, int(traffic)), max(1, int(ip_limit))


def _trial_result_dict(
    sub: Subscription,
    *,
    email: str,
    links: list[str],
    duration: int,
    traffic: int,
    settings=None,
    message: str | None = None,
) -> dict[str, Any]:
    traffic_text = traffic_label(traffic)
    return {
        "granted": True,
        "subscription_id": sub.id,
        "email": email,
        "links": links,
        "subscription_url": build_subscription_url(sub.xui_sub_id, settings) if settings else None,
        "duration_days": duration,
        "traffic_label": traffic_text,
        "expires_at": sub.expires_at.isoformat() if sub.expires_at else None,
        "message": message
        or (
            f"🎁 کانفیگ تست فعال شد — {duration} روز · {traffic_text}. "
            f"برای دیدن لینک، مینی‌اپ را باز کنید."
        ),
    }


def provision_trial_vpn(
    session: Session,
    user: User,
    panel: XUIPanel,
    settings,
    *,
    duration_days: int | None = None,
    traffic_gb: int | None = None,
    limit_ip: int | None = None,
    label: str = "حساب تست",
    comment: str = "trial",
    mark_trial_granted: bool = False,
) -> dict[str, Any]:
    plan = get_trial_plan(session)
    if not plan:
        raise ValueError("trial_plan_missing")

    duration, traffic, ip_limit = _trial_provision_params(
        session,
        plan,
        duration_days=duration_days,
        traffic_gb=traffic_gb,
        limit_ip=limit_ip,
    )

    email = f"trial{user.telegram_id}-{secrets.token_hex(2)}"
    client = panel.create_client(
        email=email,
        duration_days=duration,
        traffic_gb=traffic,
        limit_ip=ip_limit,
        tg_id=user.telegram_id,
        comment=comment,
    )
    links = public_links_for_email(panel, email, settings, name=label)
    sub = create_standalone_subscription(
        session,
        user=user,
        plan=plan,
        xui_email=email,
        xui_uuid=client.get("uuid") or client.get("id"),
        xui_sub_id=client.get("subId") or client.get("sub_id"),
        duration_days=duration,
        label=label,
    )
    if mark_trial_granted:
        user.trial_granted = True
        session.commit()
        session.refresh(user)
    return _trial_result_dict(
        sub, email=email, links=links, duration=duration, traffic=traffic, settings=settings
    )


def user_has_trial_subscription(session: Session, user_id: int) -> bool:
    plan = get_trial_plan(session)
    if not plan:
        return False
    count = session.scalar(
        select(func.count())
        .select_from(Subscription)
        .where(Subscription.user_id == user_id, Subscription.plan_id == plan.id)
    )
    return bool(count and int(count) > 0)


def resolve_trial_target_users(session: Session, targets: list[str]) -> tuple[list[User], list[str]]:
    """Resolve telegram IDs / usernames to users. Returns (found, not_found tokens)."""
    found: dict[int, User] = {}
    missing: list[str] = []

    for raw in targets:
        token = (raw or "").strip()
        if not token:
            continue
        if token.startswith("@"):
            token = token[1:]
        user: User | None = None
        if token.isdigit():
            user = session.scalar(select(User).where(User.telegram_id == int(token)))
        else:
            user = session.scalar(
                select(User).where(func.lower(User.username) == token.lower())
            )
        if user:
            found[user.id] = user
        else:
            missing.append(raw.strip())

    return list(found.values()), missing


def grant_trial_to_users(
    session: Session,
    users: list[User],
    panel: XUIPanel,
    settings,
    *,
    skip_existing_trial: bool = True,
    duration_days: int | None = None,
    traffic_gb: int | None = None,
    limit_ip: int | None = None,
    notify: bool = False,
) -> dict[str, Any]:
    granted: list[dict[str, Any]] = []
    skipped: list[dict[str, Any]] = []
    failed: list[dict[str, Any]] = []

    for user in users:
        ident = user.username or str(user.telegram_id)
        if skip_existing_trial and user_has_trial_subscription(session, user.id):
            skipped.append(
                {
                    "telegram_id": user.telegram_id,
                    "username": user.username,
                    "reason": "already_has_trial",
                }
            )
            continue
        try:
            result = provision_trial_vpn(
                session,
                user,
                panel,
                settings,
                duration_days=duration_days,
                traffic_gb=traffic_gb,
                limit_ip=limit_ip,
                comment="trial-admin-grant",
                mark_trial_granted=False,
            )
            entry = {
                "telegram_id": user.telegram_id,
                "username": user.username,
                "email": result["email"],
                "links": result["links"],
                "message": result["message"],
            }
            granted.append(entry)
            if notify:
                _notify_trial_granted(
                    settings,
                    user.telegram_id,
                    links=result.get("links") or [],
                    email=result.get("email") or "",
                    send_links=trial_send_links_enabled(session),
                    subscription_url=result.get("subscription_url"),
                )
        except PanelError as exc:
            logger.exception("Admin trial grant failed for %s: %s", ident, exc)
            failed.append(
                {
                    "telegram_id": user.telegram_id,
                    "username": user.username,
                    "error": str(exc),
                }
            )
        except Exception as exc:  # noqa: BLE001
            logger.exception("Admin trial grant failed for %s: %s", ident, exc)
            failed.append(
                {
                    "telegram_id": user.telegram_id,
                    "username": user.username,
                    "error": str(exc),
                }
            )

    return {
        "ok": True,
        "granted_count": len(granted),
        "skipped_count": len(skipped),
        "failed_count": len(failed),
        "granted": granted,
        "skipped": skipped,
        "failed": failed,
    }


def _miniapp_reply_markup(settings) -> dict[str, Any] | None:
    url = (getattr(settings, "miniapp_url_normalized", None) or getattr(settings, "miniapp_url", "") or "").strip()
    if url and not url.endswith("/"):
        url += "/"
    if not url:
        return None
    return {"inline_keyboard": [[{"text": "باز کردن مینی‌اپ", "web_app": {"url": url}}]]}


def _notify_trial_granted(
    settings,
    telegram_id: int,
    links: list[str] | None = None,
    email: str = "",
    *,
    send_links: bool = False,
    subscription_url: str | None = None,
) -> None:
    from app.texts import subscription_link_message, trial_activated_text
    from app.tg_http import send_telegram_message

    extra: dict[str, Any] = {"disable_web_page_preview": True}
    markup = _miniapp_reply_markup(settings)
    if markup:
        extra["reply_markup"] = markup
    send_telegram_message(settings, telegram_id, trial_activated_text(), extra=extra)
    if send_links:
        send_telegram_message(
            settings,
            telegram_id,
            subscription_link_message(
                email=email,
                sub_url=subscription_url or (links[0] if links else None),
                title="🎁 لینک اشتراک تست",
            ),
            extra={"disable_web_page_preview": True},
        )


def _sync_trial_granted_flag(session: Session, user: User) -> None:
    if user.trial_granted:
        return
    if user_has_trial_subscription(session, user.id):
        user.trial_granted = True
        session.commit()
        return
    existing_subs = session.scalar(
        select(func.count()).select_from(Subscription).where(Subscription.user_id == user.id)
    )
    if existing_subs and int(existing_subs) > 0:
        user.trial_granted = True
        session.commit()


def trial_claim_block_reason(session: Session, user: User) -> str | None:
    _sync_trial_granted_flag(session, user)
    if not trial_enabled(session):
        return "trial_disabled"
    if user.trial_granted or user_has_trial_subscription(session, user.id):
        return "already_granted"
    existing_subs = session.scalar(
        select(func.count()).select_from(Subscription).where(Subscription.user_id == user.id)
    )
    if existing_subs and int(existing_subs) > 0:
        return "already_has_config"
    return None


def trial_offer_dict(session: Session, user: User) -> dict[str, Any]:
    cfg = trial_settings_dict(session)
    reason = trial_claim_block_reason(session, user)
    return {
        "available": reason is None,
        "reason": reason,
        "duration_days": cfg["duration_days"],
        "traffic_gb": cfg["traffic_gb"],
        "traffic_label": cfg["traffic_label"],
        "limit_ip": cfg["limit_ip"],
    }


def claim_user_trial(
    session: Session,
    user: User,
    panel: XUIPanel,
    settings,
    *,
    notify: bool = False,
) -> dict[str, Any]:
    reason = trial_claim_block_reason(session, user)
    if reason:
        raise ValueError(reason)
    result = provision_trial_vpn(
        session,
        user,
        panel,
        settings,
        comment="trial-user-claim",
        mark_trial_granted=True,
    )
    if notify:
        _notify_trial_granted(
            settings,
            user.telegram_id,
            links=result.get("links") or [],
            email=result.get("email") or "",
            send_links=trial_send_links_enabled(session),
            subscription_url=result.get("subscription_url"),
        )
    return result


def maybe_grant_trial(
    session: Session,
    user: User,
    panel: XUIPanel,
    settings,
    *,
    is_new: bool = True,
    notify: bool = False,
) -> dict[str, Any] | None:
    """Legacy auto-grant helper. Shop now uses explicit claim_user_trial."""
    if trial_claim_block_reason(session, user):
        return None
    try:
        return claim_user_trial(session, user, panel, settings, notify=notify)
    except Exception as exc:
        logger.exception("Trial provisioning failed for user %s: %s", user.telegram_id, exc)
        try:
            session.rollback()
        except Exception:
            pass
        return None


PAYMENT_CARDS_KEY = "payment_cards"


def _legacy_payment_card(session: Session, settings) -> dict[str, Any]:
    return {
        "id": 1,
        "card": get_setting(session, "payment_card", settings.payment_card),
        "name": get_setting(session, "payment_card_name", settings.payment_card_name),
        "note": get_setting(session, "payment_note", settings.payment_note),
        "label": "کارت اصلی",
    }


def list_payment_cards(session: Session, settings) -> list[dict[str, Any]]:
    raw = get_setting(session, PAYMENT_CARDS_KEY, "")
    if raw:
        try:
            data = json.loads(raw)
            if isinstance(data, list) and data:
                out: list[dict[str, Any]] = []
                for i, item in enumerate(data):
                    if not isinstance(item, dict):
                        continue
                    card = str(item.get("card") or "").strip()
                    if not card:
                        continue
                    out.append(
                        {
                            "id": int(item.get("id") or i + 1),
                            "card": card,
                            "name": str(item.get("name") or "").strip(),
                            "note": str(item.get("note") or "").strip(),
                            "label": str(item.get("label") or "").strip() or f"کارت {i + 1}",
                        }
                    )
                if out:
                    return out
        except (json.JSONDecodeError, TypeError, ValueError):
            pass
    legacy = _legacy_payment_card(session, settings)
    if legacy["card"]:
        return [legacy]
    return []


def _save_payment_cards(session: Session, cards: list[dict[str, Any]]) -> None:
    set_setting(session, PAYMENT_CARDS_KEY, json.dumps(cards, ensure_ascii=False))
    if cards:
        primary = cards[0]
        set_setting(session, "payment_card", primary["card"])
        set_setting(session, "payment_card_name", primary.get("name") or "")
        set_setting(session, "payment_note", primary.get("note") or "")


def add_payment_card(
    session: Session,
    settings,
    *,
    card: str,
    name: str = "",
    note: str = "",
    label: str = "",
) -> dict[str, Any]:
    cards = list_payment_cards(session, settings)
    next_id = max((int(c["id"]) for c in cards), default=0) + 1
    entry = {
        "id": next_id,
        "card": card.strip(),
        "name": name.strip(),
        "note": note.strip(),
        "label": label.strip() or f"کارت {len(cards) + 1}",
    }
    cards.append(entry)
    _save_payment_cards(session, cards)
    return entry


def remove_payment_card(session: Session, settings, card_id: int) -> bool:
    cards = list_payment_cards(session, settings)
    new_cards = [c for c in cards if int(c["id"]) != int(card_id)]
    if len(new_cards) == len(cards):
        return False
    _save_payment_cards(session, new_cards)
    return True


def payment_info(session: Session, settings) -> dict[str, Any]:
    cards = list_payment_cards(session, settings)
    primary = cards[0] if cards else _legacy_payment_card(session, settings)
    note = primary.get("note") or get_setting(session, "payment_note", settings.payment_note)
    return {
        "card": primary.get("card") or "",
        "name": primary.get("name") or "",
        "note": note,
        "cards": cards,
    }


def referral_percent(session: Session) -> int:
    raw = get_setting(session, "referral_percent", str(DEFAULT_REFERRAL_PERCENT))
    try:
        return max(0, min(100, int(raw)))
    except ValueError:
        return DEFAULT_REFERRAL_PERCENT


def min_withdraw_amount(session: Session) -> int:
    raw = get_setting(session, "min_withdraw", str(DEFAULT_MIN_WITHDRAW))
    try:
        return max(0, int(raw))
    except ValueError:
        return DEFAULT_MIN_WITHDRAW


def attach_subscription(
    session: Session,
    *,
    user: User,
    order: Order,
    plan: Plan,
    xui_email: str,
    xui_uuid: str | None,
    xui_sub_id: str | None,
    duration_days: int | None = None,
    label: str | None = None,
    family_group: str | None = None,
    family_index: int | None = None,
    family_role: str | None = None,
    finalize_order: bool = True,
) -> Subscription:
    expires_at = None
    days = duration_days if duration_days is not None else plan.duration_days
    if days > 0:
        expires_at = datetime.utcnow() + timedelta(days=days)
    customer = customer_meta_dict(order)
    chosen = (getattr(order, "config_label", None) or "").strip()
    default_label = (label or chosen or customer.get("customer_name") or plan.title or "").strip() or None
    sub = Subscription(
        user_id=user.id,
        order_id=order.id,
        plan_id=plan.id,
        xui_email=xui_email,
        xui_uuid=xui_uuid,
        xui_sub_id=xui_sub_id,
        label=default_label,
        enabled=True,
        is_payg=is_payg_order(order) or is_payg_plan(plan),
        expires_at=expires_at,
        family_group=family_group,
        family_index=family_index,
        family_role=family_role,
        customer_name=customer.get("customer_name"),
        customer_email=customer.get("customer_email"),
        customer_phone=customer.get("customer_phone"),
        customer_telegram_id=customer.get("customer_telegram_id"),
    )
    session.add(sub)
    if finalize_order:
        order.status = OrderStatus.APPROVED
        order.reviewed_at = datetime.utcnow()
    session.commit()
    session.refresh(sub)
    return sub


def set_subscription_customer(
    session: Session,
    sub: Subscription,
    *,
    customer_name: str | None = None,
    customer_email: str | None = None,
    customer_phone: str | None = None,
    customer_telegram_id: str | None = None,
) -> Subscription:
    apply_customer_meta(
        sub,
        normalize_customer_meta(
            customer_name=customer_name,
            customer_email=customer_email,
            customer_phone=customer_phone,
            customer_telegram_id=customer_telegram_id,
        ),
    )
    session.commit()
    session.refresh(sub)
    return sub


def credit_referral_commission(session: Session, order: Order) -> Commission | None:
    """Credit referrer wallet when an order is approved. Commission on full plan price."""
    if is_wallet_topup(order.plan):
        return None
    existing = session.scalar(select(Commission).where(Commission.order_id == order.id))
    if existing:
        return None
    buyer = order.user
    if not buyer.referred_by_id:
        return None
    referrer = session.get(User, buyer.referred_by_id)
    if not referrer:
        return None
    percent = referral_percent(session)
    if percent <= 0:
        return None
    base = order.amount_toman + (order.wallet_used or 0)
    amount = (base * percent) // 100
    if amount <= 0:
        return None
    referrer.wallet_balance = (referrer.wallet_balance or 0) + amount
    commission = Commission(
        referrer_id=referrer.id,
        referred_id=buyer.id,
        order_id=order.id,
        percent=percent,
        amount_toman=amount,
    )
    session.add(commission)
    session.commit()
    session.refresh(commission)
    return commission


def _refund_order_wallet(order: Order) -> None:
    if not order.wallet_used:
        return
    user = order.user
    refund_wallet_spend(user, order.wallet_used, getattr(order, "wallet_locked_used", 0) or 0)
    order.wallet_used = 0
    order.wallet_locked_used = 0


def reject_order(session: Session, order: Order, note: str = "") -> None:
    _refund_order_wallet(order)
    order.status = OrderStatus.REJECTED
    order.admin_note = note
    order.reviewed_at = datetime.utcnow()
    session.commit()


def cancel_order(session: Session, order: Order, note: str = "cancelled_by_user") -> None:
    """Cancel a pending order and refund any wallet applied."""
    if order.status != OrderStatus.PENDING:
        return
    _refund_order_wallet(order)
    order.status = OrderStatus.CANCELLED
    order.admin_note = note
    order.reviewed_at = datetime.utcnow()
    session.commit()


def referral_stats(session: Session, user: User) -> dict:
    invited = session.scalar(
        select(func.count()).select_from(User).where(User.referred_by_id == user.id)
    ) or 0
    earned = session.scalar(
        select(func.coalesce(func.sum(Commission.amount_toman), 0)).where(
            Commission.referrer_id == user.id
        )
    ) or 0
    paid_refs = session.scalar(
        select(func.count()).select_from(Commission).where(Commission.referrer_id == user.id)
    ) or 0
    return {
        "invited": int(invited),
        "paid_referrals": int(paid_refs),
        "earned_total": int(earned),
        "wallet": int(user.wallet_balance or 0),
        "withdrawable": wallet_withdrawable(user),
        "percent": referral_percent(session),
        "min_withdraw": min_withdraw_amount(session),
        "code": ensure_referral_code(session, user),
    }


def list_referral_invitees(session: Session, referrer: User, *, limit: int = 50) -> list[dict]:
    referred_users = list(
        session.scalars(
            select(User)
            .where(User.referred_by_id == referrer.id)
            .order_by(User.created_at.desc())
            .limit(max(1, min(limit, 100)))
        ).all()
    )
    if not referred_users:
        return []
    referred_ids = [u.id for u in referred_users]
    orders = list(
        session.scalars(
            select(Order)
            .where(Order.user_id.in_(referred_ids), Order.status == OrderStatus.APPROVED)
            .options(selectinload(Order.plan))
        ).all()
    )
    commissions = list(
        session.scalars(
            select(Commission).where(
                Commission.referrer_id == referrer.id,
                Commission.referred_id.in_(referred_ids),
            )
        ).all()
    )
    vpn_totals: dict[int, int] = {}
    vpn_counts: dict[int, int] = {}
    for order in orders:
        if not is_vpn_plan(order.plan):
            continue
        uid = order.user_id
        amount = order.amount_toman + (order.wallet_used or 0)
        vpn_totals[uid] = vpn_totals.get(uid, 0) + amount
        vpn_counts[uid] = vpn_counts.get(uid, 0) + 1
    commission_by_user: dict[int, int] = {}
    for row in commissions:
        commission_by_user[row.referred_id] = commission_by_user.get(row.referred_id, 0) + row.amount_toman

    out: list[dict] = []
    for u in referred_users:
        vpn_total = int(vpn_totals.get(u.id, 0))
        commission = int(commission_by_user.get(u.id, 0))
        out.append(
            {
                "full_name": u.full_name,
                "username": u.username,
                "joined_at": u.created_at.isoformat() if u.created_at else None,
                "vpn_purchase_count": int(vpn_counts.get(u.id, 0)),
                "vpn_purchase_total": vpn_total,
                "vpn_purchase_label": format_price(vpn_total) if vpn_total else "—",
                "commission_earned": commission,
                "commission_label": format_price(commission) if commission else "—",
                "has_purchased": vpn_total > 0,
            }
        )
    return out


def create_withdrawal(session: Session, user: User, amount: int, card_number: str) -> Withdrawal | None:
    min_w = min_withdraw_amount(session)
    amount = int(amount)
    if amount < min_w:
        return None
    if wallet_withdrawable(user) < amount:
        return None
    pending = session.scalar(
        select(Withdrawal).where(
            Withdrawal.user_id == user.id,
            Withdrawal.status == WithdrawStatus.PENDING,
        )
    )
    if pending:
        return None
    user.wallet_balance -= amount
    wd = Withdrawal(
        user_id=user.id,
        amount_toman=amount,
        card_number=card_number.strip(),
        status=WithdrawStatus.PENDING,
    )
    session.add(wd)
    session.commit()
    session.refresh(wd)
    return wd


def list_pending_withdrawals(session: Session, *, include_test: bool = False) -> list[Withdrawal]:
    rows = list(
        session.scalars(
            select(Withdrawal)
            .where(Withdrawal.status == WithdrawStatus.PENDING)
            .options(selectinload(Withdrawal.user))
            .order_by(Withdrawal.id.desc())
        ).all()
    )
    if include_test:
        return rows
    return [w for w in rows if w.user and not bool(getattr(w.user, "is_test", False))]


def approve_withdrawal(session: Session, wd: Withdrawal) -> None:
    wd.status = WithdrawStatus.PAID
    wd.reviewed_at = datetime.utcnow()
    session.commit()


def reject_withdrawal(session: Session, wd: Withdrawal, note: str = "") -> None:
    user = wd.user
    user.wallet_balance = (user.wallet_balance or 0) + wd.amount_toman
    wd.status = WithdrawStatus.REJECTED
    wd.admin_note = note
    wd.reviewed_at = datetime.utcnow()
    session.commit()


def format_price(toman: int) -> str:
    n = int(toman or 0)
    if n < 0:
        return "−" + f"{abs(n):,}".replace(",", "٬") + " تومان"
    return f"{n:,}".replace(",", "٬") + " تومان"


def wallet_credit_limit_of(user: User) -> int:
    return max(0, int(getattr(user, "wallet_credit_limit", 0) or 0))


def wallet_debt_of(user: User) -> int:
    return max(0, -int(user.wallet_balance or 0))


def wallet_spendable(user: User) -> int:
    """How much can still be charged to wallet (cash + remaining credit)."""
    return int(user.wallet_balance or 0) + wallet_credit_limit_of(user)


def set_user_wallet_credit_limit(session: Session, user: User, limit_toman: int) -> User:
    limit = max(0, min(50_000_000, int(limit_toman)))
    debt = wallet_debt_of(user)
    if debt > limit:
        raise ValueError("debt_exceeds_limit")
    user.wallet_credit_limit = limit
    session.commit()
    session.refresh(user)
    return user


def wallet_locked_amount(user: User) -> int:
    return max(0, int(getattr(user, "wallet_locked_toman", 0) or 0))


def clamp_wallet_locked(user: User) -> int:
    locked = min(wallet_locked_amount(user), max(0, int(user.wallet_balance or 0)))
    user.wallet_locked_toman = locked
    return locked


def wallet_withdrawable(user: User) -> int:
    return max(0, int(user.wallet_balance or 0) - wallet_locked_amount(user))


def wallet_view(user: User) -> dict[str, int]:
    balance = int(user.wallet_balance or 0)
    credit_limit = wallet_credit_limit_of(user)
    debt = max(0, -balance)
    locked = min(wallet_locked_amount(user), max(0, balance))
    spendable = balance + credit_limit
    return {
        "balance": balance,
        "locked": locked,
        "withdrawable": max(0, balance - locked),
        "credit_limit": credit_limit,
        "debt": debt,
        "spendable": max(0, spendable),
        "credit_remaining": max(0, credit_limit - debt),
    }


def spend_wallet(user: User, amount: int) -> tuple[int, int]:
    """Spend wallet on a shop charge. Uses locked gift first, then cash, then credit line."""
    want = max(0, int(amount))
    spend = min(max(0, wallet_spendable(user)), want)
    balance = int(user.wallet_balance or 0)
    positive = max(0, balance)
    locked = min(wallet_locked_amount(user), positive)
    locked_used = min(locked, min(spend, positive))
    user.wallet_balance = balance - spend
    user.wallet_locked_toman = locked - locked_used
    return spend, locked_used


def refund_wallet_spend(user: User, wallet_used: int, locked_used: int = 0) -> None:
    used = max(0, int(wallet_used or 0))
    locked = max(0, int(locked_used or 0))
    if used:
        user.wallet_balance = (user.wallet_balance or 0) + used
    if locked:
        user.wallet_locked_toman = wallet_locked_amount(user) + locked
    clamp_wallet_locked(user)


def traffic_label(gb: int) -> str:
    return "نامحدود" if gb <= 0 else f"{gb} گیگ"


CHAT_PAGE_SIZE = 100
MAX_CHAT_ATTACHMENTS = 3


def _parse_attachments_json(raw: str | None) -> list[dict]:
    if not raw:
        return []
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return []
    return data if isinstance(data, list) else []


def _link_preview(link: str, max_len: int = 52) -> str:
    if len(link) <= max_len:
        return link
    return link[: max_len - 1] + "…"


def _subscription_status(sub: Subscription) -> str:
    if not sub.enabled:
        return "disabled"
    if sub.expires_at and sub.expires_at <= datetime.utcnow():
        return "expired"
    return "active"


def list_user_orders_for_chat(session: Session, user_id: int, limit: int = 40) -> list[Order]:
    return list(
        session.scalars(
            select(Order)
            .where(Order.user_id == user_id)
            .options(selectinload(Order.plan))
            .order_by(Order.id.desc())
            .limit(limit)
        ).all()
    )


def order_status_label(status: str) -> str:
    labels = {
        OrderStatus.PENDING: "در انتظار",
        OrderStatus.APPROVED: "تایید شده",
        OrderStatus.REJECTED: "رد شده",
        OrderStatus.CANCELLED: "لغو شده",
    }
    return labels.get(status, status)


def order_chat_dict(order: Order, *, include_user: bool = False) -> dict:
    plan = order.plan
    topup = is_wallet_topup(plan)
    pro = is_platform_pro(plan)
    if topup:
        kind = "wallet_topup"
        kind_label = "شارژ کیف‌پول"
    elif pro:
        kind = "platform_pro"
        kind_label = "اشتراک Pro"
    elif is_payg_order(order):
        kind = "payg"
        kind_label = "پرداخت مصرفی"
    else:
        kind = "vpn_purchase"
        kind_label = "خرید VPN"
    wallet_used = order.wallet_used or 0
    data = {
        "id": order.id,
        "plan_title": order_plan_title(order),
        "kind": kind,
        "kind_label": kind_label,
        "amount_toman": order.amount_toman,
        "amount_label": format_price(order.amount_toman),
        "wallet_used": wallet_used,
        "wallet_used_label": format_price(wallet_used) if wallet_used else None,
        "status": order.status,
        "status_label": order_status_label(order.status),
        "has_receipt": bool(order.receipt_file_id),
        "created_at": order.created_at.isoformat() if order.created_at else None,
        "reviewed_at": order.reviewed_at.isoformat() if order.reviewed_at else None,
        "admin_note": order.admin_note,
        "is_platform_pro": pro,
        "is_wallet_topup": topup,
    }
    if include_user and order.user:
        data["user"] = order.user.full_name or "—"
        data["telegram_id"] = order.user.telegram_id
        data["username"] = order.user.username
    return data


def list_orders_history(
    session: Session,
    *,
    user_id: int | None = None,
    status: str | None = None,
    q: str | None = None,
    limit: int = 40,
    offset: int = 0,
    include_user: bool = False,
) -> tuple[list[dict], int]:
    from sqlalchemy import func

    filters = []
    if user_id is not None:
        filters.append(Order.user_id == user_id)
    if status:
        filters.append(Order.status == status.strip().lower())
    query = (q or "").strip()
    if query:
        if query.isdigit():
            num = int(query)
            if num > 1_000_000:
                user = session.scalar(select(User).where(User.telegram_id == num))
                if user:
                    filters.append(Order.user_id == user.id)
                else:
                    filters.append(Order.id == -1)
            else:
                filters.append(Order.id == num)
        elif query.startswith("@"):
            user = session.scalar(
                select(User).where(func.lower(User.username) == query[1:].lower())
            )
            if user:
                filters.append(Order.user_id == user.id)
            else:
                filters.append(Order.id == -1)
        else:
            like = f"%{query}%"
            user_ids = list(
                session.scalars(
                    select(User.id).where(
                        func.lower(User.username).like(like.lower())
                        | func.lower(User.full_name).like(like.lower())
                    )
                ).all()
            )
            filters.append(Order.user_id.in_(user_ids) if user_ids else Order.id == -1)

    total = session.scalar(select(func.count()).select_from(Order).where(*filters)) or 0
    rows = list(
        session.scalars(
            select(Order)
            .where(*filters)
            .options(selectinload(Order.plan), selectinload(Order.user))
            .order_by(Order.id.desc())
            .offset(max(0, offset))
            .limit(max(1, min(limit, 100)))
        ).all()
    )
    return [order_chat_dict(o, include_user=include_user) for o in rows], int(total)


def _order_snapshot(order: Order) -> dict:
    base = order_chat_dict(order)
    return {
        "order_id": base["id"],
        "plan_title": base["plan_title"],
        "kind": base["kind"],
        "kind_label": base["kind_label"],
        "amount_toman": base["amount_toman"],
        "amount_label": base["amount_label"],
        "wallet_used": base["wallet_used"],
        "wallet_used_label": base["wallet_used_label"],
        "status": base["status"],
        "status_label": base["status_label"],
        "has_receipt": base["has_receipt"],
        "created_at": base["created_at"],
    }


def _subscription_snapshot(sub: Subscription) -> dict:
    return {
        "subscription_id": sub.id,
        "email": sub.xui_email,
        "label": sub.label,
        "plan_title": sub.plan.title if sub.plan else "—",
        "status": _subscription_status(sub),
    }


def resolve_chat_attachments(
    session: Session,
    owner_user_id: int,
    items: list[dict],
    panel: XUIPanel,
    settings,
) -> list[dict]:
    if len(items) > MAX_CHAT_ATTACHMENTS:
        raise ValueError("too_many_attachments")
    resolved: list[dict] = []
    seen: set[tuple] = set()
    for item in items:
        att_type = item.get("type")
        if att_type == "order":
            order_id = item.get("order_id")
            if not isinstance(order_id, int) or order_id <= 0:
                raise ValueError("invalid_attachment")
            key = ("order", order_id)
            if key in seen:
                continue
            seen.add(key)
            order = session.get(Order, order_id)
            if not order or order.user_id != owner_user_id:
                raise ValueError("invalid_order")
            resolved.append({"type": "order", **_order_snapshot(order)})
            continue
        sub_id = item.get("subscription_id")
        if att_type not in ("subscription", "link") or not isinstance(sub_id, int) or sub_id <= 0:
            raise ValueError("invalid_attachment")
        sub = session.get(Subscription, sub_id)
        if not sub or sub.user_id != owner_user_id:
            raise ValueError("invalid_subscription")
        key = (att_type, sub_id, item.get("link_index") if att_type == "link" else None)
        if key in seen:
            continue
        seen.add(key)
        snap = _subscription_snapshot(sub)
        if att_type == "subscription":
            resolved.append({"type": "subscription", **snap})
            continue
        link_index = item.get("link_index")
        if not isinstance(link_index, int) or link_index < 0:
            raise ValueError("invalid_link")
        try:
            links = public_links_for_subscription(panel, sub, settings)
        except PanelError as exc:
            raise ValueError("link_fetch_failed") from exc
        if link_index >= len(links):
            raise ValueError("invalid_link")
        link = links[link_index]
        resolved.append(
            {
                "type": "link",
                **snap,
                "link_index": link_index,
                "link": link,
                "link_preview": _link_preview(link),
            }
        )
    return resolved


def chat_message_dict(m: ChatMessage) -> dict:
    return {
        "id": m.id,
        "user_id": m.user_id,
        "sender": m.sender,
        "body": m.body,
        "attachments": _parse_attachments_json(m.attachments_json),
        "created_at": m.created_at.isoformat() if m.created_at else None,
        "read_at": m.read_at.isoformat() if m.read_at else None,
    }


def chat_preview_text(body: str, attachments: list[dict]) -> str:
    text = (body or "").strip()
    if attachments:
        parts = []
        for att in attachments[:2]:
            if att.get("type") == "order":
                kind = att.get("kind_label") or "فاکتور"
                parts.append(f"🧾 {kind} #{att.get('order_id', '')}")
            elif att.get("type") == "link":
                label = att.get("label") or att.get("email") or "اشتراک"
                parts.append(f"🔗 لینک {label}")
            else:
                label = att.get("label") or att.get("email") or "اشتراک"
                parts.append(f"📎 {label}")
        extra = f" (+{len(attachments) - 2})" if len(attachments) > 2 else ""
        attach_line = " · ".join(parts) + extra
        if text:
            return f"{text}\n{attach_line}"
        return attach_line
    return text


def latest_chat_message_id(session: Session, user_id: int) -> int:
    return session.scalar(
        select(func.max(ChatMessage.id)).where(ChatMessage.user_id == user_id)
    ) or 0


def list_user_chat_messages(
    session: Session,
    user_id: int,
    after_id: int = 0,
    limit: int = CHAT_PAGE_SIZE,
) -> list[ChatMessage]:
    if after_id > 0:
        return list(
            session.scalars(
                select(ChatMessage)
                .where(ChatMessage.user_id == user_id, ChatMessage.id > after_id)
                .order_by(ChatMessage.id.asc())
            ).all()
        )
    recent_ids = list(
        session.scalars(
            select(ChatMessage.id)
            .where(ChatMessage.user_id == user_id)
            .order_by(ChatMessage.id.desc())
            .limit(limit)
        ).all()
    )
    if not recent_ids:
        return []
    return list(
        session.scalars(
            select(ChatMessage)
            .where(ChatMessage.id.in_(recent_ids))
            .order_by(ChatMessage.id.asc())
        ).all()
    )


def user_chat_unread_count(session: Session, user_id: int) -> int:
    return session.scalar(
        select(func.count())
        .select_from(ChatMessage)
        .where(
            ChatMessage.user_id == user_id,
            ChatMessage.sender == "admin",
            ChatMessage.read_at.is_(None),
        )
    ) or 0


def admin_chat_unread_total(session: Session) -> int:
    return session.scalar(
        select(func.count())
        .select_from(ChatMessage)
        .where(ChatMessage.sender == "user", ChatMessage.read_at.is_(None))
    ) or 0


def mark_chat_read(session: Session, user_id: int, reader: str) -> int:
    """Mark messages from the other party as read. Returns rows updated."""
    other = "admin" if reader == "user" else "user"
    now = datetime.utcnow()
    result = session.execute(
        update(ChatMessage)
        .where(
            ChatMessage.user_id == user_id,
            ChatMessage.sender == other,
            ChatMessage.read_at.is_(None),
        )
        .values(read_at=now)
    )
    count = result.rowcount or 0
    if count:
        session.commit()
    return count


def send_chat_message(
    session: Session,
    *,
    user_id: int,
    sender: str,
    body: str,
    sender_telegram_id: int | None = None,
    attachments: list[dict] | None = None,
) -> ChatMessage:
    text = (body or "").strip()
    att_list = attachments or []
    if not text and not att_list:
        raise ValueError("empty_message")
    if len(text) > 4000:
        raise ValueError("message_too_long")
    msg = ChatMessage(
        user_id=user_id,
        sender=sender,
        sender_telegram_id=sender_telegram_id,
        body=text,
        attachments_json=json.dumps(att_list, ensure_ascii=False) if att_list else None,
    )
    session.add(msg)
    session.commit()
    session.refresh(msg)
    return msg


def list_chat_threads(session: Session) -> list[dict]:
    """Admin inbox: one row per user with recent chat activity."""
    last_per_user = (
        select(
            ChatMessage.user_id,
            func.max(ChatMessage.id).label("last_id"),
        )
        .group_by(ChatMessage.user_id)
        .subquery()
    )
    unread = (
        select(
            ChatMessage.user_id,
            func.count().label("unread_count"),
        )
        .where(ChatMessage.sender == "user", ChatMessage.read_at.is_(None))
        .group_by(ChatMessage.user_id)
        .subquery()
    )
    last_msg = aliased(ChatMessage)
    rows = session.execute(
        select(User, last_msg, func.coalesce(unread.c.unread_count, 0))
        .join(last_per_user, User.id == last_per_user.c.user_id)
        .join(last_msg, last_msg.id == last_per_user.c.last_id)
        .outerjoin(unread, User.id == unread.c.user_id)
        .order_by(last_msg.created_at.desc())
    ).all()
    return [
        {
            "user_id": user.id,
            "telegram_id": user.telegram_id,
            "username": user.username,
            "full_name": user.full_name,
            "last_message": chat_preview_text(msg.body if msg else "", _parse_attachments_json(msg.attachments_json if msg else None)),
            "last_message_at": msg.created_at.isoformat() if msg and msg.created_at else None,
            "last_sender": msg.sender if msg else None,
            "unread_count": int(unread_count or 0),
        }
        for user, msg, unread_count in rows
    ]
