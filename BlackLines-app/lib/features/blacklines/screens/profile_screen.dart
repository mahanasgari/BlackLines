import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/features/blacklines/core/api.dart';
import 'package:hiddify/features/blacklines/core/format.dart';
import 'package:hiddify/features/blacklines/core/json.dart';
import 'package:hiddify/features/blacklines/screens/activity_log.dart';
import 'package:hiddify/features/blacklines/screens/common.dart';
import 'package:hiddify/features/blacklines/screens/sheets/help_guide.dart';
import 'package:hiddify/features/blacklines/screens/sheets/order_history.dart';
import 'package:hiddify/features/blacklines/screens/sheets/reseller_desk.dart';
import 'package:hiddify/features/blacklines/state/controller.dart';
import 'package:hiddify/features/blacklines/ui/kit.dart';
import 'package:hiddify/features/blacklines/ui/tokens.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// profile-sheet.tsx `ProfilePanel`.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  J? profile;
  Uint8List? photo;
  bool loading = true;
  String? error;

  BLController get c => ref.read(blControllerProvider);

  @override
  void initState() {
    super.initState();
    _load();
    c.api.profilePhoto().then((b) {
      if (mounted && b.isNotEmpty) setState(() => photo = b);
    }).catchError((_) {});
    if (c.profileFocusHelp) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) openHelpGuide(context);
      });
    }
  }

  Future<void> _load() async {
    try {
      final p = await c.api.profile();
      _apply(p);
    } catch (e) {
      if (mounted) setState(() => error = persianError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _apply(J p) {
    setState(() => profile = p);
    if (p.b('has_birth_date')) {
      c.me = c.me?.merge({'wallet_balance': p.i('wallet_balance'), 'has_birth_date': true});
      c.setWalletBalance(p.i('wallet_balance'));
    }
  }

  static String _initials(String? name) {
    final n = (name ?? '').trim();
    if (n.isEmpty) return '?';
    final parts = n.split(RegExp(r'\s+'));
    if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
    return n.substring(0, n.length < 2 ? n.length : 2).toUpperCase();
  }

  String? _countdown(J p) {
    if (!p.b('has_birth_date')) return null;
    if (p.b('is_birthday_today') || p.intOrNull('days_until_birthday') == 0) return 'امروز تولد شماست 🎂';
    final d = p.intOrNull('days_until_birthday');
    return d == null ? null : '${faNum(d)} روز تا تولد بعدی';
  }

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final desk = ref.watch(blControllerProvider.select((c) => c.resellerDesk));
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('پروفایل', style: t(16, w: 700)),
              const Gap(2),
              Text('حساب، تماس، تولد و تنظیمات', style: t(11, c: C.n400)),
            ],
          ),
        ),
        const Gap(20),
        if (loading) const OrbLoaderPanel(),
        if (!loading && p == null && error != null) Callout(error!, tone: Tone.red),
        if (!loading && p != null) ..._body(p, desk),
      ],
    );
  }

  List<Widget> _body(J p, J? desk) {
    final birthdayComplete = p.b('has_birth_date') && !p.b('birth_date_year_hidden');
    final birthdayNeedsYear = p.b('has_birth_date') && p.b('birth_date_year_hidden');
    final fromTelegram = p.s('birth_date_source') == 'telegram';
    final filled = [p.b('has_email'), p.b('has_phone'), birthdayComplete].where((v) => v).length;
    final complete = filled == 3;
    final countdown = _countdown(p);
    final deskTotal = desk?.obj('summary').i('total') ?? 0;
    return [
      // Header card
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: C.b(50),
                    border: Border.all(color: C.w(20)),
                    boxShadow: [BoxShadow(color: C.w(4), spreadRadius: 4)],
                  ),
                  child: photo != null
                      ? Image.memory(photo!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink())
                      : Center(child: Text(_initials(p.text('full_name')), style: t(18, w: 700, c: C.white))),
                ),
                const Gap(14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.text('full_name') ?? 'کاربر', overflow: TextOverflow.ellipsis, style: t(18, w: 600, h: 1.2)),
                      if (p.text('username') != null)
                        Text('@${p.s('username')}', textDirection: TextDirection.ltr, style: t(12, c: C.n400)),
                      const Gap(6),
                      Text('عضو از ${p.text('member_since') != null ? formatDateFa(p.text('member_since'), short: true) : '—'}', style: t(11, c: C.n500)),
                    ],
                  ),
                ),
                TgButton(
                  label: 'خروج',
                  icon: Icons.logout_rounded,
                  variant: BtnVariant.outline,
                  expand: false,
                  height: 34,
                  fontSize: 12,
                  foreground: C.red300,
                  onPressed: () => _logout(context),
                ),
              ],
            ),
            const Gap(14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _StatusChip(ok: p.b('has_email'), label: 'ایمیل'),
                _StatusChip(ok: p.b('has_phone'), label: 'موبایل'),
                _StatusChip(ok: birthdayComplete, label: 'تولد'),
              ],
            ),
            if (complete && countdown != null && !p.b('is_birthday_today')) ...[
              const Gap(12),
              Text(countdown, style: t(11, c: C.n400)),
            ],
            if (!complete) ...[
              const Gap(12),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(value: filled / 3, minHeight: 4, backgroundColor: C.w(8), color: C.a(C.emerald400, 0.85)),
              ),
              const Gap(6),
              Text('${faNum(filled)} از ${faNum(3)} مورد تکمیل شده', style: t(11, c: C.n500)),
            ],
          ],
        ),
      ),
      const Gap(20),
      if (p.b('is_birthday_today'))
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: C.a(C.amber400, 0.3)),
            gradient: LinearGradient(colors: [C.a(C.amber500, 0.15), C.a(C.orange500, 0.1)]),
          ),
          child: Column(
            children: [
              Icon(Icons.cake_outlined, size: 24, color: C.amber300),
              const Gap(4),
              Text('تولدت مبارک!', style: t(14, w: 600, c: C.amber100)),
            ],
          ),
        )
      else if (!birthdayComplete)
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _birthdaySheet(p),
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: C.a(C.amber500, 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: C.a(C.amber400, 0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: C.a(C.amber500, 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: C.a(C.amber400, 0.25)),
                    ),
                    child: Icon(Icons.cake_outlined, size: 20, color: C.amber200),
                  ),
                  const Gap(12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(birthdayNeedsYear ? 'سال تولد را کامل کن' : 'تاریخ تولد را ثبت کن', style: t(13, w: 600, c: C.amber100)),
                        const Gap(2),
                        Text(
                          birthdayNeedsYear
                              ? 'روز تولد از تلگرام خوانده شد (${p.s('birth_date_label')}). سال را وارد کن.'
                              : 'تاریخ تولدت را برای تکمیل پروفایل ثبت کن.',
                          style: t(11, c: C.a(C.amber200, 0.75), h: 1.6),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_left_rounded, size: 18, color: C.a(C.amber200, 0.7)),
                ],
              ),
            ),
          ),
        ),
      const Gap(20),
      const _SectionLabel('اطلاعات حساب'),
      const Gap(8),
      _Group(
        children: [
          _Row(
            icon: Icons.person_outline_rounded,
            label: 'آیدی تلگرام',
            value: '${p.i('telegram_id')}',
            ltr: true,
            trailing: Icon(Icons.copy_rounded, size: 16, color: C.n500),
            onTap: () => copyText('${p.i('telegram_id')}'),
          ),
          _Row(
            icon: Icons.mail_outline_rounded,
            label: 'ایمیل',
            value: p.text('email'),
            empty: 'برای پشتیبانی ثبت کن',
            ltr: true,
            warn: !p.b('has_email'),
            onTap: () => _contactSheet(p),
          ),
          _Row(
            icon: Icons.phone_outlined,
            label: 'شماره موبایل',
            value: p.text('phone'),
            empty: 'برای پشتیبانی ثبت کن',
            ltr: true,
            warn: !p.b('has_phone'),
            onTap: () => _contactSheet(p),
          ),
          _Row(
            icon: Icons.calendar_today_outlined,
            label: 'تاریخ تولد',
            value: birthdayComplete ? p.text('birth_date_label') : null,
            empty: birthdayNeedsYear ? (p.text('birth_date_label') ?? 'سال مشخص نیست') : 'برای تکمیل پروفایل ثبت کن',
            hint: birthdayComplete ? (countdown != null && !p.b('is_birthday_today') ? countdown : (fromTelegram ? 'از پروفایل تلگرام' : null)) : null,
            warn: !birthdayComplete,
            onTap: () => _birthdaySheet(p),
          ),
        ],
      ),
      const Gap(20),
      const _SectionLabel('تنظیمات و راهنما'),
      const Gap(8),
      _Group(
        children: [
          _Row(
            icon: Icons.storefront_outlined,
            label: 'میز فروش',
            value: deskTotal > 0 ? '${faNum(deskTotal)} مشتری' : 'کانفیگ‌هایی که برای کس دیگری خریدی',
            onTap: () => openResellerDesk(context),
          ),
          _Row(
            icon: C.light ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
            label: 'ظاهر برنامه',
            value: c.themePref == null ? (C.light ? 'حالت روشن · خودکار' : 'حالت تاریک · خودکار') : (C.light ? 'حالت روشن' : 'حالت تاریک'),
            onTap: () => _themeSheet(context),
            trailing: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(shape: BoxShape.circle, color: C.w(5), border: Border.all(color: C.w(12))),
              child: Icon(C.light ? Icons.dark_mode_outlined : Icons.light_mode_outlined, size: 15, color: C.n300),
            ),
          ),
          _Row(icon: Icons.history_rounded, label: 'تاریخچه', value: 'خرید و پرداخت', onTap: () => openOrderHistory(context)),
          _Row(
            icon: Icons.receipt_long_outlined,
            label: 'فعالیت‌های من',
            value: 'گزارش کارهای اخیر',
            onTap: () => showTgSheet(context, title: 'فعالیت‌های من', builder: (_) => const _MyActivity()),
          ),
          _Row(
            icon: Icons.help_outline_rounded,
            label: 'راهنمای استفاده',
            value: 'آموزش، اتصال و سوالات متداول',
            onTap: () => openHelpGuide(context),
          ),
          _Row(
            icon: Icons.logout_rounded,
            label: 'حساب',
            value: 'خروج از حساب',
            warn: true,
            onTap: () => _logout(context),
          ),
        ],
      ),
    ];
  }

  void _themeSheet(BuildContext context) {
    haptic();
    showTgSheet(
      context,
      title: 'ظاهر برنامه',
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final pref = ref.watch(blControllerProvider.select((c) => c.themePref));
          Widget option(String? value, IconData icon, String label, String hint) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Panel(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  borderColor: pref == value ? C.w(40) : null,
                  onTap: () {
                    haptic();
                    Navigator.of(ctx).pop();
                    ref.read(blControllerProvider).setThemePref(value);
                  },
                  child: Row(
                    children: [
                      Icon(icon, size: 20, color: C.n300),
                      const Gap(12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [Text(label, style: t(14, w: 600)), Text(hint, style: t(11, c: C.n500))],
                        ),
                      ),
                      if (pref == value) Icon(Icons.check_circle_rounded, size: 18, color: C.foreground),
                    ],
                  ),
                ),
              );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              option(null, Icons.brightness_auto_outlined, 'خودکار', 'هماهنگ با تنظیمات گوشی'),
              option('dark', Icons.dark_mode_outlined, 'حالت تاریک', 'پس‌زمینه مشکی'),
              option('light', Icons.light_mode_outlined, 'حالت روشن', 'پس‌زمینه کرم روشن'),
            ],
          );
        },
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    if (await confirmSheet(
      context,
      title: 'خروج از حساب',
      message: 'از حساب BlackLines خارج می‌شوید. اتصال VPN فعلی قطع نمی‌شود و بعداً می‌توانید دوباره با تلگرام وارد شوید.',
      confirm: 'خروج',
      destructive: true,
    )) {
      await c.logout();
    }
  }

  void _contactSheet(J p) {
    haptic();
    showTgSheet(context, title: 'اطلاعات تماس', builder: (_) => _ContactForm(profile: p, onSaved: _apply));
  }

  void _birthdaySheet(J p) {
    haptic();
    showTgSheet(context, title: 'تاریخ تولد', builder: (_) => _BirthdayForm(profile: p, onSaved: _apply));
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(text, style: t(11, w: 600, c: C.n500)));
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: C.b(40), borderRadius: BorderRadius.circular(16), border: Border.all(color: C.w(12))),
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) Divider(height: 1, color: C.w(8)),
              children[i],
            ],
          ],
        ),
      );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    this.value,
    this.empty,
    this.hint,
    this.ltr = false,
    this.warn = false,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String? value;
  final String? empty;
  final String? hint;
  final bool ltr;
  final bool warn;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final filled = value != null && value!.trim().isNotEmpty;
    return InkWell(
      onTap: onTap == null
          ? null
          : () {
              haptic();
              onTap!();
            },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: warn ? C.a(C.amber500, 0.1) : C.w(5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: warn ? C.a(C.amber400, 0.25) : C.w(10)),
                ),
                child: Icon(icon, size: 16, color: warn ? C.amber200 : C.n300),
              ),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: t(11, c: C.n500)),
                    Text(
                      filled ? value! : (empty ?? 'ثبت نشده'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: filled && ltr ? TextDirection.ltr : null,
                      textAlign: TextAlign.start,
                      style: t(13, w: filled ? 500 : 400, c: filled ? C.n100 : (warn ? C.a(C.amber200, 0.9) : C.n500)),
                    ),
                    if (hint != null) Text(hint!, maxLines: 1, overflow: TextOverflow.ellipsis, style: t(10, c: C.n500)),
                  ],
                ),
              ),
              trailing ?? (onTap != null ? Icon(Icons.chevron_left_rounded, size: 18, color: C.n600) : const SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.ok, required this.label});

  final bool ok;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: ok ? C.a(C.emerald500, 0.1) : C.a(C.amber500, 0.1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: ok ? C.a(C.emerald400, 0.2) : C.a(C.amber400, 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (ok) ...[Icon(Icons.check_rounded, size: 10, color: C.emerald200), const Gap(4)],
            Text(label, style: t(10, c: ok ? C.emerald200 : C.amber200)),
          ],
        ),
      );
}

