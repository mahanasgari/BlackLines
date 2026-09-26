import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/features/blacklines/core/api.dart';
import 'package:hiddify/features/blacklines/core/format.dart';
import 'package:hiddify/features/blacklines/core/json.dart';
import 'package:hiddify/features/blacklines/screens/common.dart';
import 'package:hiddify/features/blacklines/screens/receipt_viewer.dart';
import 'package:hiddify/features/blacklines/state/controller.dart';
import 'package:hiddify/features/blacklines/ui/kit.dart';
import 'package:hiddify/features/blacklines/ui/tokens.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// admin-pending-order-sheet.tsx.
Future<void> openPendingOrderSheet(BuildContext context, J order) => showTgSheet(
      context,
      title: 'سفارش #${faNum(order.i('id'))}',
      description: order.text('plan'),
      builder: (_) => _PendingOrder(order: order),
    );

class _PendingOrder extends ConsumerStatefulWidget {
  const _PendingOrder({required this.order});

  final J order;

  @override
  ConsumerState<_PendingOrder> createState() => _PendingOrderState();
}

class _PendingOrderState extends ConsumerState<_PendingOrder> {
  bool acting = false;
  bool uploading = false;
  late J order = widget.order;

  BLController get c => ref.read(blControllerProvider);

  Future<void> _act(bool approve) async {
    setState(() => acting = true);
    try {
      approve ? await c.adminApprove(order.i('id')) : await c.adminReject(order.i('id'));
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
    } finally {
      if (mounted) setState(() => acting = false);
    }
  }

  Future<void> _refresh() async {
    await c.refreshAdmin();
    final fresh = c.adminOrders.where((o) => o.i('id') == order.i('id')).firstOrNull;
    if (fresh != null && mounted) setState(() => order = fresh);
  }

  Future<void> _upload() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf']);
    final f = res?.files.singleOrNull;
    if (f?.path == null) return;
    setState(() => uploading = true);
    try {
      await c.api.adminUploadReceipt(order.i('id'), f!.path!, f.name);
      haptic();
      notify('رسید ثبت شد', ToastStatus.success);
      await _refresh();
    } catch (e) {
      notify(persianError(e), ToastStatus.error);
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(blControllerProvider.select((c) => c.busy)) || acting;
    final hasReceipt = order.b('has_receipt');
    final rows = <(String, String, bool, Color?)>[
      ('کاربر', order.text('user') ?? '—', false, null),
      ('آیدی تلگرام', '${order.i('telegram_id')}', true, null),
      ('مبلغ', order.s('amount_label'), false, null),
      if (order.i('family_size', 1) > 1) ('پکیج خانواده', '${faNum(order.i('family_size'))} کانفیگ', false, null),
      if (order.text('promo_code') != null)
        (
          'کد تخفیف',
          '${order.s('promo_code')}${order.i('bonus_days') > 0 ? ' · +${faNum(order.i('bonus_days'))} روز' : ''}${order.i('discount_toman') > 0 ? ' · −${faNum(order.i('discount_toman'))}' : ''}',
          true,
          C.emerald300,
        ),
      ('رسید', hasReceipt ? 'ارسال شده' : 'ارسال نشده', false, hasReceipt ? C.emerald400 : C.amber400),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: C.b(30), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(10))),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(border: i == rows.length - 1 ? null : Border(bottom: BorderSide(color: C.w(8)))),
                  child: Row(
                    children: [
                      Text(rows[i].$1, style: t(11, c: C.n500)),
                      const Gap(12),
                      Expanded(
                        child: Text(
                          rows[i].$2,
                          textAlign: TextAlign.end,
                          textDirection: rows[i].$3 ? TextDirection.ltr : null,
                          style: t(12, c: rows[i].$4 ?? C.n100, mono: rows[i].$3),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const Gap(16),
        if (hasReceipt) ...[
          Text('تصویر رسید', style: t(12, w: 600, c: C.n300)),
          const Gap(8),
          OrderReceiptViewer(orderId: order.i('id')),
        ] else ...[
          const Callout('کاربر هنوز رسید را در اپ آپلود نکرده — می‌توانید اینجا ثبت کنید یا بدون رسید تایید کنید.', tone: Tone.amber),
          const Gap(8),
          TgButton(
            label: uploading ? 'در حال آپلود…' : 'آپلود رسید',
            icon: Icons.upload_rounded,
            variant: BtnVariant.outline,
            onPressed: busy || uploading ? null : _upload,
          ),
        ],
        const Gap(16),
        Row(
          children: [
            Expanded(
              child: TgButton(label: 'کپی شماره', icon: Icons.copy_rounded, variant: BtnVariant.outline, onPressed: busy ? null : () => copyText('${order.i('id')}')),
            ),
            const Gap(8),
            Expanded(
              child: TgButton(label: 'بروزرسانی', icon: Icons.refresh_rounded, variant: BtnVariant.outline, onPressed: busy ? null : _refresh),
            ),
          ],
        ),
        const Gap(8),
        Row(
          children: [
            Expanded(child: TgButton(label: 'تایید', onPressed: busy || !hasReceipt ? null : () => _act(true))),
            const Gap(8),
            Expanded(child: TgButton(label: 'رد', variant: BtnVariant.outline, onPressed: busy ? null : () => _act(false))),
          ],
        ),
        if (!hasReceipt) ...[
          const Gap(8),
          TgButton(label: 'تایید بدون رسید (ادمین)', variant: BtnVariant.outline, onPressed: busy ? null : () => _act(true)),
        ],
      ],
    );
  }
}
