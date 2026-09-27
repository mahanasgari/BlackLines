import 'package:flutter/material.dart';
import 'package:hiddify/features/blacklines/core/api.dart';
import 'package:hiddify/features/blacklines/core/format.dart';
import 'package:hiddify/features/blacklines/core/json.dart';
import 'package:hiddify/features/blacklines/state/controller.dart';
import 'package:hiddify/features/blacklines/ui/kit.dart';
import 'package:hiddify/features/blacklines/ui/tokens.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// family-parental-section.tsx.
class FamilyParentalSection extends ConsumerStatefulWidget {
  const FamilyParentalSection({super.key, required this.detail, required this.onDetailChange});

  final J detail;
  final ValueChanged<J> onDetailChange;

  @override
  ConsumerState<FamilyParentalSection> createState() => _FamilyParentalSectionState();
}

class _FamilyParentalSectionState extends ConsumerState<FamilyParentalSection> {
  int? editChildId;
  List<String> editCats = [];
  bool scheduleOn = false;
  String start = '21:00';
  String end = '07:00';
  bool vpnOn = false;
  String vpnStart = '08:00';
  String vpnEnd = '21:00';
  bool busy = false;
  String? toast;

  J get family => widget.detail.obj('family');

  void _flash(String msg) {
    setState(() => toast = msg);
    Future<void>.delayed(const Duration(milliseconds: 1800), () {
      if (mounted && toast == msg) setState(() => toast = null);
    });
  }

  void _patchMember(int id, Map<String, dynamic> patch) {
    final members = [for (final m in family.objs('members')) m.i('id') == id ? m.merge(patch).raw : m.raw];
    widget.onDetailChange(widget.detail.merge({'family': family.merge({'members': members}).raw}));
  }

  Map<String, dynamic> _sched(String s, String e) => {'enabled': true, 'start': s, 'end': e, 'days': [0, 1, 2, 3, 4, 5, 6]};

