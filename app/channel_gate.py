from __future__ import annotations

import logging
import time
from typing import Any

import httpx
from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update
from telegram.constants import ParseMode
from telegram.ext import ApplicationHandlerStop, ContextTypes

from app.config import Settings

logger = logging.getLogger(__name__)

_MEMBER_OK = frozenset({"creator", "administrator", "member", "restricted"})
_cache: dict[int, tuple[bool, float]] = {}
# Members are re-checked rarely; non-members soon (so joining unlocks quickly).
_CACHE_TTL_MEMBER_SEC = 600.0
_CACHE_TTL_NOT_MEMBER_SEC = 45.0
# Telegram can be slow from the server: never hold a shop request for long.
_TELEGRAM_TIMEOUT = httpx.Timeout(6.0, connect=4.0)
# Last definite answer per user, kept past the TTL for network failures.
_last_known: dict[int, bool] = {}


def normalize_channel(raw: str | None) -> str:
    value = (raw or "").strip()
    if not value:
        return ""
    if "t.me/" in value:
        value = value.split("t.me/", 1)[1]
    value = value.split("?", 1)[0].strip().strip("/")
    if value.startswith("@"):
        return value
    return f"@{value}"


def channel_username(settings: Settings) -> str:
    return normalize_channel(settings.required_channel).lstrip("@")


def channel_invite_url(settings: Settings) -> str:
    name = channel_username(settings)
    return f"https://t.me/{name}" if name else "https://t.me/"


def channel_gate_enabled(settings: Settings) -> bool:
    return bool(settings.force_join_channel and normalize_channel(settings.required_channel))


def channel_join_keyboard(settings: Settings) -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(
        [
            [InlineKeyboardButton("📣 عضویت در کانال", url=channel_invite_url(settings))],
            [InlineKeyboardButton("✅ عضو شدم — بررسی", callback_data="ch:check")],
        ]
    )


def channel_required_text(settings: Settings) -> str:
    name = channel_username(settings) or "کانال"
    return (
        f"برای استفاده از <b>{settings.shop_name}</b> باید عضو کانال شوید.\n\n"
        f"کانال: <b>@{name}</b>\n\n"
        "۱) روی «عضویت در کانال» بزنید و Join کنید\n"
        "۲) برگردید و «عضو شدم — بررسی» را بزنید"
    )


def channel_required_payload(settings: Settings) -> dict[str, Any]:
    return {
        "code": "channel_required",
        "channel": channel_username(settings),
        "invite_url": channel_invite_url(settings),
        "message": "برای استفاده از سرویس باید عضو کانال شوید",
    }


def _cache_get(user_id: int) -> bool | None:
    row = _cache.get(user_id)
    if not row:
        return None
    ok, expires = row
    if time.monotonic() > expires:
        _cache.pop(user_id, None)
        return None
    return ok


def _cache_set(user_id: int, ok: bool) -> None:
    ttl = _CACHE_TTL_MEMBER_SEC if ok else _CACHE_TTL_NOT_MEMBER_SEC
    _cache[user_id] = (ok, time.monotonic() + ttl)
    _last_known[user_id] = ok


def clear_channel_cache(user_id: int | None = None) -> None:
    if user_id is None:
        _cache.clear()
    else:
        _cache.pop(user_id, None)


def is_channel_member(settings: Settings, user_id: int, *, bypass_cache: bool = False) -> bool:
    if not channel_gate_enabled(settings):
        return True
    if not user_id:
        return False
    if settings.is_admin(user_id):
        return True
    if not bypass_cache:
        cached = _cache_get(user_id)
        if cached is not None:
            return cached

    chat_id = normalize_channel(settings.required_channel)
    last_error: str | None = None
    network_failed = False
    for token in settings.all_bot_tokens:
        try:
            with httpx.Client(timeout=_TELEGRAM_TIMEOUT) as http:
                resp = http.get(
                    f"https://api.telegram.org/bot{token}/getChatMember",
                    params={"chat_id": chat_id, "user_id": user_id},
                )
            data = resp.json() if resp.content else {}
            if data.get("ok"):
                status = str((data.get("result") or {}).get("status") or "")
                ok = status in _MEMBER_OK
                _cache_set(user_id, ok)
                return ok
            last_error = str(data.get("description") or resp.text or resp.status_code)
            # Bot may not be admin on this token — try the other bot.
            logger.warning("getChatMember failed chat=%s bot=…%s err=%s", chat_id, token[-6:], last_error)
        except httpx.TransportError as exc:
            # Telegram unreachable/slow: the same happens with every bot token, so stop here.
            last_error = str(exc) or exc.__class__.__name__
            network_failed = True
            logger.warning("getChatMember network error chat=%s user=%s err=%s", chat_id, user_id, last_error)
            break
        except Exception as exc:  # noqa: BLE001
            last_error = str(exc)
            logger.exception("getChatMember exception chat=%s user=%s", chat_id, user_id)

    if network_failed:
        # Don't lock people out because Telegram's API is unreachable: reuse the
        # last definite answer, or let them in if we never got one. Re-check soon.
        ok = _last_known.get(user_id, True)
        _cache[user_id] = (ok, time.monotonic() + _CACHE_TTL_NOT_MEMBER_SEC)
        return ok
    if last_error:
        logger.error("channel membership check failed user=%s err=%s", user_id, last_error)
    _cache_set(user_id, False)
    return False


async def enforce_channel_membership(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Block non-members early; allow admins and pass-through for members."""
    settings: Settings = context.application.bot_data["settings"]
    if not channel_gate_enabled(settings):
        return

    user = update.effective_user
    if not user:
        return
    if settings.is_admin(user.id):
        return

    cq = update.callback_query
    if cq and (cq.data or "") == "ch:check":
        await cq.answer()
        clear_channel_cache(user.id)
        if is_channel_member(settings, user.id, bypass_cache=True):
            text = (
                "✅ عضویت شما تایید شد.\n"
                "دوباره /start را بزنید یا فروشگاه را باز کنید."
            )
            try:
                await cq.edit_message_text(text)
            except Exception:
                if update.effective_chat:
                    await context.bot.send_message(update.effective_chat.id, text)
            raise ApplicationHandlerStop

        await cq.answer("هنوز عضو کانال نیستید — اول Join کنید.", show_alert=True)
        raise ApplicationHandlerStop

    if is_channel_member(settings, user.id):
        return

    text = channel_required_text(settings)
    kb = channel_join_keyboard(settings)
    if update.message:
        await update.message.reply_text(text, parse_mode=ParseMode.HTML, reply_markup=kb)
    elif cq:
        await cq.answer()
        try:
            await cq.edit_message_text(text, parse_mode=ParseMode.HTML, reply_markup=kb)
        except Exception:
            if cq.message:
                await cq.message.reply_text(text, parse_mode=ParseMode.HTML, reply_markup=kb)
    raise ApplicationHandlerStop
