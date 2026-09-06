"""Admin ops: audit log, bulk gift, config transfer, IP nicknames."""

from __future__ import annotations

import json
import logging
import re
from contextvars import ContextVar
from datetime import datetime
from typing import Any

from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.models import AdminAuditLog, Subscription, User
from app.services import (
    admin_gift_subscription,
    get_setting,
    grant_pro_to_user,
    resolve_trial_target_users,
    set_setting,
)

logger = logging.getLogger(__name__)

IP_NICK_PREFIX = "ip_nick_u:"
NICK_MAX = 32
NICK_PRESETS = ("موبایل", "لپ‌تاپ", "تبلت", "کامپیوتر", "مودم", "سایر")

_audit_request: ContextVar[Any] = ContextVar("audit_request", default=None)

ACTION_LABELS: dict[str, str] = {
    "create_order": "ثبت سفارش",
    "create_custom_order": "سفارش پلن سفارشی",
    "create_payg_order": "سفارش حجم",
    "order_pro": "سفارش Pro",
    "cancel_order": "لغو سفارش",
    "upload_receipt": "ارسال رسید",
    "confirm_wallet": "پرداخت با کیف‌پول",
    "renew_order": "درخواست تمدید",
    "approve_order": "تایید سفارش",
    "claim_trial": "دریافت کانفیگ تست",
    "auto_approve_order": "تایید خودکار کیف‌پول",
    "reject_order": "رد سفارش",
    "admin_upload_receipt": "آپلود رسید توسط ادمین",
    "wallet_deposit": "شارژ کیف‌پول",
    "wallet_transfer": "انتقال کیف‌پول",
    "withdraw_request": "درخواست برداشت",
    "approve_withdraw": "پرداخت برداشت",
    "reject_withdraw": "رد برداشت",
    "wallet_adjust": "تغییر کیف‌پول",
    "wallet_credit": "سقف اعتبار کیف‌پول",
    "wallet_convert_credit": "تبدیل شارژ به نسیه",
    "rename_config": "تغییر نام کانفیگ",
    "set_customer": "ثبت مشخصات مشتری",
    "mark_link_shared": "علامت ارسال لینک",
    "auto_renew": "تمدید خودکار",
    "ip_nickname": "نام‌گذاری آی‌پی",
    "payg_activate": "فعال‌سازی مصرفی",
    "payg_toggle": "قطع/وصل مصرفی",
    "revoke_config": "باطل کردن کانفیگ",
    "rotate_link": "لینک جدید کانفیگ",
    "hide_config": "مخفی کردن کانفیگ",
    "unhide_config": "بازگردانی کانفیگ",
    "transfer_subscription": "انتقال کانفیگ",
    "family_restrict": "محدودیت خانواده",
    "diagnose_config": "عیب‌یابی کانفیگ",
    "redeem_gift": "فعال‌سازی کارت هدیه",
    "profile_birth_date": "ثبت تاریخ تولد",
    "profile_contact": "ویرایش تماس",
    "chat_send": "ارسال پیام",
    "admin_chat_send": "پاسخ پشتیبانی",
    "broadcast": "پیام همگانی",
    "add_payment_card": "افزودن کارت",
    "remove_payment_card": "حذف کارت",
    "birthday_settings": "تنظیم هدیه تولد",
    "trial_settings": "تنظیم تست",
    "create_promo": "ساخت کد تخفیف",
    "toggle_promo": "فعال/غیرفعال کد تخفیف",
    "family_settings": "تنظیم خانواده",
    "discount_settings": "تنظیم تخفیف",
    "custom_settings": "تنظیم پلن سفارشی",
    "payg_settings": "تنظیم مصرفی",
    "parental_settings": "تنظیم کنترل والدین",
    "trial_grant": "اعطای تست",
    "add_server": "افزودن سرور",
    "toggle_server": "فعال/غیرفعال سرور",
    "server_visibility": "نمایش سرور",
    "sync_server": "همگام‌سازی سرور",
    "delete_server": "حذف سرور",
    "set_role": "تغییر نقش",
    "toggle_subscription": "فعال/غیرفعال کانفیگ",
    "grant_pro": "اعطای Pro",
    "gift_subscription": "هدیه کانفیگ",
    "delete_subscription": "حذف کانفیگ",
    "bulk_gift": "هدیه گروهی",
    "bulk_gift_pro": "هدیه گروهی Pro",
    "bulk_gift_plan": "هدیه گروهی پلن",
}

