import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hiddify/features/blacklines/core/json.dart';

/// Mirrors `ApiError` in miniapp/src/api.ts.
class BLApiError implements Exception {
  BLApiError(this.message, {this.status = 0, this.code, this.inviteUrl, this.channel});

  final String message;
  final int status;
  final String? code;
  final String? inviteUrl;
  final String? channel;

  @override
  String toString() => persianError(message);
}

/// App.tsx `persianError`.
String persianError(Object e) {
  final msg = e is BLApiError ? e.message : e.toString();
  const map = {
    'Telegram auth required': 'لطفاً دوباره وارد حساب شوید',
    'Invalid or expired session': 'نشست منقضی شد — دوباره وارد شوید',
    'plan not found': 'پلن پیدا نشد',
    'order not found': 'سفارش پیدا نشد',
    'request failed': 'خطا در ارتباط با سرور',
    'Bad Request': 'ارسال رسید به سرور نرسید. فیلترشکن را خاموش کنید و دوباره بفرستید.',
    'cannot withdraw': 'برداشت ممکن نیست — موجودی یا کارت نامعتبر است، یا برداشت قبلی در انتظار است',
    'invalid card': 'شماره کارت نامعتبر است',
  };
  return map[msg] ?? msg;
}

/// Carries requests to the shop API (live HTTP, or canned demo data).
abstract interface class BLTransport {
  Future<dynamic> send(String method, String path, {Object? body});
  Future<Uint8List> blob(String path);
}

class BLHttpTransport implements BLTransport {
  BLHttpTransport({required this.apiBase, required this.token, Dio? dio}) : _dio = dio ?? Dio();

  final String apiBase;
  final Future<String?> Function() token;
  final Dio _dio;

  Future<Options> _opts({ResponseType? type, Duration? timeout}) async {
    final t = await token();
    return Options(
      headers: {
        'Accept': 'application/json',
        if (t != null && t.isNotEmpty) 'Authorization': 'Bearer $t',
      },
      responseType: type,
      sendTimeout: timeout,
      receiveTimeout: timeout ?? const Duration(seconds: 30),
      validateStatus: (_) => true,
    );
  }

  @override
  Future<dynamic> send(String method, String path, {Object? body}) async {
    final isUpload = body is FormData;
    final opts = await _opts(timeout: isUpload ? const Duration(seconds: 45) : null);
    opts.method = method;
    late Response<dynamic> res;
    final sw = Stopwatch()..start();
    try {
      res = await _dio.request<dynamic>('$apiBase/shop/api$path', data: body, options: opts);
      if (kDebugMode) debugPrint('[BLApi] $method $path -> ${res.statusCode} in ${sw.elapsedMilliseconds}ms');
    } on DioException catch (e) {
      if (kDebugMode) debugPrint('[BLApi] $method $path -> ${e.type.name} after ${sw.elapsedMilliseconds}ms');
      if (e.type == DioExceptionType.sendTimeout || e.type == DioExceptionType.receiveTimeout) {
        throw BLApiError(
          isUpload ? 'آپلود طولانی شد — اگر فیلترشکن روشن است خاموش کنید و دوباره بفرستید' : 'اتصال به سرور طولانی شد — دوباره تلاش کنید',
        );
      }
      throw BLApiError('خطا در ارتباط با سرور');
    }
    final code = res.statusCode ?? 0;
    if (code >= 200 && code < 300) return res.data;
    throw _error(code, res.data, isUpload: isUpload);
  }

  @override
  Future<Uint8List> blob(String path) async {
    final opts = await _opts(type: ResponseType.bytes);
    final res = await _dio.get<List<int>>('$apiBase/shop/api$path', options: opts);
    final code = res.statusCode ?? 0;
    if (code < 200 || code >= 300) throw BLApiError('request failed', status: code);
    return Uint8List.fromList(res.data ?? const []);
  }

  BLApiError _error(int status, Object? data, {bool isUpload = false}) {
    var detail = status == 400 && isUpload
        ? 'ارسال رسید به سرور نرسید. فیلترشکن را خاموش کنید و همان عکس را دوباره بفرستید.'
        : 'request failed';
    String? code;
    String? inviteUrl;
    String? channel;
    final d = data is Map ? data['detail'] : null;
    if (d is String) {
      detail = d;
    } else if (d is List) {
      final msgs = d.map((e) => e is Map ? e['msg'] : null).whereType<String>().join(' · ');
      if (msgs.isNotEmpty) detail = msgs;
    } else if (d is Map) {
      code = d['code']?.toString();
      inviteUrl = d['invite_url']?.toString();
      channel = d['channel']?.toString();
      detail = (d['message'] ?? d['code'] ?? d).toString();
    }
    return BLApiError(detail, status: status, code: code, inviteUrl: inviteUrl, channel: channel);
  }
}

