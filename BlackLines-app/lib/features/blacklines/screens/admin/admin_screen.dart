import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hiddify/features/blacklines/core/api.dart';
import 'package:hiddify/features/blacklines/core/format.dart';
import 'package:hiddify/features/blacklines/core/json.dart';
import 'package:hiddify/features/blacklines/screens/activity_log.dart';
import 'package:hiddify/features/blacklines/screens/admin/admin_widgets.dart';
import 'package:hiddify/features/blacklines/screens/admin/analytics.dart';
import 'package:hiddify/features/blacklines/screens/admin/pending_order_sheet.dart';
import 'package:hiddify/features/blacklines/screens/admin/servers_growth.dart';
import 'package:hiddify/features/blacklines/screens/admin/user_sheet.dart';
import 'package:hiddify/features/blacklines/screens/sheets/notification_center.dart';
import 'package:hiddify/features/blacklines/screens/sheets/order_history.dart';
import 'package:hiddify/features/blacklines/state/controller.dart';
import 'package:hiddify/features/blacklines/ui/kit.dart';
import 'package:hiddify/features/blacklines/ui/tokens.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// admin-panel.tsx `AdminPanel`.
class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  String section = 'queue';

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(blControllerProvider);
    if (!c.isAdmin) return const SizedBox.shrink();
    if (c.tabLoading && c.adminOrders.isEmpty && c.adminWds.isEmpty) return const Center(child: OrbLoaderPanel());
    final pending = c.adminPendingCount;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, size: 16, color: C.n400),
                      const Gap(6),
                      Text('پنل ادمین', style: t(16, w: 700)),
                    ],
                  ),
                  const Gap(2),
                  Text(pending > 0 ? '${faNum(pending)} مورد نیاز به بررسی' : 'همه چیز مرتب است', style: t(11, c: C.n400)),
                ],
              ),
            ),
            _SquareIcon(icon: Icons.history_rounded, onTap: () => openOrderHistory(context, admin: true)),
            const Gap(8),
            Stack(
              clipBehavior: Clip.none,
              children: [
                _SquareIcon(icon: Icons.notifications_none_rounded, onTap: () => openNotificationCenter(context)),
                if (pending > 0)
                  Positioned(
                    top: -4,
                    left: -4,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(color: C.orange500, borderRadius: BorderRadius.circular(999)),
                      child: Text(faNum(pending.clamp(0, 99)), textAlign: TextAlign.center, style: t(9, w: 700, c: C.white)),
                    ),
                  ),
              ],
            ),
          ],
        ),
        const Gap(12),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: C.b(40), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(10))),
          child: Row(
            children: [
              for (final (id, label, icon) in [
                ('queue', pending > 0 ? 'صف · ${faNum(pending)}' : 'صف', Icons.inbox_outlined),
                ('stats', 'آمار', Icons.bar_chart_rounded),
                ('users', 'کاربران', Icons.group_outlined),
                ('logs', 'لاگ', Icons.receipt_long_outlined),
                ('settings', 'تنظیمات', Icons.tune_rounded),
              ])
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      haptic();
                      setState(() => section = id);
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(color: section == id ? C.primary : Colors.transparent, borderRadius: BorderRadius.circular(8)),
                      child: Column(
                        children: [
                          Icon(icon, size: 14, color: section == id ? C.primaryFg : C.n400),
                          const Gap(2),
                          Text(label, maxLines: 1, style: t(10, w: 600, c: section == id ? C.primaryFg : C.n400)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const Gap(12),
        switch (section) {
          'stats' => const AdminAnalyticsPanel(),
          'users' => const _AdminUsers(),
          'logs' => const AdminActivityLogPanel(),
          'settings' => const _AdminSettings(),
          _ => _AdminQueue(c: c),
        },
      ],
    );
  }
}

class _SquareIcon extends StatelessWidget {
  const _SquareIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 40,
        height: 40,
        child: Material(
          color: C.b(50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: C.w(15))),
          child: InkWell(borderRadius: BorderRadius.circular(12), onTap: onTap, child: Icon(icon, size: 16, color: C.n300)),
        ),
      );
}

