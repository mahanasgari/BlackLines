from __future__ import annotations

from datetime import date, datetime
from enum import Enum

from sqlalchemy import (
    BigInteger,
    Boolean,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    create_engine,
    event,
    func,
    text,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship, sessionmaker


class Base(DeclarativeBase):
    pass


class OrderStatus(str, Enum):
    PENDING = "pending"
    APPROVED = "approved"
    REJECTED = "rejected"
    CANCELLED = "cancelled"


class WithdrawStatus(str, Enum):
    PENDING = "pending"
    PAID = "paid"
    REJECTED = "rejected"


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    telegram_id: Mapped[int] = mapped_column(BigInteger, unique=True, index=True)
    username: Mapped[str | None] = mapped_column(String(255), nullable=True)
    full_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    referral_code: Mapped[str | None] = mapped_column(String(32), unique=True, index=True, nullable=True)
    referred_by_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True, index=True)
    wallet_balance: Mapped[int] = mapped_column(Integer, default=0)
    wallet_locked_toman: Mapped[int] = mapped_column(Integer, default=0)
    # Max debt allowed (تومان). Balance may go negative down to -wallet_credit_limit.
    wallet_credit_limit: Mapped[int] = mapped_column(Integer, default=0)
    birth_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    birth_date_source: Mapped[str | None] = mapped_column(String(16), nullable=True)
    birth_date_year_hidden: Mapped[bool] = mapped_column(Boolean, default=False)
    email: Mapped[str | None] = mapped_column(String(128), nullable=True)
    phone: Mapped[str | None] = mapped_column(String(32), nullable=True)
    photo_file_id: Mapped[str | None] = mapped_column(String(255), nullable=True)
    birthday_gift_year: Mapped[int | None] = mapped_column(Integer, nullable=True)
    pro_until: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    trial_granted: Mapped[bool] = mapped_column(Boolean, default=False)
    is_test: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
    role: Mapped[str] = mapped_column(String(16), default="user", index=True)
    # Admin support shift — only on-duty admins get new-chat pings
    on_duty: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())

    orders: Mapped[list[Order]] = relationship(back_populates="user")
    subscriptions: Mapped[list[Subscription]] = relationship(back_populates="user")
    referrer: Mapped[User | None] = relationship(remote_side="User.id", foreign_keys=[referred_by_id])


class Plan(Base):
    __tablename__ = "plans"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    code: Mapped[str] = mapped_column(String(64), unique=True)
    title: Mapped[str] = mapped_column(String(128))
    description: Mapped[str] = mapped_column(Text, default="")
    price_toman: Mapped[int] = mapped_column(Integer)
    duration_days: Mapped[int] = mapped_column(Integer)
    traffic_gb: Mapped[int] = mapped_column(Integer, default=0)  # 0 = unlimited
    limit_ip: Mapped[int] = mapped_column(Integer, default=2)
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)

    orders: Mapped[list[Order]] = relationship(back_populates="plan")


