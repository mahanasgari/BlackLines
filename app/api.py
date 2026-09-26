from __future__ import annotations

import json
import logging
import secrets
import threading
from contextlib import asynccontextmanager
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Annotated

import httpx
from fastapi import BackgroundTasks, Body, Depends, FastAPI, File, Header, HTTPException, Query, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, Response
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field, model_validator
from sqlalchemy import func, select
from sqlalchemy.orm import Session, sessionmaker

from app.app_auth import (
    create_login_challenge,
    poll_login_challenge,
    resolve_bearer,
    resolve_bot_username,
    revoke_session,
)
from app.channel_gate import (
    channel_gate_enabled,
    channel_required_payload,
    clear_channel_cache,
    is_channel_member,
)
from app.config import Settings, get_settings
from app.receipts import resolve_receipt, save_receipt_local
from app.models import OrderStatus, Subscription, User, Withdrawal, WithdrawStatus, make_session_factory
from app.panel import (
    PanelError,
    XUIPanel,
    build_subscription_url,
    parse_share_link,
    ping_tcp,
    public_links_for_email,
    subscription_import_base64,
)
from app.jobs import list_user_withdrawals, referral_leaderboard
from app.services import (
    PendingOrderError,
    add_payment_card,
    admin_chat_unread_total,
    approve_renew_subscription,
    approve_wallet_deposit,
    approve_pro_subscription,
    approve_withdrawal,
    admin_gift_subscription,
    admin_giftable_plans,
    delete_user_subscription,
    grant_pro_to_user,
    attach_subscription,
    birthday_gift_settings_dict,
    cancel_order,
    chat_message_dict,
    chat_preview_text,
    client_connection_ips,
    activate_metered_payg,
    set_metered_payg_enabled,
    apply_metered_payg_stats,
    approve_payg_topup,
    bill_all_metered_payg,
    bill_payg_subscription,
    create_custom_order,
    create_payg_order,
    create_renew_order,
    create_order,
    create_wallet_deposit,
    create_withdrawal,
    list_user_wallet_transfers,
    transfer_wallet_balance,
    credit_referral_commission,
    custom_builder_admin_settings,
    custom_builder_settings,
    is_metered_payg,
    is_payg_order,
    is_payg_subscription,
    payg_builder_admin_settings,
    payg_builder_enabled,
    payg_prepaid_settings,
    payg_status_dict,
    quote_payg_package,
    record_usage_sample,
    public_links_for_subscription,
    relative_time_fa,
    subscription_usage_analytics,
    user_prepaid_payg_subscriptions,
    update_custom_builder_settings,
    update_payg_builder_settings,
    format_price,
    format_bytes,
    get_or_create_user,
    get_order,
    grant_trial_to_users,
    get_platform_pro_plan,
    get_user_subscription,
    get_plan,
    get_setting,
    is_custom_order,
    is_wallet_topup,
    is_platform_pro,
    is_user_pro,
    is_pro_only_shop_plan,
    list_enabled_plans,
    fulfill_pending_order,
    maybe_auto_fulfill_prepaid_order,
    is_prepaid_shop_order,
    latest_chat_message_id,
    list_chat_threads,
    list_payment_cards,
    list_pending_orders,
    list_pending_withdrawals,
    list_user_chat_messages,
    list_user_orders_for_chat,
    list_orders_history,
    mark_chat_read,
    min_withdraw_amount,
    MAX_WALLET_DEPOSIT,
    MIN_WALLET_TRANSFER,
    maybe_grant_birthday_gift,
    wallet_view,
    wallet_withdrawable,
    wallet_spendable,
    set_user_wallet_credit_limit,
    trial_offer_dict,
    claim_user_trial,
    MIN_WALLET_DEPOSIT,
    is_user_admin,
    is_telegram_admin,
    search_users_admin,
    admin_user_detail,
    adjust_user_wallet,
    convert_wallet_topup_to_credit,
    set_subscription_enabled,
    set_user_role,
    set_user_test_flag,
    USER_ROLE_ADMIN,
    USER_ROLE_USER,
    order_chat_dict,
    order_plan_title,
    order_provision_params,
    plan_charge_price,
    pro_discount_percent,
    pro_status_dict,
    payment_info,
    quote_custom_package,
    referral_stats,
    list_referral_invitees,
    reject_order,
    revoke_subscription,
    rotate_subscription_link,
    diagnose_subscription,
    hide_subscription_from_dashboard,
    unhide_subscription_from_dashboard,
    subscription_is_expired,
    reject_withdrawal,
    resolve_trial_target_users,
    resolve_chat_attachments,
    remove_payment_card,
    seed_defaults,
    send_chat_message,
    set_setting,
    subscription_config_dict,
    subscription_buy_meta,
    subscription_live_stats,
    set_subscription_label,
    set_subscription_customer,
    set_subscription_link_shared,
    list_reseller_desk,
    customer_meta_dict,
    set_user_birth_date,
    set_user_contact,
    sync_user_telegram_profile,
    traffic_label,
    trial_settings_dict,
    user_active_subscriptions,
    user_all_subscriptions,
    user_chat_unread_count,
    user_pending_order,
    user_profile_dict,
)
from app.analytics import admin_analytics, list_admin_slice, list_expiring_soon
from app.servers import (
    add_vpn_server,
    delete_vpn_server,
    get_panel_hub,
    list_vpn_servers_admin,
    panel_for_server,
    set_vpn_server_enabled,
    set_vpn_server_visibility,
    sync_telegram_proxy_for_panel,
    sync_subscriptions_to_server,
    vpn_server_dict,
)
from app.texts import subscription_link_message
from app.telegram_auth import TelegramAuthError, validate_webapp_init_data_any
from app.tg_http import (
    send_telegram_document,
    send_telegram_message,
    telegram_download_file,
    telegram_user_photo_file_id,
)

logger = logging.getLogger("vpnshop.api")
STATIC_DIR = Path(__file__).resolve().parent.parent / "miniapp" / "dist"
_PROFILE_PHOTO_CACHE: dict[int, tuple[str, bytes, str]] = {}


class CustomerMetaBody(BaseModel):
    customer_name: str | None = Field(default=None, max_length=64)
    customer_email: str | None = Field(default=None, max_length=128)
    customer_phone: str | None = Field(default=None, max_length=32)
    customer_telegram_id: str | None = Field(default=None, max_length=64)


class LinkSharedBody(BaseModel):
    shared: bool = True


class CreateOrderBody(CustomerMetaBody):
    plan_id: int
    promo_code: str | None = Field(default=None, max_length=32)
    family_size: int = Field(default=1, ge=1, le=10)
    config_label: str | None = Field(default=None, max_length=64)
    gift_card: bool = False


class PromoValidateBody(BaseModel):
    code: str = Field(default="", max_length=32)
    plan_id: int | None = None
    family_size: int = Field(default=1, ge=1, le=10)
    duration_days: int | None = None
    traffic_gb: int | None = None
    limit_ip: int | None = None
    unlimited: bool = False


class PromoCodeAdminBody(BaseModel):
    code: str = Field(min_length=3, max_length=32)
    kind: str = Field(pattern="^(percent|free_days)$")
    value: int = Field(ge=1, le=365)
    max_uses: int = Field(default=0, ge=0, le=100000)
    per_user_limit: int = Field(default=1, ge=1, le=20)
    enabled: bool = True
    note: str = Field(default="", max_length=120)


class FamilySettingsBody(BaseModel):
    enabled: bool = True
    max_size: int = Field(default=5, ge=1, le=10)
    extra_discount_percent: int = Field(default=10, ge=0, le=50)


class DiscountSettingsBody(BaseModel):
    purchase_discount_percent: int = Field(default=0, ge=0, le=90)
    family_extra_discount_percent: int = Field(default=10, ge=0, le=50)


class WithdrawBody(BaseModel):
    card_number: str = Field(min_length=12, max_length=32)
    amount: int | None = None


class WalletDepositBody(BaseModel):
    amount_toman: int


class WalletTransferBody(BaseModel):
    target: str = Field(min_length=1, max_length=64)
    amount_toman: int = Field(gt=0, le=20_000_000)


class SubscriptionLabelBody(BaseModel):
    label: str = Field(default="", max_length=64)


class RenewSubscriptionBody(BaseModel):
    plan_id: int | None = None


class AutoRenewBody(BaseModel):
    enabled: bool


class ParentalRestrictBody(BaseModel):
    categories: list[str] = Field(default_factory=list)
    schedule: dict | None = None
    vpn_schedule: dict | None = None


class ParentalPauseBody(BaseModel):
    hours: int = Field(default=24, ge=1, le=336)


class AdminDutyBody(BaseModel):
    on_duty: bool = True


class RedeemGiftBody(BaseModel):
    code: str = Field(min_length=4, max_length=48)


class ParentalSettingsBody(BaseModel):
    enabled: bool = True
    custom_domains: list[str] = Field(default_factory=list)


class CustomPackageBody(CustomerMetaBody):
    duration_days: int = Field(ge=1, le=730)
    traffic_gb: int = Field(default=50, ge=0, le=2000)
    limit_ip: int = Field(default=2, ge=1, le=10)
    unlimited: bool = False
    target_subscription_id: int | None = Field(default=None, gt=0)
    promo_code: str | None = Field(default=None, max_length=32)
    family_size: int = Field(default=1, ge=1, le=10)
    config_label: str | None = Field(default=None, max_length=64)


class PaygPackageBody(CustomerMetaBody):
    traffic_gb: int = Field(default=10, ge=1, le=2000)
    limit_ip: int = Field(default=1, ge=1, le=10)
    target_subscription_id: int | None = Field(default=None, gt=0)
    config_label: str | None = Field(default=None, max_length=64)


class PaygBuilderSettingsBody(BaseModel):
    enabled: bool = True
    price_per_gb_toman: int = Field(default=4_000, ge=1, le=1_000_000)
    prepaid_price_per_gb_toman: int = Field(default=7_500, ge=1, le=1_000_000)
    min_wallet_toman: int = Field(default=10_000, ge=0, le=20_000_000)
    limit_ip: int = Field(default=2, ge=1, le=10)
    min_gb: int = Field(default=5, ge=1, le=2000)
    max_gb: int = Field(default=200, ge=1, le=2000)
    min_ip: int = Field(default=1, ge=1, le=10)
    max_ip: int = Field(default=3, ge=1, le=10)
    price_per_ip_toman: int = Field(default=25_000, ge=0, le=1_000_000)
    min_price_toman: int = Field(default=40_000, ge=0, le=20_000_000)


class PaygSetEnabledBody(BaseModel):
    enabled: bool


class CustomBuilderSettingsBody(BaseModel):
    enabled: bool = True
    min_days: int = Field(default=7, ge=1, le=730)
    max_days: int = Field(default=365, ge=1, le=730)
    min_gb: int = Field(default=10, ge=1, le=2000)
    max_gb: int = Field(default=500, ge=1, le=2000)
    min_ip: int = Field(default=1, ge=1, le=10)
    max_ip: int = Field(default=5, ge=1, le=10)
    base_fee_toman: int = Field(default=30_000, ge=0, le=10_000_000)
    price_per_day_toman: int = Field(default=3_500, ge=0, le=1_000_000)
    price_per_gb_toman: int = Field(default=1_000, ge=0, le=1_000_000)
    unlimited_day_fee_toman: int = Field(default=8_000, ge=0, le=1_000_000)
    price_per_ip_toman: int = Field(default=20_000, ge=0, le=1_000_000)
    min_price_toman: int = Field(default=100_000, ge=0, le=20_000_000)


class BirthDateBody(BaseModel):
    birth_date: str = Field(min_length=10, max_length=10)


class ProfileContactBody(BaseModel):
    email: str | None = Field(default=None, max_length=128)
    phone: str | None = Field(default=None, max_length=32)


class BirthdayGiftSettingBody(BaseModel):
    enabled: bool = False
    amount_toman: int = Field(ge=0, le=10_000_000)


class TrialSettingsBody(BaseModel):
    enabled: bool = True
    duration_days: int = Field(default=3, ge=1, le=30)
    traffic_gb: int = Field(default=2, ge=1, le=100)
    limit_ip: int = Field(default=1, ge=1, le=10)
    send_links: bool = False


class TrialGrantBody(BaseModel):
    targets: list[str] = Field(default_factory=list)
    targets_text: str = ""
    all_users: bool = False
    skip_existing_trial: bool = True
    notify_users: bool = True
    duration_days: int | None = Field(default=None, ge=1, le=365)
    traffic_gb: int | None = Field(default=None, ge=0, le=500)
    limit_ip: int | None = Field(default=None, ge=1, le=10)


class UserRoleBody(BaseModel):
    role: str = Field(pattern="^(user|admin)$")


class UserTestFlagBody(BaseModel):
    is_test: bool


class WalletAdjustBody(BaseModel):
    amount_toman: int = Field(..., ge=-50_000_000, le=50_000_000)
    note: str = Field(default="", max_length=200)


class WalletCreditLimitBody(BaseModel):
    credit_limit_toman: int = Field(..., ge=0, le=50_000_000)


class WalletConvertCreditBody(BaseModel):
    original_topup_toman: int = Field(..., ge=1, le=50_000_000)


class SubscriptionEnabledBody(BaseModel):
    enabled: bool


class GrantProBody(BaseModel):
    days: int | None = Field(default=None, ge=1, le=3650)


class GiftSubscriptionBody(BaseModel):
    plan_id: int = Field(..., ge=1)


class IpNicknameBody(BaseModel):
    ip: str = Field(min_length=3, max_length=64)
    nickname: str = Field(default="", max_length=32)


class BulkGiftBody(BaseModel):
    kind: str = Field(pattern="^(pro|plan)$")
    plan_id: int | None = Field(default=None, ge=1)
    pro_days: int | None = Field(default=None, ge=1, le=3650)
    targets_text: str = ""
    all_users: bool = False
    notify_users: bool = True


class TransferSubscriptionBody(BaseModel):
    target: str = Field(min_length=1, max_length=64)  # telegram id or @username
    notify: bool = True


class BroadcastBody(BaseModel):
    message: str = Field(min_length=1, max_length=4096)


class VpnServerBody(BaseModel):
    name: str = Field(min_length=1, max_length=64)
    country_code: str = Field(default="", max_length=16)
    xui_base_url: str = Field(min_length=8, max_length=512)
    xui_api_token: str = Field(min_length=8, max_length=256)
    inbound_ids: str = Field(min_length=1, max_length=128)
    public_host: str = Field(default="", max_length=255)
    public_ip: str = Field(default="", max_length=64)


class VpnServerEnabledBody(BaseModel):
    enabled: bool


class VpnServerVisibilityBody(BaseModel):
    enabled: bool | None = None
    configs: dict[str, bool] | None = None


class PaymentCardBody(BaseModel):
    card: str = Field(min_length=8, max_length=32)
    name: str = Field(default="", max_length=64)
    note: str = Field(default="", max_length=256)
    label: str = Field(default="", max_length=32)


class ChatAttachmentIn(BaseModel):
    type: str = Field(pattern="^(subscription|link|order)$")
    subscription_id: int | None = Field(default=None, gt=0)
    link_index: int | None = Field(default=None, ge=0)
    order_id: int | None = Field(default=None, gt=0)


class ChatMessageBody(BaseModel):
    body: str = Field(default="", max_length=4000)
    attachments: list[ChatAttachmentIn] = Field(default_factory=list, max_length=3)

    @model_validator(mode="after")
    def require_content(self):
        if not self.body.strip() and not self.attachments:
            raise ValueError("empty_message")
        return self


class AppState:
    settings: Settings
    session_factory: sessionmaker
    panel: XUIPanel


state = AppState()


