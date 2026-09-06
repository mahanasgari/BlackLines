# Black Lines VPN Shop Bot

Telegram bot for selling and managing 3x-ui VPN subscriptions.

## Features

**Users**
- Browse plans and buy with card-to-card receipt upload
- Receive VLESS share links after admin approval
- View active subscriptions and re-fetch links

**Admins**
- Approve / reject payment receipts (auto-creates 3x-ui client)
- Pending orders, stats, broadcast, payment card settings
- `/setprice`, `/toggleplan`, `/disable`, `/extend`

## Setup

1. Create a bot with [@BotFather](https://t.me/BotFather) and copy the token.
2. Copy env file and fill values:

```bash
cd /root/Projects/VpnShopBot
cp .env.example .env
nano .env
```

Required:
- `BOT_TOKEN`
- `ADMIN_IDS` — your Telegram numeric user id(s), comma-separated
- `XUI_API_TOKEN` — from 3x-ui → Settings → API Tokens

3. Run with Docker:

```bash
docker compose up -d --build
docker compose logs -f
```

Or locally:

```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python main.py
```

## Admin commands

| Command | Description |
|---------|-------------|
| `/admin` | Admin menu |
| `/setprice PLAN_ID PRICE` | Change plan price (toman) |
| `/toggleplan PLAN_ID` | Enable/disable plan |
| `/disable EMAIL` | Disable a subscription on panel |
| `/extend EMAIL DAYS` | Add days to a client |

Default plans (edit prices after start):

1. ۱ ماهه — ۵۰ گیگ — ۱۵۰٬۰۰۰
2. ۱ ماهه — نامحدود — ۲۵۰٬۰۰۰
3. ۳ ماهه — نامحدود — ۶۵۰٬۰۰۰

## Mini App

URL: https://shabash.cloudproducts.ir/shop/

In [@BotFather](https://t.me/BotFather):
1. `/mybots` → your bot → **Bot Settings** → **Domain** → `shabash.cloudproducts.ir`
2. Optional: set Menu Button to the Mini App URL

Open the bot and tap **🚀 باز کردن فروشگاه**.


- Each user gets a unique invite link (`/start ref_CODE`)
- Default commission: **15%** of purchase (wallet credit)
- Wallet can discount the next order automatically
- Withdrawal requests go to admins for payout

Admin commands:
- `/setrefpercent 15` — commission percent
- `/setminwithdraw 100000` — minimum withdraw (toman)


- New customers are attached to inbound IDs in `XUI_INBOUND_IDS` (Reality + WS + HTTP camouflage).
- Share links from the panel use `localhost`; the bot rewrites them to `PUBLIC_IP` / `PUBLIC_HOST` (WS internal `10086` → public `443`).
- Payment card can also be updated in-bot: Admin → تنظیم کارت → `CARD|NAME|NOTE`
