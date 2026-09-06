"""Background maintenance: usage alerts, auto-renew, server health."""

from __future__ import annotations

import logging
from datetime import datetime, timedelta
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.orm import Session, selectinload

from app.models import Commission, Order, OrderStatus, Subscription, User, VpnServer, Withdrawal, WithdrawStatus
from app.panel import ping_tcp
from app.services import (
    _notify_telegram,
    client_connection_ips,
    format_price,
    get_setting,
    is_metered_payg,
    is_payg_subscription,
    is_vpn_plan,
    plan_charge_price,
    set_setting,
    spend_wallet,
    wallet_spendable,
    subscription_live_stats,
)

logger = logging.getLogger(__name__)

AUTO_RENEW_WINDOW_HOURS = 48
HEALTH_FAIL_THRESHOLD = 3
HEALTH_PROBE_PORTS = (8443, 26607, 443, 8080)
PRIMARY_HEALTH_OK = "vpn_primary_health_ok"
PRIMARY_HEALTH_FAILS = "vpn_primary_health_fail_count"
PRIMARY_HEALTH_PING = "vpn_primary_last_ping_ms"
PRIMARY_HEALTH_AT = "vpn_primary_last_health_at"


def reset_subscription_alerts(sub: Subscription) -> None:
    sub.alert_traffic_80_at = None
    sub.alert_traffic_100_at = None
    sub.alert_ip_over_at = None
    sub.alert_expiry_3d_at = None
    sub.alert_expiry_1d_at = None


def check_expiry_reminders(session: Session, settings) -> dict[str, int]:
    """Telegram reminders 3 days and 1 day before subscription expiry."""
    sent = {"d3": 0, "d1": 0}
    now = datetime.utcnow()
    horizon = now + timedelta(days=4)
    subs = list(
        session.scalars(
            select(Subscription)
            .where(
                Subscription.enabled.is_(True),
                Subscription.expires_at.is_not(None),
                Subscription.expires_at > now,
                Subscription.expires_at <= horizon,
            )
            .options(selectinload(Subscription.user), selectinload(Subscription.plan))
            .limit(300)
        ).all()
    )
    for sub in subs:
        user = sub.user
        if not user or not user.telegram_id:
            continue
        if bool(getattr(user, "is_test", False)):
            continue
        if is_metered_payg(sub):
            continue
        if not sub.expires_at:
            continue
        remaining = sub.expires_at - now
        days_left = remaining.total_seconds() / 86400.0
        if days_left <= 1.0 and not sub.alert_expiry_1d_at:
            if send_expiry_reminder(session, settings, sub, mark=True):
                sent["d1"] += 1
        elif days_left <= 3.0 and not sub.alert_expiry_3d_at:
            if send_expiry_reminder(session, settings, sub, mark=True):
                sent["d3"] += 1
    return sent


def send_expiry_reminder(session: Session, settings, sub: Subscription, *, mark: bool = True) -> bool:
    """Send a one-off expiry Telegram reminder. Used by the job and admin tap."""
    user = sub.user
    if not user or not user.telegram_id or not sub.expires_at:
        return False
    if is_metered_payg(sub):
        return False
    now = datetime.utcnow()
    days_left = max(0.0, (sub.expires_at - now).total_seconds() / 86400.0)
    label = (sub.label or "").strip() or (sub.plan.title if sub.plan else sub.xui_email)
    if days_left <= 1:
        text = f"⏰ یادآوری انقضا\nکانفیگ «{label}» کمتر از ۱ روز دیگر تمام می‌شود.\nاز فروشگاه تمدید کنید."
    else:
        text = (
            f"⏰ یادآوری انقضا\nکانفیگ «{label}» حدود {max(1, int(days_left))} روز دیگر تمام می‌شود.\n"
            "از فروشگاه تمدید کنید."
        )
    _notify_telegram(settings, user.telegram_id, text)
    if mark:
        if days_left <= 1:
            sub.alert_expiry_1d_at = sub.alert_expiry_1d_at or now
        else:
            sub.alert_expiry_3d_at = sub.alert_expiry_3d_at or now
        session.commit()
    return True