// ---------------------------------------------------------------------------
// Queue
// ---------------------------------------------------------------------------

class _AdminQueue extends StatelessWidget {
  const _AdminQueue({required this.c});

  final BLController c;

  Widget _empty(String msg) => Container(
        padding: const EdgeInsets.symmetric(vertical: 32),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: C.w(12))),
        child: Column(children: [const Opacity(opacity: 0.5, child: OrbLoader(size: 48)), const Gap(8), Text(msg, style: t(14, c: C.n400))]),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckLine(value: c.adminIncludeTest, small: true, label: 'نمایش سفارش و برداشت کاربران تست', onChanged: c.setAdminIncludeTest),
        const Gap(8),
        Row(
          children: [
            Expanded(child: StatBox(label: 'سفارش', value: faNum(c.adminOrders.length), center: true)),
            const Gap(8),
            Expanded(child: StatBox(label: 'برداشت', value: faNum(c.adminWds.length), center: true)),
          ],
        ),
        const Gap(16),
        Text('سفارش‌های در انتظار', style: t(12, w: 600, c: C.n400)),
        const Gap(8),
        if (c.adminOrders.isEmpty)
          _empty('سفارشی در صف نیست')
        else
          for (final o in c.adminOrders) ...[
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: c.busy ? null : () => openPendingOrderSheet(context, o),
                child: Ink(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: C.b(35), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(10))),
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
                                Text('#${faNum(o.i('id'))} · ${o.s('plan')}', style: t(14, w: 600)),
                                Text('${o.text('user') ?? '—'} · ${faNum(o.i('telegram_id'))}', overflow: TextOverflow.ellipsis, style: t(11, c: C.n400)),
                              ],
                            ),
                          ),
                          Text(o.s('amount_label'), style: t(12, w: 500, c: C.n200)),
                        ],
                      ),
                      const Gap(8),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          if (o.b('is_wallet_topup')) const AdminChip('شارژ'),
                          if (o.b('is_platform_pro')) const AdminChip('Pro'),
                          if (o.i('wallet_used') > 0) const AdminChip('کیف‌پول'),
                          if (o.i('family_size', 1) > 1) AdminChip('خانواده ${faNum(o.i('family_size'))}'),
                          if (o.text('promo_code') != null) AdminChip('کد ${o.s('promo_code')}'),
                          AdminChip(o.b('has_receipt') ? 'رسید ✓' : 'بدون رسید'),
                          if (o.b('is_test')) const AdminChip('تست'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Gap(8),
          ],
        const Gap(8),
        Text('برداشت‌ها', style: t(12, w: 600, c: C.n400)),
        const Gap(8),
        if (c.adminWds.isEmpty)
          _empty('برداشتی در صف نیست')
        else
          for (final w in c.adminWds) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: C.b(35), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(10))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('#${faNum(w.i('id'))} · ${w.s('amount_label')}', style: t(14, w: 600)),
                  Text(w.text('user') ?? '—', style: t(11, c: C.n400)),
                  const Gap(4),
                  Text(w.s('card_number'), textDirection: TextDirection.ltr, textAlign: TextAlign.end, style: t(10, c: C.n500, mono: true)),
                  const Gap(10),
                  Row(
                    children: [
                      Expanded(child: TgButton(label: 'پرداخت شد', height: 36, fontSize: 12, onPressed: c.busy ? null : () => c.adminPayWithdrawal(w.i('id'), pay: true))),
                      const Gap(8),
                      Expanded(
                        child: TgButton(
                          label: 'رد',
                          variant: BtnVariant.outline,
                          height: 36,
                          fontSize: 12,
                          onPressed: c.busy ? null : () => c.adminPayWithdrawal(w.i('id'), pay: false),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Gap(8),
          ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Users
// ---------------------------------------------------------------------------

class _AdminUsers extends ConsumerStatefulWidget {
  const _AdminUsers();

  @override
  ConsumerState<_AdminUsers> createState() => _AdminUsersState();
}

class _AdminUsersState extends ConsumerState<_AdminUsers> {
  String query = '';
  String filter = '';
  bool includeTest = false;
  bool loading = true;
  List<J> items = const [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => loading = true);
    try {
      final r = await ref.read(blControllerProvider).api.adminUsers(q: query.trim(), includeTest: includeTest, slice: filter);
      if (mounted) setState(() => items = r.objs('items'));
    } catch (e) {
      notify(persianError(e), ToastStatus.error);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final issues = items.where((u) => u.b('has_issue')).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BLInput(
          hint: 'آیدی تلگرام، @username یا نام',
          ltr: true,
          prefixIcon: Icons.search_rounded,
          onChanged: (v) {
            query = v;
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 280), _search);
          },
        ),
        const Gap(8),
        SizedBox(
          height: 32,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final (id, label) in [
                ('', 'همه'),
                ('issues', issues > 0 ? 'رسیدگی · ${faNum(issues)}' : 'رسیدگی'),
                ('paying', 'خرید کرده'),
                ('expired', 'منقضی'),
                ('expiring', 'در حال انقضا'),
                ('wallet', 'کیف‌پول'),
                ('trial', 'تست گرفته'),
                ('pending', 'سفارش باز'),
              ])
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: GestureDetector(
                    onTap: () {
                      setState(() => filter = id);
                      _search();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: filter == id ? (id == 'issues' ? C.a(C.orange500, 0.15) : C.primary) : C.b(30),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: filter == id ? (id == 'issues' ? C.a(C.orange500, 0.4) : C.primary) : C.w(12)),
                      ),
                      child: Center(
                        widthFactor: 1,
                        child: Text(
                          label,
                          style: t(11, w: 600, c: filter == id ? (id == 'issues' ? C.orange100 : C.primaryFg) : C.n400),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        CheckLine(
          value: includeTest,
          small: true,
          label: 'کاربران تست',
          onChanged: (v) {
            setState(() => includeTest = v);
            _search();
          },
        ),
        const Gap(8),
        if (loading)
          Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Text('در حال جستجو…', textAlign: TextAlign.center, style: t(12, c: C.n500)))
        else if (items.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(10))),
            child: Text(filter == 'issues' ? 'موردی برای رسیدگی نیست' : 'کاربری پیدا نشد', textAlign: TextAlign.center, style: t(12, c: C.n500)),
          )
        else
          for (final u in items) ...[
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  await openAdminUserSheet(context, u.i('id'));
                  _search();
                },
                child: Ink(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: C.b(30), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(10))),
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
                                Text(
                                  u.text('full_name') ?? (u.text('username') != null ? '@${u.s('username')}' : faNum(u.i('telegram_id'))),
                                  overflow: TextOverflow.ellipsis,
                                  style: t(14, w: 600),
                                ),
                                Text(
                                  '${u.text('username') != null ? '@${u.s('username')} · ' : ''}${u.i('telegram_id')}',
                                  textDirection: TextDirection.ltr,
                                  style: t(10, c: C.n500, mono: true),
                                ),
                              ],
                            ),
                          ),
                          if (u.b('has_issue')) const AdminChip('باز', tone: C.orange500),
                        ],
                      ),
                      const Gap(6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          AdminChip(u.b('is_super_admin') ? 'ادمین اصلی' : (u.b('is_admin') ? 'ادمین' : 'کاربر')),
                          AdminChip(u.text('wallet_label') ?? priceText(u.i('wallet_balance'))),
                          AdminChip('${faNum(u.intOrNull('active_subscription_count') ?? u.i('subscription_count'))} کانفیگ'),
                          if (u.i('pending_order_count') > 0) AdminChip('${faNum(u.i('pending_order_count'))} سفارش باز'),
                          if (u.i('chat_unread') > 0) AdminChip('${faNum(u.i('chat_unread'))} پیام'),
                          if (u.b('is_test')) const AdminChip('تست'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Gap(8),
          ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

class _AdminSettings extends ConsumerStatefulWidget {
  const _AdminSettings();

  @override
  ConsumerState<_AdminSettings> createState() => _AdminSettingsState();
}

class _AdminSettingsState extends ConsumerState<_AdminSettings> {
  String? open;
  J? birthday;
  bool birthdayEnabled = false;
  J? trial;
  bool trialEnabled = true;
  bool trialSendLinks = false;
  bool skipExisting = true;
  bool notifyUsers = true;
  J? grantResult;
  J? custom;
  bool customEnabled = true;
  J? payg;
  bool paygEnabled = true;

  final _birthday = TextEditingController();
  final _trial = {for (final k in const ['duration_days', 'traffic_gb', 'limit_ip']) k: TextEditingController()};
  final _grantTargets = TextEditingController();
  final _custom = {
    for (final k in const [
      'min_days', 'max_days', 'min_gb', 'max_gb', 'min_ip', 'max_ip', //
      'base_fee_toman', 'price_per_day_toman', 'price_per_gb_toman', 'unlimited_day_fee_toman', 'price_per_ip_toman', 'min_price_toman',
    ])
      k: TextEditingController(),
  };
  final _payg = {
    for (final k in const [
      'price_per_gb_toman', 'prepaid_price_per_gb_toman', 'min_wallet_toman', 'limit_ip', 'min_gb', //
      'max_gb', 'min_ip', 'max_ip', 'price_per_ip_toman', 'min_price_toman',
    ])
      k: TextEditingController(),
  };
  final _card = {for (final k in const ['card', 'name', 'label', 'note']) k: TextEditingController()};
  final _broadcast = TextEditingController();

  BLController get c => ref.read(blControllerProvider);

  @override
  void initState() {
    super.initState();
    final api = c.api;
    api.adminBirthdayGift().then((r) {
      if (!mounted) return;
      setState(() {
        birthday = r;
        birthdayEnabled = r.b('enabled');
        _birthday.text = '${r.i('amount_toman')}';
      });
    }).catchError((_) {});
    api.adminTrialSettings().then(_applyTrial).catchError((_) {});
    api.adminCustomSettings().then(_applyCustom).catchError((_) {});
    api.adminPaygSettings().then(_applyPayg).catchError((_) {});
    c.refreshAdmin().catchError((_) {});
  }

  @override
  void dispose() {
    for (final x in [_birthday, _grantTargets, _broadcast, ..._trial.values, ..._custom.values, ..._payg.values, ..._card.values]) {
      x.dispose();
    }
    super.dispose();
  }

  void _applyTrial(J r) {
    if (!mounted) return;
    setState(() {
      trial = r;
      trialEnabled = r.b('enabled');
      trialSendLinks = r.b('send_links');
      for (final e in _trial.entries) {
        e.value.text = '${r.i(e.key)}';
      }
    });
  }

  void _applyCustom(J r) {
    if (!mounted) return;
    setState(() {
      custom = r;
      customEnabled = r.b('enabled');
      for (final e in _custom.entries) {
        e.value.text = '${r.i(e.key)}';
      }
    });
  }

  void _applyPayg(J r) {
    if (!mounted) return;
    setState(() {
      payg = r;
      paygEnabled = r.b('enabled');
      for (final e in _payg.entries) {
        e.value.text = '${r.intOrNull(e.key) ?? (e.key == 'prepaid_price_per_gb_toman' ? r.i('price_per_gb_toman') : 0)}';
      }
    });
  }

  /// Reads a group of numeric fields; null if any is empty/invalid (App.tsx bails on NaN).
  Map<String, int>? _ints(Map<String, TextEditingController> m) {
    final out = <String, int>{};
    for (final e in m.entries) {
      final v = int.tryParse(e.value.text.trim());
      if (v == null) return null;
      out[e.key] = v;
    }
    return out;
  }

  void _toggle(String id) => setState(() => open = open == id ? null : id);

  Future<void> _grant({bool all = false}) async {
    if (all && !await confirmSheet(context, title: 'اعطا به همه', message: 'VPN رایگان به همه کاربران پلتفرم داده شود؟', confirm: 'اعطا')) return;
    final r = await c.run(() => c.api.adminGrantTrial({
          if (!all) 'targets_text': _grantTargets.text,
          if (all) 'all_users': true,
          'skip_existing_trial': skipExisting,
          'notify_users': notifyUsers,
          'duration_days': parseIntOrNull(_trial['duration_days']!.text),
          'traffic_gb': parseIntOrNull(_trial['traffic_gb']!.text),
          'limit_ip': parseIntOrNull(_trial['limit_ip']!.text),
        }));
    if (r == null) return;
    notify(
      'اعطا شد: ${faNum(r.i('granted_count'))} · رد: ${faNum(r.i('skipped_count'))} · خطا: ${faNum(r.i('failed_count'))}',
      r.i('failed_count') > 0 ? ToastStatus.info : ToastStatus.success,
    );
    setState(() => grantResult = r);
  }

  @override
  Widget build(BuildContext context) {
    final ctl = ref.watch(blControllerProvider);
    final busy = ctl.busy;
    final tr = trial;
    final cu = custom;
    final pg = payg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminAccordion(
          icon: Icons.cake_outlined,
          title: 'هدیه تولد',
          summary: birthdayEnabled ? (birthday != null ? priceText(birthday!.i('amount_toman')) : 'فعال') : 'غیرفعال',
          open: open == 'birthday',
          onToggle: () => _toggle('birthday'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'اگر فعال باشد، در روز تولد اعتبار به کیف‌پول اضافه می‌شود. به کاربر اعلام نمی‌شود و این مبلغ فقط برای خرید داخل فروشگاه قابل استفاده است — برداشت و انتقال ندارد.',
                style: t(11, c: C.n400, h: 1.6),
              ),
              const Gap(8),
              CheckLine(value: birthdayEnabled, label: 'فعال باشد', onChanged: (v) => setState(() => birthdayEnabled = v)),
              const Gap(8),
              NumField(label: 'مبلغ (تومان)', controller: _birthday, hint: '50000'),
              const Gap(8),
              TgButton(
                label: 'ذخیره',
                height: 40,
                onPressed: busy || _birthday.text.isEmpty
                    ? null
                    : () async {
                        final amount = int.tryParse(_birthday.text);
                        if (amount == null) return;
                        final r = await c.run(() => c.api.adminSetBirthdayGift(enabled: birthdayEnabled, amountToman: amount));
                        if (r == null) return;
                        setState(() {
                          birthday = r;
                          birthdayEnabled = r.b('enabled');
                          _birthday.text = '${r.i('amount_toman')}';
                        });
                        notify(r.b('enabled') ? 'هدیه تولد فعال شد: ${r.s('amount_label')}' : 'هدیه تولد غیرفعال شد', ToastStatus.success);
                      },
              ),
            ],
          ),
        ),
        AdminAccordion(
          icon: Icons.card_giftcard_rounded,
          title: 'VPN رایگان',
          summary: tr == null ? 'در حال بارگذاری…' : (tr.b('enabled') ? '${faNum(tr.i('duration_days'))} روز · ${tr.s('traffic_label')}' : 'غیرفعال'),
          open: open == 'trial',
          onToggle: () => _toggle('trial'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('پیشنهاد تست — کاربران جدید', style: t(11, w: 600, c: C.n300)),
              const Gap(6),
              CheckLine(value: trialEnabled, label: 'نمایش دکمه دریافت تست', onChanged: (v) => setState(() => trialEnabled = v)),
              CheckLine(value: trialSendLinks, label: 'ارسال لینک کانفیگ داخل ربات', onChanged: (v) => setState(() => trialSendLinks = v)),
              const Gap(4),
              Text('کاربر باید خودش دکمه را در ربات یا فروشگاه بزند. لینک‌ها داخل برنامه هستند.', style: t(11, c: C.n500, h: 1.6)),
              const Gap(8),
              NumGrid(columns: 3, fields: [('روز', _trial['duration_days']!), ('گیگ', _trial['traffic_gb']!), ('دستگاه', _trial['limit_ip']!)]),
              TgButton(
                label: 'ذخیره تنظیمات',
                height: 40,
                onPressed: busy
                    ? null
                    : () async {
                        final v = _ints(_trial);
                        if (v == null || v.values.any((x) => x == 0)) return;
                        final r = await c.run(
                          () => c.api.adminSetTrialSettings({'enabled': trialEnabled, ...v, 'send_links': trialSendLinks}),
                          success: 'تنظیمات حساب تست ذخیره شد',
                        );
                        if (r != null) _applyTrial(r);
                      },
              ),
              const Gap(12),
              Divider(height: 1, color: C.w(10)),
              const Gap(12),
              Text('دستی — اعطا به کاربران', style: t(11, w: 600, c: C.n300)),
              const Gap(4),
              Text('آیدی تلگرام یا @username — هر خط یا با کاما جدا کنید. از تنظیمات بالا برای مدت و ترافیک استفاده می‌شود.', style: t(11, c: C.n500, h: 1.6)),
              const Gap(8),
              AreaField(controller: _grantTargets, hint: '123456789\n@username', ltr: true, onChanged: (_) => setState(() {})),
              const Gap(6),
              CheckLine(value: skipExisting, small: true, label: 'رد کردن کسانی که قبلاً VPN تست دارند', onChanged: (v) => setState(() => skipExisting = v)),
              CheckLine(value: notifyUsers, small: true, label: 'ارسال لینک در تلگرام', onChanged: (v) => setState(() => notifyUsers = v)),
              const Gap(8),
              Row(
                children: [
                  Expanded(
                    child: TgButton(
                      label: 'اعطا به انتخاب‌شده',
                      height: 40,
                      fontSize: 12,
                      onPressed: busy || _grantTargets.text.trim().isEmpty ? null : _grant,
                    ),
                  ),
                  const Gap(8),
                  Expanded(
                    child: TgButton(label: 'اعطا به همه', variant: BtnVariant.outline, height: 40, fontSize: 12, onPressed: busy ? null : () => _grant(all: true)),
                  ),
                ],
              ),
              if (grantResult case final g?) ...[
                const Gap(8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: C.b(30), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(10))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          style: t(11, c: C.n300),
                          children: [
                            const TextSpan(text: 'موفق: '),
                            TextSpan(text: faNum(g.i('granted_count')), style: t(11, w: 700, c: C.emerald300)),
                            TextSpan(text: ' · رد شده: ${faNum(g.i('skipped_count'))} · خطا: ${faNum(g.i('failed_count'))}'),
                          ],
                        ),
                      ),
                      if (g.strs('not_found').isNotEmpty) ...[
                        const Gap(4),
                        Text('پیدا نشد: ${g.strs('not_found').join(', ')}', style: t(11, c: C.a(C.amber400, 0.9))),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        AdminAccordion(
          icon: Icons.auto_awesome,
          title: 'ساخت پکیج سفارشی',
          summary: cu == null ? 'در حال بارگذاری…' : (cu.b('enabled') ? '${faNum(cu.i('min_days'))}–${faNum(cu.i('max_days'))} روز' : 'غیرفعال'),
          open: open == 'custom',
          onToggle: () => _toggle('custom'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('محدوده و قیمت ساخت پکیج دلخواه کاربران. قیمت نهایی به نزدیک ۵۰۰۰ تومان گرد می‌شود.', style: t(11, c: C.n400, h: 1.6)),
              const Gap(6),
              CheckLine(value: customEnabled, label: 'فعال برای کاربران', onChanged: (v) => setState(() => customEnabled = v)),
              const Gap(8),
              NumGrid(fields: [
                ('حداقل روز', _custom['min_days']!),
                ('حداکثر روز', _custom['max_days']!),
                ('حداقل GB', _custom['min_gb']!),
                ('حداکثر GB', _custom['max_gb']!),
                ('حداقل دستگاه', _custom['min_ip']!),
                ('حداکثر دستگاه', _custom['max_ip']!),
              ]),
              Text('قیمت‌گذاری (تومان)', style: t(11, w: 600, c: C.n300)),
              const Gap(8),
              NumGrid(fields: [
                ('هزینه پایه', _custom['base_fee_toman']!),
                ('هر روز', _custom['price_per_day_toman']!),
                ('هر گیگ', _custom['price_per_gb_toman']!),
                ('نامحدود / روز', _custom['unlimited_day_fee_toman']!),
                ('هر دستگاه', _custom['price_per_ip_toman']!),
                ('حداقل قیمت', _custom['min_price_toman']!),
              ]),
              TgButton(
                label: 'ذخیره تنظیمات پکیج',
                height: 40,
                onPressed: busy
                    ? null
                    : () async {
                        final v = _ints(_custom);
                        if (v == null) return;
                        final r = await c.run(() => c.api.adminSetCustomSettings({'enabled': customEnabled, ...v}), success: 'تنظیمات ساخت پکیج ذخیره شد');
                        if (r != null) _applyCustom(r);
                      },
              ),
            ],
          ),
        ),
        AdminAccordion(
          icon: Icons.speed_rounded,
          title: 'پرداخت مصرفی',
          summary: pg == null ? 'در حال بارگذاری…' : (pg.b('enabled') ? '${faNum(pg.i('price_per_gb_toman'))} تومان / GB' : 'غیرفعال'),
          open: open == 'payg',
          onToggle: () => _toggle('payg'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('ابری: شارژ کیف‌پول و پرداخت بر اساس مصرف واقعی. خرید حجم: پکیج گیگ بدون محدودیت زمان.', style: t(11, c: C.n400, h: 1.6)),
              const Gap(6),
              CheckLine(value: paygEnabled, label: 'فعال برای کاربران', onChanged: (v) => setState(() => paygEnabled = v)),
              const Gap(8),
              NumGrid(fields: [
                ('قیمت هر گیگ ابری', _payg['price_per_gb_toman']!),
                ('قیمت هر گیگ حجم', _payg['prepaid_price_per_gb_toman']!),
                ('حداقل موجودی ابری', _payg['min_wallet_toman']!),
                ('دستگاه ابری', _payg['limit_ip']!),
                ('حداقل GB حجم', _payg['min_gb']!),
                ('حداکثر GB حجم', _payg['max_gb']!),
                ('حداقل دستگاه حجم', _payg['min_ip']!),
                ('حداکثر دستگاه حجم', _payg['max_ip']!),
                ('قیمت هر دستگاه حجم', _payg['price_per_ip_toman']!),
                ('حداقل قیمت حجم', _payg['min_price_toman']!),
              ]),
              TgButton(
                label: 'ذخیره تنظیمات مصرفی',
                height: 40,
                onPressed: busy
                    ? null
                    : () async {
                        final v = _ints(_payg);
                        if (v == null) return;
                        final r = await c.run(() => c.api.adminSetPaygSettings({'enabled': paygEnabled, ...v}), success: 'تنظیمات پرداخت مصرفی ذخیره شد');
                        if (r != null) _applyPayg(r);
                      },
              ),
            ],
          ),
        ),
        AdminAccordion(
          icon: Icons.local_offer_outlined,
          title: 'تخفیف خرید و خانواده',
          summary: 'تخفیف هنگام خرید، کد، پکیج خانواده',
          open: open == 'growth',
          onToggle: () => _toggle('growth'),
          child: const GrowthAdminPanel(),
        ),
        AdminAccordion(
          icon: Icons.public_rounded,
          title: 'سرورهای کشورها',
          summary: 'پنل‌های 3x-ui برای اشتراک کاربران',
          open: open == 'servers',
          onToggle: () => _toggle('servers'),
          child: const AdminServersPanel(),
        ),
        AdminAccordion(
          icon: Icons.credit_card_rounded,
          title: 'کارت‌های پرداخت',
          summary: '${faNum(ctl.adminPaymentCards.length)} کارت فعال',
          open: open == 'cards',
          onToggle: () => _toggle('cards'),
          child: _paymentCards(ctl, busy),
        ),
        AdminAccordion(
          icon: Icons.campaign_outlined,
          title: 'پیام همگانی',
          summary: 'ارسال اعلان به همه کاربران',
          open: open == 'broadcast',
          onToggle: () => _toggle('broadcast'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AreaField(controller: _broadcast, hint: 'متن پیام…', lines: 4, onChanged: (_) => setState(() {})),
              const Gap(8),
              TgButton(
                label: 'ارسال',
                height: 40,
                onPressed: busy || _broadcast.text.trim().length < 2
                    ? null
                    : () async {
                        final r = await c.run(() => c.api.adminBroadcast(_broadcast.text.trim()));
                        if (r == null) return;
                        _broadcast.clear();
                        setState(() {});
                        notify('ارسال شد: ${faNum(r.i('sent'))} از ${faNum(r.i('total'))} کاربر', ToastStatus.success);
                      },
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// checkout-panel.tsx `AdminPaymentCardsPanel`.
  Widget _paymentCards(BLController ctl, bool busy) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final card in ctl.adminPaymentCards) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: C.w(5), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(12))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(card.text('label') ?? card.text('name') ?? 'کارت', style: t(14, w: 600)),
                      Text(card.text('name') ?? '—', style: t(13, c: C.n300)),
                      const Gap(4),
                      Text(card.s('card'), textDirection: TextDirection.ltr, style: t(12, c: C.n400, mono: true)),
                    ],
                  ),
                ),
                TgButton(
                  label: 'حذف',
                  variant: BtnVariant.outline,
                  expand: false,
                  height: 36,
                  fontSize: 12,
                  onPressed: busy
                      ? null
                      : () async {
                          final r = await c.run(() => c.api.adminRemovePaymentCard(card.i('id')), success: 'کارت حذف شد');
                          if (r != null) await c.refreshAdmin();
                        },
                ),
              ],
            ),
          ),
          const Gap(8),
        ],
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: C.b(40), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(12))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const FieldLabel('افزودن کارت جدید'),
              const Gap(8),
              BLInput(controller: _card['card'], hint: '6037-1234-5678-9012', ltr: true, numeric: true, onChanged: (_) => setState(() {})),
              const Gap(8),
              BLInput(controller: _card['name'], hint: 'نام صاحب حساب'),
              const Gap(8),
              BLInput(controller: _card['label'], hint: 'برچسب (مثلاً بانک ملت)'),
              const Gap(8),
              BLInput(controller: _card['note'], hint: 'یادداشت برای کاربر (اختیاری)', maxLines: 2, minLines: 2),
              const Gap(8),
              TgButton(
                label: 'افزودن کارت',
                onPressed: busy || digitsOnly(_card['card']!.text).length < 16
                    ? null
                    : () async {
                        final r = await c.run(
                          () => c.api.adminAddPaymentCard({for (final e in _card.entries) e.key: e.value.text.trim()}),
                          success: 'کارت اضافه شد',
                        );
                        if (r == null) return;
                        for (final x in _card.values) {
                          x.clear();
                        }
                        await c.refreshAdmin();
                      },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
