import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/features/blacklines/core/format.dart';
import 'package:hiddify/features/blacklines/notifier/default_profiles.dart';
import 'package:hiddify/features/blacklines/screens/admin/admin_screen.dart';
import 'package:hiddify/features/blacklines/screens/chat_screen.dart';
import 'package:hiddify/features/blacklines/screens/connect_screen.dart';
import 'package:hiddify/features/blacklines/screens/dashboard_screen.dart';
import 'package:hiddify/features/blacklines/screens/invite_screen.dart';
import 'package:hiddify/features/blacklines/screens/login_screen.dart';
import 'package:hiddify/features/blacklines/screens/profile_screen.dart';
import 'package:hiddify/features/blacklines/screens/sheets/notification_center.dart';
import 'package:hiddify/features/blacklines/screens/sheets/pro_sheet.dart';
import 'package:hiddify/features/blacklines/screens/sheets/wallet_sheet.dart';
import 'package:hiddify/features/blacklines/screens/shop/shop_screen.dart';
import 'package:hiddify/features/blacklines/state/controller.dart';
import 'package:hiddify/features/blacklines/ui/kit.dart';
import 'package:hiddify/features/blacklines/ui/tokens.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Native port of miniapp/src/App.tsx, plus the Hiddify-powered Connect tab.
class BLShell extends ConsumerWidget {
  const BLShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(blControllerProvider);
    // Public fallback configs (Mahsa) for every install; runs once per launch.
    ref.watch(blDefaultProfilesProvider);
    ref.listen(blControllerProvider.select((c) => c.pendingTrialSheet), (_, next) {
      if (next == null) return;
      final trial = ref.read(blControllerProvider).takeTrialSheet();
      if (trial != null) openTrialSheet(context, trial);
    });
    // theme.tsx: saved choice, otherwise follow the phone.
    C.light = c.themePref == null ? MediaQuery.platformBrightnessOf(context) == Brightness.light : c.themePref == 'light';
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Theme(
        data: blTheme(Theme.of(context)),
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: (C.light ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light).copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: C.navBar,
            systemNavigationBarIconBrightness: C.light ? Brightness.dark : Brightness.light,
          ),
          child: Scaffold(
            backgroundColor: C.background,
            resizeToAvoidBottomInset: true,
            body: Stack(
              key: ValueKey(C.light),
              children: [
                GradientField(
                  // Phone-first layout: keep it phone-width on wide desktop windows.
                  child: Center(
                    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: _body(context, c)),
                  ),
                ),
                const Positioned(top: 0, left: 0, right: 0, child: ToastHost()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, BLController c) {
    if (c.auth == AuthPhase.unknown) return const _Centered(child: OrbLoader());
    if (c.auth == AuthPhase.loggedOut) return const LoginScreen();
    // Signed in or guest: the shell (and Connect) is always usable; account
    // sections show their own loading/offline state while the server syncs.
    return _Main(c: c);
  }
}

/// Account tabs before the first sync lands (no cache yet), or when the server
/// requires channel membership. Connect never goes through this.
class _AccountGate extends StatelessWidget {
  const _AccountGate({required this.c});

  final BLController c;

  @override
  Widget build(BuildContext context) {
    if (c.channelGate case final gate?) {
      return _Centered(
        child: Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('عضویت در کانال الزامی است', style: t(16, w: 600)),
              const Gap(8),
              Text(gate.message, style: t(14, c: C.n300, h: 1.7)),
              const Gap(8),
              Text('@${gate.channel}', textDirection: TextDirection.ltr, textAlign: TextAlign.end, style: t(12, c: C.n400)),
              const Gap(16),
              TgButton(
                label: 'عضویت در کانال',
                onPressed: () {
                  haptic();
                  launchUrl(Uri.parse(gate.inviteUrl), mode: LaunchMode.externalApplication);
                },
              ),
              const Gap(8),
              TgButton(
                label: c.busy ? 'در حال بررسی…' : 'عضو شدم — بررسی',
                variant: BtnVariant.outline,
                onPressed: c.busy ? null : c.recheckChannel,
              ),
            ],
          ),
        ),
      );
    }
    if (c.error case final err? when !c.syncing) {
      return _Centered(
        child: Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('دریافت اطلاعات حساب ممکن نشد', style: t(16, w: 600)),
              const Gap(8),
              Text(err, style: t(14, c: C.n300, h: 1.7)),
              const Gap(6),
              Text('خودکار دوباره تلاش می‌کنیم. تا آن موقع از «اتصال» استفاده کنید.', style: t(12, c: C.n500, h: 1.6)),
              const Gap(12),
              TgButton(label: 'تلاش دوباره', onPressed: c.boot),
              const Gap(8),
              TgButton(label: 'رفتن به اتصال', variant: BtnVariant.outline, onPressed: () => c.switchTab(BLTab.connect)),
              const Gap(8),
              TgButton(label: 'خروج از حساب', variant: BtnVariant.ghost, onPressed: c.logout),
            ],
          ),
        ),
      );
    }
    return _Centered(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const OrbLoader(),
          const Gap(12),
          Text('در حال دریافت اطلاعات حساب…', style: t(14, c: C.n400)),
          const Gap(6),
          Text('می‌توانید همین حالا از تب «اتصال» وصل شوید', style: t(12, c: C.n500)),
        ],
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 512),
            child: Padding(padding: const EdgeInsets.all(16), child: child),
          ),
        ),
      );
}

