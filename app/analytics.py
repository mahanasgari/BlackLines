from __future__ import annotations

from collections import defaultdict
from datetime import datetime, timedelta
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.orm import Session, selectinload

from app.models import (
    ChatMessage,
    Commission,
    Order,
    OrderStatus,
    Plan,
    Subscription,
    UsageSample,
    User,
    WithdrawStatus,
    Withdrawal,
)
from app.services import (
    CUSTOM_PLAN_CODE,
    PAYG_PLAN_CODE,
    PLATFORM_PRO_CODE,
    TRIAL_PLAN_CODE,
    USER_ROLE_ADMIN,
    WALLET_TOPUP_CODE,
    admin_user_overview,
    format_price,
    is_custom_order,
    is_metered_payg,
    is_payg_order,
    is_platform_pro,
    is_user_pro,
    is_wallet_topup,
)


def _money(toman: int) -> dict[str, Any]:
    value = int(toman or 0)
    return {"toman": value, "label": format_price(value)}


def _pct(part: int, whole: int) -> int:
    if whole <= 0:
        return 0
    return int(round(100 * part / whole))


def _period_start(days: int) -> datetime | None:
    days = int(days or 0)
    if days <= 0:
        return None
    now = datetime.utcnow()
    if days == 1:
        return datetime(now.year, now.month, now.day)
    return now - timedelta(days=days)


def _in_period(value: datetime | None, since: datetime | None) -> bool:
    if since is None:
        return True
    if value is None:
        return False
    return value >= since


def _order_when(order: Order) -> datetime | None:
    return order.reviewed_at or order.created_at


def _daily_buckets(days: int) -> list[str]:
    span = days if days > 0 else 30
    span = max(1, min(span, 90))
    today = datetime.utcnow().date()
    return [(today - timedelta(days=span - 1 - i)).isoformat() for i in range(span)]


def _fill_daily(keys: list[str], counts: dict[str, int], amounts: dict[str, int] | None = None) -> list[dict[str, Any]]:
    out = []
    for key in keys:
        item: dict[str, Any] = {
            "date": key,
            "label": f"{int(key[5:7])}/{int(key[8:10])}",
            "count": int(counts.get(key, 0)),
        }
        if amounts is not None:
            item["toman"] = int(amounts.get(key, 0))
            item["label_money"] = format_price(item["toman"])
        out.append(item)
    return out


def _order_kind(order: Order) -> tuple[str, str]:
    plan = order.plan
    if is_wallet_topup(plan):
        return "wallet_topup", "شارژ کیف‌پول"
    if is_platform_pro(plan):
        return "platform_pro", "اشتراک Pro"
    if is_payg_order(order):
        if (order.amount_toman or 0) + (order.wallet_used or 0) <= 0:
            return "payg_metered", "فعال‌سازی ابری"
        return "payg_prepaid", "حجم مصرفی"
    if is_custom_order(order) or (plan and plan.code == CUSTOM_PLAN_CODE):
        return "custom", "پکیج سفارشی"
    if order.target_subscription_id:
        return "renew", "تمدید VPN"
    return "vpn", "خرید VPN"


def test_user_ids(session: Session) -> set[int]:
    return set(session.scalars(select(User.id).where(User.is_test.is_(True))).all())


def admin_analytics(session: Session, *, days: int = 30, include_test: bool = False) -> dict[str, Any]:
    days = int(days or 0)
    if days not in (0, 1, 7, 30):
        days = 30
    since = _period_start(days)
    now = datetime.utcnow()
    keys = _daily_buckets(days if days > 0 else 30)
    period_label = {0: "از ابتدا", 1: "امروز", 7: "۷ روز", 30: "۳۰ روز"}[days]
    skip = set() if include_test else test_user_ids(session)
    return {
        "days": days,
        "period_label": period_label,
        "include_test": include_test,
        "hidden_test_users": 0 if include_test else len(skip),
        "compare": _compare_block(session, days, skip),
        "users": _users_analytics(session, since, now, keys, skip),
        "finance": _finance_analytics(session, since, now, keys, skip),
    }