CATEGORY_LABELS: dict[str, str] = {
    "shop": "فروشگاه",
    "config": "کانفیگ",
    "wallet": "کیف‌پول",
    "family": "خانواده",
    "chat": "گفتگو",
    "profile": "پروفایل",
    "admin": "ادمین",
}

_PATH_ACTIONS: list[tuple[re.Pattern[str], str, str, str]] = [
    (re.compile(r"^/shop/api/orders$"), "POST", "create_order", "shop"),
    (re.compile(r"^/shop/api/custom/order$"), "POST", "create_custom_order", "shop"),
    (re.compile(r"^/shop/api/payg/order$"), "POST", "create_payg_order", "shop"),
    (re.compile(r"^/shop/api/pro/order$"), "POST", "order_pro", "shop"),
    (re.compile(r"^/shop/api/orders/\d+/cancel$"), "POST", "cancel_order", "shop"),
    (re.compile(r"^/shop/api/orders/\d+/receipt$"), "POST", "upload_receipt", "shop"),
    (re.compile(r"^/shop/api/orders/\d+/confirm-wallet$"), "POST", "confirm_wallet", "shop"),
    (re.compile(r"^/shop/api/trial/claim$"), "POST", "claim_trial", "shop"),
    (re.compile(r"^/shop/api/subscriptions/\d+/renew$"), "POST", "renew_order", "shop"),
    (re.compile(r"^/shop/api/admin/orders/\d+/approve$"), "POST", "approve_order", "shop"),
    (re.compile(r"^/shop/api/admin/orders/\d+/reject$"), "POST", "reject_order", "shop"),
    (re.compile(r"^/shop/api/admin/orders/\d+/receipt$"), "POST", "admin_upload_receipt", "shop"),
    (re.compile(r"^/shop/api/wallet/deposit$"), "POST", "wallet_deposit", "wallet"),
    (re.compile(r"^/shop/api/wallet/transfer$"), "POST", "wallet_transfer", "wallet"),
    (re.compile(r"^/shop/api/withdraw$"), "POST", "withdraw_request", "wallet"),
    (re.compile(r"^/shop/api/admin/withdrawals/\d+/pay$"), "POST", "approve_withdraw", "wallet"),
    (re.compile(r"^/shop/api/admin/withdrawals/\d+/reject$"), "POST", "reject_withdraw", "wallet"),
    (re.compile(r"^/shop/api/admin/users/\d+/wallet$"), "POST", "wallet_adjust", "wallet"),
    (re.compile(r"^/shop/api/admin/users/\d+/wallet-credit$"), "POST", "wallet_credit", "wallet"),
    (re.compile(r"^/shop/api/admin/users/\d+/wallet-convert-credit$"), "POST", "wallet_convert_credit", "wallet"),
    (re.compile(r"^/shop/api/subscriptions/\d+/label$"), "POST", "rename_config", "config"),
    (re.compile(r"^/shop/api/subscriptions/\d+/customer$"), "POST", "set_customer", "config"),
    (re.compile(r"^/shop/api/subscriptions/\d+/link-shared$"), "POST", "mark_link_shared", "config"),
    (re.compile(r"^/shop/api/subscriptions/\d+/auto-renew$"), "POST", "auto_renew", "config"),
    (re.compile(r"^/shop/api/subscriptions/\d+/ip-nickname$"), "POST", "ip_nickname", "config"),
    (re.compile(r"^/shop/api/payg/activate$"), "POST", "payg_activate", "config"),
    (re.compile(r"^/shop/api/payg/set-enabled$"), "POST", "payg_toggle", "config"),
    (re.compile(r"^/shop/api/subscriptions/\d+/revoke$"), "POST", "revoke_config", "config"),
    (re.compile(r"^/shop/api/subscriptions/\d+/rotate-link$"), "POST", "rotate_link", "config"),
    (re.compile(r"^/shop/api/subscriptions/\d+/diagnose$"), "POST", "diagnose_config", "config"),
    (re.compile(r"^/shop/api/gift-cards/redeem$"), "POST", "redeem_gift", "shop"),
    (re.compile(r"^/shop/api/subscriptions/\d+/hide$"), "POST", "hide_config", "config"),
    (re.compile(r"^/shop/api/subscriptions/\d+/unhide$"), "POST", "unhide_config", "config"),
    (re.compile(r"^/shop/api/subscriptions/\d+/transfer$"), "POST", "transfer_subscription", "config"),
    (re.compile(r"^/shop/api/admin/subscriptions/\d+/transfer$"), "POST", "transfer_subscription", "config"),
    (re.compile(r"^/shop/api/subscriptions/\d+/family/\d+/restrict$"), "POST", "family_restrict", "family"),
    (re.compile(r"^/shop/api/profile/birth-date$"), "POST", "profile_birth_date", "profile"),
    (re.compile(r"^/shop/api/profile/contact$"), "POST", "profile_contact", "profile"),
    (re.compile(r"^/shop/api/chat/messages$"), "POST", "chat_send", "chat"),
    (re.compile(r"^/shop/api/admin/chat/threads/\d+/messages$"), "POST", "admin_chat_send", "chat"),
    (re.compile(r"^/shop/api/admin/broadcast$"), "POST", "broadcast", "admin"),
    (re.compile(r"^/shop/api/admin/payment-cards$"), "POST", "add_payment_card", "admin"),
    (re.compile(r"^/shop/api/admin/payment-cards/\d+$"), "DELETE", "remove_payment_card", "admin"),
    (re.compile(r"^/shop/api/admin/birthday-gift$"), "POST", "birthday_settings", "admin"),
    (re.compile(r"^/shop/api/admin/trial-settings$"), "POST", "trial_settings", "admin"),
    (re.compile(r"^/shop/api/admin/promo-codes$"), "POST", "create_promo", "admin"),
    (re.compile(r"^/shop/api/admin/promo-codes/\d+/enabled$"), "POST", "toggle_promo", "admin"),
    (re.compile(r"^/shop/api/admin/family-settings$"), "POST", "family_settings", "admin"),
    (re.compile(r"^/shop/api/admin/discount-settings$"), "POST", "discount_settings", "admin"),
    (re.compile(r"^/shop/api/admin/custom-settings$"), "POST", "custom_settings", "admin"),
    (re.compile(r"^/shop/api/admin/payg-settings$"), "POST", "payg_settings", "admin"),
    (re.compile(r"^/shop/api/admin/parental-settings$"), "POST", "parental_settings", "admin"),
    (re.compile(r"^/shop/api/admin/trial-grant$"), "POST", "trial_grant", "admin"),
    (re.compile(r"^/shop/api/admin/servers$"), "POST", "add_server", "admin"),
    (re.compile(r"^/shop/api/admin/servers/\d+/enabled$"), "POST", "toggle_server", "admin"),
    (re.compile(r"^/shop/api/admin/servers/\d+/visibility$"), "POST", "server_visibility", "admin"),
    (re.compile(r"^/shop/api/admin/servers/\d+/sync$"), "POST", "sync_server", "admin"),
    (re.compile(r"^/shop/api/admin/servers/\d+/delete$"), "POST", "delete_server", "admin"),
    (re.compile(r"^/shop/api/admin/users/\d+/role$"), "POST", "set_role", "admin"),
    (re.compile(r"^/shop/api/admin/users/\d+/subscriptions/\d+/enabled$"), "POST", "toggle_subscription", "config"),
    (re.compile(r"^/shop/api/admin/users/\d+/pro$"), "POST", "grant_pro", "admin"),
    (re.compile(r"^/shop/api/admin/users/\d+/subscriptions$"), "POST", "gift_subscription", "admin"),
    (re.compile(r"^/shop/api/admin/users/\d+/subscriptions/\d+/delete$"), "POST", "delete_subscription", "admin"),
    (re.compile(r"^/shop/api/admin/bulk-gift$"), "POST", "bulk_gift", "admin"),
]


