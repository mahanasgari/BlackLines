from __future__ import annotations

import base64
import json
import logging
import secrets
import socket
import string
import time
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any
from urllib.parse import parse_qs, quote, unquote, urlencode

import httpx

from app.config import Settings

logger = logging.getLogger(__name__)


class PanelError(RuntimeError):
    pass


CLIENT_UPDATE_SKIP = {
    "inboundIds",
    "inbounds",
    "uuid",
    "up",
    "down",
    "allTime",
    "lastOnline",
    "traffic",
    "online",
    "depleted",
}


def new_client_sub_id(length: int = 16) -> str:
    alphabet = string.ascii_lowercase + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(length))


class XUIPanel:
    def __init__(
        self,
        settings: Settings,
        *,
        base_url: str | None = None,
        api_token: str | None = None,
        inbound_ids: list[int] | None = None,
        public_host: str | None = None,
        public_ip: str | None = None,
        region: str = "",
    ):
        self.settings = settings
        self.base = (base_url or settings.xui_base_url).rstrip("/")
        self.inbound_ids = list(inbound_ids if inbound_ids is not None else settings.xui_inbound_ids)
        self.public_host = public_host if public_host is not None else settings.public_host
        self.public_ip = public_ip if public_ip is not None else settings.public_ip
        self.region = region or ""
        self.server_id: int = 0
        self.links_enabled: bool = True
        self.allowed_configs: set[str] | None = None  # None = all config types
        self._telegram_inbound_id: int | None = None
        token = api_token or settings.xui_api_token
        self._client = httpx.Client(
            timeout=30.0,
            headers={
                "Authorization": f"Bearer {token}",
                "Accept": "application/json",
            },
        )

    def close(self) -> None:
        self._client.close()

    def _request(self, method: str, path: str, **kwargs: Any) -> dict[str, Any]:
        url = f"{self.base}{path}"
        response = self._client.request(method, url, **kwargs)
        try:
            data = response.json()
        except Exception as exc:  # noqa: BLE001
            raise PanelError(f"Invalid JSON from panel ({response.status_code}): {response.text[:200]}") from exc
        if response.status_code >= 400:
            raise PanelError(f"HTTP {response.status_code}: {data}")
        if isinstance(data, dict) and data.get("success") is False:
            raise PanelError(data.get("msg") or "Panel request failed")
        return data if isinstance(data, dict) else {"success": True, "obj": data}

    def create_client(
        self,
        *,
        email: str,
        duration_days: int,
        traffic_gb: int,
        limit_ip: int,
        tg_id: int,
        comment: str = "vpn-shop",
        client_id: str | None = None,
        sub_id: str | None = None,
    ) -> dict[str, Any]:
        expiry_ms = 0
        if duration_days > 0:
            expiry = datetime.now(timezone.utc) + timedelta(days=duration_days)
            expiry_ms = int(expiry.timestamp() * 1000)

        total_bytes = 0 if traffic_gb <= 0 else int(traffic_gb) * 1024 * 1024 * 1024
        inbound_ids = list(self.inbound_ids)
        try:
            telegram_id = self.ensure_telegram_proxy_inbound()
            if telegram_id and telegram_id not in inbound_ids:
                inbound_ids.append(telegram_id)
        except Exception:
            logger.exception("telegram proxy inbound ensure failed %s", self.base)

        # Reality inbound needs vision flow; other inbounds ignore/clear as needed.
        # Panel accepts one flow on the client record; vision is required for Reality.
        client_obj: dict[str, Any] = {
            "email": email,
            "enable": True,
            "flow": "xtls-rprx-vision",
            "totalGB": total_bytes,
            "expiryTime": expiry_ms,
            "limitIp": limit_ip,
            "tgId": tg_id,
            "comment": comment,
        }
        if client_id:
            client_obj["id"] = client_id
        if sub_id:
            client_obj["subId"] = sub_id
        payload = {
            "client": client_obj,
            "inboundIds": inbound_ids,
        }
        self._request("POST", "/panel/api/clients/add", json=payload)
        return self.get_client(email)

    def get_client(self, email: str) -> dict[str, Any]:
        data = self._request("GET", f"/panel/api/clients/get/{quote(email, safe='')}")
        obj = data.get("obj")
        if not obj:
            raise PanelError(f"Client not found: {email}")
        # 3x-ui returns {client: {...}, inboundIds: [...]}
        if isinstance(obj, dict) and "client" in obj:
            client = dict(obj["client"])
            client["inboundIds"] = obj.get("inboundIds") or []
            return client
        return obj

    def get_links(self, email: str) -> list[str]:
        data = self._request("GET", f"/panel/api/clients/links/{quote(email, safe='')}")
        return list(data.get("obj") or [])

    def get_traffic(self, email: str) -> dict[str, Any]:
        data = self._request("GET", f"/panel/api/clients/traffic/{quote(email, safe='')}")
        obj = data.get("obj")
        return obj if isinstance(obj, dict) else {}

    def get_xray_access_events(self, *, count: int = 400, email: str | None = None) -> list[dict[str, Any]]:
        """Last N Xray access rows (optionally filtered by client email)."""
        payload = {
            "showDirect": "true",
            "showBlocked": "true",
            "showProxy": "true",
        }
        if email:
            payload["filter"] = email
        n = max(20, min(int(count or 400), 2000))
        data = self._request("POST", f"/panel/api/server/xraylogs/{n}", data=payload)
        obj = data.get("obj")
        if isinstance(obj, list):
            return [row for row in obj if isinstance(row, dict)]
        return []

    def online_emails(self) -> set[str]:
        data = self._request("POST", "/panel/api/clients/onlines", json={})
        obj = data.get("obj") or []
        return {str(e) for e in obj}

    def get_client_ips(self, email: str) -> list[dict[str, Any]]:
        data = self._request("POST", f"/panel/api/clients/ips/{quote(email, safe='')}", json={})
        obj = data.get("obj") or []
        if not isinstance(obj, list):
            return []
        return [item for item in obj if isinstance(item, dict)]

    def last_online_map(self) -> dict[str, int]:
        data = self._request("POST", "/panel/api/clients/lastOnline", json={})
        obj = data.get("obj") or {}
        if not isinstance(obj, dict):
            return {}
        out: dict[str, int] = {}
        for key, value in obj.items():
            try:
                out[str(key)] = int(value or 0)
            except (TypeError, ValueError):
                continue
        return out

    def set_enabled(self, email: str, enabled: bool) -> None:
        path = "/panel/api/clients/bulkEnable" if enabled else "/panel/api/clients/bulkDisable"
        self._request("POST", path, json={"emails": [email]})

    def delete_client(self, email: str) -> None:
        self._request("POST", f"/panel/api/clients/del/{quote(email, safe='')}")

    def clear_client_ips(self, email: str) -> None:
        try:
            self._request("POST", f"/panel/api/clients/clearIps/{quote(email, safe='')}")
        except PanelError:
            logger.warning("clear client ips failed %s", email)

    def update_client(self, email: str, updates: dict[str, Any]) -> dict[str, Any]:
        current = self.get_client(email)
        payload = {
            key: value
            for key, value in current.items()
            if key not in CLIENT_UPDATE_SKIP
        }
        ident = payload.get("id") or current.get("id") or current.get("uuid")
        if ident:
            payload["id"] = ident
        payload.update(updates)
        self._request("POST", f"/panel/api/clients/update/{quote(email, safe='')}", json=payload)
        return self.get_client(email)

    def rotate_client_identity(self, email: str) -> dict[str, Any]:
        new_id = str(uuid.uuid4())
        new_sub = new_client_sub_id()
        updated = self.update_client(email, {"id": new_id, "subId": new_sub})
        got_id = str(updated.get("uuid") or updated.get("id") or "")
        got_sub = str(updated.get("subId") or updated.get("sub_id") or "")
        if got_id != new_id or got_sub != new_sub:
            raise PanelError("panel did not accept the new client identity")
        self.clear_client_ips(email)
        return updated

    def extend_days(self, email: str, days: int) -> None:
        self._request(
            "POST",
            "/panel/api/clients/bulkAdjust",
            json={"emails": [email], "addDays": days},
        )

    def add_traffic_gb(self, email: str, gb: int) -> None:
        add_gb = max(0, int(gb))
        if add_gb <= 0:
            return
        try:
            self._request(
                "POST",
                "/panel/api/clients/bulkAdjust",
                json={"emails": [email], "addGB": add_gb},
            )
            return
        except PanelError:
            pass
        traffic = self.get_traffic(email)
        current = int(traffic.get("total") or 0)
        add_bytes = add_gb * 1024 * 1024 * 1024
        self._request(
            "POST",
            f"/panel/api/clients/updateTraffic/{quote(email, safe='')}",
            json={"total": current + add_bytes},
        )

    def restart_xray(self) -> None:
        self._request("POST", "/panel/api/server/restartXrayService")

    def get_xray_template(self) -> dict[str, Any]:
        data = self._request("POST", "/panel/api/xray/")
        obj = data.get("obj")
        if isinstance(obj, str):
            parsed = json.loads(obj)
        elif isinstance(obj, dict):
            parsed = obj
        else:
            raise PanelError("invalid xray template response")
        xs = parsed.get("xraySetting")
        if isinstance(xs, str):
            parsed["xraySetting"] = json.loads(xs)
        return parsed

    def update_xray_template(self, xray_setting: dict[str, Any], *, outbound_test_url: str | None = None) -> None:
        payload = {
            "xraySetting": json.dumps(xray_setting, ensure_ascii=False, indent=2),
            "outboundTestUrl": outbound_test_url or "https://www.google.com/generate_204",
        }
        # 3x-ui expects form fields, not JSON body
        self._request("POST", "/panel/api/xray/update", data=payload)

    def list_inbounds(self) -> list[dict[str, Any]]:
        data = self._request("GET", "/panel/api/inbounds/list")
        obj = data.get("obj") or []
        return [item for item in obj if isinstance(item, dict)]

    def ensure_telegram_proxy_inbound(self) -> int | None:
        """Create or reuse an MTProto inbound so Telegram can use a per-user proxy."""
        if self._telegram_inbound_id:
            return self._telegram_inbound_id
        found: dict[str, Any] | None = None
        for inbound in self.list_inbounds():
            if str(inbound.get("protocol") or "").lower() != "mtproto":
                continue
            if inbound.get("enable") is False:
                continue
            found = inbound
            if str(inbound.get("remark") or "") == TELEGRAM_PROXY_REMARK:
                break
        if found and found.get("id"):
            self._telegram_inbound_id = int(found["id"])
            return self._telegram_inbound_id
        last_error: Exception | None = None
        for port in TELEGRAM_PROXY_PORTS:
            payload = {
                "enable": True,
                "remark": TELEGRAM_PROXY_REMARK,
                "listen": "",
                "port": port,
                "protocol": "mtproto",
                "expiryTime": 0,
                "total": 0,
                "settings": {
                    "fakeTlsDomain": TELEGRAM_PROXY_FAKE_TLS_DOMAIN,
                    "clients": [],
                },
            }
            try:
                data = self._request("POST", "/panel/api/inbounds/add", json=payload)
            except PanelError as exc:
                last_error = exc
                msg = str(exc).lower()
                if "port" in msg or "already" in msg or "exist" in msg:
                    continue
                raise
            obj = data.get("obj") if isinstance(data.get("obj"), dict) else {}
            inbound_id = int(obj.get("id") or 0)
            if not inbound_id:
                raise PanelError("telegram proxy inbound was created without an id")
            self._telegram_inbound_id = inbound_id
            logger.info("created telegram mtproto inbound %s port %s on %s", inbound_id, port, self.base)
            return inbound_id
        if last_error:
            raise last_error
        raise PanelError("could not create telegram proxy inbound")

    def attach_emails_to_inbound(self, emails: list[str], inbound_id: int) -> dict[str, Any]:
        clean = [str(email).strip() for email in emails if str(email).strip()]
        if not clean or not inbound_id:
            return {"attached": 0, "skipped": 0, "failed": 0}
        try:
            data = self._request(
                "POST",
                "/panel/api/clients/bulkAttach",
                json={"emails": clean, "inboundIds": [inbound_id]},
            )
            obj = data.get("obj") if isinstance(data.get("obj"), dict) else {}
            errors = obj.get("errors") or []
            return {
                "attached": len(obj.get("attached") or []),
                "skipped": len(obj.get("skipped") or []),
                "failed": len(errors) if isinstance(errors, list) else 0,
            }
        except PanelError:
            attached = skipped = failed = 0
            for email in clean:
                try:
                    self._request(
                        "POST",
                        f"/panel/api/clients/{quote(email, safe='')}/attach",
                        json={"inboundIds": [inbound_id]},
                    )
                    attached += 1
                except PanelError as exc:
                    msg = str(exc).lower()
                    if "already" in msg or "exist" in msg:
                        skipped += 1
                    else:
                        failed += 1
                        logger.warning("telegram proxy attach failed %s: %s", email, exc)
            return {"attached": attached, "skipped": skipped, "failed": failed}