def _users_analytics(
    session: Session,
    since: datetime | None,
    now: datetime,
    keys: list[str],
    skip_ids: set[int] | None = None,
) -> dict[str, Any]:
    skip_ids = skip_ids or set()
    users = [u for u in session.scalars(select(User)).all() if u.id not in skip_ids]
    total = len(users)
    new_users = [u for u in users if _in_period(u.created_at, since)]
    referred = sum(1 for u in users if u.referred_by_id)
    pro = sum(1 for u in users if is_user_pro(u))
    admins = sum(1 for u in users if (u.role or "") == USER_ROLE_ADMIN)
    with_wallet = sum(1 for u in users if (u.wallet_balance or 0) > 0)
    trial_granted = sum(1 for u in users if u.trial_granted)
    signup_counts: dict[str, int] = defaultdict(int)
    for u in users:
        if u.created_at:
            signup_counts[u.created_at.date().isoformat()] += 1

    subs = [
        s
        for s in session.scalars(select(Subscription).options(selectinload(Subscription.plan))).all()
        if s.user_id not in skip_ids
    ]
    active_user_ids: set[int] = set()
    cfg = {
        "total": 0,
        "active": 0,
        "expired": 0,
        "disabled": 0,
        "trial": 0,
        "metered": 0,
        "prepaid": 0,
        "regular": 0,
        "new": 0,
    }
    for sub in subs:
        cfg["total"] += 1
        if _in_period(sub.created_at, since):
            cfg["new"] += 1
        enabled = bool(sub.enabled)
        expired = bool(sub.expires_at and sub.expires_at <= now)
        if not enabled:
            cfg["disabled"] += 1
        elif expired:
            cfg["expired"] += 1
        else:
            cfg["active"] += 1
            active_user_ids.add(sub.user_id)
        code = sub.plan.code if sub.plan else ""
        if code == TRIAL_PLAN_CODE:
            cfg["trial"] += 1
        elif sub.payg_metered:
            cfg["metered"] += 1
        elif sub.is_payg or code == PAYG_PLAN_CODE:
            cfg["prepaid"] += 1
        else:
            cfg["regular"] += 1

    horizon = now + timedelta(days=3)
    expiring_user_ids: set[int] = set()
    for sub in subs:
        if not sub.enabled or not sub.expires_at:
            continue
        if is_metered_payg(sub):
            continue
        if now < sub.expires_at <= horizon:
            expiring_user_ids.add(sub.user_id)

    paying_user_ids = {
        uid
        for uid in session.scalars(
            select(Order.user_id)
            .join(Plan)
            .where(Order.status == OrderStatus.APPROVED, Plan.code != WALLET_TOPUP_CODE)
            .distinct()
        ).all()
        if uid not in skip_ids
    }
    converted_trial = sum(1 for u in users if u.trial_granted and u.id in paying_user_ids)

    day_ago = now - timedelta(hours=24)
    live_filters = [UsageSample.recorded_at >= day_ago, UsageSample.used_bytes > 0]
    online_filters = [UsageSample.recorded_at >= now - timedelta(minutes=20), UsageSample.online.is_(True)]
    if skip_ids:
        owned = select(Subscription.id).where(~Subscription.user_id.in_(skip_ids))
        live_filters.append(UsageSample.subscription_id.in_(owned))
        online_filters.append(UsageSample.subscription_id.in_(owned))
    active_usage = int(
        session.scalar(select(func.count(func.distinct(UsageSample.subscription_id))).where(*live_filters)) or 0
    )
    online_now = int(
        session.scalar(select(func.count(func.distinct(UsageSample.subscription_id))).where(*online_filters)) or 0
    )

    chat_q = select(ChatMessage)
    if since:
        chat_q = chat_q.where(ChatMessage.created_at >= since)
    chat_rows = [m for m in session.scalars(chat_q).all() if m.user_id not in skip_ids]
    chat_user = sum(1 for m in chat_rows if m.sender == "user")
    chat_admin = sum(1 for m in chat_rows if m.sender == "admin")
    unread_filters = [ChatMessage.sender == "user", ChatMessage.read_at.is_(None)]
    if skip_ids:
        unread_filters.append(~ChatMessage.user_id.in_(skip_ids))
    unread = int(session.scalar(select(func.count()).select_from(ChatMessage).where(*unread_filters)) or 0)

    order_filters = []
    if since:
        order_filters.append(Order.created_at >= since)
    if skip_ids:
        order_filters.append(~Order.user_id.in_(skip_ids))
    orders_new = int(
        session.scalar(select(func.count()).select_from(Order).where(*order_filters)) or 0
    )
    pending_filters = [Order.status == OrderStatus.PENDING]
    if skip_ids:
        pending_filters.append(~Order.user_id.in_(skip_ids))
    pending_orders = int(
        session.scalar(select(func.count()).select_from(Order).where(*pending_filters)) or 0
    )

    return {
        "kpis": {
            "total_users": total,
            "new_users": len(new_users),
            "paying_users": len(paying_user_ids),
            "active_customers": len(active_user_ids),
            "pro_users": pro,
            "referred_users": referred,
            "admins": admins,
            "with_wallet": with_wallet,
            "trial_granted": trial_granted,
            "trial_converted": converted_trial,
            "expiring": len(expiring_user_ids),
        },
        "signups": _fill_daily(keys, signup_counts),
        "funnel": [
            {"key": "registered", "title": "ثبت‌نام", "count": total},
            {"key": "config", "title": "دارای کانفیگ", "count": len(active_user_ids)},
            {"key": "paying", "title": "خرید کرده", "count": len(paying_user_ids)},
            {"key": "pro", "title": "Pro", "count": pro},
        ],
        "configs": {
            **cfg,
            "active_share": _pct(cfg["active"], cfg["total"]),
        },
        "activity": {
            "online_now": online_now,
            "used_24h": active_usage,
            "orders_new": orders_new,
            "pending_orders": pending_orders,
            "chat_total": len(chat_rows),
            "chat_from_users": chat_user,
            "chat_from_admins": chat_admin,
            "chat_unread": unread,
        },
    }