/// Every call from miniapp/src/api.ts, same paths and bodies.
class BLApi {
  BLApi(this._t);

  final BLTransport _t;

  Future<J> _get(String p) async => J.from(await _t.send('GET', p));
  Future<List<J>> _getList(String p) async => J.list(await _t.send('GET', p));
  Future<J> _post(String p, [Map<String, dynamic>? body]) async => J.from(await _t.send('POST', p, body: body ?? const {}));
  static String _q(Object? v) => Uri.encodeQueryComponent('${v ?? ''}');
  static Map<String, dynamic> _clean(Map<String, dynamic> m) =>
      Map.fromEntries(m.entries.where((e) => e.value != null && e.value != ''));

  // ---- auth (native app) ----
  Future<J> loginStart() => _post('/auth/login/start');
  Future<J> loginPoll(String nonce) => _get('/auth/poll/$nonce');
  Future<void> logout() => _post('/auth/logout');

  // ---- me / profile ----
  Future<J> me() => _get('/me');
  Future<J> channelStatus() => _get('/channel');
  Future<J> profile() => _get('/profile');
  Future<Uint8List> profilePhoto() => _t.blob('/profile/photo');
  Future<J> saveBirthDate(String birthDate) => _post('/profile/birth-date', {'birth_date': birthDate});
  Future<J> saveProfileContact({String? email, String? phone}) =>
      _post('/profile/contact', _clean({'email': email, 'phone': phone}));
  Future<J> myActivity({int limit = 40, int offset = 0}) => _get('/activity?limit=$limit&offset=$offset');

  // ---- shop ----
  Future<List<J>> plans() => _getList('/plans');
  Future<J> claimTrial() => _post('/trial/claim');
  Future<J> proInfo() => _get('/pro');
  Future<J> proOrder() => _post('/pro/order');
  Future<J> customOptions() => _get('/custom/options');
  Future<J> customQuote(Map<String, dynamic> body) => _post('/custom/quote', _clean(body));
  Future<J> customOrder(Map<String, dynamic> body) => _post('/custom/order', _clean(body));
  Future<J> paygStatus() => _get('/payg/status');
  Future<J> paygActivate() => _post('/payg/activate');
  Future<J> paygSetEnabled(bool enabled) => _post('/payg/set-enabled', {'enabled': enabled});
  Future<J> paygOptions() => _get('/payg/options');
  Future<J> paygQuote(Map<String, dynamic> body) => _post('/payg/quote', _clean(body));
  Future<J> paygOrder(Map<String, dynamic> body) => _post('/payg/order', _clean(body));
  Future<J> createOrder(
    int planId, {
    String? promoCode,
    int familySize = 1,
    String? configLabel,
    bool giftCard = false,
    Map<String, String?> customer = const {},
  }) =>
      _post(
        '/orders',
        _clean({
          'plan_id': planId,
          'promo_code': promoCode,
          'family_size': familySize,
          'config_label': configLabel,
          'gift_card': giftCard ? true : null,
          ...customer,
        }),
      );
  Future<J> growthOptions() => _get('/growth/options');
  Future<J> validatePromo(Map<String, dynamic> body) => _post('/promo/validate', _clean(body));
  Future<J> cancelOrder(int orderId) => _post('/orders/$orderId/cancel');
  Future<J> uploadReceipt(int orderId, String filePath, String fileName) async => J.from(
        await _t.send(
          'POST',
          '/orders/$orderId/receipt',
          body: FormData.fromMap({'file': await MultipartFile.fromFile(filePath, filename: fileName)}),
        ),
      );
  Future<Uint8List> orderReceipt(int orderId) => _t.blob('/orders/$orderId/receipt');
  Future<J> confirmWallet(int orderId) => _post('/orders/$orderId/confirm-wallet');
  Future<J> orderHistory({String? status, int? limit, int? offset}) => _get(
        '/orders/history?${_clean({'status': status, 'limit': limit, 'offset': offset}).entries.map((e) => '${e.key}=${_q(e.value)}').join('&')}',
      );
  Future<J> giftCards() => _get('/gift-cards');
  Future<J> redeemGiftCard(String code) => _post('/gift-cards/redeem', {'code': code});