class Order(Base):
    __tablename__ = "orders"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    plan_id: Mapped[int] = mapped_column(ForeignKey("plans.id"))
    status: Mapped[str] = mapped_column(String(32), default=OrderStatus.PENDING, index=True)
    amount_toman: Mapped[int] = mapped_column(Integer)
    wallet_used: Mapped[int] = mapped_column(Integer, default=0)
    wallet_locked_used: Mapped[int] = mapped_column(Integer, default=0)
    receipt_file_id: Mapped[str | None] = mapped_column(String(255), nullable=True)
    admin_note: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
    reviewed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    target_subscription_id: Mapped[int | None] = mapped_column(
        ForeignKey("subscriptions.id"), nullable=True, index=True
    )
    custom_duration_days: Mapped[int | None] = mapped_column(Integer, nullable=True)
    custom_traffic_gb: Mapped[int | None] = mapped_column(Integer, nullable=True)
    custom_limit_ip: Mapped[int | None] = mapped_column(Integer, nullable=True)
    custom_price_toman: Mapped[int | None] = mapped_column(Integer, nullable=True)
    promo_code: Mapped[str | None] = mapped_column(String(32), nullable=True)
    promo_kind: Mapped[str | None] = mapped_column(String(16), nullable=True)
    promo_value: Mapped[int | None] = mapped_column(Integer, nullable=True)
    discount_toman: Mapped[int] = mapped_column(Integer, default=0)
    bonus_days: Mapped[int] = mapped_column(Integer, default=0)
    family_size: Mapped[int] = mapped_column(Integer, default=1)
    # Reseller / buy-for-others customer snapshot (copied onto subscription on approve)
    customer_name: Mapped[str | None] = mapped_column(String(64), nullable=True)
    customer_email: Mapped[str | None] = mapped_column(String(128), nullable=True)
    customer_phone: Mapped[str | None] = mapped_column(String(32), nullable=True)
    customer_telegram_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    config_label: Mapped[str | None] = mapped_column(String(64), nullable=True)

    user: Mapped[User] = relationship(back_populates="orders")
    plan: Mapped[Plan] = relationship(back_populates="orders")
    subscription: Mapped[Subscription | None] = relationship(
        back_populates="order",
        uselist=False,
        foreign_keys="Subscription.order_id",
    )
    target_subscription: Mapped[Subscription | None] = relationship(
        foreign_keys=[target_subscription_id],
    )
    commission: Mapped[Commission | None] = relationship(back_populates="order", uselist=False)


class Subscription(Base):
    __tablename__ = "subscriptions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    order_id: Mapped[int | None] = mapped_column(ForeignKey("orders.id"), nullable=True)
    plan_id: Mapped[int] = mapped_column(ForeignKey("plans.id"))
    xui_email: Mapped[str] = mapped_column(String(128), unique=True, index=True)
    xui_uuid: Mapped[str | None] = mapped_column(String(64), nullable=True)
    xui_sub_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    label: Mapped[str | None] = mapped_column(String(64), nullable=True)
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    is_payg: Mapped[bool] = mapped_column(Boolean, default=False)
    payg_metered: Mapped[bool] = mapped_column(Boolean, default=False)
    billed_bytes: Mapped[int] = mapped_column(BigInteger, default=0)
    billed_toman: Mapped[int] = mapped_column(Integer, default=0)
    last_billed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    # User paused cloud PAYG — wallet top-up must not auto-resume
    payg_paused_by_user: Mapped[bool] = mapped_column(Boolean, default=False)
    expires_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
    auto_renew: Mapped[bool] = mapped_column(Boolean, default=False)
    alert_traffic_80_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    alert_traffic_100_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    alert_ip_over_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    auto_renew_fail_notified_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    family_group: Mapped[str | None] = mapped_column(String(32), nullable=True, index=True)
    family_index: Mapped[int | None] = mapped_column(Integer, nullable=True)
    family_role: Mapped[str | None] = mapped_column(String(16), nullable=True)  # parent | child
    parental_categories: Mapped[str | None] = mapped_column(String(512), nullable=True)  # JSON list
    parental_schedule: Mapped[str | None] = mapped_column(String(256), nullable=True)  # JSON hours/days (content blocks)
    # Child VPN may only connect during this window (Asia/Tehran); panel forced off outside it
    vpn_allow_schedule: Mapped[str | None] = mapped_column(String(256), nullable=True)
    vpn_schedule_paused: Mapped[bool] = mapped_column(Boolean, default=False)
    # Parent "pause day" — freeze child VPN until this UTC time (config kept)
    parental_pause_until: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    # Abuse soft-throttle (multi-IP / traffic spike) — temporary panel disable
    abuse_flag: Mapped[str | None] = mapped_column(String(32), nullable=True)
    abuse_throttled_until: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    abuse_notes: Mapped[str | None] = mapped_column(String(256), nullable=True)
    abuse_notified_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    alert_expiry_3d_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    alert_expiry_1d_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    # Soft-hide expired configs from the main dashboard list
    hidden_from_dashboard: Mapped[bool] = mapped_column(Boolean, default=False)
    # End-customer meta for resellers (buyer remains user_id owner)
    customer_name: Mapped[str | None] = mapped_column(String(64), nullable=True)
    customer_email: Mapped[str | None] = mapped_column(String(128), nullable=True)
    customer_phone: Mapped[str | None] = mapped_column(String(32), nullable=True)
    customer_telegram_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    # Reseller desk: last time the buyer copied/sent this config's link to the customer
    link_shared_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    user: Mapped[User] = relationship(back_populates="subscriptions")
    order: Mapped[Order | None] = relationship(
        back_populates="subscription",
        foreign_keys=[order_id],
    )
    plan: Mapped[Plan] = relationship()
    usage_samples: Mapped[list["UsageSample"]] = relationship(back_populates="subscription")


