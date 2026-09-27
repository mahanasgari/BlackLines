import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hiddify/features/blacklines/core/api.dart';
import 'package:hiddify/features/blacklines/core/format.dart';
import 'package:hiddify/features/blacklines/core/json.dart';
import 'package:hiddify/features/blacklines/screens/admin/admin_widgets.dart';
import 'package:hiddify/features/blacklines/screens/admin/user_sheet.dart';
import 'package:hiddify/features/blacklines/state/controller.dart';
import 'package:hiddify/features/blacklines/ui/kit.dart';
import 'package:hiddify/features/blacklines/ui/tokens.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _funnelSlice = {'registered': 'all', 'config': 'active', 'paying': 'paying', 'pro': 'pro'};

int _pct(int part, int whole) => whole == 0 ? 0 : (100 * part / whole).round();

/// admin-analytics.tsx `AdminAnalyticsPanel`.
class AdminAnalyticsPanel extends ConsumerStatefulWidget {
  const AdminAnalyticsPanel({super.key});

  @override
  ConsumerState<AdminAnalyticsPanel> createState() => _AdminAnalyticsPanelState();
}

class _AdminAnalyticsPanelState extends ConsumerState<AdminAnalyticsPanel> {
  int days = 30;
  String page = 'users';
  bool includeTest = false;
  J? data;
  bool loading = true;
  String? error;
  List<J> expiring = const [];

  BLController get c => ref.read(blControllerProvider);

