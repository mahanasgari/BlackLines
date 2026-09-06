"""Promo codes and family-pack pricing/helpers."""

from __future__ import annotations

import logging
import re
from datetime import datetime
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import PromoCode, PromoRedemption, User
from app.services import format_price, get_setting, set_setting

logger = logging.getLogger(__name__)

FAMILY_ENABLED = "family_pack_enabled"
FAMILY_MAX = "family_pack_max"
FAMILY_EXTRA_DISCOUNT = "family_extra_discount_percent"
PURCHASE_DISCOUNT = "shop_purchase_discount_percent"
DEFAULT_FAMILY_MAX = 5
DEFAULT_FAMILY_EXTRA_DISCOUNT = 10  # % off each extra seat — applied at purchase, set by admin
DEFAULT_PURCHASE_DISCOUNT = 0


def purchase_discount_percent(session: Session) -> int:
    try:
        raw = int(get_setting(session, PURCHASE_DISCOUNT, str(DEFAULT_PURCHASE_DISCOUNT)) or 0)
    except ValueError:
        raw = DEFAULT_PURCHASE_DISCOUNT
    return max(0, min(90, raw))


def discount_settings_dict(session: Session) -> dict[str, Any]:
    fam = family_settings_dict(session)
    return {
        "purchase_discount_percent": purchase_discount_percent(session),
        "family_extra_discount_percent": int(fam.get("extra_discount_percent") or 0),
    }


def update_discount_settings(
    session: Session,
    *,
    purchase_discount_percent: int,
    family_extra_discount_percent: int,
) -> dict[str, Any]:
    set_setting(session, PURCHASE_DISCOUNT, str(max(0, min(90, int(purchase_discount_percent)))))
    set_setting(
        session,
        FAMILY_EXTRA_DISCOUNT,
        str(max(0, min(50, int(family_extra_discount_percent)))),
    )
    return discount_settings_dict(session)


def family_settings_dict(session: Session) -> dict[str, Any]:
    enabled = get_setting(session, FAMILY_ENABLED, "1") != "0"
    try:
        max_size = int(get_setting(session, FAMILY_MAX, str(DEFAULT_FAMILY_MAX)) or DEFAULT_FAMILY_MAX)
    except ValueError:
        max_size = DEFAULT_FAMILY_MAX
    try:
        extra_disc = int(
            get_setting(session, FAMILY_EXTRA_DISCOUNT, str(DEFAULT_FAMILY_EXTRA_DISCOUNT))
            or DEFAULT_FAMILY_EXTRA_DISCOUNT
        )
    except ValueError:
        extra_disc = DEFAULT_FAMILY_EXTRA_DISCOUNT
    max_size = max(1, min(10, max_size))
    extra_disc = max(0, min(50, extra_disc))
    return {
        "enabled": enabled,
        "min_size": 1,
        "max_size": max_size,
        "extra_discount_percent": extra_disc,
    }


def update_family_settings(
    session: Session,
    *,
    enabled: bool,
    max_size: int,
    extra_discount_percent: int,
) -> dict[str, Any]:
    set_setting(session, FAMILY_ENABLED, "1" if enabled else "0")
    set_setting(session, FAMILY_MAX, str(max(1, min(10, int(max_size)))))
    set_setting(
        session,
        FAMILY_EXTRA_DISCOUNT,
        str(max(0, min(50, int(extra_discount_percent)))),
    )
    return family_settings_dict(session)


def normalize_promo_code(raw: str | None) -> str:
    return re.sub(r"\s+", "", (raw or "").strip().upper())


def family_total_charge(unit_charge: int, family_size: int, settings: dict[str, Any]) -> int:
    size = max(1, int(family_size or 1))
    unit = max(0, int(unit_charge or 0))
    if size <= 1:
        return unit
    if not settings.get("enabled"):
        size = 1
        return unit
    max_size = int(settings.get("max_size") or DEFAULT_FAMILY_MAX)
    size = min(size, max_size)
    disc = int(settings.get("extra_discount_percent") or 0)
    first = unit
    extra_unit = max(0, int(unit * (100 - disc) / 100))
    return first + extra_unit * (size - 1)


