"""Parental / family content restrictions via xray routing."""

from __future__ import annotations

import json
import logging
import re
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

try:
    from zoneinfo import ZoneInfo

    _TEHRAN = ZoneInfo("Asia/Tehran")
except Exception:  # noqa: BLE001
    _TEHRAN = timezone(timedelta(hours=3, minutes=30))

from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from app.models import FamilyBrowseEvent, FamilyBrowseHit, Subscription
from app.services import get_setting, set_setting

logger = logging.getLogger(__name__)

PARENTAL_ENABLED = "parental_controls_enabled"
PARENTAL_CUSTOM_DOMAINS = "parental_custom_domains"  # JSON list[str]
PARENTAL_RULES_FP = "parental_rules_fp"
VPN_ALLOW_SYNC_FP = "vpn_allow_schedule_fp"
OUTBOUND_TAG = "blocked-parental"
MARKER_DOMAIN = "full:vpnshop-parental.invalid"

# Curated block categories parents can toggle per child seat.
DEFAULT_CATEGORIES: list[dict[str, Any]] = [
    {
        "key": "tiktok",
        "label": "تیک‌تاک",
        "desc": "TikTok و دامنه‌های مرتبط",
        "domains": [
            "domain:tiktok.com",
            "domain:tiktokv.com",
            "domain:musical.ly",
            "domain:byteoversea.com",
            "domain:ibytedtos.com",
        ],
    },
    {
        "key": "instagram",
        "label": "اینستاگرام",
        "desc": "Instagram / Threads",
        "domains": [
            "domain:instagram.com",
            "domain:cdninstagram.com",
            "domain:threads.net",
        ],
    },
    {
        "key": "youtube",
        "label": "یوتیوب",
        "desc": "YouTube و گوگل ویدیو",
        "domains": [
            "domain:youtube.com",
            "domain:youtu.be",
            "domain:googlevideo.com",
            "domain:ytimg.com",
            "geosite:youtube",
        ],
    },
    {
        "key": "games",
        "label": "بازی آنلاین",
        "desc": "Roblox، Steam، Epic، Discord",
        "domains": [
            "domain:roblox.com",
            "domain:rbxcdn.com",
            "domain:steampowered.com",
            "domain:steamcommunity.com",
            "domain:epicgames.com",
            "domain:discord.com",
            "domain:discord.gg",
            "domain:discordapp.com",
        ],
    },
    {
        "key": "adult",
        "label": "محتوای بزرگسالان",
        "desc": "دسته‌بندی پورن (geosite)",
        "domains": ["geosite:category-porn"],
    },
    {
        "key": "gambling",
        "label": "قمار و شرط‌بندی",
        "desc": "سایت‌های قمار",
        "domains": ["geosite:category-gambling"],
    },
    {
        "key": "dating",
        "label": "دوستیابی",
        "desc": "Tinder، Bumble و مشابه",
        "domains": [
            "domain:tinder.com",
            "domain:bumble.com",
            "domain:badoo.com",
            "domain:okcupid.com",
        ],
    },
    {
        "key": "social_extra",
        "label": "شبکه‌های اجتماعی دیگر",
        "desc": "Snapchat، Reddit، Twitch",
        "domains": [
            "domain:snapchat.com",
            "domain:reddit.com",
            "domain:redd.it",
            "domain:twitch.tv",
            "domain:ttvnw.net",
        ],
    },
]


def parental_enabled(session: Session) -> bool:
    return get_setting(session, PARENTAL_ENABLED, "1") != "0"


def set_parental_enabled(session: Session, enabled: bool) -> None:
    set_setting(session, PARENTAL_ENABLED, "1" if enabled else "0")


def custom_domains(session: Session) -> list[str]:
    raw = get_setting(session, PARENTAL_CUSTOM_DOMAINS, "[]") or "[]"
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return []
    if not isinstance(data, list):
        return []
    out: list[str] = []
    for item in data:
        s = str(item or "").strip().lower()
        if not s:
            continue
        if not s.startswith(("domain:", "full:", "regexp:", "geosite:", "keyword:")):
            if "/" in s or s.startswith("*"):
                continue
            s = f"domain:{s.lstrip('.')}"
        out.append(s)
    return out[:200]


def set_custom_domains(session: Session, domains: list[str]) -> list[str]:
    cleaned: list[str] = []
    for item in domains:
        s = str(item or "").strip().lower()
        if not s:
            continue
        if not s.startswith(("domain:", "full:", "regexp:", "geosite:", "keyword:")):
            s = f"domain:{s.lstrip('.')}"
        if s not in cleaned:
            cleaned.append(s)
    set_setting(session, PARENTAL_CUSTOM_DOMAINS, json.dumps(cleaned[:200], ensure_ascii=False))
    return cleaned[:200]


def category_map() -> dict[str, dict[str, Any]]:
    return {c["key"]: c for c in DEFAULT_CATEGORIES}