def set_subscription_auto_renew(session: Session, sub: Subscription, enabled: bool) -> Subscription:
    sub.auto_renew = bool(enabled)
    if enabled:
        sub.auto_renew_fail_notified_at = None
    session.commit()
    session.refresh(sub)
    return sub


def check_usage_alerts(session: Session, panel, settings) -> dict[str, int]:
    sent = {"traffic_80": 0, "traffic_100": 0, "ip_over": 0}
    subs = list(
        session.scalars(
            select(Subscription)
            .where(Subscription.enabled.is_(True))
            .options(selectinload(Subscription.user), selectinload(Subscription.plan))
            .limit(200)
        ).all()
    )
    for sub in subs:
        user = sub.user
        if not user or not user.telegram_id:
            continue
        if is_metered_payg(sub):
            continue
        label = (sub.label or "").strip() or (sub.plan.title if sub.plan else sub.xui_email)
        try:
            stats = subscription_live_stats(panel, sub)
        except Exception:
            logger.exception("usage alert stats failed %s", sub.xui_email)
            continue
        total = int(stats.get("total_bytes") or 0)
        percent = float(stats.get("usage_percent") or 0)
        now = datetime.utcnow()
        dirty = False
        if total > 0 and not is_payg_subscription(sub):
            if percent >= 100 and not sub.alert_traffic_100_at:
                _notify_telegram(
                    settings,
                    user.telegram_id,
                    (
                        f"⛔️ ترافیک کانفیگ «{label}» تمام شد (۱۰۰٪).\n"
                        f"مصرف: {stats.get('used_label')} از {stats.get('total_label')}\n"
                        "از داشبورد تمدید یا شارژ کنید."
                    ),
                )
                sub.alert_traffic_100_at = now
                if not sub.alert_traffic_80_at:
                    sub.alert_traffic_80_at = now
                sent["traffic_100"] += 1
                dirty = True
            elif percent >= 80 and not sub.alert_traffic_80_at:
                _notify_telegram(
                    settings,
                    user.telegram_id,
                    (
                        f"⚠️ ترافیک کانفیگ «{label}» به {percent:g}٪ رسید.\n"
                        f"مصرف: {stats.get('used_label')} از {stats.get('total_label')}\n"
                        "قبل از اتمام، تمدید کنید."
                    ),
                )
                sub.alert_traffic_80_at = now
                sent["traffic_80"] += 1
                dirty = True
            elif percent < 80 and (sub.alert_traffic_80_at or sub.alert_traffic_100_at):
                # Traffic was reset (new quota) — clear markers.
                reset_subscription_alerts(sub)
                dirty = True

        try:
            ip_info = client_connection_ips(panel, sub.xui_email)
        except Exception:
            ip_info = {"connected_ip_count": 0, "limit_ip": 0}
        limit_ip = int(ip_info.get("limit_ip") or 0)
        connected = int(ip_info.get("connected_ip_count") or 0)
        if limit_ip > 0 and connected > limit_ip:
            should_notify = not sub.alert_ip_over_at or (now - sub.alert_ip_over_at) >= timedelta(hours=12)
            if should_notify:
                _notify_telegram(
                    settings,
                    user.telegram_id,
                    (
                        f"🚨 بیش از حد مجاز IP روی «{label}»\n"
                        f"متصل: {connected} · سقف: {limit_ip}\n"
                        "دستگاه اضافه را قطع کنید یا پلن با IP بیشتر بگیرید."
                    ),
                )
                sub.alert_ip_over_at = now
                sent["ip_over"] += 1
                dirty = True
        elif limit_ip > 0 and connected <= limit_ip and sub.alert_ip_over_at:
            sub.alert_ip_over_at = None
            dirty = True

        if dirty:
            session.commit()
    return sent


