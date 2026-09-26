import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hiddify/features/blacklines/core/api.dart';
import 'package:hiddify/features/blacklines/core/format.dart';
import 'package:hiddify/features/blacklines/core/json.dart';
import 'package:hiddify/features/blacklines/screens/common.dart';
import 'package:hiddify/features/blacklines/screens/sheets/family_parental.dart';
import 'package:hiddify/features/blacklines/screens/sheets/wallet_sheet.dart';
import 'package:hiddify/features/blacklines/screens/shop/builders.dart';
import 'package:hiddify/features/blacklines/state/controller.dart';
import 'package:hiddify/features/blacklines/ui/kit.dart';
import 'package:hiddify/features/blacklines/ui/tokens.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Holds the loaded detail so both the sheet title and body can react to it.
class _DetailState extends ChangeNotifier {
  J? detail;
  bool loading = true;

  void set(J? d) {
    detail = d;
    notifyListeners();
  }

  void patch(Map<String, dynamic> p) => set(detail?.merge(p));
}

/// subscription-detail-sheet.tsx.
Future<void> openSubDetail(BuildContext context, int subId, {String? tab}) {
  final state = _DetailState();
  return showTgSheet(
    context,
    title: 'جزئیات کانفیگ',
    titleWidget: Consumer(
      builder: (context, ref, _) => ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final d = state.detail;
          final title = d?.text('label') ?? d?.text('plan_title') ?? 'جزئیات کانفیگ';
          return EditableConfigName(
            name: title,
            disabled: d == null,
            style: t(14, w: 600, c: C.white),
            onSave: (label) async {
              final c = ref.read(blControllerProvider);
              await c.renameConfig(subId, label);
              state.patch({'label': label});
            },
          );
        },
      ),
    ),
    builder: (_) => _DetailBody(subId: subId, initialTab: tab, state: state),
  ).whenComplete(state.dispose);
}

class _DetailBody extends ConsumerStatefulWidget {
  const _DetailBody({required this.subId, required this.state, this.initialTab});

  final int subId;
  final String? initialTab;
  final _DetailState state;