def _finance_analytics(
    session: Session,
    since: datetime | None,
    now: datetime,
    keys: list[str],
    skip_ids: set[int] | None = None,
) -> dict[str, Any]:
    skip_ids = skip_ids or set()
    orders = [
        o
        for o in session.scalars(select(Order).options(selectinload(Order.plan))).all()
        if o.user_id not in skip_ids
    ]
    approved = [o for o in orders if o.status == OrderStatus.APPROVED]
    period_approved = [o for o in approved if _in_period(_order_when(o), since)]
    pending = [o for o in orders if o.status == OrderStatus.PENDING]

    cash_in = 0
    wallet_spent = 0
    topups = 0
    product = 0
    by_kind: dict[str, dict[str, Any]] = {}
    by_plan: dict[str, dict[str, Any]] = defaultdict(lambda: {"title": "", "count": 0, "toman": 0})
    daily_cash: dict[str, int] = defaultdict(int)
    daily_product: dict[str, int] = defaultdict(int)
    daily_count: dict[str, int] = defaultdict(int)

    kind_titles = {
        "vpn": "خرید VPN",
        "renew": "تمدید VPN",
        "custom": "پکیج سفارشی",
        "payg_prepaid": "حجم مصرفی",
        "payg_metered": "فعال‌سازی ابری",
        "platform_pro": "اشتراک Pro",
        "wallet_topup": "شارژ کیف‌پول",
    }

    for order in period_approved:
        card = int(order.amount_toman or 0)
        wallet = int(order.wallet_used or 0)
        gross = card + wallet
        kind, title = _order_kind(order)
        cash_in += card
        wallet_spent += wallet
        if kind == "wallet_topup":
            topups += card
        elif kind != "payg_metered":
            product += gross
        bucket = by_kind.setdefault(
            kind, {"key": kind, "title": title, "count": 0, "card": 0, "wallet": 0, "toman": 0}
        )
        bucket["count"] += 1
        bucket["card"] += card
        bucket["wallet"] += wallet
        bucket["toman"] += gross if kind != "wallet_topup" else card
        if kind not in ("wallet_topup", "payg_metered"):
            plan_title = (order.plan.title if order.plan else None) or title
            if kind == "custom":
                plan_title = "پکیج سفارشی"
            row = by_plan[plan_title]
            row["title"] = plan_title
            row["count"] += 1
            row["toman"] += gross
        when = _order_when(order)
        if when:
            day = when.date().isoformat()
            daily_cash[day] += card
            if kind not in ("wallet_topup", "payg_metered"):
                daily_product[day] += gross
            daily_count[day] += 1

    metered_q = select(func.coalesce(func.sum(Subscription.billed_toman), 0))
    if skip_ids:
        metered_q = metered_q.where(~Subscription.user_id.in_(skip_ids))
    metered_billed = int(session.scalar(metered_q) or 0)
    product_with_metered = product + metered_billed

    commissions = [
        c
        for c in session.scalars(select(Commission)).all()
        if c.referrer_id not in skip_ids and c.referred_id not in skip_ids
    ]
    commission_period = [c for c in commissions if _in_period(c.created_at, since)]
    commission_sum = sum(int(c.amount_toman or 0) for c in commission_period)

    withdrawals = [w for w in session.scalars(select(Withdrawal)).all() if w.user_id not in skip_ids]
    wd_paid = sum(
        int(w.amount_toman or 0)
        for w in withdrawals
        if w.status == WithdrawStatus.PAID and _in_period(w.reviewed_at or w.created_at, since)
    )
    wd_pending = sum(int(w.amount_toman or 0) for w in withdrawals if w.status == WithdrawStatus.PENDING)
    pending_card = sum(int(o.amount_toman or 0) for o in pending)

    wallet_q = select(func.coalesce(func.sum(User.wallet_balance), 0))
    if skip_ids:
        wallet_q = wallet_q.where(~User.id.in_(skip_ids))
    wallet_liability = int(session.scalar(wallet_q) or 0)
    net_cash = cash_in - wd_paid
    estimate_owned = cash_in - wd_paid - wallet_liability

    kind_rows = []
    for key, title in kind_titles.items():
        row = by_kind.get(key) or {"key": key, "title": title, "count": 0, "card": 0, "wallet": 0, "toman": 0}
        kind_rows.append(
            {
                **row,
                "card_label": format_price(row["card"]),
                "wallet_label": format_price(row["wallet"]),
                "label": format_price(row["toman"]),
                "share": _pct(row["toman"], product_with_metered if key != "wallet_topup" else cash_in),
            }
        )

    plan_rows = sorted(by_plan.values(), key=lambda r: r["toman"], reverse=True)
    plan_out = [
        {**r, "label": format_price(r["toman"]), "share": _pct(r["toman"], product)}
        for r in plan_rows
        if r["toman"] > 0 or r["count"] > 0
    ]

    return {
        "kpis": {
            "cash_in": _money(cash_in),
            "product_revenue": _money(product_with_metered),
            "wallet_topups": _money(topups),
            "wallet_spent": _money(wallet_spent),
            "metered_billed": _money(metered_billed),
            "commissions": _money(commission_sum),
            "withdrawals_paid": _money(wd_paid),
            "withdrawals_pending": _money(wd_pending),
            "pending_orders": _money(pending_card),
            "wallet_liability": _money(wallet_liability),
            "net_cash": _money(net_cash),
            "estimate_owned": _money(estimate_owned),
            "order_count": len(period_approved),
        },
        "kinds": kind_rows,
        "plans": plan_out[:12],
        "daily": _fill_daily(keys, daily_count, daily_product),
        "daily_cash": _fill_daily(keys, daily_count, daily_cash),
        "notes": {
            "cash": "پولی که واقعاً به کارت واریز شده (رسید تاییدشده).",
            "product": "ارزش فروش محصول؛ ممکن است بخشی از کیف‌پول پرداخت شده باشد.",
            "wallet": "شارژ کیف‌پول فروش نیست — بدهی به کاربر است تا خرج شود.",
            "metered": "مصرف ابری از کیف‌پول کم می‌شود؛ رقم کل تا این لحظه است.",
            "owned": "برآورد خالص ≈ واریز کارت − برداشت‌های پرداخت‌شده − مانده کیف‌پول کاربران.",
        },
        "pending_order_count": len(pending),
        "generated_at": now.isoformat(),
    }