class _Main extends StatelessWidget {
  const _Main({required this.c});

  final BLController c;

  @override
  Widget build(BuildContext context) {
    final showShopBar = c.tab == BLTab.shop && c.checkout == null && c.purchaseDraft == null;
    return PopScope(
      canPop: c.tab == BLTab.connect,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (c.tab == BLTab.shop && c.purchaseDraft != null) {
          c.setPurchaseDraft(null);
        } else {
          c.switchTab(BLTab.connect);
        }
      },
      child: Column(
        children: [
          _Header(c: c, showShopBar: showShopBar),
          if (c.auth == AuthPhase.loggedIn) _SyncStatus(c: c),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: _tabBody(context)),
                if (c.busy) const Positioned(top: 4, left: 0, right: 0, child: Center(child: BusyPill())),
              ],
            ),
          ),
          // Keyboard open: give the space to the form, like the mini app in Telegram.
          if (MediaQuery.viewInsetsOf(context).bottom == 0) _BottomNav(c: c),
        ],
      ),
    );
  }

  Widget _tabBody(BuildContext context) {
    // Signed out ("continue without account"): only Connect works.
    if (c.auth == AuthPhase.guest && c.tab != BLTab.connect) return _GuestGate(c: c);
    // Account tabs wait for the first sync (or channel check); Connect never does.
    if (c.tab != BLTab.connect && (c.channelGate != null || c.me == null)) return _AccountGate(c: c);
    return switch (c.tab) {
      BLTab.connect => const ConnectScreen(),
      BLTab.subs => const DashboardScreen(),
      BLTab.shop => const ShopScreen(),
      BLTab.chat => const ChatScreen(),
      BLTab.invite => const InviteScreen(),
      BLTab.profile => const ProfileScreen(),
      BLTab.admin => const AdminScreen(),
    };
  }
}

/// Thin progress line while syncing; amber banner when the last sync failed.
class _SyncStatus extends StatelessWidget {
  const _SyncStatus({required this.c});

  final BLController c;