def process_auto_renewals(session: Session, panel, settings) -> dict[str, int]:
    now = datetime.utcnow()
    horizon = now + timedelta(hours=AUTO_RENEW_WINDOW_HOURS)
    result = {"renewed": 0, "failed": 0, "skipped": 0}
    subs = list(
        session.scalars(
            select(Subscription)
            .where(
                Subscription.auto_renew.is_(True),
                Subscription.enabled.is_(True),
                Subscription.expires_at.is_not(None),
                Subscription.expires_at <= horizon,
                Subscription.expires_at > now - timedelta(hours=6),
            )
            .options(selectinload(Subscription.user), selectinload(Subscription.plan))
            .limit(100)
        ).all()
    )
    for sub in subs:
        if is_payg_subscription(sub) or is_metered_payg(sub):
            result["skipped"] += 1
            continue
        plan = sub.plan
        user = sub.user
        if not user or not plan or not is_vpn_plan(plan):
            result["skipped"] += 1
            continue
        days = int(plan.duration_days or 0)
        if days <= 0:
            result["skipped"] += 1
            continue
        # Avoid renewing more than once per cycle: only when within window and not already far out.
        if sub.expires_at and sub.expires_at > now + timedelta(hours=AUTO_RENEW_WINDOW_HOURS):
            result["skipped"] += 1
            continue
        charge = int(plan_charge_price(session, user, plan))
        label = (sub.label or "").strip() or plan.title
        wallet = wallet_spendable(user)
        if charge > 0 and wallet < charge:
            if not sub.auto_renew_fail_notified_at or (now - sub.auto_renew_fail_notified_at) >= timedelta(hours=24):
                _notify_telegram(
                    settings,
                    user.telegram_id,
                    (
                        f"💳 تمدید خودکار «{label}» ناموفق بود.\n"
                        f"مبلغ لازم: {format_price(charge)}\n"
                        f"موجودی: {format_price(wallet)}\n"
                        "کیف‌پول را شارژ کنید یا تمدید دستی انجام دهید."
                    ),
                )
                sub.auto_renew_fail_notified_at = now
                session.commit()
            result["failed"] += 1
            continue
        try:
            locked_used = 0
            if charge > 0:
                used, locked_used = spend_wallet(user, charge)
                if used < charge:
                    raise RuntimeError("insufficient_wallet")
            panel.extend_days(sub.xui_email, days)
            panel.set_enabled(sub.xui_email, True)
            if sub.expires_at and sub.expires_at > now:
                sub.expires_at = sub.expires_at + timedelta(days=days)
            else:
                sub.expires_at = now + timedelta(days=days)
            sub.enabled = True
            sub.auto_renew_fail_notified_at = None
            reset_subscription_alerts(sub)
            if getattr(sub, "hidden_from_dashboard", False):
                sub.hidden_from_dashboard = False
            order = Order(
                user_id=user.id,
                plan_id=plan.id,
                status=OrderStatus.APPROVED,
                amount_toman=0,
                wallet_used=charge,
                wallet_locked_used=locked_used,
                target_subscription_id=sub.id,
                admin_note=f"auto_renew:{sub.id}",
                reviewed_at=now,
            )
            session.add(order)
            session.commit()
            session.refresh(sub)
            session.refresh(user)
            _notify_telegram(
                settings,
                user.telegram_id,
                (
                    f"✅ تمدید خودکار «{label}» انجام شد.\n"
                    f"مدت: {days} روز\n"
                    f"کسر از کیف‌پول: {format_price(charge)}\n"
                    f"موجودی: {format_price(user.wallet_balance or 0)}"
                ),
            )
            result["renewed"] += 1
        except Exception:
            logger.exception("auto renew failed sub=%s", sub.id)
            session.rollback()
            result["failed"] += 1
    return result


def _probe_endpoint(host: str, ip: str) -> tuple[bool, int | None]:
    targets: list[tuple[str, int]] = []
    for port in HEALTH_PROBE_PORTS:
        if host:
            targets.append((host, port))
        if ip and ip != host:
            targets.append((ip, port))
    best: int | None = None
    for addr, port in targets[:6]:
        ms = ping_tcp(addr, port, timeout=2.0)
        if ms is None:
            continue
        best = ms if best is None else min(best, ms)
        if best <= 800:
            return True, best
    return best is not None, best