  // ---- subscriptions / dashboard ----
  Future<J> subscriptions() => _get('/subscriptions');
  Future<J> dashboard() => _get('/dashboard');
  Future<J> setLabel(int subId, String label) => _post('/subscriptions/$subId/label', {'label': label});
  Future<J> setCustomer(int subId, Map<String, String?> body) => _post('/subscriptions/$subId/customer', body);
  Future<J> links(int subId) => _get('/subscriptions/$subId/links');
  Future<J> subscriptionDetail(int subId) => _get('/subscriptions/$subId/detail');
  Future<J> setAutoRenew(int subId, bool enabled) => _post('/subscriptions/$subId/auto-renew', {'enabled': enabled});
  Future<J> setIpNickname(int subId, String ip, String nickname) =>
      _post('/subscriptions/$subId/ip-nickname', {'ip': ip, 'nickname': nickname});
  Future<J> diagnoseSubscription(int subId) => _post('/subscriptions/$subId/diagnose');
  Future<J> renewSubscription(int subId, int planId) => _post('/subscriptions/$subId/renew', {'plan_id': planId});
  Future<J> revokeSubscription(int subId) => _post('/subscriptions/$subId/revoke');
  Future<J> rotateSubscriptionLink(int subId) => _post('/subscriptions/$subId/rotate-link');
  Future<J> lookupTransferTarget(String q) => _get('/transfer/lookup?q=${_q(q.trim())}');
  Future<J> transferSubscription(int subId, String target) =>
      _post('/subscriptions/$subId/transfer', {'target': target, 'notify': true});
  Future<J> hideSubscription(int subId) => _post('/subscriptions/$subId/hide');
  Future<J> unhideSubscription(int subId) => _post('/subscriptions/$subId/unhide');
  Future<J> markLinkShared(int subId, {bool shared = true}) =>
      _post('/subscriptions/$subId/link-shared', {'shared': shared});
  Future<J> resellerDesk() => _get('/reseller-desk');

  // ---- family / parental ----
  Future<J> parentalOptions() => _get('/parental/options');
  Future<J> familyChildActivity(int parentSubId, int childId, {int limit = 80}) =>
      _get('/subscriptions/$parentSubId/family/$childId/activity?limit=$limit');
  Future<J> restrictFamilyChild(
    int parentSubId,
    int childId,
    List<String> categories, {
    Map<String, dynamic>? schedule,
    Map<String, dynamic>? vpnSchedule,
  }) =>
      _post('/subscriptions/$parentSubId/family/$childId/restrict', {
        'categories': categories,
        'schedule': schedule,
        'vpn_schedule': vpnSchedule,
      });
  Future<J> pauseFamilyChild(int parentSubId, int childId, {int hours = 24}) =>
      _post('/subscriptions/$parentSubId/family/$childId/pause', {'hours': hours});
  Future<J> resumeFamilyChild(int parentSubId, int childId) =>
      _post('/subscriptions/$parentSubId/family/$childId/resume');

  // ---- referral / wallet ----
  Future<J> referral() => _get('/referral');
  Future<J> withdraw(String cardNumber, [int? amount]) =>
      _post('/withdraw', _clean({'card_number': cardNumber, 'amount': amount}));
  Future<J> wallet() => _get('/wallet');
  Future<J> walletDeposit(int amountToman) => _post('/wallet/deposit', {'amount_toman': amountToman});
  Future<J> walletTransfer(String target, int amountToman) =>
      _post('/wallet/transfer', {'target': target, 'amount_toman': amountToman});

  // ---- chat ----
  Future<J> chatMessages({int afterId = 0, bool markRead = false}) =>
      _get('/chat/messages?after_id=$afterId${markRead ? '&mark_read=1' : ''}');
  Future<J> chatMarkRead() => _post('/chat/read');
  Future<J> chatSend(String body, [List<Map<String, dynamic>> attachments = const []]) =>
      _post('/chat/messages', {'body': body, 'attachments': attachments});
  Future<J> chatUnread() => _get('/chat/unread');
  Future<J> chatOrders() => _get('/chat/orders');

