import 'package:flutter/material.dart';
import 'package:hiddify/features/blacklines/core/api.dart';
import 'package:hiddify/features/blacklines/core/format.dart';
import 'package:hiddify/features/blacklines/core/json.dart';
import 'package:hiddify/features/blacklines/screens/admin/admin_widgets.dart';
import 'package:hiddify/features/blacklines/state/controller.dart';
import 'package:hiddify/features/blacklines/ui/kit.dart';
import 'package:hiddify/features/blacklines/ui/tokens.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _defaultFlags = {'reality': true, 'ws': true, 'http': true, 'ws_tls': true, 'http_ms': true, 'telegram': true};
const _defaultTypes = [
  ('reality', 'Reality'),
  ('ws', 'WS / 443'),
  ('http', 'HTTP'),
  ('ws_tls', 'WS-TLS'),
  ('http_ms', 'HTTP-MS'),
  ('telegram', 'پروکسی تلگرام'),
];

Map<String, bool> _flagsOf(J server) => {
      ..._defaultFlags,
      for (final e in server.obj('config_flags').raw.entries) e.key: e.value == true,
    };

/// admin-servers.tsx.
class AdminServersPanel extends ConsumerStatefulWidget {
  const AdminServersPanel({super.key});

  @override
  ConsumerState<AdminServersPanel> createState() => _AdminServersPanelState();
}

class _AdminServersPanelState extends ConsumerState<AdminServersPanel> {
  List<J> items = const [];
  List<(String, String)> types = _defaultTypes;
  bool loading = true;
  bool acting = false;
  String? message;
  final _draft = {
    for (final k in const ['name', 'country_code', 'xui_base_url', 'xui_api_token', 'inbound_ids', 'public_host', 'public_ip']) k: TextEditingController(),
  };

  BLController get c => ref.read(blControllerProvider);

  @override
  void initState() {
    super.initState();
    c.api.adminServers().then(_apply).catchError((Object e) {
      if (mounted) setState(() => message = persianError(e));
    }).whenComplete(() {
      if (mounted) setState(() => loading = false);
    });
  }

  @override
  void dispose() {
    for (final e in _draft.values) {
      e.dispose();
    }
    super.dispose();
  }

  void _apply(J res) {
    if (!mounted) return;
    setState(() {
      items = res.objs('items');
      final ct = res.objs('config_types');
      if (ct.isNotEmpty) types = [for (final x in ct) (x.s('key'), x.s('label'))];
    });
  }

