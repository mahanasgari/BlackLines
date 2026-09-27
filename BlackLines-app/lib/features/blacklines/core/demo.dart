import 'dart:convert';
import 'dart:typed_data';

import 'package:hiddify/features/blacklines/core/api.dart';

/// `--dart-define=BL_DEMO=true`: run the whole UI against canned data shaped
/// like the real `/shop/api` responses (for development and screenshots only).
const kBLDemo = bool.fromEnvironment('BL_DEMO');

class BLDemoTransport implements BLTransport {
  BLDemoTransport({this.admin = const bool.fromEnvironment('BL_DEMO_ADMIN')});

  final bool admin;
  final _now = DateTime.now();

  String _iso(Duration d) => _now.add(d).toUtc().toIso8601String();

  Map<String, dynamic> get _payment => {
        'card': '6037991234567890',
        'name': 'محمد رضایی',
        'note': 'بعد از واریز، عکس رسید را بفرستید.',
        'cards': [
          {'id': 1, 'card': '6037991234567890', 'name': 'محمد رضایی', 'label': 'ملی', 'note': ''},
          {'id': 2, 'card': '6219861012345678', 'name': 'محمد رضایی', 'label': 'سامان', 'note': ''},
        ],
      };

  Map<String, dynamic> _sub(
    int id,
    String label,
    String plan, {
    String status = 'online',
    int usedGb = 12,
    int totalGb = 50,
    int days = 18,
    String? family,
    String? role,
    String? customer,
    bool payg = false,
  }) {
    final used = usedGb * 1073741824;
    final total = totalGb * 1073741824;
    return {
      'id': id,
      'email': 'bl_$id',
      'label': label,
      'plan_title': plan,
      'expires_at': payg ? null : _iso(Duration(days: days)),
      'enabled': status != 'disabled',
      'online': status == 'online',
      'status': status,
      'up_bytes': used ~/ 8,
      'down_bytes': used - used ~/ 8,
      'up_label': '${(usedGb / 8).toStringAsFixed(1)} GB',
      'down_label': '${(usedGb * 7 / 8).toStringAsFixed(1)} GB',
      'used_bytes': used,
      'total_bytes': total,
      'used_label': '$usedGb GB',
      'total_label': totalGb == 0 ? 'نامحدود' : '$totalGb GB',
      'remaining_bytes': totalGb == 0 ? null : total - used,
      'remaining_label': totalGb == 0 ? 'نامحدود' : '${totalGb - usedGb} GB',
      'usage_percent': totalGb == 0 ? 0 : (usedGb * 100 / totalGb).round(),
      'last_online_ms': _now.millisecondsSinceEpoch,
      'last_online_at': _iso(const Duration(minutes: -3)),
      'last_seen_label': status == 'online' ? 'همین الان' : '۲ ساعت پیش',
      'limit_ip': 2,
      'traffic_label': totalGb == 0 ? 'نامحدود' : '$totalGb گیگ',
      'is_payg': payg,
      'is_metered': payg,
      'today_label': '640 MB',
      'week_label': '4.2 GB',
      'avg_daily_label': '600 MB',
      'days_left': payg ? null : days,
      'sparkline': [3, 5, 2, 8, 6, 9, 4],
      'family_role': role,
      'family_group': family,
      'family_index': role == 'child' ? 1 : (role == 'parent' ? 0 : null),
      'customer_name': customer,
      'subscription_url': 'https://shabash.cloudproducts.ir/shop/sub/demo$id',
      'link_shared': false,
    };
  }

  List<Map<String, dynamic>> get _items => [
        _sub(101, 'گوشی خودم', 'یک ماهه ۵۰ گیگ'),
        _sub(102, 'لپ‌تاپ', 'سه ماهه نامحدود', status: 'offline', usedGb: 84, totalGb: 0, days: 61),
        _sub(103, '', 'خانواده ۳ نفره', family: 'fam1', role: 'parent', usedGb: 20, totalGb: 100, days: 25),
        _sub(104, 'علی', 'خانواده ۳ نفره', family: 'fam1', role: 'child', usedGb: 6, totalGb: 100, days: 25),
        _sub(105, '', 'یک ماهه ۳۰ گیگ', customer: 'سارا احمدی', status: 'offline', usedGb: 1, totalGb: 30, days: 29),
        _sub(106, 'مصرفی', 'پرداخت مصرفی', payg: true, usedGb: 3, totalGb: 0),
      ];

