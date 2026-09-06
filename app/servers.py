from __future__ import annotations

import logging
from datetime import datetime
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import Settings, _parse_int_list
from app.models import ShopSetting, Subscription, VpnServer
from app.panel import (
    CONFIG_TYPE_DEFS,
    CONFIG_TYPE_KEYS,
    PanelError,
    PanelHub,
    XUIPanel,
    config_flags_dict,
    parse_config_flags,
    serialize_config_flags,
)

logger = logging.getLogger(__name__)

PRIMARY_ENABLED_KEY = "vpn_primary_enabled"
PRIMARY_CONFIG_FLAGS_KEY = "vpn_primary_config_flags"

_hub: PanelHub | None = None
_hub_key: tuple | None = None


def _mask_token(token: str) -> str:
    raw = (token or "").strip()
    if len(raw) <= 8:
        return "••••"
    return f"{raw[:4]}••••{raw[-4:]}"


def _region_for(name: str, country_code: str) -> str:
    return (country_code or name or "").strip()


def _get_setting(session: Session, key: str, default: str = "") -> str:
    row = session.get(ShopSetting, key)
    if not row or row.value is None:
        return default
    return str(row.value)


def _set_setting(session: Session, key: str, value: str) -> None:
    row = session.get(ShopSetting, key)
    if row:
        row.value = value
    else:
        session.add(ShopSetting(key=key, value=value))


def primary_enabled(session: Session) -> bool:
    return _get_setting(session, PRIMARY_ENABLED_KEY, "1").strip() not in {"0", "false", "False", "no"}


def primary_config_flags_raw(session: Session) -> str:
    return _get_setting(session, PRIMARY_CONFIG_FLAGS_KEY, "")


def config_types_catalog() -> list[dict[str, Any]]:
    return [{"key": item["key"], "label": item["label"]} for item in CONFIG_TYPE_DEFS]


def vpn_server_dict(row: VpnServer) -> dict[str, Any]:
    flags = getattr(row, "config_flags", "") or ""
    health_ok = bool(getattr(row, "health_ok", True))
    return {
        "id": row.id,
        "name": row.name,
        "country_code": row.country_code or "",
        "xui_base_url": row.xui_base_url,
        "token_masked": _mask_token(row.xui_api_token),
        "inbound_ids": row.inbound_ids or "",
        "public_host": row.public_host or "",
        "public_ip": row.public_ip or "",
        "enabled": bool(row.enabled),
        "primary": False,
        "config_flags": config_flags_dict(flags),
        "config_flags_raw": serialize_config_flags(parse_config_flags(flags)),
        "health_ok": health_ok,
        "health_fail_count": int(getattr(row, "health_fail_count", 0) or 0),
        "last_ping_ms": getattr(row, "last_ping_ms", None),
        "last_health_at": row.last_health_at.isoformat() if getattr(row, "last_health_at", None) else None,
        "links_visible": bool(row.enabled) and health_ok,
    }


def primary_server_dict(session: Session, settings: Settings) -> dict[str, Any]:
    from app.jobs import primary_health_dict

    ids = ",".join(str(i) for i in settings.xui_inbound_ids)
    label = (settings.vpn_primary_label or "").strip() or "سرور اصلی"
    flags = primary_config_flags_raw(session)
    health = primary_health_dict(session)
    enabled = primary_enabled(session)
    return {
        "id": 0,
        "name": label,
        "country_code": settings.vpn_primary_label or "",
        "xui_base_url": settings.xui_base_url,
        "token_masked": _mask_token(settings.xui_api_token),
        "inbound_ids": ids,
        "public_host": settings.public_host,
        "public_ip": settings.public_ip,
        "enabled": enabled,
        "primary": True,
        "config_flags": config_flags_dict(flags),
        "config_flags_raw": serialize_config_flags(parse_config_flags(flags)),
        **health,
        "links_visible": enabled and bool(health.get("health_ok", True)),
    }


