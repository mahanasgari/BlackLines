import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/features/blacklines/core/api.dart';
import 'package:hiddify/features/blacklines/core/format.dart';
import 'package:hiddify/features/blacklines/core/json.dart';
import 'package:hiddify/features/blacklines/screens/common.dart';
import 'package:hiddify/features/blacklines/screens/shop/builders.dart';
import 'package:hiddify/features/blacklines/state/controller.dart';
import 'package:hiddify/features/blacklines/ui/kit.dart';
import 'package:hiddify/features/blacklines/ui/tokens.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// ---------------------------------------------------------------------------
// buy-for-others-panel.tsx
// ---------------------------------------------------------------------------

class CustomerDraft {
  final name = TextEditingController();
  final phone = TextEditingController();
  final telegram = TextEditingController();
  final email = TextEditingController();

  void dispose() {
    name.dispose();
    phone.dispose();
    telegram.dispose();
    email.dispose();
  }

  /// `customerMetaPayload`.
  Map<String, String?> payload(bool enabled) {
    if (!enabled || name.text.trim().isEmpty) return const {};
    String? v(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    return {
      'customer_name': name.text.trim(),
      'customer_email': v(email),
      'customer_phone': v(phone),
      'customer_telegram_id': v(telegram)?.replaceFirst(RegExp('^@'), ''),
    };
  }
}

class BuyForOthersPanel extends StatelessWidget {
  const BuyForOthersPanel({
    super.key,
    required this.enabled,
    required this.onEnabledChange,
    required this.draft,
    required this.onChanged,
    this.disabled = false,
    this.error,
  });

  final bool enabled;
  final ValueChanged<bool> onEnabledChange;
  final CustomerDraft draft;
  final VoidCallback onChanged;
  final bool disabled;
  final String? error;

  Widget _toggle(IconData icon, String label, bool active, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: disabled
              ? null
              : () {
                  haptic();
                  onTap();
                },
          child: Container(
            height: 40,
            decoration: BoxDecoration(color: active ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(8)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: active ? Colors.black : C.n400),
                const Gap(6),
                Text(label, style: t(12, w: 600, c: active ? Colors.black : C.n400)),
              ],
            ),
          ),
        ),
      );

  Widget _field(String label, TextEditingController c, String hint, {bool ltr = false, bool required = false, bool invalid = false, TextInputType? type}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              style: t(10, c: C.n500),
              children: [TextSpan(text: label), if (required) TextSpan(text: ' *', style: t(10, c: C.amber300))],
            ),
          ),
          const Gap(4),
          TextField(
            controller: c,
            enabled: !disabled,
            onChanged: (_) => onChanged(),
            textDirection: ltr ? TextDirection.ltr : null,
            keyboardType: type,
            style: t(14, c: C.white),
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              hintTextDirection: ltr ? TextDirection.ltr : null,
              hintStyle: t(14, c: C.n600),
              filled: true,
              fillColor: C.b(40),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: invalid ? C.a(C.red300, 0.5) : C.w(12)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: invalid ? C.a(C.red300, 0.7) : C.w(25)),
              ),
            ),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final name = draft.name.text.trim();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: C.b(35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: C.w(12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('این کانفیگ مال کیه؟', style: t(14, w: 600, c: C.white)),
          const Gap(2),
          Text('اول مشخص کن برای خودت می‌خری یا برای کس دیگری.', style: t(11, c: C.n400, h: 1.6)),
          const Gap(12),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: C.b(40),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: C.w(10)),
            ),
            child: Row(
              children: [
                _toggle(Icons.person_outline_rounded, 'برای خودم', !enabled, () => onEnabledChange(false)),
                const Gap(4),
                _toggle(Icons.card_giftcard_rounded, 'برای کس دیگری', enabled, () => onEnabledChange(true)),
              ],
            ),
          ),
          const Gap(12),
          if (!enabled)
            Text('کانفیگ روی همین حساب ساخته می‌شود و لینک‌ها مال خودت است.', style: t(11, c: C.n500, h: 1.6))
          else ...[
            const StepList(
              tone: Tone.teal,
              steps: [
                (Icons.group_outlined, 'اسم مشتری را بنویس تا بعداً پیدایش کنی'),
                (Icons.account_balance_wallet_outlined, 'خودت پرداخت می‌کنی — مشتری پولی نمی‌دهد'),
                (Icons.send_outlined, 'بعد از تایید، از میز فروش لینک را کپی کن و برایش بفرست'),
              ],
            ),
            const Gap(12),
            _field('نام مشتری', draft.name, 'مثلاً علی رضایی', required: true, invalid: error != null && name.isEmpty),
            const Gap(8),
            _field('موبایل (اختیاری)', draft.phone, '0912…', ltr: true, type: TextInputType.phone),
            const Gap(8),
            _field('تلگرام (اختیاری)', draft.telegram, '@username یا عدد', ltr: true),
            const Gap(8),
            _field('ایمیل (اختیاری)', draft.email, 'customer@email.com', ltr: true, type: TextInputType.emailAddress),
            const Gap(12),
            if (error != null)
              Text(error!, style: t(11, c: C.red300))
            else if (name.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: C.w(5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: C.w(10)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('الان می‌خری برای', style: t(10, c: C.n500)),
                    const Gap(2),
                    Text(name, style: t(14, w: 600, c: C.white)),
                    const Gap(4),
                    Text(
                      'کانفیگ مال حساب تو می‌ماند. مشتری فقط لینکی را می‌گیرد که بعداً برایش می‌فرستی.',
                      style: t(11, c: C.n400, h: 1.6),
                    ),
                  ],
                ),
              )
            else
              Text('برای ادامه، حداقل نام مشتری لازم است.', style: t(11, c: C.a(C.amber200, 0.9))),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// purchase-confirm-panel.tsx
