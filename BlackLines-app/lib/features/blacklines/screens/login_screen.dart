import 'package:flutter/material.dart';
import 'package:hiddify/features/blacklines/state/controller.dart';
import 'package:hiddify/features/blacklines/ui/kit.dart';
import 'package:hiddify/features/blacklines/ui/tokens.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Signed-out screen: sign in through the Telegram bot (`/start app_<nonce>`).
class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(blControllerProvider);
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 512),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              Center(child: Image.asset(kBrandMark, height: 56, color: C.light ? C.foreground : null)),
              const Gap(16),
              Text('Black Lines', textAlign: TextAlign.center, style: t(26, w: 800)),
              const Gap(6),
              Text(
                'خرید، مدیریت و اتصال — همه در یک برنامه',
                textAlign: TextAlign.center,
                style: t(13, c: C.n400),
              ),
              const Gap(32),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('ورود به حساب', style: t(16, w: 600)),
                    const Gap(6),
                    Text(
                      'ورود از طریق ربات تلگرام انجام می‌شود: دکمه زیر را بزنید، در ربات «Start» را بزنید و به برنامه برگردید.',
                      style: t(13, c: C.n300, h: 1.7),
                    ),
                    const Gap(16),
                    TgButton(
                      label: 'ورود با تلگرام',
                      icon: Icons.send_rounded,
                      busy: c.loggingIn,
                      onPressed: c.startTelegramLogin,
                    ),
                    if (c.loggingIn) ...[
                      const Gap(8),
                      TgButton(label: 'انصراف', variant: BtnVariant.ghost, onPressed: c.cancelLogin),
                    ],
                    if (c.loginStatus != null) ...[
                      const Gap(10),
                      Text(c.loginStatus!, textAlign: TextAlign.center, style: t(12, c: C.n400, h: 1.6)),
                    ],
                    if (c.loginError != null) ...[
                      const Gap(10),
                      Callout(c.loginError!, tone: Tone.red, icon: Icons.error_outline_rounded),
                    ],
                  ],
                ),
              ),
              const Gap(12),
              TgButton(
                label: 'ادامه بدون ورود — فقط اتصال',
                icon: Icons.power_settings_new_rounded,
                variant: BtnVariant.outline,
                onPressed: c.loggingIn ? null : c.continueAsGuest,
              ),
              const Gap(6),
              Text(
                'بدون حساب می‌توانید لینک اشتراک خود را اضافه کنید و وصل شوید. خرید و مدیریت کانفیگ‌ها به ورود نیاز دارد.',
                textAlign: TextAlign.center,
                style: t(11, c: C.n500, h: 1.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
