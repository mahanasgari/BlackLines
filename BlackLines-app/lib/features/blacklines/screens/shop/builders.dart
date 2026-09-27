import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hiddify/features/blacklines/core/api.dart';
import 'package:hiddify/features/blacklines/core/format.dart';
import 'package:hiddify/features/blacklines/core/json.dart';
import 'package:hiddify/features/blacklines/screens/common.dart';
import 'package:hiddify/features/blacklines/state/controller.dart';
import 'package:hiddify/features/blacklines/ui/kit.dart';
import 'package:hiddify/features/blacklines/ui/tokens.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

int _clamp(int n, int min, int max) => n < min ? min : (n > max ? max : n);

/// `PresetChip` (rounded-lg, white/15 when active).
class PresetChip extends StatelessWidget {
  const PresetChip({super.key, required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        haptic();
        onTap();
      },
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: active ? C.w(15) : C.b(30),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? C.w(30) : C.w(10)),
        ),
        child: Center(widthFactor: 1, child: Text(label, style: t(11, w: 500, c: active ? C.white : C.n400))),
      ),
    );
  }
}

/// `FieldControl`: label + number box + slider + min/max.
class FieldControl extends StatefulWidget {
  const FieldControl({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.suffix,
    required this.onChanged,
    this.accent,
    this.showRange = true,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final String suffix;
  final ValueChanged<int> onChanged;
  final Color? accent;
  final bool showRange;

  @override
  State<FieldControl> createState() => _FieldControlState();
}

class _FieldControlState extends State<FieldControl> {
  late final _c = TextEditingController(text: '${widget.value}');

  @override
  void didUpdateWidget(FieldControl old) {
    super.didUpdateWidget(old);
    if (int.tryParse(_c.text) != widget.value) _c.text = '${widget.value}';
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(widget.label, style: t(12, c: C.n400))),
            SizedBox(
              width: 64,
              height: 32,
              child: TextField(
                controller: _c,
                textAlign: TextAlign.center,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.number,
                style: t(14, c: C.white),
                onChanged: (v) {
                  final n = parseAmountInput(v);
                  widget.onChanged(_clamp(n == 0 ? widget.min : n, widget.min, widget.max));
                },
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: C.b(40),
                  contentPadding: const EdgeInsets.symmetric(vertical: 7),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: C.w(12))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: C.w(12))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: C.w(25))),
                ),
              ),
            ),
            const Gap(6),
            Text(widget.suffix, style: t(11, c: C.n500)),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 5,
            activeTrackColor: widget.accent ?? C.white,
            inactiveTrackColor: C.w(12),
            thumbColor: widget.accent ?? C.white,
            overlayColor: C.a(widget.accent ?? C.white, 0.12),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          ),
          child: Slider(
            value: widget.value.clamp(widget.min, widget.max).toDouble(),
            min: widget.min.toDouble(),
            max: widget.max <= widget.min ? widget.min + 1.0 : widget.max.toDouble(),
            onChanged: (v) => widget.onChanged(v.round()),
          ),
        ),
        if (widget.showRange)
          Row(
            children: [
              Text('${faNum(widget.min)} ${widget.suffix}', style: t(10, c: C.n600)),
              const Spacer(),
              Text('${faNum(widget.max)} ${widget.suffix}', style: t(10, c: C.n600)),
            ],
          ),
      ],
    );
  }
}

/// Price box shared by the custom / traffic builders.
class QuoteBox extends StatelessWidget {
  const QuoteBox({super.key, required this.quote, required this.loading, this.error, this.caption});

