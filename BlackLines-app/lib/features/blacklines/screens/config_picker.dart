import 'package:flutter/material.dart';
import 'package:hiddify/features/blacklines/core/format.dart';
import 'package:hiddify/features/blacklines/screens/connect_screen.dart';
import 'package:hiddify/features/blacklines/state/controller.dart';
import 'package:hiddify/features/blacklines/ui/kit.dart';
import 'package:hiddify/features/blacklines/ui/tokens.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum _Section { servers, configs }

/// Pick which subscription (profile) is active and which server inside it carries traffic.
Future<void> openConfigPicker(BuildContext context) => showTgSheet(
      context,
      title: 'انتخاب کانفیگ',
      description: 'کانفیگ و سروری که از آن وصل می‌شوید',
      builder: (_) => const _ConfigPicker(),
    );

/// "حجم نامحدود · ۲ روز" style summary for a profile.
String profileSubtitle(ProfileEntity? p) {
  if (p == null) return 'یک کانفیگ انتخاب کنید';
  final sub = p is RemoteProfileEntity ? p.subInfo : null;
  if (sub == null) return p is RemoteProfileEntity ? 'لینک اشتراک' : 'کانفیگ دستی';
  if (sub.isExpired) return 'منقضی شده';
  final parts = <String>[];
  // Panels report "unlimited" as an absurd total (petabytes).
  const unlimited = 1 << 49; // ~560 TB
  if (sub.total >= unlimited) {
    parts.add('حجم نامحدود');
  } else if (sub.total > 0) {
    parts.add('${bytesLabel(sub.remainingBW.clamp(0, sub.total))} باقی‌مانده');
  }
  final days = sub.remaining.inDays;
  if (days < 3650) parts.add('${faNum(days)} روز');
  return parts.isEmpty ? 'لینک اشتراک' : parts.join(' · ');
}

/// Server label without the `<profile name> · ` prefix and the "§ n" suffix.
String serverLabel(OutboundInfo o) {
  if (o.isGroup) {
    return switch (o.tag) {
      'lowest' => 'خودکار — کمترین پینگ',
      'balance' => 'خودکار — تقسیم بار',
      _ => o.tagDisplay.isEmpty ? o.tag : o.tagDisplay,
    };
  }
  var s = (o.tagDisplay.isEmpty ? o.tag : o.tagDisplay).replaceAll(RegExp(r'\s*§.*$'), '').trim();
  final dot = s.indexOf(' · ');
  if (dot > 0 && dot < s.length - 3) s = s.substring(dot + 3);
  return s;
}

bool _visible(OutboundInfo o) => !o.tag.contains('§hide§');

class _ConfigPicker extends ConsumerStatefulWidget {
  const _ConfigPicker();

  @override
  ConsumerState<_ConfigPicker> createState() => _ConfigPickerState();
}

class _ConfigPickerState extends ConsumerState<_ConfigPicker> {
  late _Section section =
      ref.read(connectionNotifierProvider).valueOrNull is Connected ? _Section.servers : _Section.configs;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Segmented<_Section>(
          items: const [(_Section.servers, 'سرورها'), (_Section.configs, 'کانفیگ‌ها')],
          value: section,
          onChanged: (v) => setState(() => section = v),
        ),
        const Gap(14),
        if (section == _Section.servers) const _Servers() else const _Configs(),
      ],
    );
  }
}

class _Servers extends ConsumerStatefulWidget {
  const _Servers();

  @override
  ConsumerState<_Servers> createState() => _ServersState();
}

class _ServersState extends ConsumerState<_Servers> {
  bool testing = false;
  String? switching;

  Future<void> _test(String group) async {
    setState(() => testing = true);
    try {
      await ref.read(proxiesOverviewNotifierProvider.notifier).urlTest(group);
    } catch (_) {
      notify('تست پینگ ناموفق بود', ToastStatus.error);
    } finally {
      if (mounted) setState(() => testing = false);
    }
  }

  Future<void> _select(String group, String tag) async {
    setState(() => switching = tag);
    try {
      await ref.read(proxiesOverviewNotifierProvider.notifier).changeProxy(group, tag);
    } catch (_) {
      notify('تغییر سرور ناموفق بود', ToastStatus.error);
    } finally {
      if (mounted) setState(() => switching = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = ref.watch(connectionNotifierProvider).valueOrNull is Connected;
    if (!connected) {
      return EmptyState(
        message: 'لیست سرورها بعد از اتصال نمایش داده می‌شود.\nابتدا وصل شوید، سپس سرور دلخواه را انتخاب کنید.',
        actions: [
          TgButton(
            label: 'اتصال',
            icon: Icons.power_settings_new_rounded,
            onPressed: () {
              Navigator.of(context).pop();
              ref.read(connectionNotifierProvider.notifier).toggleConnection();
            },
          ),
        ],
      );
    }
    final group = ref.watch(proxiesOverviewNotifierProvider);
    return switch (group) {
      AsyncData(value: final g?) => _list(g),
      AsyncError() => const EmptyState(message: 'دریافت لیست سرورها ممکن نشد'),
      _ => const OrbLoaderPanel(),
    };
  }

  Widget _list(OutboundGroup g) {
    final items = g.items.where(_visible).toList();
    // Automatic groups first, then the individual servers.
    items.sort((a, b) => (b.isGroup ? 1 : 0) - (a.isGroup ? 1 : 0));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('${faNum(items.length)} سرور', style: t(12, c: C.n400))),
            SizedBox(
              width: 132,
              child: TgButton(
                label: testing ? 'در حال تست…' : 'تست پینگ همه',
                icon: testing ? null : Icons.speed_rounded,
                variant: BtnVariant.outline,
                height: 32,
                fontSize: 12,
                onPressed: testing ? null : () => _test(g.tag),
              ),
            ),
          ],
        ),
        const Gap(10),
        for (final o in items) ...[
          _ServerRow(
            info: o,
            selected: g.selected == o.tag,
            busy: switching == o.tag,
            onTap: switching != null || g.selected == o.tag ? null : () => _select(g.tag, o.tag),
          ),
          const Gap(8),
        ],
      ],
    );
  }
}

