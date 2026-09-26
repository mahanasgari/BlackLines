import 'package:flutter/material.dart';
import 'package:hiddify/features/blacklines/core/api.dart';
import 'package:hiddify/features/blacklines/core/format.dart';
import 'package:hiddify/features/blacklines/core/json.dart';
import 'package:hiddify/features/blacklines/screens/sheets/order_history.dart';
import 'package:hiddify/features/blacklines/state/controller.dart';
import 'package:hiddify/features/blacklines/ui/kit.dart';
import 'package:hiddify/features/blacklines/ui/tokens.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// App.tsx wallet `TgSheet` (موجودی، شارژ، انتقال و برداشت).
Future<void> openWalletSheet(BuildContext context) {
  haptic();
  return showTgSheet(
    context,
    title: 'کیف‌پول',
    description: 'موجودی، شارژ، انتقال و برداشت',
    builder: (_) => const _WalletSheet(),
  );
}

class _WalletSheet extends ConsumerStatefulWidget {
  const _WalletSheet();

  @override
  ConsumerState<_WalletSheet> createState() => _WalletSheetState();
}

class _WalletSheetState extends ConsumerState<_WalletSheet> {
  String tab = 'deposit';
  int deposit = 100000;
  int withdrawAmount = 0;
  final _card = TextEditingController();
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    final c = ref.read(blControllerProvider);
    _seed(c.walletInfo);
    c.loadWallet().then((_) {
      if (!mounted) return;
      final info = ref.read(blControllerProvider).walletInfo;
      setState(() {
        _seeded = false;
        _seed(info);
        if (info?.objOrNull('pending_withdrawal') != null) {
          tab = 'withdraw';
        } else if (info?.objOrNull('pending_deposit') != null) {
          tab = 'deposit';
        }
      });
    });
  }

  void _seed(J? info) {
    if (info == null || _seeded) return;
    _seeded = true;
    final presets = info.nums('presets');
    deposit = presets.length > 1 ? presets[1].toInt() : info.i('min_deposit', 50000);
    withdrawAmount = info.intOrNull('withdrawable') ?? info.i('balance');
  }

  @override
  void dispose() {
    _card.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(blControllerProvider);
    final w = c.walletInfo;
    final balance = w?.intOrNull('balance') ?? c.me?.i('wallet_balance') ?? 0;
    final debt = w?.i('debt') ?? 0;
    final withdrawable = w?.intOrNull('withdrawable') ?? balance;
    final minWithdraw = w?.intOrNull('min_withdraw') ?? 100000;
    final minDeposit = w?.intOrNull('min_deposit') ?? 50000;
    final creditLimit = w?.i('credit_limit') ?? 0;
    final creditRemaining = w?.i('credit_remaining') ?? 0;
    final pendingDeposit = w?.objOrNull('pending_deposit');
    final pendingWithdrawal = w?.objOrNull('pending_withdrawal');
    final presets = (w?.nums('presets').isNotEmpty ?? false)
        ? w!.nums('presets').map((e) => e.toInt()).toList()
        : const [50000, 100000, 200000, 500000, 1000000];
    final negative = debt > 0 || balance < 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          decoration: BoxDecoration(
            color: C.w(5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: C.w(12)),
          ),
          child: Column(
            children: [
              Text(negative ? 'بدهی کیف‌پول' : 'موجودی فعلی', style: t(11, c: C.n400)),
              const Gap(4),
              Text(
                debt > 0
                    ? (w?.text('debt_label') ?? priceText(debt))
                    : balance < 0
                        ? '${priceText(balance.abs())} بدهی'
                        : priceText(balance),
                style: t(28, w: 800, c: negative ? C.rose300 : null),
              ),
              if (creditLimit > 0) ...[
                const Gap(8),
                Text(
                  'اعتبار خرید: تا ${w?.text('credit_limit_label') ?? priceText(creditLimit)}'
                  '${creditRemaining > 0 ? ' · باقی‌مانده ${w?.text('credit_remaining_label') ?? priceText(creditRemaining)}' : ' · تمام شده'}',
                  textAlign: TextAlign.center,
                  style: t(11, c: C.a(C.sky200, 0.9), h: 1.6),
                ),
              ],
              const Gap(8),
              Text(
                debt > 0
                    ? 'با شارژ کیف‌پول، بدهی اول تسویه می‌شود.'
                    : (w?.i('locked') ?? 0) > 0
                        ? 'قابل برداشت و انتقال: ${w?.text('withdrawable_label') ?? priceText(withdrawable)}'
                        : 'از این موجودی می‌توانید بخرید، به کیف‌پول کس دیگری منتقل کنید، یا برداشت بزنید.',
                textAlign: TextAlign.center,
                style: t(11, c: debt > 0 ? C.a(C.amber200, 0.9) : C.n400, h: 1.6),
              ),
            ],
          ),
        ),
        const Gap(16),
        UnderlineTabs<String>(
          items: const [('deposit', 'شارژ'), ('transfer', 'انتقال'), ('withdraw', 'برداشت')],
          value: tab,
          onChanged: (v) => setState(() => tab = v),
        ),
        const Gap(12),
        if (tab == 'deposit') ...[
          if (pendingDeposit != null) ...[
            Panel(
              color: C.b(30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'شارژ در انتظار تایید: ${pendingDeposit.s('amount_label')}'
                    '${pendingDeposit.b('has_receipt') ? ' · رسید ارسال شده' : ' · منتظر رسید'}',
                    style: t(12, c: C.n300),
                  ),
                  if (!pendingDeposit.b('has_receipt')) ...[
                    const Gap(8),
                    TgButton(
                      label: 'ادامه ارسال رسید',
                      onPressed: () async {
                        if (await c.startDeposit(pendingDeposit.i('amount_toman')) && context.mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                    ),
                  ],
                ],
              ),
            ),
            const Gap(8),
          ],
          const FieldLabel('شارژ کیف‌پول (کارت‌به‌کارت)'),
          const Gap(8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (debt > 0) Pill(label: 'تسویه بدهی · ${priceText(debt)}', active: deposit == debt, onTap: () => setState(() => deposit = debt), tone: C.rose300),
              for (final p in presets) Pill(label: priceText(p), active: deposit == p, onTap: () => setState(() => deposit = p)),
            ],
          ),
          const Gap(8),
          AmountInput(value: deposit, onChanged: (v) => setState(() => deposit = v)),
          const Gap(6),
          Text('حداقل ${w?.text('min_deposit_label') ?? priceText(50000)}', style: t(11, c: C.n500)),
          const Gap(8),
          TgButton(
            label: deposit > 0 ? 'شارژ ${priceText(deposit)}' : 'شارژ / واریز',
            onPressed: c.busy || deposit < minDeposit
                ? null
                : () async {
                    if (await c.startDeposit(deposit) && context.mounted) Navigator.of(context).pop();
                  },
          ),
        ],
        if (tab == 'transfer')
          _TransferPanel(
            balance: withdrawable,
            minTransfer: w?.intOrNull('min_transfer') ?? 1000,
            minTransferLabel: w?.text('min_transfer_label') ?? priceText(1000),
            transfers: w?.objs('transfers') ?? const [],
          ),
        if (tab == 'withdraw') ...[
          if (pendingWithdrawal != null)
            Panel(
              color: C.b(30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('برداشت در انتظار بررسی', style: t(12, w: 600, c: C.amber200)),
                  const Gap(4),
                  Text(
                    '${pendingWithdrawal.s('amount_label')} · کارت منتهی به ${faDigits(_last4(pendingWithdrawal.s('card_number')))}',
                    style: t(11, c: C.n400),
                  ),
                ],
              ),
            )
          else if (withdrawable >= minWithdraw) ...[
            const FieldLabel('برداشت به کارت'),
            const Gap(8),
            BLInput(
              controller: _card,
              hint: 'شماره کارت ۱۶ رقمی',
              ltr: true,
              numeric: true,
              onChanged: (_) => setState(() {}),
            ),
            const Gap(8),
            AmountInput(value: withdrawAmount, onChanged: (v) => setState(() => withdrawAmount = v)),
            const Gap(8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Pill(label: 'کل موجودی', active: false, onTap: () => setState(() => withdrawAmount = withdrawable)),
            ),
            const Gap(6),
            Text(
              'حداقل ${w?.text('min_withdraw_label') ?? priceText(100000)} · مبلغ از کیف‌پول کسر و پس از تایید ادمین واریز می‌شود',
              style: t(11, c: C.n500, h: 1.6),
            ),
            const Gap(8),
            TgButton(
              label: withdrawAmount > 0 ? 'درخواست برداشت ${priceText(withdrawAmount)}' : 'درخواست برداشت',
              variant: BtnVariant.outline,
              onPressed: c.busy || digitsOnly(_card.text).length < 16 || withdrawAmount < minWithdraw
                  ? null
                  : () async {
                      if (await c.walletWithdraw(_card.text, withdrawAmount)) {
                        _card.clear();
                        setState(() => withdrawAmount = ref.read(blControllerProvider).walletInfo?.i('withdrawable') ?? 0);
                      }
                    },
            ),
          ] else
            Text('حداقل موجودی برای برداشت: ${w?.text('min_withdraw_label') ?? priceText(100000)}', style: t(12, c: C.n400)),
          if ((w?.objs('withdrawals') ?? const []).isNotEmpty) ...[
            const Gap(12),
            Divider(height: 1, color: C.w(10)),
            const Gap(12),
            const FieldLabel('تاریخچه برداشت'),
            const Gap(8),
            for (final wd in w!.objs('withdrawals').take(8)) ...[
              _Row(
                start: '#${faNum(wd.i('id'))} · ${wd.s('amount_label')}',
                end: Tag(wd.s('status_label'), tone: statusTone(wd.text('status'))),
              ),
              const Gap(6),
            ],
          ],
        ],
        const Gap(16),
        TgButton(
          variant: BtnVariant.outline,
          icon: Icons.history_rounded,
          label: 'تاریخچه پرداخت‌ها',
          onPressed: () => openOrderHistory(context),
        ),
        const Gap(8),
        TgButton(
          variant: BtnVariant.outline,
          label: 'کسب درآمد با دعوت دوستان',
          onPressed: () {
            Navigator.of(context).pop();
            c.switchTab(BLTab.invite);
          },
        ),
      ],
    );
  }

  String _last4(String card) {
    final d = digitsOnly(card);
    return d.length <= 4 ? d : d.substring(d.length - 4);
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.start, required this.end});

  final String start;
  final Widget end;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: C.b(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: C.w(10)),
      ),
      child: Row(
        children: [
          Expanded(child: Text(start, overflow: TextOverflow.ellipsis, style: t(12))),
          end,
        ],
      ),
    );
  }
}