  final J? quote;
  final bool loading;
  final String? error;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final q = quote;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: C.b(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: C.w(10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (loading && q == null)
            Text('در حال محاسبه قیمت…', textAlign: TextAlign.center, style: t(11, c: C.n500))
          else if (q != null) ...[
            Text(caption ?? q.s('title'), style: t(11, c: C.n500)),
            const Gap(4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: q.i('pro_discount_percent') > 0 && q.i('charge_toman') < q.i('price_toman')
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(q.s('price_label'), style: t(10, c: C.n500, deco: TextDecoration.lineThrough)),
                            Text(q.s('charge_label'), style: t(18, w: 700, c: C.emerald300)),
                            if (caption == null)
                              Text('Pro · ${faNum(q.i('pro_discount_percent'))}٪ تخفیف', style: t(10, c: C.a(C.emerald400, 0.9))),
                          ],
                        )
                      : Text(q.s('charge_label'), style: t(18, w: 700)),
                ),
                if (q.i('pay_after_wallet') < q.i('charge_toman'))
                  Text('با کیف‌پول: ${priceText(q.i('pay_after_wallet'))}', style: t(10, c: C.n500)),
              ],
            ),
          ],
          if (error != null) ...[const Gap(8), Text(error!, style: t(11, c: C.red300))],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.icon, required this.color, required this.title, required this.text});

  final IconData icon;
  final Color color;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 16, color: color)),
        const Gap(8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: t(15, w: 600, c: C.white)),
              const Gap(2),
              Text(text, style: t(11, c: C.n400, h: 1.6)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Disabled extends StatelessWidget {
  const _Disabled(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        decoration: BoxDecoration(
          color: C.b(30),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: C.w(10)),
        ),
        child: Text(text, textAlign: TextAlign.center, style: t(14, c: C.n400)),
      );
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Text('در حال بارگذاری…', textAlign: TextAlign.center, style: t(14, c: C.n500)),
      );
}

// ---------------------------------------------------------------------------
// custom-package-builder.tsx
// ---------------------------------------------------------------------------

class CustomPackageBuilder extends ConsumerStatefulWidget {
  const CustomPackageBuilder({super.key, this.targetSubscriptionId, this.onCheckout});

  /// Renew mode (subscription detail): orders directly instead of review.
  final int? targetSubscriptionId;
  final Future<void> Function(J order)? onCheckout;

  @override
  ConsumerState<CustomPackageBuilder> createState() => _CustomPackageBuilderState();
}

class _CustomPackageBuilderState extends ConsumerState<CustomPackageBuilder> {
  J? opts;
  int days = 30;
  int gb = 50;
  int limitIp = 2;
  bool unlimited = false;
  int familySize = 1;
  J? quote;
  bool quoteLoading = false;
  String? error;
  Timer? _debounce;

  bool get isRenew => widget.targetSubscriptionId != null;