class UsageSample(Base):
    __tablename__ = "usage_samples"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    subscription_id: Mapped[int] = mapped_column(ForeignKey("subscriptions.id"), index=True)
    up_bytes: Mapped[int] = mapped_column(BigInteger, default=0)
    down_bytes: Mapped[int] = mapped_column(BigInteger, default=0)
    used_bytes: Mapped[int] = mapped_column(BigInteger, default=0)
    online: Mapped[bool] = mapped_column(Boolean, default=False)
    recorded_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), index=True)

    subscription: Mapped[Subscription] = relationship(back_populates="usage_samples")


Index("ix_usage_samples_sub_recorded", UsageSample.subscription_id, UsageSample.recorded_at)


class FamilyBrowseEvent(Base):
    """Aggregated sites a family-child config connected to (from Xray access log)."""

    __tablename__ = "family_browse_events"
    __table_args__ = (UniqueConstraint("subscription_id", "domain", "verdict", name="uq_family_browse_sub_domain"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    subscription_id: Mapped[int] = mapped_column(ForeignKey("subscriptions.id"), index=True)
    family_group: Mapped[str | None] = mapped_column(String(32), nullable=True, index=True)
    domain: Mapped[str] = mapped_column(String(255), index=True)
    category: Mapped[str] = mapped_column(String(32), default="other", index=True)
    verdict: Mapped[str] = mapped_column(String(16), default="visit")  # visit | blocked
    hit_count: Mapped[int] = mapped_column(Integer, default=1)
    first_seen: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
    last_seen: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), index=True)


class FamilyBrowseHit(Base):
    """Recent raw connections for the parent activity feed."""

    __tablename__ = "family_browse_hits"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    subscription_id: Mapped[int] = mapped_column(ForeignKey("subscriptions.id"), index=True)
    domain: Mapped[str] = mapped_column(String(255), index=True)
    category: Mapped[str] = mapped_column(String(32), default="other")
    verdict: Mapped[str] = mapped_column(String(16), default="visit")
    seen_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), index=True)


Index("ix_family_browse_hits_sub_seen", FamilyBrowseHit.subscription_id, FamilyBrowseHit.seen_at)


class PromoCode(Base):
    __tablename__ = "promo_codes"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    code: Mapped[str] = mapped_column(String(32), unique=True, index=True)
    kind: Mapped[str] = mapped_column(String(16), default="percent")  # percent | free_days
    value: Mapped[int] = mapped_column(Integer, default=0)
    max_uses: Mapped[int] = mapped_column(Integer, default=0)  # 0 = unlimited
    used_count: Mapped[int] = mapped_column(Integer, default=0)
    per_user_limit: Mapped[int] = mapped_column(Integer, default=1)
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    starts_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    ends_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    note: Mapped[str | None] = mapped_column(String(120), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())


class GiftCard(Base):
    __tablename__ = "gift_cards"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    code: Mapped[str] = mapped_column(String(32), unique=True, index=True)
    plan_id: Mapped[int] = mapped_column(ForeignKey("plans.id"), index=True)
    buyer_user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    order_id: Mapped[int | None] = mapped_column(ForeignKey("orders.id"), nullable=True, index=True)
    redeemed_by_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True, index=True)
    redeemed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())

    plan: Mapped[Plan] = relationship()
    buyer: Mapped[User] = relationship(foreign_keys=[buyer_user_id])
    redeemed_by: Mapped[User | None] = relationship(foreign_keys=[redeemed_by_id])


