"""Read-only health check for the Reality inbounds on every 3x-ui panel.

Clients report "reality verification failed" when the server does not accept
their handshake and relays them to the camouflage site instead. This compares
what the panel hands out in share links with what each inbound expects.

Run on the server (nothing is changed on the panels):
    docker exec -i vpn_shop_bot python - < scripts/check_reality.py
"""
from __future__ import annotations

import base64
import email.utils
import json
import socket
import ssl
import time
from urllib.parse import parse_qs, unquote

import httpx

from app.config import get_settings
from app.models import make_session_factory
from app.servers import get_panel_hub

P = 2**255 - 19
OK, BAD, WARN = "  OK  ", "  FAIL", "  WARN"


def b64d(s: str) -> bytes:
    s = s.strip()
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


def x25519_public(private_b64: str) -> str:
    """RFC 7748 X25519 base-point multiplication, keys in Xray's raw-url base64."""
    k = bytearray(b64d(private_b64))
    k[0] &= 248
    k[31] &= 127
    k[31] |= 64
    n = int.from_bytes(k, "little")
    x1, x2, z2, x3, z3, swap = 9, 1, 0, 9, 1, 0
    for t in reversed(range(255)):
        kt = (n >> t) & 1
        swap ^= kt
        if swap:
            x2, x3, z2, z3 = x3, x2, z3, z2
        swap = kt
        a = (x2 + z2) % P
        aa = a * a % P
        b = (x2 - z2) % P
        bb = b * b % P
        e = (aa - bb) % P
        c = (x3 + z3) % P
        d = (x3 - z3) % P
        da = d * a % P
        cb = c * b % P
        x3 = (da + cb) ** 2 % P
        z3 = x1 * (da - cb) ** 2 % P
        x2 = aa * bb % P
        z2 = e * (aa + 121665 * e) % P
    if swap:
        x2, z2 = x3, z3
    out = (x2 * pow(z2, P - 2, P) % P).to_bytes(32, "little")
    return base64.urlsafe_b64encode(out).rstrip(b"=").decode()


def link_params(link: str) -> dict[str, str]:
    query = link.split("#", 1)[0].partition("?")[2]
    return {k: unquote(v[-1]) for k, v in parse_qs(query, keep_blank_values=True).items()}


def link_port(link: str) -> int | None:
    hostport = link.split("#", 1)[0].partition("@")[2].partition("?")[0]
    try:
        return int(hostport.rpartition(":")[2])
    except ValueError:
        return None


def tls_probe(host: str, port: int, sni: str, timeout: float = 6.0) -> str:
    """TLS 1.3 handshake; returns the certificate subject or the error."""
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    ctx.minimum_version = ssl.TLSVersion.TLSv1_3
    try:
        with socket.create_connection((host, port), timeout=timeout) as raw:
            raw.settimeout(timeout)
            with ctx.wrap_socket(raw, server_hostname=sni) as tls:
                der = tls.getpeercert(binary_form=True) or b""
                cn = ""
                try:
                    import subprocess

                    pem = ssl.DER_cert_to_PEM_cert(der)
                    cn = subprocess.run(
                        ["openssl", "x509", "-noout", "-subject"], input=pem, capture_output=True, text=True, timeout=5
                    ).stdout.strip()
                except Exception:  # noqa: BLE001
                    pass
                return f"ok {tls.version()} {cn or f'({len(der)} byte cert)'}"
    except Exception as exc:  # noqa: BLE001
        return f"error: {exc.__class__.__name__}: {exc}"


def clock_skew() -> str:
    try:
        r = httpx.head("https://www.google.com", timeout=8)
        remote = email.utils.parsedate_to_datetime(r.headers["date"]).timestamp()
        return f"{time.time() - remote:+.1f}s vs google.com"
    except Exception as exc:  # noqa: BLE001
        return f"unknown ({exc})"


