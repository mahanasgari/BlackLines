import 'package:flutter/material.dart';
import 'package:hiddify/features/blacklines/core/format.dart';
import 'package:hiddify/features/blacklines/core/json.dart';
import 'package:hiddify/features/blacklines/screens/common.dart';
import 'package:hiddify/features/blacklines/screens/sheets/reseller_desk.dart';
import 'package:hiddify/features/blacklines/screens/sheets/subscription_detail.dart';
import 'package:hiddify/features/blacklines/state/controller.dart';
import 'package:hiddify/features/blacklines/ui/kit.dart';
import 'package:hiddify/features/blacklines/ui/tokens.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// App.tsx `tab === "subs"` + dashboard-config-cards.tsx.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

sealed class _Group {}

class _Family extends _Group {
  _Family(this.key, this.members);
  final String key;
  final List<J> members;
}

class _Solo extends _Group {
  _Solo(this.item);
  final J item;
}

bool _matches(J s, String q) {
  final hay = [
    s.text('label'),
    s.text('plan_title'),
    s.text('email'),
    s.text('status'),
    s.text('customer_name'),
    s.text('customer_email'),
    s.text('customer_phone'),
    s.text('customer_telegram_id'),
    if (s.s('family_role') == 'parent') 'والد خانواده',
    if (s.s('family_role') == 'child') 'فرزند خانواده',
    if (s.text('family_group') != null) 'خانواده',
  ].whereType<String>().join(' ').toLowerCase();
  return hay.contains(q);
}