  @override
  void initState() {
    super.initState();
    _load();
    _loadExpiring();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final d = await c.api.adminAnalytics(days: days, includeTest: includeTest);
      if (mounted) setState(() => data = d);
    } catch (e) {
      if (mounted) setState(() => error = persianError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _loadExpiring() async {
    try {
      final r = await c.api.adminExpiring(includeTest: includeTest);
      if (mounted) setState(() => expiring = r.objs('items'));
    } catch (_) {}
  }

  void _slice(String key, [String? title]) {
    showTgSheet(
      context,
      title: title ?? 'کاربران',
      description: 'برای دیدن پرونده لمس کنید',
      builder: (_) => _SliceList(slice: key, days: days, includeTest: includeTest),
    );
  }

  Future<void> _remind(int subId) async {
    try {
      await c.api.adminRemindExpiry(subId);
      notify('یادآوری ارسال شد', ToastStatus.success);
      setState(() => expiring = [for (final r in expiring) r.i('subscription_id') == subId ? r.merge({'reminded_3d': true}) : r]);
    } catch (e) {
      notify(persianError(e), ToastStatus.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: C.b(40), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(10))),
          child: Row(
            children: [
              for (final (id, label, icon) in const [('users', 'کاربران', Icons.group_outlined), ('finance', 'مالی', Icons.account_balance_wallet_outlined)])
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => page = id),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(color: page == id ? C.primary : Colors.transparent, borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon, size: 14, color: page == id ? C.primaryFg : C.n400),
                          const Gap(6),
                          Text(label, style: t(12, w: 600, c: page == id ? C.primaryFg : C.n400)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const Gap(12),
        CheckLine(
          value: includeTest,
          small: true,
          label: 'نمایش کاربران تست در آمار${!includeTest && (d?.i('hidden_test_users') ?? 0) > 0 ? ' · ${faNum(d!.i('hidden_test_users'))} مخفی' : ''}',
          onChanged: (v) {
            setState(() => includeTest = v);
            _load();
            _loadExpiring();
          },
        ),
        const Gap(8),
        Row(
          children: [
            for (final (id, label) in const [(1, 'امروز'), (7, '۷ روز'), (30, '۳۰ روز'), (0, 'کل')]) ...[
              if (id != 1) const Gap(6),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() => days = id);
                    _load();
                  },
                  child: Container(
                    height: 32,
                    decoration: BoxDecoration(
                      color: days == id ? C.w(12) : C.b(30),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: days == id ? C.w(20) : C.w(10)),
                    ),
                    child: Center(child: Text(label, style: t(11, w: 600, c: days == id ? C.white : C.n400))),
                  ),
                ),
              ),
            ],
          ],
        ),
        const Gap(12),
        if (d?.objOrNull('compare') case final cmp?) ...[_compare(cmp), const Gap(12)],
        if (loading) Padding(padding: const EdgeInsets.symmetric(vertical: 32), child: Text('در حال جمع‌آوری آمار…', textAlign: TextAlign.center, style: t(12, c: C.n500))),
        if (error != null && !loading) Text(error!, textAlign: TextAlign.center, style: t(12, c: C.orange300)),
        if (!loading && d != null) page == 'users' ? _usersPage(d) : _financePage(d),
      ],
    );
  }

  // ---------------------------------------------------------------- pieces

  Widget _title(IconData icon, String title, [String? hint]) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(icon, size: 14, color: C.n300),
            const Gap(6),
            Expanded(child: Text(title, style: t(12, w: 600, c: C.n300))),
            if (hint != null) Text(hint, style: t(10, c: C.n500)),
          ],
        ),
      );

  Widget _card(Widget child) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: C.b(30), borderRadius: BorderRadius.circular(16), border: Border.all(color: C.w(10))),
        child: child,
      );

  Widget _kpi(String label, String value, {String? hint, bool accent = false, VoidCallback? onTap}) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: C.b(30), borderRadius: BorderRadius.circular(16), border: Border.all(color: C.w(10))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: t(10, c: C.n500)),
                const Gap(2),
                Text(value, style: t(accent ? 16 : 14, w: 700, c: accent ? C.emerald200 : null, h: 1.2)),
                if (hint != null) ...[const Gap(2), Text(hint, style: t(10, c: C.n500))],
              ],
            ),
          ),
        ),
      );

  Widget _kpiGrid(List<Widget> items) => Column(
        children: [
          for (var i = 0; i < items.length; i += 2)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: items[i]),
                  const Gap(8),
                  Expanded(child: i + 1 < items.length ? items[i + 1] : const SizedBox.shrink()),
                ],
              ),
            ),
        ],
      );

  Widget _bar(num share) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Stack(
            children: [
              Container(height: 6, color: C.w(8)),
              FractionallySizedBox(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: math.max(share > 0 ? 0.04 : 0, math.min(1, share / 100)).toDouble(),
                child: Container(height: 6, decoration: BoxDecoration(color: C.a(C.sky300, 0.75), borderRadius: BorderRadius.circular(999))),
              ),
            ],
          ),
        ),
      );

  Widget _mix(String title, String value, num share, {String? meta, VoidCallback? onTap}) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(title, overflow: TextOverflow.ellipsis, style: t(12, c: C.n200))),
                  Text(value, style: t(12, c: C.n300)),
                  if (meta != null) ...[const Gap(4), Text(meta, style: t(10, c: C.n500))],
                ],
              ),
              _bar(share),
            ],
          ),
        ),
      );

  Widget _miniBars(List<J> points, {bool money = false}) {
    num v(J p) => money ? p.d('toman') : p.i('count');
    final max = points.map(v).fold<num>(1, math.max);
    if (!points.any((p) => v(p) > 0)) {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text('در این بازه داده‌ای نیست', textAlign: TextAlign.center, style: t(11, c: C.n500)));
    }
    final slim = points.length > 14;
    return SizedBox(
      height: slim ? 80 : 64,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final p in points)
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: slim ? 0.5 : 2),
                child: Tooltip(
                  message: money ? p.text('label_money') ?? p.s('label') : '${p.s('label')}: ${faNum(p.i('count'))}',
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(
                        child: FractionallySizedBox(
                          heightFactor: math.max(v(p) > 0 ? 0.08 : 0.02, v(p) / max).toDouble(),
                          child: Container(decoration: BoxDecoration(color: C.a(C.sky300, 0.8), borderRadius: BorderRadius.circular(2))),
                        ),
                      ),
                      if (!slim) ...[const Gap(4), Text(faDigits(p.s('label')), style: t(8, c: C.n500))],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _compare(J cmp) {
    Widget delta(String label, J row, String slice, String title, {bool money = false}) {
      final dlt = row.d('delta');
      final color = dlt > 0 ? C.emerald300 : (dlt < 0 ? C.orange300 : C.n500);
      return Expanded(
        child: GestureDetector(
          onTap: () => _slice(slice, title),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: C.b(30), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(10))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: t(10, c: C.n500)),
                const Gap(2),
                Text(money ? row.text('current_label') ?? faNum(row.d('current')) : faNum(row.d('current')), style: t(12, w: 700)),
                const Gap(2),
                Text(
                  '${dlt > 0 ? '+' : ''}${money ? row.text('delta_label') ?? faNum(dlt) : faNum(dlt)}${dlt != 0 ? ' · ${faNum(row.d('delta_pct').abs())}٪' : ''}',
                  style: t(10, c: color),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(cmp.s('label'), style: t(10, c: C.n500)),
        const Gap(6),
        Row(
          children: [
            delta('کاربران جدید', cmp.obj('new_users'), 'new', 'کاربران جدید'),
            const Gap(6),
            delta('واریز کارت', cmp.obj('cash_in'), 'paying_period', 'خرید در این بازه', money: true),
            const Gap(6),
            delta('تبدیل تست', cmp.obj('trial_converted'), 'trial_converted', 'تبدیل تست به خرید'),
          ],
        ),
      ],
    );
  }

  Widget _usersPage(J d) {
    final users = d.obj('users');
    final k = users.obj('kpis');
    final cfg = users.obj('configs');
    final a = users.obj('activity');
    final funnel = users.objs('funnel');
    final maxFunnel = funnel.map((f) => f.i('count')).fold(1, math.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(Icons.schedule_rounded, 'منقضی می‌شود', '۳ روز آینده'),
        if (expiring.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(10))),
            child: Text('کانفیگی در ۳ روز آینده تمام نمی‌شود', textAlign: TextAlign.center, style: t(11, c: C.n500)),
          )
        else
          for (final row in expiring) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: C.a(C.amber500, 0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.a(C.amber400, 0.2))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GestureDetector(
                    onTap: () => openAdminUserSheet(context, row.i('user_id')),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(row.text('full_name') ?? (row.text('username') != null ? '@${row.s('username')}' : faNum(row.i('telegram_id'))), style: t(14, w: 600)),
                              Text(row.s('label'), overflow: TextOverflow.ellipsis, style: t(11, c: C.n400)),
                            ],
                          ),
                        ),
                        Text(row.s('days_left_label'), style: t(11, w: 600, c: C.amber200)),
                      ],
                    ),
                  ),
                  const Gap(8),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TgButton(
                      label: row.b('reminded_1d') || row.b('reminded_3d') ? 'ارسال دوباره یادآوری' : 'ارسال یادآوری',
                      variant: BtnVariant.outline,
                      expand: false,
                      height: 32,
                      fontSize: 11,
                      onPressed: () => _remind(row.i('subscription_id')),
                    ),
                  ),
                ],
              ),
            ),
            const Gap(8),
          ],
        const Gap(8),
        _title(Icons.group_outlined, 'پایگاه کاربران', '${d.s('period_label')} · لمس کنید'),
        _kpiGrid([
          _kpi('کل کاربران', faNum(k.i('total_users')), hint: '${faNum(k.i('new_users'))} جدید', onTap: () => _slice('all', 'همه کاربران')),
          _kpi('مشتری خرید کرده', faNum(k.i('paying_users')), hint: '${faNum(k.i('active_customers'))} کانفیگ فعال', onTap: () => _slice('paying', 'خرید کرده‌اند')),
          _kpi('دعوت‌شده', faNum(k.i('referred_users')), hint: '${faNum(k.i('pro_users'))} کاربر Pro', onTap: () => _slice('referred', 'دعوت‌شده')),
          _kpi('تست گرفته', faNum(k.i('trial_granted')), hint: '${faNum(k.i('trial_converted'))} تبدیل به خرید', onTap: () => _slice('trial', 'تست گرفته')),
          _kpi('در حال انقضا', faNum(k.i('expiring')), hint: '۳ روز آینده', onTap: () => _slice('expiring', 'در حال انقضا')),
          _kpi('کیف‌پول', faNum(k.i('with_wallet')), hint: '${faNum(k.i('admins'))} ادمین', onTap: () => _slice('wallet', 'کیف‌پول دارند')),
        ]),
        const Gap(8),
        _title(Icons.bar_chart_rounded, 'مسیر تبدیل'),
        _card(Column(children: [
          for (final f in funnel)
            _mix(f.s('title'), faNum(f.i('count')), (f.i('count') / maxFunnel * 100).round(), onTap: () => _slice(_funnelSlice[f.s('key')] ?? f.s('key'), f.s('title'))),
        ])),
        const Gap(16),
        _title(Icons.bar_chart_rounded, 'ثبت‌نام روزانه'),
        _card(_miniBars(users.objs('signups'))),
        const Gap(16),
        _title(Icons.show_chart_rounded, 'کانفیگ‌ها', '${faNum(cfg.i('active_share'))}٪ فعال'),
        _kpiGrid([
          _kpi('کل کانفیگ', faNum(cfg.i('total')), hint: '${faNum(cfg.i('new'))} در این بازه', onTap: () => _slice('has_config', 'دارای کانفیگ')),
          _kpi('فعال', faNum(cfg.i('active')), hint: '${faNum(cfg.i('expired'))} منقضی · ${faNum(cfg.i('disabled'))} قطع', onTap: () => _slice('active', 'کانفیگ فعال')),
          _kpi('عادی / سفارشی', faNum(cfg.i('regular')), onTap: () => _slice('has_config', 'دارای کانفیگ')),
          _kpi('ابری + حجم', faNum(cfg.i('metered') + cfg.i('prepaid')), hint: '${faNum(cfg.i('trial'))} تست', onTap: () => _slice('payg', 'ابری / حجم')),
        ]),
        _card(Column(children: [
          _mix('فعال', faNum(cfg.i('active')), _pct(cfg.i('active'), cfg.i('total')), onTap: () => _slice('active', 'فعال')),
          _mix('منقضی', faNum(cfg.i('expired')), _pct(cfg.i('expired'), cfg.i('total')), onTap: () => _slice('expired', 'منقضی')),
          _mix('غیرفعال', faNum(cfg.i('disabled')), _pct(cfg.i('disabled'), cfg.i('total')), onTap: () => _slice('disabled', 'قطع')),
          _mix('حساب تست', faNum(cfg.i('trial')), _pct(cfg.i('trial'), cfg.i('total')), onTap: () => _slice('trial_config', 'حساب تست')),
        ])),
        const Gap(16),
        _title(Icons.show_chart_rounded, 'فعالیت'),
        _kpiGrid([
          _kpi('آنلاین الان', faNum(a.i('online_now')), hint: '${faNum(a.i('used_24h'))} مصرف ۲۴ساعت', onTap: () => _slice('online', 'آنلاین الان')),
          _kpi('سفارش بازه', faNum(a.i('orders_new')), hint: '${faNum(a.i('pending_orders'))} در انتظار', onTap: () => _slice('pending', 'سفارش باز')),
          _kpi('پیام‌ها', faNum(a.i('chat_total')), hint: '${faNum(a.i('chat_from_users'))} از کاربر', onTap: () => _slice('unread', 'پیام خوانده‌نشده')),
          _kpi('خوانده‌نشده', faNum(a.i('chat_unread')), hint: '${faNum(a.i('chat_from_admins'))} پاسخ ادمین', onTap: () => _slice('unread', 'پیام خوانده‌نشده')),
        ]),
      ],
    );
  }

  Widget _financePage(J d) {
    final f = d.obj('finance');
    final k = f.obj('kpis');
    final notes = f.obj('notes');
    String m(String key) => k.obj(key).s('label');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(Icons.account_balance_wallet_outlined, 'خلاصه حساب', '${faNum(k.i('order_count'))} سفارش تاییدشده · لمس کنید'),
        _kpi('واریز به کارت', m('cash_in'), accent: true, onTap: () => _slice('paying_period', 'خرید در این بازه')),
        const Gap(8),
        _kpi('فروش محصول', m('product_revenue'), hint: 'شامل مصرف ابری', onTap: () => _slice('paying_period', 'خرید در این بازه')),
        const Gap(8),
        _kpi('برآورد خالص شما', m('estimate_owned'), hint: 'کارت − برداشت − مانده کیف‌پول', onTap: () => _slice('wallet', 'کیف‌پول دارند')),
        const Gap(8),
        _kpiGrid([
          _kpi('نقد پس از برداشت', m('net_cash'), onTap: () => _slice('paying_period', 'خرید در این بازه')),
          _kpi('مانده کیف‌پول کاربران', m('wallet_liability'), onTap: () => _slice('wallet', 'کیف‌پول دارند')),
          _kpi('پورسانت دعوت', m('commissions'), onTap: () => _slice('referred', 'دعوت‌شده')),
          _kpi('برداشت پرداخت‌شده', m('withdrawals_paid'), onTap: () => _slice('wallet', 'کیف‌پول دارند')),
        ]),
        _title(Icons.bar_chart_rounded, 'درآمد هر بخش'),
        _card(Column(children: [
          for (final row in f.objs('kinds'))
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _slice(row.s('key') == 'wallet_topup' ? 'wallet' : 'paying_period', row.s('title')),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [Expanded(child: Text(row.s('title'), style: t(12, c: C.n200))), Text(row.s('label'), style: t(12, c: C.n300))]),
                    const Gap(2),
                    Row(
                      children: [
                        Expanded(child: Text('${faNum(row.i('count'))} سفارش', style: t(10, c: C.n500))),
                        Text('کارت ${row.s('card_label')}${row.i('wallet') > 0 ? ' · کیف‌پول ${row.s('wallet_label')}' : ''}', style: t(10, c: C.n500)),
                      ],
                    ),
                    _bar(row.d('share')),
                  ],
                ),
              ),
            ),
        ])),
        if (f.objs('plans').isNotEmpty) ...[
          const Gap(16),
          _title(Icons.bar_chart_rounded, 'فروش بر اساس پلن'),
          _card(Column(children: [
            for (final p in f.objs('plans'))
              _mix(p.s('title'), p.s('label'), p.d('share'), meta: '${faNum(p.i('count'))} عدد', onTap: () => _slice('paying_period', p.s('title'))),
          ])),
        ],
        const Gap(16),
        _title(Icons.bar_chart_rounded, 'فروش روزانه'),
        _card(_miniBars(f.objs('daily'), money: true)),
        const Gap(16),
        _title(Icons.account_balance_wallet_outlined, 'کیف‌پول و تعهدات'),
        _kpiGrid([
          _kpi('شارژ کیف‌پول', m('wallet_topups'), onTap: () => _slice('wallet', 'کیف‌پول دارند')),
          _kpi('خرج از کیف‌پول', m('wallet_spent'), onTap: () => _slice('paying_period', 'خرید در این بازه')),
          _kpi('مصرف ابری', m('metered_billed'), onTap: () => _slice('payg', 'ابری / حجم')),
          _kpi(
            'برداشت در انتظار',
            m('withdrawals_pending'),
            hint: f.i('pending_order_count') > 0 ? '${faNum(f.i('pending_order_count'))} سفارش باز' : null,
            onTap: () => _slice('pending', 'سفارش باز'),
          ),
        ]),
        if (k.obj('pending_orders').i('toman') > 0) ...[
          _kpi('مبلغ سفارش‌های در انتظار', m('pending_orders'), onTap: () => _slice('pending', 'سفارش باز')),
          const Gap(8),
        ],
        _card(Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final key in const ['cash', 'product', 'wallet', 'metered', 'owned'])
              if (notes.text(key) != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(notes.s(key), style: t(11, c: C.n400, h: 1.6))),
          ],
        )),
      ],
    );
  }
}

