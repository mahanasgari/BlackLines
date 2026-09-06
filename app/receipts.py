from __future__ import annotations

import logging
import re
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import httpx

try:
    from zoneinfo import ZoneInfo

    _TEHRAN = ZoneInfo("Asia/Tehran")
except Exception:  # noqa: BLE001
    _TEHRAN = timezone(timedelta(hours=3, minutes=30))

logger = logging.getLogger("vpnshop.receipts")

ARCHIVE_SETTING = "receipt_tg_archive_month"
_ORDER_FILE_RE = re.compile(r"^(\d+)\.[A-Za-z0-9]+$")
_PLACEHOLDER_IDS = {"", "miniapp-uploaded", "admin-uploaded", "telegram-uploaded"}

RECEIPTS_DIR = Path("/opt/3x-ui/vpn-bot-data/receipts")
ALLOWED_EXTENSIONS = (".jpg", ".jpeg", ".png", ".webp", ".heic", ".pdf", ".gif")

MIME_BY_EXT = {
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".webp": "image/webp",
    ".heic": "image/heic",
    ".gif": "image/gif",
    ".pdf": "application/pdf",
}


def _normalize_ext(filename: str | None, content_type: str | None = None) -> str:
    ext = Path(filename or "").suffix.lower()
    if ext in ALLOWED_EXTENSIONS:
        return ext
    if content_type:
        ct = content_type.split(";")[0].strip().lower()
        if ct == "image/jpeg":
            return ".jpg"
        if ct == "image/png":
            return ".png"
        if ct == "image/webp":
            return ".webp"
        if ct == "application/pdf":
            return ".pdf"
    return ".jpg"


def receipt_local_path(order_id: int) -> Path | None:
    for ext in ALLOWED_EXTENSIONS:
        path = RECEIPTS_DIR / f"{order_id}{ext}"
        if path.is_file():
            return path
    return None


def save_receipt_local(order_id: int, data: bytes, filename: str | None = None, content_type: str | None = None) -> Path:
    RECEIPTS_DIR.mkdir(parents=True, exist_ok=True)
    ext = _normalize_ext(filename, content_type)
    path = RECEIPTS_DIR / f"{order_id}{ext}"
    path.write_bytes(data)
    return path


def media_type_for_path(path: Path) -> str:
    return MIME_BY_EXT.get(path.suffix.lower(), "application/octet-stream")


async def fetch_receipt_from_telegram(file_id: str, bot_token: str) -> tuple[bytes, str]:
    async with httpx.AsyncClient(timeout=60) as client:
        meta = await client.get(
            f"https://api.telegram.org/bot{bot_token}/getFile",
            params={"file_id": file_id},
        )
        meta.raise_for_status()
        payload = meta.json()
        if not payload.get("ok"):
            raise ValueError(payload.get("description") or "getFile failed")
        file_path = payload["result"]["file_path"]
        url = f"https://api.telegram.org/file/bot{bot_token}/{file_path}"
        resp = await client.get(url)
        resp.raise_for_status()
        ext = Path(file_path).suffix.lower()
        media_type = MIME_BY_EXT.get(ext, "application/octet-stream")
        return resp.content, media_type


async def resolve_receipt(
    order_id: int,
    receipt_file_id: str | None,
    bot_token: str | list[str],
) -> tuple[bytes, str] | None:
    local = receipt_local_path(order_id)
    if local:
        return local.read_bytes(), media_type_for_path(local)

    if not is_telegram_file_id(receipt_file_id):
        return None

    tokens = [bot_token] if isinstance(bot_token, str) else list(bot_token)
    for token in tokens:
        if not token:
            continue
        try:
            return await fetch_receipt_from_telegram(receipt_file_id, token)
        except Exception:
            logger.warning("receipt fetch failed for order %s with one bot token", order_id)
            continue
    logger.exception("Failed fetching receipt from Telegram for order %s", order_id)
    return None


def is_telegram_file_id(value: str | None) -> bool:
    raw = (value or "").strip()
    return bool(raw) and raw not in _PLACEHOLDER_IDS and len(raw) > 16


