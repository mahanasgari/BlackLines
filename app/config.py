from __future__ import annotations

from functools import lru_cache
from typing import Annotated

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict


def _parse_int_list(value: object, default: list[int] | None = None) -> list[int]:
    if value is None or value == "":
        return list(default or [])
    if isinstance(value, list):
        return [int(x) for x in value]
    return [int(part.strip()) for part in str(value).split(",") if part.strip()]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    bot_token: str = Field(alias="BOT_TOKEN")
    # Optional second bot (preferred for branding / notifications when set)
    main_bot_token: str | None = Field(default=None, alias="MAIN_BOT_TOKEN")
    admin_ids: Annotated[list[int], NoDecode] = Field(default_factory=list, alias="ADMIN_IDS")

    xui_base_url: str = Field(alias="XUI_BASE_URL")
    xui_api_token: str = Field(alias="XUI_API_TOKEN")
    xui_inbound_ids: Annotated[list[int], NoDecode] = Field(
        default_factory=lambda: [2, 3, 4, 5, 6],
        alias="XUI_INBOUND_IDS",
    )

    public_host: str = Field(default="shabash.cloudproducts.ir", alias="PUBLIC_HOST")
    public_ip: str = Field(default="46.31.79.157", alias="PUBLIC_IP")
    vpn_primary_label: str = Field(default="", alias="VPN_PRIMARY_LABEL")
    subscription_base_url: str = Field(default="", alias="SUBSCRIPTION_BASE_URL")

    payment_card: str = Field(default="تنظیم نشده", alias="PAYMENT_CARD")
    payment_card_name: str = Field(default="", alias="PAYMENT_CARD_NAME")
    payment_note: str = Field(
        default="پس از واریز، عکس رسید را از همین مینی‌اپ ارسال کنید.",
        alias="PAYMENT_NOTE",
    )

    database_url: str = Field(
        default="sqlite:////opt/3x-ui/vpn-bot-data/shop.db",
        alias="DATABASE_URL",
    )
    shop_name: str = Field(default="Black Lines VPN", alias="SHOP_NAME")
    miniapp_url: str = Field(
        default="https://shabash.cloudproducts.ir/shop/",
        alias="MINIAPP_URL",
    )
    miniapp_menu_text: str = Field(default="Open", alias="MINIAPP_MENU_TEXT")
    miniapp_short_name: str = Field(default="shop", alias="MINIAPP_SHORT_NAME")
    api_host: str = Field(default="127.0.0.1", alias="API_HOST")
    api_port: int = Field(default=8105, alias="API_PORT")
    # Require Telegram channel membership before bot / miniapp use
    force_join_channel: bool = Field(default=True, alias="FORCE_JOIN_CHANNEL")
    required_channel: str = Field(default="@Blackliness", alias="REQUIRED_CHANNEL")

    @field_validator("admin_ids", mode="before")
    @classmethod
    def _parse_admin_ids(cls, value: object) -> list[int]:
        return _parse_int_list(value, [])

    @field_validator("xui_inbound_ids", mode="before")
    @classmethod
    def _parse_inbound_ids(cls, value: object) -> list[int]:
        return _parse_int_list(value, [2, 3, 4, 5, 6])

    def is_admin(self, user_id: int | None) -> bool:
        return bool(user_id) and user_id in self.admin_ids

    @property
    def all_bot_tokens(self) -> list[str]:
        """Unique bot tokens — MainBot first when MAIN_BOT_TOKEN is set."""
        tokens: list[str] = []
        for raw in (self.main_bot_token, self.bot_token):
            token = (raw or "").strip()
            if token and token not in tokens:
                tokens.append(token)
        return tokens

    @property
    def primary_bot_token(self) -> str:
        tokens = self.all_bot_tokens
        return tokens[0] if tokens else self.bot_token

    @property
    def bot_roles(self) -> list[tuple[str, str]]:
        """(role, token) pairs for logging / multi-bot startup."""
        roles: list[tuple[str, str]] = []
        main = (self.main_bot_token or "").strip()
        secondary = (self.bot_token or "").strip()
        if main:
            roles.append(("MainBot", main))
        if secondary and secondary != main:
            roles.append(("Bot", secondary))
        elif secondary and not main:
            roles.append(("Bot", secondary))
        return roles

    @property
    def miniapp_url_normalized(self) -> str:
        """HTTPS mini app URL with trailing slash (required by Telegram WebApp)."""
        url = self.miniapp_url.strip()
        if not url:
            return ""
        if not url.endswith("/"):
            url += "/"
        return url

    @property
    def miniapp_menu_label(self) -> str:
        """Menu-bar Open label. Telegram accepts 1–16 chars; Persian is unreliable here."""
        text = self.miniapp_menu_text.strip()
        if not text or any("\u0600" <= ch <= "\u06ff" for ch in text):
            return "Open"
        return text[:16]


@lru_cache
def get_settings() -> Settings:
    return Settings()  # type: ignore[call-arg]
