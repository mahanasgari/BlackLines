import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/blacklines/core/format.dart';
import 'package:hiddify/features/blacklines/screens/common.dart';
import 'package:hiddify/features/blacklines/screens/config_picker.dart';
import 'package:hiddify/features/blacklines/ui/kit.dart';
import 'package:hiddify/features/blacklines/ui/tokens.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/settings/notifier/config_option/config_option_notifier.dart';
import 'package:hiddify/features/stats/notifier/stats_notifier.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Native connect screen: our UI, Hiddify engine underneath.
class ConnectScreen extends ConsumerWidget {
  const ConnectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Signed-in users pick from their configs; guests paste a subscription link.
    void onPickConfig() => openConfigPicker(context);
    final connection = ref.watch(connectionNotifierProvider);
    final profile = ref.watch(activeProfileProvider).valueOrNull;
    final requiresReconnect = ref.watch(configOptionNotifierProvider).valueOrNull == true;

    final status = connection.valueOrNull;
    final connected = status is Connected;
    final busy = status is Connecting || status is Disconnecting || connection.isLoading;

    String? failure;
    if (connection case AsyncError(:final error)) {
      failure = _describe(ref, error);
    } else if (status case Disconnected(:final connectionFailure?)) {
      failure = _describe(ref, connectionFailure);
    }

    Future<void> onTap() async {
      HapticFeedback.mediumImpact();
      final notifier = ref.read(connectionNotifierProvider.notifier);
      if (connected && requiresReconnect) {
        return notifier.reconnect(await ref.read(activeProfileProvider.future));
      }
      if (!connected && ref.read(activeProfileProvider).valueOrNull == null) {
        onPickConfig();
        return;
      }
      await notifier.toggleConnection();
    }

    final label = switch (status) {
      Connected() when requiresReconnect => 'اتصال مجدد لازم است',
      Connected() => 'متصل',
      Connecting() => 'در حال اتصال…',
      Disconnecting() => 'در حال قطع…',
      _ => 'قطع',
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const Gap(24),
        Center(child: _PowerButton(connected: connected, busy: busy, onTap: busy ? null : onTap)),
        const Gap(20),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: connected ? C.foreground : C.n400,
          ),
        ),
        const Gap(6),
        if (connected) const Center(child: _DelayChip()) else const Gap(32),
        if (failure != null) ...[
          const Gap(12),
          Panel(
            child: Row(
              children: [
                Icon(Icons.error_outline_rounded, color: C.red300, size: 20),
                const Gap(10),
                Expanded(child: Text(failure, style: TextStyle(fontSize: 13, color: C.n400))),
              ],
            ),
          ),
        ],
        const Gap(24),
        const _ModeSelector(),
        const Gap(8),
        _ActiveConfigCard(profile: profile, connected: connected, onTap: onPickConfig),
        const Gap(8),
        TgButton(
          label: 'افزودن لینک اشتراک',
          icon: Icons.add_link_rounded,
          variant: BtnVariant.outline,
          height: 40,
          fontSize: 13,
          onPressed: () => openAddLinkSheet(context),
        ),
        if (connected) ...[const Gap(12), const _TrafficCard()],
        const Gap(32),
        Text(
          'موتور اتصال: Hiddify · GPLv3',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: C.n600),
        ),
      ],
    );
  }

  String _describe(WidgetRef ref, Object error) {
    final t = ref.read(translationsProvider).valueOrNull;
    if (error is ConnectionFailure && t != null) {
      final p = error.present(t);
      return p.message == null ? p.type : '${p.type}\n${p.message}';
    }
    return error.toString();
  }
}

class _PowerButton extends StatefulWidget {
  const _PowerButton({required this.connected, required this.busy, this.onTap});

  final bool connected;
  final bool busy;
  final VoidCallback? onTap;

  @override
  State<_PowerButton> createState() => _PowerButtonState();
}

