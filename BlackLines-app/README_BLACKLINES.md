# BlackLines Android app (Hiddify fork)

GPLv3 fork of [hiddify/hiddify-app](https://github.com/hiddify/hiddify-app) branded as **BlackLines**, with shop API + in-app VPN auto-connect.

## Requirements

- Flutter **3.38.5+** (see `pubspec.yaml`)
- Android SDK
- Run on **your machine** (not the shop server)

## Setup

```bash
cd BlackLines-app
make android-prepare   # downloads core libs
flutter pub get
# regenerate translations if you edit assets/translations:
# dart run slang
flutter run --dart-define=API_BASE=https://shabash.cloudproducts.ir
```

Release APK:

```bash
flutter build apk --release --dart-define=API_BASE=https://shabash.cloudproducts.ir
```

## What we added

| Path | Role |
|------|------|
| `lib/features/blacklines/` | Shop API, Telegram login, shell UI, auto-connect |
| Home route | Replaced with `BlackLinesShellPage` (5 RTL tabs) |
| Branding | `BlackLines`, package `ir.cloudproducts.blacklines` |

**Auto-connect:** after login / buy / tap config → `upsertRemote(subscription_url)` → `setAsActive` → start tunnel.

## Backend (repo only until you ask to deploy)

Shop auth endpoints live in the parent repo (`app/app_auth.py`, etc.). Production must have them deployed before login works against live API.

## GPL

Keep this as a public fork of hiddify-app and do not publish under the Hiddify name/UI on app stores.