def gregorian_to_jalali(gy: int, gm: int, gd: int) -> tuple[int, int, int]:
    g_d_m = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
    gy2 = gy + 1 if gm > 2 else gy
    days = 355666 + (365 * gy) + ((gy2 + 3) // 4) - ((gy2 + 99) // 100) + ((gy2 + 399) // 400) + gd + g_d_m[gm - 1]
    jy = -1595 + 33 * (days // 12053)
    days %= 12053
    jy += 4 * (days // 1461)
    days %= 1461
    if days > 365:
        jy += (days - 1) // 365
        days = (days - 1) % 365
    if days < 186:
        jm = 1 + days // 31
        jd = 1 + (days % 31)
    else:
        jm = 7 + (days - 186) // 30
        jd = 1 + ((days - 186) % 30)
    return jy, jm, jd


def jalali_month_days(jy: int, jm: int) -> int:
    if jm <= 6:
        return 31
    if jm <= 11:
        return 30
    return 30 if (jy % 33) in {1, 5, 9, 13, 17, 22, 26, 30} else 29


def tehran_jalali_today(now: datetime | None = None) -> tuple[int, int, int]:
    stamp = now or datetime.now(_TEHRAN)
    if stamp.tzinfo is None:
        stamp = stamp.replace(tzinfo=timezone.utc).astimezone(_TEHRAN)
    else:
        stamp = stamp.astimezone(_TEHRAN)
    return gregorian_to_jalali(stamp.year, stamp.month, stamp.day)


def _jalali_month_name(jm: int) -> str:
    names = ("", "فروردین", "اردیبهشت", "خرداد", "تیر", "مرداد", "شهریور", "مهر", "آبان", "آذر", "دی", "بهمن", "اسفند")
    return names[jm] if 1 <= jm <= 12 else str(jm)


def list_local_receipt_files() -> list[Path]:
    if not RECEIPTS_DIR.is_dir():
        return []
    out: list[Path] = []
    for path in RECEIPTS_DIR.iterdir():
        if path.is_file() and _ORDER_FILE_RE.match(path.name) and path.suffix.lower() in ALLOWED_EXTENSIONS:
            out.append(path)
    return sorted(out, key=lambda p: p.name)


def _upload_receipt_to_telegram(settings, admin_ids: list[int], path: Path, order_id: int) -> str | None:
    from app.tg_http import send_telegram_document

    data = path.read_bytes()
    if not data:
        return None
    caption = f"بایگانی رسید سفارش #{order_id}"
    last_id: str | None = None
    for chat_id in admin_ids:
        file_id = send_telegram_document(
            settings,
            chat_id,
            document=data,
            caption=caption,
            filename=path.name,
        )
        if is_telegram_file_id(file_id):
            last_id = file_id
        elif file_id and not last_id:
            last_id = file_id
    return last_id


def archive_local_receipts_to_telegram(session, settings) -> dict[str, Any]:
    """Move leftover receipt files off disk onto Telegram (keep file_id for later download)."""
    from app.models import Order
    from app.services import list_admin_telegram_ids

    files = list_local_receipt_files()
    admin_ids = list_admin_telegram_ids(session, settings)
    sent = 0
    deleted = 0
    kept = 0
    for path in files:
        match = _ORDER_FILE_RE.match(path.name)
        if not match:
            continue
        order_id = int(match.group(1))
        order = session.get(Order, order_id)
        file_id = getattr(order, "receipt_file_id", None) if order else None
        if not is_telegram_file_id(file_id):
            if not admin_ids:
                kept += 1
                continue
            uploaded = _upload_receipt_to_telegram(settings, admin_ids, path, order_id)
            if not is_telegram_file_id(uploaded):
                kept += 1
                logger.warning("receipt archive send failed order=%s", order_id)
                continue
            if order:
                order.receipt_file_id = uploaded
                session.commit()
            sent += 1
        try:
            path.unlink()
            deleted += 1
        except OSError:
            kept += 1
            logger.exception("receipt archive delete failed %s", path)
    return {"ok": True, "files": len(files), "sent": sent, "deleted": deleted, "kept": kept}


def maybe_archive_receipts_end_of_jalali_month(session, settings, *, now: datetime | None = None) -> dict[str, Any]:
    """On the last Shamsi day, push server receipts to Telegram and delete local copies."""
    from app.services import get_setting, list_admin_telegram_ids, set_setting
    from app.tg_http import send_telegram_message

    jy, jm, jd = tehran_jalali_today(now)
    last = jalali_month_days(jy, jm)
    month_key = f"{jy}-{jm:02d}"
    if jd < last:
        return {"ok": True, "skipped": "not_month_end", "jalali": month_key, "day": jd}
    if (get_setting(session, ARCHIVE_SETTING, "") or "").strip() == month_key:
        return {"ok": True, "skipped": "already_ran", "jalali": month_key}

    result = archive_local_receipts_to_telegram(session, settings)
    set_setting(session, ARCHIVE_SETTING, month_key)
    session.commit()
    title = f"{_jalali_month_name(jm)} {jy}"
    text = (
        f"📦 بایگانی رسیدهای {title}\n"
        f"ارسال به تلگرام: {result['sent']}\n"
        f"حذف از سرور: {result['deleted']}\n"
        f"باقی‌مانده روی دیسک: {result['kept']}\n"
        "از این به بعد از تلگرام قابل دانلود است."
    )
    for admin_id in list_admin_telegram_ids(session, settings):
        try:
            send_telegram_message(settings, admin_id, text)
        except Exception:
            logger.exception("receipt archive notify failed")
    result["jalali"] = month_key
    result["summary"] = text
    return result
