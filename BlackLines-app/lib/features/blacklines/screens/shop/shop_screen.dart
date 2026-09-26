import 'package:flutter/material.dart';
import 'package:hiddify/features/blacklines/core/format.dart';
import 'package:hiddify/features/blacklines/core/json.dart';
import 'package:hiddify/features/blacklines/screens/sheets/wallet_sheet.dart';
import 'package:hiddify/features/blacklines/screens/shop/builders.dart';
import 'package:hiddify/features/blacklines/screens/shop/purchase.dart';
import 'package:hiddify/features/blacklines/state/controller.dart';
import 'package:hiddify/features/blacklines/ui/kit.dart';
import 'package:hiddify/features/blacklines/ui/tokens.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// App.tsx `tab === "shop"`.
class ShopScreen extends ConsumerWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(blControllerProvider);
    final idle = c.checkout == null && c.purchaseDraft == null;
    final trial = c.me?.objOrNull('trial_offer');
    return ListView(
      // Scroll back to the top whenever the shop step changes (App.tsx mainRef.scrollTo).
      key: ValueKey('${c.shopSection}-${identityHashCode(c.purchaseDraft)}-${c.checkout?.orderId}'),
      padding: const EdgeInsets.all(12),
      children: [
        if (idle && (trial?.b('available') ?? false)) ...[_TrialOffer(c: c, offer: trial!), const Gap(12)],
        if (idle && c.shopSection == ShopSection.custom) ...[
          const SectionIntro(
            title: 'پکیج سفارشی',
            description: 'مدت، حجم و تعداد دستگاه را خودتان بسازید. تخفیف و نام کانفیگ در مرحله بعد است.',
          ),
          const Gap(12),
          const CustomPackageBuilder(),
        ],
        if (idle && c.shopSection == ShopSection.payg) ...[
          const SectionIntro(
            title: 'پرداخت مصرفی',
            description: 'یا کیف‌پول را شارژ کنید و فقط مصرف واقعی بپردازید، یا یکجا حجم بخرید.',
          ),
          const Gap(12),
          Segmented<String>(
            items: const [('cloud', 'ابری'), ('traffic', 'خرید حجم')],
            value: c.paygMode,
            onChanged: c.setPaygMode,
          ),
          const Gap(12),
          if (c.paygMode == 'cloud') PaygCloudBuilder(onTopup: () => openWalletSheet(context)) else const PaygTrafficBuilder(),
        ],
        if (idle && c.shopSection == ShopSection.plans) ..._plans(c),
        if (idle && c.shopSection == ShopSection.gift) ...[
          const SectionIntro(
            title: 'کارت هدیه',
            description: 'یک پلن بخر و کد را برای دوستت بفرست، یا کدی که گرفته‌ای را اینجا فعال کن.',
          ),
          const Gap(12),
          const GiftCardsPanel(),
        ],
        if (c.checkout == null && c.purchaseDraft != null) PurchaseConfirmPanel(key: ObjectKey(c.purchaseDraft), draft: c.purchaseDraft!),
        if (c.checkout != null) CheckoutPanel(checkout: c.checkout!),
        const Gap(12),
      ],
    );
  }

  List<Widget> _plans(BLController c) {
    final plans = c.filteredPlans;
    return [
      const SectionIntro(
        title: 'پکیج‌های آماده',
        description: 'پلن و تعداد نفر را انتخاب کنید. تخفیف، نام کانفیگ و تأیید مشخصات در مرحله بعد است.',
      ),
      const Gap(12),
      FilterBar<Object>(
        items: const [('all', 'همه'), (30, '۱ ماه'), (90, '۳ ماه'), (180, '۶ ماه')],
        value: c.filter,
        onChanged: c.setFilter,
      ),
      const Gap(12),
      if (plans.isNotEmpty) ...[
        FamilyPackPanel(familySize: c.shopFamilySize, onChanged: c.setFamilySize, disabled: c.busy),
        const Gap(12),
      ],
      if (plans.isEmpty) const EmptyState(message: 'پلنی در این دسته نیست.'),
      for (final p in plans) ...[_PlanCard(plan: p, c: c), const Gap(12)],
    ];
  }
}

class _TrialOffer extends StatelessWidget {
  const _TrialOffer({required this.c, required this.offer});

  final BLController c;
  final J offer;

  @override
  Widget build(BuildContext context) {
    return Panel(
      color: C.a(C.amber300, 0.05),
      borderColor: C.a(C.amber300, 0.2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.card_giftcard_rounded, size: 16, color: C.amber300)),
              const Gap(8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('کانفیگ تست رایگان', style: t(15, w: 600, c: C.white)),
                    const Gap(2),
                    Text(
                      '${faNum(offer.i('duration_days'))} روز · ${offer.s('traffic_label')} · ${faNum(offer.i('limit_ip'))} دستگاه',
                      style: t(11, c: C.n400),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Gap(12),
          TgButton(label: 'دریافت VPN تست', onPressed: c.busy ? null : c.claimTrial),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.c});

  final J plan;
  final BLController c;

  @override
  Widget build(BuildContext context) {
    final price = plan.i('price_toman');
    final charge = plan.intOrNull('charge_toman') ?? price;
    final pro = plan.i('pro_discount_percent');
    final discounted = pro > 0 && charge < price;
    final gb = plan.i('traffic_gb');
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: t(15, w: 600, h: 1.4),
                    children: [
                      TextSpan(text: plan.s('title')),
                      if (plan.b('pro_only') || gb <= 0) TextSpan(text: '  Pro', style: t(10, w: 600, c: C.amber300)),
                    ],
                  ),
                ),
              ),
              const Gap(12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: discounted
                    ? [
                        Text(priceText(price), style: t(10, c: C.n500, deco: TextDecoration.lineThrough)),
                        Text(priceText(charge), style: t(14, w: 700, c: C.emerald300)),
                        Text('Pro · ${faNum(pro)}٪ تخفیف', style: t(10, c: C.a(C.emerald400, 0.9))),
                      ]
                    : [Text(priceText(price), style: t(14, w: 700))],
              ),
            ],
          ),
          if (plan.text('description') != null) ...[
            const Gap(4),
            Text(plan.s('description'), style: t(12, c: C.n400, h: 1.6)),
          ],
          const Gap(12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              MiniChip('${faNum(plan.i('duration_days'))} روز'),
              MiniChip(gb > 0 ? '${faNum(gb)} گیگ' : 'نامحدود'),
              MiniChip('${faNum(plan.i('limit_ip'))} دستگاه'),
            ],
          ),
          if (plan.i('pay_after_wallet') < charge) ...[
            const Gap(10),
            Text('قابل پرداخت با کیف‌پول: ${priceText(plan.i('pay_after_wallet'))}', style: t(11, c: C.n400)),
          ],
          if (!c.isPro && pro > 0) ...[
            const Gap(6),
            Text('با Pro ${faNum(pro)}٪ ارزان‌تر — دکمه Pro در بالا', style: t(11, c: C.a(C.amber400, 0.9))),
          ],
          const Gap(12),
          TgButton(
            label: c.shopFamilySize > 1 ? 'ادامه · خانواده ${faNum(c.shopFamilySize)} کانفیگ' : 'ادامه خرید',
            onPressed: c.busy ? null : () => c.startPlanPurchase(plan),
          ),
        ],
      ),
    );
  }
}