class _ServerRow extends StatelessWidget {
  const _ServerRow({required this.info, required this.selected, required this.busy, this.onTap});

  final OutboundInfo info;
  final bool selected;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final delay = info.urlTestDelay;
    final (delayText, delayColor) = switch (delay) {
      <= 0 => ('—', C.n500),
      > 65000 => ('×', C.red300),
      < 800 => ('${faNum(delay)} ms', C.emerald300),
      _ => ('${faNum(delay)} ms', C.amber300),
    };
    final sub = info.isGroup
        ? (info.groupSelectedTagDisplay.trim().isEmpty ? 'انتخاب خودکار' : 'فعلاً: ${info.groupSelectedTagDisplay.replaceAll(RegExp(r'\s*§.*$'), '').trim()}')
        : info.type;
    return Panel(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      borderColor: selected ? C.w(40) : null,
      child: Row(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: busy
                ? CircularProgressIndicator(strokeWidth: 2, color: C.foreground)
                : Icon(
                    selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                    size: 22,
                    color: selected ? C.foreground : C.n500,
                  ),
          ),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  serverLabel(info),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: info.isGroup ? null : TextDirection.ltr,
                  style: t(14, w: selected ? 700 : 500),
                ),
                const Gap(2),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: t(11, c: C.n500)),
              ],
            ),
          ),
          const Gap(8),
          Text(delayText, textDirection: TextDirection.ltr, style: t(12, w: 600, c: delayColor)),
        ],
      ),
    );
  }
}

class _Configs extends ConsumerWidget {
  const _Configs();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(blControllerProvider);
    final profiles = ref.watch(profilesNotifierProvider);
    final footer = [
      const Gap(4),
      TgButton(
        label: 'افزودن لینک اشتراک',
        icon: Icons.add_link_rounded,
        variant: BtnVariant.outline,
        height: 40,
        fontSize: 13,
        onPressed: () {
          Navigator.of(context).pop();
          openAddLinkSheet(context);
        },
      ),
      if (c.auth == AuthPhase.loggedIn) ...[
        const Gap(8),
        TgButton(
          label: 'کانفیگ‌های حساب من',
          icon: Icons.dns_outlined,
          variant: BtnVariant.ghost,
          height: 40,
          fontSize: 13,
          onPressed: () {
            Navigator.of(context).pop();
            c.switchTab(BLTab.subs);
          },
        ),
      ],
    ];
    return switch (profiles) {
      AsyncData(value: final list) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (list.isEmpty)
              const EmptyState(message: 'هنوز کانفیگی اضافه نشده است')
            else
              for (final p in list) ...[_ConfigRow(profile: p), const Gap(8)],
            ...footer,
          ],
        ),
      AsyncError() => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [const EmptyState(message: 'خواندن کانفیگ‌ها ممکن نشد'), ...footer],
        ),
      _ => const OrbLoaderPanel(),
    };
  }
}

class _ConfigRow extends ConsumerWidget {
  const _ConfigRow({required this.profile});

  final ProfileEntity profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = profile;
    final notifier = ref.read(profilesNotifierProvider.notifier);
    return Panel(
      onTap: p.active
          ? null
          : () async {
              try {
                await notifier.selectActiveProfile(p.id);
                notify('«${p.name}» انتخاب شد', ToastStatus.success);
              } catch (_) {
                notify('انتخاب کانفیگ ناموفق بود', ToastStatus.error);
              }
            },
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      borderColor: p.active ? C.w(40) : null,
      child: Row(
        children: [
          Icon(
            p.active ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
            size: 22,
            color: p.active ? C.foreground : C.n500,
          ),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t(14, w: p.active ? 700 : 500)),
                const Gap(2),
                Text(profileSubtitle(p), style: t(11, c: C.n500)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'حذف',
            icon: Icon(Icons.delete_outline_rounded, size: 20, color: C.n500),
            onPressed: () async {
              final ok = await confirmSheet(
                context,
                title: 'حذف کانفیگ',
                message: '«${p.name}» از این دستگاه حذف شود؟ اشتراک شما در حساب باقی می‌ماند.',
                confirm: 'حذف',
                destructive: true,
              );
              if (ok) await notifier.deleteProfile(p);
            },
          ),
        ],
      ),
    );
  }
}