# inbound port → public (host, port, force_tls for WS-behind-nginx)
PUBLIC_ENDPOINTS: dict[int, tuple[str, int, dict[str, str]]] = {
    8443: ("ip", 8443, {}),
    26607: ("ip", 26607, {}),
    10086: ("host", 443, {"security": "tls", "sni": "host", "fp": "chrome"}),
    8080: ("host", 8080, {}),
    2083: ("host", 2083, {}),
    8081: ("host", 8081, {}),
}


PROTOCOL_REMARKS = {
    8443: "Reality",
    26607: "Reality-AMZ",
    10086: "WS",
    8080: "HTTP",
    2083: "WS-TLS",
    8081: "HTTP-MS",
}

DEFAULT_REMARKS = {
    8443: "BlackLines-Reality-8443",
    26607: "BlackLines-Reality-AMZ-26607",
    10086: "BlackLines-WS-443",
    8080: "BlackLines-HTTP-8080",
    2083: "BlackLines-WS-TLS-2083",
    8081: "BlackLines-HTTP-MS-8081",
}

TELEGRAM_PROXY_REMARK = "BlackLines-Telegram-Proxy"
TELEGRAM_PROXY_FAKE_TLS_DOMAIN = "www.cloudflare.com"
TELEGRAM_PROXY_PORTS = (8444, 2052, 10808, 9443)