def bind_audit_request(request: Any):
    return _audit_request.set(request)


def reset_audit_request(token: Any) -> None:
    _audit_request.reset(token)


def skip_auto_audit_path(path: str) -> bool:
    p = (path or "").split("?", 1)[0]
    if not p.startswith("/shop/api/"):
        return True
    if p.endswith("/quote") or p.endswith("/promo/validate"):
        return True
    if p.endswith("/chat/read") or re.search(r"/threads/\d+/read$", p):
        return True
    if "/audit-log" in p:
        return True
    return False


def infer_actor_role(actor: User | None, path: str | None = None) -> str:
    if "/admin/" in (path or ""):
        return "admin"
    if actor is None:
        return "system"
    return "user"


def action_label(action: str) -> str:
    return ACTION_LABELS.get(action, action)


def _secret_key(key: str) -> bool:
    k = (key or "").lower()
    return any(
        part in k
        for part in (
            "token",
            "password",
            "secret",
            "init",
            "receipt",
            "file",
            "card",
            "hash",
        )
    )


def summarize_payload(raw: bytes, content_type: str) -> str:
    if "multipart/" in (content_type or "").lower():
        return "file_upload"
    if not raw:
        return ""
    try:
        data = json.loads(raw.decode("utf-8", errors="ignore") or "{}")
    except Exception:
        return ""
    if not isinstance(data, dict):
        return ""
    keep: dict[str, Any] = {}
    for key, value in list(data.items())[:16]:
        if _secret_key(str(key)):
            continue
        if isinstance(value, str):
            keep[key] = value[:80]
        elif isinstance(value, (int, float, bool)) or value is None:
            keep[key] = value
        elif isinstance(value, list):
            keep[key] = f"list:{len(value)}"
        elif isinstance(value, dict):
            keep[key] = "object"
    if not keep:
        return ""
    try:
        return json.dumps(keep, ensure_ascii=False)[:360]
    except Exception:
        return ""


