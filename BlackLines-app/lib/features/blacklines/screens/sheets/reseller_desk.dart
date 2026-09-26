import 'package:flutter/material.dart';
import 'package:hiddify/features/blacklines/core/format.dart';
import 'package:hiddify/features/blacklines/core/json.dart';
import 'package:hiddify/features/blacklines/screens/common.dart';
import 'package:hiddify/features/blacklines/screens/sheets/subscription_detail.dart';
import 'package:hiddify/features/blacklines/state/controller.dart';
import 'package:hiddify/features/blacklines/ui/kit.dart';
import 'package:hiddify/features/blacklines/ui/tokens.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// reseller-desk-panel.tsx `ResellerDeskSheet`.
Future<void> openResellerDesk(BuildContext context) {
  haptic();
  return showTgSheet(context, title: 'میز فروش', builder: (_) => const _ResellerDesk());
}

class _ResellerDesk extends ConsumerStatefulWidget {
  const _ResellerDesk();

  @override
  ConsumerState<_ResellerDesk> createState() => _ResellerDeskState();
}

class _ResellerDeskState extends ConsumerState<_ResellerDesk> {
  String query = '';
  String filter = 'all';
  int? busyId;

  @override
  void initState() {
    super.initState();
    ref.read(blControllerProvider).refreshResellerDesk();
  }

  Future<void> _markShared(J item, bool shared) async {
    final c = ref.read(blControllerProvider);
    setState(() => busyId = item.i('id'));
    try {
      await c.api.markLinkShared(item.i('id'), shared: shared);
      haptic();
      await c.refreshResellerDesk();
    } catch (_) {
    } finally {
      if (mounted) setState(() => busyId = null);
    }
  }

  String _daysLeft(J item) {
    if (item.b('is_payg') && item.text('expires_at') == null) return 'بدون انقضا';
    if (item.b('expired')) return 'منقضی';
    final d = item.intOrNull('days_left');
    if (d == null) return 'بدون انقضا';
    if (d < 0) return 'منقضی';
    if (d == 0) return 'امروز تمام می‌شود';
    return '${faNum(d)} روز مانده';
  }

  String _contact(J item) {
    final tg = item.text('customer_telegram_id');
    return [
      item.text('customer_phone'),
      if (tg != null) tg.startsWith('@') ? tg : '@$tg',
    ].whereType<String>().join(' · ');
  }

