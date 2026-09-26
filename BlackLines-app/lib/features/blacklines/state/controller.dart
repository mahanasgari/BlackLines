import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hiddify/features/blacklines/core/api.dart';
import 'package:hiddify/features/blacklines/core/demo.dart';
import 'package:hiddify/features/blacklines/core/format.dart';
import 'package:hiddify/features/blacklines/core/json.dart';
import 'package:hiddify/features/blacklines/data/auth_store.dart';
import 'package:hiddify/features/blacklines/ui/kit.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

enum BLTab { connect, subs, shop, chat, invite, profile, admin }

enum ShopSection { plans, custom, payg, gift }

/// [guest]: signed out but using the app for connecting only.
enum AuthPhase { unknown, loggedOut, guest, loggedIn }

/// App.tsx `checkout` state.
class Checkout {
  const Checkout({
    required this.orderId,
    required this.amountLabel,
    required this.amountToman,
    required this.walletUsed,
    required this.payment,
    this.kind = 'plan',
    this.recipientName,
    this.familySize,
  });

  final int orderId;
  final String amountLabel;
  final int amountToman;
  final int walletUsed;
  final J payment;
  final String kind; // plan | wallet | pro
  final String? recipientName;
  final int? familySize;
}

/// purchase-confirm-panel.tsx `PurchaseDraft`.
class PurchaseDraft {
  const PurchaseDraft.plan(J this.plan, {this.familySize = 1, this.giftCard = false})
      : kind = 'plan',
        title = '',
        durationDays = 0,
        trafficGb = 0,
        limitIp = 0,
        unlimited = false,
        chargeLabel = null;

  const PurchaseDraft.custom({
    required this.title,
    required this.durationDays,
    required this.trafficGb,
    required this.limitIp,
    required this.unlimited,
    this.familySize = 1,
    this.chargeLabel,
  })  : kind = 'custom',
        plan = null,
        giftCard = false;

  const PurchaseDraft.payg({required this.title, required this.trafficGb, required this.limitIp, this.chargeLabel})
      : kind = 'payg',
        plan = null,
        durationDays = 0,
        unlimited = false,
        familySize = 1,
        giftCard = false;

  final String kind;
  final J? plan;
  final String title;
  final int durationDays;
  final int trafficGb;
  final int limitIp;
  final bool unlimited;
  final int familySize;
  final bool giftCard;
  final String? chargeLabel;
}

/// Everything App.tsx keeps in React state, plus native-app login.
class BLController extends ChangeNotifier {
  BLController(this._auth) {
    api = BLApi(
      kBLDemo
          ? BLDemoTransport()
          : BLHttpTransport(
              apiBase: const String.fromEnvironment('API_BASE', defaultValue: 'https://shabash.cloudproducts.ir')
                  .replaceAll(RegExp(r'/$'), ''),
              token: _auth.getToken,
            ),
    );
    unawaited(_init());
  }

  final BlackLinesAuthStore _auth;
  late final BLApi api;

  // ---- auth ----
  AuthPhase auth = AuthPhase.unknown;
  bool loggingIn = false;
  String? loginStatus;
  String? loginError;
  Timer? _loginPoll;

  // ---- boot ----
  bool loading = true;
  String? error;
  ({String channel, String inviteUrl, String message})? channelGate;

  // ---- data ----
  J? me;
  List<J> plans = const [];
  List<J> dashItems = const [];
  List<J> dashArchived = const [];
  J dashSummary = const J({'total': 0, 'online': 0, 'offline': 0});
  J? pendingOrder;
  String? pendingRecipient;
  int? pendingFamilySize;
  J? refData;
  J? walletInfo;
  J? proData;
  J? resellerDesk;
  int chatUnread = 0;
  List<J> userUnreadMessages = const [];
  J? trialAccount;

  /// Set when a trial account should be shown in its sheet (consumed by the shell).
  J? pendingTrialSheet;

  // ---- admin ----
  List<J> adminOrders = const [];
  List<J> adminWds = const [];
  List<J> adminPaymentCards = const [];
  List<J> adminUnreadThreads = const [];
  bool adminIncludeTest = false;
  int? openChatThreadUserId;

