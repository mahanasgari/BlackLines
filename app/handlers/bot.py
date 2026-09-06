from __future__ import annotations

import html
import logging
import secrets
from sqlalchemy import func, select
from sqlalchemy.orm import Session, sessionmaker
from telegram import Update
from telegram.constants import ParseMode
from telegram.ext import ContextTypes, ConversationHandler

from app.config import Settings
from app.keyboards import (
    OPEN_BUTTON_ALIASES,
    admin_menu_keyboard,
    admin_order_keyboard,
    admin_withdraw_keyboard,
    confirm_buy_keyboard,
    main_menu,
    miniapp_inline,
    trial_claim_keyboard,
    order_admin_text,
    plan_detail_text,
    plans_keyboard,
    referral_keyboard,
    subscription_keyboard,
    withdraw_admin_text,
)
from app.miniapp_setup import apply_open_menu_button
from app.models import Order, OrderStatus, Plan, Subscription, User, Withdrawal
from app.panel import PanelError, XUIPanel, build_subscription_url
from app.services import (
    add_payment_card,
    approve_wallet_deposit,
    approve_pro_subscription,
    approve_payg_topup,
    approve_renew_subscription,
    approve_withdrawal,
    attach_subscription,
    bind_referrer,
    cancel_order,
    create_order,
    create_withdrawal,
    credit_referral_commission,
    format_price,
    get_or_create_user,
    get_order,
    get_plan,
    get_setting,
    is_payg_order,
    is_wallet_topup,
    is_platform_pro,
    is_pro_only_shop_plan,
    is_user_pro,
    order_plan_title,
    order_provision_params,
    pro_discount_percent,
    list_enabled_plans,
    fulfill_pending_order,
    maybe_auto_fulfill_prepaid_order,
    list_admin_telegram_ids,
    is_telegram_admin,
    list_pending_orders,
    list_pending_withdrawals,
    trial_offer_dict,
    claim_user_trial,
    trial_send_links_enabled,
    min_withdraw_amount,
    wallet_withdrawable,
    PendingOrderError,
    referral_stats,
    reject_order,
    reject_withdrawal,
    set_setting,
    traffic_label,
    user_active_subscriptions,
)
from app.texts import (
    payment_text,
    referral_text,
    subscription_link_message,
    support_text,
    trial_activated_text,
    trial_offer_text,
    welcome,
)

logger = logging.getLogger(__name__)

WAIT_RECEIPT, WAIT_BROADCAST, WAIT_CARD, WAIT_WITHDRAW_CARD = range(4)


def _audit(session, update: Update, action: str, **kwargs) -> None:
    from app.ops import record_audit

    actor = None
    if update.effective_user:
        actor, _ = get_or_create_user(
            session,
            update.effective_user.id,
            update.effective_user.username,
            update.effective_user.full_name,
        )
    admin_actions = {
        "approve_order",
        "reject_order",
        "approve_withdraw",
        "reject_withdraw",
    }
    path = "bot/admin" if action in admin_actions else "bot"
    try:
        record_audit(session, actor=actor, action=action, path=path, **kwargs)
    except Exception:
        logger.exception("bot activity log failed")


def _settings(context: ContextTypes.DEFAULT_TYPE) -> Settings:
    return context.application.bot_data["settings"]


def _sessions(context: ContextTypes.DEFAULT_TYPE) -> sessionmaker:
    return context.application.bot_data["session_factory"]


def _panel(context: ContextTypes.DEFAULT_TYPE):
    from app.servers import get_panel_hub

    settings = _settings(context)
    session = _session(context)
    try:
        return get_panel_hub(settings, session)
    finally:
        session.close()


def _session(context: ContextTypes.DEFAULT_TYPE) -> Session:
    return _sessions(context)()


async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not update.effective_user or not update.message:
        return
    settings = _settings(context)
    referrer_code = None
    if context.args:
        raw = context.args[0].strip()
        if raw.lower().startswith("ref_"):
            referrer_code = raw[4:]
        else:
            referrer_code = raw
    with _session(context) as session:
        user, _is_new = get_or_create_user(
            session,
            update.effective_user.id,
            update.effective_user.username,
            update.effective_user.full_name,
            referrer_code=referrer_code,
        )
        # if existing user without referrer and deep-link present, still try once
        if referrer_code and not user.referred_by_id:
            bind_referrer(session, user, referrer_code)
        is_admin = is_telegram_admin(session, update.effective_user.id, settings)
        offer = trial_offer_dict(session, user)
    await apply_open_menu_button(context.bot, settings, chat_id=update.effective_user.id)
    await update.message.reply_text(
        welcome(settings),
        parse_mode=ParseMode.HTML,
        reply_markup=main_menu(is_admin, settings.miniapp_url_normalized),
    )
    kb = miniapp_inline(settings.miniapp_url_normalized)
    if offer.get("available"):
        await update.message.reply_text(
            trial_offer_text(int(offer["duration_days"]), str(offer["traffic_label"])),
            parse_mode=ParseMode.HTML,
            reply_markup=trial_claim_keyboard(),
        )
    elif kb:
        await update.message.reply_text(
            "فروشگاه را به‌صورت مینی‌اپ باز کنید:",
            reply_markup=kb,
        )