def parse_categories(raw: str | None) -> list[str]:
    if not raw:
        return []
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        data = [p.strip() for p in str(raw).split(",") if p.strip()]
    if not isinstance(data, list):
        return []
    known = category_map()
    out: list[str] = []
    for item in data:
        key = str(item or "").strip()
        if key in known and key not in out:
            out.append(key)
    return out


def _parse_hhmm(raw: str | None) -> str | None:
    text = str(raw or "").strip()
    m = re.fullmatch(r"(\d{1,2}):(\d{2})", text)
    if not m:
        return None
    hour, minute = int(m.group(1)), int(m.group(2))
    if hour > 23 or minute > 59:
        return None
    return f"{hour:02d}:{minute:02d}"


def parse_schedule(raw: str | None) -> dict[str, Any] | None:
    if not raw:
        return None
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return None
    if not isinstance(data, dict) or not data.get("enabled"):
        return None
    start = _parse_hhmm(data.get("start"))
    end = _parse_hhmm(data.get("end"))
    if not start or not end:
        return None
    days_raw = data.get("days")
    days: list[int] = []
    if isinstance(days_raw, list):
        for item in days_raw:
            try:
                day = int(item)
            except (TypeError, ValueError):
                continue
            if 0 <= day <= 6 and day not in days:
                days.append(day)
    if not days:
        days = list(range(7))
    return {"enabled": True, "start": start, "end": end, "days": days}


def serialize_schedule(payload: dict[str, Any] | None) -> str | None:
    parsed = parse_schedule(json.dumps(payload, ensure_ascii=False) if payload else None)
    if not parsed:
        return None
    return json.dumps(parsed, ensure_ascii=False)


def schedule_label(sched: dict[str, Any] | None) -> str | None:
    if not sched:
        return None
    return f"{sched['start']}–{sched['end']}"


def schedule_active_now(sched: dict[str, Any] | None, *, now: datetime | None = None) -> bool:
    """True when the block window is currently in effect (Asia/Tehran)."""
    if not sched:
        return True
    when = now or datetime.now(_TEHRAN)
    if when.tzinfo is None:
        when = when.replace(tzinfo=timezone.utc).astimezone(_TEHRAN)
    else:
        when = when.astimezone(_TEHRAN)
    if int(when.weekday()) not in set(sched.get("days") or range(7)):
        return False
    start = _hhmm_minutes(sched["start"])
    end = _hhmm_minutes(sched["end"])
    current = when.hour * 60 + when.minute
    if start == end:
        return True
    if start < end:
        return start <= current < end
    return current >= start or current < end


def _hhmm_minutes(hhmm: str) -> int:
    hour, minute = hhmm.split(":")
    return int(hour) * 60 + int(minute)


def serialize_categories(keys: list[str]) -> str:
    known = category_map()
    clean = [k for k in keys if k in known]
    return json.dumps(clean, ensure_ascii=False)


def domains_for_categories(session: Session, keys: list[str]) -> list[str]:
    known = category_map()
    domains: list[str] = []
    for key in keys:
        cat = known.get(key)
        if not cat:
            continue
        for d in cat.get("domains") or []:
            if d not in domains:
                domains.append(d)
    for d in custom_domains(session):
        if d not in domains:
            domains.append(d)
    return domains


def categories_public(session: Session) -> dict[str, Any]:
    custom = custom_domains(session)
    items = [
        {
            "key": c["key"],
            "label": c["label"],
            "desc": c["desc"],
            "domain_count": len(c["domains"]),
        }
        for c in DEFAULT_CATEGORIES
    ]
    return {
        "enabled": parental_enabled(session),
        "categories": items,
        "custom_domains": custom,
        "custom_domain_count": len(custom),
    }


def parental_settings_dict(session: Session) -> dict[str, Any]:
    return categories_public(session)


def update_parental_settings(
    session: Session,
    *,
    enabled: bool,
    custom_domains_list: list[str] | None = None,
) -> dict[str, Any]:
    set_parental_enabled(session, enabled)
    if custom_domains_list is not None:
        set_custom_domains(session, custom_domains_list)
    return parental_settings_dict(session)


def family_members(session: Session, group: str) -> list[Subscription]:
    return list(
        session.scalars(
            select(Subscription)
            .where(Subscription.family_group == group)
            .order_by(Subscription.family_index.asc(), Subscription.id.asc())
        ).all()
    )


def is_family_parent(sub: Subscription) -> bool:
    role = (getattr(sub, "family_role", None) or "").strip().lower()
    if role == "parent":
        return True
    if role == "child":
        return False
    # Fallback: first seat
    return int(getattr(sub, "family_index", 0) or 0) == 1