# User-facing config toggles (admin can hide each type per server).
CONFIG_TYPE_DEFS: list[dict[str, Any]] = [
    {"key": "reality", "label": "Reality", "ports": {8443, 26607}},
    {"key": "ws", "label": "WS", "ports": {10086, 443}},
    {"key": "http", "label": "HTTP", "ports": {8080}},
    {"key": "ws_tls", "label": "WS-TLS", "ports": {2083}},
    {"key": "http_ms", "label": "HTTP-MS", "ports": {8081}},
    {"key": "telegram", "label": "تلگرام", "ports": set(), "telegram": True},
]
CONFIG_TYPE_KEYS = [str(item["key"]) for item in CONFIG_TYPE_DEFS]
DEFAULT_CONFIG_FLAGS = ",".join(CONFIG_TYPE_KEYS)


def parse_config_flags(raw: str | None) -> set[str]:
    text = (raw or "").strip()
    if not text:
        return set(CONFIG_TYPE_KEYS)
    found = {part.strip() for part in text.split(",") if part.strip() in CONFIG_TYPE_KEYS}
    return found or set(CONFIG_TYPE_KEYS)


def serialize_config_flags(flags: set[str] | list[str] | dict[str, bool] | None) -> str:
    if isinstance(flags, dict):
        enabled = {key for key in CONFIG_TYPE_KEYS if flags.get(key, True)}
    elif flags is None:
        enabled = set(CONFIG_TYPE_KEYS)
    else:
        enabled = {str(key) for key in flags if str(key) in CONFIG_TYPE_KEYS}
    if not enabled:
        enabled = set(CONFIG_TYPE_KEYS)
    return ",".join(key for key in CONFIG_TYPE_KEYS if key in enabled)