def _apply_health_result(
    *,
    ok: bool,
    ping_ms: int | None,
    fail_count: int,
) -> tuple[bool, int, bool]:
    """Returns (health_ok, fail_count, changed_visibility)."""
    if ok:
        was_down = fail_count >= HEALTH_FAIL_THRESHOLD
        return True, 0, was_down
    new_fails = fail_count + 1
    health_ok = new_fails < HEALTH_FAIL_THRESHOLD
    became_down = fail_count < HEALTH_FAIL_THRESHOLD <= new_fails
    return health_ok, new_fails, became_down


def probe_all_server_health(session: Session, settings) -> dict[str, Any]:
    from app.servers import invalidate_panel_hub, primary_enabled

    now = datetime.utcnow()
    changed = False
    summary: list[dict[str, Any]] = []

    # Primary
    if primary_enabled(session):
        ok, ping_ms = _probe_endpoint(settings.public_host or "", settings.public_ip or "")
        # Also try panel API as soft signal
        if not ok:
            try:
                from app.panel import XUIPanel

                panel = XUIPanel(settings)
                try:
                    panel.online_emails()
                    ok, ping_ms = True, ping_ms
                finally:
                    panel.close()
            except Exception:
                pass
        fails = int(get_setting(session, PRIMARY_HEALTH_FAILS, "0") or "0")
        health_ok, fails, vis_changed = _apply_health_result(ok=ok, ping_ms=ping_ms, fail_count=fails)
        prev = get_setting(session, PRIMARY_HEALTH_OK, "1") != "0"
        set_setting(session, PRIMARY_HEALTH_OK, "1" if health_ok else "0")
        set_setting(session, PRIMARY_HEALTH_FAILS, str(fails))
        set_setting(session, PRIMARY_HEALTH_PING, str(ping_ms or ""))
        set_setting(session, PRIMARY_HEALTH_AT, now.isoformat())
        if prev != health_ok:
            changed = True
        summary.append({"id": 0, "name": "primary", "ok": health_ok, "ping_ms": ping_ms, "fails": fails})
        if vis_changed and not health_ok:
            logger.warning("primary server auto-hidden from links (health)")
        if vis_changed and health_ok:
            logger.info("primary server links restored (health)")

    for row in session.scalars(select(VpnServer).order_by(VpnServer.id)).all():
        if not row.enabled:
            summary.append({"id": row.id, "name": row.name, "ok": False, "skipped": True})
            continue
        ok, ping_ms = _probe_endpoint(row.public_host or "", row.public_ip or "")
        if not ok:
            try:
                from app.servers import panel_for_server

                panel = panel_for_server(settings, row)
                try:
                    panel.online_emails()
                    ok = True
                finally:
                    panel.close()
            except Exception:
                ok = False
        fails = int(getattr(row, "health_fail_count", 0) or 0)
        health_ok, fails, vis_changed = _apply_health_result(ok=ok, ping_ms=ping_ms, fail_count=fails)
        prev = bool(getattr(row, "health_ok", True))
        row.health_ok = health_ok
        row.health_fail_count = fails
        row.last_ping_ms = ping_ms
        row.last_health_at = now
        if prev != health_ok or vis_changed:
            changed = True
        summary.append({"id": row.id, "name": row.name, "ok": health_ok, "ping_ms": ping_ms, "fails": fails})
    session.commit()
    if changed:
        try:
            invalidate_panel_hub()
        except Exception:
            logger.exception("invalidate hub after health failed")
    return {"servers": summary, "changed": changed}


def primary_health_dict(session: Session) -> dict[str, Any]:
    ok = get_setting(session, PRIMARY_HEALTH_OK, "1") != "0"
    ping_raw = get_setting(session, PRIMARY_HEALTH_PING, "")
    fails = int(get_setting(session, PRIMARY_HEALTH_FAILS, "0") or "0")
    at = get_setting(session, PRIMARY_HEALTH_AT, "") or None
    ping_ms = int(ping_raw) if ping_raw.isdigit() else None
    return {
        "health_ok": ok,
        "health_fail_count": fails,
        "last_ping_ms": ping_ms,
        "last_health_at": at,
        "links_visible": ok,
    }