/// `filterAndGroupDashboardItems`.
List<_Group> _group(List<J> items, String query) {
  final q = query.trim().toLowerCase();
  final matched = q.isEmpty ? items : items.where((s) => _matches(s, q)).toList();
  final keep = {for (final s in matched) s.i('id')};
  if (q.isNotEmpty) {
    final groups = matched.map((s) => s.text('family_group')).whereType<String>().toSet();
    for (final s in items) {
      if (groups.contains(s.text('family_group'))) keep.add(s.i('id'));
    }
  }
  final families = <String, List<J>>{};
  final solos = <J>[];
  for (final item in items.where((s) => keep.contains(s.i('id')))) {
    final g = item.text('family_group');
    if (g != null) {
      families.putIfAbsent(g, () => []).add(item);
    } else {
      solos.add(item);
    }
  }
  return [
    for (final e in families.entries)
      _Family(
        e.key,
        e.value
          ..sort((a, b) {
            final ar = a.s('family_role') == 'parent' ? 0 : 1;
            final br = b.s('family_role') == 'parent' ? 0 : 1;
            if (ar != br) return ar - br;
            return (a.intOrNull('family_index') ?? 99) - (b.intOrNull('family_index') ?? 99);
          }),
      ),
    for (final s in solos) _Solo(s),
  ];
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  String query = '';
  int? rotateConfirmId;

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(blControllerProvider);
    final s = c.dashSummary;
    final groups = _group(c.dashItems, query);
    final families = groups.whereType<_Family>().toList();
    final solos = groups.whereType<_Solo>().toList();

    return RefreshIndicator(
      color: C.primaryFg,
      backgroundColor: C.primary,
      onRefresh: c.refreshDashboard,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (c.tabLoading && c.dashItems.isEmpty)
            const OrbLoaderPanel()
          else ...[
            Row(
              children: [
                Expanded(child: _SummaryBox('کل کانفیگ', faNum(s.i('total')))),
                const Gap(8),
                Expanded(child: _SummaryBox('آنلاین', faNum(s.i('online')), color: C.emerald300)),
                const Gap(8),
                Expanded(child: _SummaryBox('آفلاین', faNum(s.i('offline')), color: C.n300)),
              ],
            ),
            const Gap(8),
            if (c.resellerDesk case final desk?) _ResellerEntry(summary: desk.obj('summary')),
            if (c.dashItems.isNotEmpty) ...[
              const Gap(8),
              Collapsible(
                title: 'خلاصه مصرف',
                hint: 'امروز ${s.text('today_label') ?? '۰'}${s.text('remaining_label') != null ? ' · مانده ${s.s('remaining_label')}' : ''}',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (s.text('last_seen_label') != null) ...[
                      Text('آخرین فعالیت: ${s.s('last_seen_label')}', style: t(10, c: C.n500)),
                      const Gap(10),
                    ],
                    Row(
                      children: [
                        Expanded(child: _MiniStat('امروز', s.text('today_label') ?? '۰ B')),
                        const Gap(8),
                        Expanded(child: _MiniStat('۷ روز', s.text('week_label') ?? '۰ B')),
                      ],
                    ),
                    const Gap(8),
                    Row(
                      children: [
                        Expanded(
                          child: _MiniStat('آپلود / دانلود', '${s.text('up_label') ?? '۰'} / ${s.text('down_label') ?? '۰'}', small: true),
                        ),
                        const Gap(8),
                        Expanded(child: _MiniStat('کل مصرف', s.text('used_label') ?? '۰ B')),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
          if (!c.tabLoading && c.pendingOrder != null) ...[const Gap(12), _PendingOrder(c: c)],
          if (!c.tabLoading && c.dashItems.isEmpty && c.dashArchived.isEmpty && c.pendingOrder == null) ...[
            const Gap(12),
            EmptyState(
              message: 'هنوز کانفیگی ندارید.',
              actions: [
                TgButton(label: 'رفتن به فروشگاه', onPressed: () => c.switchTab(BLTab.shop)),
                TgButton(label: 'راهنمای استفاده', variant: BtnVariant.outline, onPressed: () => c.openProfile(help: true)),
              ],
            ),
          ],
          if (!c.tabLoading && c.dashItems.isEmpty && c.dashArchived.isNotEmpty && c.pendingOrder == null) ...[
            const Gap(12),
            Panel(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              child: Text(
                'کانفیگ فعالی در لیست نیست — منقضی‌ها در آرشیو پایین هستند.',
                textAlign: TextAlign.center,
                style: t(12, c: C.n400),
              ),
            ),
          ],
          if (c.dashItems.isNotEmpty) ...[
            const Gap(12),
            BLInput(
              hint: 'جستجو: نام مشتری، موبایل، تلگرام، ایمیل، برچسب…',
              prefixIcon: Icons.search_rounded,
              onChanged: (v) => setState(() => query = v),
            ),
          ],
          if (c.dashItems.isNotEmpty && query.trim().isNotEmpty && groups.isEmpty) ...[
            const Gap(12),
            Panel(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text('نتیجه‌ای پیدا نشد.', textAlign: TextAlign.center, style: t(14, c: C.n400)),
            ),
          ],
          if (families.isNotEmpty) ...[
            const Gap(16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                children: [
                  Expanded(child: Text('خانواده', style: t(11, w: 600, c: C.a(C.sky200, 0.8)))),
                  Text('${faNum(families.length)} پکیج', style: t(10, c: C.n600)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 2, 2, 10),
              child: Text('همه اعضای یک پکیج کنار هم هستند.', style: t(10, c: C.n500)),
            ),
            for (final f in families) ...[_FamilyPackCard(members: f.members, c: c), const Gap(10)],
          ],
          if (solos.isNotEmpty) ...[
            const Gap(6),
            if (families.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
                child: Text('کانفیگ‌های دیگر', style: t(11, w: 600, c: C.n400)),
              ),
            for (final s in solos) ...[
              _SoloCard(
                item: s.item,
                c: c,
                rotateConfirm: rotateConfirmId == s.item.i('id'),
                onAskRotate: () {
                  haptic();
                  setState(() => rotateConfirmId = s.item.i('id'));
                },
                onCancelRotate: () => setState(() => rotateConfirmId = null),
                onConfirmRotate: () async {
                  await c.rotateLink(s.item.i('id'), onUrl: copyText);
                  if (mounted) setState(() => rotateConfirmId = null);
                },
              ),
              const Gap(10),
            ],
          ],
          if (c.dashArchived.isNotEmpty) ...[
            const Gap(4),
            Collapsible(
              title: 'آرشیو منقضی‌ها · ${faNum(c.dashArchived.length)}',
              icon: Icons.archive_outlined,
              trailingText: ('نمایش', 'بستن'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('از لیست اصلی حذف شده‌اند؛ برای تمدید یا بازگردانی اینجا هستند.', style: t(10, c: C.n500, h: 1.6)),
                  const Gap(8),
                  for (final a in c.dashArchived) ...[_ArchivedRow(item: a, c: c), const Gap(8)],
                ],
              ),
            ),
          ],
          const Gap(12),
        ],
      ),
    );
  }
}

class _SummaryBox extends StatelessWidget {
  const _SummaryBox(this.label, this.value, {this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      child: Column(
        children: [
          Text(label, style: t(10, c: C.n400)),
          const Gap(4),
          Text(value, style: t(18, w: 700, c: color)),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(this.label, this.value, {this.small = false});

  final String label;
  final String value;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: C.b(25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: C.w(8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t(10, c: C.n500)),
          Text(value, textDirection: TextDirection.ltr, style: t(small ? 11 : 13, w: 600)),
        ],
      ),
    );
  }
}

class _ResellerEntry extends StatelessWidget {
  const _ResellerEntry({required this.summary});

  final J summary;

  @override
  Widget build(BuildContext context) {
    final total = summary.i('total');
    if (total <= 0) return const SizedBox.shrink();
    final unsent = summary.i('unsent');
    final expiring = summary.i('expiring_soon');
    final hint = [
      if (unsent > 0) '${faNum(unsent)} لینک نرفته',
      if (expiring > 0) '${faNum(expiring)} رو به اتمام',
    ].join(' · ');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          haptic();
          openResellerDesk(context);
        },
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: C.a(C.teal500, 0.07),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: C.a(C.teal500, 0.25)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: C.a(C.teal500, 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: C.a(C.teal500, 0.25)),
                ),
                child: Icon(Icons.storefront_outlined, size: 20, color: C.teal100),
              ),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('میز فروش', style: t(13, w: 600, c: C.teal50)),
                    const Gap(2),
                    Text(
                      '${faNum(total)} مشتری${hint.isNotEmpty ? ' · $hint' : ' · لینک، تمدید و انتقال'}',
                      style: t(11, c: C.a(C.teal100, 0.7)),
                    ),
                  ],
                ),
              ),
              Tag('باز کردن', tone: Tone.teal, size: 11),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingOrder extends StatelessWidget {
  const _PendingOrder({required this.c});

  final BLController c;

  @override
  Widget build(BuildContext context) {
    final p = c.pendingOrder!;
    final family = c.pendingFamilySize ?? 1;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(alignment: AlignmentDirectional.centerStart, child: Tag('در انتظار تایید', tone: Tone.white, size: 11)),
          const Gap(6),
          Text(p.s('plan_title'), style: t(15, w: 600)),
          const Gap(4),
          Text(
            'سفارش #${faNum(p.i('id'))} · ${p.s('amount_label')}${p.b('has_receipt') ? ' · رسید ارسال شده' : ' · منتظر رسید'}',
            style: t(12, c: C.n400),
          ),
          if (c.pendingRecipient != null) ...[
            const Gap(8),
            Callout('برای ${c.pendingRecipient} — بعد از تایید، لینک را از میز فروش بفرست.', tone: Tone.teal),
          ],
          if (family > 1) ...[
            const Gap(8),
            Callout('پکیج خانواده · ${faNum(family)} کانفیگ جدا (۱ والد + ${faNum(family - 1)} فرزند)'),
          ],
          const Gap(12),
          if (!p.b('has_receipt')) ...[
            TgButton(label: 'ادامه پرداخت / ارسال رسید', onPressed: c.resumePendingCheckout),
            const Gap(8),
          ],
          TgButton(
            label: 'لغو سفارش',
            variant: BtnVariant.outline,
            onPressed: c.busy ? null : () => c.cancelOrder(p.i('id')),
          ),
        ],
      ),
    );
  }
}