  @override
  void initState() {
    super.initState();
    ref.read(blControllerProvider).api.customOptions().then((d) {
      if (!mounted) return;
      setState(() {
        opts = d;
        days = _clamp(30, d.i('min_days'), d.i('max_days'));
        gb = _clamp(50, d.i('min_gb'), d.i('max_gb'));
        limitIp = _clamp(2, d.i('min_ip'), d.i('max_ip'));
      });
      _requote();
    }).catchError((Object e) {
      if (mounted) setState(() => error = persianError(e));
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _update(void Function() fn) {
    setState(fn);
    _requote();
  }

  void _requote() {
    if (!(opts?.b('enabled') ?? false)) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      setState(() {
        quoteLoading = true;
        error = null;
      });
      try {
        final q = await ref.read(blControllerProvider).api.customQuote({
          'duration_days': days,
          'traffic_gb': gb,
          'limit_ip': limitIp,
          'unlimited': unlimited,
          'family_size': isRenew ? 1 : familySize,
        });
        if (mounted) setState(() => quote = q);
      } catch (e) {
        if (mounted) {
          setState(() {
            quote = null;
            error = persianError(e);
          });
        }
      } finally {
        if (mounted) setState(() => quoteLoading = false);
      }
    });
  }

  Future<void> _buy() async {
    final c = ref.read(blControllerProvider);
    haptic('medium');
    if (!isRenew) {
      c.setPurchaseDraft(
        PurchaseDraft.custom(
          title: quote?.text('title') ?? 'پکیج سفارشی',
          durationDays: days,
          trafficGb: gb,
          limitIp: limitIp,
          unlimited: unlimited,
          familySize: familySize,
          chargeLabel: quote?.text('charge_label'),
        ),
      );
      return;
    }
    try {
      final order = await c.api.customOrder({
        'duration_days': days,
        'traffic_gb': gb,
        'limit_ip': limitIp,
        'unlimited': unlimited,
        'target_subscription_id': widget.targetSubscriptionId,
        'family_size': 1,
      });
      await widget.onCheckout?.call(order);
    } catch (e) {
      setState(() => error = persianError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(blControllerProvider);
    final o = opts;
    if (o == null) return error != null ? _Disabled(error!) : const _Loading();
    if (!o.b('enabled')) return const _Disabled('ساخت پکیج سفارشی فعلاً غیرفعال است.');
    final dayPresets = [7, 30, 90, 180].where((d) => d >= o.i('min_days') && d <= o.i('max_days'));
    final gbPresets = [1, 5, 10, 50, 100, 200, 500].where((g) => g >= o.i('min_gb') && g <= o.i('max_gb'));
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            icon: Icons.auto_awesome,
            color: C.amber300,
            title: isRenew ? 'تمدید با پکیج دلخواه' : 'ساخت پکیج دلخواه',
            text: 'مدت، حجم و تعداد دستگاه را خودتان انتخاب کنید. قیمت لحظه‌ای محاسبه می‌شود.',
          ),
          const Gap(16),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final d in dayPresets) PresetChip(label: '${faNum(d)} روز', active: days == d, onTap: () => _update(() => days = d)),
            ],
          ),
          const Gap(8),
          FieldControl(
            label: 'مدت اشتراک',
            value: days,
            min: o.i('min_days'),
            max: o.i('max_days'),
            suffix: 'روز',
            onChanged: (v) => _update(() => days = v),
          ),
          const Gap(16),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final g in gbPresets)
                PresetChip(
                  label: '${faNum(g)} GB',
                  active: !unlimited && gb == g,
                  onTap: () => _update(() {
                    unlimited = false;
                    gb = g;
                  }),
                ),
              if (o.b('unlimited_allowed') || c.isPro)
                PresetChip(label: 'نامحدود', active: unlimited, onTap: () => _update(() => unlimited = !unlimited)),
            ],
          ),
          const Gap(8),
          if (unlimited)
            const Callout('حجم نامحدود فعال است — مخصوص اعضای Pro', tone: Tone.amber)
          else
            FieldControl(
              label: 'حجم ترافیک',
              value: gb,
              min: o.i('min_gb'),
              max: o.i('max_gb'),
              suffix: 'GB',
              onChanged: (v) => _update(() {
                unlimited = false;
                gb = v;
              }),
            ),
          const Gap(16),
          FieldControl(
            label: 'تعداد دستگاه (IP)',
            value: limitIp,
            min: o.i('min_ip'),
            max: o.i('max_ip'),
            suffix: 'دستگاه',
            onChanged: (v) => _update(() => limitIp = v),
          ),
          if (!isRenew) ...[
            const Gap(16),
            FamilyPackPanel(familySize: familySize, onChanged: (n) => _update(() => familySize = n), disabled: c.busy),
          ],
          const Gap(16),
          QuoteBox(quote: quote, loading: quoteLoading, error: error),
          if (!c.isPro && (quote?.i('pro_discount_percent') ?? 0) > 0) ...[
            const Gap(8),
            Text('با Pro ارزان‌تر — دکمه Pro در بالا', style: t(11, c: C.a(C.amber400, 0.9))),
          ],
          const Gap(16),
          TgButton(
            label: isRenew
                ? 'تمدید سفارشی و پرداخت'
                : familySize > 1
                    ? 'خرید پکیج خانواده · ${faNum(familySize)} کانفیگ'
                    : 'خرید پکیج سفارشی',
            onPressed: c.busy || quoteLoading || quote == null ? null : _buy,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// family-pack-panel.tsx
// ---------------------------------------------------------------------------

class FamilyPackPanel extends ConsumerStatefulWidget {
  const FamilyPackPanel({super.key, required this.familySize, required this.onChanged, this.disabled = false});

  final int familySize;
  final ValueChanged<int> onChanged;
  final bool disabled;

  @override
  ConsumerState<FamilyPackPanel> createState() => _FamilyPackPanelState();
}

class _FamilyPackPanelState extends ConsumerState<FamilyPackPanel> {
  static J? _cache;
  J? opts = _cache;

  @override
  void initState() {
    super.initState();
    ref.read(blControllerProvider).api.growthOptions().then((r) {
      _cache = r.obj('family');
      if (mounted) setState(() => opts = _cache);
    }).catchError((_) {});
  }

  Widget _toggle(IconData icon, String label, bool active, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: widget.disabled
              ? null
              : () {
                  haptic();
                  onTap();
                },
          child: Container(
            height: 40,
            decoration: BoxDecoration(color: active ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(8)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: active ? Colors.black : C.n400),
                const Gap(6),
                Text(label, style: t(12, w: 600, c: active ? Colors.black : C.n400)),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final o = opts;
    final maxSize = (o?.b('enabled') ?? false) ? o!.i('max_size') : 1;
    if (maxSize <= 1) return const SizedBox.shrink();
    final size = widget.familySize;
    final enabled = size > 1;
    final children = (size - 1).clamp(0, 99);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: C.b(35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: C.w(12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('چند نفر وصل می‌شوند؟', style: t(14, w: 600, c: C.white)),
          const Gap(2),
          Text('یک کانفیگ برای خودت، یا چند کانفیگ جدا برای خانواده.', style: t(11, c: C.n400, h: 1.6)),
          const Gap(12),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: C.b(40),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: C.w(10)),
            ),
            child: Row(
              children: [
                _toggle(Icons.person_outline_rounded, 'یک نفر', !enabled, () => widget.onChanged(1)),
                const Gap(4),
                _toggle(Icons.home_outlined, 'خانواده', enabled, () => widget.onChanged(size < 2 ? 2 : size)),
              ],
            ),
          ),
          const Gap(12),
          if (!enabled)
            Text('یک کانفیگ ساخته می‌شود و لینک‌ها مال همان نفر است.', style: t(11, c: C.n500, h: 1.6))
          else ...[
            StepList(
              tone: Tone.sky,
              steps: const [
                (Icons.account_balance_wallet_outlined, 'یک‌بار پرداخت می‌کنی — به‌ازای هر نفر یک کانفیگ جدا می‌آید'),
                (Icons.group_outlined, 'اولی والد است، بقیه فرزند — همه روی داشبورد تو می‌مانند'),
                (Icons.send_outlined, 'هر لینک را جدا برای همان نفر بفرست'),
                (Icons.shield_outlined, 'از کانفیگ والد می‌توانی سایت‌های فرزند را محدود کنی'),
              ],
            ),
            const Gap(12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: C.w(5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: C.w(10)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('تعداد کانفیگ', style: t(12, w: 500, c: C.n100)),
                        Text('۱ والد + ${faNum(children)} فرزند', style: t(10, c: C.n500)),
                      ],
                    ),
                  ),
                  _SquareBtn('−', widget.disabled || size <= 2 ? null : () => widget.onChanged(size - 1)),
                  SizedBox(width: 28, child: Text(faNum(size), textAlign: TextAlign.center, style: t(14, w: 600))),
                  _SquareBtn('+', widget.disabled || size >= maxSize ? null : () => widget.onChanged(size + 1)),
                ],
              ),
            ),
            const Gap(12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: C.w(5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: C.w(10)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('بعد از تایید روی داشبورد تو', style: t(10, c: C.n500)),
                  const Gap(2),
                  Text('${faNum(size)} کانفیگ جدا · ۱ والد + ${faNum(children)} فرزند', style: t(14, w: 600, c: C.white)),
                  const Gap(4),
                  Text('مبلغ نهایی و هر تخفیف، هنگام خرید محاسبه می‌شود.', style: t(11, c: C.n400, h: 1.6)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SquareBtn extends StatelessWidget {
  const _SquareBtn(this.label, this.onTap);

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Material(
            color: C.b(40),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: C.w(15))),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onTap == null
                  ? null
                  : () {
                      haptic();
                      onTap!();
                    },
              child: Center(child: Text(label, style: t(16))),
            ),
          ),
        ),
      );
}