  Future<void> _save(int childId) async {
    setState(() => busy = true);
    try {
      final res = await ref.read(blControllerProvider).api.restrictFamilyChild(
            widget.detail.i('id'),
            childId,
            editCats,
            schedule: scheduleOn ? _sched(start, end) : null,
            vpnSchedule: vpnOn ? _sched(vpnStart, vpnEnd) : null,
          );
      final ch = res.obj('child');
      _patchMember(childId, {
        for (final k in const [
          'parental_categories',
          'restricted',
          'schedule',
          'schedule_label',
          'schedule_active',
          'vpn_schedule',
          'vpn_schedule_label',
          'vpn_allowed_now',
          'vpn_schedule_paused',
        ])
          k: ch[k],
      });
      setState(() => editChildId = null);
      haptic();
      final bits = [
        if (ch.text('vpn_schedule_label') != null) 'VPN: ${ch.s('vpn_schedule_label')}',
        if (ch.b('restricted')) 'سایت‌ها محدود شد' else if (ch.text('vpn_schedule_label') == null) 'محدودیت برداشته شد',
      ];
      _flash(bits.isEmpty ? 'ذخیره شد' : bits.join(' · '));
    } catch (e) {
      _flash(persianError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _pause(int childId, {required bool resume}) async {
    setState(() => busy = true);
    final api = ref.read(blControllerProvider).api;
    try {
      final res = resume
          ? await api.resumeFamilyChild(widget.detail.i('id'), childId)
          : await api.pauseFamilyChild(widget.detail.i('id'), childId);
      final ch = res.obj('child');
      _patchMember(childId, {
        for (final k in const ['pause_until', 'pause_active', 'vpn_allowed_now', 'vpn_schedule_paused']) k: ch[k],
      });
      haptic();
      _flash(resume ? 'VPN فرزند دوباره فعال شد' : 'VPN فرزند برای ${faNum(24)} ساعت متوقف شد');
    } catch (e) {
      _flash(persianError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _startEdit(J m) {
    final s = m.objOrNull('schedule');
    final v = m.objOrNull('vpn_schedule');
    setState(() {
      editChildId = m.i('id');
      editCats = [...m.strs('parental_categories')];
      scheduleOn = s?.b('enabled') ?? false;
      start = s?.text('start') ?? '21:00';
      end = s?.text('end') ?? '07:00';
      vpnOn = v?.b('enabled') ?? false;
      vpnStart = v?.text('start') ?? '08:00';
      vpnEnd = v?.text('end') ?? '21:00';
    });
  }

  @override
  Widget build(BuildContext context) {
    final f = family;
    final members = f.objs('members');
    final children = members.where((m) => !m.b('is_parent')).toList();
    final restricted = children.where((m) => m.b('restricted')).length;
    final categories = f.obj('parental').objs('categories');
    final isParent = f.b('is_parent');

    Widget count(String v, String label, {Color? color}) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(color: C.b(30), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(8))),
            child: Column(
              children: [
                Text(v, style: t(14, w: 700, c: color ?? C.n100)),
                Text(label, style: t(9, c: C.n500)),
              ],
            ),
          ),
        );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: C.w(10)),
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [C.w(4), C.b(30)]),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: C.w(8)))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: C.w(5), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(12))),
                      child: Icon(Icons.group_outlined, size: 16, color: C.n200),
                    ),
                    const Gap(10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('کنترل والدین', style: t(14, w: 700, c: C.n50)),
                              const Gap(8),
                              Tag(isParent ? 'مدیریت فعال' : 'کانفیگ فرزند', tone: isParent ? Tone.emerald : Tone.neutral),
                            ],
                          ),
                          const Gap(4),
                          Text(
                            isParent
                                ? 'برای هر فرزند سایت‌ها را محدود کنید، ساعت مجاز VPN بگذارید، توقف موقت بزنید، و گزارش بازدید را ببینید.'
                                : 'محدودیت‌ها و گزارش این کانفیگ فقط برای والد خانواده است.',
                            style: t(11, c: C.n400, h: 1.6),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Gap(12),
                Row(
                  children: [
                    count(f.text('used_label') ?? '—', 'مصرف کل'),
                    const Gap(6),
                    count(faNum(children.length), 'فرزند'),
                    const Gap(6),
                    count(faNum(restricted), 'محدود شده', color: restricted > 0 ? C.rose300 : C.emerald300),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final m in members) ...[
                  _MemberCard(
                    member: m,
                    categories: categories,
                    isParentViewer: isParent,
                    editing: editChildId == m.i('id'),
                    busy: busy,
                    onStartEdit: () => _startEdit(m),
                    onActivity: () => _openActivity(context, m),
                    onPause: () => _pause(m.i('id'), resume: false),
                    onResume: () => _pause(m.i('id'), resume: true),
                    editor: editChildId == m.i('id') ? _editor(m, categories) : null,
                  ),
                  const Gap(8),
                ],
                if (!isParent)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(color: C.b(25), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(8))),
                    child: Row(
                      children: [
                        Icon(Icons.check_rounded, size: 14, color: C.n400),
                        const Gap(8),
                        Expanded(
                          child: Text(
                            'برای تغییر محدودیت‌ها، کانفیگ والد را از لیست اشتراک‌ها باز کنید.',
                            style: t(11, c: C.n400, h: 1.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (toast != null) Text(toast!, textAlign: TextAlign.center, style: t(11, c: C.emerald300)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _pickTime(String current) async {
    final parts = current.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.tryParse(parts.first) ?? 0, minute: int.tryParse(parts.last) ?? 0),
      builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (picked == null) return null;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(picked.hour)}:${two(picked.minute)}';
  }

  Widget _timeRow(String from, String to, ValueChanged<String> onFrom, ValueChanged<String> onTo) {
    Widget field(String label, String value, ValueChanged<String> on) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: t(10, c: C.n500)),
              const Gap(4),
              GestureDetector(
                onTap: () async {
                  final v = await _pickTime(value);
                  if (v != null) on(v);
                },
                child: Container(
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: C.b(40), borderRadius: BorderRadius.circular(8), border: Border.all(color: C.w(12))),
                  child: Text(faDigits(value), style: t(14, c: C.white)),
                ),
              ),
            ],
          ),
        );
    return Row(children: [field('از', from, onFrom), const Gap(8), field('تا', to, onTo)]);
  }

  Widget _editor(J m, List<J> categories) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: C.b(25), border: Border(top: BorderSide(color: C.w(8)))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('چه چیزهایی مسدود شود؟', style: t(12, w: 600, c: C.n100)),
          const Gap(2),
          Text('موارد انتخاب‌شده روی سرور برای این فرزند قطع می‌شوند.', style: t(10, c: C.n500, h: 1.6)),
          const Gap(10),
          for (final cat in categories) ...[
            _CategoryChip(
              cat: cat,
              active: editCats.contains(cat.s('key')),
              disabled: busy,
              onToggle: () => setState(() {
                final k = cat.s('key');
                editCats.contains(k) ? editCats.remove(k) : editCats.add(k);
              }),
            ),
            const Gap(6),
          ],
          const Gap(4),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: C.a(C.sky500, 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: C.a(C.sky500, 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CheckRow(
                  value: vpnOn,
                  onChanged: (v) => setState(() => vpnOn = v),
                  icon: Icons.schedule_rounded,
                  label: 'VPN فقط در این ساعت‌ها کار کند',
                  color: C.sky50,
                ),
                if (vpnOn) ...[
                  const Gap(8),
                  _timeRow(vpnStart, vpnEnd, (v) => setState(() => vpnStart = v), (v) => setState(() => vpnEnd = v)),
                ],
                const Gap(6),
                Text(
                  vpnOn
                      ? 'مثلاً ۰۸:۰۰ تا ۲۱:۰۰ — بیرون از این بازه VPN فرزند کلاً قطع می‌شود (ساعت تهران).'
                      : 'بدون این گزینه، VPN فرزند همیشه روشن است (مگر منقضی یا قطع‌شده).',
                  style: t(10, c: vpnOn ? C.a(C.sky100, 0.7) : C.n500, h: 1.6),
                ),
              ],
            ),
          ),
          const Gap(8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: C.b(30), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(10))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CheckRow(
                  value: scheduleOn,
                  onChanged: (v) => setState(() => scheduleOn = v),
                  label: 'فقط در این ساعت‌ها سایت‌ها مسدود شوند',
                  color: C.n200,
                ),
                if (scheduleOn) ...[
                  const Gap(8),
                  _timeRow(start, end, (v) => setState(() => start = v), (v) => setState(() => end = v)),
                  const Gap(6),
                  Text(
                    'مثلاً ۲۱:۰۰ تا ۰۷:۰۰ یعنی شب اینستاگرام قطع؛ بیرون از این ساعت سایت‌ها آزادند. VPN خودش روشن می‌ماند مگر گزینه بالا را زده باشی.',
                    style: t(10, c: C.n500, h: 1.6),
                  ),
                ],
              ],
            ),
          ),
          const Gap(8),
          Row(
            children: [
              Expanded(child: Text('${faNum(editCats.length)} مورد انتخاب شده', style: t(10, c: C.n500))),
              if (editCats.isNotEmpty)
                GestureDetector(
                  onTap: busy ? null : () => setState(() => editCats = []),
                  child: Text('پاک کردن همه', style: t(10, c: C.a(C.rose300, 0.9))),
                ),
            ],
          ),
          const Gap(8),
          Row(
            children: [
              Expanded(
                child: TgButton(
                  label: busy ? 'در حال اعمال…' : 'اعمال محدودیت',
                  height: 40,
                  fontSize: 12,
                  onPressed: busy ? null : () => _save(m.i('id')),
                ),
              ),
              const Gap(8),
              TgButton(
                label: 'انصراف',
                variant: BtnVariant.outline,
                height: 40,
                fontSize: 12,
                expand: false,
                onPressed: busy ? null : () => setState(() => editChildId = null),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openActivity(BuildContext context, J child) {
    showTgSheet(
      context,
      title: 'گزارش ${child.text('label') ?? child.text('email') ?? 'فرزند'}',
      builder: (_) => _FamilyActivity(parentId: widget.detail.i('id'), childId: child.i('id')),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.value, required this.onChanged, required this.label, required this.color, this.icon});

  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => onChanged(!value),
        child: Row(
          children: [
            SizedBox(width: 24, height: 24, child: Checkbox(value: value, onChanged: (v) => onChanged(v ?? false))),
            const Gap(6),
            if (icon != null) ...[Icon(icon, size: 14, color: color), const Gap(4)],
            Expanded(child: Text(label, style: t(12, c: color))),
          ],
        ),
      );
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.cat, required this.active, required this.disabled, required this.onToggle});

  final J cat;
  final bool active;
  final bool disabled;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: disabled ? 0.5 : 1,
        child: GestureDetector(
          onTap: disabled
              ? null
              : () {
                  haptic();
                  onToggle();
                },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: active ? C.a(C.rose500, 0.15) : C.b(35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: active ? C.a(C.rose300, 0.35) : C.w(10)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      active ? Icons.remove_moderator_outlined : Icons.shield_outlined,
                      size: 14,
                      color: active ? C.rose100 : C.a(C.n300, 0.5),
                    ),
                    const Gap(4),
                    Text(cat.s('label'), style: t(12, w: 600, c: active ? C.rose100 : C.n300)),
                  ],
                ),
                const Gap(2),
                Text(cat.s('desc'), style: t(10, c: active ? C.a(C.rose200, 0.7) : C.n500, h: 1.4)),
              ],
            ),
          ),
        ),
      );
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.member,
    required this.categories,
    required this.isParentViewer,
    required this.editing,
    required this.busy,
    required this.onStartEdit,
    required this.onActivity,
    required this.onPause,
    required this.onResume,
    this.editor,
  });

  final J member;
  final List<J> categories;
  final bool isParentViewer;
  final bool editing;
  final bool busy;
  final VoidCallback onStartEdit;
  final VoidCallback onActivity;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final Widget? editor;

  Widget _action(String label, Tone tone, VoidCallback? onTap, {IconData? icon}) {
    final (bg, border, fg) = toneColors(tone);
    return GestureDetector(
      onTap: onTap == null
          ? null
          : () {
              haptic();
              onTap();
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 12, color: fg), const Gap(4)],
            Text(label, style: t(11, w: 500, c: fg)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = member;
    final parent = m.b('is_parent');
    final labels = m.strs('parental_categories').map((k) {
      final hit = categories.where((c) => c.s('key') == k);
      return hit.isEmpty ? k : hit.first.s('label');
    }).toList();
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: parent
            ? C.a(C.sky500, 0.1)
            : m.b('restricted')
                ? C.a(C.rose500, 0.05)
                : C.b(30),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: parent
              ? C.a(C.sky500, 0.2)
              : m.b('restricted')
                  ? C.a(C.rose500, 0.2)
                  : C.w(10),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: parent ? C.a(C.sky500, 0.15) : C.w(5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: parent ? C.a(C.sky500, 0.25) : C.w(10)),
                  ),
                  child: Icon(parent ? Icons.person_outline_rounded : Icons.shield_outlined, size: 16, color: parent ? C.sky200 : C.n300),
                ),
                const Gap(10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(m.text('label') ?? m.s('email'), style: t(13, w: 600, c: C.n50)),
                          Tag(parent ? 'والد' : 'فرزند', tone: parent ? Tone.sky : Tone.neutral),
                        ],
                      ),
                      const Gap(2),
                      Text(m.s('email'), textDirection: TextDirection.ltr, style: t(10, c: C.n500, mono: true)),
                      const Gap(4),
                      Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'مصرف: ${m.text('used_label') ?? '۰'}${m.text('total_label') != null ? ' / ${m.s('total_label')}' : ''}',
                            style: t(11, c: C.n300),
                          ),
                          if (m.b('online')) const Tag('آنلاین', tone: Tone.emerald),
                        ],
                      ),
                      const Gap(6),
                      if (parent)
                        Text('این کانفیگ کنترل محدودیت‌ها را دارد', style: t(11, c: C.a(C.sky200, 0.8)))
                      else ...[
                        if (labels.isNotEmpty)
                          Wrap(spacing: 4, runSpacing: 4, children: [for (final l in labels) Tag('مسدود · $l', tone: Tone.rose)])
                        else
                          Text('دسترسی آزاد — محدودیتی نیست', style: t(11, c: C.a(C.emerald300, 0.9))),
                        if (m.text('vpn_schedule_label') != null) ...[
                          const Gap(4),
                          Text(
                            'VPN فقط ${m.s('vpn_schedule_label')}${m.boolOrNull('vpn_allowed_now') == false ? ' · الان قطع' : ' · الان مجاز'}',
                            style: t(10, c: C.a(C.sky200, 0.9)),
                          ),
                        ],
                        if (m.b('pause_active') || m.text('pause_until') != null) ...[
                          const Gap(4),
                          Text(
                            '${m.b('pause_active') ? 'توقف موقت VPN فعال است' : 'توقف زمان‌بندی‌شده'}'
                            '${m.text('pause_until') != null ? ' تا ${formatDateFa(m.text('pause_until'))}' : ''}',
                            style: t(10, c: C.a(C.amber200, 0.9)),
                          ),
                        ],
                        if (m.text('schedule_label') != null) ...[
                          const Gap(4),
                          Text(
                            'ساعت مسدودی سایت: ${m.s('schedule_label')}${m.boolOrNull('schedule_active') == false ? ' · الان آزاد' : ' · الان فعال'}',
                            style: t(10, c: C.a(C.amber200, 0.8)),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
                if (isParentViewer && !parent && !editing) ...[
                  const Gap(8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _action('گزارش', Tone.white, onActivity),
                      const Gap(6),
                      if (m.b('pause_active'))
                        _action('ادامه', Tone.emerald, busy ? null : onResume, icon: Icons.play_arrow_rounded)
                      else
                        _action('توقف ۱روز', Tone.amber, busy ? null : onPause, icon: Icons.pause_rounded),
                      const Gap(6),
                      _action('محدودیت', Tone.white, onStartEdit),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (editor != null) editor!,
        ],
      ),
    );
  }
}