// ---------------------------------------------------------------------------

class PurchaseConfirmPanel extends ConsumerStatefulWidget {
  const PurchaseConfirmPanel({super.key, required this.draft});

  final PurchaseDraft draft;

  @override
  ConsumerState<PurchaseConfirmPanel> createState() => _PurchaseConfirmPanelState();
}

class _PurchaseConfirmPanelState extends ConsumerState<PurchaseConfirmPanel> {
  bool buyForOthers = false;
  final customer = CustomerDraft();
  final _promo = TextEditingController();
  final _name = TextEditingController();
  String? error;
  String? priceHint;
  String? promoHint;
  bool promoError = false;
  bool promoChecking = false;
  Timer? _debounce;

  PurchaseDraft get d => widget.draft;
  bool get isGift => d.kind == 'plan' && d.giftCard;
  int get familySize => d.kind == 'payg' || isGift ? 1 : d.familySize;
  String get title => d.kind == 'plan' ? '${isGift ? 'کارت هدیه · ' : ''}${d.plan!.s('title')}' : d.title;
  String get _fallbackPrice =>
      d.kind == 'plan' ? priceText(d.plan!.intOrNull('charge_toman') ?? d.plan!.i('price_toman')) : (d.chargeLabel ?? '');

  @override
  void initState() {
    super.initState();
    priceHint = _fallbackPrice.isEmpty ? null : _fallbackPrice;
    _basePrice();
  }