class _ContactForm extends ConsumerStatefulWidget {
  const _ContactForm({required this.profile, required this.onSaved});

  final J profile;
  final ValueChanged<J> onSaved;

  @override
  ConsumerState<_ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends ConsumerState<_ContactForm> {
  late final _email = TextEditingController(text: widget.profile.text('email') ?? '');
  late final _phone = TextEditingController(text: widget.profile.text('phone') ?? '');
  bool saving = false;
  String? error;

  @override
  void dispose() {
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final p = await ref.read(blControllerProvider).api.saveProfileContact(email: _email.text.trim(), phone: _phone.text.trim());
      widget.onSaved(p);
      haptic();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      final msg = e is BLApiError ? e.message : '$e';
      setState(() => error = const {'invalid_email': 'ایمیل معتبر نیست', 'invalid_phone': 'شماره موبایل معتبر نیست'}[msg] ?? persianError(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final complete = widget.profile.b('has_email') && widget.profile.b('has_phone');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('ایمیل و شماره برای پشتیبانی و پیگیری سفارش استفاده می‌شود.', style: t(12, c: C.n400, h: 1.6)),
        if (error != null) ...[const Gap(12), Callout(error!, tone: Tone.red)],
        const Gap(16),
        const FieldLabel('ایمیل'),
        const Gap(6),
        BLInput(controller: _email, hint: 'name@email.com', ltr: true, keyboardType: TextInputType.emailAddress),
        const Gap(16),
        const FieldLabel('شماره موبایل'),
        const Gap(6),
        BLInput(controller: _phone, hint: '0912…', ltr: true, keyboardType: TextInputType.phone),
        const Gap(16),
        TgButton(
          label: saving ? 'در حال ذخیره…' : (complete ? 'بروزرسانی اطلاعات' : 'ذخیره اطلاعات تماس'),
          onPressed: saving ? null : _save,
        ),
      ],
    );
  }
}

class _BirthdayForm extends ConsumerStatefulWidget {
  const _BirthdayForm({required this.profile, required this.onSaved});