  // ---- UI ----
  BLTab tab = BLTab.connect;
  ShopSection shopSection = ShopSection.plans;
  String paygMode = 'cloud';
  Object filter = 'all';
  int shopFamilySize = 1;
  Checkout? checkout;
  PurchaseDraft? purchaseDraft;
  bool busy = false;
  bool tabLoading = false;
  bool profileFocusHelp = false;

  bool get isAdmin => me?.b('is_admin') ?? false;
  bool get isPro => (me?.b('is_pro') ?? false) || (proData?.b('is_pro') ?? false);
  int get adminPendingCount => adminOrders.length + adminWds.length;
  J? get walletPending => walletInfo?.objOrNull('pending_deposit');
  int get userNotifCount => chatUnread + (pendingOrder != null ? 1 : 0) + (walletPending != null ? 1 : 0);
  int get headerNotifCount => isAdmin ? adminPendingCount + chatUnread : userNotifCount;

  Timer? _chatPoll;

  void _set(void Function() fn) {
    fn();
    notifyListeners();
  }

  void setBusy(bool v) => _set(() => busy = v);

  void _err(Object e) => notify(persianError(e), ToastStatus.error);

  // =========================================================================
  // Auth
  // =========================================================================

  // ---- device preferences: theme, guest mode, offline cache ----
  SharedPreferences? _prefs;

  /// 'light' / 'dark', or null to follow the phone (theme.tsx default).
  String? themePref;

  /// True when showing cached data because the server was unreachable.
  bool offline = false;

  Future<void> setThemePref(String? value) async {
    themePref = value;
    notifyListeners();
    final p = _prefs ?? await SharedPreferences.getInstance();
    value == null ? await p.remove('bl_theme') : await p.setString('bl_theme', value);
  }

  void _cache(String key, Object? value) {
    try {
      _prefs?.setString('bl_cache_$key', jsonEncode(value));
    } catch (_) {}
  }