  // ---- admin ----
  Future<J> adminBirthdayGift() => _get('/admin/birthday-gift');
  Future<J> adminSetBirthdayGift({required bool enabled, required int amountToman}) =>
      _post('/admin/birthday-gift', {'enabled': enabled, 'amount_toman': amountToman});
  Future<J> adminTrialSettings() => _get('/admin/trial-settings');
  Future<J> adminSetTrialSettings(Map<String, dynamic> body) => _post('/admin/trial-settings', body);
  Future<J> adminCustomSettings() => _get('/admin/custom-settings');
  Future<J> adminSetCustomSettings(Map<String, dynamic> body) => _post('/admin/custom-settings', body);
  Future<J> adminPaygSettings() => _get('/admin/payg-settings');
  Future<J> adminSetPaygSettings(Map<String, dynamic> body) => _post('/admin/payg-settings', body);
  Future<J> adminGrantTrial(Map<String, dynamic> body) => _post('/admin/trial-grant', _clean(body));
  Future<J> adminUsers({String q = '', bool includeTest = false, String slice = '', int days = 0}) =>
      _get('/admin/users?q=${_q(q)}&include_test=$includeTest&slice=${_q(slice)}&days=$days');
  Future<J> adminAnalytics({int days = 30, bool includeTest = false}) =>
      _get('/admin/analytics?days=$days&include_test=$includeTest');
  Future<J> adminExpiring({int days = 3, bool includeTest = false}) =>
      _get('/admin/expiring?days=$days&include_test=$includeTest');
  Future<J> adminRemindExpiry(int subId) => _post('/admin/subscriptions/$subId/remind-expiry');
  Future<J> adminSetUserTest(int userId, bool isTest) => _post('/admin/users/$userId/test-flag', {'is_test': isTest});
  Future<J> adminServers() => _get('/admin/servers');
  Future<J> adminAddServer(Map<String, dynamic> body) => _post('/admin/servers', body);
  Future<J> adminSetServerEnabled(int id, bool enabled) => _post('/admin/servers/$id/enabled', {'enabled': enabled});
  Future<J> adminSetServerVisibility(int id, {bool? enabled, Map<String, bool>? configs}) =>
      _post('/admin/servers/$id/visibility', _clean({'enabled': enabled, 'configs': configs}));
  Future<J> adminSyncServer(int id) => _post('/admin/servers/$id/sync');
  Future<J> adminDeleteServer(int id) => _post('/admin/servers/$id/delete');
  Future<J> adminUserDetail(int userId) => _get('/admin/users/$userId');
  Future<J> adminSetUserRole(int userId, String role) => _post('/admin/users/$userId/role', {'role': role});
  Future<J> adminAdjustWallet(int userId, int amountToman, [String note = '']) =>
      _post('/admin/users/$userId/wallet', {'amount_toman': amountToman, 'note': note});
  Future<J> adminSetWalletCredit(int userId, int creditLimitToman) =>
      _post('/admin/users/$userId/wallet-credit', {'credit_limit_toman': creditLimitToman});
  Future<J> adminConvertWalletToCredit(int userId, int originalTopupToman) =>
      _post('/admin/users/$userId/wallet-convert-credit', {'original_topup_toman': originalTopupToman});
  Future<J> adminSetSubEnabled(int userId, int subId, bool enabled) =>
      _post('/admin/users/$userId/subscriptions/$subId/enabled', {'enabled': enabled});
  Future<J> adminGiftPlans() => _get('/admin/gift-plans');
  Future<J> adminGrantPro(int userId, [int? days]) => _post('/admin/users/$userId/pro', _clean({'days': days}));
  Future<J> adminGiftSubscription(int userId, int planId) =>
      _post('/admin/users/$userId/subscriptions', {'plan_id': planId});
  Future<J> adminDeleteSubscription(int userId, int subId) =>
      _post('/admin/users/$userId/subscriptions/$subId/delete');
  Future<J> adminDiscountSettings() => _get('/admin/discount-settings');
  Future<J> adminSetDiscountSettings(Map<String, dynamic> body) => _post('/admin/discount-settings', body);
  Future<J> adminPromoCodes() => _get('/admin/promo-codes');
  Future<J> adminCreatePromo(Map<String, dynamic> body) => _post('/admin/promo-codes', _clean(body));
  Future<J> adminSetPromoEnabled(int id, bool enabled) => _post('/admin/promo-codes/$id/enabled', {'enabled': enabled});
  Future<J> adminFamilySettings() => _get('/admin/family-settings');
  Future<J> adminSetFamilySettings(Map<String, dynamic> body) => _post('/admin/family-settings', body);
  Future<J> adminParentalSettings() => _get('/admin/parental-settings');
  Future<J> adminSetParentalSettings({required bool enabled, required List<String> customDomains}) =>
      _post('/admin/parental-settings', {'enabled': enabled, 'custom_domains': customDomains});
  Future<J> adminBulkGift(Map<String, dynamic> body) => _post('/admin/bulk-gift', _clean(body));
  Future<J> adminTransferSubscription(int subId, String target, {bool notify = true}) =>
      _post('/admin/subscriptions/$subId/transfer', {'target': target, 'notify': notify});
  Future<J> adminAuditLog({
    int limit = 80,
    int offset = 0,
    String q = '',
    String actorKind = '',
    String category = '',
    bool includeTest = false,
  }) =>
      _get(
        '/admin/audit-log?limit=$limit&offset=$offset&q=${_q(q)}&actor_kind=${_q(actorKind)}&category=${_q(category)}&include_test=$includeTest',
      );
  Future<List<J>> adminPending({bool includeTest = false}) => _getList('/admin/pending-orders?include_test=$includeTest');
  Future<J> adminApprove(int id) => _post('/admin/orders/$id/approve');
  Future<J> adminReject(int id) => _post('/admin/orders/$id/reject');
  Future<J> adminUploadReceipt(int orderId, String filePath, String fileName) async => J.from(
        await _t.send(
          'POST',
          '/admin/orders/$orderId/receipt',
          body: FormData.fromMap({'file': await MultipartFile.fromFile(filePath, filename: fileName)}),
        ),
      );
  Future<J> adminOrderHistory({String? q, String? status, int? userId, int? limit, int? offset}) => _get(
        '/admin/orders/history?${_clean({'q': q, 'status': status, 'user_id': userId, 'limit': limit, 'offset': offset}).entries.map((e) => '${e.key}=${_q(e.value)}').join('&')}',
      );
  Future<List<J>> adminWithdrawals({bool includeTest = false}) =>
      _getList('/admin/withdrawals?include_test=$includeTest');
  Future<J> adminPayWd(int id) => _post('/admin/withdrawals/$id/pay');
  Future<J> adminRejectWd(int id) => _post('/admin/withdrawals/$id/reject');
  Future<J> adminBroadcast(String message) => _post('/admin/broadcast', {'message': message});
  Future<List<J>> adminPaymentCards() => _getList('/admin/payment-cards');
  Future<J> adminAddPaymentCard(Map<String, dynamic> body) => _post('/admin/payment-cards', body);
  Future<J> adminRemovePaymentCard(int id) async => J.from(await _t.send('DELETE', '/admin/payment-cards/$id'));
  Future<J> adminChatThreads() => _get('/admin/chat/threads');
  Future<J> adminSetDuty(bool onDuty) => _post('/admin/duty', {'on_duty': onDuty});
  Future<J> adminClaimChat(int userId) => _post('/admin/chat/threads/$userId/claim');
  Future<J> adminReleaseChat(int userId) => _post('/admin/chat/threads/$userId/release');
  Future<J> adminChatMessages(int userId, {int afterId = 0, bool markRead = false}) =>
      _get('/admin/chat/threads/$userId/messages?after_id=$afterId${markRead ? '&mark_read=1' : ''}');
  Future<J> adminChatMarkRead(int userId) => _post('/admin/chat/threads/$userId/read');
  Future<J> adminChatSend(int userId, String body, [List<Map<String, dynamic>> attachments = const []]) =>
      _post('/admin/chat/threads/$userId/messages', {'body': body, 'attachments': attachments});
  Future<J> adminThreadSubscriptions(int userId) => _get('/admin/chat/threads/$userId/subscriptions');
  Future<J> adminThreadOrders(int userId) => _get('/admin/chat/threads/$userId/orders');
}

/// `paymentCardsFrom` in api.ts.
List<J> paymentCardsFrom(J payment) {
  final cards = payment.objs('cards');
  if (cards.isNotEmpty) return cards;
  final card = payment.text('card');
  if (card == null) return const [];
  return [
    J({'id': 1, 'card': card, 'name': payment.s('name'), 'note': payment.s('note'), 'label': 'کارت اصلی'}),
  ];
}