String _childSeatLabel(J item) {
  final idx = item.intOrNull('family_index');
  final n = idx != null && idx > 1 ? idx - 1 : null;
  return item.text('customer_name') ?? item.text('label') ?? (n != null ? 'فرزند ${faNum(n)}' : 'فرزند');
}

class _ConfigActions extends ConsumerWidget {
  const _ConfigActions({required this.item, required this.c, this.compact = false});

  final J item;
  final BLController c;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = item.text('subscription_url');
    final live = item.s('status') != 'expired' && item.s('status') != 'disabled';
    final h = compact ? 32.0 : 36.0;
    final fs = compact ? 11.0 : 12.0;
    return Row(
      children: [
        if (url != null && live) ...[
          Expanded(
            child: TgButton(
              label: 'اتصال',
              icon: Icons.power_settings_new_rounded,
              height: h,
              fontSize: fs,
              onPressed: c.busy
                  ? null
                  : () => connectInApp(ref, url, name: item.text('label') ?? item.text('customer_name') ?? item.text('plan_title')),
            ),
          ),
          const Gap(8),
        ],
        Expanded(
          child: TgButton(
            label: 'باز کردن',
            variant: BtnVariant.outline,
            height: h,
            fontSize: fs,
            onPressed: c.busy ? null : () => openSubDetail(context, item.i('id')),
          ),
        ),
        if (url != null) ...[
          const Gap(8),
          Expanded(
            child: TgButton(
              label: compact ? 'کپی' : 'کپی لینک',
              icon: Icons.copy_rounded,
              variant: BtnVariant.outline,
              height: h,
              fontSize: fs,
              onPressed: c.busy
                  ? null
                  : () {
                      copyText(url);
                      if (item.text('customer_name') != null) c.markShared(item.i('id'));
                    },
            ),
          ),
        ],
      ],
    );
  }
}