SLICE_TITLES: dict[str, str] = {
    "all": "همه کاربران",
    "new": "کاربران جدید",
    "paying": "خرید کرده‌اند",
    "paying_period": "خرید در این بازه",
    "active": "کانفیگ فعال",
    "has_config": "دارای کانفیگ",
    "pro": "کاربران Pro",
    "referred": "دعوت‌شده",
    "admins": "ادمین‌ها",
    "wallet": "کیف‌پول دارند",
    "trial": "تست گرفته",
    "trial_converted": "تبدیل تست به خرید",
    "expired": "کانفیگ منقضی",
    "disabled": "کانفیگ قطع",
    "expiring": "در حال انقضا",
    "unread": "پیام خوانده‌نشده",
    "pending": "سفارش باز",
    "issues": "نیازمند رسیدگی",
    "online": "آنلاین الان",
    "used_24h": "مصرف ۲۴ ساعت",
    "trial_config": "حساب تست",
    "payg": "ابری / حجم",
}


def _delta_row(current: int, previous: int, *, money: bool = False) -> dict[str, Any]:
    delta = int(current) - int(previous)
    if previous == 0:
        pct = 100 if current > 0 else 0
    else:
        pct = int(round(100 * delta / previous))
    row: dict[str, Any] = {
        "current": int(current),
        "previous": int(previous),
        "delta": delta,
        "delta_pct": pct,
    }
    if money:
        sign = "+" if delta > 0 else ""
        row["current_label"] = format_price(int(current))
        row["previous_label"] = format_price(int(previous))
        row["delta_label"] = f"{sign}{format_price(delta)}" if delta else format_price(0)
    return row