  Object? _cached(String key) {
    final raw = _prefs?.getString('bl_cache_$key');
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> _clearCache() async {
    for (final k in _prefs?.getKeys().where((k) => k.startsWith('bl_cache_')).toList() ?? const <String>[]) {
      await _prefs?.remove(k);
    }
  }

  Future<void> _init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      themePref = _prefs!.getString('bl_theme');
    } catch (_) {}
    if (kBLDemo || await _auth.isLoggedIn) {
      auth = AuthPhase.loggedIn;
      notifyListeners();
      await boot();
    } else {
      _set(() {
        auth = (_prefs?.getBool('bl_guest') ?? false) ? AuthPhase.guest : AuthPhase.loggedOut;
        loading = false;
      });
    }
  }

  /// Login screen → "continue without account": only the Connect tab works.
  Future<void> continueAsGuest() async {
    await _prefs?.setBool('bl_guest', true);
    _set(() {
      auth = AuthPhase.guest;
      tab = BLTab.connect;
      loginError = null;
    });
  }

  /// Guest → back to the login screen.
  void showLogin() => _set(() {
        auth = AuthPhase.loggedOut;
        loginError = null;
      });

  Future<void> startTelegramLogin() async {
    _set(() {
      loggingIn = true;
      loginError = null;
      loginStatus = 'در حال ساخت لینک ورود…';
    });
    try {
      final start = await api.loginStart();
      final nonce = start.text('nonce');
      final botUrl = start.text('bot_url');
      if (nonce == null || botUrl == null) throw BLApiError('پاسخ نامعتبر از سرور');
      _set(() => loginStatus = 'در تلگرام «Start» را بزنید، سپس به برنامه برگردید…');
      await launchUrl(Uri.parse(botUrl), mode: LaunchMode.externalApplication);
      final ok = await _pollLogin(nonce);
      if (!ok) {
        _set(() {
          loggingIn = false;
          loginStatus = null;
          loginError = 'مهلت ورود تمام شد — دوباره تلاش کنید';
        });
        return;
      }
      await _prefs?.remove('bl_guest');
      _set(() {
        loggingIn = false;
        loginStatus = null;
        auth = AuthPhase.loggedIn;
        tab = BLTab.connect;
      });
      await boot();
    } catch (e) {
      _set(() {
        loggingIn = false;
        loginStatus = null;
        loginError = persianError(e);
      });
    }
  }

  Future<bool> _pollLogin(String nonce) {
    final done = Completer<bool>();
    var attempts = 0;
    _loginPoll?.cancel();
    _loginPoll = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (++attempts > 90) {
        timer.cancel();
        if (!done.isCompleted) done.complete(false);
        return;
      }
      try {
        final r = await api.loginPoll(nonce);
        final st = r.text('status');
        final token = r.text('access_token');
        if (st == 'ready' && token != null) {
          timer.cancel();
          await _auth.saveSession(accessToken: token, expiresAt: r.text('expires_at'));
          if (!done.isCompleted) done.complete(true);
        } else if (st == 'expired') {
          timer.cancel();
          if (!done.isCompleted) done.complete(false);
        }
      } catch (_) {}
    });
    return done.future;
  }

  void cancelLogin() {
    _loginPoll?.cancel();
    _set(() {
      loggingIn = false;
      loginStatus = null;
    });
  }

  Future<void> logout() async {
    try {
      await api.logout();
    } catch (_) {}
    await _auth.clear();
    await _clearCache();
    _chatPoll?.cancel();
    _set(() {
      auth = AuthPhase.loggedOut;
      me = null;
      offline = false;
      dashItems = const [];
      dashArchived = const [];
      pendingOrder = null;
      walletInfo = null;
      refData = null;
      proData = null;
      resellerDesk = null;
      tab = BLTab.connect;
      checkout = null;
      purchaseDraft = null;
    });
  }

  Future<void> _sessionExpired() async {
    await _auth.clear();
    await _clearCache();
    _set(() {
      auth = AuthPhase.loggedOut;
      loginError = 'نشست منقضی شد — دوباره وارد شوید';
      me = null;
    });
  }

  // =========================================================================
  // Boot (App.tsx boot / recheckChannel)
  // =========================================================================

  Future<void> boot() async {
    _set(() {
      loading = true;
      error = null;
      channelGate = null;
    });
    try {
      final results = await Future.wait([api.me(), api.plans()]).timeout(const Duration(seconds: 20));
      me = results[0] as J;
      plans = results[1] as List<J>;
      offline = false;
      _cache('me', me!.raw);
      _cache('plans', [for (final p in plans) p.raw]);
      final trial = me!.objOrNull('trial_account');
      if (trial != null && trial.b('granted')) {
        trialAccount = trial;
        pendingTrialSheet = trial;
      }
      loading = false;
      notifyListeners();
      _afterBoot();
    } on BLApiError catch (e) {
      if (e.status == 401) return _sessionExpired();
      if (e.code == 'channel_required') {
        channelGate = (
          channel: e.channel ?? 'Blackliness',
          inviteUrl: e.inviteUrl ?? 'https://t.me/Blackliness',
          message: e.message,
        );
      } else if (!_bootFromCache()) {
        error = persianError(e);
      }
      _set(() => loading = false);
    } on TimeoutException {
      if (!_bootFromCache()) error = 'اتصال به سرور طولانی شد — دوباره تلاش کنید';
      _set(() => loading = false);
    } catch (e) {
      if (!_bootFromCache()) error = persianError(e);
      _set(() => loading = false);
    }
  }

  /// offline-cache.ts: a flaky network still shows the last known account.
  bool _bootFromCache() {
    final cachedMe = _cached('me');
    if (cachedMe is! Map) return false;
    me = J.from(cachedMe);
    plans = J.list(_cached('plans'));
    final dash = _cached('dash');
    if (dash is Map) {
      final d = J.from(dash);
      dashItems = d.objs('items');
      dashArchived = d.objs('archived');
      dashSummary = d.objOrNull('summary') ?? dashSummary;
    }
    offline = true;
    error = null;
    return true;
  }

  Future<void> recheckChannel() async {
    setBusy(true);
    try {
      final s = await api.channelStatus();
      if (!s.b('required') || s.b('member')) {
        channelGate = null;
        await boot();
        return;
      }
      _set(() => channelGate = (
            channel: s.text('channel') ?? 'Blackliness',
            inviteUrl: s.text('invite_url') ?? 'https://t.me/Blackliness',
            message: s.text('message') ?? 'هنوز عضو کانال نیستید',
          ));
      notify('هنوز عضو کانال نیستید — اول Join کنید', ToastStatus.error);
    } catch (e) {
      _err(e);
    } finally {
      setBusy(false);
    }
  }

  void _afterBoot() {
    if (isAdmin) {
      unawaited(refreshAdmin().catchError((_) {}));
    } else {
      unawaited(refreshUserNotifs().catchError((_) {}));
      unawaited(refreshProData());
    }
    unawaited(refreshResellerDesk());
    unawaited(refreshDashboard().catchError((_) {}));
    _startChatPoll();
  }

  void _startChatPoll() {
    _chatPoll?.cancel();
    Future<void> poll() async {
      if (me == null || tab == BLTab.chat) return;
      try {
        if (isAdmin) {
          final d = await api.adminChatThreads();
          _set(() => chatUnread = d.i('unread_total'));
        } else {
          final d = await api.chatUnread();
          _set(() => chatUnread = d.i('unread_count'));
        }
      } catch (_) {}
    }

    unawaited(poll());
    _chatPoll = Timer.periodic(const Duration(seconds: 12), (_) => poll());
  }

  // =========================================================================
  // Navigation
  // =========================================================================

  void switchTab(BLTab id) {
    if (id == tab) return;
    haptic();
    if (id != BLTab.profile) profileFocusHelp = false;
    tab = id;
    notifyListeners();
    unawaited(_loadTab(id));
  }

  void openProfile({bool help = false}) {
    profileFocusHelp = help;
    if (tab == BLTab.profile) {
      notifyListeners();
      return;
    }
    switchTab(BLTab.profile);
  }

  void setShopSection(ShopSection s) => _set(() => shopSection = s);
  void setPaygMode(String m) => _set(() => paygMode = m);
  void setFilter(Object f) => _set(() => filter = f);
  void setFamilySize(int n) => _set(() => shopFamilySize = n);
  void setAdminIncludeTest(bool v) {
    _set(() => adminIncludeTest = v);
    unawaited(_loadTab(BLTab.admin));
  }

  void consumeOpenThread() => openChatThreadUserId = null;

  J? takeTrialSheet() {
    final t = pendingTrialSheet;
    pendingTrialSheet = null;
    return t;
  }

  void openChatWith(int userId) {
    openChatThreadUserId = userId;
    switchTab(BLTab.chat);
  }

  Future<void> _loadTab(BLTab id) async {
    if (id != BLTab.subs && id != BLTab.invite && !(id == BLTab.admin && isAdmin)) return;
    _set(() => tabLoading = dashItems.isEmpty && id == BLTab.subs || id != BLTab.subs);
    try {
      if (id == BLTab.subs) {
        await refreshDashboard();
      } else if (id == BLTab.invite) {
        refData = await api.referral();
      } else {
        final r = await Future.wait([
          api.adminPending(includeTest: adminIncludeTest),
          api.adminWithdrawals(includeTest: adminIncludeTest),
        ]);
        adminOrders = r[0];
        adminWds = r[1];
      }
    } catch (e) {
      if (e is BLApiError && e.status == 401) return _sessionExpired();
      _err(e);
    } finally {
      _set(() => tabLoading = false);
    }
  }

  Future<void> reloadCurrentTab() => _loadTab(tab);

  List<J> get filteredPlans {
    if (filter == 'all') return plans;
    return plans.where((p) {
      final d = p.i('duration_days');
      return switch (filter) {
        30 => d <= 31,
        90 => d > 31 && d <= 93,
        180 => d > 93 && d <= 186,
        _ => d > 186,
      };
    }).toList();
  }

  // =========================================================================
  // Refreshers
  // =========================================================================

  Future<void> refreshDashboard() async {
    final r = await Future.wait([api.subscriptions(), api.dashboard()]);
    final subs = r[0];
    final dash = r[1];
    pendingOrder = subs.objOrNull('pending');
    dashItems = dash.objs('items');
    dashArchived = dash.objs('archived');
    dashSummary = dash.objOrNull('summary') ?? const J({'total': 0, 'online': 0, 'offline': 0});
    offline = false;
    _cache('dash', dash.raw);
    notifyListeners();
  }

  Future<void> refreshAdmin() async {
    if (!isAdmin) return;
    final r = await Future.wait([
      api.adminPending(includeTest: adminIncludeTest),
      api.adminWithdrawals(includeTest: adminIncludeTest),
      api.adminPaymentCards(),
    ]);
    _set(() {
      adminOrders = r[0];
      adminWds = r[1];
      adminPaymentCards = r[2];
    });
  }

  Future<void> refreshUserNotifs() async {
    if (isAdmin) return;
    final r = await Future.wait([api.subscriptions(), api.wallet(), api.chatMessages()]);
    _set(() {
      pendingOrder = r[0].objOrNull('pending');
      walletInfo = r[1];
      chatUnread = r[2].i('unread_count');
      userUnreadMessages =
          r[2].objs('messages').where((m) => m.s('sender') == 'admin' && m['read_at'] == null).toList();
    });
  }

  Future<void> refreshResellerDesk() async {
    try {
      final d = await api.resellerDesk();
      _set(() => resellerDesk = d);
    } catch (_) {}
  }

  Future<J?> refreshProData() async {
    try {
      final d = await api.proInfo();
      _set(() {
        proData = d;
        me = me?.merge({'is_pro': d.b('is_pro'), 'pro_until': d['pro_until']});
      });
      return d;
    } catch (_) {
      return null;
    }
  }

  Future<void> openNotifCenterData() async {
    try {
      if (isAdmin) {
        final r = await Future.wait([refreshAdmin(), api.adminChatThreads()]);
        final chat = r[1] as J;
        _set(() {
          chatUnread = chat.i('unread_total');
          adminUnreadThreads = chat.objs('threads').where((t) => t.i('unread_count') > 0).toList();
        });
      } else {
        await refreshUserNotifs();
      }
    } catch (e) {
      _err(e);
    }
  }

  Future<void> handleOrderAction() async {
    if (isAdmin) {
      await refreshAdmin();
    } else {
      await refreshUserNotifs();
    }
    try {
      await refreshDashboard();
    } catch (_) {}
  }

  Future<void> refreshMe() async {
    try {
      final m = await api.me();
      _set(() => me = m);
    } catch (_) {}
  }

  void setChatUnread(int n) {
    if (n == chatUnread) return;
    _set(() => chatUnread = n);
  }

  void setWalletBalance(int balance) => _set(() => me = me?.merge({'wallet_balance': balance}));

  // =========================================================================
  // Shop flows
  // =========================================================================

  Future<void> claimTrial() async {
    haptic('medium');
    setBusy(true);
    try {
      final trial = await api.claimTrial();
      trialAccount = trial;
      pendingTrialSheet = trial;
      final offer = me?.objOrNull('trial_offer');
      if (offer != null) me = me!.merge({'trial_offer': offer.merge({'available': false}).raw});
      notify('کانفیگ تست فعال شد', ToastStatus.success);
      notifyListeners();
      await refreshDashboard();
    } catch (e) {
      _err(e);
    } finally {
      setBusy(false);
    }
  }

  /// Returns true when the Pro sheet should close (checkout opened).
  Future<bool> buyPro() async {
    haptic('medium');
    setBusy(true);
    try {
      final order = await api.proOrder();
      if (order.intOrNull('wallet_balance') != null) {
        setWalletBalance(order.i('wallet_balance'));
      } else {
        await refreshMe();
      }
      if (order.b('auto_approved')) {
        notify('اشتراک Pro فعال شد', ToastStatus.success);
        checkout = null;
        unawaited(refreshProData());
        return false;
      }
      if (!order.b('needs_receipt')) {
        await api.confirmWallet(order.i('id'));
        notify(order.b('resumed') ? 'سفارش Pro قبلی ثبت شد' : 'سفارش Pro ثبت شد — منتظر تایید', ToastStatus.success);
        checkout = null;
        return false;
      }
      if (order.b('resumed')) notify('سفارش Pro ناتمام قبلی باز شد');
      checkout = _checkoutFrom(order, kind: 'pro');
      tab = BLTab.shop;
      unawaited(refreshProData());
      return true;
    } catch (e) {
      _err(e);
      return false;
    } finally {
      setBusy(false);
    }
  }

  void startPlanPurchase(J plan) {
    haptic('medium');
    _set(() => purchaseDraft = PurchaseDraft.plan(plan, familySize: shopFamilySize));
  }

  void startGiftPurchase(J plan) {
    haptic('medium');
    _set(() => purchaseDraft = PurchaseDraft.plan(plan, giftCard: true));
  }

  void setPurchaseDraft(PurchaseDraft? d) => _set(() => purchaseDraft = d);

  Future<void> confirmPurchase({
    String? promoCode,
    String? configLabel,
    required int familySize,
    Map<String, String?> customer = const {},
    String? recipientName,
  }) async {
    final draft = purchaseDraft;
    if (draft == null) return;
    setBusy(true);
    var seats = familySize;
    try {
      late J order;
      if (draft.kind == 'plan') {
        order = await api.createOrder(
          draft.plan!.i('id'),
          promoCode: promoCode,
          familySize: familySize,
          configLabel: configLabel,
          giftCard: draft.giftCard,
          customer: customer,
        );
        shopFamilySize = 1;
      } else if (draft.kind == 'custom') {
        order = await api.customOrder({
          'duration_days': draft.durationDays,
          'traffic_gb': draft.trafficGb,
          'limit_ip': draft.limitIp,
          'unlimited': draft.unlimited,
          'promo_code': promoCode,
          'family_size': familySize,
          'config_label': configLabel,
          ...customer,
        });
      } else {
        order = await api.paygOrder({
          'traffic_gb': draft.trafficGb,
          'limit_ip': draft.limitIp,
          'config_label': configLabel,
          ...customer,
        });
        seats = 1;
      }
      purchaseDraft = null;
      await completePlanOrder(order, recipientName: recipientName, familySize: seats);
    } catch (e) {
      _err(e);
    } finally {
      setBusy(false);
    }
  }

  Checkout _checkoutFrom(J order, {String kind = 'plan', String? recipientName, int? familySize}) => Checkout(
        orderId: order.i('id'),
        amountLabel: order.s('amount_label'),
        amountToman: order.i('amount_toman'),
        walletUsed: order.i('wallet_used'),
        payment: order.obj('payment'),
        kind: kind,
        recipientName: recipientName,
        familySize: familySize,
      );

  /// App.tsx `completePlanOrder`.
  Future<void> completePlanOrder(J order, {String? recipientName, int? familySize}) async {
    if (order.intOrNull('wallet_balance') != null) {
      setWalletBalance(order.i('wallet_balance'));
    } else {
      await refreshMe();
    }
    final seats = familySize ?? order.intOrNull('family_size') ?? 1;
    final forWho = recipientName != null ? ' برای $recipientName' : '';
    final familyNote = seats > 1 ? ' · ${faNum(seats)} کانفیگ خانواده' : '';
    if (order.b('auto_approved')) {
      final gift = order.text('gift_code');
      if (gift != null) {
        notify('کارت هدیه آماده شد: $gift', ToastStatus.success);
        checkout = null;
        pendingOrder = null;
        shopSection = ShopSection.gift;
        tab = BLTab.shop;
        notifyListeners();
        return;
      }
      notify(
        order.b('renew') ? 'تمدید$forWho با کیف‌پول انجام شد' : 'خرید$forWho با کیف‌پول انجام شد$familyNote. کانفیگ فعال است.',
        ToastStatus.success,
      );
      checkout = null;
      pendingOrder = null;
      await refreshDashboard();
      if (!order.b('renew')) switchTab(BLTab.subs);
    } else if (!order.b('needs_receipt')) {
      await api.confirmWallet(order.i('id'));
      notify(
        order.b('resumed')
            ? 'سفارش قبلی$forWho ثبت شد — منتظر تایید'
            : 'سفارش$forWho ثبت شد$familyNote. بعد از تایید، لینک‌ها را از داشبورد بفرست.',
        ToastStatus.success,
      );
      checkout = null;
      pendingOrder = J({
        'id': order.i('id'),
        'plan_title': order.text('plan_title') ?? 'خرید VPN',
        'amount_toman': order.i('amount_toman'),
        'amount_label': order.s('amount_label'),
        'wallet_used': order.i('wallet_used'),
        'has_receipt': false,
        'payment': order.obj('payment').raw,
      });
      pendingRecipient = recipientName;
      pendingFamilySize = seats > 1 ? seats : null;
      notifyListeners();
    } else {
      if (order.b('resumed')) notify('سفارش ناتمام قبلی باز شد');
      checkout = _checkoutFrom(order, recipientName: recipientName, familySize: seats > 1 ? seats : null);
      notifyListeners();
    }
  }

  /// Renew/checkout coming from the subscription detail sheet.
  Future<void> handleDetailCheckout(J order) async {
    setBusy(true);
    try {
      await completePlanOrder(
        order.merge({'plan_title': order.text('plan_title') ?? (order.b('renew') ? 'تمدید اشتراک' : 'خرید VPN')}),
      );
      if (order.b('needs_receipt')) switchTab(BLTab.shop);
    } catch (e) {
      _err(e);
    } finally {
      setBusy(false);
    }
  }

  void resumePendingCheckout() {
    final p = pendingOrder;
    if (p == null) return;
    _set(() {
      checkout = Checkout(
        orderId: p.i('id'),
        amountLabel: p.s('amount_label'),
        amountToman: p.i('amount_toman'),
        walletUsed: p.i('wallet_used'),
        payment: p.obj('payment'),
        kind: p.b('is_wallet_topup') ? 'wallet' : 'plan',
        recipientName: pendingRecipient,
        familySize: pendingFamilySize,
      );
      tab = BLTab.shop;
    });
  }

  Future<void> cancelOrder(int orderId, {bool isCheckout = false}) async {
    setBusy(true);
    try {
      final res = await api.cancelOrder(orderId);
      if (isCheckout) checkout = null;
      if (pendingOrder?.i('id') == orderId) pendingOrder = null;
      setWalletBalance(res.i('wallet_balance'));
      notify('سفارش لغو شد', ToastStatus.success);
    } catch (e) {
      _err(e);
    } finally {
      setBusy(false);
    }
  }

  Future<void> uploadReceipt(String path, String name) async {
    final c = checkout;
    if (c == null) return;
    setBusy(true);
    try {
      await api.uploadReceipt(c.orderId, path, name);
      notify('رسید ارسال شد — منتظر تایید', ToastStatus.success);
      checkout = null;
      await refreshMe();
      unawaited(refreshDashboard().catchError((_) {}));
    } catch (e) {
      _err(e);
    } finally {
      setBusy(false);
    }
  }

  // =========================================================================
  // Dashboard actions
  // =========================================================================

  Future<void> renameConfig(int subId, String label) async {
    try {
      final res = await api.setLabel(subId, label);
      dashItems = [for (final it in dashItems) it.i('id') == subId ? it.merge({'label': res['label']}) : it];
      dashArchived = [for (final it in dashArchived) it.i('id') == subId ? it.merge({'label': res['label']}) : it];
      haptic();
      notify('نام کانفیگ ذخیره شد', ToastStatus.success);
      notifyListeners();
    } catch (e) {
      _err(e);
      rethrow;
    }
  }

  void patchDashItem(int subId, Map<String, dynamic> patch) {
    dashItems = [for (final it in dashItems) it.i('id') == subId ? it.merge(patch) : it];
    notifyListeners();
  }

  Future<void> rotateLink(int subId, {void Function(String url)? onUrl}) async {
    setBusy(true);
    try {
      final res = await api.rotateSubscriptionLink(subId);
      notify('لینک جدید ساخته شد. لینک قبلی دیگر کار نمی‌کند.', ToastStatus.success);
      await refreshDashboard();
      final url = res.text('subscription_url');
      if (url != null) onUrl?.call(url);
    } catch (e) {
      _err(e);
    } finally {
      setBusy(false);
    }
  }

  Future<void> hideExpired(int subId) async {
    setBusy(true);
    try {
      await api.hideSubscription(subId);
      notify('از لیست کانفیگ‌ها حذف شد — در آرشیو می‌ماند', ToastStatus.success);
      await refreshDashboard();
    } catch (e) {
      _err(e);
    } finally {
      setBusy(false);
    }
  }

  Future<void> restoreArchived(int subId) async {
    setBusy(true);
    try {
      await api.unhideSubscription(subId);
      notify('به لیست کانفیگ‌ها برگشت', ToastStatus.success);
      await refreshDashboard();
    } catch (e) {
      _err(e);
    } finally {
      setBusy(false);
    }
  }

  Future<void> markShared(int subId) async {
    try {
      await api.markLinkShared(subId);
      await refreshResellerDesk();
    } catch (_) {}
  }

  // =========================================================================
  // Wallet
  // =========================================================================

  Future<void> loadWallet() async {
    try {
      final info = await api.wallet();
      walletInfo = info;
      me = me?.merge({'wallet_balance': info.i('balance')});
      notifyListeners();
    } catch (e) {
      if (walletInfo == null) _err(e);
    }
  }

  /// Returns true when a checkout opened (caller closes the wallet sheet).
  Future<bool> startDeposit(int amount) async {
    setBusy(true);
    try {
      final order = await api.walletDeposit(amount);
      checkout = _checkoutFrom(order.merge({'wallet_used': 0}), kind: 'wallet');
      tab = BLTab.shop;
      if (order.intOrNull('wallet_balance') != null) me = me?.merge({'wallet_balance': order.i('wallet_balance')});
      notify(order.b('resumed') ? 'سفارش شارژ قبلی باز شد' : 'سفارش شارژ ثبت شد — رسید را بفرستید');
      notifyListeners();
      return true;
    } catch (e) {
      _err(e);
      return false;
    } finally {
      setBusy(false);
    }
  }

  Future<bool> walletWithdraw(String card, int amount) async {
    final withdrawable = walletInfo?.intOrNull('withdrawable') ?? walletInfo?.intOrNull('balance') ?? me?.i('wallet_balance') ?? 0;
    final minW = walletInfo?.intOrNull('min_withdraw') ?? 100000;
    final digits = digitsOnly(card);
    if (digits.length < 16) {
      notify('شماره کارت باید ۱۶ رقم باشد', ToastStatus.error);
      return false;
    }
    if (amount < minW) {
      notify('حداقل برداشت ${walletInfo?.text('min_withdraw_label') ?? priceText(minW)} است', ToastStatus.error);
      return false;
    }
    if (amount > withdrawable) {
      notify('این مبلغ قابل برداشت نیست', ToastStatus.error);
      return false;
    }
    setBusy(true);
    try {
      await api.withdraw(digits, amount);
      notify('درخواست برداشت ثبت شد — پس از بررسی واریز می‌شود', ToastStatus.success);
      await loadWallet();
      await refreshMe();
      return true;
    } catch (e) {
      _err(e);
      return false;
    } finally {
      setBusy(false);
    }
  }

  Future<bool> referralWithdraw(String card) async {
    setBusy(true);
    try {
      await api.withdraw(card);
      notify('درخواست برداشت ثبت شد', ToastStatus.success);
      refData = await api.referral();
      await refreshMe();
      return true;
    } catch (e) {
      _err(e);
      return false;
    } finally {
      setBusy(false);
    }
  }

  // =========================================================================
  // Admin queue actions (used by admin tab + notification center)
  // =========================================================================

  Future<void> adminApprove(int id) async {
    setBusy(true);
    try {
      await api.adminApprove(id);
      adminOrders = await api.adminPending(includeTest: adminIncludeTest);
      notify('تایید شد', ToastStatus.success);
    } catch (e) {
      _err(e);
      rethrow;
    } finally {
      setBusy(false);
    }
  }

  Future<void> adminReject(int id) async {
    setBusy(true);
    try {
      await api.adminReject(id);
      adminOrders = await api.adminPending(includeTest: adminIncludeTest);
      notify('رد شد');
    } catch (e) {
      _err(e);
      rethrow;
    } finally {
      setBusy(false);
    }
  }

  Future<void> adminPayWithdrawal(int id, {required bool pay}) async {
    setBusy(true);
    try {
      pay ? await api.adminPayWd(id) : await api.adminRejectWd(id);
      adminWds = await api.adminWithdrawals(includeTest: adminIncludeTest);
      notify(pay ? 'پرداخت شد' : 'رد شد', pay ? ToastStatus.success : ToastStatus.info);
    } catch (e) {
      _err(e);
    } finally {
      setBusy(false);
    }
  }

  /// Generic busy + toast wrapper for one-off admin actions.
  Future<T?> run<T>(Future<T> Function() action, {String? success}) async {
    setBusy(true);
    try {
      final r = await action();
      if (success != null) notify(success, ToastStatus.success);
      return r;
    } catch (e) {
      _err(e);
      return null;
    } finally {
      setBusy(false);
    }
  }

  @override
  void dispose() {
    _loginPoll?.cancel();
    _chatPoll?.cancel();
    super.dispose();
  }
}

final blControllerProvider = ChangeNotifierProvider<BLController>((ref) => BLController(BlackLinesAuthStore()));
