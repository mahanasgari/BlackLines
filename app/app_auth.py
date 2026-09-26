"""Opaque Bearer sessions for the native BlackLines app (Telegram bot deep-link login)."""

from __future__ import annotations

import hashlib
import secrets
from datetime import datetime, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import AppLoginChallenge, AppSession, User

LOGIN_CHALLENGE_TTL = timedelta(minutes=5)
SESSION_TTL = timedelta(days=30)
NONCE_BYTES = 16
TOKEN_BYTES = 32


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def new_nonce() -> str:
    return secrets.token_urlsafe(NONCE_BYTES)


def new_access_token() -> str:
    return secrets.token_urlsafe(TOKEN_BYTES)


def resolve_bot_username(session: Session, *, primary_bot_token: str) -> str:
    from app.services import get_setting, set_setting

    bot_username = get_setting(session, "bot_username", "")
    if bot_username:
        return bot_username
    try:
        import httpx

        r = httpx.get(f"https://api.telegram.org/bot{primary_bot_token}/getMe", timeout=15)
        bot_username = (r.json().get("result") or {}).get("username") or "bot"
        set_setting(session, "bot_username", bot_username)
    except Exception:  # noqa: BLE001
        bot_username = "bot"
    return bot_username


def create_login_challenge(session: Session) -> AppLoginChallenge:
    now = datetime.utcnow()
    challenge = AppLoginChallenge(
        nonce=new_nonce(),
        expires_at=now + LOGIN_CHALLENGE_TTL,
        created_at=now,
    )
    session.add(challenge)
    session.commit()
    session.refresh(challenge)
    return challenge


def get_challenge_by_nonce(session: Session, nonce: str) -> AppLoginChallenge | None:
    return session.scalar(select(AppLoginChallenge).where(AppLoginChallenge.nonce == nonce))


def issue_session(
    session: Session,
    user: User,
    *,
    user_agent: str | None = None,
) -> tuple[AppSession, str]:
    """Create an AppSession and return (row, plaintext_token)."""
    token = new_access_token()
    now = datetime.utcnow()
    row = AppSession(
        token_hash=hash_token(token),
        user_id=user.id,
        expires_at=now + SESSION_TTL,
        created_at=now,
        user_agent=(user_agent or "")[:255] or None,
    )
    session.add(row)
    session.commit()
    session.refresh(row)
    return row, token


def confirm_login_challenge(
    session: Session,
    challenge: AppLoginChallenge,
    user: User,
    *,
    user_agent: str | None = None,
) -> str:
    """Attach a new session to a pending challenge. Returns plaintext access token."""
    now = datetime.utcnow()
    if challenge.consumed_at is not None:
        raise ValueError("already_consumed")
    if challenge.expires_at < now:
        raise ValueError("expired")
    if challenge.access_token_plain:
        # Already confirmed; return existing token until poll consumes it
        return challenge.access_token_plain

    _sess, token = issue_session(session, user, user_agent=user_agent)
    challenge.user_id = user.id
    challenge.session_id = _sess.id
    challenge.access_token_plain = token
    session.commit()
    session.refresh(challenge)
    return token


def poll_login_challenge(session: Session, nonce: str) -> dict:
    challenge = get_challenge_by_nonce(session, nonce)
    if challenge is None:
        return {"status": "expired"}
    now = datetime.utcnow()
    if challenge.consumed_at is not None:
        return {"status": "expired"}
    if challenge.expires_at < now and not challenge.access_token_plain:
        return {"status": "expired"}
    if not challenge.access_token_plain:
        return {"status": "pending"}

    token = challenge.access_token_plain
    expires_at = None
    if challenge.session_id:
        app_sess = session.get(AppSession, challenge.session_id)
        if app_sess:
            expires_at = app_sess.expires_at.isoformat() + "Z"

    challenge.consumed_at = now
    challenge.access_token_plain = None
    session.commit()
    return {
        "status": "ready",
        "access_token": token,
        "expires_at": expires_at,
    }


def resolve_bearer(session: Session, authorization: str | None) -> tuple[User, AppSession] | None:
    if not authorization:
        return None
    parts = authorization.strip().split(None, 1)
    if len(parts) != 2 or parts[0].lower() != "bearer":
        return None
    token = parts[1].strip()
    if not token:
        return None
    row = session.scalar(
        select(AppSession).where(AppSession.token_hash == hash_token(token))
    )
    if row is None:
        return None
    now = datetime.utcnow()
    if row.revoked_at is not None or row.expires_at < now:
        return None
    user = session.get(User, row.user_id)
    if user is None:
        return None
    return user, row


def revoke_session(session: Session, app_session: AppSession) -> None:
    app_session.revoked_at = datetime.utcnow()
    session.commit()