  Future<void> _run(Future<void> Function() fn) async {
    setState(() {
      acting = true;
      message = null;
    });
    try {
      await fn();
    } catch (e) {
      if (mounted) setState(() => message = persianError(e));
    } finally {
      if (mounted) setState(() => acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = acting || ref.watch(blControllerProvider.select((c) => c.busy));
    final extras = items.where((s) => !s.b('primary')).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'برای هر سرور تیک بزنید کدام کانفیگ‌ها برای کاربر فعال باشد، بعد «ذخیره تنظیمات این سرور» را بزنید. اگر خود سرور را خاموش کنید، همه‌ی لینک‌هایش از پنل کاربر حذف و اتصال قطع می‌شود.',
          style: t(11, c: C.n400, h: 1.6),
        ),
        const Gap(12),
        if (loading) Text('در حال بارگذاری…', textAlign: TextAlign.center, style: t(11, c: C.n500)),
        for (final s in items) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: C.b(30), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(10))),
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
                          Text('${s.s('name')}${s.text('country_code') != null ? ' · ${s.s('country_code')}' : ''}', style: t(14, w: 600)),
                          Text(s.text('public_host') ?? s.text('public_ip') ?? s.s('xui_base_url'), textDirection: TextDirection.ltr, overflow: TextOverflow.ellipsis, style: t(10, c: C.n500, mono: true)),
                          const Gap(4),
                          Text(
                            'اینباند ${s.text('inbound_ids') ?? '—'}${s.b('primary') ? ' · سرور اصلی' : ''}${!s.b('enabled') ? ' · الان مخفی است' : ''}',
                            style: t(10, c: C.n500),
                          ),
                          const Gap(4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Tag(
                                '${s.boolOrNull('health_ok') == false ? 'سلامت: قطع' : 'سلامت: OK'}${s.intOrNull('last_ping_ms') != null ? ' · ${faNum(s.i('last_ping_ms'))}ms' : ''}',
                                tone: s.boolOrNull('health_ok') == false ? Tone.red : Tone.emerald,
                              ),
                              Tag(s.boolOrNull('links_visible') == false ? 'لینک‌ها مخفی' : 'لینک‌ها فعال', tone: s.boolOrNull('links_visible') == false ? Tone.amber : Tone.neutral),
                              if (s.i('health_fail_count') > 0) Text('خطا: ${faNum(s.i('health_fail_count'))}', style: t(10, c: C.n500)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (!s.b('primary')) ...[
                      const Gap(8),
                      Column(
                        children: [
                          TgButton(
                            label: 'همگام‌سازی',
                            variant: BtnVariant.outline,
                            expand: false,
                            height: 28,
                            fontSize: 10,
                            onPressed: busy
                                ? null
                                : () => _run(() async {
                                      final r = await c.api.adminSyncServer(s.i('id'));
                                      final tg = r.i('telegram_attached') + r.i('telegram_skipped') + r.i('telegram_failed') > 0
                                          ? ' · تلگرام: ${faNum(r.i('telegram_attached'))} وصل · ${faNum(r.i('telegram_skipped'))} موجود · ${faNum(r.i('telegram_failed'))} خطا'
                                          : '';
                                      setState(() => message = 'همگام‌سازی: ${faNum(r.i('synced'))} اضافه · ${faNum(r.i('skipped'))} موجود · ${faNum(r.i('failed'))} خطا$tg');
                                    }),
                          ),
                          const Gap(4),
                          TgButton(
                            label: 'حذف',
                            variant: BtnVariant.outline,
                            expand: false,
                            height: 28,
                            fontSize: 10,
                            onPressed: busy
                                ? null
                                : () async {
                                    if (!await confirmSheet(
                                      context,
                                      title: 'حذف سرور',
                                      message: 'این سرور از فروشگاه حذف شود؟ کانفیگ‌های روی خود سرور پاک نمی‌شوند.',
                                      confirm: 'حذف',
                                      destructive: true,
                                    )) {
                                      return;
                                    }
                                    await _run(() async => _apply(await c.api.adminDeleteServer(s.i('id'))));
                                  },
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
                _ServerEditor(
                  key: ValueKey('${s.i('id')}-${s.b('primary')}-${s.raw.hashCode}'),
                  server: s,
                  types: types,
                  busy: busy,
                  onSaved: (res) {
                    _apply(res);
                    setState(() => message = 'ذخیره شد — فقط کانفیگ‌های تیک‌خورده برای کاربر نمایش داده می‌شود.');
                  },
                ),
              ],
            ),
          ),
          const Gap(8),
        ],
        const Gap(4),
        Divider(height: 1, color: C.w(10)),
        const Gap(12),
        Text('افزودن سرور کشور جدید', style: t(11, w: 600, c: C.n300)),
        const Gap(8),
        for (final (key, label, ltr) in const [
          ('name', 'نام (مثلاً آلمان)', false),
          ('country_code', 'کد روی کانفیگ (DE)', true),
          ('xui_base_url', 'آدرس پنل 3x-ui', true),
          ('xui_api_token', 'توکن API', true),
          ('inbound_ids', 'شناسه اینباندها (1,2,3)', true),
          ('public_host', 'دامنه عمومی', true),
          ('public_ip', 'آی‌پی عمومی', true),
        ]) ...[
          Text(label, style: t(10, c: C.n500)),
          const Gap(4),
          BLInput(controller: _draft[key], ltr: ltr, onChanged: (_) => setState(() {})),
          const Gap(8),
        ],
        TgButton(
          label: 'اتصال و ذخیره',
          height: 40,
          onPressed: busy || _draft['name']!.text.trim().isEmpty || _draft['xui_base_url']!.text.trim().isEmpty || _draft['xui_api_token']!.text.trim().isEmpty
              ? null
              : () => _run(() async {
                    _apply(await c.api.adminAddServer({for (final e in _draft.entries) e.key: e.value.text.trim()}));
                    for (final e in _draft.values) {
                      e.clear();
                    }
                    setState(() => message = 'سرور اضافه شد. همگام‌سازی را بزنید تا کاربران فعلی هم روی این سرور ساخته شوند.');
                  }),
        ),
        if (message != null) ...[const Gap(8), Text(message!, style: t(11, c: C.n400, h: 1.6))],
        if (extras.isEmpty && !loading) ...[
          const Gap(8),
          Text('هنوز سرور اضافه‌ای ندارید — فقط سرور اصلی فعال است.', style: t(11, c: C.n500)),
        ],
      ],
    );
  }
}