  @override
  void dispose() {
    customer.dispose();
    _promo.dispose();
    _name.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Map<String, dynamic> get _customShape => {
        'duration_days': d.durationDays,
        'traffic_gb': d.trafficGb,
        'limit_ip': d.limitIp,
        'unlimited': d.unlimited,
      };

  /// Server-side price for the chosen family size (no promo).
  Future<void> _basePrice() async {
    if (d.kind == 'payg') return;
    final api = ref.read(blControllerProvider).api;
    try {
      final r = d.kind == 'plan'
          ? await api.validatePromo({'code': '', 'plan_id': d.plan!.i('id'), 'family_size': familySize})
          : await api.customQuote({..._customShape, 'family_size': familySize});
      if (mounted && _promo.text.trim().isEmpty) setState(() => priceHint = r.text('charge_label') ?? priceHint);
    } catch (_) {}
  }

  /// shop-growth-controls.tsx promo validation.
  void _onPromo(String raw) {
    final up = raw.toUpperCase();
    if (up != raw) _promo.value = _promo.value.copyWith(text: up, selection: TextSelection.collapsed(offset: up.length));
    _debounce?.cancel();
    final code = up.trim();
    if (code.isEmpty) {
      setState(() {
        promoHint = familySize > 1 ? 'پکیج خانواده: ${faNum(familySize)} کانفیگ' : null;
        promoError = false;
        priceHint = _fallbackPrice.isEmpty ? null : _fallbackPrice;
      });
      _basePrice();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => promoChecking = true);
      try {
        final res = await ref.read(blControllerProvider).api.validatePromo({
          'code': code,
          if (d.kind == 'plan') 'plan_id': d.plan!.i('id'),
          'family_size': familySize,
          if (d.kind == 'custom') ..._customShape,
        });
        final parts = [
          if (res.i('discount_toman') > 0) 'تخفیف ${faNum(res.i('discount_toman'))} تومان',
          if (res.i('bonus_days') > 0) '${faNum(res.i('bonus_days'))} روز هدیه',
          if (res.i('family_size') > 1) '${faNum(res.i('family_size'))} کانفیگ',
          'مبلغ: ${res.s('charge_label')}',
        ];
        setState(() {
          promoHint = parts.join(' · ');
          promoError = false;
          priceHint = res.text('charge_label') ?? priceHint;
        });
      } catch (e) {
        setState(() {
          promoHint = persianError(e);
          promoError = true;
          priceHint = null;
        });
      } finally {
        if (mounted) setState(() => promoChecking = false);
      }
    });
  }

  void _submit() {
    if (!isGift && buyForOthers && customer.name.text.trim().isEmpty) {
      setState(() => error = 'اگر برای کس دیگری می‌خری، نامش را بنویس.');
      return;
    }
    final name = _name.text.trim();
    ref.read(blControllerProvider).confirmPurchase(
          promoCode: _promo.text.trim().isEmpty ? null : _promo.text.trim(),
          configLabel: name.isEmpty ? null : name,
          familySize: familySize,
          customer: customer.payload(buyForOthers),
          recipientName: buyForOthers && customer.name.text.trim().isNotEmpty ? customer.name.text.trim() : null,
        );
  }

  Widget _section({required IconData icon, required String title, required List<Widget> children}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: C.b(35),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: C.w(12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: C.n400),
                const Gap(6),
                Text(title, style: t(12, w: 600, c: C.n100)),
              ],
            ),
            const Gap(10),
            ...children,
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(blControllerProvider);
    final spec = switch (d.kind) {
      'plan' =>
        '${faNum(d.plan!.i('duration_days'))} روز · ${d.plan!.i('traffic_gb') > 0 ? '${faNum(d.plan!.i('traffic_gb'))} گیگ' : 'نامحدود'} · ${faNum(d.plan!.i('limit_ip'))} دستگاه',
      'custom' =>
        '${faNum(d.durationDays)} روز · ${d.unlimited ? 'حجم نامحدود' : '${faNum(d.trafficGb)} گیگ'} · ${faNum(d.limitIp)} دستگاه',
      _ => '${faNum(d.trafficGb)} گیگ · ${faNum(d.limitIp)} دستگاه',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: GestureDetector(
            onTap: () => c.setPurchaseDraft(null),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_forward_rounded, size: 14, color: C.n400),
                const Gap(4),
                Text('بازگشت به فروشگاه', style: t(12, c: C.n400)),
              ],
            ),
          ),
        ),
        const Gap(12),
        Text('تأیید خرید', style: t(14, w: 600, c: C.white)),
        const Gap(2),
        Text(
          isGift
              ? 'بعد از پرداخت یک کد می‌گیری و می‌توانی در تلگرام بفرستی.'
              : 'مشخصات را چک کنید، اگر کد تخفیف دارید وارد کنید، و برای کانفیگ اسم بگذارید.',
          style: t(11, c: C.n400, h: 1.6),
        ),
        const Gap(12),
        _section(
          icon: Icons.receipt_long_outlined,
          title: '۱. تأیید مشخصات',
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: C.w(5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: C.w(10)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t(14, w: 600, c: C.white)),
                  const Gap(4),
                  Text('$spec${familySize > 1 ? ' · خانواده ${faNum(familySize)} کانفیگ' : ''}', style: t(11, c: C.n400, h: 1.6)),
                  if (priceHint != null) ...[const Gap(8), Text(priceHint!, style: t(14, w: 700, c: C.white))],
                ],
              ),
            ),
            const Gap(10),
            if (isGift)
              const Callout('این خرید کانفیگ روی حساب تو نمی‌سازد — فقط یک کد هدیه می‌دهد.', tone: Tone.amber)
            else
              BuyForOthersPanel(
                enabled: buyForOthers,
                onEnabledChange: (v) => setState(() {
                  buyForOthers = v;
                  error = null;
                }),
                draft: customer,
                onChanged: () => setState(() => error = null),
                disabled: c.busy,
                error: error,
              ),
          ],
        ),
        const Gap(12),
        if (d.kind != 'payg' && !isGift)
          _section(
            icon: Icons.percent_rounded,
            title: '۲. تخفیف',
            children: [
              Text('تخفیف فروشگاه خودکار است. کد تخفیف اختیاری است.', style: t(11, c: C.n500, h: 1.6)),
              const Gap(8),
              Text('کد تخفیف هنگام خرید', style: t(12, w: 500, c: C.n200)),
              const Gap(4),
              BLInput(controller: _promo, hint: 'اختیاری', ltr: true, enabled: !c.busy, onChanged: _onPromo),
              if (promoChecking) ...[
                const Gap(6),
                Text('در حال بررسی…', style: t(10, c: C.n500)),
              ] else if (promoHint != null) ...[
                const Gap(6),
                Text(promoHint!, style: t(10, c: promoError ? C.rose300 : C.a(C.emerald300, 0.9))),
              ],
            ],
          )
        else
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: C.b(35),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: C.w(12)),
            ),
            child: Text('خرید حجم کد تخفیف ندارد. مبلغ همان است که در مرحله قبل دیدید.', style: t(11, c: C.n500, h: 1.6)),
          ),
        const Gap(12),
        _section(
          icon: Icons.edit_outlined,
          title: '${d.kind == 'payg' ? '۲' : '۳'}. نام کانفیگ',
          children: [
            Text('این اسم روی داشبورد می‌آید. خالی بماند همان «$title» می‌ماند.', style: t(11, c: C.n500, h: 1.6)),
            const Gap(8),
            BLInput(controller: _name, hint: title, maxLength: 64, enabled: !c.busy),
          ],
        ),
        const Gap(12),
        TgButton(label: 'تأیید و ادامه پرداخت', onPressed: c.busy ? null : _submit),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// checkout-panel.tsx + payment-card-viewer.tsx