def set_child_restrictions(
    session: Session,
    *,
    parent_sub: Subscription,
    child_sub_id: int,
    categories: list[str],
    schedule: dict[str, Any] | None = None,
    vpn_schedule: dict[str, Any] | None = None,
) -> Subscription:
    if not parental_enabled(session):
        raise ValueError("parental_disabled")
    group = (parent_sub.family_group or "").strip()
    if not group:
        raise ValueError("not_family")
    if not is_family_parent(parent_sub):
        raise ValueError("not_parent")
    child = session.get(Subscription, child_sub_id)
    if not child or child.family_group != group or child.user_id != parent_sub.user_id:
        raise ValueError("child_not_found")
    if child.id == parent_sub.id or is_family_parent(child):
        raise ValueError("cannot_restrict_parent")
    child.family_role = "child"
    child.parental_categories = serialize_categories(categories)
    child.parental_schedule = serialize_schedule(schedule)
    child.vpn_allow_schedule = serialize_schedule(vpn_schedule)
    if not child.vpn_allow_schedule:
        child.vpn_schedule_paused = False
    session.commit()
    session.refresh(child)
    return child


def parental_pause_active(sub: Subscription, *, now: datetime | None = None) -> bool:
    until = getattr(sub, "parental_pause_until", None)
    if not until:
        return False
    when = now or datetime.utcnow()
    if when.tzinfo is not None:
        when = when.astimezone(timezone.utc).replace(tzinfo=None)
    return until > when


def set_child_pause_day(
    session: Session,
    *,
    parent_sub: Subscription,
    child_sub_id: int,
    hours: int | None = None,
    until: datetime | None = None,
) -> Subscription:
    """Freeze child VPN until a time without deleting the config."""
    if not parental_enabled(session):
        raise ValueError("parental_disabled")
    group = (parent_sub.family_group or "").strip()
    if not group:
        raise ValueError("not_family")
    if not is_family_parent(parent_sub):
        raise ValueError("not_parent")
    child = session.get(Subscription, child_sub_id)
    if not child or child.family_group != group or child.user_id != parent_sub.user_id:
        raise ValueError("child_not_found")
    if child.id == parent_sub.id or is_family_parent(child):
        raise ValueError("cannot_restrict_parent")
    now = datetime.utcnow()
    if until is not None:
        pause_until = until
        if pause_until.tzinfo is not None:
            pause_until = pause_until.astimezone(timezone.utc).replace(tzinfo=None)
    else:
        h = int(hours or 24)
        if h < 1 or h > 24 * 14:
            raise ValueError("bad_pause_hours")
        pause_until = now + timedelta(hours=h)
    if pause_until <= now:
        raise ValueError("pause_in_past")
    child.family_role = "child"
    child.parental_pause_until = pause_until
    session.commit()
    session.refresh(child)
    return child


def clear_child_pause_day(
    session: Session,
    *,
    parent_sub: Subscription,
    child_sub_id: int,
) -> Subscription:
    if not parental_enabled(session):
        raise ValueError("parental_disabled")
    group = (parent_sub.family_group or "").strip()
    if not group:
        raise ValueError("not_family")
    if not is_family_parent(parent_sub):
        raise ValueError("not_parent")
    child = session.get(Subscription, child_sub_id)
    if not child or child.family_group != group or child.user_id != parent_sub.user_id:
        raise ValueError("child_not_found")
    child.parental_pause_until = None
    session.commit()
    session.refresh(child)
    return child


def child_vpn_allowed_now(sub: Subscription, *, now: datetime | None = None) -> bool:
    """Whether a child config should be able to connect right now (allow-window)."""
    if not bool(getattr(sub, "enabled", True)):
        return False
    if getattr(sub, "payg_paused_by_user", False):
        return False
    when = now or datetime.utcnow()
    if when.tzinfo is not None:
        when = when.astimezone(timezone.utc).replace(tzinfo=None)
    if sub.expires_at and sub.expires_at <= when:
        return False
    if parental_pause_active(sub, now=when):
        return False
    throttled = getattr(sub, "abuse_throttled_until", None)
    if throttled and throttled > when:
        return False
    sched = parse_schedule(getattr(sub, "vpn_allow_schedule", None))
    if not sched:
        return True
    return schedule_active_now(sched)