  bool _match(J item) {
    final d = item.intOrNull('days_left');
    if (filter == 'unsent' && (item.b('link_shared') || item.b('expired'))) return false;
    if (filter == 'expiring' && (item.b('expired') || d == null || d > 7)) return false;
    if (filter == 'expired' && !item.b('expired')) return false;
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [item.text('customer_name'), item.text('customer_phone'), item.text('customer_telegram_id'), item.text('plan_title'), item.text('label')]
        .whereType<String>()
        .join(' ')
        .toLowerCase()
        .contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(blControllerProvider);
    final data = c.resellerDesk;
    final items = data?.objs('items') ?? const <J>[];
    final summary = data?.obj('summary') ?? J.empty;
    final filtered = items.where(_match).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'مشتری‌هایی که برایشان کانفیگ خریدی. لینک را بفرست، تمدید کن، یا مالکیت را منتقل کن — قیمت همان فروشگاه است.',
          style: t(12, c: C.n400, h: 1.6),
        ),
        const Gap(12),
        if (items.isNotEmpty) ...[
          BLInput(hint: 'جستجوی نام، موبایل یا تلگرام', prefixIcon: Icons.search_rounded, onChanged: (v) => setState(() => query = v)),
          const Gap(8),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final (id, label, key) in const [
                  ('all', 'همه', 'total'),
                  ('unsent', 'لینک نرفته', 'unsent'),
                  ('expiring', 'رو به اتمام', 'expiring_soon'),
                  ('expired', 'منقضی', 'expired'),
                ])
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 4),
                    child: GestureDetector(
                      onTap: () {
                        haptic();
                        setState(() => filter = id);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: filter == id ? Colors.white : C.b(30),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: filter == id ? Colors.white : C.w(12)),
                        ),
                        child: Center(
                          widthFactor: 1,
                          child: Text(
                            '$label${summary.i(key) > 0 ? ' · ${faNum(summary.i(key))}' : ''}',
                            style: t(11, w: 500, c: filter == id ? Colors.black : C.n400),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Gap(12),
        ],
        if (items.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            decoration: BoxDecoration(color: C.b(30), borderRadius: BorderRadius.circular(16), border: Border.all(color: C.w(10))),
            child: Column(
              children: [
                Icon(Icons.group_outlined, size: 32, color: C.n500),
                const Gap(12),
                Text('هنوز مشتری‌ای نداری', style: t(14, w: 600, c: C.n100)),
                const Gap(6),
                Text(
                  'در فروشگاه «برای کس دیگری» را بزن، اسم مشتری را بنویس و خودت پرداخت کن. بعد از تایید اینجا دیده می‌شود.',
                  textAlign: TextAlign.center,
                  style: t(12, c: C.n500, h: 1.6),
                ),
                const Gap(12),
                TgButton(
                  label: 'خرید برای مشتری',
                  onPressed: () {
                    Navigator.of(context).pop();
                    c.switchTab(BLTab.shop);
                  },
                ),
              ],
            ),
          )
        else if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('با این فیلتر کسی پیدا نشد.', textAlign: TextAlign.center, style: t(12, c: C.n500)),
          )
        else
          for (final item in filtered) ...[_card(item), const Gap(8)],
      ],
    );
  }

  Widget _card(J item) {
    final name = item.text('customer_name') ?? item.text('label') ?? 'مشتری';
    final contact = _contact(item);
    final url = item.text('subscription_url');
    final d = item.intOrNull('days_left');
    final daysTone = item.b('expired') ? Tone.red : (d != null && d <= 7 ? Tone.amber : Tone.neutral);
    final role = switch (item.text('family_role')) {
      'parent' => ' · والد',
      'child' => ' · فرزند',
      _ => '',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: C.b(35), borderRadius: BorderRadius.circular(16), border: Border.all(color: C.w(10))),
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
                    Text(name, overflow: TextOverflow.ellipsis, style: t(14, w: 600, c: C.white)),
                    const Gap(2),
                    Text(
                      '${item.s('plan_title')}${item.text('traffic_label') != null ? ' · ${item.s('traffic_label')}' : ''}$role',
                      style: t(11, c: C.n400, h: 1.6),
                    ),
                    if (contact.isNotEmpty) Text(contact, textDirection: TextDirection.ltr, style: t(11, c: C.n500, mono: true)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Tag(_daysLeft(item), tone: daysTone),
                  const Gap(4),
                  GestureDetector(
                    onTap: busyId == item.i('id') ? null : () => _markShared(item, !item.b('link_shared')),
                    child: Tag(item.b('link_shared') ? 'لینک ارسال شد' : 'لینک نرفته', tone: item.b('link_shared') ? Tone.emerald : Tone.neutral),
                  ),
                ],
              ),
            ],
          ),
          const Gap(10),
          Row(
            children: [
              Expanded(
                child: TgButton(
                  label: 'کپی لینک',
                  icon: Icons.copy_rounded,
                  height: 36,
                  fontSize: 12,
                  onPressed: url == null
                      ? null
                      : () {
                          copyText(url);
                          if (!item.b('link_shared')) _markShared(item, true);
                        },
                ),
              ),
              const Gap(6),
              Expanded(
                child: TgButton(
                  label: 'ارسال',
                  icon: Icons.send_outlined,
                  variant: BtnVariant.outline,
                  height: 36,
                  fontSize: 12,
                  onPressed: url == null
                      ? null
                      : () {
                          haptic('medium');
                          Share.share(url, subject: 'لینک کانفیگ $name');
                          if (!item.b('link_shared')) _markShared(item, true);
                        },
                ),
              ),
            ],
          ),
          const Gap(6),
          Row(
            children: [
              Expanded(
                child: TgButton(
                  label: 'تمدید',
                  icon: Icons.refresh_rounded,
                  variant: BtnVariant.outline,
                  height: 36,
                  fontSize: 12,
                  onPressed: () => openSubDetail(context, item.i('id'), tab: 'renew'),
                ),
              ),
              const Gap(6),
              Expanded(
                child: TgButton(
                  label: 'انتقال',
                  icon: Icons.swap_horiz_rounded,
                  variant: BtnVariant.outline,
                  height: 36,
                  fontSize: 12,
                  onPressed: () => openSubDetail(context, item.i('id'), tab: 'more'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