/// wallet-transfer-panel.tsx.
class _TransferPanel extends ConsumerStatefulWidget {
  const _TransferPanel({
    required this.balance,
    required this.minTransfer,
    required this.minTransferLabel,
    required this.transfers,
  });

  final int balance;
  final int minTransfer;
  final String minTransferLabel;
  final List<J> transfers;

  @override
  ConsumerState<_TransferPanel> createState() => _TransferPanelState();
}

class _TransferPanelState extends ConsumerState<_TransferPanel> {
  final _target = TextEditingController();
  J? preview;
  int amount = 0;
  bool confirm = false;

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final q = _target.text.trim();
    if (q.isEmpty) return;
    final c = ref.read(blControllerProvider);
    c.setBusy(true);
    try {
      final res = await c.api.lookupTransferTarget(q);
      haptic();
      setState(() {
        preview = res.obj('user');
        confirm = false;
      });
    } catch (e) {
      setState(() => preview = null);
      notify(persianError(e), ToastStatus.error);
    } finally {
      c.setBusy(false);
    }
  }

  Future<void> _send() async {
    final p = preview;
    if (p == null || amount < widget.minTransfer || amount > widget.balance) return;
    final c = ref.read(blControllerProvider);
    c.setBusy(true);
    try {
      final res = await c.api.walletTransfer('${p.i('telegram_id')}', amount);
      haptic('medium');
      notify('${res.s('amount_label')} منتقل شد', ToastStatus.success);
      _target.clear();
      setState(() {
        preview = null;
        amount = 0;
        confirm = false;
      });
      c.setWalletBalance(res.i('wallet_balance'));
      await c.loadWallet();
    } catch (e) {
      notify(persianError(e), ToastStatus.error);
    } finally {
      c.setBusy(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(blControllerProvider.select((c) => c.busy));
    final p = preview;
    final canSend = p != null && amount >= widget.minTransfer && amount <= widget.balance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FieldLabel('انتقال به کیف‌پول کاربر دیگر'),
        const Gap(8),
        BLInput(
          controller: _target,
          hint: '@username یا آی‌دی تلگرام',
          ltr: true,
          onChanged: (_) => setState(() {
            preview = null;
            confirm = false;
          }),
        ),
        const Gap(6),
        Text('مقصد باید حداقل یک‌بار فروشگاه را از داخل ربات باز کرده باشد.', style: t(11, c: C.n500)),
        const Gap(8),
        if (p != null)
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
                Text('انتقال به', style: t(10, c: C.n500)),
                const Gap(2),
                Text(p.text('full_name') ?? 'کاربر', style: t(13, w: 600, c: C.n100)),
                const Gap(2),
                Text(
                  '${p.text('username') != null ? '@${p.s('username')} · ' : ''}${p.i('telegram_id')}',
                  textDirection: TextDirection.ltr,
                  style: t(11, c: C.n400, mono: true),
                ),
              ],
            ),
          )
        else
          TgButton(
            label: busy ? 'در حال بررسی…' : 'بررسی حساب مقصد',
            variant: BtnVariant.outline,
            onPressed: busy || _target.text.trim().isEmpty ? null : _lookup,
          ),
        if (p != null) ...[
          const Gap(8),
          AmountInput(
            value: amount,
            onChanged: (v) => setState(() {
              amount = v;
              confirm = false;
            }),
          ),
          const Gap(8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final v in const [10000, 50000, 100000].where((v) => v <= widget.balance))
                Pill(
                  label: priceText(v),
                  active: amount == v,
                  onTap: () => setState(() {
                    amount = v;
                    confirm = false;
                  }),
                ),
              Pill(
                label: 'کل موجودی',
                active: false,
                onTap: () => setState(() {
                  amount = widget.balance;
                  confirm = false;
                }),
              ),
            ],
          ),
          const Gap(6),
          Text('حداقل ${widget.minTransferLabel} · فوری از کیف‌پول شما کم و به مقصد اضافه می‌شود', style: t(11, c: C.n500)),
          if (amount > widget.balance) ...[
            const Gap(4),
            Text('مبلغ بیشتر از موجودی است', style: t(11, c: C.red300)),
          ],
          const Gap(8),
          if (!confirm)
            TgButton(
              label: 'ادامه انتقال',
              onPressed: busy || !canSend
                  ? null
                  : () {
                      haptic();
                      setState(() => confirm = true);
                    },
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: C.a(C.amber500, 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: C.a(C.amber400, 0.2)),
              ),
              child: Column(
                children: [
                  Text(
                    '${priceText(amount)} به ${p.text('full_name') ?? 'این کاربر'} منتقل می‌شود. برگشت ندارد.',
                    style: t(11, c: C.a(C.amber100, 0.9), h: 1.6),
                  ),
                  const Gap(8),
                  Row(
                    children: [
                      Expanded(
                        child: TgButton(
                          label: 'انصراف',
                          variant: BtnVariant.outline,
                          onPressed: busy ? null : () => setState(() => confirm = false),
                        ),
                      ),
                      const Gap(8),
                      Expanded(
                        child: TgButton(
                          label: busy ? 'در حال انتقال…' : 'تایید و ارسال',
                          onPressed: busy || !canSend ? null : _send,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
        if (widget.transfers.isNotEmpty) ...[
          const Gap(12),
          Divider(height: 1, color: C.w(10)),
          const Gap(12),
          const FieldLabel('تاریخچه انتقال'),
          const Gap(8),
          for (final tr in widget.transfers.take(8)) ...[
            _Row(
              start: '${tr.s('direction') == 'out' ? 'به' : 'از'} ${tr.s('other_name')}',
              end: Text(
                '${tr.s('direction') == 'in' ? '+' : '−'}${tr.s('amount_label')}',
                style: t(12, c: tr.s('direction') == 'in' ? C.emerald300 : C.n200),
              ),
            ),
            const Gap(6),
          ],
        ],
      ],
    );
  }
}