class PromoRedemption(Base):
    __tablename__ = "promo_redemptions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    promo_code_id: Mapped[int] = mapped_column(ForeignKey("promo_codes.id"), index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    order_id: Mapped[int] = mapped_column(ForeignKey("orders.id"), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())


class Commission(Base):
    __tablename__ = "commissions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    referrer_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    referred_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    order_id: Mapped[int] = mapped_column(ForeignKey("orders.id"), unique=True)
    percent: Mapped[int] = mapped_column(Integer)
    amount_toman: Mapped[int] = mapped_column(Integer)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())

    order: Mapped[Order] = relationship(back_populates="commission")
    referrer: Mapped[User] = relationship(foreign_keys=[referrer_id])
    referred: Mapped[User] = relationship(foreign_keys=[referred_id])


class Withdrawal(Base):
    __tablename__ = "withdrawals"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    amount_toman: Mapped[int] = mapped_column(Integer)
    card_number: Mapped[str] = mapped_column(String(32))
    status: Mapped[str] = mapped_column(String(32), default=WithdrawStatus.PENDING, index=True)
    admin_note: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
    reviewed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    user: Mapped[User] = relationship()


class VpnServer(Base):
    __tablename__ = "vpn_servers"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(64))
    country_code: Mapped[str] = mapped_column(String(16), default="")
    xui_base_url: Mapped[str] = mapped_column(String(512))
    xui_api_token: Mapped[str] = mapped_column(String(256))
    inbound_ids: Mapped[str] = mapped_column(String(128), default="")
    public_host: Mapped[str] = mapped_column(String(255), default="")
    public_ip: Mapped[str] = mapped_column(String(64), default="")
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    # Comma-separated config keys (reality,ws,http,ws_tls,http_ms,telegram). Empty = all.
    config_flags: Mapped[str] = mapped_column(String(128), default="")
    health_ok: Mapped[bool] = mapped_column(Boolean, default=True)
    health_fail_count: Mapped[int] = mapped_column(Integer, default=0)
    last_ping_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)
    last_health_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())


class ShopSetting(Base):
    __tablename__ = "shop_settings"

    key: Mapped[str] = mapped_column(String(64), primary_key=True)
    value: Mapped[str] = mapped_column(Text, default="")


class WalletTransfer(Base):
    __tablename__ = "wallet_transfers"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    from_user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    to_user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    amount_toman: Mapped[int] = mapped_column(Integer)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), index=True)

    sender: Mapped[User] = relationship(foreign_keys=[from_user_id])
    recipient: Mapped[User] = relationship(foreign_keys=[to_user_id])


class ChatMessage(Base):
    __tablename__ = "chat_messages"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    sender: Mapped[str] = mapped_column(String(16), index=True)  # user | admin
    sender_telegram_id: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    body: Mapped[str] = mapped_column(Text)
    attachments_json: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), index=True)
    read_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    user: Mapped[User] = relationship()


Index("ix_chat_messages_user_id_id", ChatMessage.user_id, ChatMessage.id)
Index("ix_chat_messages_user_sender_read", ChatMessage.user_id, ChatMessage.sender, ChatMessage.read_at)


class AdminAuditLog(Base):
    __tablename__ = "admin_audit_logs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    actor_user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True, index=True)
    actor_telegram_id: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    actor_role: Mapped[str | None] = mapped_column(String(16), nullable=True, index=True)  # user | admin | system
    action: Mapped[str] = mapped_column(String(64), index=True)
    category: Mapped[str | None] = mapped_column(String(32), nullable=True, index=True)
    path: Mapped[str | None] = mapped_column(String(160), nullable=True)
    target_user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True, index=True)
    target_subscription_id: Mapped[int | None] = mapped_column(Integer, nullable=True, index=True)
    detail: Mapped[str | None] = mapped_column(String(500), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), index=True)