def list_vpn_servers(session: Session, settings: Settings) -> list[dict[str, Any]]:
    extras = list(session.scalars(select(VpnServer).order_by(VpnServer.id.asc())).all())
    return [primary_server_dict(session, settings), *[vpn_server_dict(row) for row in extras]]


def list_vpn_servers_admin(session: Session, settings: Settings) -> dict[str, Any]:
    return {
        "items": list_vpn_servers(session, settings),
        "config_types": config_types_catalog(),
    }


def panel_for_server(settings: Settings, row: VpnServer) -> XUIPanel:
    panel = XUIPanel(
        settings,
        base_url=row.xui_base_url,
        api_token=row.xui_api_token,
        inbound_ids=_parse_int_list(row.inbound_ids, []),
        public_host=row.public_host or settings.public_host,
        public_ip=row.public_ip or settings.public_ip,
        region=_region_for(row.name, row.country_code),
    )
    panel.server_id = int(row.id)
    health_ok = bool(getattr(row, "health_ok", True))
    panel.links_enabled = bool(row.enabled) and health_ok
    panel.allowed_configs = parse_config_flags(getattr(row, "config_flags", "") or "")
    return panel


def probe_vpn_panel(
    settings: Settings,
    *,
    base_url: str,
    api_token: str,
    inbound_ids: str,
    public_host: str,
    public_ip: str,
) -> None:
    ids = _parse_int_list(inbound_ids, [])
    if not ids:
        raise ValueError("inbound_ids_required")
    panel = XUIPanel(
        settings,
        base_url=base_url,
        api_token=api_token,
        inbound_ids=ids,
        public_host=public_host,
        public_ip=public_ip,
    )
    try:
        panel.online_emails()
    finally:
        panel.close()


def add_vpn_server(
    session: Session,
    settings: Settings,
    *,
    name: str,
    country_code: str,
    xui_base_url: str,
    xui_api_token: str,
    inbound_ids: str,
    public_host: str,
    public_ip: str,
) -> VpnServer:
    name = (name or "").strip()
    if not name:
        raise ValueError("name_required")
    base = (xui_base_url or "").strip().rstrip("/")
    token = (xui_api_token or "").strip()
    if not base or not token:
        raise ValueError("panel_required")
    host = (public_host or "").strip()
    ip = (public_ip or "").strip()
    if not host and not ip:
        raise ValueError("endpoint_required")
    probe_vpn_panel(
        settings,
        base_url=base,
        api_token=token,
        inbound_ids=inbound_ids,
        public_host=host,
        public_ip=ip,
    )
    row = VpnServer(
        name=name,
        country_code=(country_code or "").strip().upper(),
        xui_base_url=base,
        xui_api_token=token,
        inbound_ids=",".join(str(i) for i in _parse_int_list(inbound_ids, [])),
        public_host=host,
        public_ip=ip,
        enabled=True,
        config_flags="",
    )
    session.add(row)
    session.commit()
    session.refresh(row)
    invalidate_panel_hub()
    return row


def apply_panel_subscription_state(session: Session, panel: XUIPanel, *, enabled: bool) -> dict[str, int]:
    """Enable/disable all shop subscription emails on one panel."""
    subs = list(session.scalars(select(Subscription)).all())
    if not subs:
        return {"updated": 0, "failed": 0}
    updated = failed = 0
    for sub in subs:
        email = (sub.xui_email or "").strip()
        if not email:
            continue
        want = bool(enabled and sub.enabled)
        try:
            panel.set_enabled(email, want)
            updated += 1
        except Exception:
            failed += 1
            logger.exception("set_enabled failed %s on %s", email, panel.base)
    return {"updated": updated, "failed": failed}


