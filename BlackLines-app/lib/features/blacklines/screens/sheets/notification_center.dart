import 'package:flutter/material.dart';
import 'package:hiddify/features/blacklines/core/format.dart';
import 'package:hiddify/features/blacklines/core/json.dart';
import 'package:hiddify/features/blacklines/screens/admin/pending_order_sheet.dart';
import 'package:hiddify/features/blacklines/screens/sheets/wallet_sheet.dart';
import 'package:hiddify/features/blacklines/state/controller.dart';
import 'package:hiddify/features/blacklines/ui/kit.dart';
import 'package:hiddify/features/blacklines/ui/tokens.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// notification-center-sheet.tsx (user + admin variants).
Future<void> openNotificationCenter(BuildContext context) {
  haptic();
  return showTgSheet(
    context,
    title: 'مرکز اعلان',
    description: 'اعلان‌ها و صف بررسی',
    builder: (_) => const _NotificationCenter(),
  );
}

String _preview(J msg) {
  final body = msg.text('body');
  if (body != null) return body.length > 120 ? '${body.substring(0, 117)}…' : body;
  final att = msg.objs('attachments').firstOrNull;
  if (att == null) return 'پیام';
  return switch (att.s('type')) {
    'order' => 'فاکتور · ${att.text('plan_title') ?? 'سفارش'}',
    'link' => 'لینک · ${att.text('label') ?? att.text('email') ?? 'کانفیگ'}',
    _ => 'کانفیگ · ${att.text('label') ?? att.text('email') ?? '—'}',
  };
}

class _NotificationCenter extends ConsumerStatefulWidget {
  const _NotificationCenter();

  @override
  ConsumerState<_NotificationCenter> createState() => _NotificationCenterState();
}

class _NotificationCenterState extends ConsumerState<_NotificationCenter> {
  bool loading = true;

  @override
  void initState() {
    super.initState();
    ref.read(blControllerProvider).openNotifCenterData().whenComplete(() {
      if (mounted) setState(() => loading = false);
    });
  }

  void _go(BLTab tab) {
    Navigator.of(context).pop();
    ref.read(blControllerProvider).switchTab(tab);
  }