def sync_vpn_allow_schedules(session: Session, panel) -> dict[str, Any]:
    """Enable/disable child clients for allow-window + pause-day."""
    rows = list(
        session.scalars(
            select(Subscription).where(Subscription.family_group.is_not(None))
        ).all()
    )
    changed = 0
    errors: list[str] = []
    checked = 0
    now = datetime.utcnow()
    for sub in rows:
        if is_family_parent(sub):
            continue
        email = (sub.xui_email or "").strip()
        if not email:
            continue
        has_sched = bool(parse_schedule(getattr(sub, "vpn_allow_schedule", None)))
        paused = bool(getattr(sub, "vpn_schedule_paused", False))
        pause_day = parental_pause_active(sub, now=now)
        until = getattr(sub, "parental_pause_until", None)
        if until and not pause_day:
            sub.parental_pause_until = None
            until = None
        if not has_sched and not paused and not pause_day and not until:
            continue
        checked += 1
        want_on = child_vpn_allowed_now(sub, now=now)
        try:
            if want_on:
                if paused:
                    panel.set_enabled(email, True)
                    sub.vpn_schedule_paused = False
                    changed += 1
            elif has_sched or pause_day:
                panel.set_enabled(email, False)
                if not paused:
                    sub.vpn_schedule_paused = True
                    changed += 1
            elif paused:
                if bool(sub.enabled) and not getattr(sub, "payg_paused_by_user", False):
                    panel.set_enabled(email, True)
                sub.vpn_schedule_paused = False
                changed += 1
        except Exception as exc:  # noqa: BLE001
            logger.exception("vpn allow schedule sync failed sub=%s", sub.id)
            errors.append(f"{email}: {exc}")

    if changed:
        session.commit()
    return {"ok": not errors, "checked": checked, "changed": changed, "errors": errors}


def maybe_sync_vpn_allow_schedules(session: Session, panel) -> dict[str, Any]:
    """Apply VPN allow windows every maintenance cycle (minute-level)."""
    return sync_vpn_allow_schedules(session, panel)


def collect_restriction_groups(session: Session) -> dict[tuple[str, ...], list[str]]:
    """Map frozenset of category keys → list of xui emails."""
    rows = list(
        session.scalars(
            select(Subscription).where(
                Subscription.family_group.is_not(None),
                Subscription.parental_categories.is_not(None),
                Subscription.enabled.is_(True),
            )
        ).all()
    )
    groups: dict[tuple[str, ...], list[str]] = {}
    for sub in rows:
        keys = tuple(parse_categories(sub.parental_categories))
        if not keys:
            continue
        if (getattr(sub, "family_role", None) or "child") == "parent":
            continue
        sched = parse_schedule(getattr(sub, "parental_schedule", None))
        if sched and not schedule_active_now(sched):
            continue
        email = (sub.xui_email or "").strip()
        if not email:
            continue
        groups.setdefault(keys, []).append(email)
    return groups


def build_parental_rules(session: Session) -> list[dict[str, Any]]:
    if not parental_enabled(session):
        return []
    groups = collect_restriction_groups(session)
    rules: list[dict[str, Any]] = []
    for keys, emails in groups.items():
        domains = domains_for_categories(session, list(keys))
        if not domains or not emails:
            continue
        # Marker first so we can identify our rules later if needed
        rule_domains = [MARKER_DOMAIN, *domains]
        rules.append(
            {
                "type": "field",
                "outboundTag": OUTBOUND_TAG,
                "user": sorted(set(emails)),
                "domain": rule_domains,
            }
        )
    return rules


def _ensure_blocked_outbound(xray: dict[str, Any]) -> None:
    outs = xray.setdefault("outbounds", [])
    if not isinstance(outs, list):
        xray["outbounds"] = []
        outs = xray["outbounds"]
    for o in outs:
        if isinstance(o, dict) and o.get("tag") == OUTBOUND_TAG:
            return
    outs.append({"tag": OUTBOUND_TAG, "protocol": "blackhole", "settings": {}})


def _strip_parental_rules(xray: dict[str, Any]) -> None:
    routing = xray.setdefault("routing", {})
    rules = routing.get("rules")
    if not isinstance(rules, list):
        routing["rules"] = []
        return
    kept: list[Any] = []
    for rule in rules:
        if not isinstance(rule, dict):
            kept.append(rule)
            continue
        if rule.get("outboundTag") == OUTBOUND_TAG:
            continue
        domains = rule.get("domain") or []
        if isinstance(domains, list) and MARKER_DOMAIN in domains:
            continue
        kept.append(rule)
    routing["rules"] = kept


def apply_parental_to_xray_config(session: Session, xray: dict[str, Any]) -> dict[str, Any]:
    _ensure_blocked_outbound(xray)
    _strip_parental_rules(xray)
    new_rules = build_parental_rules(session)
    routing = xray.setdefault("routing", {})
    rules = routing.setdefault("rules", [])
    if not isinstance(rules, list):
        routing["rules"] = []
        rules = routing["rules"]
    # Insert parental rules early (after api rule if present)
    insert_at = 0
    for i, rule in enumerate(rules):
        if isinstance(rule, dict) and rule.get("outboundTag") == "api":
            insert_at = i + 1
            break
    for offset, rule in enumerate(new_rules):
        rules.insert(insert_at + offset, rule)
    return xray


