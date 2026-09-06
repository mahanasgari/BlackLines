from __future__ import annotations

import asyncio
import logging
import signal
from pathlib import Path

from telegram import Update
from telegram.ext import (
    Application,
    CallbackQueryHandler,
    CommandHandler,
    ConversationHandler,
    MessageHandler,
    TypeHandler,
    filters,
)

from app.config import get_settings
from app.channel_gate import enforce_channel_membership
from app.handlers.bot import (
    WAIT_BROADCAST,
    WAIT_CARD,
    WAIT_RECEIPT,
    WAIT_WITHDRAW_CARD,
    admin_approve,
    admin_broadcast_send,
    admin_broadcast_start,
    admin_card_save,
    admin_card_start,
    admin_panel,
    admin_pending,
    admin_plans,
    admin_reject,
    admin_stats,
    admin_withdraw_no,
    admin_withdraw_ok,
    admin_withdraws,
    cancel_receipt,
    cmd_disable_sub,
    cmd_extend,
    cmd_setminwithdraw,
    cmd_setprice,
    cmd_setrefpercent,
    cmd_toggleplan,
    help_cmd,
    menu_router,
    noop,
    on_buy,
    on_plan_select,
    on_receipt_photo,
    on_sub_links,
    referral_withdraw_card,
    referral_withdraw_start,
    show_referral,
    shop_cmd,
    start,
    on_trial_claim,
)
from app.models import make_session_factory
from app.servers import get_panel_hub, invalidate_panel_hub, sync_telegram_proxy_for_panel
from app.services import seed_defaults

logging.basicConfig(
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    level=logging.INFO,
)
logger = logging.getLogger("vpnshop")


async def _configure_miniapp(application: Application) -> None:
    from app.miniapp_setup import configure_bot_miniapp

    await configure_bot_miniapp(application)


def _register_handlers(app: Application) -> None:
    # Must run first: block non-members of required channel.
    app.add_handler(TypeHandler(Update, enforce_channel_membership), group=-1)

    buy_conv = ConversationHandler(
        entry_points=[CallbackQueryHandler(on_buy, pattern=r"^buy:\d+$")],
        states={
            WAIT_RECEIPT: [
                MessageHandler(filters.PHOTO | filters.Document.ALL, on_receipt_photo),
                CommandHandler("cancel", cancel_receipt),
            ],
        },
        fallbacks=[CommandHandler("cancel", cancel_receipt)],
        allow_reentry=True,
        name="buy_flow",
        persistent=False,
    )

    admin_conv = ConversationHandler(
        entry_points=[
            CallbackQueryHandler(admin_broadcast_start, pattern=r"^adm:broadcast$"),
            CallbackQueryHandler(admin_card_start, pattern=r"^adm:card$"),
        ],
        states={
            WAIT_BROADCAST: [
                MessageHandler(filters.TEXT & ~filters.COMMAND, admin_broadcast_send),
                CommandHandler("cancel", cancel_receipt),
            ],
            WAIT_CARD: [
                MessageHandler(filters.TEXT & ~filters.COMMAND, admin_card_save),
                CommandHandler("cancel", cancel_receipt),
            ],
        },
        fallbacks=[CommandHandler("cancel", cancel_receipt)],
        allow_reentry=True,
        name="admin_flow",
        persistent=False,
    )

    withdraw_conv = ConversationHandler(
        entry_points=[CallbackQueryHandler(referral_withdraw_start, pattern=r"^ref:withdraw$")],
        states={
            WAIT_WITHDRAW_CARD: [
                MessageHandler(filters.TEXT & ~filters.COMMAND, referral_withdraw_card),
                CommandHandler("cancel", cancel_receipt),
            ],
        },
        fallbacks=[CommandHandler("cancel", cancel_receipt)],
        allow_reentry=True,
        name="withdraw_flow",
        persistent=False,
    )

    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("open", shop_cmd))
    app.add_handler(CommandHandler("shop", shop_cmd))
    app.add_handler(CommandHandler("help", help_cmd))
    app.add_handler(CommandHandler("admin", admin_panel))
    app.add_handler(CommandHandler("setprice", cmd_setprice))
    app.add_handler(CommandHandler("toggleplan", cmd_toggleplan))
    app.add_handler(CommandHandler("disable", cmd_disable_sub))
    app.add_handler(CommandHandler("extend", cmd_extend))
    app.add_handler(CommandHandler("setrefpercent", cmd_setrefpercent))
    app.add_handler(CommandHandler("setminwithdraw", cmd_setminwithdraw))

    app.add_handler(buy_conv)
    app.add_handler(admin_conv)
    app.add_handler(withdraw_conv)

    app.add_handler(CallbackQueryHandler(on_trial_claim, pattern=r"^trial:claim$"))
    app.add_handler(CallbackQueryHandler(on_plan_select, pattern=r"^plan:\d+$"))
    app.add_handler(CallbackQueryHandler(on_sub_links, pattern=r"^sub:links:\d+$"))
    app.add_handler(CallbackQueryHandler(show_referral, pattern=r"^ref:refresh$"))
    app.add_handler(CallbackQueryHandler(admin_pending, pattern=r"^adm:pending$"))
    app.add_handler(CallbackQueryHandler(admin_withdraws, pattern=r"^adm:withdraws$"))
    app.add_handler(CallbackQueryHandler(admin_plans, pattern=r"^adm:plans$"))
    app.add_handler(CallbackQueryHandler(admin_stats, pattern=r"^adm:stats$"))
    app.add_handler(CallbackQueryHandler(admin_approve, pattern=r"^adm:ok:\d+$"))
    app.add_handler(CallbackQueryHandler(admin_reject, pattern=r"^adm:no:\d+$"))
    app.add_handler(CallbackQueryHandler(admin_withdraw_ok, pattern=r"^adm:wdok:\d+$"))
    app.add_handler(CallbackQueryHandler(admin_withdraw_no, pattern=r"^adm:wdno:\d+$"))
    app.add_handler(CallbackQueryHandler(noop, pattern=r"^noop$"))

    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, menu_router))