class _SoloCard extends StatelessWidget {
  const _SoloCard({
    required this.item,
    required this.c,
    required this.rotateConfirm,
    required this.onAskRotate,
    required this.onCancelRotate,
    required this.onConfirmRotate,
  });

  final J item;
  final BLController c;
  final bool rotateConfirm;
  final VoidCallback onAskRotate;
  final VoidCallback onCancelRotate;
  final VoidCallback onConfirmRotate;

  @override
  Widget build(BuildContext context) {
    final title = item.text('label') ?? item.s('plan_title');
    final (statusText, tone) = statusMeta(item.text('status'));
    final expired = item.s('status') == 'expired';
    final live = !expired && item.s('status') != 'disabled';
    return Panel(
      onTap: () => openSubDetail(context, item.i('id')),
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
                    EditableConfigName(name: title, disabled: c.busy, onSave: (l) => c.renameConfig(item.i('id'), l)),
                    const Gap(2),
                    Text(
                      item.b('is_metered') ? 'مصرفی ابری' : (item.b('is_payg') ? 'خرید حجم' : item.s('plan_title')),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t(11, c: C.n400),
                    ),
                    if (item.text('customer_name') != null) ...[
                      const Gap(4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: C.a(C.teal500, 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: C.a(C.teal500, 0.25)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.group_outlined, size: 12, color: C.teal100),
                            const Gap(4),
                            Text('برای ${item.s('customer_name')}', style: t(10, w: 500, c: C.teal100)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Tag(statusText, tone: tone, size: 11),
            ],
          ),
          const Gap(10),
          Text(remainingDaysHint(item.text('expires_at'), isPayg: item.b('is_payg')), style: t(11, c: C.n400)),
          const Gap(10),
          UsageBar(
            usedLabel: item.s('used_label'),
            totalLabel: item.s('total_label'),
            percent: item.d('usage_percent'),
            hasTotal: item.i('total_bytes') > 0,
          ),
          const Gap(10),
          _ConfigActions(item: item, c: c),
          if (expired) ...[
            const Gap(8),
            TgButton(
              label: 'حذف از لیست',
              icon: Icons.delete_outline_rounded,
              variant: BtnVariant.outline,
              height: 36,
              fontSize: 12,
              foreground: C.red300,
              onPressed: c.busy ? null : () => c.hideExpired(item.i('id')),
            ),
          ],
          if (live) ...[
            const Gap(8),
            if (rotateConfirm)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: C.a(C.amber500, 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: C.a(C.amber400, 0.2)),
                ),
                child: Column(
                  children: [
                    Text(
                      'لینک فعلی باطل می‌شود و لینک جدید کپی می‌شود. مطمئنی؟',
                      style: t(11, c: C.a(C.amber100, 0.9), h: 1.6),
                    ),
                    const Gap(8),
                    Row(
                      children: [
                        Expanded(
                          child: TgButton(
                            label: 'انصراف',
                            variant: BtnVariant.outline,
                            height: 36,
                            fontSize: 12,
                            onPressed: c.busy ? null : onCancelRotate,
                          ),
                        ),
                        const Gap(8),
                        Expanded(
                          child: TgButton(
                            label: c.busy ? 'در حال ساخت…' : 'لینک جدید',
                            height: 36,
                            fontSize: 12,
                            onPressed: c.busy ? null : onConfirmRotate,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            else
              TgButton(
                label: 'باطل کردن و لینک جدید',
                icon: Icons.key_rounded,
                variant: BtnVariant.outline,
                height: 36,
                fontSize: 12,
                onPressed: c.busy ? null : onAskRotate,
              ),
          ],
        ],
      ),
    );
  }
}

class _FamilyPackCard extends StatefulWidget {
  const _FamilyPackCard({required this.members, required this.c});

  final List<J> members;
  final BLController c;

  @override
  State<_FamilyPackCard> createState() => _FamilyPackCardState();
}

class _FamilyPackCardState extends State<_FamilyPackCard> {
  bool open = true;

  @override
  Widget build(BuildContext context) {
    final members = widget.members;
    final parent = members.firstWhere((m) => m.s('family_role') == 'parent', orElse: () => members.first);
    final children = members.where((m) => m.i('id') != parent.i('id')).toList();
    final online = members.where((m) => m.s('status') == 'online').length;
    final plan = parent.s('plan_title');
    final packTitle = parent.text('label') != null && parent.s('family_role') == 'parent'
        ? parent.s('label')
        : (plan.isEmpty ? 'پکیج خانواده' : plan);
    final names = members
        .map((m) => m.i('id') == parent.i('id') ? (m.text('label') ?? m.text('customer_name') ?? 'والد') : _childSeatLabel(m))
        .take(4)
        .join(' · ');
    final extra = members.length > 4 ? ' +${faNum(members.length - 4)}' : '';

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: C.a(C.sky500, 0.25)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [C.a(C.sky500, 0.08), C.b(20)],
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              haptic();
              setState(() => open = !open);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: C.a(C.sky500, 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: C.a(C.sky300, 0.25)),
                    ),
                    child: Icon(Icons.group_outlined, size: 20, color: C.sky100),
                  ),
                  const Gap(12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(packTitle, style: t(14, w: 600, c: C.n50)),
                        const Gap(2),
                        Text(
                          '${faNum(members.length)} نفر · ${faNum(online)} آنلاین${plan.isNotEmpty && packTitle != plan ? ' · $plan' : ''}',
                          style: t(11, c: C.n400),
                        ),
                        if (names.isNotEmpty) ...[
                          const Gap(4),
                          Text('$names$extra', maxLines: 1, overflow: TextOverflow.ellipsis, style: t(11, c: C.n300)),
                        ],
                        const Gap(4),
                        Text(remainingDaysHint(parent.text('expires_at')), style: t(10, c: C.n500)),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: C.n500),
                  ),
                ],
              ),
            ),
          ),
          if (open)
            Container(
              decoration: BoxDecoration(border: Border(top: BorderSide(color: C.a(C.sky500, 0.15)))),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'هر نفر لینک جدا دارد. والد را برای خودت نگه دار و لینک هر فرزند را برای همان نفر بفرست.',
                    style: t(10, c: C.n500, h: 1.6),
                  ),
                  const Gap(8),
                  _FamilyMemberRow(item: parent, parent: true, c: widget.c),
                  if (children.isNotEmpty) ...[
                    const Gap(8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Text('فرزندان', style: t(10, w: 600, c: C.n500)),
                    ),
                    for (final ch in children) ...[const Gap(6), _FamilyMemberRow(item: ch, parent: false, c: widget.c)],
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _FamilyMemberRow extends StatelessWidget {
  const _FamilyMemberRow({required this.item, required this.parent, required this.c});

  final J item;
  final bool parent;
  final BLController c;

  @override
  Widget build(BuildContext context) {
    final title = parent ? (item.text('label') ?? 'کانفیگ والد') : _childSeatLabel(item);
    final (statusText, tone) = statusMeta(item.text('status'));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: parent ? C.a(C.sky500, 0.07) : C.b(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: parent ? C.a(C.sky300, 0.2) : C.w(8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Tag(parent ? 'والد' : 'فرزند', tone: parent ? Tone.sky : Tone.neutral),
                        if (parent && item.text('customer_name') != null) ...[
                          const Gap(4),
                          Flexible(
                            child: Text(
                              'برای ${item.s('customer_name')}',
                              overflow: TextOverflow.ellipsis,
                              style: t(10, c: C.teal200),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const Gap(2),
                    EditableConfigName(
                      name: title,
                      disabled: c.busy,
                      style: t(13, w: 500, c: C.n100),
                      onSave: (l) => c.renameConfig(item.i('id'), l),
                    ),
                  ],
                ),
              ),
              Tag(statusText, tone: tone),
            ],
          ),
          const Gap(6),
          UsageBar(
            usedLabel: item.s('used_label'),
            totalLabel: item.s('total_label'),
            percent: item.d('usage_percent'),
            hasTotal: item.i('total_bytes') > 0,
          ),
          const Gap(8),
          _ConfigActions(item: item, c: c, compact: true),
        ],
      ),
    );
  }
}