def get_promo_by_code(session: Session, code: str) -> PromoCode | None:
    normalized = normalize_promo_code(code)
    if not normalized:
        return None
    return session.scalar(select(PromoCode).where(PromoCode.code == normalized))


def validate_promo_for_user(session: Session, user: User, code: str) -> PromoCode:
    promo = get_promo_by_code(session, code)
    if not promo or not promo.enabled:
        raise ValueError("promo_invalid")
    now = datetime.utcnow()
    if promo.starts_at and promo.starts_at.replace(tzinfo=None) > now:
        raise ValueError("promo_not_started")
    if promo.ends_at and promo.ends_at.replace(tzinfo=None) < now:
        raise ValueError("promo_expired")
    if promo.max_uses > 0 and int(promo.used_count or 0) >= promo.max_uses:
        raise ValueError("promo_exhausted")
    used = session.scalar(
        select(func.count()).select_from(PromoRedemption).where(
            PromoRedemption.promo_code_id == promo.id,
            PromoRedemption.user_id == user.id,
        )
    ) or 0
    limit = max(1, int(promo.per_user_limit or 1))
    if int(used) >= limit:
        raise ValueError("promo_already_used")
    if promo.kind not in ("percent", "free_days"):
        raise ValueError("promo_invalid")
    if int(promo.value or 0) <= 0:
        raise ValueError("promo_invalid")
    if promo.kind == "percent" and int(promo.value) > 90:
        raise ValueError("promo_invalid")
    return promo


def apply_promo_to_charge(charge: int, promo: PromoCode | None) -> tuple[int, int, int]:
    """Returns (final_charge, discount_toman, bonus_days)."""
    base = max(0, int(charge or 0))
    if not promo:
        return base, 0, 0
    if promo.kind == "percent":
        pct = max(1, min(90, int(promo.value or 0)))
        discount = int(base * pct / 100)
        return max(0, base - discount), discount, 0
    if promo.kind == "free_days":
        days = max(1, min(365, int(promo.value or 0)))
        return base, 0, days
    return base, 0, 0


def quote_growth_pricing(
    session: Session,
    user: User,
    unit_charge: int,
    *,
    promo_code: str | None = None,
    family_size: int = 1,
) -> dict[str, Any]:
    fam = family_settings_dict(session)
    size = max(1, int(family_size or 1))
    if not fam["enabled"]:
        size = 1
    else:
        size = min(size, int(fam["max_size"]))
    family_charge = family_total_charge(unit_charge, size, fam)
    shop_pct = purchase_discount_percent(session)
    shop_off = int(family_charge * shop_pct / 100) if shop_pct > 0 else 0
    after_shop = max(0, family_charge - shop_off)
    promo = None
    promo_error = None
    if promo_code:
        try:
            promo = validate_promo_for_user(session, user, promo_code)
        except ValueError as exc:
            promo_error = str(exc)
    final_charge, promo_off, bonus_days = apply_promo_to_charge(after_shop, promo)
    discount = shop_off + promo_off
    return {
        "family_size": size,
        "family_enabled": fam["enabled"],
        "family_max": fam["max_size"],
        "unit_charge": int(unit_charge),
        "family_charge": family_charge,
        "purchase_discount_percent": shop_pct,
        "purchase_discount_toman": shop_off,
        "discount_toman": discount,
        "bonus_days": bonus_days,
        "charge_toman": final_charge,
        "charge_label": format_price(final_charge),
        "discount_label": format_price(discount) if discount else None,
        "promo_code": promo.code if promo else None,
        "promo_kind": promo.kind if promo else None,
        "promo_value": int(promo.value) if promo else None,
        "promo_error": promo_error,
        "promo_ok": bool(promo) and not promo_error,
    }


def record_promo_redemption(session: Session, promo: PromoCode, user: User, order_id: int) -> None:
    session.add(
        PromoRedemption(
            promo_code_id=promo.id,
            user_id=user.id,
            order_id=order_id,
        )
    )
    promo.used_count = int(promo.used_count or 0) + 1
    session.commit()