class _ServerEditor extends ConsumerStatefulWidget {
  const _ServerEditor({super.key, required this.server, required this.types, required this.busy, required this.onSaved});

  final J server;
  final List<(String, String)> types;
  final bool busy;
  final ValueChanged<J> onSaved;

  @override
  ConsumerState<_ServerEditor> createState() => _ServerEditorState();
}

class _ServerEditorState extends ConsumerState<_ServerEditor> {
  late Map<String, bool> saved = _flagsOf(widget.server);
  late Map<String, bool> draft = {...saved};
  late bool serverOn = widget.server.b('enabled');
  bool saving = false;
  String? error;

  bool get flagsDirty => saved.keys.any((k) => saved[k] != draft[k]);
  bool get dirty => serverOn != widget.server.b('enabled') || flagsDirty;

  Future<void> _save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final res = await ref.read(blControllerProvider).api.adminSetServerVisibility(
            widget.server.i('id'),
            enabled: serverOn != widget.server.b('enabled') ? serverOn : null,
            configs: flagsDirty ? draft : null,
          );
      widget.onSaved(res);
    } catch (e) {
      if (mounted) setState(() => error = persianError(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.busy || saving;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: C.w(8)))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: C.b(25), borderRadius: BorderRadius.circular(8), border: Border.all(color: C.w(10))),
            child: CheckLine(
              value: serverOn,
              onChanged: (v) {
                if (!locked) setState(() => serverOn = v);
              },
              label: 'این سرور برای کاربران فعال باشد${!serverOn ? ' (مخفی + قطع اتصال)' : ''}',
            ),
          ),
          const Gap(8),
          Opacity(
            opacity: serverOn ? 1 : 0.45,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('کدام کانفیگ‌ها در پنل کاربر نشان داده شوند؟', style: t(10, c: C.n500)),
                const Gap(6),
                for (final (key, label) in widget.types) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: draft[key] == true ? C.a(C.emerald500, 0.1) : C.b(20),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: draft[key] == true ? C.a(C.emerald500, 0.3) : C.w(10)),
                    ),
                    child: CheckLine(
                      value: draft[key] == true,
                      label: label,
                      onChanged: (v) {
                        if (serverOn && !locked) setState(() => draft = {...draft, key: v});
                      },
                    ),
                  ),
                  const Gap(6),
                ],
              ],
            ),
          ),
          TgButton(
            label: saving ? 'در حال ذخیره…' : 'ذخیره تنظیمات این سرور',
            height: 36,
            fontSize: 12,
            onPressed: !dirty || locked ? null : _save,
          ),
          if (error != null) ...[const Gap(6), Text(error!, style: t(11, c: C.red300))],
        ],
      ),
    );
  }
}

/// growth-admin.tsx.
class GrowthAdminPanel extends ConsumerStatefulWidget {
  const GrowthAdminPanel({super.key});

  @override
  ConsumerState<GrowthAdminPanel> createState() => _GrowthAdminPanelState();
}

class _GrowthAdminPanelState extends ConsumerState<GrowthAdminPanel> {
  bool loading = true;
  bool saving = false;
  List<J> promos = const [];
  bool familyEnabled = true;
  bool parentalEnabled = true;
  List<J> parentalCats = const [];
  String kind = 'percent';
  final _familyMax = TextEditingController(text: '5');
  final _familyDisc = TextEditingController(text: '10');
  final _purchaseDisc = TextEditingController(text: '0');
  final _code = TextEditingController();
  final _value = TextEditingController(text: '20');
  final _maxUses = TextEditingController(text: '0');
  final _perUser = TextEditingController(text: '1');
  final _note = TextEditingController();
  final _domains = TextEditingController();