def build_application(
    *,
    token: str,
    role: str,
    settings,
    session_factory,
    panel,
) -> Application:
    app = (
        Application.builder()
        .token(token)
        .post_init(_configure_miniapp)
        .build()
    )
    app.bot_data["settings"] = settings
    app.bot_data["session_factory"] = session_factory
    app.bot_data["panel"] = panel
    app.bot_data["bot_role"] = role
    _register_handlers(app)
    return app


async def _run_apps(apps: list[Application]) -> None:
    stop = asyncio.Event()

    def _request_stop(*_args) -> None:
        stop.set()

    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, _request_stop)
        except NotImplementedError:
            pass

    for app in apps:
        await app.initialize()
        await app.start()
        assert app.updater is not None
        await app.updater.start_polling(allowed_updates=["message", "callback_query"])
        me = await app.bot.get_me()
        role = app.bot_data.get("bot_role") or "Bot"
        logger.info("Started %s @%s", role, me.username)

    await stop.wait()

    for app in apps:
        if app.updater:
            await app.updater.stop()
        await app.stop()
        await app.shutdown()
    invalidate_panel_hub()


def main() -> None:
    settings = get_settings()

    db_url = settings.database_url
    if db_url.startswith("sqlite:///"):
        db_path = db_url.replace("sqlite:///", "", 1)
        Path(db_path).parent.mkdir(parents=True, exist_ok=True)

    session_factory = make_session_factory(db_url)
    with session_factory() as session:
        seed_defaults(session)
        panel = get_panel_hub(settings, session)
        try:
            panel.prepare_telegram_proxy()
            for member in panel.members:
                sync_telegram_proxy_for_panel(session, member)
        except Exception:
            logger.exception("telegram proxy startup sync failed")

    roles = settings.bot_roles
    if not roles:
        raise SystemExit("No bot tokens configured (BOT_TOKEN / MAIN_BOT_TOKEN)")

    apps = [
        build_application(
            token=token,
            role=role,
            settings=settings,
            session_factory=session_factory,
            panel=panel,
        )
        for role, token in roles
    ]
    logger.info("Starting %s with %s bot(s)…", settings.shop_name, len(apps))
    asyncio.run(_run_apps(apps))


if __name__ == "__main__":
    main()