def describe_api_action(method: str, path: str, raw: bytes, content_type: str) -> tuple[str, str, str]:
    method_u = (method or "POST").upper()
    clean = (path or "").split("?", 1)[0]
    action = f"{method_u.lower()}:{clean.replace('/shop/api/', '')[:48]}"
    category = "admin" if "/admin/" in clean else "shop"
    for pattern, want_method, mapped, cat in _PATH_ACTIONS:
        if want_method == method_u and pattern.match(clean):
            action, category = mapped, cat
            break
    ids = re.findall(r"/(\d+)(?:/|$)", clean)
    bits = [f"id={n}" for n in ids[:4]]
    payload = summarize_payload(raw, content_type)
    if payload:
        bits.append(payload)
    return action, category, " ".join(bits)[:500]


def record_audit(
    session: Session,
    *,
    actor: User | None,
    action: str,
    target_user: User | None = None,
    target_subscription_id: int | None = None,
    detail: str | None = None,
    category: str | None = None,
    path: str | None = None,
    actor_role: str | None = None,
    commit: bool = True,
) -> AdminAuditLog:
    role = actor_role or infer_actor_role(actor, path)
    cat = category
    if not cat:
        if action in ACTION_LABELS:
            for pattern, _method, mapped, mapped_cat in _PATH_ACTIONS:
                if mapped == action:
                    cat = mapped_cat
                    break
        cat = cat or ("admin" if role == "admin" else "shop")
    row = AdminAuditLog(
        actor_user_id=actor.id if actor else None,
        actor_telegram_id=actor.telegram_id if actor else None,
        actor_role=role[:16],
        action=(action or "unknown")[:64],
        category=(cat or "shop")[:32],
        path=(path or "")[:160] or None,
        target_user_id=target_user.id if target_user else None,
        target_subscription_id=target_subscription_id,
        detail=(detail or "").strip()[:500] or None,
    )
    session.add(row)
    req = _audit_request.get()
    if req is not None:
        try:
            req.state.audit_written = True
        except Exception:
            pass
    if commit:
        session.commit()
        session.refresh(row)
    return row


def _user_display(user: User | None, fallback: str | int | None = None) -> str:
    if user and user.full_name:
        return user.full_name
    if user and user.username:
        return f"@{user.username}"
    if user:
        return str(user.telegram_id)
    if fallback:
        return str(fallback)
    return "—"