def referral_leaderboard(session: Session, *, limit: int = 10) -> list[dict[str, Any]]:
    limit = max(1, min(50, int(limit)))
    rows = session.execute(
        select(
            Commission.referrer_id,
            func.coalesce(func.sum(Commission.amount_toman), 0).label("earned"),
            func.count(Commission.id).label("sales"),
        )
        .group_by(Commission.referrer_id)
        .order_by(func.coalesce(func.sum(Commission.amount_toman), 0).desc())
        .limit(limit)
    ).all()
    if not rows:
        return []
    users = {
        u.id: u
        for u in session.scalars(select(User).where(User.id.in_([r.referrer_id for r in rows]))).all()
    }
    out: list[dict[str, Any]] = []
    for rank, row in enumerate(rows, start=1):
        user = users.get(row.referrer_id)
        if not user:
            continue
        name = (user.full_name or "").strip()
        if not name and user.username:
            name = f"@{user.username}"
        if not name:
            name = "کاربر"
        # Light privacy: keep first word + mask rest for long names
        parts = name.split()
        display = parts[0] if parts else name
        if len(parts) > 1:
            display = f"{parts[0]} …"
        earned = int(row.earned or 0)
        out.append(
            {
                "rank": rank,
                "referrer_id": user.id,
                "display_name": display,
                "earned_total": earned,
                "earned_label": format_price(earned),
                "sales_count": int(row.sales or 0),
                "is_self": False,
            }
        )
    return out


def list_user_withdrawals(session: Session, user: User, *, limit: int = 20) -> list[dict[str, Any]]:
    rows = list(
        session.scalars(
            select(Withdrawal)
            .where(Withdrawal.user_id == user.id)
            .order_by(Withdrawal.id.desc())
            .limit(max(1, min(50, limit)))
        ).all()
    )
    status_fa = {
        WithdrawStatus.PENDING: "در انتظار",
        WithdrawStatus.PAID: "پرداخت شد",
        WithdrawStatus.REJECTED: "رد شد",
    }
    out: list[dict[str, Any]] = []
    for w in rows:
        out.append(
            {
                "id": w.id,
                "amount_toman": w.amount_toman,
                "amount_label": format_price(w.amount_toman),
                "card_number": w.card_number,
                "status": w.status,
                "status_label": status_fa.get(w.status, w.status),
                "created_at": w.created_at.isoformat() if w.created_at else None,
                "reviewed_at": w.reviewed_at.isoformat() if w.reviewed_at else None,
            }
        )
    return out


def run_maintenance_jobs(session: Session, panel, settings) -> None:
    try:
        check_usage_alerts(session, panel, settings)
    except Exception:
        logger.exception("usage alerts job failed")
    try:
        check_expiry_reminders(session, settings)
    except Exception:
        logger.exception("expiry reminders job failed")
    try:
        process_auto_renewals(session, panel, settings)
    except Exception:
        logger.exception("auto renew job failed")
    try:
        probe_all_server_health(session, settings)
    except Exception:
        logger.exception("server health job failed")
    try:
        from app.parental import ingest_family_browse_logs

        ingest_family_browse_logs(session, panel)
    except Exception:
        logger.exception("family browse log job failed")
    try:
        from app.parental import maybe_sync_parental_routing

        maybe_sync_parental_routing(session, panel)
    except Exception:
        logger.exception("parental schedule sync failed")
    try:
        from app.parental import maybe_sync_vpn_allow_schedules

        maybe_sync_vpn_allow_schedules(session, panel)
    except Exception:
        logger.exception("vpn allow schedule sync failed")
    try:
        from app.receipts import maybe_archive_receipts_end_of_jalali_month

        maybe_archive_receipts_end_of_jalali_month(session, settings)
    except Exception:
        logger.exception("receipt telegram archive job failed")