def config_flags_dict(raw: str | None) -> dict[str, bool]:
    enabled = parse_config_flags(raw)
    return {key: key in enabled for key in CONFIG_TYPE_KEYS}


def sanitize_config_name(name: str | None) -> str:
    cleaned = " ".join(str(name or "").replace("#", " ").replace("\n", " ").split())
    return cleaned[:48]


def config_remark(port: int, name: str | None, original: str = "", region: str | None = None) -> str:
    """VPN client display name: user label, protocol, and server region."""
    cleaned = sanitize_config_name(name)
    place = sanitize_config_name(region)
    tag = PROTOCOL_REMARKS.get(port, "")
    parts = [p for p in (cleaned, tag, place) if p]
    if cleaned or place:
        return " · ".join(parts)
    if port in DEFAULT_REMARKS:
        base = DEFAULT_REMARKS[port]
        return f"{base} · {place}" if place else base
    if original:
        remark = unquote(original)
        return f"{remark} · {place}" if place else remark
    return place or "BlackLines"


def is_telegram_proxy_link(link: str) -> bool:
    text = (link or "").strip()
    if text.startswith("tg://proxy?") or text.startswith("tg://socks?"):
        return True
    if text.startswith("https://t.me/proxy?") or text.startswith("https://t.me/socks?"):
        return True
    if text.startswith("http://t.me/proxy?") or text.startswith("http://t.me/socks?"):
        return True
    return False