def sync_parental_routing(session: Session, panel) -> dict[str, Any]:
    """Push parental block rules to all panels. Returns summary."""
    members = getattr(panel, "members", None) or [panel]
    applied = 0
    errors: list[str] = []
    rule_count = len(build_parental_rules(session))
    for member in members:
        base = getattr(member, "base", "?")
        try:
            tmpl = member.get_xray_template()
            xs = tmpl.get("xraySetting")
            if isinstance(xs, str):
                xs = json.loads(xs)
            if not isinstance(xs, dict):
                raise RuntimeError("invalid xray template")
            xs = apply_parental_to_xray_config(session, xs)
            member.update_xray_template(xs, outbound_test_url=tmpl.get("outboundTestUrl"))
            try:
                member.restart_xray()
            except Exception as restart_exc:  # noqa: BLE001
                # Template saved; restart may time out while xray reloads.
                logger.warning("parental restart slow/failed %s: %s", base, restart_exc)
            applied += 1
        except Exception as exc:  # noqa: BLE001
            logger.exception("parental sync failed %s", base)
            errors.append(f"{base}: {exc}")
    try:
        ensure_xray_access_log(panel)
    except Exception:
        logger.exception("parental access-log enable failed")
    set_setting(session, PARENTAL_RULES_FP, parental_rules_fingerprint(session))
    return {"ok": not errors, "panels": applied, "rule_groups": rule_count, "errors": errors}


def parental_rules_fingerprint(session: Session) -> str:
    import hashlib

    payload = json.dumps(build_parental_rules(session), sort_keys=True, ensure_ascii=False)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def maybe_sync_parental_routing(session: Session, panel) -> dict[str, Any]:
    """Restart Xray only when the active block set changed (schedule windows)."""
    fp = parental_rules_fingerprint(session)
    prev = get_setting(session, PARENTAL_RULES_FP, "")
    if fp == prev:
        return {"ok": True, "skipped": True, "rule_groups": len(build_parental_rules(session))}
    result = sync_parental_routing(session, panel)
    set_setting(session, PARENTAL_RULES_FP, fp)
    return result


def family_seat_dict(sub: Subscription, stats: dict[str, Any] | None = None) -> dict[str, Any]:
    cats = parse_categories(getattr(sub, "parental_categories", None))
    sched = parse_schedule(getattr(sub, "parental_schedule", None))
    vpn_sched = parse_schedule(getattr(sub, "vpn_allow_schedule", None))
    role = (getattr(sub, "family_role", None) or "").strip().lower()
    if not role:
        role = "parent" if int(getattr(sub, "family_index", 0) or 0) == 1 else "child"
    vpn_allowed = child_vpn_allowed_now(sub) if role != "parent" else True
    pause_until = getattr(sub, "parental_pause_until", None)
    pause_on = parental_pause_active(sub) if role != "parent" else False
    out = {
        "id": sub.id,
        "label": sub.label,
        "email": sub.xui_email,
        "family_index": sub.family_index,
        "family_role": role,
        "is_parent": role == "parent",
        "parental_categories": cats,
        "restricted": bool(cats),
        "schedule": sched,
        "schedule_label": schedule_label(sched),
        "schedule_active": schedule_active_now(sched) if sched else True,
        "vpn_schedule": vpn_sched,
        "vpn_schedule_label": schedule_label(vpn_sched),
        "vpn_allowed_now": vpn_allowed,
        "vpn_schedule_paused": bool(getattr(sub, "vpn_schedule_paused", False)),
        "pause_until": pause_until.isoformat() if pause_until else None,
        "pause_active": pause_on,
        "enabled": bool(sub.enabled),
    }
    if stats:
        used = int(stats.get("used_bytes") or 0)
        out.update(
            {
                "used_bytes": used,
                "used_label": stats.get("used_label") or f"{used} B",
                "total_label": stats.get("total_label"),
                "up_label": stats.get("up_label"),
                "down_label": stats.get("down_label"),
                "online": bool(stats.get("online")),
                "status": stats.get("status"),
                "last_online_at": stats.get("last_online_at"),
            }
        )
    return out