def _window_metrics(session: Session, start: datetime, end: datetime, skip_ids: set[int]) -> dict[str, int]:
    users = [u for u in session.scalars(select(User)).all() if u.id not in skip_ids]
    new_users = sum(1 for u in users if u.created_at and start <= u.created_at < end)
    trial_ids = {u.id for u in users if u.trial_granted}
    first_pay: dict[int, datetime] = {}
    cash_in = 0
    orders = list(session.scalars(select(Order).options(selectinload(Order.plan))).all())
    for order in orders:
        if order.user_id in skip_ids or order.status != OrderStatus.APPROVED:
            continue
        when = _order_when(order)
        if when is None:
            continue
        kind, _title = _order_kind(order)
        if start <= when < end:
            cash_in += int(order.amount_toman or 0)
        if kind in ("wallet_topup", "payg_metered"):
            continue
        prev = first_pay.get(order.user_id)
        if prev is None or when < prev:
            first_pay[order.user_id] = when
    trial_converted = sum(
        1 for uid, when in first_pay.items() if uid in trial_ids and start <= when < end
    )
    return {"new_users": new_users, "cash_in": cash_in, "trial_converted": trial_converted}


def _compare_block(session: Session, days: int, skip_ids: set[int]) -> dict[str, Any]:
    now = datetime.utcnow()
    span = 30 if days <= 0 else days
    if days == 1:
        cur_start = datetime(now.year, now.month, now.day)
        prev_start = cur_start - timedelta(days=1)
        cur_end = now
        prev_end = cur_start
        label = "امروز نسبت به دیروز"
    else:
        cur_start = now - timedelta(days=span)
        cur_end = now
        prev_start = cur_start - timedelta(days=span)
        prev_end = cur_start
        if days == 7:
            label = "۷ روز اخیر نسبت به ۷ روز قبل"
        elif days <= 0:
            label = "۳۰ روز اخیر نسبت به ۳۰ روز قبل"
        else:
            label = "۳۰ روز اخیر نسبت به ۳۰ روز قبل"
    current = _window_metrics(session, cur_start, cur_end, skip_ids)
    previous = _window_metrics(session, prev_start, prev_end, skip_ids)
    return {
        "label": label,
        "new_users": _delta_row(current["new_users"], previous["new_users"]),
        "cash_in": _delta_row(current["cash_in"], previous["cash_in"], money=True),
        "trial_converted": _delta_row(current["trial_converted"], previous["trial_converted"]),
    }