def set_vpn_server_enabled(session: Session, settings: Settings, server_id: int, enabled: bool) -> dict[str, Any]:
    enabled = bool(enabled)
    if server_id == 0:
        _set_setting(session, PRIMARY_ENABLED_KEY, "1" if enabled else "0")
        session.commit()
        invalidate_panel_hub()
        panel = XUIPanel(settings, region=(settings.vpn_primary_label or "").strip())
        panel.server_id = 0
        try:
            apply_panel_subscription_state(session, panel, enabled=enabled)
        finally:
            panel.close()
        return primary_server_dict(session, settings)

    row = session.get(VpnServer, server_id)
    if not row:
        raise ValueError("server_not_found")
    row.enabled = enabled
    session.commit()
    session.refresh(row)
    invalidate_panel_hub()
    panel = panel_for_server(settings, row)
    try:
        apply_panel_subscription_state(session, panel, enabled=enabled)
        if enabled:
            try:
                sync_telegram_proxy_for_panel(session, panel)
            except Exception:
                logger.exception("telegram proxy bootstrap failed for enabled server %s", row.id)
    finally:
        panel.close()
    return vpn_server_dict(row)


def set_vpn_server_visibility(
    session: Session,
    settings: Settings,
    server_id: int,
    *,
    enabled: bool | None = None,
    configs: dict[str, bool] | None = None,
) -> dict[str, Any]:
    if server_id == 0:
        if configs is not None:
            _set_setting(session, PRIMARY_CONFIG_FLAGS_KEY, serialize_config_flags(configs))
        if enabled is not None:
            prev = primary_enabled(session)
            _set_setting(session, PRIMARY_ENABLED_KEY, "1" if enabled else "0")
            session.commit()
            invalidate_panel_hub()
            if bool(enabled) != prev:
                panel = XUIPanel(settings, region=(settings.vpn_primary_label or "").strip())
                panel.server_id = 0
                try:
                    apply_panel_subscription_state(session, panel, enabled=bool(enabled))
                finally:
                    panel.close()
            return primary_server_dict(session, settings)
        session.commit()
        invalidate_panel_hub()
        return primary_server_dict(session, settings)

    row = session.get(VpnServer, server_id)
    if not row:
        raise ValueError("server_not_found")
    prev_enabled = bool(row.enabled)
    if configs is not None:
        row.config_flags = serialize_config_flags(configs)
    if enabled is not None:
        row.enabled = bool(enabled)
    session.commit()
    session.refresh(row)
    invalidate_panel_hub()
    if enabled is not None and bool(enabled) != prev_enabled:
        panel = panel_for_server(settings, row)
        try:
            apply_panel_subscription_state(session, panel, enabled=bool(enabled))
            if enabled:
                try:
                    sync_telegram_proxy_for_panel(session, panel)
                except Exception:
                    logger.exception("telegram proxy bootstrap failed for enabled server %s", row.id)
        finally:
            panel.close()
    return vpn_server_dict(row)


def delete_vpn_server(session: Session, server_id: int) -> None:
    row = session.get(VpnServer, server_id)
    if not row:
        raise ValueError("server_not_found")
    session.delete(row)
    session.commit()
    invalidate_panel_hub()


def invalidate_panel_hub() -> None:
    global _hub, _hub_key
    if _hub is not None:
        try:
            _hub.close()
        except Exception:
            pass
    _hub = None
    _hub_key = None


def get_panel_hub(settings: Settings, session: Session) -> PanelHub:
    global _hub, _hub_key
    from app.jobs import primary_health_dict

    extras_all = list(session.scalars(select(VpnServer).order_by(VpnServer.id)).all())
    primary_on = primary_enabled(session)
    primary_flags = primary_config_flags_raw(session)
    primary_health = primary_health_dict(session)
    primary_links = primary_on and bool(primary_health.get("health_ok", True))
    key = (
        primary_on,
        primary_links,
        primary_flags,
        tuple(
            (
                r.id,
                bool(r.enabled),
                bool(getattr(r, "health_ok", True)),
                getattr(r, "config_flags", "") or "",
                r.xui_base_url,
                r.xui_api_token,
                r.inbound_ids,
                r.public_host,
                r.public_ip,
                r.name,
                r.country_code,
            )
            for r in extras_all
        ),
    )
    if _hub is not None and _hub_key == key:
        return _hub
    invalidate_panel_hub()
    primary = XUIPanel(settings, region=(settings.vpn_primary_label or "").strip())
    primary.server_id = 0
    primary.links_enabled = primary_links
    primary.allowed_configs = parse_config_flags(primary_flags)
    # Keep disabled extras in hub for revoke/extend fanout, but mark links_enabled.
    extra_panels = [panel_for_server(settings, row) for row in extras_all]
    _hub = PanelHub(primary, extra_panels)
    _hub_key = key
    return _hub