ACCESS_LOG_XRAY_PATH = "/var/log/x-ui/xray-access.log"
ACCESS_LOG_OFFSET = "family_access_log_offset"
ACCESS_LOG_CURSOR_PREFIX = "family_xraylog_cursor_"
ACCESS_LOG_CANDIDATES = (
    Path("/var/log/x-ui/xray-access.log"),
    Path("/opt/3x-ui/vpn-bot-data/xray/access.log"),
    Path("/opt/3x-ui/panel-db/xray-access.log"),
    Path("/opt/3x-ui/db/xray-access.log"),
    Path("/etc/x-ui/xray-access.log"),
)
ACCESS_LINE_RE = re.compile(
    r"^(?P<ts>\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}(?:\.\d+)?).*?"
    r"(?P<verdict>accepted|rejected)\s+"
    r"(?P<proto>tcp|udp):(?P<dest>[^:\s]+):(?P<port>\d+)"
    r".*?(?:email:\s*(?P<email>\S+))?",
    re.IGNORECASE,
)
IP_RE = re.compile(r"^\d{1,3}(?:\.\d{1,3}){3}$")
SKIP_DOMAINS = {
    "localhost",
    "vpnshop-parental.invalid",
    "connectivitycheck.gstatic.com",
    "clients3.google.com",
    "detectportal.firefox.com",
}
DOWNLOAD_HINTS = (
    "mediafire.com",
    "mega.nz",
    "mega.co.nz",
    "dropbox.com",
    "wetransfer.com",
    "apkpure.com",
    "apkmirror.com",
    "uptodown.com",
    "play.google.com",
    "dl.google.com",
    "googleusercontent.com",
    "gvt1.com",
    "sourceforge.net",
    "github.com",
    "objects.githubusercontent.com",
)
CATEGORY_LABELS = {
    "tiktok": "تیک‌تاک",
    "instagram": "اینستاگرام",
    "youtube": "یوتیوب",
    "games": "بازی",
    "adult": "بزرگسالان",
    "gambling": "قمار",
    "dating": "دوستیابی",
    "social_extra": "شبکه اجتماعی",
    "download": "دانلود / فایل",
    "telegram": "تلگرام",
    "google": "گوگل",
    "other": "سایر",
}


def _host_matches(host: str, needle: str) -> bool:
    host = host.lower().lstrip(".")
    needle = needle.lower().lstrip(".")
    return host == needle or host.endswith("." + needle)


def classify_domain(host: str) -> str:
    host = (host or "").lower().lstrip(".")
    if any(_host_matches(host, h) for h in DOWNLOAD_HINTS):
        return "download"
    if _host_matches(host, "telegram.org") or _host_matches(host, "t.me") or "telegram" in host:
        return "telegram"
    if host.endswith("google.com") or host.endswith("gstatic.com") or host.endswith("googleapis.com"):
        if "youtube" in host or "video" in host:
            return "youtube"
        return "google"
    for cat in DEFAULT_CATEGORIES:
        for raw in cat.get("domains") or []:
            if not isinstance(raw, str):
                continue
            if raw.startswith("geosite:"):
                continue
            name = raw.split(":", 1)[-1].lstrip(".")
            if name and _host_matches(host, name):
                return str(cat["key"])
    return "other"


def normalize_dest(dest: str) -> str | None:
    host = (dest or "").strip().lower().split("/")[0]
    if host.startswith("[") and "]" in host:
        return None
    if host.startswith("www."):
        host = host[4:]
    if not host or host in SKIP_DOMAINS or IP_RE.match(host):
        return None
    if host.endswith(".invalid"):
        return None
    return host[:255]


def parse_access_ts(raw: str) -> datetime:
    raw = (raw or "").split(".")[0]
    try:
        return datetime.strptime(raw, "%Y/%m/%d %H:%M:%S")
    except ValueError:
        return datetime.utcnow()


def resolve_access_log_path() -> Path | None:
    found: list[Path] = []
    for path in ACCESS_LOG_CANDIDATES:
        if path.is_file():
            found.append(path)
    nonempty = [path for path in found if path.stat().st_size > 0]
    return (nonempty or found or [None])[0]


def family_child_email_map(session: Session) -> dict[str, Subscription]:
    rows = list(
        session.scalars(
            select(Subscription).where(
                Subscription.family_group.is_not(None),
                Subscription.enabled.is_(True),
            )
        ).all()
    )
    out: dict[str, Subscription] = {}
    for sub in rows:
        if is_family_parent(sub):
            continue
        email = (sub.xui_email or "").strip().lower()
        if email:
            out[email] = sub
    return out


def ensure_xray_access_log(panel) -> dict[str, Any]:
    """Turn on Xray access logging once so family activity can be collected."""
    members = getattr(panel, "members", None) or [panel]
    changed = 0
    errors: list[str] = []
    for member in members:
        try:
            tmpl = member.get_xray_template()
            xs = tmpl.get("xraySetting")
            if isinstance(xs, str):
                xs = json.loads(xs)
            if not isinstance(xs, dict):
                raise RuntimeError("invalid xray template")
            log = xs.setdefault("log", {})
            if not isinstance(log, dict):
                log = {}
                xs["log"] = log
            current = str(log.get("access") or "").strip().lower()
            if current and current not in {"none", "null", "/dev/null"}:
                continue
            log["access"] = ACCESS_LOG_XRAY_PATH
            if not log.get("loglevel"):
                log["loglevel"] = "warning"
            member.update_xray_template(xs, outbound_test_url=tmpl.get("outboundTestUrl"))
            try:
                member.restart_xray()
            except Exception as restart_exc:  # noqa: BLE001
                logger.warning("access-log restart slow/failed %s: %s", getattr(member, "base", "?"), restart_exc)
            changed += 1
        except Exception as exc:  # noqa: BLE001
            logger.exception("enable access log failed")
            errors.append(str(exc))
    return {"ok": not errors, "updated": changed, "errors": errors}