def link_config_key(link: str) -> str | None:
    if is_telegram_proxy_link(link):
        return "telegram"
    if not link.startswith("vless://"):
        return None
    try:
        main = link.split("#", 1)[0]
        scheme_rest = main[len("vless://") :]
        _, _, hostport_query = scheme_rest.partition("@")
        hostport, _, _query = hostport_query.partition("?")
        _, _, port_s = hostport.rpartition(":")
        port = int(port_s)
    except Exception:
        return None
    for item in CONFIG_TYPE_DEFS:
        ports = item.get("ports") or set()
        if port in ports:
            return str(item["key"])
    return None


def link_allowed_by_flags(link: str, allowed: set[str] | None) -> bool:
    if allowed is None:
        return True
    key = link_config_key(link)
    if key is None:
        return True
    return key in allowed


def telegram_https_link(link: str) -> str | None:
    """Telegram in-app URL that opens Settings → Proxy."""
    text = (link or "").strip()
    if text.startswith("tg://proxy?"):
        return "https://t.me/proxy?" + text[len("tg://proxy?") :]
    if text.startswith("tg://socks?"):
        return "https://t.me/socks?" + text[len("tg://socks?") :]
    if text.startswith("https://t.me/proxy?") or text.startswith("https://t.me/socks?"):
        return text
    if text.startswith("http://t.me/proxy?"):
        return "https://" + text[len("http://") :]
    if text.startswith("http://t.me/socks?"):
        return "https://" + text[len("http://") :]
    return None


def _telegram_endpoint(link: str) -> tuple[str | None, int | None]:
    try:
        _, _, query = link.partition("?")
        params = parse_qs(query, keep_blank_values=True)
        host = (params.get("server") or [""])[-1] or None
        port_s = (params.get("port") or [""])[-1]
        port = int(port_s) if port_s else None
        return host, port
    except (TypeError, ValueError):
        return None, None


def rewrite_telegram_proxy_link(
    link: str,
    *,
    public_host: str | None,
    public_ip: str | None,
) -> str:
    dest = (public_ip or public_host or "").strip()
    if not dest:
        return link
    try:
        scheme, _, rest = link.partition("://")
        path, _, query = rest.partition("?")
        params = parse_qs(query, keep_blank_values=True)
        server = (params.get("server") or [""])[-1]
        if server in {"", "localhost", "127.0.0.1", "0.0.0.0", "::1"}:
            params["server"] = [dest]
        flat = {key: values[-1] for key, values in params.items()}
        rebuilt = f"{scheme}://{path}?{urlencode(flat, doseq=False, quote_via=quote)}"
        https = telegram_https_link(rebuilt)
        return https or rebuilt
    except Exception:
        return link


