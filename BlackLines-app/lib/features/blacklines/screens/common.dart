import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/features/blacklines/core/api.dart';
import 'package:hiddify/features/blacklines/notifier/auto_connect_service.dart';
import 'package:hiddify/features/blacklines/state/controller.dart';
import 'package:hiddify/features/blacklines/ui/kit.dart';
import 'package:hiddify/features/blacklines/ui/tokens.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// App.tsx `copy`.
Future<void> copyText(String text, {String message = 'کپی شد'}) async {
  await Clipboard.setData(ClipboardData(text: text));
  haptic();
  notify(message, ToastStatus.success);
}

Future<void> openExternal(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    await copyText(url, message: 'لینک کپی شد');
  }
}

/// Imports a subscription into the Hiddify engine and connects (our addition
/// to the mini app: configs connect inside this app instead of another client).
Future<void> connectInApp(WidgetRef ref, String subscriptionUrl, {String? name}) async {
  final c = ref.read(blControllerProvider);
  c.switchTab(BLTab.connect);
  notify('در حال افزودن کانفیگ و اتصال…');
  try {
    await ref.read(blackLinesAutoConnectProvider).importAndConnect(subscriptionUrl: subscriptionUrl, name: name);
  } catch (e) {
    notify('اتصال ناموفق بود: ${persianError(e)}', ToastStatus.error);
  }
}

/// editable-config-name.tsx.
class EditableConfigName extends StatefulWidget {
  const EditableConfigName({
    super.key,
    required this.name,
    required this.onSave,
    this.disabled = false,
    this.style,
  });

  final String name;
  final Future<void> Function(String label) onSave;
  final bool disabled;
  final TextStyle? style;

  @override
  State<EditableConfigName> createState() => _EditableConfigNameState();
}

class _EditableConfigNameState extends State<EditableConfigName> {
  bool editing = false;
  bool saving = false;
  late final _c = TextEditingController(text: widget.name);

  @override
  void didUpdateWidget(EditableConfigName old) {
    super.didUpdateWidget(old);
    if (!editing) _c.text = widget.name;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _commit() async {
    final next = _c.text.trim();
    if (next == widget.name.trim()) {
      setState(() => editing = false);
      return;
    }
    setState(() => saving = true);
    try {
      await widget.onSave(next);
      if (mounted) setState(() => editing = false);
    } catch (_) {
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget _iconBtn(IconData icon, Color color, VoidCallback? onTap, {bool bordered = true}) => SizedBox(
        width: 28,
        height: 28,
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: bordered ? BorderSide(color: C.w(15)) : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Icon(icon, size: 14, color: color),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (editing) {
      return Row(
        children: [
          Icon(Icons.edit_outlined, size: 14, color: C.sky300),
          const Gap(4),
          Expanded(
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: _c,
                autofocus: true,
                maxLength: 64,
                enabled: !saving && !widget.disabled,
                onSubmitted: (_) => _commit(),
                style: t(14, w: 600, c: C.white),
                decoration: InputDecoration(
                  counterText: '',
                  isDense: true,
                  filled: true,
                  fillColor: C.b(50),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: C.w(20))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: C.w(20))),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: C.a(C.sky300, 0.5)),
                  ),
                ),
              ),
            ),
          ),
          const Gap(4),
          _iconBtn(Icons.check_rounded, C.emerald300, saving || widget.disabled ? null : _commit),
          const Gap(4),
          _iconBtn(Icons.close_rounded, C.n400, saving ? null : () => setState(() => editing = false)),
        ],
      );
    }
    return Row(
      children: [
        _iconBtn(Icons.edit_outlined, C.n400, widget.disabled ? null : () => setState(() => editing = true), bordered: false),
        const Gap(6),
        Flexible(
          child: Text(
            widget.name.isEmpty ? 'بدون نام' : widget.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: widget.style ?? t(15, w: 600, c: C.white),
          ),
        ),
      ],
    );
  }
}

/// Usage bar from dashboard-config-cards.tsx.
class UsageBar extends StatelessWidget {
  const UsageBar({super.key, required this.usedLabel, required this.totalLabel, required this.percent, required this.hasTotal});

  final String usedLabel;
  final String totalLabel;
  final double percent;
  final bool hasTotal;

  @override
  Widget build(BuildContext context) {
    final pct = hasTotal ? percent.clamp(0, 100).toDouble() : 0.0;
    final color = pct >= 90
        ? C.a(C.red300, 0.9)
        : pct >= 70
            ? C.a(C.amber400, 0.85)
            : C.w(80);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$usedLabel / $totalLabel', textDirection: TextDirection.ltr, style: t(11, c: C.n400)),
        const Gap(4),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Stack(
            children: [
              Container(height: 6, color: C.w(10)),
              FractionallySizedBox(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: pct / 100,
                child: Container(height: 6, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999))),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