def _record_browse_hit(
    session: Session,
    sub: Subscription,
    *,
    domain: str,
    verdict: str,
    seen_at: datetime,
    store_hit: bool,
) -> bool:
    blocked_keys = parse_categories(getattr(sub, "parental_categories", None))
    cat_guess = classify_domain(domain)
    if verdict == "visit" and blocked_keys and cat_guess in blocked_keys:
        verdict = "blocked"
    row = session.scalar(
        select(FamilyBrowseEvent).where(
            FamilyBrowseEvent.subscription_id == sub.id,
            FamilyBrowseEvent.domain == domain,
            FamilyBrowseEvent.verdict == verdict,
        )
    )
    if row:
        row.hit_count = int(row.hit_count or 0) + 1
        if not row.last_seen or seen_at > row.last_seen:
            row.last_seen = seen_at
        row.category = cat_guess
        row.family_group = sub.family_group
    else:
        session.add(
            FamilyBrowseEvent(
                subscription_id=sub.id,
                family_group=sub.family_group,
                domain=domain,
                category=cat_guess,
                verdict=verdict,
                hit_count=1,
                first_seen=seen_at,
                last_seen=seen_at,
            )
        )
    if store_hit:
        session.add(
            FamilyBrowseHit(
                subscription_id=sub.id,
                domain=domain,
                category=cat_guess,
                verdict=verdict,
                seen_at=seen_at,
            )
        )
    return True


def dest_from_to_address(raw: str) -> str | None:
    text = (raw or "").strip()
    if not text:
        return None
    proto, _, rest = text.partition(":")
    if proto.lower() in {"tcp", "udp"} and rest:
        text = rest
    if text.startswith("["):
        return None
    host, sep, tail = text.rpartition(":")
    if sep and tail.isdigit():
        text = host
    return normalize_dest(text)


def parse_api_access_ts(raw: Any) -> datetime:
    text = str(raw or "").strip()
    if not text:
        return datetime.utcnow()
    try:
        if text.endswith("Z"):
            text = text[:-1] + "+00:00"
        dt = datetime.fromisoformat(text)
        if dt.tzinfo:
            return dt.astimezone(timezone.utc).replace(tzinfo=None)
        return dt
    except ValueError:
        return datetime.utcnow()


def _access_verdict(row: dict[str, Any]) -> str:
    outbound = str(row.get("Outbound") or "").lower()
    if any(token in outbound for token in ("block", "blackhole", "reject", "parental")):
        return "blocked"
    event = str(row.get("Event") or "").lower()
    if event in {"1", "rejected", "reject", "blocked"}:
        return "blocked"
    return "visit"


def _panel_cursor_key(panel) -> str:
    sid = getattr(panel, "server_id", None)
    if sid is None:
        sid = "p"
    return f"{ACCESS_LOG_CURSOR_PREFIX}{sid}"


def _ingest_file_access_log(session: Session, children: dict[str, Subscription]) -> tuple[int, int]:
    path = resolve_access_log_path()
    if path is None:
        return 0, 0
    size = path.stat().st_size
    if size <= 0:
        return 0, 0
    try:
        offset = int(get_setting(session, ACCESS_LOG_OFFSET, "0") or "0")
    except ValueError:
        offset = 0
    if offset > size:
        offset = 0
    if offset == 0 and size > 4_000_000:
        offset = max(0, size - 4_000_000)
    stored = 0
    lines_read = 0
    with path.open("r", encoding="utf-8", errors="ignore") as fh:
        fh.seek(offset)
        chunk = fh.read()
        new_offset = fh.tell()
    if offset and chunk.startswith("\n") is False and "\n" in chunk:
        chunk = chunk.split("\n", 1)[-1]
    for line in chunk.splitlines():
        lines_read += 1
        match = ACCESS_LINE_RE.search(line)
        if not match:
            continue
        email = (match.group("email") or "").strip().lower()
        sub = children.get(email)
        if not sub:
            continue
        domain = normalize_dest(match.group("dest") or "")
        if not domain:
            continue
        verdict = "blocked" if (match.group("verdict") or "").lower() == "rejected" else "visit"
        _record_browse_hit(
            session,
            sub,
            domain=domain,
            verdict=verdict,
            seen_at=parse_access_ts(match.group("ts")),
            store_hit=stored < 800,
        )
        stored += 1
    set_setting(session, ACCESS_LOG_OFFSET, str(new_offset))
    return lines_read, stored