class AppSession(Base):
    """Opaque Bearer token sessions for the native Flutter app."""

    __tablename__ = "app_sessions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
    user_agent: Mapped[str | None] = mapped_column(String(255), nullable=True)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


class AppLoginChallenge(Base):
    """Pending bot deep-link login: Flutter polls until bot confirms app_<nonce>."""

    __tablename__ = "app_login_challenges"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    nonce: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
    user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True, index=True)
    session_id: Mapped[int | None] = mapped_column(ForeignKey("app_sessions.id"), nullable=True)
    # Held until poll consumes the challenge (then cleared)
    access_token_plain: Mapped[str | None] = mapped_column(String(128), nullable=True)
    consumed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


def make_engine(database_url: str):
    """Create engine; SQLite gets WAL + busy timeout so concurrent bot/API requests don't freeze."""
    is_sqlite = database_url.startswith("sqlite")
    connect_args = {"check_same_thread": False, "timeout": 30} if is_sqlite else {}
    engine = create_engine(
        database_url,
        future=True,
        connect_args=connect_args,
        pool_pre_ping=True,
    )
    if is_sqlite:

        @event.listens_for(engine, "connect")
        def _sqlite_on_connect(dbapi_conn, _connection_record):  # noqa: ANN001
            cursor = dbapi_conn.cursor()
            cursor.execute("PRAGMA journal_mode=WAL")
            cursor.execute("PRAGMA busy_timeout=30000")
            cursor.execute("PRAGMA synchronous=NORMAL")
            cursor.close()

    return engine


def _sqlite_columns(engine, table: str) -> set[str]:
    with engine.connect() as conn:
        rows = conn.execute(text(f"PRAGMA table_info({table})")).fetchall()
    return {row[1] for row in rows}


