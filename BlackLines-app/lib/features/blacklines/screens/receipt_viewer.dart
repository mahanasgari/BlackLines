import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:hiddify/features/blacklines/core/api.dart';
import 'package:hiddify/features/blacklines/state/controller.dart';
import 'package:hiddify/features/blacklines/ui/kit.dart';
import 'package:hiddify/features/blacklines/ui/tokens.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// order-receipt-viewer.tsx: shows an order's receipt image (tap to zoom) or a PDF button.
class OrderReceiptViewer extends ConsumerStatefulWidget {
  const OrderReceiptViewer({super.key, required this.orderId});

  final int orderId;

  @override
  ConsumerState<OrderReceiptViewer> createState() => _OrderReceiptViewerState();
}

class _OrderReceiptViewerState extends ConsumerState<OrderReceiptViewer> {
  Uint8List? bytes;
  bool loading = true;
  String? error;

  bool get isPdf => bytes != null && bytes!.length > 4 && String.fromCharCodes(bytes!.sublist(0, 4)) == '%PDF';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final b = await ref.read(blControllerProvider).api.orderReceipt(widget.orderId);
      if (mounted) setState(() => bytes = b);
    } catch (e) {
      if (mounted) setState(() => error = e is BLApiError ? persianError(e) : 'خطا در بارگذاری رسید');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _openPdf() async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/receipt-${widget.orderId}.pdf');
    await f.writeAsBytes(bytes!);
    await Share.shareXFiles([XFile(f.path, mimeType: 'application/pdf')]);
  }

  Widget _frame(Widget child) => Container(
        width: double.infinity,
        decoration: BoxDecoration(color: C.b(30), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(10))),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return _frame(Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Text('در حال بارگذاری رسید…', textAlign: TextAlign.center, style: t(12, c: C.n400)),
      ));
    }
    if (error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Callout(error!, tone: Tone.red),
          const Gap(8),
          TgButton(label: 'تلاش مجدد', icon: Icons.refresh_rounded, variant: BtnVariant.outline, height: 36, fontSize: 12, onPressed: _load),
        ],
      );
    }
    final b = bytes;
    if (b == null || b.isEmpty) return const SizedBox.shrink();
    if (isPdf) {
      return _frame(Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('رسید به صورت PDF است', style: t(11, c: C.n400)),
            const Gap(8),
            TgButton(label: 'باز کردن رسید', variant: BtnVariant.outline, height: 40, fontSize: 12, onPressed: _openPdf),
          ],
        ),
      ));
    }
    return GestureDetector(
      onTap: () => showTgSheet(
        context,
        title: 'رسید پرداخت',
        builder: (_) => InteractiveViewer(maxScale: 5, child: Image.memory(b, fit: BoxFit.contain)),
      ),
      child: _frame(
        Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 256),
                child: Center(child: Image.memory(b, fit: BoxFit.contain)),
              ),
            ),
            Positioned(
              bottom: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: C.b(60), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    Icon(Icons.open_in_full_rounded, size: 12, color: C.n200),
                    const Gap(4),
                    Text('بزرگ‌نمایی', style: t(10, c: C.n200)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