// ---------------------------------------------------------------------------

class CheckoutPanel extends ConsumerWidget {
  const CheckoutPanel({super.key, required this.checkout});

  final Checkout checkout;

  Future<void> _pickReceipt(BLController c) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
    );
    final f = res?.files.singleOrNull;
    if (f?.path == null) return;
    await c.uploadReceipt(f!.path!, f.name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(blControllerProvider);
    final k = checkout;
    final title = switch (k.kind) {
      'wallet' => 'شارژ کیف‌پول · سفارش ${faNum(k.orderId)}',
      'pro' => 'اشتراک Pro · سفارش ${faNum(k.orderId)}',
      _ => 'تسویه سفارش · ${faNum(k.orderId)}',
    };
    final cards = paymentCardsFrom(k.payment);
    final note = k.payment.text('note');
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(alignment: AlignmentDirectional.centerStart, child: Tag('مرحله ۱ از ۲ · واریز', tone: Tone.white, size: 11)),
          const Gap(6),
          Text(title, style: t(18, w: 800, h: 1.4)),
          const Gap(4),
          Text('مبلغ و شماره را از فیش زیر کپی کنید، واریز کنید، بعد رسید را بفرستید.', style: t(14, c: C.n400, h: 1.6)),
          if (k.recipientName != null) ...[
            const Gap(16),
            _Banner(
              tone: Tone.teal,
              caption: 'این سفارش برای مشتری است',
              title: k.recipientName!,
              text: 'بعد از تایید ادمین، کانفیگ روی میز فروش شما ظاهر می‌شود. همان‌جا لینک را کپی کنید و برای ${k.recipientName} بفرستید.',
            ),
          ],
          if ((k.familySize ?? 1) > 1) ...[
            const Gap(16),
            _Banner(
              tone: Tone.sky,
              caption: 'پکیج خانواده',
              title: '${faNum(k.familySize!)} کانفیگ جدا · ۱ والد + ${faNum(k.familySize! - 1)} فرزند',
              text:
                  'بعد از تایید، همه روی داشبورد شما می‌آیند. هر لینک را برای همان نفر بفرستید. از کانفیگ «والد» می‌توانید سایت‌های فرزند را محدود کنید.',
            ),
          ],
          if (k.walletUsed > 0) ...[
            const Gap(16),
            _Note('${priceText(k.walletUsed)} از کیف‌پول شما کسر شده است'),
          ],
          const Gap(16),
          PaymentCardViewer(cards: cards, amountToman: k.amountToman, orderId: k.orderId, disabled: c.busy),
          if (note != null && !cards.any((e) => e.text('note') != null)) ...[const Gap(16), _Note(note)],
          const Gap(16),
          Divider(height: 1, color: C.w(10)),
          const Gap(16),
          const Align(alignment: AlignmentDirectional.centerStart, child: Tag('مرحله ۲ از ۲ · رسید', tone: Tone.white, size: 11)),
          const Gap(8),
          TgButton(
            height: 48,
            icon: Icons.upload_rounded,
            label: c.busy ? 'در حال ارسال رسید…' : 'ارسال عکس رسید پرداخت',
            busy: c.busy,
            onPressed: () => _pickReceipt(c),
          ),
          const Gap(8),
          Text(
            'یک عکس معمولی از گالری بفرستید. اگر روی لودینگ ماند، فیلترشکن را خاموش کنید و دوباره همان عکس را بفرستید.',
            textAlign: TextAlign.center,
            style: t(11, c: C.n500, h: 1.6),
          ),
          const Gap(8),
          TgButton(
            label: 'لغو سفارش و بازگشت وجه به کیف‌پول',
            variant: BtnVariant.ghost,
            onPressed: c.busy ? null : () => c.cancelOrder(k.orderId, isCheckout: true),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.tone, required this.caption, required this.title, required this.text});

  final Tone tone;
  final String caption;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final (bg, border, fg) = toneColors(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(caption, style: t(10, c: C.a(fg, 0.8))),
          const Gap(2),
          Text(title, style: t(14, w: 600, c: C.white)),
          const Gap(4),
          Text(text, style: t(11, c: C.n300, h: 1.6)),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: C.w(5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: C.w(10)),
        ),
        child: Text(text, style: t(12, c: C.n300, h: 1.6)),
      );
}