  final J profile;
  final ValueChanged<J> onSaved;

  @override
  ConsumerState<_BirthdayForm> createState() => _BirthdayFormState();
}

class _BirthdayFormState extends ConsumerState<_BirthdayForm> {
  DateTime? date;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    date = DateTime.tryParse(widget.profile.s('birth_date'));
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: date ?? DateTime(now.year - 20),
      firstDate: DateTime(1920),
      lastDate: now,
      helpText: 'تاریخ تولد (میلادی)',
    );
    if (picked != null) setState(() => date = picked);
  }

  Future<void> _save() async {
    final d = date;
    if (d == null) {
      setState(() => error = 'لطفاً تاریخ تولد را انتخاب کنید');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    String two(int v) => v.toString().padLeft(2, '0');
    try {
      final p = await ref.read(blControllerProvider).api.saveBirthDate('${d.year}-${two(d.month)}-${two(d.day)}');
      widget.onSaved(p);
      haptic();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      final msg = e is BLApiError ? e.message : '$e';
      setState(
        () => error = const {
              'future_date': 'تاریخ نمی‌تواند در آینده باشد',
              'too_young': 'حداقل سن ۱۰ سال است',
              'invalid_date': 'فرمت تاریخ نامعتبر است',
            }[msg] ??
            persianError(e),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final complete = p.b('has_birth_date') && !p.b('birth_date_year_hidden');
    final needsYear = p.b('has_birth_date') && p.b('birth_date_year_hidden');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null) ...[Callout(error!, tone: Tone.red), const Gap(12)],
        Text(
          complete
              ? (p.s('birth_date_source') == 'telegram'
                  ? 'این تاریخ از پروفایل تلگرام خوانده شده. در صورت نیاز می‌توانی عوضش کنی.'
                  : 'تاریخ ثبت‌شده را در صورت نیاز تغییر بده.')
              : needsYear
                  ? 'روز تولد از تلگرام خوانده شد (${p.s('birth_date_label')})، ولی سال مشخص نیست. تاریخ کامل را وارد کن.'
                  : 'تاریخ تولد در پروفایل تلگرام دیده نشد. در صورت تمایل واردش کن.',
          style: t(12, c: C.n400, h: 1.6),
        ),
        const Gap(16),
        const FieldLabel('تاریخ تولد (میلادی)'),
        const Gap(6),
        GestureDetector(
          onTap: _pick,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: C.b(40), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(12))),
            child: Row(
              children: [
                Icon(Icons.calendar_today_outlined, size: 16, color: C.n400),
                const Gap(8),
                Text(
                  date == null ? 'انتخاب تاریخ' : faDigits('${date!.year}/${date!.month}/${date!.day}'),
                  style: t(14, c: date == null ? C.n500 : Colors.white),
                ),
              ],
            ),
          ),
        ),
        const Gap(16),
        TgButton(
          label: saving ? 'در حال ذخیره…' : (complete ? 'بروزرسانی تاریخ تولد' : 'ثبت تاریخ تولد'),
          onPressed: saving || date == null ? null : _save,
        ),
      ],
    );
  }
}

