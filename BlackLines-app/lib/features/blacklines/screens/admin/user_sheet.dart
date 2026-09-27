import 'package:flutter/material.dart';
import 'package:hiddify/features/blacklines/core/api.dart';
import 'package:hiddify/features/blacklines/core/format.dart';
import 'package:hiddify/features/blacklines/core/json.dart';
import 'package:hiddify/features/blacklines/screens/admin/admin_widgets.dart';
import 'package:hiddify/features/blacklines/screens/common.dart';
import 'package:hiddify/features/blacklines/screens/sheets/subscription_detail.dart';
import 'package:hiddify/features/blacklines/state/controller.dart';
import 'package:hiddify/features/blacklines/ui/kit.dart';
import 'package:hiddify/features/blacklines/ui/tokens.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

String _statusFa(String? s) => switch (s) {
      'online' => 'آنلاین',
      'expired' => 'منقضی',
      'disabled' => 'غیرفعال',
      'pending' => 'در انتظار',
      'approved' || 'paid' => 'تایید شده',
      'rejected' => 'رد شده',
      'cancelled' => 'لغو',
      _ => 'آفلاین',
    };

Tone _statusTone(String? s) => switch (s) {
      'online' => Tone.emerald,
      'expired' || 'rejected' || 'cancelled' => Tone.red,
      'pending' => Tone.amber,
      'approved' || 'paid' => Tone.sky,
      _ => Tone.neutral,
    };

/// admin-user-sheet.tsx.
Future<void> openAdminUserSheet(BuildContext context, int userId) => showTgSheet(
      context,
      title: 'پرونده کاربر',
      builder: (_) => _AdminUser(userId: userId),
    );

class _AdminUser extends ConsumerStatefulWidget {
  const _AdminUser({required this.userId});

  final int userId;

  @override
  ConsumerState<_AdminUser> createState() => _AdminUserState();
}

class _AdminUserState extends ConsumerState<_AdminUser> {
  J? d;
  bool loading = true;
  bool acting = false;
  List<J> giftPlans = const [];
  int? planId;
  int? openSubId;
  final _wallet = TextEditingController();
  final _credit = TextEditingController();
  final _convert = TextEditingController();
  final _proDays = TextEditingController();

  BLController get c => ref.read(blControllerProvider);

  @override
  void initState() {
    super.initState();
    Future.wait([c.api.adminUserDetail(widget.userId), c.api.adminGiftPlans()]).then((r) {
      if (!mounted) return;
      setState(() {
        d = r[0];
        _credit.text = '${r[0].i('wallet_credit_limit')}';
        giftPlans = r[1].objs('items');
        if (giftPlans.isNotEmpty) planId = giftPlans.first.i('id');
      });
    }).catchError((Object e) {
      notify(persianError(e), ToastStatus.error);
    }).whenComplete(() {
      if (mounted) setState(() => loading = false);
    });
  }

  @override
  void dispose() {
    _wallet.dispose();
    _credit.dispose();
    _convert.dispose();
    _proDays.dispose();
    super.dispose();
  }

  Future<void> _run(Future<J> Function() fn) async {
    setState(() => acting = true);
    try {
      final next = await fn();
      if (mounted) setState(() => d = next);
    } catch (e) {
      notify(persianError(e), ToastStatus.error);
    } finally {
      if (mounted) setState(() => acting = false);
    }
  }

  Future<void> _adjust(int sign) async {
    final amount = parseAmountInput(_wallet.text);
    if (amount == 0) {
      notify('مبلغ را وارد کنید', ToastStatus.error);
      return;
    }
    await _run(() async {
      final r = await c.api.adminAdjustWallet(d!.i('id'), sign * amount);
      _wallet.clear();
      notify(sign > 0 ? 'کیف‌پول شارژ شد' : 'از کیف‌پول کسر شد', ToastStatus.success);
      return r.obj('user');
    });
  }

  Widget _inputRow(TextEditingController ctl, String hint, List<Widget> buttons) => Row(
        children: [
          Expanded(child: SizedBox(height: 40, child: BLInput(controller: ctl, hint: hint, ltr: true, numeric: true))),
          for (final b in buttons) ...[const Gap(8), b],
        ],
      );