def rewrite_share_link(
    link: str,
    settings: Settings,
    *,
    name: str | None = None,
    public_host: str | None = None,
    public_ip: str | None = None,
    region: str | None = None,
) -> str:
    """Replace localhost + internal ports with public host/IP and nginx 443 for WS."""
    if is_telegram_proxy_link(link):
        return rewrite_telegram_proxy_link(
            link,
            public_host=public_host or settings.public_host,
            public_ip=public_ip or settings.public_ip,
        )
    if not link.startswith("vless://"):
        return link

    pub_host = public_host or settings.public_host
    pub_ip = public_ip or settings.public_ip

    # vless://uuid@host:port?query#remark
    try:
        main, remark = link.split("#", 1)
    except ValueError:
        main, remark = link, ""
    scheme_rest = main[len("vless://") :]
    userinfo, _, hostport_query = scheme_rest.partition("@")
    hostport, _, query = hostport_query.partition("?")
    host, _, port_s = hostport.rpartition(":")
    try:
        port = int(port_s)
    except ValueError:
        return link

    new_remark = config_remark(port, name, remark, region=region)
    endpoint = PUBLIC_ENDPOINTS.get(port)
    if not endpoint:
        if host in {"localhost", "127.0.0.1"}:
            host = pub_host
        rebuilt = f"vless://{userinfo}@{host}:{port}"
        if query:
            rebuilt += f"?{query}"
        rebuilt += f"#{quote(new_remark, safe='')}"
        return rebuilt

    kind, public_port, overrides = endpoint
    dest_host = pub_ip if kind == "ip" else pub_host
    params = parse_qs(query, keep_blank_values=True)
    flat: dict[str, str] = {k: v[-1] for k, v in params.items()}
    for key, value in overrides.items():
        flat[key] = pub_host if value == "host" else value
    if kind == "host":
        if flat.get("security") == "tls" and "sni" not in flat:
            flat["sni"] = pub_host
        if flat.get("type") == "ws" and "host" not in flat:
            flat["host"] = pub_host
    if flat.get("security") == "reality":
        flat.setdefault("encryption", "none")
        # Keep panel sid as-is (including empty). Do not force a shared shortId —
        # each Reality inbound has its own shortIds.
        flat.setdefault("spx", "/")
    if "encryption" not in flat:
        flat["encryption"] = "none"

    new_query = urlencode(flat, doseq=False, quote_via=quote)
    return f"vless://{userinfo}@{dest_host}:{public_port}?{new_query}#{quote(new_remark, safe='')}"


def public_links_for_email(
    panel: XUIPanel,
    email: str,
    settings: Settings,
    *,
    name: str | None = None,
) -> list[str]:
    if isinstance(panel, PanelHub):
        return panel.gather_public_links(email, settings, name=name)
    raw = panel.get_links(email)
    out: list[str] = []
    seen: set[str] = set()
    allowed = getattr(panel, "allowed_configs", None)
    for link in raw:
        rewritten = rewrite_share_link(
            link,
            settings,
            name=name,
            public_host=getattr(panel, "public_host", None),
            public_ip=getattr(panel, "public_ip", None),
            region=getattr(panel, "region", None) or None,
        )
        if not link_allowed_by_flags(rewritten, allowed):
            continue
        if rewritten in seen:
            continue
        seen.add(rewritten)
        out.append(rewritten)
        https = telegram_https_link(rewritten)
        if https and https not in seen and link_allowed_by_flags(https, allowed):
            seen.add(https)
            out.append(https)
    return out