def _ingest_panel_access_events(
    session: Session,
    panel,
    children: dict[str, Subscription],
) -> tuple[int, int]:
    members = getattr(panel, "members", None) or [panel]
    stored = 0
    seen = 0
    emails = list(children.keys())
    for member in members:
        cursor_key = _panel_cursor_key(member)
        raw_cursor = (get_setting(session, cursor_key, "") or "").strip()
        cursor_at = parse_api_access_ts(raw_cursor) if raw_cursor else None
        newest = cursor_at
        rows: list[dict[str, Any]] = []
        if emails:
            for email in emails:
                try:
                    rows.extend(member.get_xray_access_events(count=1500, email=email))
                except Exception:
                    logger.exception("xray access fetch failed %s email=%s", getattr(member, "base", "?"), email)
        else:
            try:
                rows.extend(member.get_xray_access_events(count=400))
            except Exception:
                logger.exception("xray access fetch failed %s", getattr(member, "base", "?"))
        for row in rows:
            seen += 1
            email = str(row.get("Email") or "").strip().lower()
            sub = children.get(email)
            if not sub:
                continue
            seen_at = parse_api_access_ts(row.get("DateTime"))
            if newest is None or seen_at > newest:
                newest = seen_at
            if cursor_at and seen_at <= cursor_at:
                continue
            domain = dest_from_to_address(str(row.get("ToAddress") or ""))
            if not domain:
                continue
            _record_browse_hit(
                session,
                sub,
                domain=domain,
                verdict=_access_verdict(row),
                seen_at=seen_at,
                store_hit=stored < 800,
            )
            stored += 1
        if newest:
            stamp = newest.isoformat(timespec="milliseconds")
            if newest.tzinfo is None:
                stamp += "Z"
            set_setting(session, cursor_key, stamp)
    return seen, stored


def ingest_family_browse_logs(session: Session, panel=None) -> dict[str, int]:
    """Collect family-child destinations from local files and every panel's Xray log API."""
    children = family_child_email_map(session)
    if not children:
        return {"ok": 1, "lines": 0, "stored": 0, "reason": "no_children"}

    file_lines, file_stored = _ingest_file_access_log(session, children)
    api_lines, api_stored = (0, 0)
    if panel is not None:
        try:
            api_lines, api_stored = _ingest_panel_access_events(session, panel, children)
        except Exception:
            logger.exception("family xray API ingest failed")
    cutoff = datetime.utcnow() - timedelta(days=7)
    session.execute(delete(FamilyBrowseHit).where(FamilyBrowseHit.seen_at < cutoff))
    session.commit()
    stored = file_stored + api_stored
    return {
        "ok": 1,
        "lines": file_lines + api_lines,
        "stored": stored,
        "file_stored": file_stored,
        "api_stored": api_stored,
    }


def list_child_activity(session: Session, child: Subscription, *, limit: int = 80) -> dict[str, Any]:
    limit = max(10, min(int(limit or 80), 200))
    sites = list(
        session.scalars(
            select(FamilyBrowseEvent)
            .where(FamilyBrowseEvent.subscription_id == child.id)
            .order_by(FamilyBrowseEvent.last_seen.desc())
            .limit(120)
        ).all()
    )
    recent = list(
        session.scalars(
            select(FamilyBrowseHit)
            .where(FamilyBrowseHit.subscription_id == child.id)
            .order_by(FamilyBrowseHit.seen_at.desc())
            .limit(limit)
        ).all()
    )
    hits = sum(int(s.hit_count or 0) for s in sites)
    blocked = sum(int(s.hit_count or 0) for s in sites if s.verdict == "blocked")
    downloads = sum(int(s.hit_count or 0) for s in sites if s.category == "download")

    def site_dict(row: FamilyBrowseEvent) -> dict[str, Any]:
        return {
            "domain": row.domain,
            "category": row.category,
            "category_label": CATEGORY_LABELS.get(row.category, "سایر"),
            "verdict": row.verdict,
            "verdict_label": "مسدود شد" if row.verdict == "blocked" else "بازدید",
            "hit_count": int(row.hit_count or 0),
            "first_seen": row.first_seen.isoformat() if row.first_seen else None,
            "last_seen": row.last_seen.isoformat() if row.last_seen else None,
        }

    return {
        "child": family_seat_dict(child),
        "logging": {
            "ready": True,
            "note": "فقط دامنه و سرویس دیده می‌شود، نه صفحه یا نام فایل.",
        },
        "summary": {
            "domains": len(sites),
            "hits": hits,
            "blocked": blocked,
            "downloads": downloads,
        },
        "sites": [site_dict(s) for s in sites],
        "recent": [
            {
                "domain": h.domain,
                "category": h.category,
                "category_label": CATEGORY_LABELS.get(h.category, "سایر"),
                "verdict": h.verdict,
                "verdict_label": "مسدود شد" if h.verdict == "blocked" else "بازدید",
                "seen_at": h.seen_at.isoformat() if h.seen_at else None,
            }
            for h in recent
        ],
        "disclaimer": "اتصال‌ها رمزنگاری شده‌اند؛ والد دامنه (مثلاً instagram.com) را می‌بیند، نه پست یا فایل دقیق.",
    }