  Widget _header(int count, String title, String subtitle) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: C.b(30), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(10))),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    decoration: BoxDecoration(color: C.w(8), borderRadius: BorderRadius.circular(8)),
                    child: Center(child: Icon(Icons.notifications_none_rounded, size: 14, color: C.n400)),
                  ),
                  if (count > 0)
                    Positioned(
                      top: -4,
                      left: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        constraints: const BoxConstraints(minWidth: 14),
                        decoration: BoxDecoration(color: C.orange500, borderRadius: BorderRadius.circular(999)),
                        child: Text(faNum(count.clamp(0, 99)), textAlign: TextAlign.center, style: t(9, w: 700, c: C.white)),
                      ),
                    ),
                ],
              ),
            ),
            const Gap(8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t(12, w: 600)),
                  Text(subtitle, overflow: TextOverflow.ellipsis, style: t(10, c: C.n500)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _label(IconData icon, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 6),
        child: Row(children: [Icon(icon, size: 12, color: C.n500), const Gap(4), Text(text, style: t(11, w: 600, c: C.n500))]),
      );

  Widget _actionRow(String title, String body, {String? meta, required VoidCallback onTap, bool accent = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: accent ? C.a(C.orange500, 0.08) : C.b(35),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accent ? C.a(C.orange500, 0.2) : C.w(10)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(title, style: t(12, w: 600))),
                      if (meta != null) Text(meta, style: t(10, c: C.n500)),
                    ],
                  ),
                  const Gap(2),
                  Text(body, maxLines: 2, overflow: TextOverflow.ellipsis, style: t(11, c: C.n400, h: 1.6)),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _notice(String title, String body, String action, VoidCallback onAction) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: C.b(35), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(10))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: t(12, w: 600)),
            const Gap(2),
            Text(body, style: t(11, c: C.n400, h: 1.6)),
            const Gap(8),
            GestureDetector(onTap: onAction, child: Text('$action ←', style: t(11, w: 600, c: C.orange300))),
          ],
        ),
      );

  Widget _empty(String text) => Container(
        padding: const EdgeInsets.symmetric(vertical: 32),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(10))),
        child: Column(
          children: [
            Icon(Icons.notifications_none_rounded, size: 24, color: C.n600),
            const Gap(8),
            Text(text, style: t(12, c: C.n400)),
          ],
        ),
      );

  Widget _loadingBox() => Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(10))),
        child: Text('در حال بارگذاری…', textAlign: TextAlign.center, style: t(12, c: C.n400)),
      );

  Widget _outlineAction(String label, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: C.w(10))),
          child: Text(label, textAlign: TextAlign.center, style: t(11, w: 600, c: C.n300)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(blControllerProvider);
    return c.isAdmin ? _admin(c) : _user(c);
  }

  Widget _user(BLController c) {
    final count = c.userNotifCount;
    final pending = c.pendingOrder;
    final wallet = c.walletPending;
    final msgs = c.userUnreadMessages;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(count, 'اعلان‌های شما', loading ? 'در حال بروزرسانی…' : (count > 0 ? '${faNum(count)} مورد' : 'همه چیز مرتب است')),
        const Gap(12),
        if (loading) _loadingBox(),
        if (!loading && c.chatUnread > 0) ...[
          _label(Icons.chat_bubble_outline_rounded, '${faNum(c.chatUnread)} پیام خوانده‌نشده'),
          for (final m in msgs.take(5)) _actionRow('پشتیبانی', _preview(m), meta: chatTimeFa(m.text('created_at')), accent: true, onTap: () => _go(BLTab.chat)),
          if (c.chatUnread > msgs.length && msgs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('و ${faNum(c.chatUnread - msgs.length)} پیام دیگر…', style: t(10, c: C.n500)),
            ),
          _outlineAction('باز کردن گفتگو', () => _go(BLTab.chat)),
          const Gap(12),
        ],
        if (!loading && pending != null) ...[
          _label(Icons.shopping_bag_outlined, 'سفارش در انتظار'),
          _notice(
            pending.s('plan_title'),
            'سفارش #${faNum(pending.i('id'))} · ${pending.s('amount_label')}${pending.b('has_receipt') ? ' · رسید ارسال شده' : ' · رسید را ارسال کنید'}',
            'مشاهده در داشبورد',
            () => _go(BLTab.subs),
          ),
          const Gap(12),
        ],
        if (!loading && wallet != null) ...[
          _label(Icons.account_balance_wallet_outlined, 'شارژ کیف‌پول'),
          _notice(
            'شارژ ${wallet.s('amount_label')}',
            wallet.b('has_receipt') ? 'رسید ارسال شده — پس از تایید موجودی به‌روز می‌شود.' : 'شارژ ثبت شده — لطفاً رسید پرداخت را ارسال کنید.',
            'باز کردن کیف‌پول',
            () {
              final ctx = Navigator.of(context).context;
              Navigator.of(context).pop();
              openWalletSheet(ctx);
            },
          ),
          const Gap(12),
        ],
        if (!loading && count == 0) _empty('اعلان فعالی ندارید'),
      ],
    );
  }

  Widget _admin(BLController c) {
    final total = c.adminPendingCount + c.chatUnread;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(
          total,
          'صندوق ورود',
          loading
              ? 'در حال بروزرسانی…'
              : total > 0
                  ? '${faNum(c.adminOrders.length)} سفارش · ${faNum(c.adminWds.length)} برداشت · ${faNum(c.chatUnread)} پیام'
                  : 'همه چیز بررسی شده',
        ),
        const Gap(12),
        if (loading) _loadingBox(),
        if (!loading && c.chatUnread > 0) ...[
          _label(Icons.chat_bubble_outline_rounded, '${faNum(c.chatUnread)} پیام خوانده‌نشده'),
          for (final th in c.adminUnreadThreads.take(5))
            _actionRow(
              th.text('full_name') ?? (th.text('username') != null ? '@${th.s('username')}' : faNum(th.i('telegram_id'))),
              th.text('last_message') ?? 'پیام جدید',
              meta: th.text('last_message_at') != null ? chatTimeFa(th.text('last_message_at')) : null,
              accent: true,
              onTap: () {
                Navigator.of(context).pop();
                ref.read(blControllerProvider).openChatWith(th.i('user_id'));
              },
            ),
          _outlineAction('باز کردن گفتگوها', () => _go(BLTab.chat)),
          const Gap(12),
        ],
        if (!loading && c.adminOrders.isNotEmpty) ...[
          _label(Icons.shopping_bag_outlined, 'سفارش‌های اخیر'),
          for (final o in c.adminOrders.take(5))
            _actionRow(
              '#${faNum(o.i('id'))} · ${o.s('plan')}',
              '${o.text('user') ?? '—'}${o.b('has_receipt') ? ' · رسید ✓' : ''}',
              meta: o.s('amount_label'),
              onTap: () {
                final ctx = Navigator.of(context).context;
                Navigator.of(context).pop();
                openPendingOrderSheet(ctx, o);
              },
            ),
          const Gap(12),
        ],
        if (!loading && c.adminWds.isNotEmpty) ...[
          _label(Icons.account_balance_wallet_outlined, 'برداشت‌های اخیر'),
          for (final w in c.adminWds.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: C.b(35), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(10))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('#${faNum(w.i('id'))} — ${w.s('amount_label')}', style: t(12, w: 600)),
                    Text(w.text('user') ?? '—', style: t(10, c: C.n500)),
                  ],
                ),
              ),
            ),
          const Gap(12),
        ],
        if (!loading && total == 0) ...[_empty('مورد جدیدی در صندوق ورود نیست'), const Gap(12)],
        TgButton(label: 'پنل ادمین', variant: BtnVariant.outline, height: 36, fontSize: 12, onPressed: () => _go(BLTab.admin)),
      ],
    );
  }
}
