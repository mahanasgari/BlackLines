from __future__ import annotations

import logging

import httpx
from telegram import Bot, BotCommand, MenuButtonWebApp, WebAppInfo
from telegram.ext import Application

from app.config import Settings

logger = logging.getLogger(__name__)

BOT_COMMANDS = [
    BotCommand("start", "Start / main menu"),
    BotCommand("open", "Open shop"),
    BotCommand("shop", "Open shop mini app"),
    BotCommand("help", "Help and support"),
]


def menu_button_payload(settings: Settings) -> MenuButtonWebApp | None:
    url = settings.miniapp_url_normalized
    if not url:
        return None
    return MenuButtonWebApp(
        text=settings.miniapp_menu_label,
        web_app=WebAppInfo(url=url),
    )


async def apply_open_menu_button(bot: Bot, settings: Settings, chat_id: int | None = None) -> bool:
    """Put Open on the Telegram message bar. Omit chat_id for the default (all PVs)."""
    button = menu_button_payload(settings)
    if not button:
        return False
    try:
        await bot.set_chat_menu_button(chat_id=chat_id, menu_button=button)
        return True
    except Exception:
        logger.exception("Failed to set Open menu button (chat_id=%s)", chat_id)
        return False


async def configure_bot_miniapp(application: Application) -> None:
    """Set the default chat menu button (Open) next to the message field."""
    settings: Settings = application.bot_data["settings"]
    url = settings.miniapp_url_normalized
    if not url:
        logger.warning("MINIAPP_URL is empty — skipping menu button setup")
        return

    role = application.bot_data.get("bot_role") or "Bot"
    try:
        me = await application.bot.get_me()
        ok = await apply_open_menu_button(application.bot, settings)
        await application.bot.set_my_commands(BOT_COMMANDS)
        current = await application.bot.get_chat_menu_button()
        current_type = getattr(current, "type", None)
        current_text = getattr(current, "text", None)
        has_main = bool(getattr(me, "has_main_web_app", False))
        logger.info(
            "Mini App Open button configured for %s @%s → %s (label=%s, type=%s, text=%s, profile_main_app=%s)",
            role,
            me.username,
            url,
            settings.miniapp_menu_label,
            current_type,
            current_text,
            has_main,
        )
        if not ok:
            logger.warning("setChatMenuButton returned false for %s @%s", role, me.username)
        if not has_main:
            logger.warning(
                "@%s has no Main Mini App — profile / bot-name Open button needs "
                "@BotFather → Bot Settings → Configure Mini App → %s",
                me.username,
                url,
            )
    except Exception:
        logger.exception("Failed to configure Mini App menu button (%s)", role)


def _setup_one_bot(client: httpx.Client, token: str, role: str, settings: Settings) -> dict:
    base = f"https://api.telegram.org/bot{token}"
    url = settings.miniapp_url_normalized
    result: dict = {"ok": False, "role": role, "username": None, "direct_link": None, "has_main_web_app": False}

    me_resp = client.get(f"{base}/getMe")
    me_resp.raise_for_status()
    me = me_resp.json().get("result") or {}
    username = me.get("username") or "bot"
    result["username"] = username
    result["has_main_web_app"] = bool(me.get("has_main_web_app"))
    short = settings.miniapp_short_name.strip().lower() or "shop"
    result["direct_link"] = f"https://t.me/{username}/{short}"

    menu_resp = client.post(
        f"{base}/setChatMenuButton",
        json={
            "menu_button": {
                "type": "web_app",
                "text": settings.miniapp_menu_label,
                "web_app": {"url": url},
            }
        },
    )
    menu_resp.raise_for_status()
    menu_ok = menu_resp.json().get("ok")

    cmds_resp = client.post(
        f"{base}/setMyCommands",
        json={
            "commands": [
                {"command": "start", "description": "Start / main menu"},
                {"command": "open", "description": "Open shop"},
                {"command": "shop", "description": "Open shop mini app"},
                {"command": "help", "description": "Help and support"},
            ]
        },
    )
    cmds_resp.raise_for_status()
    cmds_ok = cmds_resp.json().get("ok")

    result["ok"] = bool(menu_ok and cmds_ok)
    result["menu_button"] = menu_ok
    result["commands"] = cmds_ok
    return result


def setup_miniapp_via_http(settings: Settings) -> dict:
    """One-shot HTTP setup (menu button + commands) for all configured bots."""
    url = settings.miniapp_url_normalized
    bots: list[dict] = []
    with httpx.Client(timeout=30) as client:
        for role, token in settings.bot_roles:
            bots.append(_setup_one_bot(client, token, role, settings))

    primary = next((b for b in bots if b.get("role") == "MainBot"), None) or (bots[0] if bots else {})
    username = primary.get("username") or "bot"
    short = settings.miniapp_short_name.strip().lower() or "shop"
    domain = settings.public_host
    missing_main = [b.get("username") for b in bots if b.get("username") and not b.get("has_main_web_app")]
    steps = [
        f"1. Open @BotFather → /mybots → @{username} → Bot Settings",
        f"2. Run /setdomain and enter: {domain}",
        "3. Bot Settings → Configure Mini App → Enable Main Mini App",
        f"   Web App URL: {url}",
        f"4. Optional /newapp short name (ASCII): {short}",
        f"5. Direct Mini App link: https://t.me/{username}/{short}",
        "6. Restart Telegram if the Open button does not appear next to the message field",
        "7. Repeat Configure Mini App for each secondary bot",
    ]
    if missing_main:
        steps.insert(
            0,
            "Profile Open (tap bot name in PV) is missing until Main Mini App is enabled for: "
            + ", ".join(f"@{u}" for u in missing_main),
        )
    return {
        "ok": all(b.get("ok") for b in bots) if bots else False,
        "username": username,
        "direct_link": primary.get("direct_link") or f"https://t.me/{username}/{short}",
        "bots": bots,
        "steps": steps,
    }