class _MyActivity extends ConsumerStatefulWidget {
  const _MyActivity();

  @override
  ConsumerState<_MyActivity> createState() => _MyActivityState();
}

class _MyActivityState extends ConsumerState<_MyActivity> {
  List<J>? items;

  @override
  void initState() {
    super.initState();
    ref.read(blControllerProvider).api.myActivity().then((r) {
      if (mounted) setState(() => items = r.objs('items'));
    }).catchError((_) {
      if (mounted) setState(() => items = const []);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('خرید، تغییر کانفیگ، انتقال و بقیه کارهایی که از حسابت انجام شده.', style: t(12, c: C.n400, h: 1.6)),
        const Gap(12),
        if (items == null)
          Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Text('در حال بارگذاری…', textAlign: TextAlign.center, style: t(12, c: C.n500)))
        else if (items!.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Text('هنوز فعالیتی ثبت نشده.', textAlign: TextAlign.center, style: t(12, c: C.n500)))
        else
          ActivityLogRows(items: items!, showActor: false),
      ],
    );
  }
}

/// profile-sheet.tsx `TrialAccountSheet` (shown after claiming the free trial).
Future<void> openTrialSheet(BuildContext context, J trial) => showTgSheet(
      context,
      title: 'حساب تست رایگان 🎁',
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: C.a(C.emerald500, 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: C.a(C.emerald500, 0.25)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: C.a(C.emerald500, 0.15),
                      border: Border.all(color: C.a(C.emerald400, 0.3)),
                    ),
                    child: Icon(Icons.inventory_2_outlined, size: 32, color: C.emerald300),
                  ),
                  const Gap(12),
                  Text(trial.s('message'), textAlign: TextAlign.center, style: t(14, c: C.n100, h: 1.6)),
                  const Gap(12),
                  Wrap(
                    spacing: 8,
                    children: [
                      MiniChip('${faNum(trial.i('duration_days'))} روز'),
                      MiniChip(trial.s('traffic_label')),
                    ],
                  ),
                ],
              ),
            ),
            const Gap(16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: C.b(30), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(10))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('شناسه کانفیگ', style: t(11, c: C.n500)),
                  Text(trial.s('email'), textDirection: TextDirection.ltr, style: t(12, c: C.n100, mono: true)),
                ],
              ),
            ),
            Builder(
              builder: (_) {
                // Hiddify must fetch an HTTP(S) subscription URL — not a raw vless:// share link.
                final subUrl = trial.text('subscription_url');
                final links = trial.strs('links');
                final connectUrl = (subUrl != null && subUrl.trim().isNotEmpty)
                    ? subUrl.trim()
                    : links.cast<String?>().firstWhere(
                          (l) => l != null && (l.startsWith('http://') || l.startsWith('https://')),
                          orElse: () => links.isNotEmpty ? links.first : null,
                        );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (connectUrl != null && connectUrl.isNotEmpty) ...[
                      const Gap(16),
                      TgButton(
                        label: 'اتصال در همین برنامه',
                        icon: Icons.power_settings_new_rounded,
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          connectInApp(ref, connectUrl, name: 'حساب تست');
                        },
                      ),
                    ],
                    if (links.isNotEmpty) ...[
                      const Gap(8),
                      for (final link in links) ...[
                        TgButton(
                          label: link,
                          variant: BtnVariant.outline,
                          fontSize: 11,
                          icon: Icons.copy_rounded,
                          onPressed: () => Clipboard.setData(ClipboardData(text: link))
                              .then((_) => notify('کپی شد', ToastStatus.success)),
                        ),
                        const Gap(6),
                      ],
                    ],
                  ],
                );
              },
            ),
            const Gap(10),
            Row(
              children: [
                Expanded(
                  child: TgButton(
                    label: 'داشبورد',
                    variant: BtnVariant.outline,
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      ref.read(blControllerProvider).switchTab(BLTab.subs);
                    },
                  ),
                ),
                const Gap(8),
                Expanded(child: TgButton(label: 'باشه', variant: BtnVariant.outline, onPressed: () => Navigator.of(ctx).pop())),
              ],
            ),
          ],
        ),
      ),
    );
