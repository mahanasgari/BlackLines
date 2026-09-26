import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hiddify/features/blacklines/core/api.dart';
import 'package:hiddify/features/blacklines/core/format.dart';
import 'package:hiddify/features/blacklines/core/json.dart';
import 'package:hiddify/features/blacklines/state/controller.dart';
import 'package:hiddify/features/blacklines/ui/kit.dart';
import 'package:hiddify/features/blacklines/ui/tokens.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// admin-activity-log.tsx `formatActivityWhen`.
String activityWhen(String? iso) {
  final d = iso == null ? null : DateTime.tryParse(iso);
  if (d == null) return '—';
  final diff = DateTime.now().difference(d.toLocal()).inSeconds;
  if (diff < 45) return 'همین الان';
  if (diff < 3600) return '${faNum((diff / 60).floor().clamp(1, 59))} دقیقه پیش';
  if (diff < 86400) return '${faNum((diff / 3600).floor())} ساعت پیش';
  if (diff < 86400 * 7) return '${faNum((diff / 86400).floor())} روز پیش';
  return formatDateFa(iso);
}

/// `ActivityLogRows`.
class ActivityLogRows extends StatelessWidget {
  const ActivityLogRows({super.key, required this.items, this.showActor = true});

  final List<J> items;
  final bool showActor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: C.b(35), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(10))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 4,
                        children: [
                          switch (item.s('actor_role')) {
                            'admin' => const Tag('ادمین', tone: Tone.amber),
                            'system' => const Tag('سیستم'),
                            _ => const Tag('کاربر', tone: Tone.sky),
                          },
                          if (item.text('category_label') != null) Tag(item.s('category_label')),
                        ],
                      ),
                      const Gap(4),
                      Text(item.s('action_label'), style: t(13, w: 600, c: C.n50)),
                      if (showActor) Text(item.s('actor_name'), overflow: TextOverflow.ellipsis, style: t(11, c: C.n400)),
                      if (item.text('target_name') != null)
                        Text('روی ${item.s('target_name')}', overflow: TextOverflow.ellipsis, style: t(11, c: C.n500)),
                      if (item.text('detail') != null) ...[
                        const Gap(4),
                        Text(item.s('detail'), textDirection: TextDirection.ltr, style: t(10, c: C.n500, h: 1.6)),
                      ],
                    ],
                  ),
                ),
                const Gap(8),
                Text(activityWhen(item.text('created_at')), style: t(10, c: C.n500)),
              ],
            ),
          ),
          const Gap(8),
        ],
      ],
    );
  }
}

/// `AdminActivityLogPanel`.
class AdminActivityLogPanel extends ConsumerStatefulWidget {
  const AdminActivityLogPanel({super.key});

  @override
  ConsumerState<AdminActivityLogPanel> createState() => _AdminActivityLogPanelState();
}

class _AdminActivityLogPanelState extends ConsumerState<AdminActivityLogPanel> {
  List<J> items = const [];
  int total = 0;
  bool loading = true;
  bool loadingMore = false;
  String? error;
  String q = '';
  String actorKind = '';
  String category = '';
  bool includeTest = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      more ? loadingMore = true : loading = true;
      error = null;
    });
    try {
      final r = await ref.read(blControllerProvider).api.adminAuditLog(
            limit: 50,
            offset: more ? items.length : 0,
            q: q.trim(),
            actorKind: actorKind,
            category: category,
            includeTest: includeTest,
          );
      if (!mounted) return;
      setState(() {
        items = more ? [...items, ...r.objs('items')] : r.objs('items');
        total = r.i('total');
      });
    } catch (e) {
      if (mounted) setState(() => error = persianError(e));
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
          loadingMore = false;
        });
      }
    }
  }

  Widget _filters(List<(String, String)> list, String value, ValueChanged<String> on, {bool small = false}) => SizedBox(
        height: small ? 28 : 32,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final (id, label) in list)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 4),
                child: GestureDetector(
                  onTap: () {
                    on(id);
                    _load();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: value == id ? C.w(12) : C.b(30),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: value == id ? C.w(20) : C.w(10)),
                    ),
                    child: Center(widthFactor: 1, child: Text(label, style: t(small ? 10 : 11, w: 600, c: value == id ? C.white : C.n400))),
                  ),
                ),
              ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: C.w(5), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.w(12))),
              child: Icon(Icons.receipt_long_outlined, size: 16, color: C.n200),
            ),
            const Gap(8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('گزارش فعالیت‌ها', style: t(14, w: 600)),
                  Text(
                    'هر کار کاربر، ادمین یا ربات اینجا ثبت می‌شود${total > 0 ? ' · ${faNum(total)} مورد' : ''}',
                    style: t(11, c: C.n400),
                  ),
                ],
              ),
            ),
          ],
        ),
        const Gap(12),
        BLInput(
          hint: 'جستجو: عمل، جزئیات، مسیر…',
          prefixIcon: Icons.search_rounded,
          onChanged: (v) {
            q = v;
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 280), _load);
          },
        ),
        const Gap(8),
        GestureDetector(
          onTap: () {
            setState(() => includeTest = !includeTest);
            _load();
          },
          child: Row(
            children: [
              SizedBox(width: 24, height: 24, child: Checkbox(value: includeTest, onChanged: (_) {})),
              const Gap(6),
              Text('نمایش فعالیت کاربران تست', style: t(11, c: C.n400)),
            ],
          ),
        ),
        const Gap(8),
        _filters(const [('', 'همه'), ('user', 'کاربر'), ('admin', 'ادمین'), ('system', 'سیستم')], actorKind, (v) => actorKind = v),
        const Gap(6),
        _filters(
          const [
            ('', 'همه'),
            ('shop', 'فروشگاه'),
            ('config', 'کانفیگ'),
            ('wallet', 'کیف‌پول'),
            ('family', 'خانواده'),
            ('chat', 'گفتگو'),
            ('profile', 'پروفایل'),
            ('admin', 'تنظیمات'),
          ],
          category,
          (v) => category = v,
          small: true,
        ),
        const Gap(12),
        if (loading) const OrbLoaderPanel(message: 'در حال بارگذاری لاگ…'),
        if (error != null) Callout(error!, tone: Tone.red),
        if (!loading && items.isEmpty && error == null) const EmptyState(message: 'هنوز فعالیتی ثبت نشده.'),
        if (!loading) ActivityLogRows(items: items),
        if (!loading && items.length < total)
          TgButton(
            label: loadingMore ? '…' : 'موارد بیشتر · ${faNum(total - items.length)} باقی',
            variant: BtnVariant.outline,
            onPressed: loadingMore ? null : () => _load(more: true),
          ),
      ],
    );
  }
}