  Map<String, dynamic> _plan(int id, String title, int price, int days, int gb, int ip, {bool pro = false}) => {
        'id': id,
        'title': title,
        'description': gb == 0 ? 'بدون محدودیت حجم، مناسب استفاده سنگین' : 'مناسب استفاده روزمره',
        'price_toman': price,
        'price_label': '$price تومان',
        'charge_toman': (price * 0.9).round(),
        'charge_label': '',
        'pro_discount_percent': 10,
        'duration_days': days,
        'traffic_gb': gb,
        'traffic_label': gb == 0 ? 'نامحدود' : '$gb گیگ',
        'limit_ip': ip,
        'pro_only': pro,
        'pay_after_wallet': (price - 85000).clamp(0, price),
      };

  @override
  Future<Uint8List> blob(String path) async => Uint8List(0);

  @override
  Future<dynamic> send(String method, String path, {Object? body}) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final p = path.split('?').first;
    final r = _route(method, p);
    // Round-trip through JSON so screens only ever see JSON-shaped data.
    return jsonDecode(jsonEncode(r));
  }

  Object? _route(String method, String p) {
    if (method != 'GET') return _mutation(p);
    switch (p) {
      case '/me':
        return {
          'telegram_id': 11223344,
          'username': 'blackline_user',
          'full_name': 'کاربر نمونه',
          'wallet_balance': 85000,
          'is_admin': admin,
          'shop_name': 'Black Lines VPN',
          'payment': _payment,
          'has_birth_date': false,
          'trial_offer': {
            'available': true,
            'duration_days': 1,
            'traffic_gb': 1,
            'traffic_label': '۱ گیگ',
            'limit_ip': 1,
          },
          'is_pro': false,
        };
      case '/plans':
        return [
          _plan(1, 'یک ماهه ۳۰ گیگ', 120000, 30, 30, 1),
          _plan(2, 'یک ماهه ۵۰ گیگ', 170000, 30, 50, 2),
          _plan(3, 'سه ماهه ۱۵۰ گیگ', 420000, 90, 150, 2),
          _plan(4, 'سه ماهه نامحدود', 690000, 90, 0, 2, pro: true),
          _plan(5, 'شش ماهه ۳۰۰ گیگ', 780000, 180, 300, 3),
        ];
      case '/dashboard':
        return {
          'summary': {
            'total': 6,
            'online': 3,
            'offline': 3,
            'used_label': '126 GB',
            'up_label': '15.8 GB',
            'down_label': '110.2 GB',
            'today_label': '1.9 GB',
            'week_label': '14.6 GB',
            'remaining_label': '154 GB',
            'last_seen_label': 'همین الان',
          },
          'items': _items,
          'archived': [
            {
              'id': 90,
              'email': 'bl_90',
              'label': 'قدیمی',
              'plan_title': 'یک ماهه ۲۰ گیگ',
              'expires_at': _iso(const Duration(days: -40)),
              'status': 'expired',
            },
          ],
        };
      case '/subscriptions':
        return {
          'items': [],
          'pending': {
            'id': 5512,
            'plan_title': 'یک ماهه ۵۰ گیگ',
            'amount_toman': 85000,
            'amount_label': '۸۵٬۰۰۰ تومان',
            'wallet_used': 85000,
            'has_receipt': false,
            'payment': _payment,
          },
        };
      case '/wallet':
        return {
          'balance': 85000,
          'balance_label': '۸۵٬۰۰۰ تومان',
          'withdrawable': 85000,
          'withdrawable_label': '۸۵٬۰۰۰ تومان',
          'min_deposit': 50000,
          'min_deposit_label': '۵۰٬۰۰۰ تومان',
          'max_deposit': 20000000,
          'max_deposit_label': '۲۰٬۰۰۰٬۰۰۰ تومان',
          'min_withdraw': 100000,
          'min_withdraw_label': '۱۰۰٬۰۰۰ تومان',
          'min_transfer': 1000,
          'min_transfer_label': '۱٬۰۰۰ تومان',
          'presets': [50000, 100000, 200000, 500000, 1000000],
          'transfers': [
            {
              'id': 1,
              'direction': 'in',
              'amount_toman': 50000,
              'amount_label': '۵۰٬۰۰۰ تومان',
              'other_name': 'رضا',
              'other_telegram_id': 1,
              'created_at': _iso(const Duration(days: -2)),
            },
          ],
          'payment': _payment,
          'pending_deposit': null,
          'pending_withdrawal': null,
          'withdrawals': [
            {
              'id': 12,
              'amount_toman': 150000,
              'amount_label': '۱۵۰٬۰۰۰ تومان',
              'card_number': '6037991234567890',
              'status': 'paid',
              'status_label': 'پرداخت شد',
              'created_at': _iso(const Duration(days: -10)),
              'reviewed_at': null,
            },
          ],
        };
      case '/referral':
        return {
          'invited': 7,
          'paid_referrals': 3,
          'earned_total': 64500,
          'wallet': 85000,
          'percent': 15,
          'min_withdraw': 100000,
          'code': 'ABC123',
          'invite_link': 'https://t.me/BlackLinesBot?start=ref_ABC123',
          'earned_label': '۶۴٬۵۰۰ تومان',
          'wallet_label': '۸۵٬۰۰۰ تومان',
          'min_withdraw_label': '۱۰۰٬۰۰۰ تومان',
          'leaderboard': [
            {'rank': 1, 'display_name': 'م***د', 'earned_total': 420000, 'earned_label': '۴۲۰٬۰۰۰ تومان', 'sales_count': 22},
            {'rank': 2, 'display_name': 'ر***ا', 'earned_total': 210000, 'earned_label': '۲۱۰٬۰۰۰ تومان', 'sales_count': 11},
            {'rank': 5, 'display_name': 'شما', 'earned_total': 64500, 'earned_label': '۶۴٬۵۰۰ تومان', 'sales_count': 3, 'is_self': true},
          ],
          'invitees': [
            {
              'full_name': 'رضا کریمی',
              'username': 'reza_k',
              'joined_at': _iso(const Duration(days: -12)),
              'vpn_purchase_count': 2,
              'vpn_purchase_total': 290000,
              'vpn_purchase_label': '۲۹۰٬۰۰۰ تومان',
              'commission_earned': 43500,
              'commission_label': '۴۳٬۵۰۰ تومان',
              'has_purchased': true,
            },
            {
              'full_name': null,
              'username': 'nima99',
              'joined_at': _iso(const Duration(days: -3)),
              'vpn_purchase_count': 0,
              'vpn_purchase_total': 0,
              'vpn_purchase_label': '۰ تومان',
              'commission_earned': 0,
              'commission_label': '۰ تومان',
              'has_purchased': false,
            },
          ],
          'withdrawals': [],
        };
      case '/pro':
        return {
          'is_pro': false,
          'pro_until': null,
          'pro_until_label': null,
          'discount_percent': 10,
          'config_count': 0,
          'plan': {
            'id': 99,
            'title': 'Pro یک ماهه',
            'description': 'تخفیف روی همه خریدها و امکانات ویژه',
            'price_toman': 49000,
            'price_label': '۴۹٬۰۰۰ تومان',
            'duration_days': 30,
          },
          'benefits': [
            {'id': 'discount', 'title': '۱۰٪ تخفیف همه خریدها', 'description': 'روی پلن‌های آماده و سفارشی', 'active': true},
            {'id': 'unlimited', 'title': 'پلن‌های نامحدود', 'description': 'دسترسی به پلن‌های بدون محدودیت حجم', 'active': true},
            {'id': 'priority', 'title': 'پشتیبانی سریع‌تر', 'description': 'پاسخ در اولویت', 'active': true},
            {'id': 'servers', 'title': 'سرورهای اختصاصی', 'description': 'به‌زودی', 'active': false, 'coming_soon': true},
          ],
        };
      case '/chat/unread':
        return {'unread_count': 1};
      case '/chat/messages':
        return {
          'messages': [
            {'id': 1, 'user_id': 1, 'sender': 'user', 'body': 'سلام، کانفیگم وصل نمیشه', 'created_at': _iso(const Duration(hours: -3)), 'read_at': _iso(const Duration(hours: -3))},
            {
              'id': 2,
              'user_id': 1,
              'sender': 'admin',
              'body': 'سلام! لطفاً از بخش جزئیات کانفیگ «بررسی و رفع مشکل» را بزنید. اگر حل نشد همینجا خبر بدید.',
              'created_at': _iso(const Duration(hours: -2)),
              'read_at': null,
            },
          ],
          'unread_count': 1,
          'latest_id': 2,
        };
      case '/chat/orders':
        return {'items': []};
      case '/reseller-desk':
        return {
          'items': [
            {
              'id': 105,
              'customer_name': 'سارا احمدی',
              'label': null,
              'plan_title': 'یک ماهه ۳۰ گیگ',
              'expires_at': _iso(const Duration(days: 29)),
              'days_left': 29,
              'expired': false,
              'enabled': true,
              'subscription_url': 'https://shabash.cloudproducts.ir/shop/sub/demo105',
              'link_shared': false,
              'link_shared_at': null,
            },
          ],
          'summary': {'total': 1, 'unsent': 1, 'expiring_soon': 0, 'expired': 0},
        };
      case '/growth/options':
        return {
          'family': {'enabled': true, 'min_size': 2, 'max_size': 5, 'extra_discount_percent': 10},
          'purchase_discount_percent': 0,
        };
      case '/custom/options':
        return {'enabled': true, 'min_days': 7, 'max_days': 180, 'min_gb': 1, 'max_gb': 500, 'min_ip': 1, 'max_ip': 5, 'unlimited_allowed': true};
      case '/payg/options':
        return {'enabled': true, 'min_gb': 5, 'max_gb': 200, 'min_ip': 1, 'max_ip': 3, 'existing': []};
      case '/payg/status':
        return {
          'enabled': true,
          'price_per_gb_toman': 4000,
          'price_per_gb_label': '۴٬۰۰۰ تومان',
          'unit_price_toman': 400,
          'unit_price_label': '۴۰۰ تومان',
          'min_wallet_toman': 10000,
          'min_wallet_label': '۱۰٬۰۰۰ تومان',
          'limit_ip': 2,
          'example_100mb_toman': 400,
          'example_100mb_label': '۴۰۰ تومان',
          'wallet_balance': 85000,
          'wallet_label': '۸۵٬۰۰۰ تومان',
          'can_activate': true,
          'needs_topup': false,
          'pro_discount_percent': 10,
          'remaining_bytes': 0,
          'remaining_label': '۰',
          'used_bytes': 0,
          'used_label': '۰',
          'billed_toman': 0,
          'billed_label': '۰ تومان',
          'suspended': false,
          'subscription': null,
        };
      case '/gift-cards':
        return {
          'items': [
            {
              'id': 1,
              'code': 'GIFT-7KQ2-9XM4',
              'plan_id': 2,
              'plan_title': 'یک ماهه ۵۰ گیگ',
              'status': 'available',
              'status_label': 'استفاده نشده',
              'created_at': _iso(const Duration(days: -1)),
              'redeemed_at': null,
            },
          ],
        };
      case '/profile':
        return {
          'telegram_id': 11223344,
          'username': 'blackline_user',
          'full_name': 'کاربر نمونه',
          'has_photo': false,
          'email': null,
          'phone': null,
          'has_email': false,
          'has_phone': false,
          'birth_date': null,
          'birth_date_label': null,
          'birth_date_source': null,
          'birth_date_year_hidden': false,
          'has_birth_date': false,
          'needs_birth_date': true,
          'is_birthday_today': false,
          'days_until_birthday': null,
          'birthday_gift_received_year': null,
          'birthday_gift_amount_toman': 50000,
          'birthday_gift_amount_label': '۵۰٬۰۰۰ تومان',
          'member_since': _iso(const Duration(days: -120)),
          'wallet_balance': 85000,
        };
      case '/orders/history' || '/admin/orders/history':
        return {
          'items': [
            {
              'id': 5512,
              'plan_title': 'یک ماهه ۵۰ گیگ',
              'kind': 'vpn_purchase',
              'kind_label': 'خرید VPN',
              'amount_toman': 170000,
              'amount_label': '۱۷۰٬۰۰۰ تومان',
              'wallet_used': 85000,
              'wallet_used_label': '۸۵٬۰۰۰ تومان',
              'status': 'pending',
              'status_label': 'در انتظار',
              'has_receipt': false,
              'created_at': _iso(const Duration(hours: -5)),
            },
            {
              'id': 5401,
              'plan_title': 'شارژ کیف‌پول',
              'kind': 'wallet_topup',
              'kind_label': 'شارژ کیف‌پول',
              'amount_toman': 200000,
              'amount_label': '۲۰۰٬۰۰۰ تومان',
              'wallet_used': 0,
              'wallet_used_label': null,
              'status': 'approved',
              'status_label': 'تایید شده',
              'has_receipt': true,
              'created_at': _iso(const Duration(days: -6)),
            },
          ],
          'total': 2,
        };
      case '/activity':
        return {'items': [], 'total': 0, 'limit': 40, 'offset': 0};
      case '/parental/options':
        return {
          'enabled': true,
          'categories': [
            {'key': 'adult', 'label': 'بزرگسالان', 'desc': 'سایت‌های نامناسب', 'domain_count': 12000},
            {'key': 'gambling', 'label': 'قمار', 'desc': 'شرط‌بندی و کازینو', 'domain_count': 3400},
            {'key': 'social', 'label': 'شبکه‌های اجتماعی', 'desc': 'اینستاگرام، تیک‌تاک…', 'domain_count': 60},
          ],
          'custom_domains': [],
        };
    }
    if (RegExp(r'^/subscriptions/\d+/family/\d+/activity$').hasMatch(p)) {
      return {
        'child': {'id': 104, 'label': 'علی', 'email': 'bl_104', 'family_role': 'child', 'parental_categories': ['adult'], 'restricted': true},
        'logging': {'ready': true, 'note': ''},
        'summary': {'domains': 3, 'hits': 41, 'blocked': 1, 'downloads': 1},
        'sites': [
          {'domain': 'youtube.com', 'category': 'video', 'category_label': 'ویدیو', 'verdict': 'visit', 'verdict_label': 'بازدید', 'hit_count': 28, 'first_seen': _iso(const Duration(days: -2)), 'last_seen': _iso(const Duration(minutes: -20))},
          {'domain': 'bet365.com', 'category': 'gambling', 'category_label': 'قمار', 'verdict': 'blocked', 'verdict_label': 'مسدود شد', 'hit_count': 3, 'first_seen': _iso(const Duration(days: -1)), 'last_seen': _iso(const Duration(hours: -5))},
          {'domain': 'dl.example.com', 'category': 'download', 'category_label': 'دانلود', 'verdict': 'visit', 'verdict_label': 'بازدید', 'hit_count': 10, 'first_seen': _iso(const Duration(days: -1)), 'last_seen': _iso(const Duration(hours: -2))},
        ],
        'recent': [
          {'domain': 'youtube.com', 'category': 'video', 'category_label': 'ویدیو', 'verdict': 'visit', 'verdict_label': 'بازدید', 'seen_at': _iso(const Duration(minutes: -20))},
          {'domain': 'bet365.com', 'category': 'gambling', 'category_label': 'قمار', 'verdict': 'blocked', 'verdict_label': 'مسدود شد', 'seen_at': _iso(const Duration(hours: -5))},
        ],
        'disclaimer': 'فقط دامنه‌ها ثبت می‌شوند، نه محتوای صفحات.',
      };
    }
    final detail = RegExp(r'^/subscriptions/(\d+)/detail$').firstMatch(p);
    if (detail != null) return _detail(int.parse(detail[1]!));
    return _admin(p) ?? {'ok': true};
  }

  Map<String, dynamic> _detail(int id) {
    final base = _items.firstWhere((e) => e['id'] == id, orElse: () => _items.first);
    return {
      ...base,
      'plan_id': 2,
      'plan_duration_days': 30,
      'created_at': _iso(const Duration(days: -12)),
      'xui_sub_id': 'demo$id',
      'subscription_import': 'https://shabash.cloudproducts.ir/shop/sub/demo$id',
      'auto_renew': false,
      'remaining_days': base['days_left'],
      'expired': base['status'] == 'expired',
      'links': [
        {'index': 0, 'label': 'آلمان · Reality', 'link': 'vless://demo@de.example:443?security=reality#DE', 'kind': 'vless', 'host': 'de.example', 'port': 443, 'ping_ms': 84, 'reachable': true},
        {'index': 1, 'label': 'هلند · WS', 'link': 'vless://demo@nl.example:8443?type=ws#NL', 'kind': 'vless', 'host': 'nl.example', 'port': 8443, 'ping_ms': 131, 'reachable': true},
        {'index': 2, 'label': 'پروکسی تلگرام', 'link': 'tg://proxy?server=tg.example&port=443&secret=ee00', 'kind': 'telegram', 'host': 'tg.example', 'port': 443, 'ping_ms': null, 'reachable': false},
      ],
      'links_text': 'vless://demo@de.example:443#DE\nvless://demo@nl.example:8443#NL',
      'connection': {
        'online': base['online'],
        'connected_ip_count': 1,
        'limit_ip': 2,
        'connected_ips': [
          {'ip': '5.120.33.12', 'at': _iso(const Duration(minutes: -2)), 'node': 'DE', 'nickname': 'گوشی'},
        ],
        'ip_available': true,
        'nickname_presets': ['گوشی', 'لپ‌تاپ', 'تبلت', 'تلویزیون'],
        'last_online_at': base['last_online_at'],
        'history': [
          {'at': _iso(const Duration(minutes: -2)), 'event': 'اتصال', 'ip': '5.120.33.12'},
        ],
      },
      'usage': {
        'today_bytes': 671088640,
        'today_label': '640 MB',
        'week_bytes': 4509715660,
        'week_label': '4.2 GB',
        'avg_daily_bytes': 629145600,
        'avg_daily_label': '600 MB',
        'days_left': base['days_left'],
        'peak_day': 'پنجشنبه',
        'peak_label': '1.3 GB',
        'daily': [
          for (var i = 6; i >= 0; i--)
            {'day': 'd$i', 'label': '${7 - i}', 'used_bytes': (i * 97 % 7 + 2) * 150000000, 'used_label': '${(i * 97 % 7 + 2) * 150} MB'},
        ],
        'sparkline': [3, 5, 2, 8, 6, 9, 4],
        'last_seen_label': base['last_seen_label'],
        'remaining_bytes': base['remaining_bytes'],
        'remaining_label': base['remaining_label'],
      },
      'source': 'purchase',
      'source_label': 'خرید',
      'order_status': 'approved',
      'order_status_label': 'تایید شده',
      'order_amount_label': '۱۷۰٬۰۰۰ تومان',
      'order_id': 5401,
      'family': base['family_group'] == null
          ? null
          : {
              'group': base['family_group'],
              'is_parent': base['family_role'] == 'parent',
              'used_label': '26 GB',
              'members': [
                {
                  'id': 103,
                  'label': 'والد',
                  'email': 'bl_103',
                  'family_index': 0,
                  'family_role': 'parent',
                  'is_parent': true,
                  'parental_categories': [],
                  'restricted': false,
                  'enabled': true,
                  'used_label': '20 GB',
                  'total_label': '100 GB',
                  'online': true,
                },
                {
                  'id': 104,
                  'label': 'علی',
                  'email': 'bl_104',
                  'family_index': 1,
                  'family_role': 'child',
                  'is_parent': false,
                  'parental_categories': ['adult', 'gambling'],
                  'restricted': true,
                  'enabled': true,
                  'used_label': '6 GB',
                  'total_label': '100 GB',
                  'online': true,
                  'vpn_schedule': {'enabled': true, 'start': '08:00', 'end': '21:00', 'days': [0, 1, 2, 3, 4, 5, 6]},
                  'vpn_schedule_label': '۰۸:۰۰ تا ۲۱:۰۰',
                  'vpn_allowed_now': true,
                },
              ],
              'parental': {
                'enabled': true,
                'categories': [
                  {'key': 'adult', 'label': 'بزرگسالان', 'desc': 'سایت‌های نامناسب', 'domain_count': 12000},
                  {'key': 'gambling', 'label': 'قمار', 'desc': 'شرط‌بندی و کازینو', 'domain_count': 3400},
                  {'key': 'social', 'label': 'شبکه‌های اجتماعی', 'desc': 'اینستاگرام، تیک‌تاک…', 'domain_count': 60},
                ],
                'custom_domains': [],
                'custom_domain_count': 0,
              },
            },
    };
  }

  Object? _admin(String p) {
    switch (p) {
      case '/admin/pending-orders':
        return [
          {
            'id': 5512,
            'user': 'کاربر نمونه (@blackline_user)',
            'telegram_id': 11223344,
            'plan': 'یک ماهه ۵۰ گیگ',
            'amount_toman': 85000,
            'amount_label': '۸۵٬۰۰۰ تومان',
            'wallet_used': 85000,
            'has_receipt': true,
          },
        ];
      case '/admin/withdrawals':
        return [
          {'id': 31, 'user': 'رضا کریمی', 'telegram_id': 55, 'amount_label': '۱۲۰٬۰۰۰ تومان', 'card_number': '6219861012345678'},
        ];
      case '/admin/payment-cards':
        return (_payment['cards'] as List);
      case '/admin/chat/threads':
        return {
          'threads': [
            {
              'user_id': 1,
              'telegram_id': 11223344,
              'username': 'blackline_user',
              'full_name': 'کاربر نمونه',
              'last_message': 'سلام، کانفیگم وصل نمیشه',
              'last_message_at': _iso(const Duration(hours: -3)),
              'last_sender': 'user',
              'unread_count': 1,
            },
          ],
          'unread_total': 1,
          'on_duty': true,
          'duty_count': 2,
        };
      case '/admin/birthday-gift':
        return {'enabled': true, 'amount_toman': 50000, 'amount_label': '۵۰٬۰۰۰ تومان'};
      case '/admin/trial-settings':
        return {'enabled': true, 'duration_days': 1, 'traffic_gb': 1, 'limit_ip': 1, 'traffic_label': '۱ گیگ', 'send_links': false};
    }
    return null;
  }

  Object? _mutation(String p) {
    if (p == '/auth/login/start') {
      return {'nonce': 'demo', 'bot_url': 'https://t.me/BlackLinesBot?start=app_demo', 'expires_at': _iso(const Duration(minutes: 5))};
    }
    if (p == '/orders' || p == '/custom/order' || p == '/payg/order' || p == '/wallet/deposit' || p == '/pro/order') {
      return {
        'id': 6001,
        'amount_toman': 85000,
        'amount_label': '۸۵٬۰۰۰ تومان',
        'wallet_used': 85000,
        'needs_receipt': true,
        'wallet_balance': 0,
        'payment': _payment,
        'plan_title': 'یک ماهه ۵۰ گیگ',
      };
    }
    if (p == '/custom/quote' || p == '/payg/quote') {
      return {
        'duration_days': 30,
        'traffic_gb': 40,
        'limit_ip': 2,
        'unlimited': false,
        'title': 'پکیج سفارشی ۳۰ روز · ۴۰ گیگ',
        'traffic_label': '۴۰ گیگ',
        'price_toman': 175000,
        'price_label': '۱۷۵٬۰۰۰ تومان',
        'charge_toman': 157500,
        'charge_label': '۱۵۷٬۵۰۰ تومان',
        'pay_after_wallet': 72500,
        'pro_discount_percent': 10,
      };
    }
    if (p == '/chat/messages') {
      return {
        'ok': true,
        'message': {'id': 99, 'user_id': 1, 'sender': 'user', 'body': 'پیام', 'created_at': _iso(Duration.zero), 'read_at': null},
      };
    }
    if (p.endsWith('/diagnose')) {
      return {
        'ok': true,
        'subscription_id': 101,
        'enabled': true,
        'expired': false,
        'panel_ok': true,
        'reachable_count': 2,
        'server_count': 3,
        'subscription_url': 'https://shabash.cloudproducts.ir/shop/sub/demo101',
        'best': {'label': 'آلمان · Reality', 'link': 'vless://demo@de.example:443#DE', 'host': 'de.example', 'port': 443, 'ping_ms': 84},
        'issues': [
          {'code': 'ok', 'title': 'کانفیگ سالم است', 'hint': 'اگر وصل نمی‌شوید، در برنامه «به‌روزرسانی Subscription» را بزنید یا سرور دیگری انتخاب کنید.', 'action': 'none'},
          {'code': 'server_down', 'title': 'یک سرور در دسترس نیست', 'hint': 'پروکسی تلگرام پاسخ نمی‌دهد؛ بقیه سرورها سالم‌اند.', 'action': 'none'},
        ],
        'can_rotate': true,
        'can_renew': true,
      };
    }
    if (p == '/trial/claim') {
      return {
        'granted': true,
        'subscription_id': 200,
        'email': 'trial_200',
        // Match production: share URIs in links, HTTP subscription for in-app connect.
        'links': ['vless://demo@de.example:443?security=reality#Trial-DE'],
        'subscription_url': 'https://shabash.cloudproducts.ir/shop/sub/trial200',
        'duration_days': 1,
        'traffic_label': '۱ گیگ',
        'expires_at': _iso(const Duration(days: 1)),
        'message': 'کانفیگ تست فعال شد',
      };
    }
    return {'ok': true, 'wallet_balance': 85000};
  }
}
