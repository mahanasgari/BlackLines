import 'package:flutter/material.dart';
import 'package:hiddify/features/blacklines/core/format.dart';
import 'package:hiddify/features/blacklines/screens/common.dart';
import 'package:hiddify/features/blacklines/state/controller.dart';
import 'package:hiddify/features/blacklines/ui/kit.dart';
import 'package:hiddify/features/blacklines/ui/tokens.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// App.tsx `tab === "invite"`.
class InviteScreen extends ConsumerStatefulWidget {
  const InviteScreen({super.key});

  @override
  ConsumerState<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends ConsumerState<InviteScreen> {
  final _card = TextEditingController();

  @override
  void dispose() {
    _card.dispose();
    super.dispose();
  }

  Widget _divider() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Divider(height: 1, color: C.w(10)),
      );

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(blControllerProvider);
    final r = c.refData;
    if (r == null) {
      return ListView(padding: const EdgeInsets.all(12), children: const [Panel(child: OrbLoaderPanel())]);
    }
    final leaderboard = r.objs('leaderboard');
    final withdrawals = r.objs('withdrawals');
    final invitees = r.objs('invitees');
    final link = r.s('invite_link');
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('دعوت دوستان', style: t(15, w: 600)),
              const Gap(4),
              Text.rich(
                TextSpan(
                  style: t(14, c: C.n400, h: 1.7),
                  children: [
                    const TextSpan(text: 'از هر خرید موفق '),
                    TextSpan(text: '${faNum(r.i('percent'))}٪', style: t(14, w: 700, c: C.white)),
                    const TextSpan(text: ' پورسانت بگیرید.'),
                  ],
                ),
              ),
              const Gap(16),
              const FieldLabel('لینک دعوت'),
              const Gap(8),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => copyText(link),
                  child: Ink(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: C.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(link, textDirection: TextDirection.ltr, style: t(12, c: C.n200)),
                        ),
                        const Gap(8),
                        const Icon(Icons.copy_rounded, size: 16),
                      ],
                    ),
                  ),
                ),
              ),
              const Gap(12),
              Row(
                children: [
                  Expanded(child: StatBox(label: 'دعوت‌ها', value: faNum(r.i('invited')))),
                  const Gap(8),
                  Expanded(child: StatBox(label: 'خرید موفق', value: faNum(r.i('paid_referrals')))),
                ],
              ),
              const Gap(8),
              Row(
                children: [
                  Expanded(child: StatBox(label: 'پورسانت', value: r.s('earned_label'))),
                  const Gap(8),
                  Expanded(child: StatBox(label: 'کیف‌پول', value: r.s('wallet_label'))),
                ],
              ),
              if (leaderboard.isNotEmpty) ...[
                _divider(),
                const FieldLabel('جدول برترین معرف‌ها'),
                const Gap(8),
                for (final row in leaderboard) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: row.b('is_self') ? C.a(C.amber500, 0.1) : C.b(30),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: row.b('is_self') ? C.a(C.amber500, 0.3) : C.w(10)),
                    ),
                    child: Row(
                      children: [
                        Text('#${faNum(row.i('rank'))} ', style: t(12, w: 700, c: C.n400)),
                        Expanded(
                          child: Text(
                            '${row.s('display_name')}${row.b('is_self') ? ' (شما)' : ''}',
                            overflow: TextOverflow.ellipsis,
                            style: t(12),
                          ),
                        ),
                        Text(row.s('earned_label'), style: t(12, c: C.emerald300)),
                      ],
                    ),
                  ),
                  const Gap(6),
                ],
              ],
              if (withdrawals.isNotEmpty) ...[
                _divider(),
                const FieldLabel('وضعیت برداشت‌ها'),
                const Gap(8),
                for (final w in withdrawals.take(8)) ...[
                  _WithdrawRow(id: w.i('id'), amount: w.s('amount_label'), status: w.s('status'), label: w.s('status_label')),
                  const Gap(6),
                ],
              ],
              if (invitees.isNotEmpty) ...[
                _divider(),
                const FieldLabel('افراد دعوت‌شده'),
                const Gap(8),
                for (final inv in invitees) ...[
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
                                  Text(
                                    inv.text('full_name') ?? (inv.text('username') != null ? '@${inv.s('username')}' : 'کاربر'),
                                    overflow: TextOverflow.ellipsis,
                                    style: t(14, w: 600),
                                  ),
                                  if (inv.text('full_name') != null && inv.text('username') != null)
                                    Text('@${inv.s('username')}', textDirection: TextDirection.ltr, style: t(10, c: C.n500)),
                                ],
                              ),
                            ),
                            Tag(
                              inv.b('has_purchased') ? 'خرید کرده' : 'بدون خرید',
                              tone: inv.b('has_purchased') ? Tone.emerald : Tone.neutral,
                            ),
                          ],
                        ),
                        const Gap(8),
                        Wrap(
                          spacing: 12,
                          children: [
                            Text.rich(
                              TextSpan(
                                style: t(10, c: C.n400),
                                children: [
                                  const TextSpan(text: 'خرید VPN: '),
                                  TextSpan(text: inv.s('vpn_purchase_label'), style: t(10, w: 700, c: C.n200)),
                                  if (inv.i('vpn_purchase_count') > 0) TextSpan(text: ' (${faNum(inv.i('vpn_purchase_count'))} بار)'),
                                ],
                              ),
                            ),
                            Text.rich(
                              TextSpan(
                                style: t(10, c: C.n400),
                                children: [
                                  const TextSpan(text: 'پورسانت شما: '),
                                  TextSpan(text: inv.s('commission_label'), style: t(10, w: 700, c: C.a(C.emerald300, 0.9))),
                                ],
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
              if (r.i('invited') == 0) ...[
                const Gap(12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: C.w(15)),
                  ),
                  child: Text(
                    'هنوز کسی با لینک شما ثبت‌نام نکرده — لینک را برای دوستان بفرستید.',
                    textAlign: TextAlign.center,
                    style: t(12, c: C.n500),
                  ),
                ),
              ],
              if (r.i('wallet') >= r.i('min_withdraw')) ...[
                _divider(),
                FieldLabel('برداشت (حداقل ${r.s('min_withdraw_label')})'),
                const Gap(8),
                BLInput(
                  controller: _card,
                  hint: 'شماره کارت ۱۶ رقمی',
                  ltr: true,
                  numeric: true,
                  onChanged: (_) => setState(() {}),
                ),
                const Gap(8),
                TgButton(
                  label: 'درخواست برداشت',
                  onPressed: c.busy || digitsOnly(_card.text).length < 12
                      ? null
                      : () async {
                          if (await c.referralWithdraw(digitsOnly(_card.text))) _card.clear();
                        },
                ),
              ] else ...[
                const Gap(12),
                Text('حداقل برداشت: ${r.s('min_withdraw_label')}', style: t(12, c: C.n400)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _WithdrawRow extends StatelessWidget {
  const _WithdrawRow({required this.id, required this.amount, required this.status, required this.label});

  final int id;
  final String amount;
  final String status;
  final String label;

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
          Expanded(child: Text('#${faNum(id)} · $amount', overflow: TextOverflow.ellipsis, style: t(12))),
          Tag(label, tone: statusTone(status)),
        ],
      ),
    );
  }
}