def list_audit_logs(
    session: Session,
    *,
    limit: int = 80,
    offset: int = 0,
    q: str = "",
    actor_kind: str = "",
    category: str = "",
    actor_user_id: int | None = None,
    include_test: bool = False,
) -> dict[str, Any]:
    stmt = select(AdminAuditLog)
    count_stmt = select(func.count(AdminAuditLog.id))
    filters = []
    if not include_test:
        test_ids = set(session.scalars(select(User.id).where(User.is_test.is_(True))).all())
        if test_ids:
            filters.append(
                or_(
                    AdminAuditLog.actor_user_id.is_(None),
                    ~AdminAuditLog.actor_user_id.in_(test_ids),
                )
            )
            filters.append(
                or_(
                    AdminAuditLog.target_user_id.is_(None),
                    ~AdminAuditLog.target_user_id.in_(test_ids),
                )
            )
    if category.strip():
        filters.append(AdminAuditLog.category == category.strip())
    if actor_user_id:
        filters.append(AdminAuditLog.actor_user_id == actor_user_id)
    kind = actor_kind.strip().lower()
    legacy_admin = (
        "grant_pro",
        "gift_subscription",
        "delete_subscription",
        "bulk_gift_pro",
        "bulk_gift_plan",
        "trial_grant",
        "wallet_adjust",
        "set_role",
        "broadcast",
    )
    if kind == "system":
        filters.append(AdminAuditLog.actor_user_id.is_(None))
    elif kind == "admin":
        filters.append(
            or_(
                AdminAuditLog.actor_role == "admin",
                AdminAuditLog.path.contains("/admin/"),
                AdminAuditLog.action.in_(legacy_admin),
            )
        )
    elif kind == "user":
        filters.append(AdminAuditLog.actor_user_id.is_not(None))
        filters.append(or_(AdminAuditLog.actor_role == "user", AdminAuditLog.actor_role.is_(None)))
        filters.append(or_(AdminAuditLog.path.is_(None), ~AdminAuditLog.path.contains("/admin/")))
        filters.append(~AdminAuditLog.action.in_(legacy_admin))
    query = (q or "").strip()
    if query:
        like = f"%{query}%"
        filters.append(
            or_(
                AdminAuditLog.action.ilike(like),
                AdminAuditLog.detail.ilike(like),
                AdminAuditLog.path.ilike(like),
            )
        )
    if filters:
        stmt = stmt.where(*filters)
        count_stmt = count_stmt.where(*filters)
    total = int(session.scalar(count_stmt) or 0)
    rows = list(
        session.scalars(
            stmt.order_by(AdminAuditLog.id.desc()).offset(max(0, offset)).limit(max(1, min(200, limit)))
        ).all()
    )
    actor_ids = {r.actor_user_id for r in rows if r.actor_user_id}
    target_ids = {r.target_user_id for r in rows if r.target_user_id}
    users: dict[int, User] = {}
    need = actor_ids | target_ids
    if need:
        for u in session.scalars(select(User).where(User.id.in_(need))).all():
            users[u.id] = u
    out: list[dict[str, Any]] = []
    for r in rows:
        actor = users.get(r.actor_user_id or 0)
        target = users.get(r.target_user_id or 0)
        role = r.actor_role or infer_actor_role(actor, r.path)
        cat = r.category or "shop"
        out.append(
            {
                "id": r.id,
                "action": r.action,
                "action_label": action_label(r.action),
                "category": cat,
                "category_label": CATEGORY_LABELS.get(cat, cat),
                "actor_role": role,
                "actor_user_id": r.actor_user_id,
                "actor_telegram_id": r.actor_telegram_id,
                "actor_name": _user_display(actor, r.actor_telegram_id),
                "target_user_id": r.target_user_id,
                "target_name": _user_display(target) if target or r.target_user_id else None,
                "target_subscription_id": r.target_subscription_id,
                "detail": r.detail,
                "path": r.path,
                "created_at": r.created_at.isoformat() if r.created_at else None,
            }
        )
    return {"items": out, "total": total, "limit": limit, "offset": offset}


def ip_nick_key(user_id: int) -> str:
    return f"{IP_NICK_PREFIX}{int(user_id)}"


