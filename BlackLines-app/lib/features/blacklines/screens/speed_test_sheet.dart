import 'package:flutter/material.dart';
import 'package:hiddify/features/blacklines/core/format.dart';
import 'package:hiddify/features/blacklines/core/speed_test.dart';
import 'package:hiddify/features/blacklines/ui/kit.dart';
import 'package:hiddify/features/blacklines/ui/tokens.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Speed test with and without the VPN, side by side.
Future<void> openSpeedTest(BuildContext context) => showTgSheet(
      context,
      title: 'تست سرعت',
      description: 'سرعت اینترنت با VPN و بدون آن',
      builder: (_) => const _SpeedTestSheet(),
    );

enum _Phase { ping, download, upload }

class _Side {
  int? ping;
  double? down;
  double? up;
  _Phase? phase;
  String? error;
  String? server;

  void reset() {
    server = null;
    ping = null;
    down = null;
    up = null;
    error = null;
  }
}

class _SpeedTestSheet extends ConsumerStatefulWidget {
  const _SpeedTestSheet();

  @override
  ConsumerState<_SpeedTestSheet> createState() => _SpeedTestSheetState();
}

class _SpeedTestSheetState extends ConsumerState<_SpeedTestSheet> {
  final _vpn = _Side();
  final _direct = _Side();
  SpeedTest? _test;
  bool _busy = false;
  SpeedProvider _provider = SpeedProvider.cloudflare;

  static const _providerKey = 'bl_speed_provider';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final saved = SpeedProvider.values.where((v) => v.name == p.getString(_providerKey)).firstOrNull;
      if (saved != null && mounted) setState(() => _provider = saved);
    }).catchError((_) {});
  }

  void _setProvider(SpeedProvider p) {
    if (_busy || p == _provider) return;
    setState(() {
      _provider = p;
      _vpn.reset();
      _direct.reset();
    });
    SharedPreferences.getInstance().then((prefs) => prefs.setString(_providerKey, p.name)).catchError((_) => false);
  }

  bool get _connected => ref.read(connectionNotifierProvider).valueOrNull is Connected;

  @override
  void dispose() {
    _test?.cancel();
    super.dispose();
  }

  Future<void> _run({required bool viaVpn}) async {
    final side = viaVpn ? _vpn : _direct;
    // Through the engine's local mixed proxy = through the tunnel.
    final test = _test = SpeedTest(_provider, proxyPort: viaVpn ? ref.read(ConfigOptions.mixedPort) : null);
    setState(() {
      _busy = true;
      side
        ..reset()
        ..phase = _Phase.ping;
    });
    try {
      final ping = await test.ping();
      if (!mounted) return;
      setState(() => side
        ..ping = ping
        ..phase = _Phase.download);
      final down = await test.download((v) => mounted ? setState(() => side.down = v) : null);
      if (!mounted) return;
      setState(() => side
        ..down = down
        ..server = test.serverLabel
        ..phase = _Phase.upload);
      final up = await test.upload((v) => mounted ? setState(() => side.up = v) : null);
      if (mounted) setState(() => side.up = up);
    } catch (e) {
      debugPrint('[SpeedTest] ${viaVpn ? 'vpn' : 'direct'}: $e');
      if (mounted) setState(() => side.error = side.ping == null ? 'در دسترس نیست' : 'تست کامل نشد');
    } finally {
      if (mounted) {
        setState(() {
          side.phase = null;
          _busy = false;
        });
      }
    }
  }

  Future<void> _runBoth() async {
    if (_connected) await _run(viaVpn: true);
    if (mounted) await _run(viaVpn: false);
  }

  @override
  Widget build(BuildContext context) {
    final connected = ref.watch(connectionNotifierProvider).valueOrNull is Connected;
    final mlab = _provider == SpeedProvider.mlab;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Segmented<SpeedProvider>(
          items: const [(SpeedProvider.cloudflare, 'Cloudflare'), (SpeedProvider.mlab, 'M-Lab')],
          value: _provider,
          onChanged: _setProvider,
        ),
        const Gap(10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _card(
                'با VPN',
                _vpn,
                note: connected ? null : 'برای تست با VPN ابتدا وصل شوید',
                onRun: connected && !_busy ? () => _run(viaVpn: true) : null,
              ),
            ),
            const Gap(8),
            Expanded(child: _card('بدون VPN', _direct, onRun: _busy ? null : () => _run(viaVpn: false))),
          ],
        ),
        const Gap(12),
        TgButton(
          label: _busy ? 'در حال تست…' : (connected ? 'تست هر دو' : 'تست بدون VPN'),
          icon: _busy ? null : Icons.speed_rounded,
          busy: _busy,
          onPressed: _busy ? null : _runBoth,
        ),
        const Gap(6),
        Text(
          mlab ? 'نزدیک‌ترین سرور M-Lab · هر مرحله حداکثر ۱۰ ثانیه' : 'سرور Cloudflare · هر مرحله حداکثر ۷ ثانیه',
          textAlign: TextAlign.center,
          style: t(10, c: C.n500),
        ),
        if (mlab) ...[
          const Gap(2),
          Text(
            'M-Lab نتایج همه تست‌ها، از جمله آدرس IP، را به‌صورت عمومی منتشر می‌کند.',
            textAlign: TextAlign.center,
            style: t(10, c: C.n500, h: 1.5),
          ),
        ],
      ],
    );
  }

  Widget _card(String title, _Side s, {String? note, VoidCallback? onRun}) {
    String mbps(double? v) => v == null ? '—' : '${faDigits(v.toStringAsFixed(v < 10 ? 1 : 0))} Mbps';
    return Panel(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: t(13, w: 700))),
              SizedBox(
                width: 32,
                height: 32,
                child: s.phase != null
                    ? Padding(padding: const EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2, color: C.foreground))
                    : IconButton(
                        padding: EdgeInsets.zero,
                        tooltip: 'تست',
                        icon: Icon(Icons.play_arrow_rounded, size: 20, color: onRun == null ? C.n600 : C.foreground),
                        onPressed: onRun,
                      ),
              ),
            ],
          ),
          if (s.server != null) Text(s.server!, textDirection: TextDirection.ltr, textAlign: TextAlign.end, style: t(10, c: C.n500)),
          const Gap(6),
          _metric('پینگ', s.ping == null ? '—' : '${faNum(s.ping!)} ms', active: s.phase == _Phase.ping),
          _metric('دانلود', mbps(s.down), active: s.phase == _Phase.download),
          _metric('آپلود', mbps(s.up), active: s.phase == _Phase.upload),
          if (s.error != null) ...[const Gap(4), Text(s.error!, style: t(11, c: C.red300))],
          if (note != null && s.error == null) ...[const Gap(4), Text(note, style: t(10, c: C.n500, h: 1.5))],
        ],
      ),
    );
  }

  Widget _metric(String label, String value, {bool active = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Text(label, style: t(11, c: active ? C.foreground : C.n400)),
            const Spacer(),
            Text(value, textDirection: TextDirection.ltr, style: t(13, w: 600, c: active ? C.foreground : C.n200)),
          ],
        ),
      );
}