class _FamilyActivity extends ConsumerStatefulWidget {
  const _FamilyActivity({required this.parentId, required this.childId});

  final int parentId;
  final int childId;

  @override
  ConsumerState<_FamilyActivity> createState() => _FamilyActivityState();
}

class _FamilyActivityState extends ConsumerState<_FamilyActivity> {
  J? data;
  bool loading = true;
  String? error;
  String tab = 'all';

  @override
  void initState() {
    super.initState();
    ref.read(blControllerProvider).api.familyChildActivity(widget.parentId, widget.childId).then((d) {
      if (mounted) setState(() => data = d);
    }).catchError((Object e) {
      if (mounted) setState(() => error = persianError(e));
    }).whenComplete(() {
      if (mounted) setState(() => loading = false);
    });
  }

  bool _match(J s) => switch (tab) {
        'blocked' => s.s('verdict') == 'blocked',
        'download' => s.s('category') == 'download',
        _ => true,
      };

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Text('در حال جمع‌آوری گزارش…', textAlign: TextAlign.center, style: t(14, c: C.n400)),
      );
    }
    if (error != null) return Text(error!, textAlign: TextAlign.center, style: t(14, c: C.orange300));
    final d = data!;
    final summary = d.obj('summary');
    final sites = d.objs('sites').where(_match).toList();
    final recent = d.objs('recent').where(_match).take(20).toList();
    Widget count(String v, String label, {Color? color}) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(color: C.b(30), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(10))),
            child: Column(children: [Text(v, style: t(15, w: 700, c: color)), Text(label, style: t(9, c: C.n500))]),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            count(faNum(summary.i('domains')), 'سایت'),
            const Gap(6),
            count(faNum(summary.i('blocked')), 'مسدود', color: C.rose200),
            const Gap(6),
            count(faNum(summary.i('downloads')), 'دانلود', color: C.sky200),
          ],
        ),
        const Gap(12),
        Text(d.s('disclaimer'), style: t(11, c: C.n500, h: 1.6)),
        const Gap(12),
        Row(
          children: [
            for (final (id, label) in const [('all', 'همه'), ('blocked', 'مسدود'), ('download', 'دانلود')]) ...[
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => tab = id),
                  child: Container(
                    height: 32,
                    decoration: BoxDecoration(
                      color: tab == id ? C.w(12) : C.b(30),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: tab == id ? C.w(20) : C.w(10)),
                    ),
                    child: Center(child: Text(label, style: t(11, w: 600, c: tab == id ? C.white : C.n400))),
                  ),
                ),
              ),
              if (id != 'download') const Gap(4),
            ],
          ],
        ),
        const Gap(12),
        if (sites.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(10))),
            child: Text(
              d.obj('logging').b('ready')
                  ? 'هنوز اتصالی برای این فرزند ثبت نشده. بعد از استفاده از VPN اینجا پر می‌شود.'
                  : 'گزارش‌گیری در حال فعال‌سازی است. چند دقیقه دیگر دوباره باز کنید.',
              textAlign: TextAlign.center,
              style: t(12, c: C.n500, h: 1.6),
            ),
          )
        else
          for (final s in sites) ...[
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
                            Text(s.s('domain'), textDirection: TextDirection.ltr, style: t(12, c: C.n100, mono: true)),
                            const Gap(4),
                            Wrap(
                              spacing: 4,
                              children: [
                                Tag(s.s('category_label')),
                                Tag(s.s('verdict_label'), tone: s.s('verdict') == 'blocked' ? Tone.rose : Tone.emerald),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Column(children: [Text(faNum(s.i('hit_count')), style: t(12, w: 600)), Text('بار', style: t(10, c: C.n500))]),
                    ],
                  ),
                  const Gap(6),
                  Text('آخرین ${relativeFa(s.date('last_seen'))}', style: t(10, c: C.n500)),
                ],
              ),
            ),
            const Gap(8),
          ],
        if (recent.isNotEmpty) ...[
          const Gap(4),
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 14, color: C.n400),
              const Gap(6),
              Text('فعالیت اخیر', style: t(11, w: 600, c: C.n400)),
            ],
          ),
          const Gap(6),
          for (final h in recent)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(h.s('domain'), textDirection: TextDirection.ltr, overflow: TextOverflow.ellipsis, style: t(11, c: C.n200, mono: true)),
                  ),
                  const Gap(8),
                  Text(relativeFa(h.date('seen_at')), style: t(11, c: C.n500)),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
