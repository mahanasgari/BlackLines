from __future__ import annotations

import hashlib
import hmac
import json
import time
from urllib.parse import parse_qsl


class TelegramAuthError(Exception):
    pass


def validate_webapp_init_data(init_data: str, bot_token: str, max_age_sec: int = 86400) -> dict:
    """Validate Telegram Mini App initData and return parsed fields + user dict."""
    if not init_data or not bot_token:
        raise TelegramAuthError("missing init data")

    parsed = dict(parse_qsl(init_data, keep_blank_values=True))
    received_hash = parsed.pop("hash", None)
    if not received_hash:
        raise TelegramAuthError("missing hash")

    data_check = "\n".join(f"{k}={v}" for k, v in sorted(parsed.items()))
    secret_key = hmac.new(b"WebAppData", bot_token.encode(), hashlib.sha256).digest()
    calculated = hmac.new(secret_key, data_check.encode(), hashlib.sha256).hexdigest()
    if not hmac.compare_digest(calculated, received_hash):
        raise TelegramAuthError("invalid hash")

    auth_date = int(parsed.get("auth_date") or 0)
    if auth_date and time.time() - auth_date > max_age_sec:
        raise TelegramAuthError("init data expired")

    user_raw = parsed.get("user")
    if not user_raw:
        raise TelegramAuthError("missing user")
    try:
        user = json.loads(user_raw)
    except json.JSONDecodeError as exc:
        raise TelegramAuthError("invalid user json") from exc

    start_param = parsed.get("start_param") or ""
    return {"user": user, "start_param": start_param, "auth_date": auth_date}


def validate_webapp_init_data_any(
    init_data: str,
    bot_tokens: list[str],
    max_age_sec: int = 86400,
) -> dict:
    """Validate initData against any configured bot token (MainBot + secondary)."""
    last: TelegramAuthError | None = None
    for token in bot_tokens:
        try:
            return validate_webapp_init_data(init_data, token, max_age_sec=max_age_sec)
        except TelegramAuthError as exc:
            last = exc
            continue
    raise last or TelegramAuthError("invalid hash")
