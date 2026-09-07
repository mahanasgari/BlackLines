"""Paid gift cards: buy a catalog plan as a code, redeem later on any account."""

from __future__ import annotations

import logging
import re
import secrets
from datetime import datetime
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.models import GiftCard, Order, OrderStatus, Plan, User
from app.panel import build_subscription_url
from app.services import (
    _notify_telegram,
    assert_shop_plan_available,
    format_price,
    is_pro_only_shop_plan,
    is_retired_shop_plan,
    is_vpn_plan,
    public_links_for_email,
)

logger = logging.getLogger(__name__)

GIFT_CARD_NOTE = "gift_card"
_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"


def is_gift_card_order(order: Order | None) -> bool:
    return bool(order and str(order.admin_note or "").startswith(GIFT_CARD_NOTE))


def assert_giftable_shop_plan(user: User, plan: Plan) -> None:
    if not is_vpn_plan(plan) or is_retired_shop_plan(plan) or is_pro_only_shop_plan(plan):
        raise ValueError("gift_plan_invalid")
    assert_shop_plan_available(user, plan)


def generate_gift_code() -> str:
    chunks = ["".join(secrets.choice(_CODE_ALPHABET) for _ in range(4)) for _ in range(3)]
    return "BL-" + "-".join(chunks)


def normalize_gift_code(raw: str | None) -> str:
    return re.sub(r"[^A-Z0-9]", "", (raw or "").upper())


def gift_card_dict(card: GiftCard, *, reveal_code: bool = True) -> dict[str, Any]:
    plan = card.plan
    redeemed = bool(card.redeemed_at)
    return {
        "id": card.id,
        "code": card.code if reveal_code else None,
        "plan_id": card.plan_id,
        "plan_title": plan.title if plan else "—",
        "plan_label": (plan.title if plan else "کانفیگ") + (f" · {format_price(plan.price_toman)}" if plan else ""),
        "status": "redeemed" if redeemed else "available",
        "status_label": "استفاده شده" if redeemed else "آماده ارسال",
        "created_at": card.created_at.isoformat() if card.created_at else None,
        "redeemed_at": card.redeemed_at.isoformat() if card.redeemed_at else None,
    }


def list_user_gift_cards(session: Session, user: User, *, limit: int = 30) -> list[dict[str, Any]]:
    rows = list(
        session.scalars(
            select(GiftCard)
            .where(GiftCard.buyer_user_id == user.id)
            .options(selectinload(GiftCard.plan))
            .order_by(GiftCard.id.desc())
            .limit(max(1, min(60, limit)))
        ).all()
    )
    return [gift_card_dict(row) for row in rows]


def issue_gift_card_from_order(session: Session, order: Order) -> GiftCard:
    existing = session.scalar(select(GiftCard).where(GiftCard.order_id == order.id))
    if existing:
        return existing
    for _ in range(8):
        code = generate_gift_code()
        clash = session.scalar(select(GiftCard).where(GiftCard.code == code))
        if clash:
            continue
        card = GiftCard(
            code=code,
            plan_id=order.plan_id,
            buyer_user_id=order.user_id,
            order_id=order.id,
        )
        session.add(card)
        session.commit()
        session.refresh(card)
        return card
    raise RuntimeError("gift_code_collision")


def get_gift_card_for_order(session: Session, order: Order) -> GiftCard | None:
    return session.scalar(select(GiftCard).where(GiftCard.order_id == order.id))


def redeem_gift_card(session: Session, user: User, raw_code: str, panel, settings) -> dict[str, Any]:
    from app.services import admin_gift_subscription

    compact = normalize_gift_code(raw_code)
    if len(compact) < 8:
        raise ValueError("gift_code_invalid")
    rows = list(session.scalars(select(GiftCard).options(selectinload(GiftCard.plan))).all())
    card = next((r for r in rows if normalize_gift_code(r.code) == compact), None)
    if not card:
        raise ValueError("gift_code_invalid")
    if card.redeemed_at:
        raise ValueError("gift_already_used")
    plan = card.plan
    if not plan:
        raise ValueError("gift_plan_invalid")
    sub = admin_gift_subscription(session, user, panel, settings, plan_id=plan.id)
    if sub.label and "هدیه" not in (sub.label or ""):
        sub.label = f"{sub.label} · هدیه"
        session.commit()
        session.refresh(sub)
    card.redeemed_by_id = user.id
    card.redeemed_at = datetime.utcnow()
    session.commit()
    session.refresh(card)
    sub_url = build_subscription_url(sub.xui_sub_id, settings)
    try:
        public_links_for_email(panel, sub.xui_email, settings, name=sub.label or plan.title)
    except Exception:
        logger.exception("gift redeem links warm failed")
    buyer = session.get(User, card.buyer_user_id)
    if buyer and buyer.id != user.id:
        who = user.full_name or (f"@{user.username}" if user.username else str(user.telegram_id))
        try:
            _notify_telegram(
                settings,
                buyer.telegram_id,
                f"🎁 کارت هدیه {card.code} توسط {who} فعال شد.",
            )
        except Exception:
            logger.exception("gift redeem buyer notify failed")
    return {
        "ok": True,
        "subscription_id": sub.id,
        "plan_title": plan.title,
        "subscription_url": sub_url,
        "email": sub.xui_email,
        "expires_at": sub.expires_at.isoformat() if sub.expires_at else None,
    }


def gift_error_fa(code: str) -> str:
    return {
        "gift_plan_invalid": "این پلن را نمی‌توان به‌صورت کارت هدیه خرید",
        "gift_code_invalid": "کد هدیه معتبر نیست",
        "gift_already_used": "این کد قبلاً استفاده شده",
        "gift_code_collision": "ساخت کد ناموفق بود — دوباره تلاش کنید",
    }.get(code, code)