class _PowerButtonState extends State<_PowerButton> with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
    if (widget.busy) _spin.repeat();
  }

  @override
  void didUpdateWidget(_PowerButton old) {
    super.didUpdateWidget(old);
    if (widget.busy && !_spin.isAnimating) _spin.repeat();
    if (!widget.busy && _spin.isAnimating) _spin.stop();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const size = 196.0;
    final on = widget.connected;
    return Semantics(
      button: true,
      label: on ? 'قطع اتصال' : 'اتصال',
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 380),
                curve: Curves.easeOutCubic,
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: on
                      ? [BoxShadow(color: C.foreground.withValues(alpha: C.light ? 0.12 : 0.18), blurRadius: 60, spreadRadius: 4)]
                      : const [],
                  border: Border.all(color: on ? C.w(33) : C.w(12), width: 1.5),
                ),
              ),
              if (widget.busy)
                RotationTransition(
                  turns: _spin,
                  child: const SizedBox(
                    width: size,
                    height: size,
                    child: CustomPaint(painter: _ArcPainter()),
                  ),
                ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 380),
                curve: Curves.easeOutCubic,
                width: size - 40,
                height: size - 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on ? C.foreground : C.surfaceDeep,
                  border: Border.all(color: on ? Colors.transparent : C.w(12)),
                ),
                child: Icon(
                  Icons.power_settings_new_rounded,
                  size: 64,
                  color: on ? C.primaryFg : C.foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  const _ArcPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = C.foreground
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Offset.zero & size, 0, math.pi / 2, false, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DelayChip extends ConsumerWidget {
  const _DelayChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proxy = ref.watch(activeProxyNotifierProvider).valueOrNull;
    final delay = proxy?.urlTestDelay ?? 0;
    final text = switch (delay) {
      <= 0 => 'تست پینگ',
      > 65000 => 'پاسخی نیامد',
      _ => '$delay ms',
    };
    final color = switch (delay) {
      <= 0 => C.n400,
      > 65000 => C.red300,
      < 800 => C.emerald300,
      _ => C.amber300,
    };
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => ref.read(activeProxyNotifierProvider.notifier).urlTest('').catchError((_) {}),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.network_ping_rounded, size: 16, color: color),
            const Gap(6),
            Text(text, textDirection: TextDirection.ltr, style: TextStyle(fontSize: 13, color: color)),
          ],
        ),
      ),
    );
  }
}

class _ActiveConfigCard extends ConsumerWidget {
  const _ActiveConfigCard({required this.profile, required this.connected, required this.onTap});

  final ProfileEntity? profile;
  final bool connected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = profile;
    final server = connected ? ref.watch(activeProxyNotifierProvider).valueOrNull : null;
    return Panel(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: C.w(8), borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.dns_rounded, size: 20, color: C.foreground),
          ),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p?.name ?? 'کانفیگی انتخاب نشده',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const Gap(2),
                Text(
                  p == null ? 'برای انتخاب کانفیگ بزنید' : profileSubtitle(p),
                  style: TextStyle(fontSize: 12, color: C.n400),
                ),
                if (server != null) ...[
                  const Gap(2),
                  Text(
                    'سرور: ${serverLabel(server)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: C.n300),
                  ),
                ],
              ],
            ),
          ),
          Text('تغییر', style: TextStyle(fontSize: 12, color: C.n400)),
          Icon(Icons.chevron_left_rounded, color: C.n400),
        ],
      ),
    );
  }
}

class _TrafficCard extends ConsumerWidget {
  const _TrafficCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsNotifierProvider).valueOrNull;
    Widget cell(IconData icon, String title, String value) => Expanded(
          child: Column(
            children: [
              Icon(icon, size: 18, color: C.n400),
              const Gap(6),
              Text(value, textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w700)),
              const Gap(2),
              Text(title, style: TextStyle(fontSize: 11, color: C.n400)),
            ],
          ),
        );
    return Panel(
      child: Row(
        children: [
          cell(Icons.south_rounded, 'دانلود', '${bytesLabel(stats?.downlink.toInt() ?? 0)}/s'),
          cell(Icons.north_rounded, 'آپلود', '${bytesLabel(stats?.uplink.toInt() ?? 0)}/s'),
          cell(
            Icons.data_usage_rounded,
            'این نشست',
            bytesLabel((stats?.downlinkTotal.toInt() ?? 0) + (stats?.uplinkTotal.toInt() ?? 0)),
          ),
        ],
      ),
    );
  }
}

/// Paste / type a subscription URL and connect with it.
Future<void> openAddLinkSheet(BuildContext context) => showTgSheet(context, title: 'افزودن لینک اشتراک', builder: (_) => const _AddLink());

class _AddLink extends ConsumerStatefulWidget {
  const _AddLink();

  @override
  ConsumerState<_AddLink> createState() => _AddLinkState();
}

class _AddLinkState extends ConsumerState<_AddLink> {
  final _url = TextEditingController();
  String? error;

