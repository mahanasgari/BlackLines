import 'package:flutter/material.dart';
import 'package:hiddify/core/analytics/analytics_controller.dart';
import 'package:hiddify/core/model/region.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/blacklines/screens/shell.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Replaces Hiddify's intro: applies the defaults it used to ask about
/// (region Iran, no crash reporting to Hiddify), then shows the BlackLines app.
class BLFirstRun extends ConsumerStatefulWidget {
  const BLFirstRun({super.key});

  @override
  ConsumerState<BLFirstRun> createState() => _BLFirstRunState();
}

class _BLFirstRunState extends ConsumerState<BLFirstRun> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ref.read(ConfigOptions.region.notifier).update(Region.ir);
        await ref.read(analyticsControllerProvider.notifier).disableAnalytics();
      } catch (_) {}
      await ref.read(Preferences.introCompleted.notifier).update(true);
    });
  }

  @override
  Widget build(BuildContext context) => const BLShell();
}