def get_ip_nicknames(session: Session, user_id: int) -> dict[str, str]:
    raw = get_setting(session, ip_nick_key(user_id), "{}") or "{}"
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return {}
    if not isinstance(data, dict):
        return {}
    out: dict[str, str] = {}
    for ip, nick in data.items():
        ip_s = str(ip or "").strip()
        nick_s = str(nick or "").strip()[:NICK_MAX]
        if ip_s and nick_s:
            out[ip_s] = nick_s
    return out


def set_ip_nickname(session: Session, user_id: int, ip: str, nickname: str | None) -> dict[str, str]:
    ip_s = str(ip or "").strip()
    if not ip_s or len(ip_s) > 64:
        raise ValueError("ip_invalid")
    nick_s = (nickname or "").strip()[:NICK_MAX]
    data = get_ip_nicknames(session, user_id)
    if not nick_s:
        data.pop(ip_s, None)
    else:
        data[ip_s] = nick_s
    # Cap map size
    if len(data) > 40:
        # drop arbitrary extras keeping newest-ish by keeping insertion order of remaining
        keys = list(data.keys())
        for k in keys[:-40]:
            data.pop(k, None)
    set_setting(session, ip_nick_key(user_id), json.dumps(data, ensure_ascii=False))
    return data


def merge_ips_with_nicknames(
    connected_ips: list[dict[str, Any]], nicknames: dict[str, str]
) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for row in connected_ips:
        item = dict(row)
        ip = str(item.get("ip") or "")
        item["nickname"] = nicknames.get(ip) or None
        out.append(item)
    return out


def transfer_subscription(
    session: Session,
    *,
    sub: Subscription,
    target: User,
    actor: User | None = None,
) -> tuple[Subscription, User | None]:
    """Move subscription ownership to target user. Returns (sub, previous_owner)."""
    if sub.user_id == target.id:
        raise ValueError("same_user")
    source = session.get(User, sub.user_id)
    source_id = sub.user_id
    sub.user_id = target.id
    sub.family_group = None
    sub.family_index = None
    sub.family_role = None
    sub.parental_categories = None
    sub.parental_schedule = None
    sub.vpn_allow_schedule = None
    sub.vpn_schedule_paused = False
    session.commit()
    session.refresh(sub)
    record_audit(
        session,
        actor=actor,
        action="transfer_subscription",
        target_user=target,
        target_subscription_id=sub.id,
        detail=f"from_user={source_id} email={sub.xui_email}",
    )
    return sub, source


def resolve_shop_user(session: Session, raw: str) -> User | None:
    token = (raw or "").strip()
    if token.startswith("@"):
        token = token[1:]
    if not token:
        return None
    if token.isdigit():
        return session.scalar(select(User).where(User.telegram_id == int(token)))
    return session.scalar(select(User).where(func.lower(User.username) == token.lower()))


def shop_user_public_dict(user: User) -> dict[str, Any]:
    return {
        "telegram_id": user.telegram_id,
        "username": user.username,
        "full_name": user.full_name,
    }


def _apply_owner(sub: Subscription, target: User, *, detach_family: bool) -> None:
    sub.user_id = target.id
    sub.auto_renew = False
    if detach_family:
        sub.family_group = None
        sub.family_index = None
        sub.family_role = None
        sub.parental_categories = None
        sub.parental_schedule = None
        sub.vpn_allow_schedule = None
        sub.vpn_schedule_paused = False


def _sync_panel_owner(panel, emails: list[str], telegram_id: int | None) -> None:
    if not panel or not telegram_id:
        return
    for email in emails:
        if not email:
            continue
        try:
            panel.update_client(email, {"tgId": telegram_id})
        except Exception:
            logger.exception("panel owner sync failed %s", email)


