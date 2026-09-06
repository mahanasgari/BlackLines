from __future__ import annotations

from app.config import Settings
from app.services import format_price


def welcome(settings: Settings) -> str:
    return (
        f"سلام! به <b>{settings.shop_name}</b> خوش آمدید 👋\n\n"
        "از دکمه <b>باز کردن</b> فروشگاه را باز کنید — کانفیگ‌ها، خرید و کیف‌پول آنجاست."
    )


def trial_activated_text() -> str:
    return (
        "🎁 <b>کانفیگ تست فعال شد</b>\n\n"
        "لینک‌ها داخل مینی‌اپ هستند.\n"
        "برای دیدن و استفاده، مینی‌اپ را باز کنید."
    )


def trial_offer_text(duration_days: int, traffic: str) -> str:
    return (
        "🎁 <b>کانفیگ تست رایگان</b>\n\n"
        f"{duration_days} روز · {traffic}\n"
        "اگر می‌خواهید امتحان کنید، دکمه زیر را بزنید."
    )


def referral_text(stats: dict, bot_username: str) -> str:
    link = f"https://t.me/{bot_username}?start=ref_{stats['code']}"
    return (
        "🎁 <b>برنامه دعوت و همکاری</b>\n\n"
        f"با اشتراک‌گذاری لینک دعوت، از هر خرید موفق دوستانتان "
        f"<b>{stats['percent']}٪</b> پورسانت می‌گیرید "
        "(به کیف‌پول داخل ربات).\n\n"
        f"🔗 لینک دعوت:\n<code>{link}</code>\n"
        f"کد دعوت: <code>{stats['code']}</code>\n\n"
        f"👥 دعوت‌شده‌ها: {stats['invited']}\n"
        f"✅ خرید موفق از دعوت‌ها: {stats['paid_referrals']}\n"
        f"💵 مجموع پورسانت: {format_price(stats['earned_total'])}\n"
        f"👛 موجودی کیف‌پول: <b>{format_price(stats['wallet'])}</b>\n"
        f"حداقل برداشت: {format_price(stats['min_withdraw'])}\n\n"
        "موجودی را می‌توانید برای خرید بعدی استفاده کنید "
        "یا درخواست برداشت بدهید."
    )


def support_text() -> str:
    return (
        "🆘 پشتیبانی\n\n"
        "اگر در اتصال مشکل دارید، لینک Reality یا WS-443 را امتحان کنید.\n"
        "برای پیگیری سفارش، شماره سفارش را به ادمین بفرستید."
    )


def payment_text(settings: Settings, amount: int | None = None) -> str:
    lines = [
        "💳 راهنمای پرداخت\n",
        f"شماره کارت: <code>{settings.payment_card}</code>",
    ]
    if settings.payment_card_name:
        lines.append(f"به نام: {settings.payment_card_name}")
    if amount is not None:
        lines.append(f"مبلغ قابل پرداخت: <b>{format_price(amount)}</b>")
    lines.append("")
    lines.append(settings.payment_note)
    lines.append("\nبعد از واریز، <b>عکس رسید</b> را همین‌جا ارسال کنید.")
    return "\n".join(lines)


def configs_message(links: list[str], email: str) -> str:
    """Legacy: prefer subscription_link_message so Telegram only gets the sub URL."""
    return subscription_link_message(email=email, sub_url=links[0] if links else None)


def subscription_link_message(
    *,
    email: str,
    sub_url: str | None,
    label: str | None = None,
    title: str = "✅ اشتراک فعال شد",
    extra: str = "",
) -> str:
    lines = [title]
    if label:
        lines.append(f"<b>{label}</b>")
    lines.append(f"شناسه: <code>{email}</code>")
    if sub_url:
        lines.append(f"\nلینک اشتراک:\n<code>{sub_url}</code>")
    else:
        lines.append("\nلینک اشتراک را در مینی‌اپ ببینید.")
    lines.append("\nکانفیگ‌های تکی فقط داخل مینی‌اپ هستند.")
    if extra:
        lines.append(extra)
    return "\n".join(lines)