class _ArchivedRow extends StatelessWidget {
  const _ArchivedRow({required this.item, required this.c});

  final J item;
  final BLController c;

  @override
  Widget build(BuildContext context) {
    final title = item.text('label') ?? item.s('plan_title');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: C.b(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: C.w(8)),
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
                    EditableConfigName(
                      name: title,
                      disabled: c.busy,
                      style: t(14, w: 500, c: C.n100),
                      onSave: (l) => c.renameConfig(item.i('id'), l),
                    ),
                    if (item.text('label') != null)
                      Text(item.s('plan_title'), maxLines: 1, overflow: TextOverflow.ellipsis, style: t(11, c: C.n500)),
                    const Gap(2),
                    Text(item.s('email'), textDirection: TextDirection.ltr, style: t(10, c: C.n500, mono: true)),
                  ],
                ),
              ),
              const Tag('منقضی', tone: Tone.red),
            ],
          ),
          const Gap(8),
          Row(
            children: [
              Expanded(
                child: TgButton(
                  label: 'جزئیات / تمدید',
                  variant: BtnVariant.outline,
                  height: 36,
                  fontSize: 12,
                  onPressed: c.busy ? null : () => openSubDetail(context, item.i('id')),
                ),
              ),
              const Gap(8),
              Expanded(
                child: TgButton(
                  label: 'بازگردانی',
                  height: 36,
                  fontSize: 12,
                  onPressed: c.busy ? null : () => c.restoreArchived(item.i('id')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