def sync_telegram_proxy_for_panel(session: Session, panel: XUIPanel) -> dict[str, int]:
    """Ensure MTProto inbound exists and attach every enabled subscription email."""
    emails = [
        str(email)
        for email in session.scalars(select(Subscription.xui_email).where(Subscription.enabled.is_(True))).all()
        if str(email).strip()
    ]
    if not emails:
        return {"attached": 0, "skipped": 0, "failed": 0}
    inbound_id = panel.ensure_telegram_proxy_inbound()
    return panel.attach_emails_to_inbound(emails, inbound_id)


def sync_subscriptions_to_server(
    session: Session,
    settings: Settings,
    server_id: int,
) -> dict[str, Any]:
    row = session.get(VpnServer, server_id)
    if not row:
        raise ValueError("server_not_found")
    extra = panel_for_server(settings, row)
    primary = XUIPanel(settings)
    result = {"synced": 0, "skipped": 0, "failed": 0, "errors": []}
    subs = list(session.scalars(select(Subscription).where(Subscription.enabled.is_(True))).all())
    try:
        try:
            tg_sync = sync_telegram_proxy_for_panel(session, extra)
            result["telegram_attached"] = int(tg_sync.get("attached") or 0)
            result["telegram_skipped"] = int(tg_sync.get("skipped") or 0)
            result["telegram_failed"] = int(tg_sync.get("failed") or 0)
        except Exception as exc:
            logger.exception("telegram proxy sync failed on %s", extra.base)
            result["telegram_attached"] = 0
            result["telegram_skipped"] = 0
            result["telegram_failed"] = 0
            result["errors"].append(f"telegram proxy: {exc}")
        for sub in subs:
            email = sub.xui_email
            try:
                extra.get_client(email)
                result["skipped"] += 1
                continue
            except PanelError:
                pass
            try:
                src = primary.get_client(email)
            except PanelError as exc:
                result["failed"] += 1
                result["errors"].append(f"{email}: primary missing ({exc})")
                continue
            uuid = str(src.get("uuid") or src.get("id") or "") or None
            sub_id = str(src.get("subId") or src.get("sub_id") or "") or None
            total = int(src.get("totalGB") or src.get("total") or 0)
            traffic_gb = 0 if total <= 0 else max(1, round(total / (1024 * 1024 * 1024)))
            days = 0
            if sub.expires_at:
                days = max(1, (sub.expires_at - datetime.utcnow()).days)
            try:
                extra.create_client(
                    email=email,
                    duration_days=days,
                    traffic_gb=traffic_gb,
                    limit_ip=int(src.get("limitIp") or 2),
                    tg_id=int(src.get("tgId") or 0),
                    comment=str(src.get("comment") or "vpn-shop"),
                    client_id=uuid,
                    sub_id=sub_id,
                )
                if not sub.enabled or not row.enabled:
                    extra.set_enabled(email, False)
                result["synced"] += 1
            except Exception as exc:
                logger.exception("sync client failed %s -> %s", email, extra.base)
                result["failed"] += 1
                result["errors"].append(f"{email}: {exc}")
    finally:
        extra.close()
        primary.close()
    if len(result["errors"]) > 8:
        result["errors"] = result["errors"][:8] + ["…"]
    return result