/// Numbered steps with icons (family / buy-for-others explainers).
class StepList extends StatelessWidget {
  const StepList({super.key, required this.steps, this.tone = Tone.sky});

  final List<(IconData, String)> steps;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, border, fg) = toneColors(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: C.a(bg, 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: C.a(border, 0.8)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == steps.length - 1 ? 0 : 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: bg,
                      border: Border.all(color: border),
                    ),
                    child: Text(faNum(i + 1), style: t(10, w: 700, c: C.n200)),
                  ),
                  const Gap(8),
                  Padding(padding: const EdgeInsets.only(top: 2), child: Icon(steps[i].$1, size: 14, color: C.a(fg, 0.8))),
                  const Gap(8),
                  Expanded(child: Text(steps[i].$2, style: t(11, c: C.n200, h: 1.6))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// payg-package-builder.tsx (مصرفی ابری)
// ---------------------------------------------------------------------------

class PaygCloudBuilder extends ConsumerStatefulWidget {
  const PaygCloudBuilder({super.key, required this.onTopup, this.compact = false});

  final VoidCallback onTopup;
  final bool compact;

  @override
  ConsumerState<PaygCloudBuilder> createState() => _PaygCloudBuilderState();
}

class _PaygCloudBuilderState extends ConsumerState<PaygCloudBuilder> {
  J? status;
  bool loading = true;
  bool acting = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await ref.read(blControllerProvider).api.paygStatus();
      if (mounted) setState(() => status = s);
    } catch (e) {
      if (mounted) setState(() => error = persianError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _act(Future<J> Function() fn, {bool activated = false}) async {
    haptic('medium');
    setState(() {
      acting = true;
      error = null;
    });
    try {
      final s = await fn();
      setState(() => status = s);
      if (activated) {
        final c = ref.read(blControllerProvider);
        notify('کانفیگ مصرفی فعال شد', ToastStatus.success);
        await c.refreshDashboard();
        c.switchTab(BLTab.subs);
      }
    } catch (e) {
      setState(() => error = persianError(e));
    } finally {
      if (mounted) setState(() => acting = false);
    }
  }

  Widget _cell(String label, String value, {Color? color, String? strike}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: C.b(30),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: C.w(10)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: t(10, c: C.n500)),
            const Gap(2),
            Text(value, style: t(14, w: 600, c: color)),
            if (strike != null) Text(strike, style: t(10, c: C.n500, deco: TextDecoration.lineThrough)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(blControllerProvider);
    final s = status;
    if (loading && s == null) return const _Loading();
    if (s == null || !s.b('enabled')) return _Disabled(error ?? 'پرداخت مصرفی فعلاً غیرفعال است.');
    final sub = s.objOrNull('subscription');
    final disabled = c.busy || acting;
    final api = c.api;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.compact) ...[
            _Header(
              icon: Icons.speed_rounded,
              color: C.sky300,
              title: 'مصرفی ابری',
              text:
                  'کیف‌پول را شارژ کنید، کانفیگ بگیرید، و فقط به‌اندازه مصرف واقعی پرداخت کنید. اگر ۱۰۰ مگ استفاده کنید، فقط قیمت همان ۱۰۰ مگ کسر می‌شود.',
            ),
            const Gap(16),
          ],
          Row(
            children: [
              Expanded(
                child: _cell(
                  'قیمت هر گیگ',
                  s.s('unit_price_label'),
                  color: C.sky100,
                  strike: s.i('pro_discount_percent') > 0 && s.i('unit_price_toman') < s.i('price_per_gb_toman')
                      ? s.s('price_per_gb_label')
                      : null,
                ),
              ),
              const Gap(8),
              Expanded(child: _cell('مثال ۱۰۰ مگ', s.s('example_100mb_label'), color: C.emerald200)),
            ],
          ),
          const Gap(8),
          Row(
            children: [
              Expanded(child: _cell('موجودی کیف‌پول', s.s('wallet_label'))),
              const Gap(8),
              Expanded(child: _cell('حجم تقریبی باقی‌مانده', s.s('remaining_label'))),
            ],
          ),
          const Gap(16),
          if (sub != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: C.a(C.sky500, 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: C.a(C.sky500, 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(sub.text('label') ?? sub.s('plan_title'), style: t(12, w: 600, c: C.sky100))),
                      Text(
                        s.b('user_paused')
                            ? 'غیرفعال (دستی)'
                            : s.b('suspended')
                                ? 'قطع شده'
                                : sub.b('enabled')
                                    ? 'فعال'
                                    : 'غیرفعال',
                        style: t(10, c: C.n400),
                      ),
                    ],
                  ),
                  const Gap(8),
                  Row(
                    children: [
                      Expanded(child: Text('مصرف شده: ${s.s('used_label')}', style: t(11, c: C.n300))),
                      Expanded(child: Text('کسر شده: ${s.s('billed_label')}', style: t(11, c: C.n300))),
                    ],
                  ),
                  const Gap(8),
                  Text(
                    'لینک کانفیگ در داشبورد است. با هر مصرف، مبلغ همان حجم از کیف‌پول کم می‌شود.',
                    style: t(10, c: C.n500, h: 1.6),
                  ),
                  if (s.b('suspended')) ...[
                    const Gap(6),
                    Text('کانفیگ به‌خاطر موجودی ناکافی قطع شده. بعد از شارژ کیف‌پول دوباره وصل می‌شود.', style: t(11, c: C.amber300)),
                  ],
                  if (s.b('user_paused')) ...[
                    const Gap(6),
                    Text('خودتان غیرفعال کرده‌اید — با دکمه فعال‌سازی دوباره وصل می‌شود.', style: t(11, c: C.n400)),
                  ],
                  const Gap(8),
                  Row(
                    children: [
                      Expanded(
                        child: sub.b('enabled')
                            ? TgButton(
                                label: 'غیرفعال کردن',
                                variant: BtnVariant.outline,
                                foreground: C.red300,
                                onPressed: disabled ? null : () => _act(() => api.paygSetEnabled(false)),
                              )
                            : TgButton(
                                label: 'فعال کردن',
                                onPressed: disabled || s.b('needs_topup') ? null : () => _act(() => api.paygSetEnabled(true)),
                              ),
                      ),
                      const Gap(8),
                      Expanded(
                        child: TgButton(
                          label: 'شارژ کیف‌پول',
                          icon: Icons.account_balance_wallet_outlined,
                          variant: BtnVariant.outline,
                          onPressed: disabled ? null : widget.onTopup,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: C.b(30),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: C.w(10)),
              ),
              child: Text(
                'حداقل موجودی برای فعال‌سازی: ${s.s('min_wallet_label')} · حداکثر ${faNum(s.i('limit_ip'))} دستگاه',
                style: t(11, c: C.n400, h: 1.6),
              ),
            ),
          if (!c.isPro && s.i('pro_discount_percent') > 0) ...[
            const Gap(10),
            Text('با Pro هر گیگ ارزان‌تر حساب می‌شود', style: t(11, c: C.a(C.amber400, 0.9))),
          ],
          if (error != null) ...[const Gap(8), Text(error!, style: t(11, c: C.red300))],
          if (sub == null) ...[
            const Gap(16),
            if (s.b('can_activate'))
              TgButton(
                label: 'فعال‌سازی کانفیگ مصرفی',
                onPressed: disabled ? null : () => _act(api.paygActivate, activated: true),
              )
            else
              TgButton(
                label: 'شارژ کیف‌پول و ادامه',
                icon: Icons.account_balance_wallet_outlined,
                onPressed: disabled ? null : widget.onTopup,
              ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// payg-traffic-builder.tsx (خرید حجم)
// ---------------------------------------------------------------------------

class PaygTrafficBuilder extends ConsumerStatefulWidget {
  const PaygTrafficBuilder({super.key, this.lockTargetId, this.onCheckout});

  final int? lockTargetId;
  final Future<void> Function(J order)? onCheckout;

  @override
  ConsumerState<PaygTrafficBuilder> createState() => _PaygTrafficBuilderState();
}

class _PaygTrafficBuilderState extends ConsumerState<PaygTrafficBuilder> {
  J? opts;
  int gb = 10;
  int limitIp = 1;
  int targetId = 0;
  J? quote;
  bool quoteLoading = false;
  String? error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    ref.read(blControllerProvider).api.paygOptions().then((d) {
      if (!mounted) return;
      setState(() {
        opts = d;
        gb = _clamp(10, d.i('min_gb'), d.i('max_gb'));
        limitIp = _clamp(1, d.i('min_ip'), d.i('max_ip'));
        targetId = widget.lockTargetId ?? 0;
      });
      _requote();
    }).catchError((Object e) {
      if (mounted) setState(() => error = persianError(e));
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _update(void Function() fn) {
    setState(fn);
    _requote();
  }

  void _requote() {
    if (!(opts?.b('enabled') ?? false)) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      setState(() {
        quoteLoading = true;
        error = null;
      });
      try {
        final q = await ref.read(blControllerProvider).api.paygQuote({
          'traffic_gb': gb,
          'limit_ip': limitIp,
          'target_subscription_id': targetId == 0 ? null : targetId,
        });
        if (mounted) setState(() => quote = q);
      } catch (e) {
        if (mounted) {
          setState(() {
            quote = null;
            error = persianError(e);
          });
        }
      } finally {
        if (mounted) setState(() => quoteLoading = false);
      }
    });
  }

  Future<void> _buy() async {
    final c = ref.read(blControllerProvider);
    haptic('medium');
    if (targetId == 0) {
      c.setPurchaseDraft(
        PurchaseDraft.payg(
          title: quote?.text('title') ?? 'خرید حجم',
          trafficGb: gb,
          limitIp: limitIp,
          chargeLabel: quote?.text('charge_label'),
        ),
      );
      return;
    }
    try {
      final order = await c.api.paygOrder({'traffic_gb': gb, 'limit_ip': limitIp, 'target_subscription_id': targetId});
      if (widget.onCheckout != null) {
        await widget.onCheckout!(order);
      } else {
        await c.completePlanOrder(order);
      }
    } catch (e) {
      setState(() => error = persianError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(blControllerProvider);
    final o = opts;
    if (o == null) return error != null ? _Disabled(error!) : const _Loading();
    if (!o.b('enabled')) return const _Disabled('خرید حجم فعلاً غیرفعال است.');
    final existing = o.objs('existing');
    final gbPresets = [5, 10, 20, 50, 100].where((g) => g >= o.i('min_gb') && g <= o.i('max_gb'));
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            icon: Icons.speed_rounded,
            color: C.violet300,
            title: 'خرید حجم',
            text: 'فقط ترافیک بخرید — بدون محدودیت زمانی (قیمت بالاتر از مصرف ابری). هر وقت تمام شد دوباره شارژ کنید.',
          ),
          if (widget.lockTargetId == null && existing.isNotEmpty) ...[
            const Gap(16),
            Text('افزودن به کانفیگ فعلی', style: t(12, c: C.n400)),
            const Gap(6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: C.b(40),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: C.w(12)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: targetId,
                  isExpanded: true,
                  dropdownColor: C.sheetElevated,
                  style: t(14),
                  items: [
                    const DropdownMenuItem(value: 0, child: Text('کانفیگ حجم‌دار جدید')),
                    for (final s in existing)
                      DropdownMenuItem(
                        value: s.i('id'),
                        child: Text('${s.text('label') ?? s.s('plan_title')} · ${s.s('email')}', overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => _update(() => targetId = v ?? 0),
                ),
              ),
            ),
          ],
          const Gap(16),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final g in gbPresets) PresetChip(label: '${faNum(g)} GB', active: gb == g, onTap: () => _update(() => gb = g))],
          ),
          const Gap(8),
          FieldControl(
            label: 'حجم ترافیک',
            value: gb,
            min: o.i('min_gb'),
            max: o.i('max_gb'),
            suffix: 'GB',
            accent: C.violet300,
            showRange: false,
            onChanged: (v) => _update(() => gb = v),
          ),
          if (targetId == 0) ...[
            const Gap(12),
            Text('تعداد دستگاه (IP)', style: t(12, c: C.n400)),
            const Gap(6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var n = o.i('min_ip'); n <= o.i('max_ip'); n++)
                  PresetChip(label: faNum(n), active: limitIp == n, onTap: () => _update(() => limitIp = n)),
              ],
            ),
          ],
          const Gap(16),
          QuoteBox(
            quote: quote,
            loading: quoteLoading,
            error: error,
            caption: targetId != 0 ? 'شارژ ${faNum(gb)} گیگ روی کانفیگ فعلی' : null,
          ),
          if (!c.isPro && (quote?.i('pro_discount_percent') ?? 0) > 0) ...[
            const Gap(8),
            Text('با Pro ارزان‌تر — دکمه Pro در بالا', style: t(11, c: C.a(C.amber400, 0.9))),
          ],
          const Gap(16),
          TgButton(
            label: targetId != 0 ? 'شارژ ترافیک و پرداخت' : 'خرید کانفیگ حجم‌دار',
            onPressed: c.busy || quoteLoading || quote == null ? null : _buy,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// gift-cards-panel.tsx
// ---------------------------------------------------------------------------

class GiftCardsPanel extends ConsumerStatefulWidget {
  const GiftCardsPanel({super.key});

  @override
  ConsumerState<GiftCardsPanel> createState() => _GiftCardsPanelState();
}

class _GiftCardsPanelState extends ConsumerState<GiftCardsPanel> {
  final _code = TextEditingController();
  List<J> cards = const [];
  bool redeeming = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _load() {
    ref.read(blControllerProvider).api.giftCards().then((r) {
      if (mounted) setState(() => cards = r.objs('items'));
    }).catchError((_) {});
  }

  Future<void> _redeem() async {
    final v = _code.text.trim();
    if (v.isEmpty) return;
    final c = ref.read(blControllerProvider);
    setState(() {
      redeeming = true;
      error = null;
    });
    try {
      await c.api.redeemGiftCard(v);
      haptic('medium');
      _code.clear();
      _load();
      notify('کارت هدیه فعال شد — کانفیگ در داشبورد است', ToastStatus.success);
      await c.refreshDashboard();
      c.switchTab(BLTab.subs);
    } catch (e) {
      setState(() => error = persianError(e));
    } finally {
      if (mounted) setState(() => redeeming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(blControllerProvider);
    final plans = c.plans.where((p) => p.i('traffic_gb') > 0 && !p.b('pro_only')).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: C.a(C.amber500, 0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: C.a(C.amber400, 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.card_giftcard_rounded, size: 16, color: C.amber200)),
                  const Gap(8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('کد هدیه داری؟', style: t(13, w: 600, c: C.amber50)),
                        const Gap(4),
                        Text('کد را وارد کن تا کانفیگ روی همین حساب ساخته شود.', style: t(11, c: C.n400, h: 1.6)),
                      ],
                    ),
                  ),
                ],
              ),
              const Gap(12),
              Row(
                children: [
                  Expanded(
                    child: BLInput(
                      controller: _code,
                      hint: 'BL-XXXX-XXXX-XXXX',
                      ltr: true,
                      onChanged: (v) {
                        final up = v.toUpperCase();
                        if (up != v) {
                          _code.value = _code.value.copyWith(text: up, selection: TextSelection.collapsed(offset: up.length));
                        }
                        setState(() {});
                      },
                    ),
                  ),
                  const Gap(8),
                  TgButton(
                    label: 'فعال کن',
                    expand: false,
                    fontSize: 12,
                    busy: redeeming,
                    onPressed: _code.text.trim().isEmpty ? null : _redeem,
                  ),
                ],
              ),
              if (error != null) ...[const Gap(8), Text(error!, style: t(11, c: C.red200))],
            ],
          ),
        ),
        const Gap(12),
        Text('خرید کارت هدیه', style: t(13, w: 600, c: C.white)),
        const Gap(2),
        Text('پلن را بخر، کد بگیر، در تلگرام برای دوستت بفرست. نامحدود و Pro در کارت هدیه نیست.', style: t(11, c: C.n500, h: 1.6)),
        const Gap(8),
        for (final plan in plans) ...[
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: c.busy ? null : () => c.startGiftPurchase(plan),
              child: Ink(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: C.b(30),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: C.w(10)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(plan.s('title'), style: t(13, w: 600, c: C.n50)),
                          const Gap(2),
                          Text(
                            '${faNum(plan.i('duration_days'))} روز${plan.i('traffic_gb') > 0 ? ' · ${faNum(plan.i('traffic_gb'))} گیگ' : ''}',
                            style: t(11, c: C.n500),
                          ),
                        ],
                      ),
                    ),
                    Text(priceText(plan.intOrNull('charge_toman') ?? plan.i('price_toman')), style: t(13, w: 700, c: C.white)),
                  ],
                ),
              ),
            ),
          ),
          const Gap(8),
        ],
        if (cards.isNotEmpty) ...[
          const Gap(4),
          Text('کارت‌های تو', style: t(12, w: 600, c: C.n300)),
          const Gap(8),
          for (final card in cards) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: C.b(30),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: C.w(10)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(card.s('plan_title'), style: t(13, w: 600, c: C.n100)),
                            const Gap(4),
                            Text(card.s('code'), textDirection: TextDirection.ltr, style: t(12, c: C.n200, mono: true)),
                          ],
                        ),
                      ),
                      Tag(card.s('status_label'), tone: card.s('status') == 'available' ? Tone.emerald : Tone.neutral),
                    ],
                  ),
                  if (card.s('status') == 'available' && card.text('code') != null) ...[
                    const Gap(8),
                    GestureDetector(
                      onTap: () => copyText(card.s('code')),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.copy_rounded, size: 14, color: C.n300),
                          const Gap(4),
                          Text('کپی کد', style: t(11, c: C.n300)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Gap(8),
          ],
        ],
      ],
    );
  }
}