  @override
  ConsumerState<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends ConsumerState<_DetailBody> {
  String tab = 'connect';
  bool busy = false;
  bool renewCustom = false;
  int? renewPlanId;
  bool confirmRotate = false;
  bool confirmRevoke = false;
  bool confirmTransfer = false;
  bool linkRotated = false;
  bool serversOpen = false;
  String? actionError;
  J? transferPreview;
  final _label = TextEditingController();
  final _transfer = TextEditingController();
  final _cust = {
    'customer_name': TextEditingController(),
    'customer_email': TextEditingController(),
    'customer_phone': TextEditingController(),
    'customer_telegram_id': TextEditingController(),
  };

  BLController get c => ref.read(blControllerProvider);
  J? get d => widget.state.detail;

  @override
  void initState() {
    super.initState();
    _load(first: true);
  }

  @override
  void dispose() {
    _label.dispose();
    _transfer.dispose();
    for (final e in _cust.values) {
      e.dispose();
    }
    super.dispose();
  }

  Future<void> _load({bool first = false}) async {
    widget.state.loading = true;
    if (mounted) setState(() {});
    try {
      final data = await c.api.subscriptionDetail(widget.subId);
      widget.state.set(data);
      _label.text = data.text('label') ?? '';
      for (final e in _cust.entries) {
        e.value.text = data.text(e.key) ?? '';
      }
      renewPlanId = data.intOrNull('plan_id');
      if (first) {
        final days = data.intOrNull('remaining_days');
        final expired = data.s('status') == 'expired' || data.b('expired');
        tab = widget.initialTab ?? (expired || (days != null && days <= 5) ? 'renew' : 'connect');
      }
    } catch (e) {
      notify(persianError(e), ToastStatus.error);
    } finally {
      widget.state.loading = false;
      if (mounted) setState(() {});
    }
  }

  Future<T?> _guard<T>(Future<T> Function() fn) async {
    setState(() {
      busy = true;
      actionError = null;
    });
    try {
      return await fn();
    } catch (e) {
      if (mounted) setState(() => actionError = persianError(e));
      return null;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _markShared() {
    if (d?.text('customer_name') == null) return;
    c.markShared(widget.subId);
  }

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final detail = d;
    if (widget.state.loading && detail == null) return const OrbLoaderPanel();
    if (detail == null) return const EmptyState(message: 'اطلاعات کانفیگ دریافت نشد.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(detail.s('email'), textDirection: TextDirection.ltr, textAlign: TextAlign.end, style: t(11, c: C.n400, mono: true)),
        const Gap(8),
        _StatusCard(detail: detail),
        const Gap(12),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: C.b(35), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(10))),
          child: Row(
            children: [
              for (final (id, label) in [
                ('connect', 'اتصال'),
                ('usage', 'مصرف'),
                ('renew', detail.b('is_payg') ? 'شارژ' : 'تمدید'),
                ('more', 'بیشتر'),
              ])
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      haptic();
                      setState(() => tab = id);
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(color: tab == id ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(8)),
                      child: Text(label, textAlign: TextAlign.center, style: t(11, w: 500, c: tab == id ? Colors.black : C.n400)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const Gap(12),
        switch (tab) {
          'usage' => _usage(detail),
          'renew' => _renew(detail),
          'more' => _more(detail),
          _ => _connect(detail),
        },
      ],
    );
  }

  // ------------------------------------------------------------------ connect

  J? _bestLink(J detail) {
    final links = detail.objs('links');
    if (links.isEmpty) return null;
    final good = links.where((l) => l.s('kind') != 'telegram' && l.b('reachable') && l.intOrNull('ping_ms') != null).toList()
      ..sort((a, b) => a.i('ping_ms', 99999).compareTo(b.i('ping_ms', 99999)));
    if (good.isNotEmpty) return good.first;
    return links.firstWhere((l) => l.s('kind') != 'telegram', orElse: () => links.first);
  }

  Widget _connect(J detail) {
    final url = detail.text('subscription_url');
    final best = _bestLink(detail);
    final family = detail.objOrNull('family');
    final live = detail.b('enabled') && !detail.b('expired');
    final links = detail.objs('links');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: C.a(C.emerald500, 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: C.a(C.emerald500, 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.auto_awesome, size: 16, color: C.emerald300)),
                  const Gap(8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('اتصال سریع', style: t(14, w: 600, c: C.emerald100)),
                        const Gap(4),
                        Text(
                          url != null
                              ? 'با یک ضربه همین‌جا در برنامه وصل شو، یا لینک را کپی کن.'
                              : 'لینک کانفیگ را کپی کنید.',
                          style: t(11, c: C.n400, h: 1.6),
                        ),
                        if (detail.text('customer_name') != null) ...[
                          const Gap(8),
                          Callout(
                            'این کانفیگ برای ${detail.s('customer_name')} است. لینک را از همین‌جا یا میز فروش برایش بفرست.',
                            tone: Tone.teal,
                          ),
                        ],
                        if (family != null) ...[
                          const Gap(8),
                          Callout(
                            family.b('is_parent')
                                ? 'این کانفیگ والد خانواده است. لینک را برای خودت نگه دار و لینک هر فرزند را جدا بفرست.'
                                : 'این کانفیگ یکی از اعضای خانواده است. همین لینک را برای همان نفر بفرست — بقیه کانفیگ‌ها جدا هستند.',
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const Gap(12),
              if (url != null && live) ...[
                TgButton(
                  label: 'اتصال در همین برنامه',
                  icon: Icons.power_settings_new_rounded,
                  onPressed: () {
                    _close();
                    connectInApp(ref, url, name: detail.text('label') ?? detail.text('customer_name') ?? detail.text('plan_title'));
                  },
                ),
                const Gap(8),
              ],
              if (url != null)
                TgButton(
                  label: 'کپی لینک Subscription',
                  icon: Icons.copy_rounded,
                  variant: live ? BtnVariant.outline : BtnVariant.primary,
                  onPressed: () {
                    copyText(url);
                    _markShared();
                  },
                )
              else if (best != null)
                TgButton(
                  label: 'کپی لینک کانفیگ${best.intOrNull('ping_ms') != null ? ' · ${faNum(best.i('ping_ms'))}ms' : ''}',
                  icon: Icons.copy_rounded,
                  onPressed: () => copyText(best.s('link')),
                )
              else
                Text('لینکی برای این کانفیگ موجود نیست.', style: t(11, c: C.n500)),
              const Gap(8),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    haptic();
                    _openSelfFix(detail);
                  },
                  child: Ink(
                    height: 40,
                    decoration: BoxDecoration(
                      color: C.a(C.amber500, 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: C.a(C.amber400, 0.25)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.wifi_off_rounded, size: 14, color: C.amber100),
                        const Gap(6),
                        Text('وصل نمیشه؟ تست و تعمیر', style: t(12, w: 600, c: C.amber100)),
                      ],
                    ),
                  ),
                ),
              ),
              const Gap(8),
              Row(
                children: [
                  if (url != null && best != null) ...[
                    Expanded(child: _SmallBtn(icon: Icons.copy_rounded, label: 'بهترین سرور', onTap: () => copyText(best.s('link')))),
                    const Gap(8),
                  ],
                  Expanded(
                    child: _SmallBtn(
                      icon: Icons.copy_rounded,
                      label: 'کپی Base64',
                      onTap: () => copyText(detail.s('subscription_import')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (linkRotated) ...[
          const Gap(12),
          const Callout('لینک جدید ساخته شد و کپی شد. لینک قبلی دیگر کار نمی‌کند — در اپ Subscription را آپدیت کن.', tone: Tone.emerald),
        ],
        if (live) ...[
          const Gap(12),
          _Box(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _IconTitle(
                  icon: Icons.key_rounded,
                  title: 'باطل کردن و لینک جدید',
                  text: 'اگر لینک لو رفته، لینک فعلی را باطل کن و لینک تازه بگیر. حجم و تاریخ انقضا عوض نمی‌شود.',
                ),
                if (actionError != null && tab == 'connect') ...[const Gap(8), Callout(actionError!, tone: Tone.red)],
                const Gap(8),
                if (!confirmRotate)
                  TgButton(
                    label: 'لینک جدید',
                    icon: Icons.key_rounded,
                    variant: BtnVariant.outline,
                    height: 36,
                    fontSize: 12,
                    onPressed: busy
                        ? null
                        : () {
                            haptic();
                            setState(() => confirmRotate = true);
                          },
                  )
                else ...[
                  Text('لینک فعلی قطع می‌شود. مطمئنی؟', style: t(11, c: C.a(C.amber100, 0.9))),
                  const Gap(8),
                  _TwoButtons(
                    cancel: () => setState(() => confirmRotate = false),
                    confirmLabel: busy ? 'در حال ساخت…' : 'تایید و لینک جدید',
                    confirm: busy ? null : () => _rotate(),
                  ),
                ],
              ],
            ),
          ),
        ],
        const Gap(12),
        Collapsible(
          title: 'لیست سرورها · ${faNum(links.length)}',
          icon: Icons.link_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SmallBtn(label: 'کپی همه لینک‌ها', onTap: () => copyText(detail.s('links_text'), message: 'همه لینک‌ها کپی شد')),
              const Gap(6),
              for (final l in links) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: C.b(20),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: C.w(8)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: l.b('reachable') ? C.emerald400 : C.n600),
                      ),
                      const Gap(8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.s('label'), overflow: TextOverflow.ellipsis, style: t(12, w: 500, c: C.n200)),
                            if (l.text('host') != null)
                              Text(
                                '${l.s('host')}:${l.s('port')}',
                                textDirection: TextDirection.ltr,
                                overflow: TextOverflow.ellipsis,
                                style: t(10, c: C.n500, mono: true),
                              ),
                          ],
                        ),
                      ),
                      Text(l.intOrNull('ping_ms') != null ? '${faNum(l.i('ping_ms'))}ms' : '—', style: t(10, c: C.n500)),
                      if (l.s('kind') == 'telegram') ...[
                        const Gap(6),
                        GestureDetector(
                          onTap: () => openExternal(l.s('link')),
                          child: const Tag('باز کردن', tone: Tone.sky),
                        ),
                      ],
                      const Gap(6),
                      GestureDetector(
                        onTap: () => copyText(l.s('link')),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: C.w(5),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: C.w(10)),
                          ),
                          child: Icon(Icons.copy_rounded, size: 14, color: C.n300),
                        ),
                      ),
                    ],
                  ),
                ),
                const Gap(6),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _rotate() async {
    final res = await _guard(() => c.api.rotateSubscriptionLink(widget.subId));
    if (res == null) return;
    haptic();
    setState(() {
      confirmRotate = false;
      linkRotated = true;
      tab = 'connect';
    });
    notify('لینک جدید ساخته شد. لینک قبلی دیگر کار نمی‌کند.', ToastStatus.success);
    await _load();
    final url = res.text('subscription_url');
    if (url != null) {
      await copyText(url);
      _markShared();
    }
    await c.refreshDashboard();
    await c.refreshResellerDesk();
  }

  Future<void> _openSelfFix(J detail) => showTgSheet(
        context,
        title: 'وصل نمیشه؟',
        builder: (_) => _SelfFix(
          subId: widget.subId,
          onRenew: () => setState(() => tab = 'renew'),
          onRotated: () {
            setState(() => linkRotated = true);
            _load();
            c.refreshDashboard();
          },
        ),
      );

  // -------------------------------------------------------------------- usage

  Widget _usage(J detail) {
    final family = detail.objOrNull('family');
    final usage = detail.objOrNull('usage');
    final conn = detail.obj('connection');
    final presets = conn.strs('nickname_presets').isNotEmpty ? conn.strs('nickname_presets') : const ['موبایل', 'لپ‌تاپ', 'تبلت', 'کامپیوتر'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (family != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: C.a(C.sky500, 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: C.a(C.sky500, 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('مصرف اعضای خانواده', style: t(12, w: 600, c: C.sky100)),
                if (family.text('used_label') != null) ...[
                  const Gap(4),
                  Text('جمع پکیج: ${family.s('used_label')}', style: t(11, c: C.n400)),
                ],
                const Gap(8),
                for (final m in family.objs('members')) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: C.b(25),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: C.w(8)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m.text('label') ?? m.s('email'), overflow: TextOverflow.ellipsis, style: t(12, w: 500, c: C.n100)),
                              Text(m.b('is_parent') ? 'والد' : 'فرزند', style: t(10, c: C.n500)),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(m.text('used_label') ?? '۰', style: t(12, w: 600, c: C.n100)),
                            Text(m.b('online') ? 'آنلاین' : (m.text('total_label') ?? 'نامحدود'), style: t(10, c: C.n500)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Gap(6),
                ],
              ],
            ),
          ),
          const Gap(12),
        ],
        if (usage != null)
          _Box(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('تحلیل مصرف', style: t(12, w: 600, c: C.n200)),
                const Gap(10),
                Row(
                  children: [
                    Expanded(child: _StatTile('امروز', usage.s('today_label'))),
                    const Gap(8),
                    Expanded(child: _StatTile('۷ روز', usage.s('week_label'))),
                  ],
                ),
                const Gap(8),
                Row(
                  children: [
                    Expanded(child: _StatTile('میانگین روزانه', usage.s('avg_daily_label'))),
                    const Gap(8),
                    Expanded(child: _StatTile('آپلود / دانلود', '${detail.text('up_label') ?? '۰'} / ${detail.text('down_label') ?? '۰'}')),
                  ],
                ),
                if (usage.text('last_seen_label') != null) ...[
                  const Gap(8),
                  Text('آخرین فعالیت: ${usage.s('last_seen_label')}', style: t(11, c: C.n400)),
                ],
                if (usage.intOrNull('days_left') != null) ...[
                  const Gap(4),
                  Text('با همین روند حدود ${faNum(usage.i('days_left'))} روز حجم می‌ماند', style: t(11, c: C.n400)),
                ],
                if (usage.objs('daily').isNotEmpty) ...[const Gap(10), _DailyBars(days: usage.objs('daily'))],
              ],
            ),
          )
        else
          _Box(child: Text('هنوز آمار مصرفی ثبت نشده است.', textAlign: TextAlign.center, style: t(11, c: C.n500))),
        const Gap(12),
        _Box(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('دستگاه‌های متصل', style: t(12, w: 600, c: C.n200)),
              const Gap(8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(color: C.b(20), borderRadius: BorderRadius.circular(8), border: Border.all(color: C.w(8))),
                child: Row(
                  children: [
                    Icon(conn.b('online') ? Icons.wifi_rounded : Icons.wifi_off_rounded, size: 14, color: conn.b('online') ? C.emerald400 : C.n500),
                    const Gap(6),
                    Expanded(child: Text(conn.b('online') ? 'هم‌اکنون متصل' : 'قطع', style: t(11, c: C.n400))),
                    if (conn.b('ip_available')) Text('IP: ${_ipLimit(conn)}', style: t(10, c: C.n400)),
                  ],
                ),
              ),
              const Gap(8),
              if (conn.objs('connected_ips').isNotEmpty) ...[
                Text('با نام دستگاه برچسب بزنید', style: t(10, c: C.n500)),
                const Gap(6),
                for (final row in conn.objs('connected_ips')) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(color: C.b(20), borderRadius: BorderRadius.circular(8), border: Border.all(color: C.w(8))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(row.s('ip'), textDirection: TextDirection.ltr, textAlign: TextAlign.end, style: t(11, c: C.n200, mono: true)),
                            ),
                            if (row.text('at') != null) ...[const Gap(8), Text(relativeFa(row.date('at')), style: t(10, c: C.n500))],
                          ],
                        ),
                        const Gap(6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (final p in presets)
                              GestureDetector(
                                onTap: () => _setNickname(detail, row.s('ip'), row.text('nickname') == p ? '' : p),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: row.text('nickname') == p ? C.a(C.emerald500, 0.15) : C.b(30),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: row.text('nickname') == p ? C.a(C.emerald500, 0.4) : C.w(10)),
                                  ),
                                  child: Text(p, style: t(10, c: row.text('nickname') == p ? C.emerald200 : C.n400)),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Gap(6),
                ],
              ] else
                Text(
                  conn.b('online') ? 'IP هنوز ثبت نشده — چند ثانیه بعد بروزرسانی کنید.' : 'دستگاهی آنلاین نیست.',
                  style: t(10, c: C.n500),
                ),
              if (conn.text('last_online_at') != null) ...[
                const Gap(6),
                Text('آخرین اتصال: ${formatDateFa(conn.text('last_online_at'))}', style: t(11, c: C.n500)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _ipLimit(J conn) {
    final connected = conn.i('connected_ip_count');
    final limit = conn.i('limit_ip');
    if (limit > 0) return '${faNum(connected)} / ${faNum(limit)}';
    return connected > 0 ? faNum(connected) : '۰';
  }

  Future<void> _setNickname(J detail, String ip, String nick) async {
    try {
      await c.api.setIpNickname(detail.i('id'), ip, nick);
      final conn = detail.obj('connection');
      final ips = [
        for (final r in conn.objs('connected_ips')) r.s('ip') == ip ? r.merge({'nickname': nick.isEmpty ? null : nick}).raw : r.raw,
      ];
      widget.state.patch({'connection': conn.merge({'connected_ips': ips}).raw});
      haptic();
      setState(() {});
    } catch (_) {}
  }

  // -------------------------------------------------------------------- renew

  Widget _renew(J detail) {
    Future<void> checkout(J order) async {
      _close();
      await c.handleDetailCheckout(order);
    }

    if (detail.b('is_payg')) {
      return _Box(
        borderColor: C.a(C.sky500, 0.15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.event_repeat_rounded, size: 14, color: C.a(C.sky300, 0.8)),
                const Gap(6),
                Text(detail.b('is_metered') ? 'مصرف ابری' : 'شارژ ترافیک', style: t(12, w: 600, c: C.n200)),
              ],
            ),
            const Gap(12),
            if (detail.b('is_metered')) ...[
              Row(
                children: [
                  Expanded(child: _StatTile('مصرف شده', detail.s('used_label'))),
                  const Gap(8),
                  Expanded(child: _StatTile('مانده از کیف‌پول', detail.s('remaining_label'))),
                ],
              ),
              const Gap(8),
              Row(
                children: [
                  Expanded(child: _StatTile('کسر شده', detail.text('billed_label') ?? '۰ تومان')),
                  const Gap(8),
                  Expanded(child: _StatTile('وضعیت', detail.b('enabled') ? 'فعال' : 'قطع‌شده')),
                ],
              ),
              const Gap(8),
              Text(
                'فقط حجم واقعی از کیف‌پول کسر می‌شود. اگر موجودی تمام شود کانفیگ قطع می‌شود.',
                style: t(11, c: C.n400, h: 1.6),
              ),
              const Gap(8),
              Row(
                children: [
                  Expanded(
                    child: detail.b('enabled')
                        ? TgButton(
                            label: 'غیرفعال کردن',
                            variant: BtnVariant.outline,
                            foreground: C.red300,
                            onPressed: busy
                                ? null
                                : () async {
                                    if (await _guard(() => c.api.paygSetEnabled(false)) != null) {
                                      widget.state.patch({'enabled': false, 'online': false});
                                      haptic();
                                      setState(() {});
                                    }
                                  },
                          )
                        : TgButton(
                            label: 'فعال کردن',
                            onPressed: busy
                                ? null
                                : () async {
                                    if (await _guard(() => c.api.paygSetEnabled(true)) != null) {
                                      widget.state.patch({'enabled': true});
                                      haptic();
                                      setState(() {});
                                    }
                                  },
                          ),
                  ),
                  const Gap(8),
                  Expanded(
                    child: TgButton(
                      label: 'شارژ کیف‌پول',
                      variant: BtnVariant.outline,
                      onPressed: busy
                          ? null
                          : () {
                              final ctx = Navigator.of(context).context;
                              _close();
                              openWalletSheet(ctx);
                            },
                    ),
                  ),
                ],
              ),
            ] else
              PaygTrafficBuilder(lockTargetId: detail.i('id'), onCheckout: checkout),
          ],
        ),
      );
    }

    final plans = ref.watch(blControllerProvider).plans;
    return _Box(
      borderColor: C.a(C.amber500, 0.15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.event_repeat_rounded, size: 14, color: C.a(C.amber300, 0.8)),
              const Gap(6),
              Text('تمدید اشتراک', style: t(12, w: 600, c: C.n200)),
            ],
          ),
          const Gap(12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: C.b(25), borderRadius: BorderRadius.circular(8), border: Border.all(color: C.w(10))),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('تمدید خودکار از کیف‌پول', style: t(12, w: 500, c: C.n100)),
                      const Gap(2),
                      Text('نزدیک انقضا، اگر موجودی کافی باشد خودش تمدید می‌شود.', style: t(10, c: C.n500, h: 1.5)),
                    ],
                  ),
                ),
                Checkbox(
                  value: detail.b('auto_renew'),
                  activeColor: C.amber400,
                  onChanged: busy
                      ? null
                      : (v) async {
                          final res = await _guard(() => c.api.setAutoRenew(detail.i('id'), v ?? false));
                          if (res == null) return;
                          widget.state.patch({'auto_renew': res.b('auto_renew')});
                          haptic();
                          notify(res.b('auto_renew') ? 'تمدید خودکار روشن شد' : 'تمدید خودکار خاموش شد', ToastStatus.success);
                          setState(() {});
                        },
                ),
              ],
            ),
          ),
          const Gap(12),
          Row(
            children: [
              Expanded(child: _ModeBtn(label: 'پکیج آماده', active: !renewCustom, onTap: () => setState(() => renewCustom = false))),
              const Gap(8),
              Expanded(
                child: _ModeBtn(label: 'ساخت پکیج', active: renewCustom, amber: true, onTap: () => setState(() => renewCustom = true)),
              ),
            ],
          ),
          const Gap(12),
          if (!renewCustom) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(color: C.b(40), borderRadius: BorderRadius.circular(8), border: Border.all(color: C.w(12))),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: plans.any((p) => p.i('id') == renewPlanId) ? renewPlanId : null,
                  isExpanded: true,
                  hint: Text('انتخاب پلن', style: t(14, c: C.n500)),
                  dropdownColor: C.sheetElevated,
                  style: t(14),
                  items: [
                    for (final p in plans)
                      DropdownMenuItem(
                        value: p.i('id'),
                        child: Text('${p.s('title')} — ${p.text('price_label') ?? faNum(p.i('price_toman'))}', overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => renewPlanId = v),
                ),
              ),
            ),
            const Gap(8),
            TgButton(
              label: 'تمدید و پرداخت',
              height: 40,
              onPressed: busy || renewPlanId == null
                  ? null
                  : () async {
                      final order = await _guard(() => c.api.renewSubscription(widget.subId, renewPlanId!));
                      if (order != null) await checkout(order);
                    },
            ),
            if (actionError != null && tab == 'renew') ...[const Gap(8), Callout(actionError!, tone: Tone.red)],
          ] else
            CustomPackageBuilder(targetSubscriptionId: detail.i('id'), onCheckout: checkout),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------- more

  Widget _more(J detail) {
    final family = detail.objOrNull('family');
    final hasCustomer = _cust.keys.any((k) => detail.text(k) != null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Box(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 14, color: C.n400),
                  const Gap(6),
                  Text('مشخصات', style: t(12, w: 600, c: C.n200)),
                ],
              ),
              const Gap(8),
              KV('ایمیل', detail.s('email'), ltr: true),
              KV('شروع', formatDateFa(detail.text('created_at'))),
              KV('پایان', formatDateFa(detail.text('expires_at'))),
              KV('حجم باقی‌مانده', detail.s('remaining_label')),
              if (detail.text('source_label') != null)
                KV(
                  'وضعیت خرید',
                  '${detail.s('source_label')}${detail.text('order_status_label') != null ? ' · ${detail.s('order_status_label')}' : ''}',
                ),
              if (detail.text('order_amount_label') != null)
                KV(
                  'مبلغ سفارش',
                  '${detail.s('order_amount_label')}${detail.intOrNull('order_id') != null ? ' · #${faNum(detail.i('order_id'))}' : ''}',
                ),
              if (detail.text('renew_status_label') != null)
                KV(
                  'آخرین تمدید',
                  '${detail.s('renew_status_label')}${detail.text('renew_amount_label') != null ? ' · ${detail.s('renew_amount_label')}' : ''}',
                ),
            ],
          ),
        ),
        const Gap(10),
        Collapsible(
          title: 'نام کانفیگ',
          icon: Icons.sell_outlined,
          initiallyOpen: detail.text('label') == null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BLInput(controller: _label, hint: 'مثلاً موبایل، لپ‌تاپ…', maxLength: 64),
              const Gap(8),
              TgButton(
                label: busy ? 'در حال ذخیره…' : 'ذخیره نام',
                variant: BtnVariant.outline,
                height: 36,
                fontSize: 12,
                onPressed: busy
                    ? null
                    : () async {
                        await _guard(() => c.renameConfig(widget.subId, _label.text.trim()));
                        widget.state.patch({'label': _label.text.trim().isEmpty ? null : _label.text.trim()});
                      },
              ),
            ],
          ),
        ),
        const Gap(10),
        Collapsible(
          title: 'گیرنده این کانفیگ',
          icon: Icons.group_outlined,
          initiallyOpen: hasCustomer,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'اگر این کانفیگ را برای کس دیگری خریدی، اسمش اینجاست. لینک اتصال را از تب «اتصال» کپی کن و برای همان نفر بفرست — کانفیگ روی حساب تو می‌ماند.',
                style: t(11, c: C.n400, h: 1.6),
              ),
              for (final (key, label, hint) in const [
                ('customer_name', 'نام', 'علی رضایی'),
                ('customer_email', 'ایمیل', 'customer@email.com'),
                ('customer_phone', 'موبایل', '0912…'),
                ('customer_telegram_id', 'تلگرام', '@username'),
              ]) ...[
                const Gap(8),
                Text(label, style: t(10, c: C.n500)),
                const Gap(4),
                BLInput(controller: _cust[key], hint: hint, ltr: key != 'customer_name'),
              ],
              const Gap(8),
              TgButton(
                label: busy ? 'در حال ذخیره…' : 'ذخیره اطلاعات مشتری',
                variant: BtnVariant.outline,
                height: 36,
                fontSize: 12,
                onPressed: busy ? null : _saveCustomer,
              ),
            ],
          ),
        ),
        if (family != null && family.obj('parental').b('enabled')) ...[
          const Gap(10),
          FamilyParentalSection(
            detail: detail,
            onDetailChange: (next) {
              widget.state.set(next);
              setState(() {});
            },
          ),
        ],
        const Gap(10),
        Collapsible(
          title: 'انتقال مالکیت',
          icon: Icons.swap_horiz_rounded,
          child: _transferBody(detail),
        ),
        const Gap(10),
        Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: C.a(C.red500, 0.15))),
          child: Collapsible(
            title: 'غیرفعال‌سازی',
            icon: Icons.shield_outlined,
            child: !confirmRevoke
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'کل کانفیگ قطع می‌شود. برای فقط عوض کردن لینک، از تب اتصال «لینک جدید» را بزن.',
                        style: t(11, c: C.n500, h: 1.6),
                      ),
                      const Gap(8),
                      TgButton(
                        label: 'غیرفعال کردن',
                        variant: BtnVariant.outline,
                        height: 36,
                        fontSize: 12,
                        foreground: C.red300,
                        onPressed: () => setState(() => confirmRevoke = true),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('مطمئن هستید؟', style: t(11, c: C.a(C.red200, 0.9))),
                      if (actionError != null) ...[const Gap(8), Callout(actionError!, tone: Tone.red)],
                      const Gap(8),
                      _TwoButtons(
                        cancel: () => setState(() => confirmRevoke = false),
                        confirmLabel: 'تایید',
                        danger: true,
                        confirm: busy
                            ? null
                            : () async {
                                if (await _guard(() => c.api.revokeSubscription(widget.subId)) == null) return;
                                haptic();
                                notify('کانفیگ غیرفعال شد', ToastStatus.success);
                                _close();
                                await c.refreshDashboard();
                                await c.refreshResellerDesk();
                              },
                      ),
                    ],
                  ),
          ),
        ),
        const Gap(4),
        TextButton.icon(
          onPressed: widget.state.loading ? null : _load,
          icon: Icon(Icons.refresh_rounded, size: 14, color: C.n500),
          label: Text('بروزرسانی اطلاعات', style: t(11, c: C.n500)),
        ),
      ],
    );
  }

  Future<void> _saveCustomer() async {
    String? v(String k) {
      final s = _cust[k]!.text.trim();
      return s.isEmpty ? null : s;
    }

    final res = await _guard(
      () => c.api.setCustomer(widget.subId, {
        'customer_name': v('customer_name'),
        'customer_email': v('customer_email'),
        'customer_phone': v('customer_phone'),
        'customer_telegram_id': v('customer_telegram_id')?.replaceFirst(RegExp('^@'), ''),
      }),
    );
    if (res == null) return;
    c.patchDashItem(widget.subId, {
      for (final k in _cust.keys) k: res[k],
    });
    notify('اطلاعات مشتری ذخیره شد', ToastStatus.success);
    await c.refreshResellerDesk();
    await _load();
  }

  Widget _transferBody(J detail) {
    final family = detail.objOrNull('family');
    final p = transferPreview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'کانفیگ از حساب تو خارج می‌شود و به حساب مقصد می‌رود. لینک اتصال همان می‌ماند؛ تمدید خودکار خاموش می‌شود.',
          style: t(11, c: C.n400, h: 1.6),
        ),
        if (family != null) ...[
          const Gap(8),
          family.b('is_parent')
              ? Callout('این کانفیگ والد خانواده است. همه ${faNum(family.objs('members').length)} کانفیگ پکیج با هم منتقل می‌شوند.')
              : const Callout('این صندلی از خانواده جدا می‌شود و فقط همین کانفیگ منتقل می‌گردد.', tone: Tone.amber),
        ],
        if (detail.b('is_payg') || detail.b('is_metered')) ...[
          const Gap(8),
          const Callout('مصرفی از کیف‌پول صاحب جدید کسر می‌شود.', tone: Tone.neutral),
        ],
        const Gap(8),
        Text('آیدی تلگرام یا یوزرنیم', style: t(10, c: C.n500)),
        const Gap(4),
        BLInput(
          controller: _transfer,
          hint: '@username یا 123456789',
          ltr: true,
          onChanged: (_) => setState(() {
            transferPreview = null;
            confirmTransfer = false;
          }),
        ),
        const Gap(6),
        Text('مقصد باید حداقل یک‌بار فروشگاه را از داخل ربات باز کرده باشد.', style: t(10, c: C.n500, h: 1.6)),
        if (actionError != null && tab == 'more' && !confirmRevoke) ...[const Gap(8), Callout(actionError!, tone: Tone.red)],
        if (p != null) ...[
          const Gap(8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: C.b(30), borderRadius: BorderRadius.circular(8), border: Border.all(color: C.w(10))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('انتقال به', style: t(10, c: C.n500)),
                const Gap(2),
                Text(p.text('full_name') ?? 'کاربر', style: t(13, w: 600, c: C.n100)),
                Text(
                  '${p.text('username') != null ? '@${p.s('username')} · ' : ''}${p.i('telegram_id')}',
                  textDirection: TextDirection.ltr,
                  style: t(11, c: C.n400, mono: true),
                ),
              ],
            ),
          ),
        ],
        const Gap(8),
        if (p == null)
          TgButton(
            label: busy ? 'در حال بررسی…' : 'بررسی حساب مقصد',
            variant: BtnVariant.outline,
            height: 36,
            fontSize: 12,
            onPressed: busy || _transfer.text.trim().isEmpty
                ? null
                : () async {
                    final res = await _guard(() => c.api.lookupTransferTarget(_transfer.text));
                    if (res != null) {
                      haptic();
                      setState(() => transferPreview = res.obj('user'));
                    }
                  },
          )
        else if (!confirmTransfer)
          Row(
            children: [
              Expanded(
                child: TgButton(
                  label: 'عوض کردن',
                  variant: BtnVariant.outline,
                  height: 36,
                  fontSize: 12,
                  onPressed: () => setState(() => transferPreview = null),
                ),
              ),
              const Gap(8),
              Expanded(
                child: TgButton(
                  label: 'ادامه انتقال',
                  height: 36,
                  fontSize: 12,
                  onPressed: () {
                    haptic();
                    setState(() => confirmTransfer = true);
                  },
                ),
              ),
            ],
          )
        else ...[
          Text('بعد از تایید، این کانفیگ از داشبورد تو حذف می‌شود. مطمئنی؟', style: t(11, c: C.a(C.amber100, 0.9))),
          const Gap(8),
          _TwoButtons(
            cancel: () => setState(() => confirmTransfer = false),
            confirmLabel: busy ? 'در حال انتقال…' : 'تایید انتقال',
            confirm: busy
                ? null
                : () async {
                    final res = await _guard(() => c.api.transferSubscription(widget.subId, '${p.i('telegram_id')}'));
                    if (res == null) return;
                    haptic();
                    final target = res.obj('target');
                    final name = target.text('full_name') ??
                        (target.text('username') != null ? '@${target.s('username')}' : '${target.i('telegram_id')}');
                    notify(
                      res.b('family_moved')
                          ? 'پکیج خانواده (${faNum(res.i('moved_count'))} کانفیگ) به $name منتقل شد'
                          : 'مالکیت کانفیگ به $name منتقل شد',
                      ToastStatus.success,
                    );
                    _close();
                    await c.refreshDashboard();
                    await c.refreshResellerDesk();
                  },
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Pieces
// ---------------------------------------------------------------------------

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.detail});

  final J detail;

  @override
  Widget build(BuildContext context) {
    final conn = detail.obj('connection');
    final (label, tone) = detail.b('online')
        ? ('آنلاین', Tone.emerald)
        : switch (detail.s('status')) {
            'expired' => ('منقضی', Tone.red),
            'disabled' => ('غیرفعال', Tone.neutral),
            _ => ('آفلاین', Tone.amber),
          };
    final orderStatus = detail.text('order_status');
    final sourceTone = orderStatus == 'pending'
        ? Tone.amber
        : (orderStatus == 'rejected' || orderStatus == 'cancelled')
            ? Tone.red
            : Tone.sky;
    final total = detail.i('total_bytes');
    final pct = total > 0 ? math.min(100.0, detail.d('usage_percent')) : 0.0;
    final abuse = detail.objOrNull('abuse');
    final connected = conn.i('connected_ip_count');
    final limit = conn.i('limit_ip');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: C.w(10)),
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [C.w(5), C.b(40)]),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    Tag(label, tone: tone, size: 11),
                    if (detail.text('source_label') != null)
                      Tag(
                        '${detail.s('source_label')}${detail.text('order_status_label') != null ? ' · ${detail.s('order_status_label')}' : ''}',
                        tone: sourceTone,
                        size: 11,
                      ),
                  ],
                ),
              ),
              Icon(conn.b('online') ? Icons.wifi_rounded : Icons.wifi_off_rounded, size: 14, color: conn.b('online') ? C.emerald400 : C.n500),
              const Gap(4),
              Text(conn.b('online') ? 'متصل' : 'قطع', style: t(11, c: C.n400)),
              if (conn.b('ip_available'))
                Text(
                  ' · IP ${limit > 0 ? '${faNum(connected)} / ${faNum(limit)}' : (connected > 0 ? faNum(connected) : '۰')}',
                  style: t(11, c: C.n500),
                ),
            ],
          ),
          if (abuse != null && abuse.b('active')) ...[
            const Gap(8),
            Callout(
              'محدودیت موقت فعال است'
              '${abuse.text('notes') != null ? ' · ${abuse.s('notes')}' : ''}'
              '${abuse.text('throttled_until') != null ? ' · تا ${formatDateFa(abuse.text('throttled_until'))}' : ''}'
              '. کانفیگ حذف نشده؛ بعد از رفع مشکل خودکار وصل می‌شود.',
              tone: Tone.amber,
            ),
          ],
          const Gap(10),
          Row(
            children: [
              Expanded(child: Text('ترافیک', style: t(11, c: C.n400))),
              Text(
                '${detail.s('used_label')} / ${detail.s('total_label')}${total > 0 ? ' · ${faNum(detail.d('usage_percent').round())}٪' : ''}',
                textDirection: TextDirection.ltr,
                style: t(11, c: C.n400),
              ),
            ],
          ),
          const Gap(4),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: pct / 100,
              minHeight: 6,
              backgroundColor: C.w(10),
              color: pct >= 90
                  ? C.a(C.red300, 0.9)
                  : pct >= 70
                      ? C.a(C.amber400, 0.85)
                      : C.a(C.emerald400, 0.85),
            ),
          ),
          const Gap(10),
          Row(
            children: [
              Expanded(child: _StatTile('انقضا', formatDateFa(detail.text('expires_at'), short: true))),
              const Gap(8),
              Expanded(
                child: _StatTile(
                  'باقی‌مانده',
                  detail.intOrNull('remaining_days') != null ? '${faNum(detail.i('remaining_days'))} روز' : detail.s('remaining_label'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(color: C.b(30), borderRadius: BorderRadius.circular(8), border: Border.all(color: C.w(8))),
        child: Column(
          children: [
            Text(label, style: t(10, c: C.n500)),
            const Gap(2),
            Text(value, textAlign: TextAlign.center, style: t(12, w: 600, c: C.n100)),
          ],
        ),
      );
}

class _Box extends StatelessWidget {
  const _Box({required this.child, this.borderColor});

  final Widget child;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: C.b(25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor ?? C.w(10)),
        ),
        child: child,
      );
}

class _IconTitle extends StatelessWidget {
  const _IconTitle({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 16, color: C.n300)),
          const Gap(8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t(13, w: 600, c: C.n100)),
                const Gap(4),
                Text(text, style: t(11, c: C.n400, h: 1.6)),
              ],
            ),
          ),
        ],
      );
}