  Widget _smallBtn(String label, VoidCallback? onTap, {bool outline = false}) => TgButton(
        label: label,
        expand: false,
        height: 40,
        fontSize: 12,
        variant: outline ? BtnVariant.outline : BtnVariant.primary,
        onPressed: onTap,
      );

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 32), child: Text('در حال بارگذاری پرونده…', textAlign: TextAlign.center, style: t(14, c: C.n400)));
    }
    final u = d;
    if (u == null) return const EmptyState(message: 'پرونده پیدا نشد');
    final busy = acting || ref.watch(blControllerProvider.select((c) => c.busy));
    final title = u.text('full_name') ?? (u.text('username') != null ? '@${u.s('username')}' : 'کاربر');
    final subs = u.objs('subscriptions');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: C.b(30), borderRadius: BorderRadius.circular(16), border: Border.all(color: C.w(10))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, overflow: TextOverflow.ellipsis, style: t(14, w: 600)),
                        Text(
                          '${u.text('username') != null ? '@${u.s('username')} · ' : ''}${u.i('telegram_id')}',
                          textDirection: TextDirection.ltr,
                          style: t(11, c: C.n500, mono: true),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => copyText('${u.i('telegram_id')}', message: 'آیدی کپی شد'),
                    icon: Icon(Icons.copy_rounded, size: 16, color: C.n400),
                  ),
                ],
              ),
              const Gap(8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  AdminChip(u.b('is_super_admin') ? 'ادمین اصلی' : (u.b('is_admin') ? 'ادمین' : 'کاربر'), tone: u.b('is_admin') ? C.amber400 : null),
                  if (u.b('is_pro')) AdminChip('Pro', tone: C.amber400),
                  if (u.b('trial_granted')) const AdminChip('تست گرفته'),
                  if (u.b('is_test')) AdminChip('کاربر تست', tone: C.amber400),
                  if (u.i('chat_unread') > 0) AdminChip('${faNum(u.i('chat_unread'))} پیام', tone: C.orange500),
                  if (u.i('pending_order_count') > 0) AdminChip('${faNum(u.i('pending_order_count'))} سفارش باز', tone: C.orange500),
                ],
              ),
              if (u.text('pro_until') != null) ...[
                const Gap(8),
                Text('Pro تا ${formatDateFa(u.text('pro_until'), short: true)}', style: t(10, c: C.n500)),
              ],
            ],
          ),
        ),
        const Gap(16),
        // Wallet
        Row(
          children: [
            Icon(Icons.account_balance_wallet_outlined, size: 14, color: C.n400),
            const Gap(6),
            Text('کیف‌پول · ${u.text('wallet_label') ?? priceText(u.i('wallet_balance'))}', style: t(12, w: 600, c: C.n400)),
          ],
        ),
        const Gap(8),
        if (u.i('wallet_debt') > 0) ...[
          Callout(
            'بدهی: ${u.text('wallet_debt_label') ?? priceText(u.i('wallet_debt'))}'
            '${u.i('wallet_credit_limit') > 0 ? ' · سقف اعتبار ${u.text('wallet_credit_limit_label') ?? priceText(u.i('wallet_credit_limit'))}' : ''}',
            tone: Tone.rose,
          ),
          const Gap(8),
        ] else if (u.i('wallet_credit_limit') > 0) ...[
          Callout('اعتبار خرید تا ${u.text('wallet_credit_limit_label') ?? priceText(u.i('wallet_credit_limit'))}'),
          const Gap(8),
        ],
        _inputRow(_wallet, 'مبلغ (تومان)', [
          _smallBtn('شارژ', busy ? null : () => _adjust(1)),
          _smallBtn('کسر / بدهکار', busy ? null : () => _adjust(-1), outline: true),
        ]),
        const Gap(6),
        Text('کسر ادمین می‌تواند موجودی را منفی کند؛ در این حالت سقف اعتبار خودکار تا حد بدهی بالا می‌رود.', style: t(10, c: C.n500, h: 1.6)),
        const Gap(10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: C.a(C.amber500, 0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.a(C.amber500, 0.2))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('تبدیل شارژ قبلی به نسیه', style: t(11, w: 600, c: C.amber100)),
              const Gap(4),
              Text(
                'اگر قبلاً مثلاً ۱٬۰۰۰٬۰۰۰ شارژ کردی و بخشی مصرف شده: مبلغ همان شارژ اولیه را بزن. باقیمانده هدیه حذف می‌شود و مبلغ مصرف‌شده به بدهی تبدیل می‌شود تا بعداً با شارژ کیف‌پول بپردازد.',
                style: t(10, c: C.n500, h: 1.6),
              ),
              const Gap(8),
              _inputRow(_convert, 'مبلغ شارژ اولیه', [
                _smallBtn('تبدیل به نسیه', busy ? null : () {
                  final amount = parseAmountInput(_convert.text);
                  if (amount == 0) {
                    notify('مبلغ شارژ اولیه را وارد کنید', ToastStatus.error);
                    return;
                  }
                  _run(() async {
                    final r = await c.api.adminConvertWalletToCredit(u.i('id'), amount);
                    _convert.clear();
                    final user = r.obj('user');
                    _credit.text = '${user.i('wallet_credit_limit')}';
                    final debt = user.i('wallet_debt');
                    notify(debt > 0 ? 'تبدیل شد — بدهی ${priceText(debt)}' : 'تبدیل شد', ToastStatus.success);
                    return user;
                  });
                }, outline: true),
              ]),
            ],
          ),
        ),
        const Gap(10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: C.b(30), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(10))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('سقف اعتبار خرید (نسیه)', style: t(11, w: 600, c: C.n200)),
              const Gap(4),
              Text('اگر بیشتر از موجودی بخرد، کیف‌پول منفی می‌شود تا همین سقف. با شارژ کیف‌پول بدهی کم می‌شود.', style: t(10, c: C.n500, h: 1.6)),
              const Gap(8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in const [0, 100000, 200000, 500000, 1000000])
                    Pill(
                      label: p == 0 ? 'بدون اعتبار' : priceText(p),
                      active: parseAmountInput(_credit.text) == p,
                      onTap: () => setState(() => _credit.text = '$p'),
                    ),
                ],
              ),
              const Gap(8),
              _inputRow(_credit, 'سقف اعتبار', [
                _smallBtn('ذخیره اعتبار', busy ? null : () => _run(() async {
                      final limit = parseAmountInput(_credit.text);
                      final r = await c.api.adminSetWalletCredit(u.i('id'), limit);
                      notify(limit > 0 ? 'سقف اعتبار ذخیره شد' : 'اعتبار غیرفعال شد', ToastStatus.success);
                      return r.obj('user');
                    }), outline: true),
              ]),
            ],
          ),
        ),
        const Gap(16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: C.a(C.amber500, 0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: C.a(C.amber500, 0.2))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [Icon(Icons.star_outline_rounded, size: 14, color: C.amber200), const Gap(6), Text('اشتراک Pro', style: t(12, w: 600, c: C.amber200))]),
              const Gap(8),
              _inputRow(_proDays, 'روز (خالی = پیش‌فرض)', [
                _smallBtn('اعطای Pro', busy ? null : () => _run(() async {
                      final r = await c.api.adminGrantPro(u.i('id'), parseIntOrNull(_proDays.text));
                      _proDays.clear();
                      notify('Pro اعطا شد', ToastStatus.success);
                      return r.obj('user');
                    })),
              ]),
            ],
          ),
        ),
        const Gap(12),
        Row(
          children: [
            Expanded(
              child: TgButton(
                label: 'گفتگو',
                icon: Icons.chat_bubble_outline_rounded,
                variant: BtnVariant.outline,
                height: 40,
                fontSize: 12,
                onPressed: () {
                  Navigator.of(context).pop();
                  c.openChatWith(u.i('id'));
                },
              ),
            ),
            if (!u.b('is_super_admin')) ...[
              const Gap(8),
              Expanded(
                child: TgButton(
                  label: u.b('is_admin') ? 'حذف ادمین' : 'ادمین کن',
                  icon: Icons.shield_outlined,
                  variant: u.b('is_admin') ? BtnVariant.outline : BtnVariant.primary,
                  height: 40,
                  fontSize: 12,
                  onPressed: busy
                      ? null
                      : () => _run(() async {
                            final role = u.b('is_admin') ? 'user' : 'admin';
                            await c.api.adminSetUserRole(u.i('id'), role);
                            notify(role == 'admin' ? 'کاربر ادمین شد' : 'نقش ادمین برداشته شد', ToastStatus.success);
                            return c.api.adminUserDetail(u.i('id'));
                          }),
                ),
              ),
            ],
          ],
        ),
        const Gap(8),
        TgButton(
          label: u.b('is_test') ? 'حذف پرچم تست' : 'علامت کاربر تست',
          variant: u.b('is_test') ? BtnVariant.outline : BtnVariant.primary,
          height: 40,
          fontSize: 12,
          onPressed: busy
              ? null
              : () => _run(() async {
                    await c.api.adminSetUserTest(u.i('id'), !u.b('is_test'));
                    notify(u.b('is_test') ? 'این کاربر دیگر تست نیست' : 'کاربر تست شد و از آمار ادمین مخفی می‌شود', ToastStatus.success);
                    return c.api.adminUserDetail(u.i('id'));
                  }),
        ),
        if (!u.b('trial_granted')) ...[
          const Gap(8),
          TgButton(
            label: 'اعطای VPN تست',
            icon: Icons.card_giftcard_rounded,
            variant: BtnVariant.outline,
            height: 40,
            fontSize: 12,
            onPressed: busy
                ? null
                : () => _run(() async {
                      final r = await c.api.adminGrantTrial({
                        'targets_text': '${u.i('telegram_id')}',
                        'skip_existing_trial': true,
                        'notify_users': true,
                      });
                      notify('اعطا شد: ${faNum(r.i('granted_count'))} · رد: ${faNum(r.i('skipped_count'))} · خطا: ${faNum(r.i('failed_count'))}');
                      return c.api.adminUserDetail(u.i('id'));
                    }),
          ),
        ],
        const Gap(12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: C.b(25), borderRadius: BorderRadius.circular(16), border: Border.all(color: C.w(10))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [Icon(Icons.add_rounded, size: 14, color: C.n300), const Gap(6), Text('افزودن کانفیگ', style: t(12, w: 600, c: C.n300))]),
              const Gap(8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: C.b(40), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(15))),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: planId,
                    isExpanded: true,
                    hint: Text('پلنی نیست', style: t(13, c: C.n500)),
                    dropdownColor: C.sheetElevated,
                    style: t(13),
                    items: [
                      for (final p in giftPlans)
                        DropdownMenuItem(
                          value: p.i('id'),
                          child: Text('${p.s('title')} · ${p.s('traffic_label')} · ${faNum(p.i('limit_ip'))} IP', overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() => planId = v),
                  ),
                ),
              ),
              const Gap(8),
              TgButton(
                label: 'ساخت و اختصاص کانفیگ',
                height: 40,
                fontSize: 12,
                onPressed: busy || planId == null
                    ? null
                    : () => _run(() async {
                          final r = await c.api.adminGiftSubscription(u.i('id'), planId!);
                          notify('کانفیگ اضافه شد', ToastStatus.success);
                          return r.obj('user');
                        }),
              ),
            ],
          ),
        ),
        const Gap(16),
        Text('کانفیگ‌ها · ${faNum(subs.length)}', style: t(12, w: 600, c: C.n400)),
        const Gap(6),
        if (subs.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(10))),
            child: Text('کانفیگی ندارد', textAlign: TextAlign.center, style: t(12, c: C.n500)),
          )
        else
          for (final s in subs) ...[_subCard(u, s, busy), const Gap(6)],
        const Gap(12),
        Text('سفارش‌های اخیر', style: t(12, w: 600, c: C.n400)),
        const Gap(6),
        if (u.objs('orders').isEmpty)
          Text('سفارشی نیست', style: t(11, c: C.n500))
        else
          for (final o in u.objs('orders').take(8)) ...[
            _line('#${faNum(o.i('id'))} · ${o.text('plan_title') ?? o.text('kind_label') ?? 'سفارش'}', '${o.s('amount_label')} · ${o.text('status_label') ?? _statusFa(o.text('status'))}'),
            const Gap(6),
          ],
        if (u.objs('withdrawals').isNotEmpty) ...[
          const Gap(12),
          Text('برداشت‌ها', style: t(12, w: 600, c: C.n400)),
          const Gap(6),
          for (final w in u.objs('withdrawals')) ...[
            _line('#${faNum(w.i('id'))} · ${w.s('amount_label')}', _statusFa(w.text('status'))),
            const Gap(6),
          ],
        ],
      ],
    );
  }

  Widget _line(String start, String end) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: C.b(25), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(8))),
        child: Row(
          children: [
            Expanded(child: Text(start, overflow: TextOverflow.ellipsis, style: t(12))),
            Text(end, style: t(12, c: C.n400)),
          ],
        ),
      );

  Widget _subCard(J u, J s, bool busy) {
    final open = openSubId == s.i('id');
    final buyText = [s.text('source_label'), s.text('order_status_label')].whereType<String>().join(' · ');
    final pct = s.d('usage_percent').clamp(0, 100).toDouble();
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: C.b(30), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(10))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () {
              haptic();
              setState(() => openSubId = open ? null : s.i('id'));
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.text('label') ?? s.s('plan_title'), overflow: TextOverflow.ellipsis, style: t(14, w: 600)),
                        Text(s.s('email'), textDirection: TextDirection.ltr, style: t(10, c: C.n500, mono: true)),
                        const Gap(6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            Tag(_statusFa(s.text('status')), tone: _statusTone(s.text('status'))),
                            if (buyText.isNotEmpty) Tag(buyText, tone: _statusTone(s.text('order_status') ?? s.text('source'))),
                          ],
                        ),
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
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: C.w(8)))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  KV('پلن', s.s('plan_title')),
                  KV('وضعیت خرید', buyText.isEmpty ? '—' : buyText),
                  if (s.text('order_amount_label') != null)
                    KV('مبلغ', '${s.s('order_amount_label')}${s.intOrNull('order_id') != null ? ' · #${faNum(s.i('order_id'))}' : ''}'),
                  if (s.text('renew_status_label') != null)
                    KV('آخرین تمدید', '${s.s('renew_status_label')}${s.text('renew_amount_label') != null ? ' · ${s.s('renew_amount_label')}' : ''}'),
                  KV('انقضا', s.b('expired') ? 'منقضی' : formatDateFa(s.text('expires_at'), short: true)),
                  KV(
                    'باقی‌مانده',
                    s.intOrNull('remaining_days') != null && !s.b('expired')
                        ? '${faNum(s.i('remaining_days'))} روز'
                        : (s.b('expired') ? 'منقضی' : 'بدون انقضا'),
                  ),
                  KV('مصرف', '${s.s('used_label')} / ${s.text('total_label') ?? s.s('traffic_label')}'),
                  if (s.text('remaining_label') != null) KV('حجم مانده', s.s('remaining_label')),
                  if (s.i('limit_ip') > 0) KV('محدودیت IP', faNum(s.i('limit_ip'))),
                  if (s.text('customer_name') != null) KV('گیرنده', s.s('customer_name')),
                  if (s.text('family_role') != null) KV('خانواده', s.s('family_role') == 'parent' ? 'والد' : 'فرزند'),
                  KV('شروع', formatDateFa(s.text('created_at'), short: true)),
                  if (s.i('total_bytes') > 0) ...[
                    const Gap(6),
                    Row(children: [Expanded(child: Text('مصرف', style: t(10, c: C.n500))), Text('${faNum(pct.round())}٪', style: t(10, c: C.n500))]),
                    const Gap(4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: pct / 100,
                        minHeight: 6,
                        backgroundColor: C.w(10),
                        color: pct >= 90 ? C.a(C.red300, 0.9) : (pct >= 70 ? C.a(C.amber400, 0.85) : C.w(75)),
                      ),
                    ),
                  ],
                  const Gap(10),
                  Row(
                    children: [
                      Expanded(
                        child: TgButton(
                          label: s.b('enabled') ? 'قطع' : 'وصل',
                          variant: BtnVariant.outline,
                          height: 32,
                          fontSize: 11,
                          onPressed: busy
                              ? null
                              : () => _run(() async {
                                    final r = await c.api.adminSetSubEnabled(u.i('id'), s.i('id'), !s.b('enabled'));
                                    notify(s.b('enabled') ? 'کانفیگ غیرفعال شد' : 'کانفیگ فعال شد', ToastStatus.success);
                                    return r.obj('user');
                                  }),
                        ),
                      ),
                      const Gap(8),
                      Expanded(
                        child: TgButton(
                          label: 'حذف',
                          icon: Icons.delete_outline_rounded,
                          variant: BtnVariant.outline,
                          foreground: C.red300,
                          height: 32,
                          fontSize: 11,
                          onPressed: busy
                              ? null
                              : () async {
                                  if (!await confirmSheet(
                                    context,
                                    title: 'حذف کانفیگ',
                                    message: 'حذف کامل کانفیگ «${s.text('label') ?? s.s('plan_title')}»؟',
                                    confirm: 'حذف',
                                    destructive: true,
                                  )) {
                                    return;
                                  }
                                  await _run(() async {
                                    final r = await c.api.adminDeleteSubscription(u.i('id'), s.i('id'));
                                    notify('کانفیگ حذف شد', ToastStatus.success);
                                    return r.obj('user');
                                  });
                                },
                        ),
                      ),
                    ],
                  ),
                  const Gap(8),
                  TgButton(label: 'جزئیات کامل کانفیگ', height: 36, fontSize: 12, onPressed: () => openSubDetail(context, s.i('id'))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