async def on_trial_claim(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    query = update.callback_query
    if not query or not update.effective_user:
        return
    await query.answer("در حال ساخت کانفیگ تست…")
    settings = _settings(context)
    with _session(context) as session:
        user, _ = get_or_create_user(
            session,
            update.effective_user.id,
            update.effective_user.username,
            update.effective_user.full_name,
        )
        try:
            trial = claim_user_trial(session, user, _panel(context), settings, notify=False)
        except ValueError as exc:
            code = str(exc)
            messages = {
                "already_granted": "قبلاً کانفیگ تست گرفته‌اید.",
                "trial_disabled": "حساب تست فعلاً غیرفعال است.",
                "already_has_config": "چون قبلاً کانفیگ دارید، تست رایگان فعال نمی‌شود.",
            }
            await query.edit_message_text(messages.get(code, "دریافت تست ممکن نیست."))
            return
        except Exception:
            logger.exception("trial claim failed tg=%s", update.effective_user.id)
            await query.edit_message_text("ساخت کانفیگ تست ناموفق بود. کمی بعد دوباره تلاش کنید.")
            return
        send_links = trial_send_links_enabled(session)
    kb = miniapp_inline(settings.miniapp_url_normalized)
    try:
        await query.edit_message_text(
            trial_activated_text(),
            parse_mode=ParseMode.HTML,
            reply_markup=kb,
        )
    except Exception:  # noqa: BLE001
        pass
    if send_links:
        await context.bot.send_message(
            chat_id=update.effective_user.id,
            text=subscription_link_message(
                email=trial.get("email") or "",
                sub_url=trial.get("subscription_url"),
                title="🎁 لینک اشتراک تست",
            ),
            parse_mode=ParseMode.HTML,
            disable_web_page_preview=True,
        )


async def shop_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not update.message:
        return
    settings = _settings(context)
    if update.effective_user:
        await apply_open_menu_button(context.bot, settings, chat_id=update.effective_user.id)
    kb = miniapp_inline(settings.miniapp_url_normalized)
    text = (
        f"🛍 <b>{settings.shop_name}</b>\n\n"
        "دکمه <b>Open</b> کنار کادر پیام را بزنید، یا از دکمه پایین استفاده کنید.\n"
        "روی اسم ربات بالای همین پیوی هم می‌توانید Open را ببینید."
    )
    if kb:
        await update.message.reply_text(text, parse_mode=ParseMode.HTML, reply_markup=kb)
    else:
        await update.message.reply_text(text, parse_mode=ParseMode.HTML)


async def help_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if update.message:
        await update.message.reply_text(support_text())


async def show_plans(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not update.message:
        return
    with _session(context) as session:
        user = None
        if update.effective_user:
            user, _ = get_or_create_user(
                session,
                update.effective_user.id,
                update.effective_user.username,
                update.effective_user.full_name,
            )
        plans = list_enabled_plans(session, user)
    if not plans:
        await update.message.reply_text("هنوز پلنی فعال نیست. با ادمین تماس بگیرید.")
        return
    await update.message.reply_text(
        "یک پلن انتخاب کنید:",
        reply_markup=plans_keyboard(plans),
    )


async def on_plan_select(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    query = update.callback_query
    if not query or not query.data:
        return
    await query.answer()
    plan_id = int(query.data.split(":")[1])
    with _session(context) as session:
        plan = get_plan(session, plan_id)
        if not plan or not plan.enabled:
            await query.edit_message_text("این پلن موجود نیست.")
            return
        if is_pro_only_shop_plan(plan):
            buyer = None
            if update.effective_user:
                buyer, _ = get_or_create_user(
                    session,
                    update.effective_user.id,
                    update.effective_user.username,
                    update.effective_user.full_name,
                )
            if not buyer or not is_user_pro(buyer):
                await query.edit_message_text("پلن نامحدود فقط برای اعضای Pro است.")
                return
        text = plan_detail_text(plan)
    await query.edit_message_text(
        text,
        parse_mode=ParseMode.HTML,
        reply_markup=confirm_buy_keyboard(plan_id),
    )


async def on_buy(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    query = update.callback_query
    if not query or not query.data or not update.effective_user:
        return ConversationHandler.END
    await query.answer()
    plan_id = int(query.data.split(":")[1])
    settings = _settings(context)
    with _session(context) as session:
        user, _ = get_or_create_user(
            session,
            update.effective_user.id,
            update.effective_user.username,
            update.effective_user.full_name,
        )
        plan = get_plan(session, plan_id)
        if not plan or not plan.enabled:
            await query.edit_message_text("این پلن موجود نیست.")
            return ConversationHandler.END
        try:
            order = create_order(session, user, plan)
            _audit(
                session,
                update,
                "create_order",
                target_user=user,
                detail=f"order_id={order.id} plan={plan.title} via=bot",
                category="shop",
            )
        except PendingOrderError:
            await query.edit_message_text(
                "یک سفارش ناتمام دارید. ابتدا آن را تکمیل یا با /cancel لغو کنید."
            )
            return ConversationHandler.END
        except ValueError as exc:
            if str(exc) == "plan_pro_only":
                await query.edit_message_text("پلن نامحدود فقط برای اعضای Pro است.")
            else:
                await query.edit_message_text("این پلن فعلاً در دسترس نیست.")
            return ConversationHandler.END
        auto_ok = False
        if order.amount_toman <= 0 and not is_wallet_topup(plan):
            auto_ok = bool(
                maybe_auto_fulfill_prepaid_order(session, _panel(context), settings, order)
            )
        context.user_data["pending_order_id"] = order.id
        # pull live card overrides from DB if set
        card = get_setting(session, "payment_card", settings.payment_card)
        name = get_setting(session, "payment_card_name", settings.payment_card_name)
        note = get_setting(session, "payment_note", settings.payment_note)
        pay_settings = settings.model_copy(
            update={
                "payment_card": card,
                "payment_card_name": name,
                "payment_note": note,
            }
        )
        amount = order.amount_toman
        wallet_used = order.wallet_used or 0
        order_id = order.id

    extra = ""
    if wallet_used:
        extra = f"\n\n👛 {format_price(wallet_used)} از کیف‌پول کم شد."
    if amount <= 0:
        if auto_ok:
            await query.edit_message_text(
                f"سفارش #{order_id} با کیف‌پول پرداخت شد و اشتراک فعال شد.{extra}\n"
                "لینک‌ها در تلگرام و مینی‌اپ ارسال شد.",
                parse_mode=ParseMode.HTML,
            )
        else:
            await query.edit_message_text(
                f"سفارش #{order_id} ثبت شد.{extra}\n"
                "مبلغ قابل پرداخت صفر است — رسید لازم نیست. منتظر تایید ادمین بمانید.",
                parse_mode=ParseMode.HTML,
            )
            for admin_id in settings.admin_ids:
                try:
                    with _session(context) as session:
                        order = get_order(session, int(order_id))
                        text = order_admin_text(order) if order else f"سفارش #{order_id}"
                    await context.bot.send_message(
                        chat_id=admin_id,
                        text=text + "\n(پرداخت کامل با کیف‌پول)",
                        parse_mode=ParseMode.HTML,
                        reply_markup=admin_order_keyboard(int(order_id)),
                    )
                except Exception:  # noqa: BLE001
                    logger.exception("Failed notifying admin %s", admin_id)
        context.user_data.pop("pending_order_id", None)
        return ConversationHandler.END

    await query.edit_message_text(
        f"سفارش #{order_id} ثبت شد.{extra}\n\n{payment_text(pay_settings, amount)}",
        parse_mode=ParseMode.HTML,
    )
    if query.message:
        await query.message.reply_text("📸 الان عکس رسید بانکی را ارسال کنید.")
    return WAIT_RECEIPT


async def on_receipt_photo(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    if not update.message or not update.effective_user:
        return WAIT_RECEIPT
    order_id = context.user_data.get("pending_order_id")
    if not order_id:
        await update.message.reply_text("سفارش فعالی نیست. از منو «خرید اشتراک» را بزنید.")
        return ConversationHandler.END

    photo = update.message.photo[-1] if update.message.photo else None
    document = update.message.document
    file_id = photo.file_id if photo else (document.file_id if document else None)
    if not file_id:
        await update.message.reply_text("لطفاً عکس یا فایل رسید را بفرستید.")
        return WAIT_RECEIPT

    settings = _settings(context)
    with _session(context) as session:
        order = get_order(session, int(order_id))
        if not order or order.status != OrderStatus.PENDING:
            await update.message.reply_text("این سفارش دیگر قابل پرداخت نیست.")
            return ConversationHandler.END
        if order.user.telegram_id != update.effective_user.id:
            await update.message.reply_text("دسترسی ندارید.")
            return ConversationHandler.END
        order.receipt_file_id = file_id
        session.commit()
        _audit(
            session,
            update,
            "upload_receipt",
            target_user=order.user,
            detail=f"order_id={order.id} via=bot",
            category="shop",
        )
        admin_caption = order_admin_text(order)

    await update.message.reply_text(
        f"رسید سفارش #{order_id} دریافت شد.\nپس از تایید ادمین، کانفیگ برایتان ارسال می‌شود."
    )

    for admin_id in settings.admin_ids:
        try:
            await context.bot.send_photo(
                chat_id=admin_id,
                photo=file_id,
                caption=admin_caption,
                parse_mode=ParseMode.HTML,
                reply_markup=admin_order_keyboard(int(order_id)),
            )
        except Exception:  # noqa: BLE001
            logger.exception("Failed notifying admin %s", admin_id)

    context.user_data.pop("pending_order_id", None)
    return ConversationHandler.END


async def cancel_receipt(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    order_id = context.user_data.pop("pending_order_id", None)
    if order_id:
        with _session(context) as session:
            order = get_order(session, int(order_id))
            if order and order.status == OrderStatus.PENDING:
                cancel_order(session, order, note="cancelled_via_bot")
                _audit(
                    session,
                    update,
                    "cancel_order",
                    target_user=order.user,
                    detail=f"order_id={order.id} via=bot",
                    category="shop",
                )
    if update.message:
        await update.message.reply_text("سفارش لغو شد و موجودی کیف‌پول برگردانده شد.")
    return ConversationHandler.END


async def my_subscriptions(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not update.message or not update.effective_user:
        return
    with _session(context) as session:
        user, _ = get_or_create_user(
            session,
            update.effective_user.id,
            update.effective_user.username,
            update.effective_user.full_name,
        )
        subs = user_active_subscriptions(session, user.id)
        if not subs:
            await update.message.reply_text("اشتراک فعالی ندارید.")
            return
        for sub in subs:
            exp = sub.expires_at.strftime("%Y-%m-%d") if sub.expires_at else "نامحدود"
            text = (
                f"📦 {sub.plan.title}\n"
                f"شناسه: <code>{html.escape(sub.xui_email)}</code>\n"
                f"انقضا: {exp}\n"
                f"ترافیک: {traffic_label(sub.plan.traffic_gb)}"
            )
            await update.message.reply_text(
                text,
                parse_mode=ParseMode.HTML,
                reply_markup=subscription_keyboard(sub.id),
            )


async def on_sub_links(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    query = update.callback_query
    if not query or not query.data or not update.effective_user:
        return
    await query.answer()
    sub_id = int(query.data.split(":")[2])
    settings = _settings(context)
    with _session(context) as session:
        sub = session.get(Subscription, sub_id)
        if not sub or not sub.enabled:
            await query.edit_message_text("اشتراک پیدا نشد.")
            return
        user = session.get(User, sub.user_id)
        if not user or user.telegram_id != update.effective_user.id:
            if not is_telegram_admin(session, update.effective_user.id, settings):
                await query.answer("دسترسی ندارید", show_alert=True)
                return
        email = sub.xui_email
        label = (sub.label or "").strip() or (sub.plan.title if sub.plan else None)
        sub_url = build_subscription_url(sub.xui_sub_id, settings)
    await query.message.reply_text(
        subscription_link_message(email=email, sub_url=sub_url, label=label, title="🔗 لینک اشتراک"),
        parse_mode=ParseMode.HTML,
        disable_web_page_preview=True,
    )


async def payment_help(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not update.message:
        return
    settings = _settings(context)
    with _session(context) as session:
        card = get_setting(session, "payment_card", settings.payment_card)
        name = get_setting(session, "payment_card_name", settings.payment_card_name)
        note = get_setting(session, "payment_note", settings.payment_note)
    pay = settings.model_copy(
        update={"payment_card": card, "payment_card_name": name, "payment_note": note}
    )
    await update.message.reply_text(payment_text(pay), parse_mode=ParseMode.HTML)


async def support(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if update.message:
        await update.message.reply_text(support_text())


async def noop(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    query = update.callback_query
    if query:
        await query.answer()
        with contextlib_suppress():
            await query.edit_message_reply_markup(reply_markup=None)


class contextlib_suppress:
    def __enter__(self):
        return self

    def __exit__(self, *args):
        return True


# ---- Admin ----


def _require_admin(update: Update, context: ContextTypes.DEFAULT_TYPE) -> bool:
    user = update.effective_user
    if not user:
        return False
    with _session(context) as session:
        return is_telegram_admin(session, user.id, _settings(context))


async def admin_panel(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not update.message:
        return
    if not _require_admin(update, context):
        await update.message.reply_text("دسترسی ادمین ندارید.")
        return
    await update.message.reply_text("🛠 پنل ادمین", reply_markup=admin_menu_keyboard())


async def admin_pending(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    query = update.callback_query
    if not query:
        return
    if not _require_admin(update, context):
        await query.answer("ادمین نیستید", show_alert=True)
        return
    await query.answer()
    with _session(context) as session:
        orders = list_pending_orders(session, include_test=False)
        if not orders:
            await query.edit_message_text("سفارش در انتظاری نیست.")
            return
        await query.edit_message_text(f"{len(orders)} سفارش در انتظار:")
        for order in orders[:20]:
            text = order_admin_text(order)
            if order.receipt_file_id and order.receipt_file_id != "miniapp-uploaded":
                try:
                    await context.bot.send_document(
                        chat_id=query.from_user.id,
                        document=order.receipt_file_id,
                        caption=text,
                        parse_mode=ParseMode.HTML,
                        reply_markup=admin_order_keyboard(order.id),
                    )
                except Exception:  # noqa: BLE001
                    try:
                        await context.bot.send_photo(
                            chat_id=query.from_user.id,
                            photo=order.receipt_file_id,
                            caption=text,
                            parse_mode=ParseMode.HTML,
                            reply_markup=admin_order_keyboard(order.id),
                        )
                    except Exception:  # noqa: BLE001
                        await context.bot.send_message(
                            chat_id=query.from_user.id,
                            text=text + "\n(رسید قابل نمایش نیست)",
                            parse_mode=ParseMode.HTML,
                            reply_markup=admin_order_keyboard(order.id),
                        )
            else:
                await context.bot.send_message(
                    chat_id=query.from_user.id,
                    text=text + ("\n(رسید دارد)" if order.receipt_file_id else "\n(بدون رسید)"),
                    parse_mode=ParseMode.HTML,
                    reply_markup=admin_order_keyboard(order.id),
                )


async def admin_approve(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    query = update.callback_query
    if not query or not query.data:
        return
    if not _require_admin(update, context):
        await query.answer("ادمین نیستید", show_alert=True)
        return
    order_id = int(query.data.split(":")[2])
    await query.answer("در حال ساخت کانفیگ…")
    settings = _settings(context)
    panel = _panel(context)
    caption = ""

    with _session(context) as session:
        order = get_order(session, order_id)
        if not order:
            await query.edit_message_caption(caption="سفارش پیدا نشد.")
            return
        if order.status != OrderStatus.PENDING:
            await query.answer(f"وضعیت فعلی: {order.status}", show_alert=True)
            return
        admin_user, _ = get_or_create_user(
            session,
            query.from_user.id,
            query.from_user.username,
            query.from_user.full_name,
        )
        try:
            result = fulfill_pending_order(
                session,
                panel,
                settings,
                order,
                actor=admin_user,
                via="bot",
            )
        except PanelError as exc:
            logger.exception("panel fulfill failed")
            if query.message:
                await query.message.reply_text(f"خطای پنل: {exc}")
            return
        except ValueError as exc:
            if query.message:
                await query.message.reply_text(f"خطا: {exc}")
            return
        caption = order_admin_text(order) + "\n\n✅ تایید شد"
        if result.get("email"):
            caption += f" → {result['email']}"
        elif result.get("pro_until"):
            caption += f"\nPro تا {str(result['pro_until'])[:10]}"
        elif result.get("wallet_credited"):
            caption += f"\nشارژ کیف‌پول: {format_price(int(result['wallet_credited']))}"
        elif result.get("renewed"):
            caption += "\nتمدید / شارژ انجام شد"

    try:
        if query.message and (query.message.photo or query.message.document):
            await query.edit_message_caption(caption=caption, parse_mode=ParseMode.HTML)
        else:
            await query.edit_message_text(caption, parse_mode=ParseMode.HTML)
    except Exception:  # noqa: BLE001
        pass


async def admin_reject(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    query = update.callback_query
    if not query or not query.data:
        return
    if not _require_admin(update, context):
        await query.answer("ادمین نیستید", show_alert=True)
        return
    order_id = int(query.data.split(":")[2])
    await query.answer()
    with _session(context) as session:
        order = get_order(session, order_id)
        if not order or order.status != OrderStatus.PENDING:
            await query.answer("قابل رد نیست", show_alert=True)
            return
        reject_order(session, order, note="rejected_by_admin")
        _audit(
            session,
            update,
            "reject_order",
            target_user=order.user,
            detail=f"order_id={order.id} via=bot",
            category="shop",
        )
        tg_id = order.user.telegram_id
    try:
        await query.edit_message_caption(caption=f"سفارش #{order_id} رد شد ❌")
    except Exception:  # noqa: BLE001
        await query.edit_message_text(f"سفارش #{order_id} رد شد ❌")
    await context.bot.send_message(
        chat_id=tg_id,
        text=f"سفارش #{order_id} رد شد. اگر اشتباهی رخ داده با پشتیبانی تماس بگیرید.",
    )


async def admin_plans(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    query = update.callback_query
    if not query or not _require_admin(update, context):
        return
    await query.answer()
    with _session(context) as session:
        plans = list(session.scalars(select(Plan).order_by(Plan.sort_order)).all())
    lines = ["📋 پلن‌ها\n"]
    for p in plans:
        flag = "✅" if p.enabled else "⏸"
        lines.append(
            f"{flag} #{p.id} {p.title} — {format_price(p.price_toman)} "
            f"({p.duration_days}d / {traffic_label(p.traffic_gb)})"
        )
    lines.append("\nبرای ویرایش قیمت از دستور زیر استفاده کنید:")
    lines.append("<code>/setprice PLAN_ID PRICE</code>")
    lines.append("<code>/toggleplan PLAN_ID</code>")
    await query.edit_message_text("\n".join(lines), parse_mode=ParseMode.HTML)


async def admin_stats(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    query = update.callback_query
    if not query or not _require_admin(update, context):
        return
    await query.answer()
    with _session(context) as session:
        skip = set(session.scalars(select(User.id).where(User.is_test.is_(True))).all())
        user_q = select(func.count()).select_from(User)
        pending_q = select(func.count()).select_from(Order).where(Order.status == OrderStatus.PENDING)
        approved_q = select(func.count()).select_from(Order).where(Order.status == OrderStatus.APPROVED)
        sub_q = select(func.count()).select_from(Subscription).where(Subscription.enabled.is_(True))
        revenue_q = select(func.coalesce(func.sum(Order.amount_toman), 0)).where(
            Order.status == OrderStatus.APPROVED
        )
        referred_q = select(func.count()).select_from(User).where(User.referred_by_id.is_not(None))
        if skip:
            user_q = user_q.where(~User.id.in_(skip))
            pending_q = pending_q.where(~Order.user_id.in_(skip))
            approved_q = approved_q.where(~Order.user_id.in_(skip))
            sub_q = sub_q.where(~Subscription.user_id.in_(skip))
            revenue_q = revenue_q.where(~Order.user_id.in_(skip))
            referred_q = referred_q.where(~User.id.in_(skip))
        users = session.scalar(user_q) or 0
        pending = session.scalar(pending_q) or 0
        approved = session.scalar(approved_q) or 0
        active_subs = session.scalar(sub_q) or 0
        revenue = session.scalar(revenue_q) or 0
        from app.models import Commission

        comm_q = select(func.coalesce(func.sum(Commission.amount_toman), 0))
        if skip:
            comm_q = comm_q.where(~Commission.referrer_id.in_(skip), ~Commission.referred_id.in_(skip))
        commissions = session.scalar(comm_q) or 0
        referred_users = session.scalar(referred_q) or 0
        percent = get_setting(session, "referral_percent", "15")
        min_w = get_setting(session, "min_withdraw", "100000")
    await query.edit_message_text(
        "📊 آمار\n"
        f"کاربران: {users}\n"
        f"دعوت‌شده‌ها: {referred_users}\n"
        f"سفارش در انتظار: {pending}\n"
        f"سفارش تاییدشده: {approved}\n"
        f"اشتراک فعال: {active_subs}\n"
        f"درآمد تاییدشده: {format_price(int(revenue))}\n"
        f"مجموع پورسانت پرداختی: {format_price(int(commissions))}\n"
        f"نرخ دعوت: {percent}%\n"
        f"حداقل برداشت: {format_price(int(min_w))}"
    )


async def show_referral(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    message = update.message or (update.callback_query.message if update.callback_query else None)
    user = update.effective_user
    if not message or not user:
        return
    me = await context.bot.get_me()
    with _session(context) as session:
        db_user, _ = get_or_create_user(session, user.id, user.username, user.full_name)
        stats = referral_stats(session, db_user)
    text = referral_text(stats, me.username or "bot")
    kb = referral_keyboard(int(stats.get("withdrawable") or stats["wallet"]) >= stats["min_withdraw"])
    if update.callback_query:
        await update.callback_query.answer()
        await update.callback_query.edit_message_text(
            text, parse_mode=ParseMode.HTML, reply_markup=kb, disable_web_page_preview=True
        )
    else:
        await message.reply_text(
            text, parse_mode=ParseMode.HTML, reply_markup=kb, disable_web_page_preview=True
        )


async def referral_withdraw_start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    query = update.callback_query
    if not query or not update.effective_user:
        return ConversationHandler.END
    await query.answer()
    with _session(context) as session:
        user, _ = get_or_create_user(
            session,
            update.effective_user.id,
            update.effective_user.username,
            update.effective_user.full_name,
        )
        min_w = min_withdraw_amount(session)
        balance = wallet_withdrawable(user)
    if balance < min_w:
        await query.answer(
            f"حداقل برداشت {format_price(min_w)} است",
            show_alert=True,
        )
        return ConversationHandler.END
    context.user_data["withdraw_amount"] = balance
    await query.message.reply_text(
        f"موجودی قابل برداشت: <b>{format_price(balance)}</b>\n"
        "شماره کارت مقصد را ارسال کنید (یا /cancel):",
        parse_mode=ParseMode.HTML,
    )
    return WAIT_WITHDRAW_CARD


async def referral_withdraw_card(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    if not update.message or not update.effective_user:
        return WAIT_WITHDRAW_CARD
    card = (update.message.text or "").strip().replace(" ", "").replace("-", "")
    if not card.isdigit() or len(card) < 12:
        await update.message.reply_text("شماره کارت معتبر نیست. دوباره بفرستید.")
        return WAIT_WITHDRAW_CARD
    amount = int(context.user_data.get("withdraw_amount") or 0)
    settings = _settings(context)
    with _session(context) as session:
        user, _ = get_or_create_user(
            session,
            update.effective_user.id,
            update.effective_user.username,
            update.effective_user.full_name,
        )
        # withdraw full available (non-locked) balance
        amount = min(amount, wallet_withdrawable(user))
        wd = create_withdrawal(session, user, amount, card)
        if wd:
            _audit(
                session,
                update,
                "withdraw_request",
                target_user=user,
                detail=f"withdraw_id={wd.id} amount={amount} via=bot",
                category="wallet",
            )
        if not wd:
            min_w = min_withdraw_amount(session)
            await update.message.reply_text(
                f"برداشت ممکن نیست. حداقل {format_price(min_w)} و بدون درخواست باز."
            )
            return ConversationHandler.END
        text = withdraw_admin_text(wd)
        wd_id = wd.id

    await update.message.reply_text(
        f"درخواست برداشت #{wd_id} ثبت شد.\nپس از واریز ادمین، اطلاع داده می‌شود."
    )
    for admin_id in settings.admin_ids:
        try:
            await context.bot.send_message(
                chat_id=admin_id,
                text=text,
                parse_mode=ParseMode.HTML,
                reply_markup=admin_withdraw_keyboard(wd_id),
            )
        except Exception:  # noqa: BLE001
            logger.exception("Failed notifying admin about withdraw")
    context.user_data.pop("withdraw_amount", None)
    return ConversationHandler.END


async def admin_withdraws(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    query = update.callback_query
    if not query or not _require_admin(update, context):
        return
    await query.answer()
    with _session(context) as session:
        items = list_pending_withdrawals(session, include_test=False)
        if not items:
            await query.edit_message_text("درخواست برداشت بازی نیست.")
            return
        await query.edit_message_text(f"{len(items)} درخواست برداشت:")
        for wd in items[:20]:
            await context.bot.send_message(
                chat_id=query.from_user.id,
                text=withdraw_admin_text(wd),
                parse_mode=ParseMode.HTML,
                reply_markup=admin_withdraw_keyboard(wd.id),
            )


async def admin_withdraw_ok(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    query = update.callback_query
    if not query or not query.data or not _require_admin(update, context):
        return
    wd_id = int(query.data.split(":")[2])
    await query.answer()
    with _session(context) as session:
        wd = session.get(Withdrawal, wd_id)
        if not wd or wd.status != "pending":
            await query.answer("قابل تایید نیست", show_alert=True)
            return
        approve_withdrawal(session, wd)
        _audit(
            session,
            update,
            "approve_withdraw",
            target_user=wd.user,
            detail=f"withdraw_id={wd.id} amount={wd.amount_toman} via=bot",
            category="wallet",
        )
        tg_id = wd.user.telegram_id
        amount = wd.amount_toman
    await query.edit_message_text(f"برداشت #{wd_id} پرداخت شد ✅")
    await context.bot.send_message(
        chat_id=tg_id,
        text=f"✅ مبلغ {format_price(amount)} به کارت شما واریز شد.",
    )


async def admin_withdraw_no(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    query = update.callback_query
    if not query or not query.data or not _require_admin(update, context):
        return
    wd_id = int(query.data.split(":")[2])
    await query.answer()
    with _session(context) as session:
        wd = session.get(Withdrawal, wd_id)
        if not wd or wd.status != "pending":
            await query.answer("قابل رد نیست", show_alert=True)
            return
        reject_withdrawal(session, wd, note="rejected_by_admin")
        _audit(
            session,
            update,
            "reject_withdraw",
            target_user=wd.user,
            detail=f"withdraw_id={wd.id} amount={wd.amount_toman} via=bot",
            category="wallet",
        )
        tg_id = wd.user.telegram_id
        amount = wd.amount_toman
    await query.edit_message_text(f"برداشت #{wd_id} رد شد ❌ (مبلغ به کیف‌پول برگشت)")
    await context.bot.send_message(
        chat_id=tg_id,
        text=f"درخواست برداشت رد شد. {format_price(amount)} به کیف‌پول شما برگشت.",
    )


async def cmd_setrefpercent(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not update.message or not _require_admin(update, context):
        return
    try:
        percent = int(context.args[0])
        if not 0 <= percent <= 100:
            raise ValueError
    except (IndexError, ValueError, TypeError):
        await update.message.reply_text("Usage: /setrefpercent 15")
        return
    with _session(context) as session:
        set_setting(session, "referral_percent", str(percent))
    await update.message.reply_text(f"نرخ پورسانت دعوت → {percent}%")


async def cmd_setminwithdraw(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not update.message or not _require_admin(update, context):
        return
    try:
        amount = int(context.args[0])
        if amount < 0:
            raise ValueError
    except (IndexError, ValueError, TypeError):
        await update.message.reply_text("Usage: /setminwithdraw 100000")
        return
    with _session(context) as session:
        set_setting(session, "min_withdraw", str(amount))
    await update.message.reply_text(f"حداقل برداشت → {format_price(amount)}")


async def menu_router(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not update.message or not update.message.text:
        return
    text = update.message.text.strip()
    mapping = {
        "🛒 خرید اشتراک": show_plans,
        "📦 اشتراک‌های من": my_subscriptions,
        "🎁 دعوت دوستان": show_referral,
        "💳 راهنمای پرداخت": payment_help,
        "🆘 پشتیبانی": support,
        "🛠 پنل ادمین": admin_panel,
    }
    if text in OPEN_BUTTON_ALIASES:
        await shop_cmd(update, context)
        return
    handler = mapping.get(text)
    if handler:
        await handler(update, context)


async def admin_card_start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    query = update.callback_query
    if not query or not _require_admin(update, context):
        return ConversationHandler.END
    await query.answer()
    await query.edit_message_text(
        "شماره کارت جدید را بفرستید.\nفرمت:\n<code>CARD|NAME|NOTE</code>\n"
        "مثال:\n<code>6037-1111-2222-3333|علی رضایی|فقط کارت به کارت</code>",
        parse_mode=ParseMode.HTML,
    )
    return WAIT_CARD


async def admin_card_save(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    if not update.message or not _require_admin(update, context):
        return ConversationHandler.END
    raw = (update.message.text or "").strip()
    parts = [p.strip() for p in raw.split("|")]
    card = parts[0] if parts else raw
    name = parts[1] if len(parts) > 1 else ""
    note = parts[2] if len(parts) > 2 else _settings(context).payment_note
    with _session(context) as session:
        add_payment_card(session, _settings(context), card=card, name=name, note=note)
    await update.message.reply_text("کارت به لیست پرداخت اضافه شد.")
    return ConversationHandler.END


async def admin_broadcast_start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    query = update.callback_query
    if not query or not _require_admin(update, context):
        return ConversationHandler.END
    await query.answer()
    await query.edit_message_text("متن پیام همگانی را بفرستید (یا /cancel).")
    return WAIT_BROADCAST


async def admin_broadcast_send(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    if not update.message or not _require_admin(update, context):
        return ConversationHandler.END
    text = update.message.text or ""
    with _session(context) as session:
        ids = list(session.scalars(select(User.telegram_id)).all())
    ok = 0
    for tid in ids:
        try:
            await context.bot.send_message(chat_id=tid, text=text)
            ok += 1
        except Exception:  # noqa: BLE001
            continue
    await update.message.reply_text(f"ارسال شد به {ok}/{len(ids)} کاربر.")
    return ConversationHandler.END


async def cmd_setprice(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not update.message or not _require_admin(update, context):
        return
    try:
        plan_id = int(context.args[0])
        price = int(context.args[1])
    except (IndexError, ValueError, TypeError):
        await update.message.reply_text("Usage: /setprice PLAN_ID PRICE")
        return
    with _session(context) as session:
        plan = session.get(Plan, plan_id)
        if not plan:
            await update.message.reply_text("پلن پیدا نشد")
            return
        plan.price_toman = price
        session.commit()
    await update.message.reply_text(f"قیمت پلن #{plan_id} → {format_price(price)}")


async def cmd_toggleplan(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not update.message or not _require_admin(update, context):
        return
    try:
        plan_id = int(context.args[0])
    except (IndexError, ValueError, TypeError):
        await update.message.reply_text("Usage: /toggleplan PLAN_ID")
        return
    with _session(context) as session:
        plan = session.get(Plan, plan_id)
        if not plan:
            await update.message.reply_text("پلن پیدا نشد")
            return
        plan.enabled = not plan.enabled
        session.commit()
        state = "فعال" if plan.enabled else "غیرفعال"
    await update.message.reply_text(f"پلن #{plan_id} الان {state} است.")


async def cmd_disable_sub(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not update.message or not _require_admin(update, context):
        return
    if not context.args:
        await update.message.reply_text("Usage: /disable EMAIL_OR_SUB_ID")
        return
    arg = context.args[0]
    panel = _panel(context)
    with _session(context) as session:
        sub = None
        if arg.isdigit():
            sub = session.get(Subscription, int(arg))
        if sub is None:
            sub = session.scalar(select(Subscription).where(Subscription.xui_email == arg))
        if not sub:
            await update.message.reply_text("اشتراک پیدا نشد")
            return
        try:
            panel.set_enabled(sub.xui_email, False)
        except PanelError as exc:
            await update.message.reply_text(f"خطای پنل: {exc}")
            return
        sub.enabled = False
        session.commit()
        email = sub.xui_email
    await update.message.reply_text(f"غیرفعال شد: {email}")


async def cmd_extend(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not update.message or not _require_admin(update, context):
        return
    try:
        email = context.args[0]
        days = int(context.args[1])
    except (IndexError, ValueError, TypeError):
        await update.message.reply_text("Usage: /extend EMAIL DAYS")
        return
    panel = _panel(context)
    try:
        panel.extend_days(email, days)
    except PanelError as exc:
        await update.message.reply_text(f"خطای پنل: {exc}")
        return
    with _session(context) as session:
        sub = session.scalar(select(Subscription).where(Subscription.xui_email == email))
        if sub and sub.expires_at:
            from datetime import timedelta

            sub.expires_at = sub.expires_at + timedelta(days=days)
            session.commit()
    await update.message.reply_text(f"{days} روز به {email} اضافه شد.")