  BLController get c => ref.read(blControllerProvider);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    for (final x in [_familyMax, _familyDisc, _purchaseDisc, _code, _value, _maxUses, _perUser, _note, _domains]) {
      x.dispose();
    }
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => loading = true);
    try {
      final r = await Future.wait([c.api.adminPromoCodes(), c.api.adminFamilySettings(), c.api.adminDiscountSettings(), c.api.adminParentalSettings()]);
      if (!mounted) return;
      setState(() {
        promos = r[0].objs('items');
        familyEnabled = r[1].b('enabled');
        _familyMax.text = '${r[1].i('max_size', 5)}';
        _familyDisc.text = '${r[2].intOrNull('family_extra_discount_percent') ?? r[1].i('extra_discount_percent', 10)}';
        _purchaseDisc.text = '${r[2].i('purchase_discount_percent')}';
        parentalEnabled = r[3].b('enabled');
        _domains.text = r[3].strs('custom_domains').join('\n');
        parentalCats = r[3].objs('categories');
      });
    } catch (e) {
      notify(persianError(e), ToastStatus.error);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _save(Future<void> Function() fn) async {
    setState(() => saving = true);
    try {
      await fn();
    } catch (e) {
      notify(persianError(e), ToastStatus.error);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  int _n(TextEditingController x, [int fallback = 0]) => int.tryParse(x.text) ?? fallback;

  Widget _section(String intro, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.only(top: 12),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: C.w(10)))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [Text(intro, style: t(11, c: C.n400, h: 1.6)), const Gap(8), ...children],
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (loading) return Text('در حال بارگذاری…', style: t(11, c: C.n500));
    final locked = saving || ref.watch(blControllerProvider.select((c) => c.busy));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('تخفیف فقط هنگام خرید اعمال می‌شود، نه وقتی کاربر تعداد نفر یا پلن را انتخاب می‌کند.', style: t(11, c: C.n400, h: 1.6)),
        const Gap(8),
        NumGrid(enabled: !locked, fields: [('تخفیف روی مبلغ خرید ٪', _purchaseDisc), ('تخفیف عضو اضافه خانواده ٪', _familyDisc)]),
        TgButton(
          label: 'ذخیره تخفیف خرید',
          height: 36,
          fontSize: 12,
          onPressed: locked
              ? null
              : () => _save(() async {
                    final r = await c.api.adminSetDiscountSettings({
                      'purchase_discount_percent': _n(_purchaseDisc).clamp(0, 90),
                      'family_extra_discount_percent': _n(_familyDisc).clamp(0, 50),
                    });
                    _purchaseDisc.text = '${r.i('purchase_discount_percent')}';
                    _familyDisc.text = '${r.i('family_extra_discount_percent')}';
                    notify('تخفیف خرید ذخیره شد', ToastStatus.success);
                  }),
        ),
        const Gap(12),
        _section('پکیج خانواده: یک پرداخت برای چند کانفیگ (اولی والد، بقیه فرزند). والد می‌تواند دسترسی فرزند را محدود کند.', [
          CheckLine(value: familyEnabled, label: 'فعال بودن پکیج خانواده', onChanged: (v) => setState(() => familyEnabled = v)),
          const Gap(6),
          NumField(label: 'حداکثر اعضا', controller: _familyMax, enabled: !locked),
          const Gap(8),
          TgButton(
            label: 'ذخیره خانواده',
            height: 36,
            fontSize: 12,
            onPressed: locked
                ? null
                : () => _save(() async {
                      final r = await c.api.adminSetFamilySettings({
                        'enabled': familyEnabled,
                        'max_size': _n(_familyMax, 5).clamp(1, 10),
                        'extra_discount_percent': _n(_familyDisc).clamp(0, 50),
                      });
                      setState(() {
                        familyEnabled = r.b('enabled');
                        _familyMax.text = '${r.i('max_size')}';
                      });
                      notify('تنظیمات پکیج خانواده ذخیره شد', ToastStatus.success);
                    }),
          ),
        ]),
        _section('محدودیت والدین: والد روی کانفیگ فرزند سایت‌هایی مثل تیک‌تاک یا بازی را مسدود می‌کند (روی سرور).', [
          CheckLine(value: parentalEnabled, label: 'فعال بودن محدودیت والدین', onChanged: (v) => setState(() => parentalEnabled = v)),
          for (final cat in parentalCats) Text('· ${cat.s('label')} — ${cat.s('desc')}', style: t(10, c: C.n400)),
          const Gap(8),
          Text('دامنه‌های سفارشی (هر خط یکی)', style: t(10, c: C.n400)),
          const Gap(4),
          AreaField(controller: _domains, hint: 'example.com\ndomain:blocked.net', ltr: true),
          const Gap(8),
          TgButton(
            label: 'ذخیره محدودیت والدین',
            height: 36,
            fontSize: 12,
            onPressed: locked
                ? null
                : () => _save(() async {
                      final domains = _domains.text.split(RegExp(r'[\n,]')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
                      final r = await c.api.adminSetParentalSettings(enabled: parentalEnabled, customDomains: domains);
                      setState(() {
                        parentalEnabled = r.b('enabled');
                        _domains.text = r.strs('custom_domains').join('\n');
                        parentalCats = r.objs('categories');
                      });
                      final syncFailed = r.objOrNull('sync')?.boolOrNull('ok') == false;
                      notify(
                        syncFailed ? 'ذخیره شد ولی همگام‌سازی پنل کامل نشد' : 'محدودیت والدین ذخیره و روی سرور اعمال شد',
                        syncFailed ? ToastStatus.error : ToastStatus.success,
                      );
                    }),
          ),
        ]),
        _section('کد تخفیف: درصد از مبلغ یا روز رایگان اضافه روی مدت اشتراک.', [
          Text('کد', style: t(10, c: C.n400)),
          const Gap(4),
          BLInput(
            controller: _code,
            hint: 'SUMMER20',
            ltr: true,
            enabled: !locked,
            onChanged: (v) {
              final up = v.toUpperCase();
              if (up != v) _code.value = _code.value.copyWith(text: up, selection: TextSelection.collapsed(offset: up.length));
              setState(() {});
            },
          ),
          const Gap(8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('نوع', style: t(10, c: C.n500)),
                    const Gap(4),
                    Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(color: C.b(40), borderRadius: BorderRadius.circular(8), border: Border.all(color: C.w(15))),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: kind,
                          isExpanded: true,
                          dropdownColor: C.sheetElevated,
                          style: t(13),
                          items: const [
                            DropdownMenuItem(value: 'percent', child: Text('درصد تخفیف')),
                            DropdownMenuItem(value: 'free_days', child: Text('روز رایگان')),
                          ],
                          onChanged: locked ? null : (v) => setState(() => kind = v ?? 'percent'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Gap(8),
              Expanded(child: NumField(label: kind == 'percent' ? 'درصد' : 'روز', controller: _value, enabled: !locked)),
            ],
          ),
          const Gap(8),
          NumGrid(enabled: !locked, fields: [('سقف کل (۰=بی‌حد)', _maxUses), ('سقف هر کاربر', _perUser)]),
          Text('یادداشت', style: t(10, c: C.n400)),
          const Gap(4),
          BLInput(controller: _note, enabled: !locked),
          const Gap(8),
          TgButton(
            label: 'ساخت کد تخفیف',
            height: 36,
            fontSize: 12,
            onPressed: locked || _code.text.trim().length < 3
                ? null
                : () => _save(() async {
                      await c.api.adminCreatePromo({
                        'code': _code.text.trim(),
                        'kind': kind,
                        'value': _n(_value),
                        'max_uses': _n(_maxUses),
                        'per_user_limit': _n(_perUser, 1),
                        'enabled': true,
                        'note': _note.text.trim(),
                      });
                      _code.clear();
                      _note.clear();
                      notify('کد تخفیف ساخته شد', ToastStatus.success);
                      await _reload();
                    }),
          ),
        ]),
        if (promos.isEmpty)
          Text('هنوز کدی ساخته نشده.', style: t(11, c: C.n500))
        else
          for (final p in promos) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: C.b(30), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(10))),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(p.s('code'), textDirection: TextDirection.ltr, style: t(14, w: 600, mono: true)),
                            const Gap(8),
                            Tag(p.b('enabled') ? 'فعال' : 'خاموش', tone: p.b('enabled') ? Tone.emerald : Tone.neutral, size: 9),
                          ],
                        ),
                        const Gap(2),
                        Text(
                          '${p.s('kind_label')} · ${p.s('value_label')} · استفاده ${faNum(p.i('used_count'))}${p.i('max_uses') > 0 ? '/${faNum(p.i('max_uses'))}' : ''}${p.text('note') != null ? ' · ${p.s('note')}' : ''}',
                          style: t(10, c: C.n400),
                        ),
                      ],
                    ),
                  ),
                  TgButton(
                    label: p.b('enabled') ? 'خاموش' : 'روشن',
                    variant: BtnVariant.outline,
                    expand: false,
                    height: 32,
                    fontSize: 10,
                    onPressed: locked
                        ? null
                        : () => _save(() async {
                              await c.api.adminSetPromoEnabled(p.i('id'), !p.b('enabled'));
                              await _reload();
                            }),
                  ),
                ],
              ),
            ),
            const Gap(6),
          ],
      ],
    );
  }
}