def _paying_user_ids(session: Session, skip_ids: set[int], since: datetime | None = None) -> set[int]:
    stmt = (
        select(Order.user_id)
        .join(Plan)
        .where(Order.status == OrderStatus.APPROVED, Plan.code != WALLET_TOPUP_CODE)
        .distinct()
    )
    ids = {uid for uid in session.scalars(stmt).all() if uid not in skip_ids}
    if since is None:
        return ids
    out: set[int] = set()
    orders = list(session.scalars(select(Order).options(selectinload(Order.plan))).all())
    for order in orders:
        if order.user_id in skip_ids or order.status != OrderStatus.APPROVED:
            continue
        if order.user_id not in ids:
            continue
        kind, _title = _order_kind(order)
        if kind in ("wallet_topup", "payg_metered"):
            continue
        if _in_period(_order_when(order), since):
            out.add(order.user_id)
    return out


def user_ids_for_admin_slice(
    session: Session,
    key: str,
    since: datetime | None,
    now: datetime,
    skip_ids: set[int],
) -> set[int] | None:
    key = (key or "").strip()
    if not key or key == "all":
        return None
    users = [u for u in session.scalars(select(User)).all() if u.id not in skip_ids]
    user_ids = {u.id for u in users}
    subs = [
        s
        for s in session.scalars(select(Subscription).options(selectinload(Subscription.plan))).all()
        if s.user_id not in skip_ids
    ]

    def from_usage(*, hours: float | None = None, minutes: float | None = None, online: bool = False) -> set[int]:
        if minutes is not None:
            start = now - timedelta(minutes=minutes)
        else:
            start = now - timedelta(hours=hours or 24)
        filters = [UsageSample.recorded_at >= start]
        if online:
            filters.append(UsageSample.online.is_(True))
        else:
            filters.append(UsageSample.used_bytes > 0)
        sub_ids = set(session.scalars(select(UsageSample.subscription_id).where(*filters).distinct()).all())
        if not sub_ids:
            return set()
        return {
            s.user_id
            for s in session.scalars(select(Subscription).where(Subscription.id.in_(sub_ids))).all()
            if s.user_id not in skip_ids
        }

    if key == "new":
        return {u.id for u in users if _in_period(u.created_at, since)}
    if key == "paying":
        return _paying_user_ids(session, skip_ids)
    if key == "paying_period":
        return _paying_user_ids(session, skip_ids, since)
    if key == "pro":
        return {u.id for u in users if is_user_pro(u)}
    if key == "referred":
        return {u.id for u in users if u.referred_by_id}
    if key == "admins":
        return {u.id for u in users if (u.role or "") == USER_ROLE_ADMIN}
    if key == "wallet":
        return {u.id for u in users if (u.wallet_balance or 0) > 0}
    if key == "trial":
        return {u.id for u in users if u.trial_granted}
    if key == "trial_converted":
        paying = _paying_user_ids(session, skip_ids)
        return {u.id for u in users if u.trial_granted and u.id in paying}
    if key == "active":
        return {
            s.user_id
            for s in subs
            if s.enabled and not (s.expires_at and s.expires_at <= now)
        }
    if key == "has_config":
        return {s.user_id for s in subs}
    if key == "expired":
        return {s.user_id for s in subs if s.expires_at and s.expires_at <= now}
    if key == "disabled":
        return {s.user_id for s in subs if not s.enabled}
    if key == "expiring":
        horizon = now + timedelta(days=3)
        return {
            s.user_id
            for s in subs
            if s.enabled
            and s.expires_at
            and now < s.expires_at <= horizon
            and not is_metered_payg(s)
        }
    if key == "trial_config":
        return {s.user_id for s in subs if s.plan and s.plan.code == TRIAL_PLAN_CODE}
    if key == "payg":
        return {
            s.user_id
            for s in subs
            if s.payg_metered or s.is_payg or (s.plan and s.plan.code == PAYG_PLAN_CODE)
        }
    if key == "online":
        return from_usage(minutes=20, online=True)
    if key == "used_24h":
        return from_usage(hours=24)
    if key == "unread":
        rows = session.scalars(
            select(ChatMessage.user_id)
            .where(ChatMessage.sender == "user", ChatMessage.read_at.is_(None))
            .distinct()
        ).all()
        return {uid for uid in rows if uid in user_ids}
    if key == "pending":
        rows = session.scalars(
            select(Order.user_id).where(Order.status == OrderStatus.PENDING).distinct()
        ).all()
        return {uid for uid in rows if uid in user_ids}
    if key == "issues":
        unread = user_ids_for_admin_slice(session, "unread", since, now, skip_ids) or set()
        pending = user_ids_for_admin_slice(session, "pending", since, now, skip_ids) or set()
        return unread | pending
    return set()


