#!/usr/bin/env python3
"""Configure Telegram Mini App menu button and print BotFather steps."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from app.config import get_settings
from app.miniapp_setup import setup_miniapp_via_http


def main() -> int:
    settings = get_settings()
    if not settings.bot_token:
        print("BOT_TOKEN is missing in .env", file=sys.stderr)
        return 1
    if not settings.miniapp_url:
        print("MINIAPP_URL is missing in .env", file=sys.stderr)
        return 1

    print(f"Setting Mini App menu button → {settings.miniapp_url}")
    result = setup_miniapp_via_http(settings)

    if result.get("ok"):
        print(f"✓ Menu button set for @{result['username']}")
        print("✓ Bot commands updated (/start, /open, /shop, /help)")
    else:
        print("✗ Setup failed — check BOT_TOKEN and try again", file=sys.stderr)
        return 1

    print()
    print("BotFather steps (for profile Mini App / t.me link):")
    for step in result.get("steps") or []:
        print(f"  {step}")
    print()
    print(f"Direct link (after BotFather /newapp): {result.get('direct_link')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
