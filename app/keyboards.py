from __future__ import annotations

from telegram import InlineKeyboardButton, InlineKeyboardMarkup, KeyboardButton, ReplyKeyboardMarkup, WebAppInfo

from app.models import Order, Plan, Withdrawal
from app.services import format_price, traffic_label

OPEN_BUTTON_TEXT = "باز کردن"
OPEN_BUTTON_ALIASES = frozenset(
    {
        OPEN_BUTTON_TEXT,
        "🚀 باز کردن",
        "🚀 Shop",
        "Shop",
        "Open",
    }
)


def _miniapp_https(url: str) -> str:
    cleaned = url.strip()
    if cleaned and not cleaned.endswith("/"):
        cleaned += "/"
    return cleaned


def main_menu(is_admin: bool = False, miniapp_url: str = "") -> ReplyKeyboardMarkup:
    rows: list[list[KeyboardButton]] = []
    url = _miniapp_https(miniapp_url)
    if url:
        rows.append([KeyboardButton(OPEN_BUTTON_TEXT, web_app=WebAppInfo(url=url))])
    rows.extend(
        [
            [KeyboardButton("🛒 خرید اشتراک"), KeyboardButton("📦 اشتراک‌های من")],
            [KeyboardButton("🎁 دعوت دوستان"), KeyboardButton("💳 راهنمای پرداخت")],
            [KeyboardButton("🆘 پشتیبانی")],
        ]
    )
    if is_admin:
        rows.append([KeyboardButton("🛠 پنل ادمین")])
    return ReplyKeyboardMarkup(rows, resize_keyboard=True)


def trial_claim_keyboard() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(
        [[InlineKeyboardButton("🎁 دریافت VPN تست", callback_data="trial:claim")]]
    )


def miniapp_inline(miniapp_url: str) -> InlineKeyboardMarkup | None:
    url = _miniapp_https(miniapp_url)
    if not url:
        return None
    return InlineKeyboardMarkup(
        [[InlineKeyboardButton(OPEN_BUTTON_TEXT, web_app=WebAppInfo(url=url))]]
    )


def plans_keyboard(plans: list[Plan]) -> InlineKeyboardMarkup:
    rows = [
        [
            InlineKeyboardButton(
                f"{plan.title} — {format_price(plan.price_toman)}",
                callback_data=f"plan:{plan.id}",
            )
        ]
        for plan in plans
    ]
    rows.append([InlineKeyboardButton("بستن", callback_data="noop")])
    return InlineKeyboardMarkup(rows)


def confirm_buy_keyboard(plan_id: int) -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(
        [
            [
                InlineKeyboardButton("✅ ادامه خرید", callback_data=f"buy:{plan_id}"),
                InlineKeyboardButton("انصراف", callback_data="noop"),
            ]
        ]
    )


def admin_order_keyboard(order_id: int) -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(
        [
            [
                InlineKeyboardButton("✅ تایید و ساخت کانفیگ", callback_data=f"adm:ok:{order_id}"),
                InlineKeyboardButton("❌ رد", callback_data=f"adm:no:{order_id}"),
            ]
        ]
    )


def admin_menu_keyboard() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(
        [
            [InlineKeyboardButton("⏳ سفارش‌های در انتظار", callback_data="adm:pending")],
            [InlineKeyboardButton("💸 درخواست‌های برداشت", callback_data="adm:withdraws")],
            [InlineKeyboardButton("📋 پلن‌ها", callback_data="adm:plans")],
            [InlineKeyboardButton("👥 آمار", callback_data="adm:stats")],
            [InlineKeyboardButton("💳 تنظیم کارت", callback_data="adm:card")],
            [InlineKeyboardButton("📣 پیام همگانی", callback_data="adm:broadcast")],
        ]
    )


def subscription_keyboard(sub_id: int) -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(
        [[InlineKeyboardButton("🔗 لینک اشتراک", callback_data=f"sub:links:{sub_id}")]]
    )


def referral_keyboard(can_withdraw: bool) -> InlineKeyboardMarkup:
    rows = []
    if can_withdraw:
        rows.append([InlineKeyboardButton("💸 درخواست برداشت", callback_data="ref:withdraw")])
    rows.append([InlineKeyboardButton("🔄 بروزرسانی", callback_data="ref:refresh")])
    return InlineKeyboardMarkup(rows)


def admin_withdraw_keyboard(wd_id: int) -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(
        [
            [
                InlineKeyboardButton("✅ پرداخت شد", callback_data=f"adm:wdok:{wd_id}"),
                InlineKeyboardButton("❌ رد", callback_data=f"adm:wdno:{wd_id}"),
            ]
        ]
    )


def plan_detail_text(plan: Plan) -> str:
    return (
        f"<b>{plan.title}</b>\n"
        f"{plan.description}\n\n"
        f"⏱ مدت: {plan.duration_days} روز\n"
        f"📊 ترافیک: {traffic_label(plan.traffic_gb)}\n"
        f"📱 محدودیت دستگاه: {plan.limit_ip}\n"
        f"💰 قیمت: <b>{format_price(plan.price_toman)}</b>"
    )


def order_admin_text(order: Order) -> str:
    user = order.user
    plan = order.plan
    uname = f"@{user.username}" if user.username else "—"
    from app.services import is_custom_order, order_plan_title

    plan_line = order_plan_title(order) if is_custom_order(order) else (plan.title if plan else "—")
    lines = [
        f"🧾 سفارش #{order.id}",
        f"کاربر: {user.full_name or '—'} ({uname})",
        f"آیدی: <code>{user.telegram_id}</code>",
        f"پلن: {plan_line}",
        f"مبلغ واریزی: {format_price(order.amount_toman)}",
    ]
    if order.wallet_used:
        lines.append(f"از کیف‌پول: {format_price(order.wallet_used)}")
    if user.referred_by_id:
        lines.append(f"دعوت‌شده توسط user_id={user.referred_by_id}")
    lines.append(f"وضعیت: {order.status}")
    return "\n".join(lines)


def withdraw_admin_text(wd: Withdrawal) -> str:
    user = wd.user
    uname = f"@{user.username}" if user.username else "—"
    return (
        f"💸 برداشت #{wd.id}\n"
        f"کاربر: {user.full_name or '—'} ({uname})\n"
        f"آیدی: <code>{user.telegram_id}</code>\n"
        f"مبلغ: {format_price(wd.amount_toman)}\n"
        f"کارت: <code>{wd.card_number}</code>\n"
        f"وضعیت: {wd.status}"
    )
