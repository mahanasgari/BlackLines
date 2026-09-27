import 'package:flutter/material.dart';
import 'package:hiddify/features/blacklines/core/format.dart';
import 'package:hiddify/features/blacklines/state/controller.dart';
import 'package:hiddify/features/blacklines/ui/kit.dart';
import 'package:hiddify/features/blacklines/ui/tokens.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// App.tsx Pro `TgSheet` + pro-panel.tsx.
Future<void> openProSheet(BuildContext context) {
  haptic();
  return showTgSheet(
    context,
    title: 'Black Lines Pro',
    builder: (_) => const _ProSheet(),
  );
}

class _ProSheet extends ConsumerStatefulWidget {
  const _ProSheet();

  @override
  ConsumerState<_ProSheet> createState() => _ProSheetState();
}

class _ProSheetState extends ConsumerState<_ProSheet> {
  @override
  void initState() {
    super.initState();
    final c = ref.read(blControllerProvider);
    if (c.proData == null) c.refreshProData();
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(blControllerProvider);
    final d = c.proData;
    if (d == null) return const OrbLoaderPanel(message: 'در حال بارگذاری Pro…');
    final active = d.b('is_pro');
    final discount = faNum(d.i('discount_percent'));
    final plan = d.obj('plan');

    Future<void> buy() async {
      final openedCheckout = await c.buyPro();
      if (openedCheckout && context.mounted) Navigator.of(context).pop();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: C.b(45),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: C.w(18)),
            gradient: RadialGradient(
              center: Alignment.topCenter,
              radius: 1.1,
              colors: [C.w(8), Colors.transparent],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: C.w(10),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: C.w(20)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.workspace_premium_rounded, size: 14, color: C.amber300),
                              const Gap(6),
                              Text('Black Lines Pro', style: t(11, w: 600, c: C.n100)),
                            ],
                          ),
                        ),
                        const Gap(8),
                        Text(active ? 'عضو Pro هستید' : 'ارتقا به Pro', style: t(18, w: 800, c: C.n100)),
                        const Gap(4),
                        Text(
                          active
                              ? 'اعتبار تا ${d.text('pro_until_label') ?? '—'} · $discount٪ تخفیف فعال'
                              : d.i('config_count') >= 3
                                  ? 'شما ${faNum(d.i('config_count'))} کانفیگ دارید — Pro برای مدیریت و تخفیف $discount٪ مناسب‌تر است.'
                                  : 'با Pro روی هر خرید کانفیگ $discount٪ تخفیف بگیرید.',
                          style: t(12, c: C.n400, h: 1.6),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.auto_awesome, size: 32, color: C.a(C.n300, 0.8)),
                ],
              ),
              if (!active) ...[
                const Gap(12),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: C.b(25),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: C.w(12)),
                  ),
                  child: Column(
                    children: [
                      Text('قیمت اشتراک', style: t(11, c: C.n500)),
                      const Gap(2),
                      Text(plan.s('price_label'), style: t(20, w: 800, c: C.n100)),
                      Text('${faNum(plan.i('duration_days'))} روز', style: t(11, c: C.n400)),
                    ],
                  ),
                ),
              ],
              const Gap(12),
              if (!active)
                _ProUpgradeButton(label: 'خرید اشتراک Pro', onPressed: c.busy ? null : buy)
              else
                TgButton(label: 'تمدید Pro', variant: BtnVariant.outline, onPressed: c.busy ? null : buy),
            ],
          ),
        ),
        const Gap(12),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('مزایای Pro', style: t(14, w: 600, c: C.n100)),
              const Gap(8),
              for (final b in d.objs('benefits')) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: b.b('active') ? C.w(8) : C.b(25),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: b.b('active') ? C.w(18) : C.w(10)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: b.b('active') ? C.w(15) : C.w(8),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          b.b('active') ? Icons.check_rounded : Icons.lock_outline_rounded,
                          size: 14,
                          color: b.b('active') ? C.n100 : C.n500,
                        ),
                      ),
                      const Gap(12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(b.s('title'), style: t(14, w: 500, c: C.n100)),
                            const Gap(2),
                            Text(b.s('description'), style: t(11, c: C.n400, h: 1.6)),
                            if (b.b('coming_soon')) ...[
                              const Gap(4),
                              Text('با فعال‌سازی Pro', style: t(10, w: 500, c: C.n400)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Gap(8),
              ],
            ],
          ),
        ),
        const Gap(12),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  style: t(11, c: C.n400, h: 1.7),
                  children: [
                    TextSpan(text: 'تخفیف کانفیگ: ', style: t(11, w: 700, c: C.n200)),
                    TextSpan(text: 'در فروشگاه، قیمت نهایی با $discount٪ تخفیف برای اعضای Pro نمایش داده می‌شود.'),
                  ],
                ),
              ),
              const Gap(8),
              Text.rich(
                TextSpan(
                  style: t(11, c: C.n400, h: 1.7),
                  children: [
                    TextSpan(text: 'برای همه: ', style: t(11, w: 700, c: C.n200)),
                    const TextSpan(text: 'هر کاربری می‌تواند Pro بخرد؛ اگر کانفیگ‌های زیادی دارید بیشتر به‌صرفه است.'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// pro-panel.tsx `ProUpgradeButton` (metallic dark button).
class _ProUpgradeButton extends StatelessWidget {
  const _ProUpgradeButton({required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? 0.5 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          child: Ink(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: C.w(22)),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF2A2A2A), Color(0xFF0A0A0A)],
              ),
              boxShadow: [BoxShadow(color: C.w(8), blurRadius: 14, spreadRadius: -2)],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.workspace_premium_rounded, size: 16, color: Color(0xFFFCD34D)),
                const Gap(8),
                Text(label, style: t(14, w: 700, c: Colors.white)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