def create_app() -> FastAPI:
    settings = get_settings()
    db_url = settings.database_url
    if db_url.startswith("sqlite:///"):
        Path(db_url.replace("sqlite:///", "", 1)).parent.mkdir(parents=True, exist_ok=True)

    session_factory = make_session_factory(db_url)
    with session_factory() as session:
        seed_defaults(session)
        state.panel = get_panel_hub(settings, session)
        try:
            state.panel.prepare_telegram_proxy()
        except Exception:
            logger.exception("telegram proxy prepare failed during startup")
        try:
            for member in state.panel.members:
                sync_telegram_proxy_for_panel(session, member)
        except Exception:
            logger.exception("telegram proxy startup sync failed")

    state.settings = settings
    state.session_factory = session_factory
    billing_stop = threading.Event()

    def _payg_billing_loop() -> None:
        ticks = 0
        while not billing_stop.wait(60):
            ticks += 1
            db = session_factory()
            try:
                bill_all_metered_payg(db, state.panel, settings)
                # Usage / renew / health: every cycle (~1 min). Health probes are cheap TCP.
                from app.jobs import run_maintenance_jobs

                # Refresh hub panel reference periodically in case servers changed.
                try:
                    from app.servers import get_panel_hub

                    state.panel = get_panel_hub(settings, db)
                except Exception:
                    logger.exception("hub refresh in maintenance failed")
                run_maintenance_jobs(db, state.panel, settings)
            except Exception:
                logger.exception("payg billing loop failed")
            finally:
                db.close()

    @asynccontextmanager
    async def lifespan(_app: FastAPI):
        worker = threading.Thread(target=_payg_billing_loop, name="payg-billing", daemon=True)
        worker.start()
        try:
            yield
        finally:
            billing_stop.set()

    app = FastAPI(title="Black Lines Shop API", docs_url=None, redoc_url=None, lifespan=lifespan)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @app.middleware("http")
    async def activity_log_middleware(request: Request, call_next):
        from app.ops import (
            bind_audit_request,
            describe_api_action,
            infer_actor_role,
            record_audit,
            reset_audit_request,
            skip_auto_audit_path,
        )

        token = bind_audit_request(request)
        method = request.method.upper()
        path = request.url.path
        raw = b""
        ctype = (request.headers.get("content-type") or "").lower()
        should = method in {"POST", "PUT", "PATCH", "DELETE"} and path.startswith("/shop/api/")
        try:
            if should and "multipart/" not in ctype:
                raw = await request.body()
                if len(raw) > 8192:
                    raw = raw[:8192]
            response = await call_next(request)
        finally:
            reset_audit_request(token)
        if not should or response.status_code >= 400 or skip_auto_audit_path(path):
            return response
        if getattr(request.state, "audit_written", False):
            return response
        try:
            actor = getattr(request.state, "actor", None)
            action, category, detail = describe_api_action(method, path, raw, ctype)
            db = session_factory()
            try:
                live = db.get(User, actor.id) if actor is not None and getattr(actor, "id", None) else None
                record_audit(
                    db,
                    actor=live,
                    action=action,
                    category=category,
                    path=path[:160],
                    detail=detail,
                    actor_role=infer_actor_role(live, path),
                )
            finally:
                db.close()
        except Exception:
            logger.exception("activity log failed")
        return response

    def get_db():
        db = session_factory()
        try:
            yield db
        finally:
            db.close()

    def _tg_post(method: str, *, json_body=None, data=None, files=None, timeout: float = 30):
        last = None
        for token in settings.all_bot_tokens:
            try:
                with httpx.Client(timeout=timeout) as http:
                    resp = http.post(
                        f"https://api.telegram.org/bot{token}/{method}",
                        json=json_body,
                        data=data,
                        files=files,
                    )
                body = resp.json() if resp.content else {}
                if resp.is_success and (not body or body.get("ok", True)):
                    return resp
                last = resp
            except Exception as exc:  # noqa: BLE001
                last = exc
                continue
        return last

    async def _tg_post_async(method: str, *, json_body=None, data=None, files=None, timeout: float = 60):
        last = None
        for token in settings.all_bot_tokens:
            try:
                async with httpx.AsyncClient(timeout=timeout) as http:
                    resp = await http.post(
                        f"https://api.telegram.org/bot{token}/{method}",
                        json=json_body,
                        data=data,
                        files=files,
                    )
                body = resp.json() if resp.content else {}
                if resp.is_success and (not body or body.get("ok", True)):
                    return resp
                last = resp
            except Exception as exc:  # noqa: BLE001
                last = exc
                continue
        return last

    def _notify_telegram(chat_id: int, text: str) -> None:
        send_telegram_message(settings, chat_id, text, parse_mode=None)

    def current_user(
        request: Request,
        x_telegram_init_data: Annotated[str | None, Header(alias="X-Telegram-Init-Data")] = None,
        authorization: Annotated[str | None, Header()] = None,
        db: Session = Depends(get_db),
    ) -> User:
        # Native app: Authorization Bearer <opaque session token>
        if authorization and authorization.lower().startswith("bearer "):
            resolved = resolve_bearer(db, authorization)
            if not resolved:
                raise HTTPException(401, "Invalid or expired session")
            user, app_session = resolved
            setattr(user, "_is_new_session", False)
            request.state.actor = user
            request.state.app_session = app_session
            if channel_gate_enabled(settings) and not is_channel_member(settings, user.telegram_id):
                raise HTTPException(status_code=403, detail=channel_required_payload(settings))
            return user

        if not x_telegram_init_data:
            raise HTTPException(401, "Telegram auth required")
        try:
            parsed = validate_webapp_init_data_any(x_telegram_init_data, settings.all_bot_tokens)
        except TelegramAuthError as exc:
            raise HTTPException(401, str(exc)) from exc
        tg = parsed["user"]
        tg_id = int(tg["id"])
        username = tg.get("username")
        full_name = " ".join(
            part for part in [tg.get("first_name"), tg.get("last_name")] if part
        ).strip() or None
        start_param = parsed.get("start_param") or ""
        referrer_code = None
        if start_param:
            referrer_code = start_param[4:] if start_param.lower().startswith("ref_") else start_param
        user, is_new = get_or_create_user(db, tg_id, username, full_name, referrer_code=referrer_code)
        setattr(user, "_is_new_session", is_new)
        request.state.actor = user
        if channel_gate_enabled(settings) and not is_channel_member(settings, tg_id):
            raise HTTPException(status_code=403, detail=channel_required_payload(settings))
        return user

    def require_admin(user: User = Depends(current_user)) -> User:
        if not is_user_admin(user, settings):
            raise HTTPException(403, "admin only")
        return user

    @app.get("/shop/api/health")
    def health():
        return {"ok": True, "shop": settings.shop_name}

    @app.post("/shop/api/auth/login/start")
    def auth_login_start(db: Session = Depends(get_db)):
        """Start Telegram bot deep-link login for the native app."""
        challenge = create_login_challenge(db)
        bot_username = resolve_bot_username(db, primary_bot_token=settings.primary_bot_token)
        bot_url = f"https://t.me/{bot_username}?start=app_{challenge.nonce}"
        return {
            "nonce": challenge.nonce,
            "bot_url": bot_url,
            "expires_at": challenge.expires_at.isoformat() + "Z",
        }

    @app.get("/shop/api/auth/poll/{nonce}")
    def auth_poll(nonce: str, db: Session = Depends(get_db)):
        """Poll until the user confirms login via the Telegram bot deep-link."""
        return poll_login_challenge(db, nonce.strip())

    @app.post("/shop/api/auth/logout")
    def auth_logout(request: Request, user: User = Depends(current_user), db: Session = Depends(get_db)):
        app_session = getattr(request.state, "app_session", None)
        if app_session is None:
            # Miniapp / initData sessions have nothing to revoke
            return {"ok": True}
        revoke_session(db, app_session)
        return {"ok": True}

    @app.get("/shop/api/channel")
    def channel_status(
        x_telegram_init_data: Annotated[str | None, Header(alias="X-Telegram-Init-Data")] = None,
    ):
        """Check channel membership without creating shop session side-effects beyond auth."""
        if not channel_gate_enabled(settings):
            return {"required": False, "member": True, "invite_url": None, "channel": None}
        if not x_telegram_init_data:
            raise HTTPException(401, "Telegram auth required")
        try:
            parsed = validate_webapp_init_data_any(x_telegram_init_data, settings.all_bot_tokens)
        except TelegramAuthError as exc:
            raise HTTPException(401, str(exc)) from exc
        tg_id = int(parsed["user"]["id"])
        clear_channel_cache(tg_id)
        member = is_channel_member(settings, tg_id, bypass_cache=True)
        payload = channel_required_payload(settings)
        return {
            "required": True,
            "member": member,
            "channel": payload["channel"],
            "invite_url": payload["invite_url"],
            "message": payload["message"],
        }

    @app.get("/shop/sub/{token}")
    def public_subscription(token: str, db: Session = Depends(get_db)):
        """Subscription URI for V2rayNG / V2Box / Hiddify — base64 of active VPN links."""
        token = (token or "").strip()
        if not token or len(token) < 8 or len(token) > 64:
            raise HTTPException(404, "not found")
        if any(ch for ch in token if not (ch.isalnum() or ch in "-_")):
            raise HTTPException(404, "not found")
        sub = db.scalar(select(Subscription).where(Subscription.xui_sub_id == token))
        if not sub or not sub.enabled:
            raise HTTPException(404, "not found")
        try:
            links = public_links_for_subscription(state.panel, sub, settings)
        except PanelError as exc:
            raise HTTPException(502, str(exc)) from exc
        body = subscription_import_base64(links)
        expire_ts = int(sub.expires_at.timestamp()) if sub.expires_at else 0
        headers = {
            "profile-update-interval": "12",
            "subscription-userinfo": f"upload=0; download=0; total=0; expire={expire_ts}",
            "Cache-Control": "no-store",
            "Content-Disposition": 'inline; filename="subscription.txt"',
        }
        return Response(content=body, media_type="text/plain; charset=utf-8", headers=headers)

    def finalize_shop_order(db: Session, user: User, order, *, resumed: bool = False, **extra):
        maybe_auto_fulfill_prepaid_order(db, state.panel, settings, order)
        db.refresh(user)
        db.refresh(order)
        approved = order.status == OrderStatus.APPROVED
        from app.gifts import get_gift_card_for_order, is_gift_card_order

        payload = {
            "id": order.id,
            "amount_toman": order.amount_toman,
            "amount_label": format_price(order.amount_toman),
            "wallet_used": order.wallet_used or 0,
            "needs_receipt": (order.amount_toman or 0) > 0 and not approved,
            "wallet_balance": user.wallet_balance or 0,
            "resumed": resumed,
            "payment": payment_info(db, settings),
            "auto_approved": approved and (order.amount_toman or 0) <= 0,
            "status": order.status.value if hasattr(order.status, "value") else str(order.status),
        }
        if is_gift_card_order(order):
            payload["is_gift_card"] = True
            card = get_gift_card_for_order(db, order)
            if card and approved:
                payload["kind"] = "gift_card"
                payload["gift_code"] = card.code
                payload["gift_card"] = {"id": card.id, "code": card.code, "plan_title": order.plan.title if order.plan else None}
        payload.update(extra)
        return payload

    @app.get("/shop/api/me")
    def me(
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        maybe_grant_birthday_gift(db, user)
        db.refresh(user)
        view = wallet_view(user)
        return {
            "telegram_id": user.telegram_id,
            "username": user.username,
            "full_name": user.full_name,
            "wallet_balance": view["balance"],
            "wallet_debt": view["debt"],
            "wallet_credit_limit": view["credit_limit"],
            "wallet_spendable": view["spendable"],
            "is_admin": is_user_admin(user, settings),
            "role": user.role or USER_ROLE_USER,
            "on_duty": bool(getattr(user, "on_duty", False)) if is_user_admin(user, settings) else False,
            "shop_name": settings.shop_name,
            "payment": payment_info(db, settings),
            "has_birth_date": bool(user.birth_date),
            "birthday_gift": None,
            "trial_account": None,
            "trial_offer": trial_offer_dict(db, user),
            "is_pro": is_user_pro(user),
            "pro_until": user.pro_until.isoformat() if user.pro_until else None,
        }

    @app.post("/shop/api/trial/claim")
    def claim_trial_api(user: User = Depends(current_user), db: Session = Depends(get_db)):
        try:
            data = claim_user_trial(db, user, state.panel, settings, notify=True)
        except ValueError as exc:
            messages = {
                "already_granted": "قبلاً کانفیگ تست گرفته‌اید",
                "trial_disabled": "حساب تست فعلاً غیرفعال است",
                "already_has_config": "چون قبلاً کانفیگ دارید، تست رایگان فعال نمی‌شود",
            }
            raise HTTPException(400, messages.get(str(exc), str(exc))) from exc
        except PanelError as exc:
            raise HTTPException(502, str(exc)) from exc
        except Exception as exc:
            logger.exception("trial claim failed user=%s", user.id)
            raise HTTPException(400, "ساخت کانفیگ تست ناموفق بود") from exc
        return data

    def _profile_payload(db: Session, user: User, gift: dict | None = None) -> dict:
        data = user_profile_dict(db, user)
        data["wallet_balance"] = user.wallet_balance or 0
        data["birthday_gift"] = None
        return data

    @app.get("/shop/api/profile")
    def profile(user: User = Depends(current_user), db: Session = Depends(get_db)):
        sync_user_telegram_profile(db, user, settings)
        maybe_grant_birthday_gift(db, user)
        db.refresh(user)
        return _profile_payload(db, user)

    @app.get("/shop/api/profile/photo")
    def profile_photo(user: User = Depends(current_user), db: Session = Depends(get_db)):
        file_id = getattr(user, "photo_file_id", None)
        if not file_id:
            file_id = telegram_user_photo_file_id(settings, user.telegram_id)
            if file_id:
                user.photo_file_id = file_id
                db.commit()
        if not file_id:
            raise HTTPException(404, "no_photo")
        cached = _PROFILE_PHOTO_CACHE.get(user.telegram_id)
        if cached and cached[0] == file_id:
            return Response(
                content=cached[1],
                media_type=cached[2],
                headers={"Cache-Control": "private, max-age=3600"},
            )
        downloaded = telegram_download_file(settings, file_id)
        if not downloaded:
            raise HTTPException(404, "no_photo")
        content, ctype = downloaded
        _PROFILE_PHOTO_CACHE[user.telegram_id] = (file_id, content, ctype)
        return Response(
            content=content,
            media_type=ctype,
            headers={"Cache-Control": "private, max-age=3600"},
        )

    @app.post("/shop/api/profile/birth-date")
    def save_birth_date(
        body: BirthDateBody,
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        try:
            birth_date = date.fromisoformat(body.birth_date)
        except ValueError as exc:
            raise HTTPException(400, "invalid_date") from exc
        try:
            set_user_birth_date(db, user, birth_date, source="manual", year_hidden=False)
        except ValueError as exc:
            raise HTTPException(400, str(exc)) from exc
        maybe_grant_birthday_gift(db, user)
        db.refresh(user)
        return _profile_payload(db, user)

    @app.post("/shop/api/profile/contact")
    def save_profile_contact(
        body: ProfileContactBody,
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        try:
            set_user_contact(db, user, email=body.email, phone=body.phone)
        except ValueError as exc:
            raise HTTPException(400, str(exc)) from exc
        return _profile_payload(db, user)

    @app.get("/shop/api/plans")
    def plans(user: User = Depends(current_user), db: Session = Depends(get_db)):
        items = list_enabled_plans(db, user)
        discount = pro_discount_percent(db)
        pro_active = is_user_pro(user)
        wallet = wallet_spendable(user)
        return [
            {
                "id": p.id,
                "title": p.title,
                "description": p.description,
                "price_toman": p.price_toman,
                "price_label": format_price(p.price_toman),
                "charge_toman": plan_charge_price(db, user, p),
                "charge_label": format_price(plan_charge_price(db, user, p)),
                "pro_discount_percent": discount if pro_active else 0,
                "duration_days": p.duration_days,
                "traffic_gb": p.traffic_gb,
                "traffic_label": traffic_label(p.traffic_gb),
                "limit_ip": p.limit_ip,
                "pro_only": is_pro_only_shop_plan(p),
                "pay_after_wallet": max(0, plan_charge_price(db, user, p) - wallet),
            }
            for p in items
        ]

    @app.get("/shop/api/pro")
    def pro_info(user: User = Depends(current_user), db: Session = Depends(get_db)):
        data = pro_status_dict(db, user)
        data["config_count"] = len(user_all_subscriptions(db, user.id))
        return data

    @app.post("/shop/api/pro/order")
    def pro_order(user: User = Depends(current_user), db: Session = Depends(get_db)):
        plan = get_platform_pro_plan(db)
        db.refresh(user)
        pending = user_pending_order(db, user.id)
        if pending:
            return finalize_shop_order(
                db, user, pending, resumed=True, is_platform_pro=is_platform_pro(pending.plan)
            )
        try:
            order = create_order(db, user, plan)
        except PendingOrderError as exc:
            raise HTTPException(400, "سفارش ناتمام دارید") from exc
        return finalize_shop_order(db, user, order, is_platform_pro=True)

    @app.post("/shop/api/orders")
    def create_order_api(
        payload: Annotated[CreateOrderBody, Body()],
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        plan = get_plan(db, payload.plan_id)
        if not plan or not plan.enabled:
            raise HTTPException(404, "پلن پیدا نشد")
        db.refresh(user)
        pending = user_pending_order(db, user.id)
        if pending:
            return finalize_shop_order(db, user, pending, resumed=True)
        try:
            order = create_order(
                db,
                user,
                plan,
                promo_code=payload.promo_code,
                family_size=payload.family_size,
                customer_name=payload.customer_name,
                customer_email=payload.customer_email,
                customer_phone=payload.customer_phone,
                customer_telegram_id=payload.customer_telegram_id,
                config_label=payload.config_label,
                gift_card=bool(payload.gift_card),
            )
        except PendingOrderError as exc:
            raise HTTPException(400, "سفارش ناتمام دارید") from exc
        except ValueError as exc:
            from app.gifts import gift_error_fa
            from app.growth import promo_error_fa

            code = str(exc)
            raise HTTPException(400, gift_error_fa(code) if code.startswith("gift_") else promo_error_fa(code)) from exc
        extra = {
            "promo_code": order.promo_code,
            "discount_toman": int(order.discount_toman or 0),
            "bonus_days": int(order.bonus_days or 0),
            "family_size": int(order.family_size or 1),
        }
        return finalize_shop_order(db, user, order, **extra)

    @app.get("/shop/api/gift-cards")
    def list_gift_cards_api(user: User = Depends(current_user), db: Session = Depends(get_db)):
        from app.gifts import list_user_gift_cards

        return {"items": list_user_gift_cards(db, user)}

    @app.post("/shop/api/gift-cards/redeem")
    def redeem_gift_card_api(
        body: RedeemGiftBody,
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        from app.gifts import gift_error_fa, redeem_gift_card

        try:
            return redeem_gift_card(db, user, body.code, state.panel, settings)
        except ValueError as exc:
            raise HTTPException(400, gift_error_fa(str(exc))) from exc
        except PanelError as exc:
            raise HTTPException(502, str(exc)) from exc
        except Exception as exc:
            logger.exception("gift redeem failed user=%s", user.id)
            raise HTTPException(400, "فعال‌سازی کارت هدیه ناموفق بود") from exc

    @app.get("/shop/api/custom/options")
    def custom_options(user: User = Depends(current_user), db: Session = Depends(get_db)):
        return custom_builder_settings(db, user)

    @app.post("/shop/api/custom/quote")
    def custom_quote(
        payload: Annotated[CustomPackageBody, Body()],
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        db.refresh(user)
        try:
            data = quote_custom_package(
                db,
                user,
                duration_days=payload.duration_days,
                traffic_gb=payload.traffic_gb,
                limit_ip=payload.limit_ip,
                unlimited=payload.unlimited,
            )
        except ValueError as exc:
            code = str(exc)
            messages = {
                "custom_builder_disabled": "ساخت پکیج سفارشی غیرفعال است",
                "duration_out_of_range": "مدت زمان خارج از محدوده مجاز است",
                "traffic_out_of_range": "حجم ترافیک خارج از محدوده مجاز است",
                "ip_out_of_range": "تعداد دستگاه خارج از محدوده مجاز است",
                "unlimited_disabled": "پلن نامحدود فعلاً در دسترس نیست",
                "unlimited_pro_only": "پکیج نامحدود فقط برای اعضای Pro است",
            }
            raise HTTPException(400, messages.get(code, code)) from exc
        if not payload.target_subscription_id:
            from app.growth import promo_error_fa, quote_growth_pricing

            growth = quote_growth_pricing(
                db,
                user,
                int(data["charge_toman"]),
                promo_code=payload.promo_code,
                family_size=payload.family_size,
            )
            if payload.promo_code and not growth["promo_ok"]:
                raise HTTPException(400, promo_error_fa(growth.get("promo_error") or "promo_invalid"))
            data["charge_toman"] = int(growth["charge_toman"])
            data["charge_label"] = format_price(int(growth["charge_toman"]))
            data["pay_after_wallet"] = max(0, int(growth["charge_toman"]) - wallet_spendable(user))
            data["discount_toman"] = int(growth.get("discount_toman") or 0)
            data["bonus_days"] = int(growth.get("bonus_days") or 0)
            data["family_size"] = int(growth.get("family_size") or 1)
            data["promo_code"] = growth.get("promo_code")
        return data

    @app.post("/shop/api/custom/order")
    def custom_order_api(
        payload: Annotated[CustomPackageBody, Body()],
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        db.refresh(user)
        pending = user_pending_order(db, user.id)
        if pending:
            return finalize_shop_order(db, user, pending, resumed=True, custom=is_custom_order(pending))
        try:
            order = create_custom_order(
                db,
                user,
                duration_days=payload.duration_days,
                traffic_gb=payload.traffic_gb,
                limit_ip=payload.limit_ip,
                unlimited=payload.unlimited,
                target_subscription_id=payload.target_subscription_id,
                promo_code=payload.promo_code,
                family_size=payload.family_size,
                customer_name=payload.customer_name,
                customer_email=payload.customer_email,
                customer_phone=payload.customer_phone,
                customer_telegram_id=payload.customer_telegram_id,
                config_label=payload.config_label,
            )
        except PendingOrderError as exc:
            raise HTTPException(400, "سفارش ناتمام دارید") from exc
        except ValueError as exc:
            code = str(exc)
            from app.growth import promo_error_fa

            messages = {
                "custom_builder_disabled": "ساخت پکیج سفارشی غیرفعال است",
                "duration_out_of_range": "مدت زمان خارج از محدوده مجاز است",
                "traffic_out_of_range": "حجم ترافیک خارج از محدوده مجاز است",
                "ip_out_of_range": "تعداد دستگاه خارج از محدوده مجاز است",
                "unlimited_disabled": "پلن نامحدود فعلاً در دسترس نیست",
                "unlimited_pro_only": "پکیج نامحدود فقط برای اعضای Pro است",
            }
            raise HTTPException(400, messages.get(code, promo_error_fa(code))) from exc
        return finalize_shop_order(
            db,
            user,
            order,
            custom=True,
            renew=bool(order.target_subscription_id),
            target_subscription_id=order.target_subscription_id,
            plan_title=order_plan_title(order),
            promo_code=order.promo_code,
            discount_toman=int(order.discount_toman or 0),
            bonus_days=int(order.bonus_days or 0),
            family_size=int(order.family_size or 1),
        )

    @app.get("/shop/api/payg/options")
    def payg_options(user: User = Depends(current_user), db: Session = Depends(get_db)):
        cfg = payg_prepaid_settings(db)
        data = {
            "enabled": payg_builder_enabled(db),
            "min_gb": cfg["min_gb"],
            "max_gb": cfg["max_gb"],
            "min_ip": cfg["min_ip"],
            "max_ip": cfg["max_ip"],
            "price_per_gb_toman": cfg["price_per_gb_toman"],
            "price_per_ip_toman": cfg["price_per_ip_toman"],
            "min_price_toman": cfg["min_price_toman"],
            "existing": [],
        }
        for s in user_prepaid_payg_subscriptions(db, user.id):
            data["existing"].append(
                {
                    "id": s.id,
                    "email": s.xui_email,
                    "label": s.label,
                    "plan_title": subscription_config_dict(s)["plan_title"],
                }
            )
        return data

    @app.post("/shop/api/payg/quote")
    def payg_quote(
        payload: Annotated[PaygPackageBody, Body()],
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        db.refresh(user)
        try:
            return quote_payg_package(
                db,
                user,
                traffic_gb=payload.traffic_gb,
                limit_ip=payload.limit_ip,
                target_subscription_id=payload.target_subscription_id,
            )
        except ValueError as exc:
            messages = {
                "payg_builder_disabled": "پرداخت مصرفی فعلاً غیرفعال است",
                "traffic_out_of_range": "حجم ترافیک خارج از محدوده مجاز است",
                "ip_out_of_range": "تعداد دستگاه خارج از محدوده مجاز است",
            }
            raise HTTPException(400, messages.get(str(exc), str(exc))) from exc

    @app.post("/shop/api/payg/order")
    def payg_order_api(
        payload: Annotated[PaygPackageBody, Body()],
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        db.refresh(user)
        pending = user_pending_order(db, user.id)
        if pending:
            return finalize_shop_order(
                db,
                user,
                pending,
                resumed=True,
                payg=is_payg_order(pending),
                renew=bool(pending.target_subscription_id),
            )
        try:
            order = create_payg_order(
                db,
                user,
                traffic_gb=payload.traffic_gb,
                limit_ip=payload.limit_ip,
                target_subscription_id=payload.target_subscription_id,
                customer_name=payload.customer_name,
                customer_email=payload.customer_email,
                customer_phone=payload.customer_phone,
                customer_telegram_id=payload.customer_telegram_id,
                config_label=payload.config_label,
            )
        except PendingOrderError as exc:
            raise HTTPException(400, "سفارش ناتمام دارید") from exc
        except ValueError as exc:
            messages = {
                "payg_builder_disabled": "پرداخت مصرفی فعلاً غیرفعال است",
                "traffic_out_of_range": "حجم ترافیک خارج از محدوده مجاز است",
                "ip_out_of_range": "تعداد دستگاه خارج از محدوده مجاز است",
                "payg_target_invalid": "کانفیگ حجم‌دار معتبر نیست",
            }
            raise HTTPException(400, messages.get(str(exc), str(exc))) from exc
        return finalize_shop_order(
            db,
            user,
            order,
            payg=True,
            renew=bool(order.target_subscription_id),
            target_subscription_id=order.target_subscription_id,
            plan_title=order_plan_title(order),
        )

    @app.get("/shop/api/payg/status")
    def payg_status(user: User = Depends(current_user), db: Session = Depends(get_db)):
        db.refresh(user)
        return payg_status_dict(db, user, state.panel, bill=True)

    @app.post("/shop/api/payg/activate")
    def payg_activate_api(user: User = Depends(current_user), db: Session = Depends(get_db)):
        db.refresh(user)
        try:
            result = activate_metered_payg(db, user, state.panel, settings)
        except ValueError as exc:
            messages = {
                "payg_builder_disabled": "پرداخت مصرفی فعلاً غیرفعال است",
                "insufficient_wallet": "موجودی کیف‌پول برای فعال‌سازی کافی نیست",
            }
            raise HTTPException(400, messages.get(str(exc), str(exc))) from exc
        except PanelError as exc:
            raise HTTPException(502, str(exc)) from exc
        if result.get("created"):
            from app.texts import subscription_link_message

            send_telegram_message(
                settings,
                user.telegram_id,
                subscription_link_message(
                    email=result.get("email") or "",
                    sub_url=result.get("subscription_url"),
                    label="مصرفی ابری",
                    title="✅ کانفیگ مصرفی فعال شد",
                    extra="فقط به‌اندازه مصرف واقعی از کیف‌پول کسر می‌شود.",
                ),
                extra={"disable_web_page_preview": True},
            )
        db.refresh(user)
        result["wallet_balance"] = user.wallet_balance or 0
        return result

    @app.post("/shop/api/payg/set-enabled")
    def payg_set_enabled_api(
        body: PaygSetEnabledBody,
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        db.refresh(user)
        try:
            result = set_metered_payg_enabled(db, user, state.panel, enabled=body.enabled, settings=settings)
        except ValueError as exc:
            messages = {
                "payg_builder_disabled": "پرداخت مصرفی فعلاً غیرفعال است",
                "payg_not_found": "کانفیگ مصرفی پیدا نشد",
                "insufficient_wallet": "موجودی کیف‌پول برای فعال‌سازی کافی نیست",
            }
            raise HTTPException(400, messages.get(str(exc), str(exc))) from exc
        except PanelError as exc:
            raise HTTPException(502, str(exc)) from exc
        db.refresh(user)
        result["wallet_balance"] = user.wallet_balance or 0
        return result

    @app.post("/shop/api/orders/{order_id}/cancel")
    def cancel_order_api(
        order_id: int,
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        order = get_order(db, order_id)
        if not order or order.user_id != user.id:
            raise HTTPException(404, "سفارش پیدا نشد")
        if order.status != OrderStatus.PENDING:
            raise HTTPException(400, "این سفارش قابل لغو نیست")
        cancel_order(db, order, note="cancelled_via_miniapp")
        db.refresh(user)
        return {"ok": True, "wallet_balance": user.wallet_balance or 0}

    @app.post("/shop/api/orders/{order_id}/receipt")
    async def upload_receipt(
        order_id: int,
        file: UploadFile = File(...),
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        order = get_order(db, order_id)
        if not order or order.user_id != user.id:
            raise HTTPException(404, "order not found")
        if order.status != OrderStatus.PENDING:
            raise HTTPException(400, "order not pending")
        data = await file.read()
        if not data:
            raise HTTPException(400, "empty file")
        if len(data) > 8 * 1024 * 1024:
            raise HTTPException(400, "file too large")

        try:
            save_receipt_local(order.id, data, file.filename, file.content_type)
        except Exception:
            logger.exception("Failed saving receipt locally for order %s", order.id)
            raise HTTPException(500, "ذخیره رسید ناموفق بود") from None

        if not order.receipt_file_id:
            order.receipt_file_id = "miniapp-uploaded"
            db.commit()

        caption = (
            f"🧾 سفارش #{order.id} (مینی‌اپ)\n"
            f"کاربر: {user.full_name or '—'} (@{user.username or '—'})\n"
            f"آیدی: {user.telegram_id}\n"
            f"مبلغ: {format_price(order.amount_toman)}"
        )
        keyboard = {
            "inline_keyboard": [[
                {"text": "✅ تایید و ساخت کانفیگ", "callback_data": f"adm:ok:{order.id}"},
                {"text": "❌ رد", "callback_data": f"adm:no:{order.id}"},
            ]]
        }
        try:
            notified = False
            for admin_id in settings.admin_ids:
                resp = await _tg_post_async(
                    "sendDocument",
                    data={"chat_id": str(admin_id), "caption": caption, "reply_markup": json.dumps(keyboard)},
                    files={
                        "document": (
                            file.filename or "receipt.jpg",
                            data,
                            file.content_type or "application/octet-stream",
                        )
                    },
                    timeout=20,
                )
                if resp is None or not hasattr(resp, "json"):
                    continue
                payload = resp.json()
                if not isinstance(payload, dict):
                    continue
                if payload.get("ok"):
                    notified = True
                    doc = payload["result"].get("document") or {}
                    photo = (payload["result"].get("photo") or [None])[-1] or {}
                    file_id = doc.get("file_id") or photo.get("file_id")
                    if file_id:
                        order.receipt_file_id = file_id
                        db.commit()
            if not notified:
                logger.warning("receipt saved locally but telegram notify failed order=%s", order.id)
        except Exception:
            logger.exception("receipt notify failed order=%s", order.id)
        return {"ok": True, "order_id": order.id}

    @app.get("/shop/api/orders/{order_id}/receipt")
    async def get_order_receipt(
        order_id: int,
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        order = get_order(db, order_id)
        if not order:
            raise HTTPException(404, "order not found")
        if order.user_id != user.id and not is_user_admin(user, settings):
            raise HTTPException(403, "forbidden")
        if not order.receipt_file_id:
            raise HTTPException(404, "receipt not found")
        resolved = await resolve_receipt(order.id, order.receipt_file_id, settings.all_bot_tokens)
        if not resolved:
            raise HTTPException(404, "receipt not available")
        body, media_type = resolved
        return Response(content=body, media_type=media_type)

    @app.post("/shop/api/orders/{order_id}/confirm-wallet")
    def confirm_wallet_only(
        order_id: int,
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        order = get_order(db, order_id)
        if not order or order.user_id != user.id:
            raise HTTPException(404, "order not found")
        if order.status == OrderStatus.APPROVED:
            return {"ok": True, "auto_approved": True, "already_approved": True}
        if order.amount_toman > 0:
            raise HTTPException(400, "receipt required")
        result = maybe_auto_fulfill_prepaid_order(db, state.panel, settings, order)
        if result:
            return {"ok": True, "auto_approved": True}
        text = (
            f"🧾 سفارش #{order.id} (پرداخت کامل با کیف‌پول)\n"
            f"کاربر: {user.full_name or '—'} ({user.telegram_id})\n"
            f"مبلغ واریزی: ۰"
        )
        keyboard = {
            "inline_keyboard": [[
                {"text": "✅ تایید و ساخت کانفیگ", "callback_data": f"adm:ok:{order.id}"},
                {"text": "❌ رد", "callback_data": f"adm:no:{order.id}"},
            ]]
        }
        with httpx.Client(timeout=30) as client:
            for admin_id in settings.admin_ids:
                _tg_post("sendMessage", json_body={"chat_id": admin_id, "text": text, "reply_markup": keyboard})
        return {"ok": True, "auto_approved": False}

    @app.get("/shop/api/subscriptions")
    def subscriptions(user: User = Depends(current_user), db: Session = Depends(get_db)):
        pending = user_pending_order(db, user.id)
        if pending:
            maybe_auto_fulfill_prepaid_order(db, state.panel, settings, pending)
        subs = user_active_subscriptions(db, user.id)
        pending = user_pending_order(db, user.id)
        return {
            "items": [
                {
                    "id": s.id,
                    "email": s.xui_email,
                    "plan_title": subscription_config_dict(s)["plan_title"],
                    "label": s.label,
                    "expires_at": s.expires_at.isoformat() if s.expires_at else None,
                    "traffic_label": subscription_config_dict(s)["traffic_label"],
                    "status": "active",
                }
                for s in subs
            ],
            "pending": (
                {
                    "id": pending.id,
                    "plan_title": order_plan_title(pending),
                    "amount_toman": pending.amount_toman,
                    "amount_label": format_price(pending.amount_toman),
                    "wallet_used": pending.wallet_used or 0,
                    "has_receipt": bool(pending.receipt_file_id),
                    "is_wallet_topup": is_wallet_topup(pending.plan),
                    "is_platform_pro": is_platform_pro(pending.plan),
                    "payment": payment_info(db, settings),
                    "recipientName": (getattr(pending, "customer_name", None) or "").strip() or None,
                    "familySize": int(getattr(pending, "family_size", 1) or 1) or None,
                }
                if pending
                else None
            ),
        }

    @app.get("/shop/api/dashboard")
    def dashboard(user: User = Depends(current_user), db: Session = Depends(get_db)):
        pending = user_pending_order(db, user.id)
        if pending:
            maybe_auto_fulfill_prepaid_order(db, state.panel, settings, pending)
        subs = user_all_subscriptions(db, user.id)
        now = datetime.utcnow()
        archived_items = []
        visible_subs = []
        for s in subs:
            if getattr(s, "hidden_from_dashboard", False):
                cfg = subscription_config_dict(s)
                expired = subscription_is_expired(s, now=now)
                archived_items.append(
                    {
                        "id": s.id,
                        "email": s.xui_email,
                        "label": s.label,
                        "plan_title": cfg["plan_title"],
                        "expires_at": s.expires_at.isoformat() if s.expires_at else None,
                        "status": "expired" if expired else ("disabled" if not s.enabled else "offline"),
                        "traffic_label": cfg["traffic_label"],
                        "link_shared": bool(getattr(s, "link_shared_at", None)),
                        **customer_meta_dict(s),
                    }
                )
            else:
                visible_subs.append(s)
        online: set[str] = set()
        last_map: dict[str, int] = {}
        try:
            online = state.panel.online_emails()
        except PanelError as exc:
            logger.warning("online fetch failed: %s", exc)
        try:
            last_map = state.panel.last_online_map()
        except PanelError as exc:
            logger.warning("lastOnline fetch failed: %s", exc)

        items = []
        online_count = 0
        total_up = 0
        total_down = 0
        total_used = 0
        total_remaining = 0
        remaining_known = False
        last_activity_at: datetime | None = None
        all_daily: dict[str, int] = {}
        for s in visible_subs:
            traffic = {}
            try:
                traffic = state.panel.get_traffic(s.xui_email)
            except PanelError as exc:
                logger.warning("traffic fetch failed for %s: %s", s.xui_email, exc)

            up = int(traffic.get("up") or 0)
            down = int(traffic.get("down") or 0)
            used = up + down
            total = int(traffic.get("total") or 0)
            cfg = subscription_config_dict(s)
            if (
                total <= 0
                and s.plan
                and s.plan.traffic_gb > 0
                and not is_metered_payg(s)
                and not cfg.get("is_payg")
            ):
                total = int(s.plan.traffic_gb) * 1024 * 1024 * 1024
            panel_enable = traffic.get("enable")
            enabled = bool(panel_enable) if panel_enable is not None else bool(s.enabled)
            last_ms = int(traffic.get("lastOnline") or last_map.get(s.xui_email) or 0)
            is_online = s.xui_email in online
            if is_online:
                online_count += 1
            expired = bool(s.expires_at and s.expires_at <= now)
            status = "online" if is_online else ("expired" if expired else ("disabled" if not enabled else "offline"))
            total_label = "نامحدود" if total <= 0 else format_bytes(total)
            if is_metered_payg(s):
                total_label = "مصرف کیف‌پول"
            last_online_at = datetime.utcfromtimestamp(last_ms / 1000) if last_ms > 0 else None
            if last_online_at and (last_activity_at is None or last_online_at > last_activity_at):
                last_activity_at = last_online_at
            try:
                record_usage_sample(
                    db,
                    s,
                    up_bytes=up,
                    down_bytes=down,
                    used_bytes=used,
                    online=is_online,
                    min_interval_sec=300,
                )
                # Release SQLite write lock between slow panel HTTP calls.
                db.commit()
            except Exception:
                db.rollback()
                logger.warning("usage sample skipped for %s (db busy)", s.xui_email)
            analytics = subscription_usage_analytics(
                db,
                s,
                up_bytes=up,
                down_bytes=down,
                used_bytes=used,
                total_bytes=total,
                last_online_at=last_online_at,
            )
            total_up += up
            total_down += down
            total_used += used
            for day in analytics["daily"]:
                all_daily[day["day"]] = all_daily.get(day["day"], 0) + int(day["used_bytes"])
            remaining_label = analytics["remaining_label"]
            remaining_bytes = analytics["remaining_bytes"]
            usage_percent = round(min(100.0, (used / total) * 100), 1) if total > 0 else 0.0
            if is_metered_payg(s):
                metered = apply_metered_payg_stats(
                    db,
                    user,
                    s,
                    {
                        "remaining_label": remaining_label,
                        "remaining_bytes": remaining_bytes,
                        "usage_percent": usage_percent,
                    },
                )
                remaining_label = metered.get("remaining_label", remaining_label)
                remaining_bytes = metered.get("remaining_bytes", remaining_bytes)
                usage_percent = metered.get("usage_percent", usage_percent)
            if remaining_bytes is not None:
                total_remaining += remaining_bytes
                remaining_known = True
            items.append(
                {
                    "id": s.id,
                    "email": s.xui_email,
                    "label": s.label,
                    "plan_title": cfg["plan_title"],
                    "expires_at": s.expires_at.isoformat() if s.expires_at else None,
                    "enabled": enabled,
                    "online": is_online,
                    "status": status,
                    "up_bytes": up,
                    "down_bytes": down,
                    "up_label": format_bytes(up),
                    "down_label": format_bytes(down),
                    "used_bytes": used,
                    "total_bytes": total,
                    "used_label": format_bytes(used),
                    "total_label": total_label,
                    "remaining_bytes": remaining_bytes,
                    "remaining_label": remaining_label,
                    "usage_percent": usage_percent,
                    "last_online_ms": last_ms,
                    "last_online_at": last_online_at.isoformat() if last_online_at else None,
                    "last_seen_label": analytics["last_seen_label"],
                    "limit_ip": cfg["limit_ip"],
                    "traffic_label": cfg["traffic_label"],
                    "is_payg": bool(cfg.get("is_payg")),
                    "is_metered": is_metered_payg(s),
                    "today_bytes": analytics["today_bytes"],
                    "today_label": analytics["today_label"],
                    "week_label": analytics["week_label"],
                    "avg_daily_label": analytics["avg_daily_label"],
                    "days_left": analytics["days_left"],
                    "sparkline": analytics["sparkline"],
                    "daily": analytics["daily"],
                    "family_role": getattr(s, "family_role", None),
                    "family_index": getattr(s, "family_index", None),
                    "family_group": getattr(s, "family_group", None),
                    "subscription_url": build_subscription_url(s.xui_sub_id, settings),
                    "link_shared": bool(getattr(s, "link_shared_at", None)),
                    **customer_meta_dict(s),
                }
            )
        db.commit()
        daily_summary = []
        for i in range(6, -1, -1):
            day = (datetime.utcnow().date() - timedelta(days=i))
            key = day.isoformat()
            used_day = all_daily.get(key, 0)
            daily_summary.append(
                {
                    "day": key,
                    "label": f"{day.month}/{day.day}",
                    "used_bytes": used_day,
                    "used_label": format_bytes(used_day),
                }
            )
        today_total = daily_summary[-1]["used_bytes"] if daily_summary else 0
        week_total = sum(d["used_bytes"] for d in daily_summary)

        return {
            "summary": {
                "total": len(items),
                "online": online_count,
                "offline": max(0, len(items) - online_count),
                "used_bytes": total_used,
                "used_label": format_bytes(total_used),
                "up_bytes": total_up,
                "down_bytes": total_down,
                "up_label": format_bytes(total_up),
                "down_label": format_bytes(total_down),
                "today_bytes": today_total,
                "today_label": format_bytes(today_total),
                "week_bytes": week_total,
                "week_label": format_bytes(week_total),
                "remaining_bytes": total_remaining if remaining_known else None,
                "remaining_label": format_bytes(total_remaining) if remaining_known else "نامحدود / مصرفی",
                "last_activity_at": last_activity_at.isoformat() if last_activity_at else None,
                "last_seen_label": relative_time_fa(last_activity_at) if last_activity_at else None,
                "daily": daily_summary,
            },
            "items": items,
            "archived": archived_items,
        }

    @app.post("/shop/api/subscriptions/{sub_id}/label")
    def update_subscription_label(
        sub_id: int,
        payload: Annotated[SubscriptionLabelBody, Body()],
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        sub = db.get(Subscription, sub_id)
        if not sub or sub.user_id != user.id:
            raise HTTPException(404, "اشتراک پیدا نشد")
        updated = set_subscription_label(db, sub, payload.label)
        return {"ok": True, "id": updated.id, "label": updated.label}

    @app.post("/shop/api/subscriptions/{sub_id}/customer")
    def update_subscription_customer(
        sub_id: int,
        payload: Annotated[CustomerMetaBody, Body()],
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        sub = db.get(Subscription, sub_id)
        if not sub or sub.user_id != user.id:
            raise HTTPException(404, "اشتراک پیدا نشد")
        updated = set_subscription_customer(
            db,
            sub,
            customer_name=payload.customer_name,
            customer_email=payload.customer_email,
            customer_phone=payload.customer_phone,
            customer_telegram_id=payload.customer_telegram_id,
        )
        return {"ok": True, "id": updated.id, **customer_meta_dict(updated)}

    @app.get("/shop/api/reseller-desk")
    def reseller_desk_api(user: User = Depends(current_user), db: Session = Depends(get_db)):
        return list_reseller_desk(db, user, settings)

    @app.post("/shop/api/subscriptions/{sub_id}/link-shared")
    def mark_subscription_link_shared(
        sub_id: int,
        payload: Annotated[LinkSharedBody, Body()],
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        sub = db.get(Subscription, sub_id)
        if not sub or sub.user_id != user.id:
            raise HTTPException(404, "اشتراک پیدا نشد")
        updated = set_subscription_link_shared(db, sub, bool(payload.shared))
        return {
            "ok": True,
            "id": updated.id,
            "link_shared": bool(updated.link_shared_at),
            "link_shared_at": updated.link_shared_at.isoformat() if updated.link_shared_at else None,
        }

    @app.get("/shop/api/subscriptions/{sub_id}/links")
    def sub_links(sub_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
        sub = db.get(Subscription, sub_id)
        if not sub or (sub.user_id != user.id and not is_user_admin(user, settings)):
            raise HTTPException(404, "not found")
        try:
            links = public_links_for_subscription(state.panel, sub, settings)
        except PanelError as exc:
            raise HTTPException(502, str(exc)) from exc
        return {"email": sub.xui_email, "links": links}

    @app.get("/shop/api/subscriptions/{sub_id}/detail")
    def subscription_detail(sub_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
        sub = get_user_subscription(db, user.id, sub_id)
        if not sub and not is_user_admin(user, settings):
            raise HTTPException(404, "not found")
        if not sub:
            sub = db.get(Subscription, sub_id)
        if not sub:
            raise HTTPException(404, "not found")
        if sub.user_id != user.id and not is_user_admin(user, settings):
            raise HTTPException(404, "not found")
        try:
            links = public_links_for_subscription(state.panel, sub, settings)
        except PanelError as exc:
            raise HTTPException(502, str(exc)) from exc
        if is_metered_payg(sub):
            try:
                bill_payg_subscription(db, state.panel, sub)
                db.refresh(sub)
                db.refresh(user)
            except Exception:
                logger.exception("payg detail bill failed sub=%s", sub.id)
        stats = subscription_live_stats(state.panel, sub)
        if is_metered_payg(sub):
            owner = sub.user if sub.user_id != user.id else user
            stats = apply_metered_payg_stats(db, owner, sub, stats)
        last_online_at = None
        if stats.get("last_online_at"):
            try:
                last_online_at = datetime.fromisoformat(str(stats["last_online_at"]))
            except ValueError:
                last_online_at = None
        record_usage_sample(
            db,
            sub,
            up_bytes=int(stats.get("up_bytes") or 0),
            down_bytes=int(stats.get("down_bytes") or 0),
            used_bytes=int(stats.get("used_bytes") or 0),
            online=bool(stats.get("online")),
            min_interval_sec=180,
        )
        usage = subscription_usage_analytics(
            db,
            sub,
            up_bytes=int(stats.get("up_bytes") or 0),
            down_bytes=int(stats.get("down_bytes") or 0),
            used_bytes=int(stats.get("used_bytes") or 0),
            total_bytes=int(stats.get("total_bytes") or 0),
            last_online_at=last_online_at,
        )
        db.commit()
        ip_info = client_connection_ips(state.panel, sub.xui_email)
        from app.ops import get_ip_nicknames, merge_ips_with_nicknames

        nicknames = get_ip_nicknames(db, sub.user_id)
        ip_info["connected_ips"] = merge_ips_with_nicknames(ip_info["connected_ips"], nicknames)
        ip_info["nickname_presets"] = ["موبایل", "لپ‌تاپ", "تبلت", "کامپیوتر", "مودم", "سایر"]
        cfg = subscription_config_dict(sub)
        plan = sub.plan
        ip_limit = ip_info["limit_ip"] or cfg["limit_ip"] or (plan.limit_ip if plan else 0)
        link_items = []
        for i, link in enumerate(links):
            host, port, label, link_type = parse_share_link(link)
            ping_ms = ping_tcp(host, port) if host and port else None
            link_items.append(
                {
                    "index": i,
                    "label": label or f"کانفیگ {i + 1}",
                    "link": link,
                    "kind": link_type,
                    "host": host,
                    "port": port,
                    "ping_ms": ping_ms,
                    "reachable": ping_ms is not None,
                }
            )
        sub_url = build_subscription_url(sub.xui_sub_id, settings)
        import_b64 = subscription_import_base64(links)
        from app.parental import (
            family_members,
            family_seat_dict,
            is_family_parent,
            parse_categories,
            parental_settings_dict,
        )

        detail = {
            "id": sub.id,
            "email": sub.xui_email,
            "label": sub.label,
            "plan_id": sub.plan_id,
            "plan_title": cfg["plan_title"],
            "plan_duration_days": cfg["duration_days"],
            "traffic_label": cfg["traffic_label"],
            "limit_ip": cfg["limit_ip"],
            "is_payg": bool(cfg.get("is_payg")),
            "is_metered": is_metered_payg(sub),
            **customer_meta_dict(sub),
            "up_label": format_bytes(int(stats.get("up_bytes") or 0)),
            "down_label": format_bytes(int(stats.get("down_bytes") or 0)),
            "usage": usage,
            "billed_toman": int(sub.billed_toman or 0) if is_metered_payg(sub) else 0,
            "billed_label": format_price(int(sub.billed_toman or 0)) if is_metered_payg(sub) else None,
            "created_at": sub.created_at.isoformat() if sub.created_at else None,
            "expires_at": sub.expires_at.isoformat() if sub.expires_at else None,
            **subscription_buy_meta(db, sub),
            "xui_sub_id": sub.xui_sub_id,
            "subscription_url": sub_url,
            "subscription_import": import_b64,
            "auto_renew": bool(getattr(sub, "auto_renew", False)),
            "family_group": sub.family_group,
            "family_index": sub.family_index,
            "family_role": getattr(sub, "family_role", None),
            "parental_categories": parse_categories(getattr(sub, "parental_categories", None)),
            "family": None,
            "links": link_items,
            "links_text": "\n".join(links),
            "connection": {
                "online": stats["online"],
                "connected_ip_count": ip_info["connected_ip_count"],
                "limit_ip": ip_limit,
                "connected_ips": ip_info["connected_ips"],
                "ip_available": ip_info["ip_available"],
                "nickname_presets": ip_info.get("nickname_presets") or [],
                "last_online_at": stats["last_online_at"],
                "history": [
                    *[{"at": row.get("at"), "event": "ip", "ip": row.get("ip")} for row in ip_info["connected_ips"]],
                    *(
                        [{"at": stats["last_online_at"], "event": "last_seen"}]
                        if stats["last_online_at"]
                        else []
                    ),
                ],
            },
            "abuse": {
                "flag": getattr(sub, "abuse_flag", None),
                "throttled_until": (
                    sub.abuse_throttled_until.isoformat()
                    if getattr(sub, "abuse_throttled_until", None)
                    else None
                ),
                "notes": getattr(sub, "abuse_notes", None),
                "active": bool(
                    getattr(sub, "abuse_throttled_until", None)
                    and sub.abuse_throttled_until > datetime.utcnow()
                ),
            },
            **stats,
        }
        if sub.family_group:
            try:
                online_emails = state.panel.online_emails()
            except Exception:
                online_emails = set()
            try:
                last_map = state.panel.last_online_map()
            except Exception:
                last_map = {}
            members = []
            for seat in family_members(db, sub.family_group):
                try:
                    seat_stats = subscription_live_stats(
                        state.panel,
                        seat,
                        online_emails=online_emails,
                        last_map=last_map,
                    )
                except Exception:
                    seat_stats = None
                members.append(family_seat_dict(seat, seat_stats))
            pack_used = sum(int(m.get("used_bytes") or 0) for m in members)
            detail["family"] = {
                "group": sub.family_group,
                "is_parent": is_family_parent(sub),
                "members": members,
                "used_bytes": pack_used,
                "used_label": format_bytes(pack_used),
                "parental": parental_settings_dict(db),
            }
        return detail

    @app.post("/shop/api/subscriptions/{sub_id}/auto-renew")
    def subscription_auto_renew(
        sub_id: int,
        payload: Annotated[AutoRenewBody, Body()],
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        from app.jobs import set_subscription_auto_renew as _set_auto

        sub = get_user_subscription(db, user.id, sub_id)
        if not sub:
            raise HTTPException(404, "اشتراک پیدا نشد")
        if is_metered_payg(sub) or is_payg_subscription(sub):
            raise HTTPException(400, "تمدید خودکار برای کانفیگ مصرفی در دسترس نیست")
        _set_auto(db, sub, payload.enabled)
        return {"ok": True, "auto_renew": bool(sub.auto_renew)}

    @app.post("/shop/api/subscriptions/{sub_id}/ip-nickname")
    def subscription_ip_nickname(
        sub_id: int,
        payload: Annotated[IpNicknameBody, Body()],
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        from app.ops import get_ip_nicknames, set_ip_nickname

        sub = get_user_subscription(db, user.id, sub_id)
        if not sub and not is_user_admin(user, settings):
            raise HTTPException(404, "اشتراک پیدا نشد")
        if not sub:
            sub = db.get(Subscription, sub_id)
        if not sub or (sub.user_id != user.id and not is_user_admin(user, settings)):
            raise HTTPException(404, "اشتراک پیدا نشد")
        owner_id = sub.user_id
        try:
            nicknames = set_ip_nickname(db, owner_id, payload.ip, payload.nickname)
        except ValueError as exc:
            raise HTTPException(400, "IP نامعتبر است") from exc
        return {
            "ok": True,
            "ip": payload.ip.strip(),
            "nickname": nicknames.get(payload.ip.strip()) or None,
            "nicknames": nicknames,
        }

    @app.post("/shop/api/subscriptions/{sub_id}/family/{child_id}/restrict")
    def family_restrict_child(
        sub_id: int,
        child_id: int,
        payload: Annotated[ParentalRestrictBody, Body()],
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        from app.parental import (
            family_seat_dict,
            maybe_sync_parental_routing,
            set_child_restrictions,
            sync_vpn_allow_schedules,
        )

        parent = get_user_subscription(db, user.id, sub_id)
        if not parent:
            raise HTTPException(404, "اشتراک پیدا نشد")
        try:
            child = set_child_restrictions(
                db,
                parent_sub=parent,
                child_sub_id=child_id,
                categories=payload.categories,
                schedule=payload.schedule,
                vpn_schedule=payload.vpn_schedule,
            )
        except ValueError as exc:
            messages = {
                "parental_disabled": "محدودیت والدین غیرفعال است",
                "not_family": "این کانفیگ پکیج خانواده نیست",
                "not_parent": "فقط والد می‌تواند محدودیت بگذارد",
                "child_not_found": "کانفیگ فرزند پیدا نشد",
                "cannot_restrict_parent": "نمی‌توان روی کانفیگ والد محدودیت گذاشت",
            }
            raise HTTPException(400, messages.get(str(exc), str(exc))) from exc
        sync = maybe_sync_parental_routing(db, state.panel)
        vpn_sync = sync_vpn_allow_schedules(db, state.panel)
        return {"ok": True, "child": family_seat_dict(child), "sync": sync, "vpn_sync": vpn_sync}

    def _family_parental_error(exc: Exception) -> HTTPException:
        messages = {
            "parental_disabled": "محدودیت والدین غیرفعال است",
            "not_family": "این کانفیگ پکیج خانواده نیست",
            "not_parent": "فقط والد می‌تواند محدودیت بگذارد",
            "child_not_found": "کانفیگ فرزند پیدا نشد",
            "cannot_restrict_parent": "نمی‌توان روی کانفیگ والد محدودیت گذاشت",
            "bad_pause_hours": "مدت توقف باید بین ۱ تا ۳۳۶ ساعت باشد",
            "pause_in_past": "زمان پایان توقف نامعتبر است",
        }
        return HTTPException(400, messages.get(str(exc), str(exc)))

    @app.post("/shop/api/subscriptions/{sub_id}/family/{child_id}/pause")
    def family_pause_child(
        sub_id: int,
        child_id: int,
        payload: Annotated[ParentalPauseBody, Body()],
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        from app.parental import family_seat_dict, set_child_pause_day, sync_vpn_allow_schedules

        parent = get_user_subscription(db, user.id, sub_id)
        if not parent:
            raise HTTPException(404, "اشتراک پیدا نشد")
        try:
            child = set_child_pause_day(
                db, parent_sub=parent, child_sub_id=child_id, hours=payload.hours
            )
        except ValueError as exc:
            raise _family_parental_error(exc) from exc
        vpn_sync = sync_vpn_allow_schedules(db, state.panel)
        return {"ok": True, "child": family_seat_dict(child), "vpn_sync": vpn_sync}

    @app.post("/shop/api/subscriptions/{sub_id}/family/{child_id}/resume")
    def family_resume_child(
        sub_id: int,
        child_id: int,
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        from app.parental import clear_child_pause_day, family_seat_dict, sync_vpn_allow_schedules

        parent = get_user_subscription(db, user.id, sub_id)
        if not parent:
            raise HTTPException(404, "اشتراک پیدا نشد")
        try:
            child = clear_child_pause_day(db, parent_sub=parent, child_sub_id=child_id)
        except ValueError as exc:
            raise _family_parental_error(exc) from exc
        vpn_sync = sync_vpn_allow_schedules(db, state.panel)
        return {"ok": True, "child": family_seat_dict(child), "vpn_sync": vpn_sync}

    @app.get("/shop/api/subscriptions/{sub_id}/family/{child_id}/activity")
    def family_child_activity(
        sub_id: int,
        child_id: int,
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
        limit: int = 80,
    ):
        from app.parental import (
            family_members,
            ingest_family_browse_logs,
            is_family_parent,
            list_child_activity,
        )

        parent = get_user_subscription(db, user.id, sub_id)
        if not parent or not parent.family_group:
            raise HTTPException(404, "کانفیگ خانواده پیدا نشد")
        if not is_family_parent(parent):
            raise HTTPException(403, "فقط والد خانواده می‌تواند گزارش فرزند را ببیند")
        child = next((m for m in family_members(db, parent.family_group) if m.id == child_id), None)
        if not child or child.user_id != parent.user_id or is_family_parent(child):
            raise HTTPException(404, "کانفیگ فرزند پیدا نشد")
        try:
            ingest_family_browse_logs(db, state.panel)
        except Exception:
            logger.exception("family activity ingest failed")
        return list_child_activity(db, child, limit=limit)

    @app.get("/shop/api/parental/options")
    def parental_options(user: User = Depends(current_user), db: Session = Depends(get_db)):
        from app.parental import parental_settings_dict

        return parental_settings_dict(db)

    @app.get("/shop/api/admin/parental-settings")
    def admin_parental_get(admin: User = Depends(require_admin), db: Session = Depends(get_db)):
        from app.parental import parental_settings_dict

        return parental_settings_dict(db)

    @app.post("/shop/api/admin/parental-settings")
    def admin_parental_set(
        body: Annotated[ParentalSettingsBody, Body()],
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        from app.parental import sync_parental_routing, update_parental_settings

        data = update_parental_settings(
            db,
            enabled=body.enabled,
            custom_domains_list=body.custom_domains,
        )
        sync = sync_parental_routing(db, state.panel)
        data["sync"] = sync
        return data

    @app.post("/shop/api/subscriptions/{sub_id}/renew")
    def renew_subscription(
        sub_id: int,
        payload: Annotated[RenewSubscriptionBody, Body()],
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        sub = get_user_subscription(db, user.id, sub_id)
        if not sub:
            raise HTTPException(404, "اشتراک پیدا نشد")
        plan_id = payload.plan_id or sub.plan_id
        plan = get_plan(db, plan_id)
        if not plan or not plan.enabled:
            raise HTTPException(404, "پلن پیدا نشد")
        db.refresh(user)
        pending = user_pending_order(db, user.id)
        if pending:
            return finalize_shop_order(
                db, user, pending, resumed=True, renew=bool(pending.target_subscription_id)
            )
        try:
            order = create_renew_order(db, user, sub, plan)
        except PendingOrderError as exc:
            raise HTTPException(400, "سفارش ناتمام دارید") from exc
        except ValueError as exc:
            from app.growth import promo_error_fa

            code = str(exc)
            if code in ("plan_unavailable", "plan_pro_only"):
                raise HTTPException(400, promo_error_fa(code)) from exc
            raise HTTPException(400, code) from exc
        return finalize_shop_order(db, user, order, renew=True, target_subscription_id=sub.id)

    @app.post("/shop/api/subscriptions/{sub_id}/revoke")
    def revoke_subscription_api(sub_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
        sub = get_user_subscription(db, user.id, sub_id)
        if not sub:
            raise HTTPException(404, "اشتراک پیدا نشد")
        try:
            revoke_subscription(db, state.panel, sub)
        except PanelError as exc:
            raise HTTPException(502, str(exc)) from exc
        return {"ok": True, "enabled": False}

    @app.post("/shop/api/subscriptions/{sub_id}/diagnose")
    def diagnose_subscription_api(sub_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
        sub = get_user_subscription(db, user.id, sub_id)
        if not sub:
            raise HTTPException(404, "اشتراک پیدا نشد")
        try:
            return diagnose_subscription(db, state.panel, settings, sub)
        except PanelError as exc:
            raise HTTPException(502, str(exc)) from exc

    @app.post("/shop/api/subscriptions/{sub_id}/rotate-link")
    def rotate_subscription_link_api(sub_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
        sub = get_user_subscription(db, user.id, sub_id)
        if not sub:
            raise HTTPException(404, "اشتراک پیدا نشد")
        try:
            return rotate_subscription_link(db, state.panel, sub, settings)
        except PanelError as exc:
            raise HTTPException(502, str(exc)) from exc

    @app.get("/shop/api/transfer/lookup")
    def lookup_transfer_target(
        q: str = Query(min_length=1, max_length=64),
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        from app.ops import resolve_shop_user, shop_user_public_dict

        target = resolve_shop_user(db, q)
        if not target:
            raise HTTPException(404, "کاربر مقصد پیدا نشد — باید حداقل یک‌بار فروشگاه را باز کرده باشد")
        if target.id == user.id:
            raise HTTPException(400, "نمی‌توانی به حساب خودت منتقل کنی")
        return {"ok": True, "user": shop_user_public_dict(target)}

    @app.post("/shop/api/subscriptions/{sub_id}/transfer")
    def transfer_subscription_api(
        sub_id: int,
        body: Annotated[TransferSubscriptionBody, Body()],
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        from app.ops import resolve_shop_user, shop_user_public_dict, user_transfer_subscription
        from app.services import _notify_telegram as notify_tg

        sub = get_user_subscription(db, user.id, sub_id)
        if not sub:
            raise HTTPException(404, "اشتراک پیدا نشد")
        target = resolve_shop_user(db, body.target)
        if not target:
            raise HTTPException(404, "کاربر مقصد پیدا نشد — باید حداقل یک‌بار فروشگاه را باز کرده باشد")
        try:
            result = user_transfer_subscription(
                db,
                sub=sub,
                target=target,
                actor=user,
                panel=state.panel,
            )
        except ValueError as exc:
            messages = {
                "same_user": "کانفیگ همین الان مال این کاربر است",
                "not_owner": "فقط مالک کانفیگ می‌تواند آن را منتقل کند",
            }
            raise HTTPException(400, messages.get(str(exc), str(exc))) from exc
        label = (sub.label or "").strip() or sub.xui_email
        source = result.get("source")
        if body.notify:
            if source and source.telegram_id:
                extra = " به‌همراه پکیج خانواده" if result.get("family_moved") else ""
                notify_tg(settings, source.telegram_id, f"↩️ کانفیگ «{label}»{extra} به حساب دیگری منتقل شد.")
            if target.telegram_id:
                extra = f"\nتعداد کانفیگ: {result.get('moved_count')}" if result.get("family_moved") else ""
                notify_tg(
                    settings,
                    target.telegram_id,
                    f"✅ کانفیگ «{label}» به حساب شما منتقل شد.{extra}\nشناسه: {sub.xui_email}",
                )
        return {
            "ok": True,
            "subscription_id": sub.id,
            "moved_ids": result["moved_ids"],
            "moved_count": result["moved_count"],
            "family_moved": result["family_moved"],
            "email": sub.xui_email,
            "target": shop_user_public_dict(target),
        }

    @app.post("/shop/api/subscriptions/{sub_id}/hide")
    def hide_subscription_api(sub_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
        sub = get_user_subscription(db, user.id, sub_id)
        if not sub:
            raise HTTPException(404, "اشتراک پیدا نشد")
        try:
            hide_subscription_from_dashboard(db, sub)
        except ValueError as exc:
            if str(exc) == "only_expired":
                raise HTTPException(400, "فقط کانفیگ منقضی را می‌توان از لیست حذف کرد") from exc
            raise HTTPException(400, str(exc)) from exc
        return {"ok": True, "hidden": True}

    @app.post("/shop/api/subscriptions/{sub_id}/unhide")
    def unhide_subscription_api(sub_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
        sub = get_user_subscription(db, user.id, sub_id)
        if not sub:
            raise HTTPException(404, "اشتراک پیدا نشد")
        unhide_subscription_from_dashboard(db, sub)
        return {"ok": True, "hidden": False}

    @app.get("/shop/api/referral")
    def referral(user: User = Depends(current_user), db: Session = Depends(get_db)):
        stats = referral_stats(db, user)
        bot_username = get_setting(db, "bot_username", "")
        if not bot_username:
            try:
                r = httpx.get(f"https://api.telegram.org/bot{settings.primary_bot_token}/getMe", timeout=15)
                bot_username = (r.json().get("result") or {}).get("username") or "bot"
                set_setting(db, "bot_username", bot_username)
            except Exception:  # noqa: BLE001
                bot_username = "bot"
        stats["invite_link"] = f"https://t.me/{bot_username}?start=ref_{stats['code']}"
        stats["invite_miniapp"] = f"https://t.me/{bot_username}/shop?startapp=ref_{stats['code']}"
        stats["earned_label"] = format_price(stats["earned_total"])
        stats["wallet_label"] = format_price(stats["wallet"])
        stats["min_withdraw_label"] = format_price(stats["min_withdraw"])
        stats["invitees"] = list_referral_invitees(db, user)
        board = referral_leaderboard(db, limit=10)
        for row in board:
            row["is_self"] = int(row.get("referrer_id") or 0) == user.id
            row.pop("referrer_id", None)
        stats["leaderboard"] = board
        stats["withdrawals"] = list_user_withdrawals(db, user)
        return stats

    @app.post("/shop/api/withdraw")
    def withdraw(
        payload: Annotated[WithdrawBody, Body()],
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        db.refresh(user)
        amount = payload.amount if payload.amount is not None else wallet_withdrawable(user)
        card = payload.card_number.replace(" ", "").replace("-", "")
        if not card.isdigit():
            raise HTTPException(400, "invalid card")
        wd = create_withdrawal(db, user, amount, card)
        if not wd:
            raise HTTPException(400, "cannot withdraw")
        text = (
            f"💸 برداشت #{wd.id} (مینی‌اپ)\n"
            f"کاربر: {user.full_name or '—'} ({user.telegram_id})\n"
            f"مبلغ: {format_price(wd.amount_toman)}\n"
            f"کارت: {wd.card_number}"
        )
        keyboard = {
            "inline_keyboard": [[
                {"text": "✅ پرداخت شد", "callback_data": f"adm:wdok:{wd.id}"},
                {"text": "❌ رد", "callback_data": f"adm:wdno:{wd.id}"},
            ]]
        }
        with httpx.Client(timeout=30) as client:
            for admin_id in settings.admin_ids:
                _tg_post("sendMessage", json_body={"chat_id": admin_id, "text": text, "reply_markup": keyboard})
        return {"ok": True, "id": wd.id, "amount_toman": wd.amount_toman}

    @app.get("/shop/api/admin/pending-orders")
    def admin_pending(
        include_test: bool = False,
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        orders = list_pending_orders(db, include_test=include_test)
        for o in list(orders):
            if is_prepaid_shop_order(o):
                maybe_auto_fulfill_prepaid_order(db, state.panel, settings, o)
        orders = list_pending_orders(db, include_test=include_test)
        return [
            {
                "id": o.id,
                "user": o.user.full_name,
                "telegram_id": o.user.telegram_id,
                "plan": o.plan.title,
                "amount_toman": o.amount_toman,
                "amount_label": format_price(o.amount_toman),
                "wallet_used": o.wallet_used or 0,
                "has_receipt": bool(o.receipt_file_id),
                "is_wallet_topup": is_wallet_topup(o.plan),
                "is_platform_pro": is_platform_pro(o.plan),
                "promo_code": o.promo_code,
                "discount_toman": int(o.discount_toman or 0),
                "bonus_days": int(o.bonus_days or 0),
                "family_size": int(o.family_size or 1),
                "is_test": bool(getattr(o.user, "is_test", False)),
            }
            for o in orders
        ]

    @app.get("/shop/api/wallet")
    def wallet_info(user: User = Depends(current_user), db: Session = Depends(get_db)):
        pending = user_pending_order(db, user.id)
        pending_topup = pending if pending and is_wallet_topup(pending.plan) else None
        view = wallet_view(user)
        min_withdraw = min_withdraw_amount(db)
        pending_wd = db.scalar(
            select(Withdrawal)
            .where(
                Withdrawal.user_id == user.id,
                Withdrawal.status == WithdrawStatus.PENDING,
            )
            .order_by(Withdrawal.id.desc())
        )
        return {
            "balance": view["balance"],
            "balance_label": format_price(view["balance"]),
            "locked": view["locked"],
            "locked_label": format_price(view["locked"]) if view["locked"] else None,
            "withdrawable": view["withdrawable"],
            "withdrawable_label": format_price(view["withdrawable"]),
            "credit_limit": view["credit_limit"],
            "credit_limit_label": format_price(view["credit_limit"]) if view["credit_limit"] else None,
            "debt": view["debt"],
            "debt_label": format_price(view["debt"]) if view["debt"] else None,
            "spendable": view["spendable"],
            "spendable_label": format_price(view["spendable"]),
            "credit_remaining": view["credit_remaining"],
            "credit_remaining_label": format_price(view["credit_remaining"]) if view["credit_limit"] else None,
            "min_deposit": MIN_WALLET_DEPOSIT,
            "min_deposit_label": format_price(MIN_WALLET_DEPOSIT),
            "max_deposit": MAX_WALLET_DEPOSIT,
            "max_deposit_label": format_price(MAX_WALLET_DEPOSIT),
            "min_withdraw": min_withdraw,
            "min_withdraw_label": format_price(min_withdraw),
            "min_transfer": MIN_WALLET_TRANSFER,
            "min_transfer_label": format_price(MIN_WALLET_TRANSFER),
            "presets": [50_000, 100_000, 200_000, 500_000, 1_000_000],
            "transfers": list_user_wallet_transfers(db, user),
            "payment": payment_info(db, settings),
            "pending_deposit": (
                {
                    "id": pending_topup.id,
                    "amount_toman": pending_topup.amount_toman,
                    "amount_label": format_price(pending_topup.amount_toman),
                    "has_receipt": bool(pending_topup.receipt_file_id),
                }
                if pending_topup
                else None
            ),
            "pending_withdrawal": (
                {
                    "id": pending_wd.id,
                    "amount_toman": pending_wd.amount_toman,
                    "amount_label": format_price(pending_wd.amount_toman),
                    "card_number": pending_wd.card_number,
                }
                if pending_wd
                else None
            ),
            "withdrawals": list_user_withdrawals(db, user),
        }

    @app.post("/shop/api/wallet/deposit")
    def wallet_deposit(
        payload: Annotated[WalletDepositBody, Body()],
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        db.refresh(user)
        pending = user_pending_order(db, user.id)
        if pending:
            if is_wallet_topup(pending.plan):
                return {
                    "id": pending.id,
                    "amount_toman": pending.amount_toman,
                    "amount_label": format_price(pending.amount_toman),
                    "wallet_used": 0,
                    "needs_receipt": True,
                    "wallet_balance": user.wallet_balance or 0,
                    "resumed": True,
                    "payment": payment_info(db, settings),
                }
            raise HTTPException(400, "سفارش ناتمام دارید — ابتدا آن را تکمیل یا لغو کنید")
        try:
            order = create_wallet_deposit(db, user, payload.amount_toman)
        except PendingOrderError as exc:
            raise HTTPException(400, "سفارش ناتمام دارید") from exc
        except ValueError as exc:
            msg = str(exc)
            if msg == "amount_too_low":
                raise HTTPException(400, f"حداقل شارژ {format_price(MIN_WALLET_DEPOSIT)} است") from exc
            if msg == "amount_too_high":
                raise HTTPException(400, f"حداکثر شارژ {format_price(MAX_WALLET_DEPOSIT)} است") from exc
            raise HTTPException(400, "مبلغ نامعتبر است") from exc
        db.refresh(user)
        return {
            "id": order.id,
            "amount_toman": order.amount_toman,
            "amount_label": format_price(order.amount_toman),
            "wallet_used": 0,
            "needs_receipt": True,
            "wallet_balance": user.wallet_balance or 0,
            "resumed": False,
            "payment": payment_info(db, settings),
        }

    @app.post("/shop/api/wallet/transfer")
    def wallet_transfer(
        payload: Annotated[WalletTransferBody, Body()],
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        from app.ops import resolve_shop_user, shop_user_public_dict
        from app.services import _notify_telegram as notify_tg

        db.refresh(user)
        target = resolve_shop_user(db, payload.target)
        if not target:
            raise HTTPException(404, "کاربر مقصد پیدا نشد — باید حداقل یک‌بار فروشگاه را باز کرده باشد")
        try:
            row = transfer_wallet_balance(
                db,
                source=user,
                target=target,
                amount_toman=payload.amount_toman,
                panel=state.panel,
                settings=settings,
            )
        except ValueError as exc:
            messages = {
                "same_user": "نمی‌توانی به کیف‌پول خودت منتقل کنی",
                "amount_too_low": f"حداقل انتقال {format_price(MIN_WALLET_TRANSFER)} است",
                "amount_too_high": f"حداکثر انتقال {format_price(MAX_WALLET_DEPOSIT)} است",
                "insufficient_wallet": "موجودی کیف‌پول کافی نیست",
            }
            raise HTTPException(400, messages.get(str(exc), str(exc))) from exc
        db.refresh(user)
        db.refresh(target)
        sender_name = user.full_name or (f"@{user.username}" if user.username else str(user.telegram_id))
        try:
            notify_tg(
                settings,
                target.telegram_id,
                (
                    f"💸 {format_price(row.amount_toman)} به کیف‌پول شما منتقل شد.\n"
                    f"از طرف: {sender_name}\n"
                    f"موجودی فعلی: {format_price(target.wallet_balance or 0)}"
                ),
            )
        except Exception:
            logger.exception("wallet transfer notify failed")
        return {
            "ok": True,
            "id": row.id,
            "amount_toman": row.amount_toman,
            "amount_label": format_price(row.amount_toman),
            "wallet_balance": user.wallet_balance or 0,
            "wallet_label": format_price(user.wallet_balance or 0),
            "target": shop_user_public_dict(target),
        }

    @app.post("/shop/api/admin/orders/{order_id}/approve")
    def admin_approve_order(order_id: int, admin: User = Depends(require_admin), db: Session = Depends(get_db)):
        order = get_order(db, order_id)
        if not order or order.status != OrderStatus.PENDING:
            raise HTTPException(400, "not pending")
        try:
            return fulfill_pending_order(
                db,
                state.panel,
                settings,
                order,
                actor=admin,
                via="admin",
                notify_user=True,
                notify_admins=False,
            )
        except PanelError as exc:
            raise HTTPException(502, str(exc)) from exc
        except ValueError as exc:
            code = str(exc)
            if code == "renew_target_invalid":
                raise HTTPException(400, "renew target invalid") from exc
            raise HTTPException(400, code) from exc

    @app.post("/shop/api/admin/orders/{order_id}/reject")
    def admin_reject_order(order_id: int, admin: User = Depends(require_admin), db: Session = Depends(get_db)):
        order = get_order(db, order_id)
        if not order or order.status != OrderStatus.PENDING:
            raise HTTPException(400, "not pending")
        tg_id = order.user.telegram_id
        reject_order(db, order, note="rejected_via_miniapp")
        _tg_post("sendMessage", json_body={"chat_id": tg_id, "text": f"سفارش #{order_id} رد شد."})
        return {"ok": True}

    @app.post("/shop/api/admin/orders/{order_id}/receipt")
    async def admin_upload_receipt(
        order_id: int,
        file: UploadFile = File(...),
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        order = get_order(db, order_id)
        if not order:
            raise HTTPException(404, "order not found")
        if order.status != OrderStatus.PENDING:
            raise HTTPException(400, "order not pending")
        data = await file.read()
        if not data:
            raise HTTPException(400, "empty file")
        if len(data) > 8 * 1024 * 1024:
            raise HTTPException(400, "file too large")
        try:
            save_receipt_local(order.id, data, file.filename, file.content_type)
        except Exception:
            logger.exception("Failed saving receipt locally for order %s", order.id)
        order.receipt_file_id = order.receipt_file_id or "admin-uploaded"
        db.commit()
        return {"ok": True, "has_receipt": True}

    @app.get("/shop/api/orders/history")
    def user_orders_history(
        status: str = "",
        limit: int = 40,
        offset: int = 0,
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        items, total = list_orders_history(
            db,
            user_id=user.id,
            status=status or None,
            limit=limit,
            offset=offset,
        )
        return {"items": items, "total": total}

    @app.get("/shop/api/admin/orders/history")
    def admin_orders_history(
        q: str = "",
        status: str = "",
        user_id: int | None = None,
        limit: int = 40,
        offset: int = 0,
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        items, total = list_orders_history(
            db,
            user_id=user_id,
            status=status or None,
            q=q,
            limit=limit,
            offset=offset,
            include_user=True,
        )
        return {"items": items, "total": total}

    @app.get("/shop/api/admin/withdrawals")
    def admin_wd_list(
        include_test: bool = False,
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        items = list_pending_withdrawals(db, include_test=include_test)
        return [
            {
                "id": w.id,
                "user": w.user.full_name,
                "telegram_id": w.user.telegram_id,
                "amount_toman": w.amount_toman,
                "amount_label": format_price(w.amount_toman),
                "card_number": w.card_number,
                "is_test": bool(getattr(w.user, "is_test", False)),
            }
            for w in items
        ]

    @app.post("/shop/api/admin/withdrawals/{wd_id}/pay")
    def admin_wd_pay(wd_id: int, admin: User = Depends(require_admin), db: Session = Depends(get_db)):
        wd = db.get(Withdrawal, wd_id)
        if not wd or wd.status != "pending":
            raise HTTPException(400, "not pending")
        approve_withdrawal(db, wd)
        _tg_post("sendMessage", json_body={"chat_id": wd.user.telegram_id, "text": f"✅ مبلغ {format_price(wd.amount_toman)} واریز شد."})
        return {"ok": True}

    @app.post("/shop/api/admin/withdrawals/{wd_id}/reject")
    def admin_wd_reject(wd_id: int, admin: User = Depends(require_admin), db: Session = Depends(get_db)):
        wd = db.get(Withdrawal, wd_id)
        if not wd or wd.status != "pending":
            raise HTTPException(400, "not pending")
        amount = wd.amount_toman
        tg_id = wd.user.telegram_id
        reject_withdrawal(db, wd, note="rejected_via_miniapp")
        _tg_post("sendMessage", json_body={"chat_id": tg_id, "text": f"برداشت رد شد. {format_price(amount)} به کیف‌پول برگشت."})
        return {"ok": True}

    def _notify_admins_new_chat(name: str, preview: str, *, assignee_tg: int | None = None) -> None:
        body = f"💬 پیام جدید از {name}:\n{preview}"
        targets: list[int] = []
        if assignee_tg:
            targets = [assignee_tg]
        else:
            try:
                with state.session_factory() as s:
                    duty_rows = list(
                        s.scalars(
                            select(User).where(User.role == USER_ROLE_ADMIN, User.on_duty.is_(True))
                        ).all()
                    )
                    if duty_rows:
                        targets = [int(u.telegram_id) for u in duty_rows if u.telegram_id]
            except Exception:
                logger.exception("duty admin lookup failed")
            if not targets:
                targets = list(settings.admin_ids)
        for admin_id in targets:
            _notify_telegram(admin_id, body)

    def _chat_messages_payload(db: Session, user_id: int, after_id: int) -> dict:
        items = list_user_chat_messages(db, user_id, after_id=after_id)
        return {
            "messages": [chat_message_dict(m) for m in items],
            "unread_count": user_chat_unread_count(db, user_id),
            "latest_id": latest_chat_message_id(db, user_id),
        }

    @app.get("/shop/api/chat/messages")
    def chat_messages(
        after_id: int = 0,
        mark_read: bool = False,
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        if mark_read:
            mark_chat_read(db, user.id, "user")
        return _chat_messages_payload(db, user.id, after_id)

    @app.post("/shop/api/chat/read")
    def chat_mark_read(user: User = Depends(current_user), db: Session = Depends(get_db)):
        marked = mark_chat_read(db, user.id, "user")
        return {"ok": True, "marked": marked, "unread_count": user_chat_unread_count(db, user.id)}

    @app.post("/shop/api/chat/messages")
    def chat_send(
        payload: Annotated[ChatMessageBody, Body()],
        background_tasks: BackgroundTasks,
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        try:
            attachments = resolve_chat_attachments(
                db,
                user.id,
                [a.model_dump() for a in payload.attachments],
                state.panel,
                settings,
            )
            msg = send_chat_message(
                db,
                user_id=user.id,
                sender="user",
                body=payload.body,
                sender_telegram_id=user.telegram_id,
                attachments=attachments,
            )
        except ValueError as exc:
            raise HTTPException(400, str(exc)) from exc
        preview = chat_preview_text(payload.body, attachments)
        if len(preview) > 120:
            preview = preview[:117] + "…"
        name = user.full_name or user.username or str(user.telegram_id)
        assignee_tg = None
        try:
            from app.services import get_chat_assignee

            assignee = get_chat_assignee(db, user.id)
            if assignee and assignee.telegram_id:
                assignee_tg = int(assignee.telegram_id)
        except Exception:
            logger.exception("chat assignee lookup failed")
        background_tasks.add_task(_notify_admins_new_chat, name, preview, assignee_tg=assignee_tg)
        return {"ok": True, "message": chat_message_dict(msg)}

    @app.get("/shop/api/chat/unread")
    def chat_unread(user: User = Depends(current_user), db: Session = Depends(get_db)):
        return {"unread_count": user_chat_unread_count(db, user.id)}

    @app.get("/shop/api/chat/orders")
    def chat_orders(user: User = Depends(current_user), db: Session = Depends(get_db)):
        orders = list_user_orders_for_chat(db, user.id)
        return {"items": [order_chat_dict(o) for o in orders]}

    @app.get("/shop/api/admin/chat/threads")
    def admin_chat_threads(admin: User = Depends(require_admin), db: Session = Depends(get_db)):
        return {
            "threads": list_chat_threads(db),
            "unread_total": admin_chat_unread_total(db),
            "on_duty": bool(getattr(admin, "on_duty", False)),
            "duty_count": db.scalar(
                select(func.count()).select_from(User).where(User.role == USER_ROLE_ADMIN, User.on_duty.is_(True))
            )
            or 0,
        }

    @app.post("/shop/api/admin/duty")
    def admin_set_duty(
        payload: Annotated[AdminDutyBody, Body()],
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        admin.on_duty = bool(payload.on_duty)
        db.commit()
        db.refresh(admin)
        duty_count = (
            db.scalar(
                select(func.count()).select_from(User).where(User.role == USER_ROLE_ADMIN, User.on_duty.is_(True))
            )
            or 0
        )
        return {"ok": True, "on_duty": bool(admin.on_duty), "duty_count": int(duty_count)}

    @app.post("/shop/api/admin/chat/threads/{user_id}/claim")
    def admin_claim_chat(
        user_id: int,
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        from app.services import claim_chat_thread

        target = db.get(User, user_id)
        if not target:
            raise HTTPException(404, "کاربر پیدا نشد")
        claim_chat_thread(db, user_id, admin.id)
        return {
            "ok": True,
            "user_id": user_id,
            "assigned_admin_id": admin.id,
            "assigned_name": admin.full_name or admin.username or str(admin.telegram_id),
        }

    @app.post("/shop/api/admin/chat/threads/{user_id}/release")
    def admin_release_chat(
        user_id: int,
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        from app.services import release_chat_thread

        target = db.get(User, user_id)
        if not target:
            raise HTTPException(404, "کاربر پیدا نشد")
        release_chat_thread(db, user_id, admin_id=admin.id)
        return {"ok": True, "user_id": user_id, "assigned_admin_id": None}

    @app.get("/shop/api/admin/chat/threads/{user_id}/messages")
    def admin_chat_messages(
        user_id: int,
        after_id: int = 0,
        mark_read: bool = False,
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        target = db.get(User, user_id)
        if not target:
            raise HTTPException(404, "کاربر پیدا نشد")
        if mark_read:
            mark_chat_read(db, user_id, "admin")
        payload = _chat_messages_payload(db, user_id, after_id)
        return {
            "user": {
                "id": target.id,
                "telegram_id": target.telegram_id,
                "username": target.username,
                "full_name": target.full_name,
            },
            "messages": payload["messages"],
            "unread_count": payload["unread_count"],
            "latest_id": payload["latest_id"],
            "unread_total": admin_chat_unread_total(db),
        }

    @app.post("/shop/api/admin/chat/threads/{user_id}/read")
    def admin_chat_mark_read(
        user_id: int,
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        if not db.get(User, user_id):
            raise HTTPException(404, "کاربر پیدا نشد")
        marked = mark_chat_read(db, user_id, "admin")
        return {
            "ok": True,
            "marked": marked,
            "unread_total": admin_chat_unread_total(db),
        }

    @app.get("/shop/api/admin/chat/threads/{user_id}/subscriptions")
    def admin_thread_subscriptions(
        user_id: int,
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        if not db.get(User, user_id):
            raise HTTPException(404, "کاربر پیدا نشد")
        subs = user_all_subscriptions(db, user_id)
        now = datetime.utcnow()
        items = []
        for s in subs:
            active = s.enabled and (s.expires_at is None or s.expires_at > now)
            items.append(
                {
                    "id": s.id,
                    "email": s.xui_email,
                    "plan_title": s.plan.title if s.plan else "—",
                    "label": s.label,
                    "expires_at": s.expires_at.isoformat() if s.expires_at else None,
                    "traffic_label": traffic_label(s.plan.traffic_gb) if s.plan else "—",
                    "status": "active" if active else ("expired" if s.expires_at and s.expires_at <= now else "disabled"),
                }
            )
        return {"items": items}

    @app.get("/shop/api/admin/chat/threads/{user_id}/orders")
    def admin_thread_orders(
        user_id: int,
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        if not db.get(User, user_id):
            raise HTTPException(404, "کاربر پیدا نشد")
        orders = list_user_orders_for_chat(db, user_id)
        return {"items": [order_chat_dict(o) for o in orders]}

    @app.post("/shop/api/admin/chat/threads/{user_id}/messages")
    def admin_chat_send(
        user_id: int,
        payload: Annotated[ChatMessageBody, Body()],
        background_tasks: BackgroundTasks,
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        target = db.get(User, user_id)
        if not target:
            raise HTTPException(404, "کاربر پیدا نشد")
        try:
            attachments = resolve_chat_attachments(
                db,
                user_id,
                [a.model_dump() for a in payload.attachments],
                state.panel,
                settings,
            )
            msg = send_chat_message(
                db,
                user_id=user_id,
                sender="admin",
                body=payload.body,
                sender_telegram_id=admin.telegram_id,
                attachments=attachments,
            )
        except ValueError as exc:
            raise HTTPException(400, str(exc)) from exc
        preview = chat_preview_text(payload.body, attachments)
        if len(preview) > 120:
            preview = preview[:117] + "…"
        text = f"💬 پاسخ پشتیبانی:\n{preview}\n\nبرای ادامه گفتگو مینی‌اپ را باز کنید."
        background_tasks.add_task(_notify_telegram, target.telegram_id, text)
        return {"ok": True, "message": chat_message_dict(msg)}

    @app.post("/shop/api/admin/broadcast")
    def admin_broadcast(
        payload: Annotated[BroadcastBody, Body()],
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        ids = list(db.scalars(select(User.telegram_id)).all())
        sent = 0
        with httpx.Client(timeout=30) as client:
            for tid in ids:
                try:
                    r = _tg_post("sendMessage", json_body={"chat_id": tid, "text": payload.message})
                    if r.status_code == 200:
                        sent += 1
                except Exception:  # noqa: BLE001
                    continue
        return {"ok": True, "sent": sent, "total": len(ids)}

    @app.get("/shop/api/admin/payment-cards")
    def admin_payment_cards(admin: User = Depends(require_admin), db: Session = Depends(get_db)):
        return list_payment_cards(db, settings)

    @app.post("/shop/api/admin/payment-cards")
    def admin_add_payment_card(
        payload: Annotated[PaymentCardBody, Body()],
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        card = add_payment_card(
            db,
            settings,
            card=payload.card,
            name=payload.name,
            note=payload.note,
            label=payload.label,
        )
        return {"ok": True, "card": card, "cards": list_payment_cards(db, settings)}

    @app.delete("/shop/api/admin/payment-cards/{card_id}")
    def admin_delete_payment_card(
        card_id: int,
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        if not remove_payment_card(db, settings, card_id):
            raise HTTPException(404, "کارت پیدا نشد")
        return {"ok": True, "cards": list_payment_cards(db, settings)}

    @app.get("/shop/api/admin/birthday-gift")
    def admin_birthday_gift_get(admin: User = Depends(require_admin), db: Session = Depends(get_db)):
        return birthday_gift_settings_dict(db)

    @app.post("/shop/api/admin/birthday-gift")
    def admin_birthday_gift_set(
        body: BirthdayGiftSettingBody,
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        from app.services import BIRTHDAY_GIFT_ENABLED_SETTING, BIRTHDAY_GIFT_SETTING

        set_setting(db, BIRTHDAY_GIFT_SETTING, str(body.amount_toman))
        set_setting(db, BIRTHDAY_GIFT_ENABLED_SETTING, "1" if body.enabled else "0")
        data = birthday_gift_settings_dict(db)
        data["ok"] = True
        return data

    @app.get("/shop/api/admin/trial-settings")
    def admin_trial_settings_get(admin: User = Depends(require_admin), db: Session = Depends(get_db)):
        return trial_settings_dict(db)

    @app.post("/shop/api/admin/trial-settings")
    def admin_trial_settings_set(
        body: TrialSettingsBody,
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        from app.services import (
            TRIAL_DURATION_DAYS_SETTING,
            TRIAL_ENABLED_SETTING,
            TRIAL_LIMIT_IP_SETTING,
            TRIAL_SEND_LINKS_SETTING,
            TRIAL_TRAFFIC_GB_SETTING,
        )

        set_setting(db, TRIAL_ENABLED_SETTING, "1" if body.enabled else "0")
        set_setting(db, TRIAL_DURATION_DAYS_SETTING, str(body.duration_days))
        set_setting(db, TRIAL_TRAFFIC_GB_SETTING, str(body.traffic_gb))
        set_setting(db, TRIAL_LIMIT_IP_SETTING, str(body.limit_ip))
        set_setting(db, TRIAL_SEND_LINKS_SETTING, "1" if body.send_links else "0")
        return trial_settings_dict(db)

    @app.get("/shop/api/admin/custom-settings")
    def admin_custom_settings_get(admin: User = Depends(require_admin), db: Session = Depends(get_db)):
        return custom_builder_admin_settings(db)

    @app.get("/shop/api/growth/options")
    def growth_options(user: User = Depends(current_user), db: Session = Depends(get_db)):
        from app.growth import family_settings_dict

        from app.growth import purchase_discount_percent

        fam = family_settings_dict(db)
        return {
            "family": {
                "enabled": fam["enabled"],
                "min_size": fam["min_size"],
                "max_size": fam["max_size"],
            },
            "purchase_discount_percent": purchase_discount_percent(db),
        }

    @app.post("/shop/api/promo/validate")
    def promo_validate(
        payload: Annotated[PromoValidateBody, Body()],
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
    ):
        from app.growth import family_settings_dict, promo_error_fa, quote_growth_pricing

        db.refresh(user)
        unit = 0
        if payload.plan_id:
            plan = get_plan(db, payload.plan_id)
            if not plan:
                raise HTTPException(404, "پلن پیدا نشد")
            unit = plan_charge_price(db, user, plan)
        elif payload.duration_days:
            from app.services import compute_custom_base_price, custom_charge_price

            base = compute_custom_base_price(
                db,
                duration_days=int(payload.duration_days),
                traffic_gb=0 if payload.unlimited else int(payload.traffic_gb or 0),
                limit_ip=int(payload.limit_ip or 1),
                unlimited=bool(payload.unlimited),
            )
            unit = custom_charge_price(db, user, base)
        else:
            raise HTTPException(400, "پلن یا پکیج لازم است")
        growth = quote_growth_pricing(
            db,
            user,
            unit,
            promo_code=payload.code.strip() or None,
            family_size=payload.family_size,
        )
        if payload.code.strip() and not growth["promo_ok"]:
            raise HTTPException(400, promo_error_fa(growth.get("promo_error") or "promo_invalid"))
        fam = family_settings_dict(db)
        growth["family"] = fam
        return growth

    @app.get("/shop/api/admin/promo-codes")
    def admin_promo_list(admin: User = Depends(require_admin), db: Session = Depends(get_db)):
        from app.growth import list_promo_codes

        return {"items": list_promo_codes(db)}

    @app.post("/shop/api/admin/promo-codes")
    def admin_promo_create(
        body: Annotated[PromoCodeAdminBody, Body()],
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        from app.growth import promo_dict, promo_error_fa, upsert_promo_code

        try:
            row = upsert_promo_code(
                db,
                code=body.code,
                kind=body.kind,
                value=body.value,
                max_uses=body.max_uses,
                per_user_limit=body.per_user_limit,
                enabled=body.enabled,
                note=body.note,
            )
        except ValueError as exc:
            raise HTTPException(400, promo_error_fa(str(exc))) from exc
        return {"ok": True, "item": promo_dict(row)}

    @app.post("/shop/api/admin/promo-codes/{promo_id}/enabled")
    def admin_promo_enabled(
        promo_id: int,
        body: Annotated[SubscriptionEnabledBody, Body()],
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        from app.growth import promo_dict, promo_error_fa, set_promo_enabled

        try:
            row = set_promo_enabled(db, promo_id, body.enabled)
        except ValueError as exc:
            raise HTTPException(400, promo_error_fa(str(exc))) from exc
        return {"ok": True, "item": promo_dict(row)}

    @app.get("/shop/api/admin/family-settings")
    def admin_family_get(admin: User = Depends(require_admin), db: Session = Depends(get_db)):
        from app.growth import family_settings_dict

        return family_settings_dict(db)

    @app.post("/shop/api/admin/family-settings")
    def admin_family_set(
        body: Annotated[FamilySettingsBody, Body()],
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        from app.growth import update_family_settings

        return update_family_settings(
            db,
            enabled=body.enabled,
            max_size=body.max_size,
            extra_discount_percent=body.extra_discount_percent,
        )

    @app.get("/shop/api/admin/discount-settings")
    def admin_discount_get(admin: User = Depends(require_admin), db: Session = Depends(get_db)):
        from app.growth import discount_settings_dict

        return discount_settings_dict(db)

    @app.post("/shop/api/admin/discount-settings")
    def admin_discount_set(
        body: Annotated[DiscountSettingsBody, Body()],
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        from app.growth import update_discount_settings

        return update_discount_settings(
            db,
            purchase_discount_percent=body.purchase_discount_percent,
            family_extra_discount_percent=body.family_extra_discount_percent,
        )

    @app.post("/shop/api/admin/custom-settings")
    def admin_custom_settings_set(
        body: CustomBuilderSettingsBody,
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        try:
            return update_custom_builder_settings(
                db,
                enabled=body.enabled,
                min_days=body.min_days,
                max_days=body.max_days,
                min_gb=body.min_gb,
                max_gb=body.max_gb,
                min_ip=body.min_ip,
                max_ip=body.max_ip,
                base_fee_toman=body.base_fee_toman,
                price_per_day_toman=body.price_per_day_toman,
                price_per_gb_toman=body.price_per_gb_toman,
                unlimited_day_fee_toman=body.unlimited_day_fee_toman,
                price_per_ip_toman=body.price_per_ip_toman,
                min_price_toman=body.min_price_toman,
            )
        except ValueError as exc:
            messages = {
                "days_range_invalid": "بازه روز نامعتبر است",
                "gb_range_invalid": "بازه حجم نامعتبر است",
                "ip_range_invalid": "بازه دستگاه نامعتبر است",
            }
            raise HTTPException(400, messages.get(str(exc), str(exc))) from exc

    @app.get("/shop/api/admin/payg-settings")
    def admin_payg_settings_get(admin: User = Depends(require_admin), db: Session = Depends(get_db)):
        return payg_builder_admin_settings(db)

    @app.post("/shop/api/admin/payg-settings")
    def admin_payg_settings_set(
        body: PaygBuilderSettingsBody,
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        try:
            return update_payg_builder_settings(
                db,
                enabled=body.enabled,
                price_per_gb_toman=body.price_per_gb_toman,
                prepaid_price_per_gb_toman=body.prepaid_price_per_gb_toman,
                min_wallet_toman=body.min_wallet_toman,
                limit_ip=body.limit_ip,
                min_gb=body.min_gb,
                max_gb=body.max_gb,
                min_ip=body.min_ip,
                max_ip=body.max_ip,
                price_per_ip_toman=body.price_per_ip_toman,
                min_price_toman=body.min_price_toman,
            )
        except ValueError as exc:
            messages = {
                "ip_range_invalid": "تعداد دستگاه نامعتبر است",
                "gb_range_invalid": "بازه حجم نامعتبر است",
                "price_invalid": "قیمت هر گیگ نامعتبر است",
                "min_wallet_invalid": "حداقل موجودی نامعتبر است",
            }
            raise HTTPException(400, messages.get(str(exc), str(exc))) from exc

    @app.post("/shop/api/admin/trial-grant")
    def admin_trial_grant(
        body: TrialGrantBody,
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        import re

        tokens: list[str] = list(body.targets)
        if body.targets_text.strip():
            tokens.extend(re.split(r"[\s,;]+", body.targets_text.strip()))

        if body.all_users:
            users = list(db.scalars(select(User)).all())
            not_found: list[str] = []
        else:
            if not tokens:
                raise HTTPException(400, "targets_required")
            users, not_found = resolve_trial_target_users(db, tokens)
            if not users:
                raise HTTPException(404, "users_not_found")

        result = grant_trial_to_users(
            db,
            users,
            state.panel,
            settings,
            skip_existing_trial=body.skip_existing_trial,
            duration_days=body.duration_days,
            traffic_gb=body.traffic_gb,
            limit_ip=body.limit_ip,
            notify=body.notify_users,
        )
        from app.ops import record_audit

        record_audit(
            db,
            actor=admin,
            action="trial_grant",
            detail=f"granted={result.get('granted_count', 0)} skipped={result.get('skipped_count', 0)} all={body.all_users}",
        )
        result["not_found"] = not_found
        result["total_targets"] = len(users)
        return result

    @app.get("/shop/api/admin/users")
    def admin_users_list(
        q: str = "",
        include_test: bool = False,
        slice: str = "",
        days: int = 0,
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        if slice:
            return list_admin_slice(
                db, settings, key=slice, days=days, include_test=include_test, query=q
            )
        return {
            "items": search_users_admin(db, settings, q, include_test=include_test),
            "title": "کاربران",
            "key": "",
        }

    @app.get("/shop/api/admin/analytics")
    def admin_analytics_get(
        days: int = 30,
        include_test: bool = False,
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        return admin_analytics(db, days=days, include_test=include_test)

    @app.get("/shop/api/admin/expiring")
    def admin_expiring_list(
        days: int = 3,
        include_test: bool = False,
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        return list_expiring_soon(db, days=days, include_test=include_test)

    @app.post("/shop/api/admin/subscriptions/{sub_id}/remind-expiry")
    def admin_remind_expiry(
        sub_id: int,
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        from app.jobs import send_expiry_reminder

        sub = db.get(Subscription, sub_id)
        if not sub:
            raise HTTPException(404, "کانفیگ پیدا نشد")
        if not send_expiry_reminder(db, settings, sub, mark=True):
            raise HTTPException(400, "ارسال یادآوری ممکن نبود")
        return {"ok": True, "subscription_id": sub.id}

    @app.get("/shop/api/admin/servers")
    def admin_servers_list(admin: User = Depends(require_admin), db: Session = Depends(get_db)):
        return list_vpn_servers_admin(db, settings)

    @app.post("/shop/api/admin/servers")
    def admin_servers_add(
        body: VpnServerBody,
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        try:
            row = add_vpn_server(
                db,
                settings,
                name=body.name,
                country_code=body.country_code,
                xui_base_url=body.xui_base_url,
                xui_api_token=body.xui_api_token,
                inbound_ids=body.inbound_ids,
                public_host=body.public_host,
                public_ip=body.public_ip,
            )
        except ValueError as exc:
            messages = {
                "name_required": "نام سرور را وارد کنید",
                "panel_required": "آدرس پنل و توکن لازم است",
                "endpoint_required": "دامنه یا آی‌پی عمومی لازم است",
                "inbound_ids_required": "شناسه اینباند را وارد کنید",
            }
            raise HTTPException(400, messages.get(str(exc), str(exc))) from exc
        except PanelError as exc:
            raise HTTPException(400, f"اتصال به پنل ناموفق بود: {exc}") from exc
        try:
            panel = panel_for_server(settings, row)
            try:
                sync_telegram_proxy_for_panel(db, panel)
            finally:
                panel.close()
        except Exception:
            logger.exception("telegram proxy bootstrap failed for server %s", row.id)
        state.panel = get_panel_hub(settings, db)
        return {"ok": True, "server": vpn_server_dict(row), **list_vpn_servers_admin(db, settings)}

    @app.post("/shop/api/admin/servers/{server_id}/enabled")
    def admin_servers_enabled(
        server_id: int,
        body: VpnServerEnabledBody,
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        try:
            set_vpn_server_enabled(db, settings, server_id, body.enabled)
        except ValueError:
            raise HTTPException(404, "سرور پیدا نشد")
        state.panel = get_panel_hub(settings, db)
        return {"ok": True, **list_vpn_servers_admin(db, settings)}

    @app.post("/shop/api/admin/servers/{server_id}/visibility")
    def admin_servers_visibility(
        server_id: int,
        body: VpnServerVisibilityBody,
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        if body.enabled is None and body.configs is None:
            raise HTTPException(400, "چیزی برای ذخیره ارسال نشده")
        try:
            set_vpn_server_visibility(
                db,
                settings,
                server_id,
                enabled=body.enabled,
                configs=body.configs,
            )
        except ValueError:
            raise HTTPException(404, "سرور پیدا نشد")
        state.panel = get_panel_hub(settings, db)
        return {"ok": True, **list_vpn_servers_admin(db, settings)}

    @app.post("/shop/api/admin/servers/{server_id}/sync")
    def admin_servers_sync(
        server_id: int,
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        try:
            result = sync_subscriptions_to_server(db, settings, server_id)
        except ValueError:
            raise HTTPException(404, "سرور پیدا نشد")
        return {"ok": True, **result}

    @app.post("/shop/api/admin/servers/{server_id}/delete")
    def admin_servers_delete(
        server_id: int,
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        try:
            delete_vpn_server(db, server_id)
        except ValueError:
            raise HTTPException(404, "سرور پیدا نشد")
        state.panel = get_panel_hub(settings, db)
        return {"ok": True, **list_vpn_servers_admin(db, settings)}

    @app.post("/shop/api/admin/users/{user_id}/role")
    def admin_set_user_role(
        user_id: int,
        body: UserRoleBody,
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        target = db.get(User, user_id)
        if not target:
            raise HTTPException(404, "user_not_found")
        try:
            updated = set_user_role(
                db,
                target,
                body.role,
                actor=admin,
                settings=settings,
            )
        except ValueError as exc:
            code = str(exc)
            if code == "super_admin_locked":
                raise HTTPException(400, "این کاربر ادمین اصلی است و از پنل قابل حذف نیست") from exc
            if code == "cannot_demote_self":
                raise HTTPException(400, "نمی‌توانید نقش خود را تغییر دهید") from exc
            raise HTTPException(400, code) from exc
        return {"ok": True, "user": search_users_admin(db, settings, str(updated.telegram_id))[0]}

    @app.post("/shop/api/admin/users/{user_id}/test-flag")
    def admin_set_user_test_flag(
        user_id: int,
        body: UserTestFlagBody,
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        target = db.get(User, user_id)
        if not target:
            raise HTTPException(404, "user_not_found")
        updated = set_user_test_flag(db, target, body.is_test)
        return {"ok": True, "user": search_users_admin(db, settings, str(updated.telegram_id), include_test=True)[0]}

    @app.get("/shop/api/admin/users/{user_id}")
    def admin_user_get(
        user_id: int,
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        target = db.get(User, user_id)
        if not target:
            raise HTTPException(404, "کاربر پیدا نشد")
        return admin_user_detail(db, target, settings, state.panel)

    @app.post("/shop/api/admin/users/{user_id}/wallet")
    def admin_user_wallet(
        user_id: int,
        body: Annotated[WalletAdjustBody, Body()],
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        target = db.get(User, user_id)
        if not target:
            raise HTTPException(404, "کاربر پیدا نشد")
        try:
            updated = adjust_user_wallet(
                db,
                target,
                body.amount_toman,
                state.panel,
                settings,
                allow_negative=True,
            )
        except ValueError as exc:
            code = str(exc)
            if code == "zero_amount":
                raise HTTPException(400, "مبلغ نمی‌تواند صفر باشد") from exc
            if code == "insufficient_wallet":
                raise HTTPException(400, "موجودی برای کسر کافی نیست") from exc
            raise HTTPException(400, code) from exc
        sign = "+" if body.amount_toman > 0 else "−"
        note = (body.note or "").strip()
        debt = max(0, -int(updated.wallet_balance or 0))
        text = (
            f"{'💰 شارژ کیف‌پول' if body.amount_toman > 0 else '📉 کسر از کیف‌پول'} توسط پشتیبانی\n"
            f"مبلغ: {sign}{format_price(abs(body.amount_toman))}\n"
            f"موجودی فعلی: {format_price(updated.wallet_balance or 0)}"
        )
        if debt:
            text += f"\nبدهی: {format_price(debt)}"
            text += f"\nسقف اعتبار: {format_price(int(updated.wallet_credit_limit or 0))}"
        if note:
            text += f"\nتوضیح: {note}"
        _notify_telegram(updated.telegram_id, text)
        return {"ok": True, "user": admin_user_detail(db, updated, settings, state.panel)}

    @app.post("/shop/api/admin/users/{user_id}/wallet-convert-credit")
    def admin_user_wallet_convert_credit(
        user_id: int,
        body: Annotated[WalletConvertCreditBody, Body()],
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        target = db.get(User, user_id)
        if not target:
            raise HTTPException(404, "کاربر پیدا نشد")
        before = int(target.wallet_balance or 0)
        try:
            updated = convert_wallet_topup_to_credit(
                db,
                target,
                body.original_topup_toman,
                state.panel,
                settings,
            )
        except ValueError as exc:
            if str(exc) == "zero_amount":
                raise HTTPException(400, "مبلغ شارژ اولیه را وارد کنید") from exc
            raise HTTPException(400, str(exc)) from exc
        debt = max(0, -int(updated.wallet_balance or 0))
        text = (
            "💳 شارژ قبلی به اعتبار (نسیه) تبدیل شد\n"
            f"مبلغ شارژ اولیه: {format_price(body.original_topup_toman)}\n"
            f"موجودی قبل: {format_price(before)}\n"
            f"موجودی الان: {format_price(updated.wallet_balance or 0)}\n"
            f"سقف اعتبار: {format_price(int(updated.wallet_credit_limit or 0))}"
        )
        if debt:
            text += f"\nبدهی قابل پرداخت با شارژ کیف‌پول: {format_price(debt)}"
        _notify_telegram(updated.telegram_id, text)
        return {"ok": True, "user": admin_user_detail(db, updated, settings, state.panel)}

    @app.post("/shop/api/admin/users/{user_id}/wallet-credit")
    def admin_user_wallet_credit(
        user_id: int,
        body: Annotated[WalletCreditLimitBody, Body()],
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        target = db.get(User, user_id)
        if not target:
            raise HTTPException(404, "کاربر پیدا نشد")
        try:
            updated = set_user_wallet_credit_limit(db, target, body.credit_limit_toman)
        except ValueError as exc:
            if str(exc) == "debt_exceeds_limit":
                raise HTTPException(
                    400,
                    "سقف اعتبار کمتر از بدهی فعلی است — اول بدهی را تسویه کنید یا سقف را بالاتر بگذارید",
                ) from exc
            raise HTTPException(400, str(exc)) from exc
        limit = int(updated.wallet_credit_limit or 0)
        debt = max(0, -int(updated.wallet_balance or 0))
        if limit > 0:
            text = (
                f"💳 اعتبار خرید برای شما فعال شد\n"
                f"سقف اعتبار: {format_price(limit)}\n"
                "می‌توانید تا این مبلغ بخرید و بعداً با شارژ کیف‌پول بدهی را تسویه کنید."
            )
            if debt:
                text += f"\nبدهی فعلی: {format_price(debt)}"
        else:
            text = "اعتبار خرید کیف‌پول شما غیرفعال شد."
            if debt:
                text += f"\nبدهی باقی‌مانده: {format_price(debt)} — با شارژ کیف‌پول تسویه می‌شود."
        _notify_telegram(updated.telegram_id, text)
        return {"ok": True, "user": admin_user_detail(db, updated, settings, state.panel)}

    @app.post("/shop/api/admin/users/{user_id}/subscriptions/{sub_id}/enabled")
    def admin_user_sub_enabled(
        user_id: int,
        sub_id: int,
        body: Annotated[SubscriptionEnabledBody, Body()],
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        target = db.get(User, user_id)
        if not target:
            raise HTTPException(404, "کاربر پیدا نشد")
        sub = db.get(Subscription, sub_id)
        if not sub or sub.user_id != target.id:
            raise HTTPException(404, "کانفیگ پیدا نشد")
        try:
            set_subscription_enabled(db, state.panel, sub, body.enabled)
        except Exception as exc:
            logger.exception("admin set sub enabled failed")
            raise HTTPException(400, "تغییر وضعیت کانفیگ ناموفق بود") from exc
        return {"ok": True, "user": admin_user_detail(db, target, settings, state.panel)}

    @app.get("/shop/api/admin/gift-plans")
    def admin_gift_plans(admin: User = Depends(require_admin), db: Session = Depends(get_db)):
        items = []
        for p in admin_giftable_plans(db):
            items.append(
                {
                    "id": p.id,
                    "code": p.code,
                    "title": p.title,
                    "duration_days": p.duration_days,
                    "traffic_gb": p.traffic_gb,
                    "traffic_label": traffic_label(p.traffic_gb),
                    "limit_ip": p.limit_ip,
                    "price_toman": p.price_toman,
                    "price_label": format_price(p.price_toman),
                }
            )
        return {"items": items}

    @app.post("/shop/api/admin/users/{user_id}/pro")
    def admin_user_grant_pro(
        user_id: int,
        body: Annotated[GrantProBody, Body()],
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        target = db.get(User, user_id)
        if not target:
            raise HTTPException(404, "کاربر پیدا نشد")
        try:
            until = grant_pro_to_user(db, target, days=body.days)
        except Exception as exc:
            logger.exception("admin grant pro failed")
            raise HTTPException(400, "اعطای Pro ناموفق بود") from exc
        from app.ops import record_audit

        record_audit(
            db,
            actor=admin,
            action="grant_pro",
            target_user=target,
            detail=f"days={body.days or 'default'} until={until.isoformat() if until else ''}",
        )
        until_label = until.strftime("%Y/%m/%d") if until else ""
        _notify_telegram(
            target.telegram_id,
            f"⭐ اشتراک Pro برای شما فعال شد.\nاعتبار تا: {until_label}",
        )
        return {"ok": True, "user": admin_user_detail(db, target, settings, state.panel)}

    @app.post("/shop/api/admin/users/{user_id}/subscriptions")
    def admin_user_gift_subscription(
        user_id: int,
        body: Annotated[GiftSubscriptionBody, Body()],
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        target = db.get(User, user_id)
        if not target:
            raise HTTPException(404, "کاربر پیدا نشد")
        try:
            sub = admin_gift_subscription(
                db,
                target,
                state.panel,
                settings,
                plan_id=body.plan_id,
            )
        except ValueError as exc:
            if str(exc) == "invalid_plan":
                raise HTTPException(400, "پلن نامعتبر است") from exc
            if str(exc) == "plan_unavailable":
                raise HTTPException(400, "این پلن فعلاً در دسترس نیست") from exc
            raise HTTPException(400, "افزودن کانفیگ ناموفق بود") from exc
        except PanelError as exc:
            raise HTTPException(502, str(exc)) from exc
        except Exception as exc:
            logger.exception("admin gift subscription failed")
            raise HTTPException(400, "افزودن کانفیگ ناموفق بود") from exc
        from app.ops import record_audit

        record_audit(
            db,
            actor=admin,
            action="gift_subscription",
            target_user=target,
            target_subscription_id=sub.id,
            detail=f"plan_id={body.plan_id} email={sub.xui_email}",
        )
        from app.texts import subscription_link_message

        _notify_telegram(
            target.telegram_id,
            subscription_link_message(
                email=sub.xui_email,
                sub_url=build_subscription_url(sub.xui_sub_id, settings),
                label=sub.label or "کانفیگ",
                title="✅ یک کانفیگ جدید برای شما فعال شد",
            ),
        )
        return {"ok": True, "subscription_id": sub.id, "user": admin_user_detail(db, target, settings, state.panel)}

    @app.post("/shop/api/admin/users/{user_id}/subscriptions/{sub_id}/delete")
    def admin_user_delete_subscription(
        user_id: int,
        sub_id: int,
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        target = db.get(User, user_id)
        if not target:
            raise HTTPException(404, "کاربر پیدا نشد")
        sub = db.get(Subscription, sub_id)
        if not sub or sub.user_id != target.id:
            raise HTTPException(404, "کانفیگ پیدا نشد")
        email = sub.xui_email
        sub_id_keep = sub.id
        try:
            delete_user_subscription(db, state.panel, sub)
        except Exception as exc:
            logger.exception("admin delete subscription failed")
            raise HTTPException(400, "حذف کانفیگ ناموفق بود") from exc
        from app.ops import record_audit

        record_audit(
            db,
            actor=admin,
            action="delete_subscription",
            target_user=target,
            target_subscription_id=sub_id_keep,
            detail=f"email={email}",
        )
        _notify_telegram(target.telegram_id, f"کانفیگ شما حذف شد.\nشناسه: {email}")
        return {"ok": True, "user": admin_user_detail(db, target, settings, state.panel)}

    @app.post("/shop/api/admin/bulk-gift")
    def admin_bulk_gift(
        body: Annotated[BulkGiftBody, Body()],
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        from app.ops import bulk_gift_to_users, resolve_bulk_targets

        users, not_found = resolve_bulk_targets(
            db, targets_text=body.targets_text, all_users=body.all_users
        )
        if not body.all_users and not users:
            raise HTTPException(404, "کاربری پیدا نشد")
        try:
            result = bulk_gift_to_users(
                db,
                users,
                state.panel,
                settings,
                kind=body.kind,
                plan_id=body.plan_id,
                pro_days=body.pro_days,
                notify=body.notify_users,
                actor=admin,
            )
        except ValueError as exc:
            messages = {
                "kind_invalid": "نوع هدیه نامعتبر است",
                "plan_required": "پلن را انتخاب کنید",
            }
            raise HTTPException(400, messages.get(str(exc), str(exc))) from exc
        result["not_found"] = not_found
        result["total_targets"] = len(users)
        return result

    @app.post("/shop/api/admin/subscriptions/{sub_id}/transfer")
    def admin_transfer_subscription(
        sub_id: int,
        body: Annotated[TransferSubscriptionBody, Body()],
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
    ):
        from app.ops import resolve_bulk_targets, transfer_subscription
        from app.services import _notify_telegram as notify_tg

        sub = db.get(Subscription, sub_id)
        if not sub:
            raise HTTPException(404, "کانفیگ پیدا نشد")
        users, missing = resolve_bulk_targets(db, targets_text=body.target, all_users=False)
        if not users:
            raise HTTPException(404, "کاربر مقصد پیدا نشد" + (f": {', '.join(missing)}" if missing else ""))
        target = users[0]
        try:
            sub, source = transfer_subscription(db, sub=sub, target=target, actor=admin)
        except ValueError as exc:
            if str(exc) == "same_user":
                raise HTTPException(400, "کانفیگ همین الان مال این کاربر است") from exc
            raise HTTPException(400, str(exc)) from exc
        label = (sub.label or "").strip() or sub.xui_email
        if body.notify:
            if source and source.telegram_id:
                notify_tg(settings, source.telegram_id, f"↩️ کانفیگ «{label}» به حساب دیگری منتقل شد.")
            if target.telegram_id:
                notify_tg(
                    settings,
                    target.telegram_id,
                    f"✅ کانفیگ «{label}» به حساب شما منتقل شد.\nشناسه: {sub.xui_email}",
                )
        return {
            "ok": True,
            "subscription_id": sub.id,
            "from_user_id": source.id if source else None,
            "to_user_id": target.id,
            "email": sub.xui_email,
        }

    @app.get("/shop/api/activity")
    def my_activity(
        user: User = Depends(current_user),
        db: Session = Depends(get_db),
        limit: int = 40,
        offset: int = 0,
    ):
        from app.ops import list_audit_logs

        return list_audit_logs(db, limit=limit, offset=offset, actor_user_id=user.id)

    @app.get("/shop/api/admin/audit-log")
    def admin_audit_log(
        admin: User = Depends(require_admin),
        db: Session = Depends(get_db),
        limit: int = 80,
        offset: int = 0,
        q: str = "",
        actor_kind: str = "",
        category: str = "",
        include_test: bool = False,
    ):
        from app.ops import list_audit_logs

        return list_audit_logs(
            db,
            limit=limit,
            offset=offset,
            q=q,
            actor_kind=actor_kind,
            category=category,
            include_test=include_test,
        )

    if STATIC_DIR.exists():
        assets = STATIC_DIR / "assets"
        if assets.exists():
            app.mount("/shop/assets", StaticFiles(directory=str(assets)), name="assets")

        @app.get("/shop")
        @app.get("/shop/")
        def shop_index():
            return FileResponse(STATIC_DIR / "index.html")

        @app.get("/shop/{path:path}")
        def shop_spa(path: str):
            if path.startswith("api/") or path.startswith("sub/"):
                raise HTTPException(404)
            candidate = STATIC_DIR / path
            if candidate.is_file():
                return FileResponse(candidate)
            return FileResponse(STATIC_DIR / "index.html")

    return app


app = create_app()
