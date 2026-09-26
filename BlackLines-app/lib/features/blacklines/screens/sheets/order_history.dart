import 'package:flutter/material.dart';
import 'package:hiddify/features/blacklines/core/format.dart';
import 'package:hiddify/features/blacklines/core/json.dart';
import 'package:hiddify/features/blacklines/screens/receipt_viewer.dart';
import 'package:hiddify/features/blacklines/state/controller.dart';
import 'package:hiddify/features/blacklines/ui/kit.dart';
import 'package:hiddify/features/blacklines/ui/tokens.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// order-history-sheet.tsx.
Future<void> openOrderHistory(BuildContext context, {bool admin = false}) => showTgSheet(
      context,
      title: admin ? 'تاریخچه سفارشات' : 'تاریخچه خرید',
      description: admin ? null : 'پرداخت‌ها و سفارش‌های شما',
      builder: (_) => _OrderHistory(admin: admin),
    );

Color _statusColor(String? s) => switch (s) {
      'approved' => C.emerald400,
      'pending' => C.amber400,
      'rejected' || 'cancelled' => C.red300,
      _ => C.n400,
    };

class _OrderHistory extends ConsumerStatefulWidget {
  const _OrderHistory({required this.admin});

  final bool admin;

  @override
  ConsumerState<_OrderHistory> createState() => _OrderHistoryState();
}

class _OrderHistoryState extends ConsumerState<_OrderHistory> {
  List<J> items = const [];
  int total = 0;
  bool loading = true;
  String status = '';
  String query = '';
  J? selected;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final api = ref.read(blControllerProvider).api;
    try {
      final r = widget.admin
          ? await api.adminOrderHistory(q: query, status: status.isEmpty ? null : status, limit: 50)
          : await api.orderHistory(status: status.isEmpty ? null : status, limit: 50);
      if (!mounted) return;
      setState(() {
        items = r.objs('items');
        total = r.i('total');
        final sel = selected;
        if (sel != null) selected = items.where((o) => o.i('id') == sel.i('id')).firstOrNull ?? sel;
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sel = selected;
    if (sel != null) return _detail(sel);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.admin) ...[
          Text('${faNum(total)} سفارش', style: t(11, c: C.n400)),
          const Gap(8),
          Row(
            children: [
              Expanded(child: BLInput(controller: _search, hint: 'شماره، آیدی یا @username', ltr: true)),
              const Gap(8),
              SizedBox(
                width: 44,
                child: TgButton(
                  icon: Icons.search_rounded,
                  variant: BtnVariant.outline,
                  onPressed: loading
                      ? null
                      : () {
                          query = _search.text.trim();
                          _load();
                        },
                ),
              ),
            ],
          ),
          const Gap(12),
        ],
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (id, label) in const [('', 'همه'), ('pending', 'در انتظار'), ('approved', 'تایید شده'), ('rejected', 'رد شده'), ('cancelled', 'لغو شده')])
              GestureDetector(
                onTap: () {
                  status = id;
                  _load();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: status == id ? C.primary : C.w(5),
                    borderRadius: BorderRadius.circular(8),
                    border: status == id ? null : Border.all(color: C.w(12)),
                  ),
                  child: Text(label, style: t(11, c: status == id ? C.primaryFg : C.n400)),
                ),
              ),
          ],
        ),
        const Gap(12),
        if (loading && items.isEmpty)
          const OrbLoaderPanel()
        else if (items.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(15))),
            child: Text('سفارشی پیدا نشد', textAlign: TextAlign.center, style: t(14, c: C.n500)),
          )
        else ...[
          for (final item in items) ...[_row(item), const Gap(8)],
          if (total > items.length)
            Text('نمایش ${faNum(items.length)} از ${faNum(total)}', textAlign: TextAlign.center, style: t(10, c: C.n500)),
        ],
        const Gap(12),
        TgButton(
          label: loading ? 'در حال بارگذاری…' : 'بروزرسانی',
          icon: loading ? null : Icons.refresh_rounded,
          variant: BtnVariant.outline,
          height: 40,
          onPressed: loading ? null : _load,
        ),
      ],
    );
  }

  Widget _row(J item) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => selected = item),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: C.b(30), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(10))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: C.w(10), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.receipt_long_outlined, size: 14),
                ),
                const Gap(8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text('${item.s('kind_label')} · ${item.s('plan_title')}', overflow: TextOverflow.ellipsis, style: t(14, w: 600)),
                          ),
                          Text(item.s('status_label'), style: t(11, w: 500, c: _statusColor(item.text('status')))),
                        ],
                      ),
                      if (widget.admin)
                        Text(
                          '${item.text('user') ?? '—'}${item.intOrNull('telegram_id') != null ? ' · ${item.i('telegram_id')}' : ''}',
                          overflow: TextOverflow.ellipsis,
                          style: t(10, c: C.n500),
                        ),
                      const Gap(4),
                      Text(
                        [
                          '#${faNum(item.i('id'))}',
                          item.s('amount_label'),
                          if (item.b('has_receipt')) '· رسید ✓',
                          if (item.text('created_at') != null) '· ${formatDateFa(item.text('created_at'))}',
                        ].join('  '),
                        style: t(10, c: C.n500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _detail(J item) {
    final rows = <(String, String)>[
      ('شماره', '#${faNum(item.i('id'))}'),
      if (widget.admin) ...[('کاربر', item.text('user') ?? '—'), ('آیدی تلگرام', item.intOrNull('telegram_id') != null ? '${item.i('telegram_id')}' : '—')],
      ('نوع', item.s('kind_label')),
      ('شرح', item.s('plan_title')),
      ('مبلغ', item.s('amount_label')),
      ('وضعیت', item.s('status_label')),
      ('تاریخ ثبت', formatDateFa(item.text('created_at'))),
      ('تاریخ بررسی', formatDateFa(item.text('reviewed_at'))),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: GestureDetector(
            onTap: () => setState(() => selected = null),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chevron_right_rounded, size: 16, color: C.n400),
                Text('بازگشت به لیست', style: t(11, c: C.n400)),
              ],
            ),
          ),
        ),
        const Gap(12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: C.b(30), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(10))),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(border: i == rows.length - 1 ? null : Border(bottom: BorderSide(color: C.w(8)))),
                  child: Row(
                    children: [
                      Text(rows[i].$1, style: t(11, c: C.n500)),
                      const Gap(12),
                      Expanded(
                        child: Text(
                          rows[i].$2,
                          textAlign: TextAlign.end,
                          textDirection: rows[i].$1 == 'آیدی تلگرام' ? TextDirection.ltr : null,
                          style: t(12, c: rows[i].$1 == 'وضعیت' ? _statusColor(item.text('status')) : C.n100),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (item.i('wallet_used') > 0 && item.text('wallet_used_label') != null) ...[
          const Gap(12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: C.b(25), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(10))),
            child: Text('از کیف‌پول: ${item.s('wallet_used_label')}', style: t(11, c: C.n400)),
          ),
        ],
        if (item.b('has_receipt')) ...[
          const Gap(16),
          Text('رسید پرداخت', style: t(11, w: 500, c: C.n300)),
          const Gap(8),
          OrderReceiptViewer(orderId: item.i('id')),
        ],
        const Gap(16),
        TgButton(label: 'بروزرسانی', icon: Icons.refresh_rounded, variant: BtnVariant.outline, height: 40, onPressed: _load),
      ],
    );
  }
}
