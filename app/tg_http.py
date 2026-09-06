from __future__ import annotations

import logging
from typing import Any

import httpx

from app.config import Settings

logger = logging.getLogger(__name__)


def send_telegram_message(
    settings: Settings,
    chat_id: int,
    text: str,
    *,
    parse_mode: str | None = "HTML",
    extra: dict[str, Any] | None = None,
) -> bool:
    """Send a message, trying MainBot then secondary until one succeeds."""
    if not chat_id or not text:
        return False
    payload: dict[str, Any] = {"chat_id": chat_id, "text": text}
    if parse_mode:
        payload["parse_mode"] = parse_mode
    if extra:
        payload.update(extra)
    last_error: str | None = None
    for token in settings.all_bot_tokens:
        try:
            with httpx.Client(timeout=20) as http:
                resp = http.post(f"https://api.telegram.org/bot{token}/sendMessage", json=payload)
            data = resp.json() if resp.content else {}
            if resp.is_success and data.get("ok"):
                return True
            last_error = str(data.get("description") or resp.text or resp.status_code)
        except Exception as exc:
            last_error = str(exc)
            logger.exception("telegram sendMessage failed chat=%s", chat_id)
    if last_error:
        logger.warning("telegram sendMessage exhausted bots chat=%s err=%s", chat_id, last_error)
    return False


def _file_id_from_send_result(body: dict[str, Any]) -> str | None:
    result = body.get("result") if isinstance(body, dict) else None
    if not isinstance(result, dict):
        return None
    doc = result.get("document") if isinstance(result.get("document"), dict) else {}
    photos = result.get("photo") if isinstance(result.get("photo"), list) else []
    last_photo = photos[-1] if photos and isinstance(photos[-1], dict) else {}
    file_id = doc.get("file_id") or last_photo.get("file_id")
    return str(file_id) if file_id else None


def send_telegram_document(
    settings: Settings,
    chat_id: int,
    *,
    document: Any,
    caption: str | None = None,
    filename: str | None = None,
) -> str | None:
    """Upload a document. Returns Telegram file_id, or None on failure."""
    if not chat_id:
        return None
    files = {"document": (filename or "file", document)}
    data: dict[str, Any] = {"chat_id": str(chat_id)}
    if caption:
        data["caption"] = caption
    for token in settings.all_bot_tokens:
        try:
            with httpx.Client(timeout=60) as http:
                resp = http.post(
                    f"https://api.telegram.org/bot{token}/sendDocument",
                    data=data,
                    files=files,
                )
            body = resp.json() if resp.content else {}
            if resp.is_success and body.get("ok"):
                return _file_id_from_send_result(body) or "telegram-uploaded"
        except Exception:
            logger.exception("telegram sendDocument failed chat=%s", chat_id)
    return None


def telegram_api_result(settings: Settings, method: str, payload: dict[str, Any], *, timeout: float = 8) -> Any:
    last_error: str | None = None
    for token in settings.all_bot_tokens:
        try:
            with httpx.Client(timeout=timeout) as http:
                resp = http.post(f"https://api.telegram.org/bot{token}/{method}", json=payload)
            data = resp.json() if resp.content else {}
            if resp.is_success and data.get("ok"):
                return data.get("result")
            last_error = str(data.get("description") or resp.status_code)
        except Exception as exc:
            last_error = str(exc)
    if last_error:
        logger.warning("telegram %s failed err=%s", method, last_error)
    return None


def telegram_user_birthdate(settings: Settings, telegram_id: int) -> dict[str, Any] | None:
    """Return Telegram birthdate dict {day, month, year?} if the user made it visible."""
    chat = telegram_api_result(settings, "getChat", {"chat_id": telegram_id})
    if not isinstance(chat, dict):
        return None
    raw = chat.get("birthdate") or chat.get("birth_date")
    return raw if isinstance(raw, dict) else None


def telegram_user_photo_file_id(settings: Settings, telegram_id: int) -> str | None:
    result = telegram_api_result(settings, "getUserProfilePhotos", {"user_id": telegram_id, "limit": 1})
    if not isinstance(result, dict):
        return None
    photos = result.get("photos") or []
    if not photos:
        return None
    sizes = photos[0] if isinstance(photos[0], list) else []
    if not sizes:
        return None
    best = sizes[-1] if isinstance(sizes[-1], dict) else None
    file_id = (best or {}).get("file_id")
    return str(file_id) if file_id else None


def telegram_download_file(settings: Settings, file_id: str) -> tuple[bytes, str] | None:
    for token in settings.all_bot_tokens:
        try:
            with httpx.Client(timeout=15) as http:
                meta = http.post(f"https://api.telegram.org/bot{token}/getFile", json={"file_id": file_id})
                body = meta.json() if meta.content else {}
                if not (meta.is_success and body.get("ok")):
                    continue
                path = (body.get("result") or {}).get("file_path")
                if not path:
                    continue
                file_resp = http.get(f"https://api.telegram.org/file/bot{token}/{path}")
                if file_resp.is_success and file_resp.content:
                    ctype = file_resp.headers.get("content-type") or "image/jpeg"
                    return file_resp.content, ctype
        except Exception:
            logger.exception("telegram getFile failed")
    return None