class _SmallBtn extends StatelessWidget {
  const _SmallBtn({required this.label, required this.onTap, this.icon});

  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Ink(
            height: 36,
            decoration: BoxDecoration(color: C.b(30), borderRadius: BorderRadius.circular(8), border: Border.all(color: C.w(12))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[Icon(icon, size: 14, color: C.n300), const Gap(6)],
                Text(label, style: t(11, c: C.n300)),
              ],
            ),
          ),
        ),
      );
}

class _ModeBtn extends StatelessWidget {
  const _ModeBtn({required this.label, required this.active, required this.onTap, this.amber = false});

  final String label;
  final bool active;
  final bool amber;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          haptic();
          onTap();
        },
        child: Container(
          height: 32,
          decoration: BoxDecoration(
            color: active ? (amber ? C.a(C.amber500, 0.1) : C.w(10)) : C.b(30),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: active ? (amber ? C.a(C.amber500, 0.3) : C.w(25)) : C.w(10)),
          ),
          child: Center(child: Text(label, style: t(11, w: 500, c: active ? (amber ? C.amber200 : C.white) : C.n400))),
        ),
      );
}

class _TwoButtons extends StatelessWidget {
  const _TwoButtons({required this.cancel, required this.confirm, required this.confirmLabel, this.danger = false});