class PanelHub:
    """Primary 3x-ui plus extra country servers. Duck-types XUIPanel."""

    def __init__(self, primary: XUIPanel, extras: list[XUIPanel] | None = None):
        self.primary = primary
        self.extras = list(extras or [])
        self.members = [primary, *self.extras]
        self.settings = primary.settings
        self.base = primary.base
        self.public_host = primary.public_host
        self.public_ip = primary.public_ip
        self.region = primary.region
        self.inbound_ids = primary.inbound_ids

    @property
    def link_members(self) -> list[XUIPanel]:
        return [panel for panel in self.members if getattr(panel, "links_enabled", True)]

    @property
    def provision_extras(self) -> list[XUIPanel]:
        return [panel for panel in self.extras if getattr(panel, "links_enabled", True)]

    def close(self) -> None:
        for panel in self.members:
            try:
                panel.close()
            except Exception:
                pass

    def create_client(self, **kwargs: Any) -> dict[str, Any]:
        client = self.primary.create_client(**kwargs)
        uuid = str(client.get("uuid") or client.get("id") or "") or None
        sub_id = str(client.get("subId") or client.get("sub_id") or "") or None
        extra_kwargs = dict(kwargs)
        if uuid:
            extra_kwargs["client_id"] = uuid
        if sub_id:
            extra_kwargs["sub_id"] = sub_id
        for panel in self.provision_extras:
            try:
                panel.create_client(**extra_kwargs)
            except Exception:
                logger.exception("extra panel create failed %s", panel.base)
        return client

    def get_client(self, email: str) -> dict[str, Any]:
        return self.primary.get_client(email)

    def get_links(self, email: str) -> list[str]:
        return self.primary.get_links(email)

    def gather_public_links(self, email: str, settings: Settings, name: str | None = None) -> list[str]:
        links: list[str] = []
        for panel in self.link_members:
            try:
                links.extend(public_links_for_email(panel, email, settings, name=name))
            except Exception:
                logger.exception("gather links failed %s", panel.base)
        return links

    def get_traffic(self, email: str) -> dict[str, Any]:
        """Sum usage across every node — traffic is per-server, not copied."""
        up = 0
        down = 0
        last = 0
        total = 0
        enable: bool | None = None
        base: dict[str, Any] = {}
        for panel in self.members:
            try:
                row = panel.get_traffic(email)
            except Exception:
                logger.exception("traffic failed %s", panel.base)
                continue
            if not isinstance(row, dict):
                continue
            base = row
            up += int(row.get("up") or 0)
            down += int(row.get("down") or 0)
            try:
                last = max(last, int(row.get("lastOnline") or 0))
            except (TypeError, ValueError):
                pass
            try:
                total = max(total, int(row.get("total") or 0))
            except (TypeError, ValueError):
                pass
            if row.get("enable") is not None:
                flag = bool(row.get("enable"))
                enable = flag if enable is None else (enable or flag)
        if not base:
            return self.primary.get_traffic(email)
        out = dict(base)
        out["up"] = up
        out["down"] = down
        out["lastOnline"] = last
        out["total"] = total
        if enable is not None:
            out["enable"] = enable
        return out

    def get_xray_access_events(self, *, count: int = 400, email: str | None = None) -> list[dict[str, Any]]:
        events: list[dict[str, Any]] = []
        for panel in self.members:
            try:
                events.extend(panel.get_xray_access_events(count=count, email=email))
            except Exception:
                logger.exception("xray logs failed %s", panel.base)
        return events

    def online_emails(self) -> set[str]:
        found: set[str] = set()
        for panel in self.members:
            try:
                found |= panel.online_emails()
            except Exception:
                logger.exception("online emails failed %s", panel.base)
        return found

    def get_client_ips(self, email: str) -> list[dict[str, Any]]:
        """Merge connected IPs from every panel (primary + extras)."""
        merged: list[dict[str, Any]] = []
        seen: set[str] = set()
        for panel in self.members:
            try:
                items = panel.get_client_ips(email)
            except Exception:
                logger.exception("client ips failed %s", panel.base)
                continue
            region = (getattr(panel, "region", None) or "").strip()
            own_ip = (getattr(panel, "public_ip", None) or "").strip()
            for item in items:
                ip = str(item.get("ip") or "").strip()
                if not ip or ip in seen:
                    continue
                # Panel sometimes reports its own public IP; skip that noise.
                if own_ip and ip == own_ip:
                    continue
                seen.add(ip)
                row = dict(item)
                if not str(row.get("node") or "").strip() and region:
                    row["node"] = region
                merged.append(row)
        return merged

    def last_online_map(self) -> dict[str, int]:
        merged: dict[str, int] = {}
        for panel in self.members:
            try:
                for key, value in panel.last_online_map().items():
                    merged[key] = max(merged.get(key, 0), value)
            except Exception:
                logger.exception("last online failed %s", panel.base)
        return merged

    def _fanout(self, method: str, *args: Any, **kwargs: Any) -> None:
        getattr(self.primary, method)(*args, **kwargs)
        for panel in self.extras:
            try:
                getattr(panel, method)(*args, **kwargs)
            except Exception:
                logger.exception("extra panel %s failed %s", method, panel.base)

    def set_enabled(self, email: str, enabled: bool) -> None:
        self._fanout("set_enabled", email, enabled)

    def delete_client(self, email: str) -> None:
        self._fanout("delete_client", email)

    def update_client(self, email: str, updates: dict[str, Any]) -> dict[str, Any]:
        client = self.primary.update_client(email, updates)
        for panel in self.extras:
            try:
                panel.update_client(email, updates)
            except Exception:
                logger.exception("extra panel update failed %s", panel.base)
        return client

    def clear_client_ips(self, email: str) -> None:
        self._fanout("clear_client_ips", email)

    def rotate_client_identity(self, email: str) -> dict[str, Any]:
        client = self.primary.rotate_client_identity(email)
        ident = str(client.get("uuid") or client.get("id") or "") or None
        sub_id = str(client.get("subId") or client.get("sub_id") or "") or None
        updates: dict[str, Any] = {}
        if ident:
            updates["id"] = ident
        if sub_id:
            updates["subId"] = sub_id
        for panel in self.extras:
            try:
                if updates:
                    panel.update_client(email, updates)
                panel.clear_client_ips(email)
            except Exception:
                logger.exception("extra panel rotate failed %s", panel.base)
        return client

    def extend_days(self, email: str, days: int) -> None:
        self._fanout("extend_days", email, days)

    def add_traffic_gb(self, email: str, gb: int) -> None:
        self._fanout("add_traffic_gb", email, gb)

    def restart_xray(self) -> None:
        self._fanout("restart_xray")

    def prepare_telegram_proxy(self) -> None:
        for panel in self.members:
            try:
                panel.ensure_telegram_proxy_inbound()
            except Exception:
                logger.exception("telegram proxy ensure failed %s", panel.base)