class _SliceList extends ConsumerStatefulWidget {
  const _SliceList({required this.slice, required this.days, required this.includeTest});

  final String slice;
  final int days;
  final bool includeTest;

  @override
  ConsumerState<_SliceList> createState() => _SliceListState();
}

class _SliceListState extends ConsumerState<_SliceList> {
  List<J>? items;

  @override
  void initState() {
    super.initState();
    ref.read(blControllerProvider).api.adminUsers(includeTest: widget.includeTest, slice: widget.slice, days: widget.days).then((r) {
      if (mounted) setState(() => items = r.objs('items'));
    }).catchError((Object e) {
      notify(persianError(e), ToastStatus.error);
      if (mounted) setState(() => items = const []);
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = items;
    if (list == null) {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 32), child: Text('در حال بارگذاری…', textAlign: TextAlign.center, style: t(14, c: C.n400)));
    }
    if (list.isEmpty) {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 32), child: Text('کسی در این فیلتر نیست', textAlign: TextAlign.center, style: t(14, c: C.n500)));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final u in list) ...[
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => openAdminUserSheet(context, u.i('id')),
              child: Ink(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: C.b(30), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(10))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(u.text('full_name') ?? (u.text('username') != null ? '@${u.s('username')}' : faNum(u.i('telegram_id'))), style: t(14, w: 600)),
                    Text('${u.text('username') != null ? '@${u.s('username')} · ' : ''}${u.i('telegram_id')}', textDirection: TextDirection.ltr, style: t(10, c: C.n500, mono: true)),
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