def list_admin_slice(
    session: Session,
    settings,
    *,
    key: str = "",
    days: int = 0,
    include_test: bool = False,
    query: str = "",
) -> dict[str, Any]:
    key = (key or "").strip()
    days = int(days or 0)
    if days not in (0, 1, 7, 30):
        days = 30
    now = datetime.utcnow()
    since = _period_start(days)
    skip = set() if include_test else test_user_ids(session)
    ids = user_ids_for_admin_slice(session, key, since, now, skip)
    stmt = select(User).order_by(User.id.desc())
    if ids is not None:
        if not ids:
            return {"items": [], "title": SLICE_TITLES.get(key, "کاربران"), "key": key}
        stmt = stmt.where(User.id.in_(ids))
    elif not include_test:
        stmt = stmt.where(User.is_test.is_(False))
    q = (query or "").strip()
    if q:
        if q.isdigit():
            num = int(q)
            stmt = stmt.where((User.telegram_id == num) | (User.id == num))
        elif q.startswith("@"):
            stmt = stmt.where(func.lower(User.username) == q[1:].lower())
        else:
            like = f"%{q}%"
            stmt = stmt.where(
                func.lower(User.username).like(like.lower())
                | func.lower(User.full_name).like(like.lower())
            )
    users = list(session.scalars(stmt.limit(80)).all())
    return {
        "items": [admin_user_overview(session, u, settings) for u in users],
        "title": SLICE_TITLES.get(key, "کاربران"),
        "key": key,
    }


def list_expiring_soon(
    session: Session,
    *,
    days: int = 3,
    include_test: bool = False,
) -> dict[str, Any]:
    days = max(1, min(int(days or 3), 14))
    now = datetime.utcnow()
    horizon = now + timedelta(days=days)
    skip = set() if include_test else test_user_ids(session)
    subs = list(
        session.scalars(
            select(Subscription)
            .where(
                Subscription.enabled.is_(True),
                Subscription.expires_at.is_not(None),
                Subscription.expires_at > now,
                Subscription.expires_at <= horizon,
            )
            .options(selectinload(Subscription.user), selectinload(Subscription.plan))
            .order_by(Subscription.expires_at.asc())
            .limit(200)
        ).all()
    )
    items: list[dict[str, Any]] = []
    for sub in subs:
        user = sub.user
        if not user or user.id in skip:
            continue
        if is_metered_payg(sub) or not sub.expires_at:
            continue
        left = max(0.0, (sub.expires_at - now).total_seconds() / 86400.0)
        label = (sub.label or "").strip() or (sub.plan.title if sub.plan else sub.xui_email)
        if left < 1:
            left_label = "کمتر از ۱ روز"
        else:
            left_label = f"{int(left)} روز"
        items.append(
            {
                "user_id": user.id,
                "telegram_id": user.telegram_id,
                "username": user.username,
                "full_name": user.full_name,
                "subscription_id": sub.id,
                "label": label,
                "expires_at": sub.expires_at.isoformat(),
                "days_left": round(left, 2),
                "days_left_label": left_label,
                "reminded_3d": bool(sub.alert_expiry_3d_at),
                "reminded_1d": bool(sub.alert_expiry_1d_at),
                "is_test": bool(getattr(user, "is_test", False)),
            }
        )
    return {"items": items, "count": len(items), "days": days}