def list_promo_codes(session: Session) -> list[dict[str, Any]]:
    rows = list(session.scalars(select(PromoCode).order_by(PromoCode.id.desc())).all())
    out: list[dict[str, Any]] = []
    for p in rows:
        out.append(promo_dict(p))
    return out


def promo_dict(p: PromoCode) -> dict[str, Any]:
    return {
        "id": p.id,
        "code": p.code,
        "kind": p.kind,
        "value": int(p.value or 0),
        "max_uses": int(p.max_uses or 0),
        "used_count": int(p.used_count or 0),
        "per_user_limit": int(p.per_user_limit or 1),
        "enabled": bool(p.enabled),
        "starts_at": p.starts_at.isoformat() if p.starts_at else None,
        "ends_at": p.ends_at.isoformat() if p.ends_at else None,
        "note": p.note,
        "created_at": p.created_at.isoformat() if p.created_at else None,
        "kind_label": "درصد تخفیف" if p.kind == "percent" else "روز رایگان",
        "value_label": f"{int(p.value or 0)}٪" if p.kind == "percent" else f"{int(p.value or 0)} روز",
    }


def upsert_promo_code(
    session: Session,
    *,
    code: str,
    kind: str,
    value: int,
    max_uses: int = 0,
    per_user_limit: int = 1,
    enabled: bool = True,
    note: str | None = None,
    promo_id: int | None = None,
) -> PromoCode:
    normalized = normalize_promo_code(code)
    if len(normalized) < 3 or len(normalized) > 32:
        raise ValueError("promo_code_invalid")
    if kind not in ("percent", "free_days"):
        raise ValueError("promo_kind_invalid")
    value = int(value)
    if kind == "percent" and not (1 <= value <= 90):
        raise ValueError("promo_value_invalid")
    if kind == "free_days" and not (1 <= value <= 365):
        raise ValueError("promo_value_invalid")
    row: PromoCode | None = None
    if promo_id:
        row = session.get(PromoCode, promo_id)
    if row is None:
        existing = get_promo_by_code(session, normalized)
        if existing and (promo_id is None or existing.id != promo_id):
            raise ValueError("promo_exists")
        row = PromoCode(code=normalized)
        session.add(row)
    else:
        clash = get_promo_by_code(session, normalized)
        if clash and clash.id != row.id:
            raise ValueError("promo_exists")
        row.code = normalized
    row.kind = kind
    row.value = value
    row.max_uses = max(0, int(max_uses))
    row.per_user_limit = max(1, min(20, int(per_user_limit)))
    row.enabled = bool(enabled)
    row.note = (note or "").strip()[:120] or None
    session.commit()
    session.refresh(row)
    return row


def set_promo_enabled(session: Session, promo_id: int, enabled: bool) -> PromoCode:
    row = session.get(PromoCode, promo_id)
    if not row:
        raise ValueError("promo_not_found")
    row.enabled = bool(enabled)
    session.commit()
    session.refresh(row)
    return row


def promo_error_fa(code: str) -> str:
    return {
        "promo_invalid": "کد تخفیف نامعتبر است",
        "promo_not_started": "این کد هنوز فعال نشده",
        "promo_expired": "مهلت این کد تمام شده",
        "promo_exhausted": "ظرفیت استفاده از این کد تمام شده",
        "promo_already_used": "قبلاً از این کد استفاده کرده‌اید",
        "promo_code_invalid": "کد باید ۳ تا ۳۲ کاراکتر باشد",
        "promo_kind_invalid": "نوع کد نامعتبر است",
        "promo_value_invalid": "مقدار کد نامعتبر است",
        "promo_exists": "این کد از قبل وجود دارد",
        "promo_not_found": "کد پیدا نشد",
        "family_size_invalid": "تعداد اعضای خانواده نامعتبر است",
        "plan_unavailable": "این پلن فعلاً در دسترس نیست",
        "plan_pro_only": "پلن نامحدود فقط برای اعضای Pro است",
    }.get(code, "خطای کد تخفیف")