  final VoidCallback cancel;
  final VoidCallback? confirm;
  final String confirmLabel;
  final bool danger;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: TgButton(label: 'انصراف', variant: BtnVariant.outline, height: 36, fontSize: 12, onPressed: cancel)),
          const Gap(8),
          Expanded(
            child: TgButton(
              label: confirmLabel,
              height: 36,
              fontSize: 12,
              color: danger ? const Color(0xFFDC2626) : null,
              foreground: danger ? Colors.white : null,
              onPressed: confirm,
            ),
          ),
        ],
      );
}

class _DailyBars extends StatelessWidget {
  const _DailyBars({required this.days});

  final List<J> days;

  @override
  Widget build(BuildContext context) {
    final max = days.map((d) => d.d('used_bytes')).fold<double>(1, math.max);
    return SizedBox(
      height: 72,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final d in days)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Tooltip(
                  message: d.s('used_label'),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(
                        child: FractionallySizedBox(
                          heightFactor: math.max(0.06, d.d('used_bytes') / max),
                          child: Container(
                            decoration: BoxDecoration(color: C.a(C.sky300, 0.8), borderRadius: BorderRadius.circular(2)),
                          ),
                        ),
                      ),
                      const Gap(4),
                      Text(faDigits(d.s('label')), style: t(9, c: C.n500)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// self-fix-sheet.tsx.
class _SelfFix extends ConsumerStatefulWidget {
  const _SelfFix({required this.subId, required this.onRenew, required this.onRotated});

  final int subId;
  final VoidCallback onRenew;
  final VoidCallback onRotated;

  @override
  ConsumerState<_SelfFix> createState() => _SelfFixState();
}

class _SelfFixState extends ConsumerState<_SelfFix> {
  J? data;
  bool loading = false;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final d = await ref.read(blControllerProvider).api.diagnoseSubscription(widget.subId);
      if (mounted) setState(() => data = d);
    } catch (e) {
      if (mounted) setState(() => error = persianError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _rotate() async {
    final api = ref.read(blControllerProvider).api;
    setState(() => busy = true);
    try {
      final res = await api.rotateSubscriptionLink(widget.subId);
      haptic();
      widget.onRotated();
      final url = res.text('subscription_url');
      if (url != null) await copyText(url);
      final d = await api.diagnoseSubscription(widget.subId);
      if (mounted) setState(() => data = d);
    } catch (e) {
      if (mounted) setState(() => error = persianError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _count(String value, String label, {Color? color}) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(color: C.b(30), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(10))),
          child: Column(
            children: [
              Text(value, style: t(15, w: 700, c: color)),
              Text(label, style: t(9, c: C.n500)),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final d = data;
    final best = d?.objOrNull('best');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'سرورها را دوباره تست می‌کنیم و می‌گوییم قدم بعدی چیست — معمولاً بدون پشتیبانی حل می‌شود.',
          style: t(11, c: C.n400, h: 1.6),
        ),
        if (loading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text('در حال تست سرورها…', textAlign: TextAlign.center, style: t(14, c: C.n400)),
          ),
        if (error != null) ...[const Gap(12), Callout(error!, tone: Tone.red)],
        if (d != null && !loading) ...[
          const Gap(12),
          Row(
            children: [
              _count(faNum(d.i('reachable_count')), 'سرور سالم', color: C.emerald200),
              const Gap(6),
              _count(faNum(d.i('server_count')), 'کل سرور'),
              const Gap(6),
              _count(best?.intOrNull('ping_ms') != null ? '${faNum(best!.i('ping_ms'))}ms' : '—', 'بهترین پینگ', color: C.sky200),
            ],
          ),
          const Gap(12),
          for (final issue in d.objs('issues')) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: issue.s('code') == 'ok' ? C.a(C.emerald500, 0.1) : C.a(C.amber500, 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: issue.s('code') == 'ok' ? C.a(C.emerald500, 0.25) : C.a(C.amber400, 0.25)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    issue.s('code') == 'ok' ? Icons.check_rounded : Icons.wifi_off_rounded,
                    size: 16,
                    color: issue.s('code') == 'ok' ? C.emerald300 : C.amber200,
                  ),
                  const Gap(8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(issue.s('title'), style: t(13, w: 600, c: C.n50)),
                        const Gap(4),
                        Text(issue.s('hint'), style: t(11, c: C.n300, h: 1.6)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Gap(8),
          ],
          if (best != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: C.b(30), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(10))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('بهترین سرور الان', style: t(11, c: C.n500)),
                  const Gap(2),
                  Text(best.s('label'), overflow: TextOverflow.ellipsis, style: t(13, w: 500, c: C.n100)),
                  if (best.text('host') != null)
                    Text('${best.s('host')}:${best.s('port')}', textDirection: TextDirection.ltr, style: t(10, c: C.n500, mono: true)),
                ],
              ),
            ),
            const Gap(8),
          ],
          Row(
            children: [
              if (d.text('subscription_url') != null)
                Expanded(
                  child: TgButton(
                    label: 'کپی Subscription',
                    icon: Icons.copy_rounded,
                    variant: BtnVariant.outline,
                    height: 40,
                    fontSize: 12,
                    onPressed: () => copyText(d.s('subscription_url')),
                  ),
                ),
              if (d.text('subscription_url') != null && best != null) const Gap(8),
              if (best != null)
                Expanded(
                  child: TgButton(
                    label: 'کپی بهترین سرور',
                    icon: Icons.copy_rounded,
                    variant: BtnVariant.outline,
                    height: 40,
                    fontSize: 12,
                    onPressed: () => copyText(best.s('link')),
                  ),
                ),
            ],
          ),
          const Gap(8),
          Row(
            children: [
              Expanded(
                child: TgButton(
                  label: 'تست دوباره',
                  icon: Icons.refresh_rounded,
                  variant: BtnVariant.outline,
                  height: 40,
                  fontSize: 12,
                  onPressed: loading || busy ? null : _run,
                ),
              ),
              const Gap(8),
              Expanded(
                child: d.b('can_rotate')
                    ? TgButton(
                        label: busy ? 'در حال ساخت…' : 'لینک جدید',
                        icon: Icons.key_rounded,
                        height: 40,
                        fontSize: 12,
                        onPressed: busy ? null : _rotate,
                      )
                    : TgButton(
                        label: 'تمدید',
                        height: 40,
                        fontSize: 12,
                        onPressed: () {
                          widget.onRenew();
                          Navigator.of(context).pop();
                        },
                      ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