  @override
  void initState() {
    super.initState();
    Clipboard.getData(Clipboard.kTextPlain).then((d) {
      final text = d?.text?.trim() ?? '';
      if (mounted && _url.text.isEmpty && (text.startsWith('http://') || text.startsWith('https://'))) {
        setState(() => _url.text = text);
      }
    });
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  void _submit() {
    final url = _url.text.trim();
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      setState(() => error = 'لینک اشتراک باید با https:// شروع شود');
      return;
    }
    Navigator.of(context).pop();
    connectInApp(ref, url);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'لینک Subscription را از داشبورد، ربات یا فروشنده کپی کنید و اینجا بگذارید. کانفیگ به برنامه اضافه و وصل می‌شود.',
          style: t(12, c: C.n400, h: 1.6),
        ),
        const Gap(12),
        BLInput(controller: _url, hint: 'https://…/sub/…', ltr: true, maxLines: 3, minLines: 1, onChanged: (_) => setState(() => error = null)),
        if (error != null) ...[const Gap(8), Text(error!, style: t(11, c: C.red300))],
        const Gap(12),
        Row(
          children: [
            Expanded(
              child: TgButton(
                label: 'چسباندن',
                icon: Icons.content_paste_rounded,
                variant: BtnVariant.outline,
                onPressed: () async {
                  final d = await Clipboard.getData(Clipboard.kTextPlain);
                  setState(() => _url.text = d?.text?.trim() ?? '');
                },
              ),
            ),
            const Gap(8),
            Expanded(child: TgButton(label: 'افزودن و اتصال', icon: Icons.power_settings_new_rounded, onPressed: _url.text.trim().isEmpty ? null : _submit)),
          ],
        ),
      ],
    );
  }
}

/// VPN (TUN) or proxy: how the engine carries traffic on this device.
class _ModeSelector extends ConsumerWidget {
  const _ModeSelector();

  static String _label(ServiceMode m) => switch (m) {
        ServiceMode.tun => 'VPN (تونل)',
        ServiceMode.systemProxy => 'پراکسی سیستم',
        ServiceMode.proxy => 'فقط پراکسی',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(ConfigOptions.serviceMode);
    final port = ref.watch(ConfigOptions.mixedPort);
    final modes = [ServiceMode.tun, ServiceMode.systemProxy, ServiceMode.proxy].where(ServiceMode.choices.contains);
    final note = switch (mode) {
      ServiceMode.tun => PlatformUtils.isDesktop
          ? 'همه ترافیک سیستم از VPN عبور می‌کند. روی ویندوز برنامه را با «Run as administrator» و روی لینوکس با sudo اجرا کنید.'
          : 'همه برنامه‌ها از VPN عبور می‌کنند.',
      ServiceMode.systemProxy => 'مرورگر و برنامه‌هایی که از پراکسی سیستم پیروی می‌کنند وصل می‌شوند؛ نیاز به دسترسی ادمین ندارد.',
      ServiceMode.proxy => 'فقط پراکسی محلی روشن می‌شود و بقیه برنامه‌ها مستقیم وصل می‌شوند. آدرس زیر را به‌عنوان پراکسی HTTP یا SOCKS در برنامه دلخواه تنظیم کنید.',
    };
    return Panel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.tune_rounded, size: 16, color: C.n400),
              const Gap(6),
              Text('حالت اتصال', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.n300)),
            ],
          ),
          const Gap(10),
          Segmented<ServiceMode>(
            items: [for (final m in modes) (m, _label(m))],
            value: mode,
            onChanged: (m) => _change(ref, m),
          ),
          const Gap(8),
          Text(note, style: TextStyle(fontSize: 11, color: C.n500, height: 1.6)),
          if (mode == ServiceMode.proxy) ...[
            const Gap(8),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => copyText('127.0.0.1:$port', message: 'آدرس پراکسی کپی شد'),
                child: Ink(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: C.w(5), borderRadius: BorderRadius.circular(10), border: Border.all(color: C.w(12))),
                  child: Row(
                    children: [
                      Icon(Icons.copy_rounded, size: 14, color: C.n400),
                      const Spacer(),
                      Text('127.0.0.1:$port', textDirection: TextDirection.ltr, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.foreground)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // While connected, ConfigOptionNotifier restarts the tunnel in the new mode.
  Future<void> _change(WidgetRef ref, ServiceMode m) async {
    if (m == ref.read(ConfigOptions.serviceMode)) return;
    await ref.read(ConfigOptions.serviceMode.notifier).update(m);
  }
}