def user_transfer_subscription(
    session: Session,
    *,
    sub: Subscription,
    target: User,
    actor: User,
    panel=None,
) -> dict[str, Any]:
    """Owner moves this config (and a family pack, if this is the parent) to another shop user."""
    if actor.id != sub.user_id:
        raise ValueError("not_owner")
    if sub.user_id == target.id:
        raise ValueError("same_user")

    from app.parental import family_members, is_family_parent

    source = session.get(User, sub.user_id)
    source_id = sub.user_id
    moved: list[Subscription] = [sub]
    family_moved = False

    if is_family_parent(sub) and (sub.family_group or "").strip():
        members = [
            m
            for m in family_members(session, sub.family_group)
            if m.user_id == actor.id
        ]
        moved = members or [sub]
        family_moved = len(moved) > 1
        for member in moved:
            _apply_owner(member, target, detach_family=False)
    elif (sub.family_group or "").strip():
        _apply_owner(sub, target, detach_family=True)
    else:
        _apply_owner(sub, target, detach_family=False)

    session.commit()
    session.refresh(sub)
    emails = [m.xui_email for m in moved]
    _sync_panel_owner(panel, emails, target.telegram_id)
    record_audit(
        session,
        actor=actor,
        action="transfer_subscription",
        target_user=target,
        target_subscription_id=sub.id,
        detail=f"from_user={source_id} email={sub.xui_email} count={len(moved)} family={int(family_moved)}",
    )
    return {
        "subscription_id": sub.id,
        "moved_ids": [m.id for m in moved],
        "moved_count": len(moved),
        "family_moved": family_moved,
        "email": sub.xui_email,
        "source": source,
        "target": target,
    }


def bulk_gift_to_users(
    session: Session,
    users: list[User],
    panel,
    settings,
    *,
    kind: str,
    plan_id: int | None = None,
    pro_days: int | None = None,
    notify: bool = True,
    actor: User | None = None,
) -> dict[str, Any]:
    granted: list[dict[str, Any]] = []
    failed: list[dict[str, Any]] = []
    kind = (kind or "").strip().lower()
    if kind not in ("pro", "plan"):
        raise ValueError("kind_invalid")
    if kind == "plan" and not plan_id:
        raise ValueError("plan_required")

    for user in users:
        try:
            if kind == "pro":
                until = grant_pro_to_user(session, user, days=pro_days)
                record_audit(
                    session,
                    actor=actor,
                    action="bulk_gift_pro",
                    target_user=user,
                    detail=f"until={until.isoformat() if until else ''}",
                    commit=True,
                )
                if notify and user.telegram_id:
                    from app.services import _notify_telegram as notify_tg

                    notify_tg(
                        settings,
                        user.telegram_id,
                        f"⭐ اشتراک Pro برای شما فعال شد.\nاعتبار تا: {until.strftime('%Y/%m/%d') if until else '—'}",
                    )
                granted.append(
                    {
                        "telegram_id": user.telegram_id,
                        "username": user.username,
                        "pro_until": until.isoformat() if until else None,
                    }
                )
            else:
                sub = admin_gift_subscription(
                    session, user, panel, settings, plan_id=int(plan_id or 0)
                )
                record_audit(
                    session,
                    actor=actor,
                    action="bulk_gift_plan",
                    target_user=user,
                    target_subscription_id=sub.id,
                    detail=f"plan_id={plan_id} email={sub.xui_email}",
                    commit=True,
                )
                if notify and user.telegram_id:
                    from app.services import _notify_telegram as notify_tg

                    from app.panel import build_subscription_url
                    from app.texts import subscription_link_message

                    notify_tg(
                        settings,
                        user.telegram_id,
                        subscription_link_message(
                            email=sub.xui_email,
                            sub_url=build_subscription_url(sub.xui_sub_id, settings),
                            label=sub.label or "کانفیگ",
                            title="✅ یک کانفیگ هدیه برای شما فعال شد",
                        ),
                    )
                granted.append(
                    {
                        "telegram_id": user.telegram_id,
                        "username": user.username,
                        "subscription_id": sub.id,
                        "email": sub.xui_email,
                    }
                )
        except Exception as exc:  # noqa: BLE001
            logger.exception("bulk gift failed user=%s", user.id)
            failed.append(
                {
                    "telegram_id": user.telegram_id,
                    "username": user.username,
                    "error": str(exc)[:120],
                }
            )
    return {
        "granted_count": len(granted),
        "failed_count": len(failed),
        "granted": granted,
        "failed": failed,
    }


def resolve_bulk_targets(
    session: Session,
    *,
    targets_text: str = "",
    all_users: bool = False,
) -> tuple[list[User], list[str]]:
    if all_users:
        users = list(session.scalars(select(User).order_by(User.id.asc())).all())
        return users, []
    tokens = re.split(r"[\s,;]+", targets_text or "")
    return resolve_trial_target_users(session, tokens)