def check_panel(panel) -> None:
    name = getattr(panel, "region", "") or panel.base
    print(f"\n=== Panel {name}  ({panel.base})  public ip {getattr(panel, 'public_ip', '?')}")
    try:
        inbounds = panel.list_inbounds()
    except Exception as exc:  # noqa: BLE001
        print(f"{BAD} cannot list inbounds: {exc}")
        return
    for ib in inbounds:
        stream = json.loads(ib.get("streamSettings") or "{}")
        if stream.get("security") != "reality":
            continue
        port = ib.get("port")
        rs = stream.get("realitySettings") or {}
        extra = rs.get("settings") or {}
        print(f"\n--- inbound #{ib.get('id')} '{ib.get('remark')}' port {port} enabled={ib.get('enable')}")

        priv = rs.get("privateKey") or ""
        pub_cfg = extra.get("publicKey") or ""
        derived = ""
        try:
            derived = x25519_public(priv) if priv else ""
        except Exception as exc:  # noqa: BLE001
            print(f"{BAD} privateKey is not a valid X25519 key: {exc}")
        if derived and pub_cfg:
            print(f"{OK if derived == pub_cfg else BAD} panel publicKey matches privateKey"
                  + ("" if derived == pub_cfg else f"  (panel has {pub_cfg[:12]}…, private key gives {derived[:12]}…)"))

        names = rs.get("serverNames") or []
        sids = rs.get("shortIds") or []
        dest = rs.get("dest") or rs.get("target") or ""
        print(f"        serverNames={names} shortIds={sids} dest={dest}")
        for key in ("minClientVer", "maxClientVer", "maxTimeDiff", "xver"):
            if rs.get(key):
                print(f"{WARN} {key}={rs[key]!r} (sing-box clients can fail version/time limits)")
        if rs.get("mldsa65Seed"):
            print(f"{WARN} mldsa65Seed is set (post-quantum verify; needs clients that support it)")

        clients = (json.loads(ib.get("settings") or "{}").get("clients")) or []
        flows = sorted({c.get("flow") or "" for c in clients})
        print(f"        {len(clients)} clients, flows={flows}")
        sample = next((c.get("email") for c in clients if c.get("enable", True) and c.get("email")), None)
        if sample:
            try:
                links = [l for l in panel.get_links(sample) if link_port(l) == port]
            except Exception as exc:  # noqa: BLE001
                links = []
                print(f"{BAD} cannot fetch links for {sample}: {exc}")
            for link in links[:1]:
                p = link_params(link)
                print(f"        link for {sample}: pbk={p.get('pbk', '')[:12]}… sid={p.get('sid')!r} "
                      f"sni={p.get('sni')!r} fp={p.get('fp')!r} flow={p.get('flow')!r}")
                if derived:
                    print(f"{OK if p.get('pbk') == derived else BAD} link pbk matches the inbound key")
                print(f"{OK if (p.get('sid') or '') in sids else BAD} link sid is in shortIds")
                print(f"{OK if p.get('sni') in names else BAD} link sni is in serverNames")
                client_flow = next((c.get("flow") or "" for c in clients if c.get("email") == sample), "")
                if (p.get("flow") or "") != client_flow:
                    print(f"{BAD} link flow {p.get('flow')!r} != client flow {client_flow!r}")
            if not links:
                print(f"{WARN} panel returned no link on port {port} for {sample}")

        if dest:
            host, _, dport = dest.rpartition(":")
            host = host or dest
            sni = names[0] if names else host
            res = tls_probe(host, int(dport or 443), sni)
            print(f"{OK if res.startswith('ok') else BAD} server -> dest {host}:{dport} (sni {sni}): {res}")
        pub_ip = getattr(panel, "public_ip", "") or ""
        if pub_ip and names:
            res = tls_probe(pub_ip, int(port), names[0])
            print(f"{OK if res.startswith('ok') else BAD} unauthenticated probe {pub_ip}:{port} relays to dest: {res}")


def main() -> None:
    settings = get_settings()
    sessions = make_session_factory(settings.database_url)
    with sessions() as session:
        hub = get_panel_hub(settings, session)
    print(f"server clock: {clock_skew()}  (Reality rejects clients when skew exceeds maxTimeDiff)")
    for panel in hub.members:
        check_panel(panel)


if __name__ == "__main__":
    main()