  @override
  Widget build(BuildContext context) {
    if (c.offline) {
      final when = relativeFa(c.lastSyncedAt);
      return Material(
        color: C.a(C.amber500, 0.12),
        child: InkWell(
          onTap: c.syncing ? null : c.boot,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.cloud_off_rounded, size: 16, color: C.amber200),
                const Gap(8),
                Expanded(
                  child: Text(
                    when.isEmpty ? 'آفلاین — اطلاعات ذخیره‌شده نمایش داده می‌شود' : 'آفلاین — آخرین به‌روزرسانی: $when',
                    style: t(11, c: C.amber200),
                  ),
                ),
                Text(c.syncing ? 'در حال تلاش…' : 'تلاش دوباره', style: t(11, w: 600, c: C.amber200)),
              ],
            ),
          ),
        ),
      );
    }
    if (c.syncing && c.me != null) {
      return LinearProgressIndicator(minHeight: 2, backgroundColor: Colors.transparent, color: C.w(40));
    }
    return const SizedBox.shrink();
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.c, required this.showShopBar});

  final BLController c;
  final bool showShopBar;

  @override
  Widget build(BuildContext context) {
    final balance = c.me?.i('wallet_balance') ?? 0;
    final pro = c.isPro;
    final guest = c.auth == AuthPhase.guest;
    return Container(
      decoration: BoxDecoration(
        color: C.b(50),
        border: Border(bottom: BorderSide(color: C.w(10))),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Wallet chip (guest: sign-in button)
                  Expanded(
                    child: guest
                        ? Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TgButton(
                              label: 'ورود',
                              icon: Icons.login_rounded,
                              expand: false,
                              height: 40,
                              fontSize: 13,
                              onPressed: c.showLogin,
                            ),
                          )
                        : Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => openWalletSheet(context),
                          child: Ink(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: C.b(60),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: pro ? C.w(20) : C.w(15)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(color: C.w(10), borderRadius: BorderRadius.circular(8)),
                                  child: Icon(Icons.account_balance_wallet_outlined, size: 16, color: pro ? C.n200 : C.foreground),
                                ),
                                const Gap(8),
                                Flexible(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        balance < 0 ? 'بدهی کیف‌پول' : (pro ? 'موجودی · Pro' : 'کیف پول'),
                                        style: t(10, c: C.n500),
                                      ),
                                      Text(
                                        balance < 0 ? '${faNum(balance.abs())} تومان' : '${faNum(balance)} تومان',
                                        overflow: TextOverflow.ellipsis,
                                        style: t(13, w: 600, c: balance < 0 ? C.rose300 : null, h: 1.2),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Image.asset(kBrandMark, height: 32, color: C.light ? C.foreground : null),
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (guest) const SizedBox.shrink() else ...[
                        if (!c.isAdmin) ...[
                          ProHeaderEntry(isPro: pro, onTap: () => openProSheet(context)),
                          const Gap(6),
                        ],
                        NotificationBell(count: c.headerNotifCount, onTap: () => openNotificationCenter(context)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (showShopBar)
              Container(
                decoration: BoxDecoration(border: Border(top: BorderSide(color: C.w(8)))),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Segmented<ShopSection>(
                  items: const [
                    (ShopSection.plans, 'آماده'),
                    (ShopSection.custom, 'سفارشی'),
                    (ShopSection.payg, 'مصرفی'),
                    (ShopSection.gift, 'هدیه'),
                  ],
                  value: c.shopSection,
                  onChanged: c.setShopSection,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// bottom-nav-bar.tsx.
class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.c});

  final BLController c;

  @override
  Widget build(BuildContext context) {
    final items = <(BLTab, IconData, String, bool, int)>[
      (BLTab.connect, Icons.power_settings_new_rounded, 'اتصال', false, 0),
      (BLTab.subs, Icons.show_chart_rounded, 'داشبورد', c.pendingOrder != null, 0),
      (BLTab.shop, Icons.storefront_outlined, 'فروشگاه', c.checkout != null || c.purchaseDraft != null, 0),
      (BLTab.chat, Icons.chat_bubble_outline_rounded, 'گفتگو', c.chatUnread > 0, c.chatUnread),
      (BLTab.invite, Icons.card_giftcard_rounded, 'دعوت', false, 0),
      (BLTab.profile, Icons.person_outline_rounded, 'پروفایل', c.me != null && !(c.me!.b('has_birth_date')), 0),
      if (c.isAdmin) (BLTab.admin, Icons.shield_outlined, 'ادمین', c.adminPendingCount > 0, c.adminPendingCount),
    ];
    return Container(
      decoration: BoxDecoration(color: C.b(75), border: Border(top: BorderSide(color: C.w(10)))),
      padding: EdgeInsets.fromLTRB(8, 6, 8, MediaQuery.paddingOf(context).bottom + 7),
      child: Row(
        children: [
          for (final (id, icon, label, badge, count) in items)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => c.switchTab(id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: const Cubic(0.23, 1, 0.32, 1),
                  height: 48,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: id == c.tab ? C.w(12) : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(icon, size: 19, color: id == c.tab ? C.white : C.n500),
                          if (badge)
                            Positioned(
                              top: -4,
                              left: -7,
                              child: count > 0
                                  ? Container(
                                      constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                                      padding: const EdgeInsets.symmetric(horizontal: 2),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(color: C.primary, borderRadius: BorderRadius.circular(999)),
                                      child: Text(faNum(count.clamp(0, 99)), style: t(8, w: 700, c: C.primaryFg)),
                                    )
                                  : Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(color: C.primary, shape: BoxShape.circle),
                                    ),
                            ),
                        ],
                      ),
                      const Gap(2),
                      Text(
                        label,
                        maxLines: 1,
                        style: t(10.5, w: 500, c: id == c.tab ? C.white : C.n500),
                      ),
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

/// Tabs other than Connect while signed out.
class _GuestGate extends StatelessWidget {
  const _GuestGate({required this.c});

  final BLController c;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.lock_outline_rounded, size: 34, color: C.n400),
              const Gap(12),
              Text('برای این بخش وارد حساب شوید', textAlign: TextAlign.center, style: t(16, w: 600)),
              const Gap(6),
              Text(
                'فروشگاه، کانفیگ‌ها، کیف‌پول و پشتیبانی به حساب BlackLines نیاز دارند. بدون حساب فقط می‌توانید از تب «اتصال» استفاده کنید.',
                textAlign: TextAlign.center,
                style: t(13, c: C.n400, h: 1.7),
              ),
              const Gap(16),
              TgButton(label: 'ورود با تلگرام', icon: Icons.send_rounded, busy: c.loggingIn, onPressed: c.startTelegramLogin),
              if (c.loginStatus != null) ...[
                const Gap(10),
                Text(c.loginStatus!, textAlign: TextAlign.center, style: t(12, c: C.n400)),
              ],
              if (c.loginError != null) ...[const Gap(10), Callout(c.loginError!, tone: Tone.red)],
            ],
          ),
        ),
      ),
    );
  }
}