def migrate_schema(engine) -> None:
    """Add new columns/tables for existing SQLite DBs (create_all won't alter)."""
    if engine.dialect.name != "sqlite":
        return
    with engine.begin() as conn:
        cols = {row[1] for row in conn.execute(text("PRAGMA table_info(users)")).fetchall()}
        if cols:
            if "referral_code" not in cols:
                conn.execute(text("ALTER TABLE users ADD COLUMN referral_code VARCHAR(32)"))
            if "referred_by_id" not in cols:
                conn.execute(text("ALTER TABLE users ADD COLUMN referred_by_id INTEGER"))
            if "wallet_balance" not in cols:
                conn.execute(text("ALTER TABLE users ADD COLUMN wallet_balance INTEGER DEFAULT 0"))
            if "wallet_locked_toman" not in cols:
                conn.execute(text("ALTER TABLE users ADD COLUMN wallet_locked_toman INTEGER DEFAULT 0"))
            if "wallet_credit_limit" not in cols:
                conn.execute(text("ALTER TABLE users ADD COLUMN wallet_credit_limit INTEGER DEFAULT 0"))
            if "birth_date" not in cols:
                conn.execute(text("ALTER TABLE users ADD COLUMN birth_date DATE"))
            if "birth_date_source" not in cols:
                conn.execute(text("ALTER TABLE users ADD COLUMN birth_date_source VARCHAR(16)"))
            if "birth_date_year_hidden" not in cols:
                conn.execute(text("ALTER TABLE users ADD COLUMN birth_date_year_hidden BOOLEAN DEFAULT 0"))
            if "email" not in cols:
                conn.execute(text("ALTER TABLE users ADD COLUMN email VARCHAR(128)"))
            if "phone" not in cols:
                conn.execute(text("ALTER TABLE users ADD COLUMN phone VARCHAR(32)"))
            if "photo_file_id" not in cols:
                conn.execute(text("ALTER TABLE users ADD COLUMN photo_file_id VARCHAR(255)"))
            if "birthday_gift_year" not in cols:
                conn.execute(text("ALTER TABLE users ADD COLUMN birthday_gift_year INTEGER"))
            if "pro_until" not in cols:
                conn.execute(text("ALTER TABLE users ADD COLUMN pro_until DATETIME"))
            if "trial_granted" not in cols:
                conn.execute(text("ALTER TABLE users ADD COLUMN trial_granted BOOLEAN DEFAULT 0"))
            if "role" not in cols:
                conn.execute(text("ALTER TABLE users ADD COLUMN role VARCHAR(16) DEFAULT 'user'"))
            if "is_test" not in cols:
                conn.execute(text("ALTER TABLE users ADD COLUMN is_test BOOLEAN DEFAULT 0"))
            if "on_duty" not in cols:
                conn.execute(text("ALTER TABLE users ADD COLUMN on_duty BOOLEAN DEFAULT 0"))
        order_cols = {row[1] for row in conn.execute(text("PRAGMA table_info(orders)")).fetchall()}
        if order_cols and "wallet_used" not in order_cols:
            conn.execute(text("ALTER TABLE orders ADD COLUMN wallet_used INTEGER DEFAULT 0"))
        if order_cols and "wallet_locked_used" not in order_cols:
            conn.execute(text("ALTER TABLE orders ADD COLUMN wallet_locked_used INTEGER DEFAULT 0"))
        if order_cols and "target_subscription_id" not in order_cols:
            conn.execute(text("ALTER TABLE orders ADD COLUMN target_subscription_id INTEGER"))
        if order_cols and "custom_duration_days" not in order_cols:
            conn.execute(text("ALTER TABLE orders ADD COLUMN custom_duration_days INTEGER"))
        if order_cols and "custom_traffic_gb" not in order_cols:
            conn.execute(text("ALTER TABLE orders ADD COLUMN custom_traffic_gb INTEGER"))
        if order_cols and "custom_limit_ip" not in order_cols:
            conn.execute(text("ALTER TABLE orders ADD COLUMN custom_limit_ip INTEGER"))
        if order_cols and "custom_price_toman" not in order_cols:
            conn.execute(text("ALTER TABLE orders ADD COLUMN custom_price_toman INTEGER"))
        sub_cols = {row[1] for row in conn.execute(text("PRAGMA table_info(subscriptions)")).fetchall()}
        if sub_cols and "label" not in sub_cols:
            conn.execute(text("ALTER TABLE subscriptions ADD COLUMN label VARCHAR(64)"))
        if sub_cols and "is_payg" not in sub_cols:
            conn.execute(text("ALTER TABLE subscriptions ADD COLUMN is_payg BOOLEAN DEFAULT 0"))
        if sub_cols and "payg_metered" not in sub_cols:
            conn.execute(text("ALTER TABLE subscriptions ADD COLUMN payg_metered BOOLEAN DEFAULT 0"))
        if sub_cols and "billed_bytes" not in sub_cols:
            conn.execute(text("ALTER TABLE subscriptions ADD COLUMN billed_bytes INTEGER DEFAULT 0"))
        if sub_cols and "billed_toman" not in sub_cols:
            conn.execute(text("ALTER TABLE subscriptions ADD COLUMN billed_toman INTEGER DEFAULT 0"))
        if sub_cols and "last_billed_at" not in sub_cols:
            conn.execute(text("ALTER TABLE subscriptions ADD COLUMN last_billed_at DATETIME"))
        if sub_cols and "payg_paused_by_user" not in sub_cols:
            conn.execute(text("ALTER TABLE subscriptions ADD COLUMN payg_paused_by_user BOOLEAN DEFAULT 0"))
        if sub_cols and "auto_renew" not in sub_cols:
            conn.execute(text("ALTER TABLE subscriptions ADD COLUMN auto_renew BOOLEAN DEFAULT 0"))
        if sub_cols and "alert_traffic_80_at" not in sub_cols:
            conn.execute(text("ALTER TABLE subscriptions ADD COLUMN alert_traffic_80_at DATETIME"))
        if sub_cols and "alert_traffic_100_at" not in sub_cols:
            conn.execute(text("ALTER TABLE subscriptions ADD COLUMN alert_traffic_100_at DATETIME"))
        if sub_cols and "alert_ip_over_at" not in sub_cols:
            conn.execute(text("ALTER TABLE subscriptions ADD COLUMN alert_ip_over_at DATETIME"))
        if sub_cols and "auto_renew_fail_notified_at" not in sub_cols:
            conn.execute(text("ALTER TABLE subscriptions ADD COLUMN auto_renew_fail_notified_at DATETIME"))
        if sub_cols and "family_group" not in sub_cols:
            conn.execute(text("ALTER TABLE subscriptions ADD COLUMN family_group VARCHAR(32)"))
        if sub_cols and "family_index" not in sub_cols:
            conn.execute(text("ALTER TABLE subscriptions ADD COLUMN family_index INTEGER"))
        if sub_cols and "family_role" not in sub_cols:
            conn.execute(text("ALTER TABLE subscriptions ADD COLUMN family_role VARCHAR(16)"))
        if sub_cols and "parental_categories" not in sub_cols:
            conn.execute(text("ALTER TABLE subscriptions ADD COLUMN parental_categories VARCHAR(512)"))
        if sub_cols and "parental_schedule" not in sub_cols:
            conn.execute(text("ALTER TABLE subscriptions ADD COLUMN parental_schedule VARCHAR(256)"))
        if sub_cols and "vpn_allow_schedule" not in sub_cols:
            conn.execute(text("ALTER TABLE subscriptions ADD COLUMN vpn_allow_schedule VARCHAR(256)"))
        if sub_cols and "vpn_schedule_paused" not in sub_cols:
            conn.execute(text("ALTER TABLE subscriptions ADD COLUMN vpn_schedule_paused BOOLEAN DEFAULT 0"))
        if sub_cols and "parental_pause_until" not in sub_cols:
            conn.execute(text("ALTER TABLE subscriptions ADD COLUMN parental_pause_until DATETIME"))
        if sub_cols and "abuse_flag" not in sub_cols:
            conn.execute(text("ALTER TABLE subscriptions ADD COLUMN abuse_flag VARCHAR(32)"))
        if sub_cols and "abuse_throttled_until" not in sub_cols:
            conn.execute(text("ALTER TABLE subscriptions ADD COLUMN abuse_throttled_until DATETIME"))
        if sub_cols and "abuse_notes" not in sub_cols:
            conn.execute(text("ALTER TABLE subscriptions ADD COLUMN abuse_notes VARCHAR(256)"))
        if sub_cols and "abuse_notified_at" not in sub_cols:
            conn.execute(text("ALTER TABLE subscriptions ADD COLUMN abuse_notified_at DATETIME"))
        if sub_cols and "alert_expiry_3d_at" not in sub_cols:
            conn.execute(text("ALTER TABLE subscriptions ADD COLUMN alert_expiry_3d_at DATETIME"))
        if sub_cols and "alert_expiry_1d_at" not in sub_cols:
            conn.execute(text("ALTER TABLE subscriptions ADD COLUMN alert_expiry_1d_at DATETIME"))
        if sub_cols and "hidden_from_dashboard" not in sub_cols:
            conn.execute(text("ALTER TABLE subscriptions ADD COLUMN hidden_from_dashboard BOOLEAN DEFAULT 0"))
        if order_cols and "promo_code" not in order_cols:
            conn.execute(text("ALTER TABLE orders ADD COLUMN promo_code VARCHAR(32)"))
        if order_cols and "promo_kind" not in order_cols:
            conn.execute(text("ALTER TABLE orders ADD COLUMN promo_kind VARCHAR(16)"))
        if order_cols and "promo_value" not in order_cols:
            conn.execute(text("ALTER TABLE orders ADD COLUMN promo_value INTEGER"))
        if order_cols and "discount_toman" not in order_cols:
            conn.execute(text("ALTER TABLE orders ADD COLUMN discount_toman INTEGER DEFAULT 0"))
        if order_cols and "bonus_days" not in order_cols:
            conn.execute(text("ALTER TABLE orders ADD COLUMN bonus_days INTEGER DEFAULT 0"))
        if order_cols and "family_size" not in order_cols:
            conn.execute(text("ALTER TABLE orders ADD COLUMN family_size INTEGER DEFAULT 1"))
        if order_cols and "customer_name" not in order_cols:
            conn.execute(text("ALTER TABLE orders ADD COLUMN customer_name VARCHAR(64)"))
        if order_cols and "customer_email" not in order_cols:
            conn.execute(text("ALTER TABLE orders ADD COLUMN customer_email VARCHAR(128)"))
        if order_cols and "customer_phone" not in order_cols:
            conn.execute(text("ALTER TABLE orders ADD COLUMN customer_phone VARCHAR(32)"))
        if order_cols and "customer_telegram_id" not in order_cols:
            conn.execute(text("ALTER TABLE orders ADD COLUMN customer_telegram_id VARCHAR(64)"))
        if sub_cols and "customer_name" not in sub_cols:
            conn.execute(text("ALTER TABLE subscriptions ADD COLUMN customer_name VARCHAR(64)"))
        if sub_cols and "customer_email" not in sub_cols:
            conn.execute(text("ALTER TABLE subscriptions ADD COLUMN customer_email VARCHAR(128)"))
        if sub_cols and "customer_phone" not in sub_cols:
            conn.execute(text("ALTER TABLE subscriptions ADD COLUMN customer_phone VARCHAR(32)"))
        if sub_cols and "customer_telegram_id" not in sub_cols:
            conn.execute(text("ALTER TABLE subscriptions ADD COLUMN customer_telegram_id VARCHAR(64)"))
        if sub_cols and "link_shared_at" not in sub_cols:
            conn.execute(text("ALTER TABLE subscriptions ADD COLUMN link_shared_at DATETIME"))
        if order_cols and "config_label" not in order_cols:
            conn.execute(text("ALTER TABLE orders ADD COLUMN config_label VARCHAR(64)"))
        chat_cols = {row[1] for row in conn.execute(text("PRAGMA table_info(chat_messages)")).fetchall()}
        if chat_cols and "attachments_json" not in chat_cols:
            conn.execute(text("ALTER TABLE chat_messages ADD COLUMN attachments_json TEXT"))
        vpn_cols = {row[1] for row in conn.execute(text("PRAGMA table_info(vpn_servers)")).fetchall()}
        if vpn_cols and "config_flags" not in vpn_cols:
            conn.execute(text("ALTER TABLE vpn_servers ADD COLUMN config_flags VARCHAR(128) DEFAULT ''"))
        if vpn_cols and "health_ok" not in vpn_cols:
            conn.execute(text("ALTER TABLE vpn_servers ADD COLUMN health_ok BOOLEAN DEFAULT 1"))
        if vpn_cols and "health_fail_count" not in vpn_cols:
            conn.execute(text("ALTER TABLE vpn_servers ADD COLUMN health_fail_count INTEGER DEFAULT 0"))
        if vpn_cols and "last_ping_ms" not in vpn_cols:
            conn.execute(text("ALTER TABLE vpn_servers ADD COLUMN last_ping_ms INTEGER"))
        if vpn_cols and "last_health_at" not in vpn_cols:
            conn.execute(text("ALTER TABLE vpn_servers ADD COLUMN last_health_at DATETIME"))
        audit_cols = {row[1] for row in conn.execute(text("PRAGMA table_info(admin_audit_logs)")).fetchall()}
        if audit_cols and "actor_role" not in audit_cols:
            conn.execute(text("ALTER TABLE admin_audit_logs ADD COLUMN actor_role VARCHAR(16)"))
        if audit_cols and "category" not in audit_cols:
            conn.execute(text("ALTER TABLE admin_audit_logs ADD COLUMN category VARCHAR(32)"))
        if audit_cols and "path" not in audit_cols:
            conn.execute(text("ALTER TABLE admin_audit_logs ADD COLUMN path VARCHAR(160)"))


def make_session_factory(database_url: str):
    engine = make_engine(database_url)
    Base.metadata.create_all(engine)
    migrate_schema(engine)
    return sessionmaker(bind=engine, expire_on_commit=False, future=True)