/// payment-card-viewer.tsx: swipeable card slip with masked number (tap to reveal).
class PaymentCardViewer extends StatefulWidget {
  const PaymentCardViewer({
    super.key,
    required this.cards,
    required this.amountToman,
    required this.orderId,
    this.disabled = false,
  });

  final List<J> cards;
  final int amountToman;
  final int orderId;
  final bool disabled;

  @override
  State<PaymentCardViewer> createState() => _PaymentCardViewerState();
}

class _PaymentCardViewerState extends State<PaymentCardViewer> {
  int index = 0;
  bool revealed = false;
  String? copied;

  void _flash(String kind) {
    setState(() => copied = kind);
    Future<void>.delayed(const Duration(milliseconds: 1600), () {
      if (mounted && copied == kind) setState(() => copied = null);
    });
  }

  static String _group(String digits) =>
      RegExp('.{1,4}').allMatches(digits).map((m) => m[0]).join(' ');

  static String _mask(String digits) {
    final last4 = digits.length >= 4 ? digits.substring(digits.length - 4) : digits.padLeft(4, '•');
    final groups = (digits.length / 4).ceil().clamp(1, 8);
    return [...List.filled(groups - 1, '••••'), last4].join(' ');
  }

  Widget _copyChip(String kind, String label, VoidCallback onTap) {
    final done = copied == kind;
    return GestureDetector(
      onTap: widget.disabled ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: done ? C.a(C.emerald500, 0.15) : C.w(5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: done ? C.a(C.emerald400, 0.3) : C.w(12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(done ? Icons.check_rounded : Icons.copy_rounded, size: 14, color: done ? C.emerald200 : C.n200),
            const Gap(6),
            Text(done ? 'کپی شد' : label, style: t(11, w: 600, c: done ? C.emerald200 : C.n200)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cards = widget.cards;
    if (cards.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
        decoration: BoxDecoration(
          color: C.w(5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: C.w(12)),
        ),
        child: Text('کارت پرداخت تنظیم نشده است', textAlign: TextAlign.center, style: t(14, c: C.n400)),
      );
    }
    final i = index.clamp(0, cards.length - 1);
    final card = cards[i];
    final digits = digitsOnly(card.s('card'));
    final holder = card.text('name') ?? 'دریافت‌کننده';
    final label = card.text('label') ?? 'کارت ${faNum(i + 1)}';

    void select(int next) {
      if (next < 0 || next >= cards.length || next == i) return;
      haptic();
      setState(() {
        index = next;
        revealed = false;
        copied = null;
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onHorizontalDragEnd: (e) {
            final v = e.primaryVelocity ?? 0;
            if (v.abs() < 200) return;
            // RTL: swipe left = next.
            select(v < 0 ? i + 1 : i - 1);
          },
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Container(
              key: ValueKey(i),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: C.w(12)),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [C.w(8), C.b(40)],
                ),
              ),
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
                            Text('واریز به این کارت', style: t(10, c: C.n500)),
                            const Gap(2),
                            Text(label, overflow: TextOverflow.ellipsis, style: t(14, w: 600, c: C.white)),
                            Text('به نام $holder', overflow: TextOverflow.ellipsis, style: t(12, c: C.n400)),
                          ],
                        ),
                      ),
                      Tag('#${faNum(widget.orderId)}', tone: Tone.neutral, size: 11),
                    ],
                  ),
                  const Gap(12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: C.w(5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: C.w(10)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('مبلغ قابل پرداخت', style: t(10, c: C.n500)),
                              const Gap(2),
                              Text('${faNum(widget.amountToman)} تومان', style: t(16, w: 700, c: C.white)),
                            ],
                          ),
                        ),
                        _copyChip('amount', 'کپی مبلغ', () async {
                          await copyText('${widget.amountToman}');
                          _flash('amount');
                        }),
                      ],
                    ),
                  ),
                  const Gap(8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: C.b(30),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: C.w(10)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => revealed = !revealed),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(revealed ? 'شماره کامل' : 'شماره کارت', style: t(10, c: C.n500)),
                                const Gap(2),
                                Text(
                                  revealed ? _group(digits) : _mask(digits),
                                  textDirection: TextDirection.ltr,
                                  style: t(14, c: C.white, mono: true).copyWith(letterSpacing: 1.6),
                                ),
                              ],
                            ),
                          ),
                        ),
                        _copyChip('card', 'کپی شماره', () async {
                          await copyText(digits);
                          _flash('card');
                        }),
                      ],
                    ),
                  ),
                  const Gap(8),
                  GestureDetector(
                    onTap: () => setState(() => revealed = !revealed),
                    child: Row(
                      children: [
                        Icon(revealed ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 14, color: C.n500),
                        const Gap(6),
                        Text(revealed ? 'پنهان کردن شماره' : 'برای دیدن شماره کامل بزنید', style: t(11, c: C.n500)),
                      ],
                    ),
                  ),
                  if (card.text('note') != null) ...[
                    const Gap(8),
                    Text(card.s('note'), style: t(11, c: C.n300, h: 1.6)),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (cards.length > 1) ...[
          const Gap(10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var j = 0; j < cards.length; j++)
                GestureDetector(
                  onTap: () => select(j),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: j == i ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(color: j == i ? Colors.white : C.w(25), borderRadius: BorderRadius.circular(999)),
                  ),
                ),
            ],
          ),
          const Gap(4),
          Text(
            '${faNum(cards.length)} کارت — برای کارت دیگر بکشید',
            textAlign: TextAlign.center,
            style: t(10, c: C.n500),
          ),
        ],
      ],
    );
  }
}