def parse_share_link(link: str) -> tuple[str | None, int | None, str | None, str]:
    if is_telegram_proxy_link(link):
        host, port = _telegram_endpoint(link)
        return host, port, "پروکسی تلگرام", "telegram"
    host, port, remark = parse_vless_link(link)
    return host, port, remark, "vless"


def parse_vless_link(link: str) -> tuple[str | None, int | None, str | None]:
    if not link.startswith("vless://"):
        return None, None, None
    try:
        main, remark = link.split("#", 1)
        remark = unquote(remark)
    except ValueError:
        main, remark = link, None
    scheme_rest = main[len("vless://") :]
    _, _, hostport_query = scheme_rest.partition("@")
    hostport, _, _query = hostport_query.partition("?")
    host, _, port_s = hostport.rpartition(":")
    try:
        return host or None, int(port_s), remark or None
    except ValueError:
        return host or None, None, remark or None


def ping_tcp(host: str, port: int, *, timeout: float = 2.0) -> int | None:
    try:
        start = time.perf_counter()
        with socket.create_connection((host, port), timeout=timeout):
            return int((time.perf_counter() - start) * 1000)
    except OSError:
        return None


def vpn_links_only(links: list[str]) -> list[str]:
    return [link for link in links if not is_telegram_proxy_link(link)]


def subscription_import_base64(links: list[str]) -> str:
    body = "\n".join(vpn_links_only(links)).strip()
    return base64.b64encode(body.encode()).decode()


def build_subscription_url(sub_id: str | None, settings: Settings) -> str | None:
    if not sub_id:
        return None
    base = (settings.subscription_base_url or "").strip()
    if not base:
        host = (settings.public_host or "").strip().rstrip("/")
        if not host:
            return None
        if host.startswith("http://") or host.startswith("https://"):
            base = f"{host}/shop/sub"
        else:
            base = f"https://{host}/shop/sub"
    return f"{base.rstrip('/')}/{sub_id}"
