import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Public subscriptions every install gets, signed in or not, as a fallback
/// when the user's own config is unreachable.
const kDefaultProfiles = [
  // Hiddify's curated public "Mahsa" list (also offered in upstream's free configs).
  (name: 'مهسا', url: 'https://raw.githubusercontent.com/hiddify/hiddify-app/refs/heads/main/test.configs/mahsa'),
];

/// Adds [kDefaultProfiles] once per install. The user's active config stays
/// active, and a profile the user deleted is not re-added. Failures (e.g. the
/// feed is unreachable) are retried on the next launch.
final blDefaultProfilesProvider = FutureProvider<void>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final repo = await ref.read(profileRepositoryProvider.future);
  for (final d in kDefaultProfiles) {
    final doneKey = 'bl_default_profile_${d.url}';
    if (prefs.getBool(doneKey) ?? false) continue;

    final profiles = (await repo.watchAll().first).getOrElse((_) => const <ProfileEntity>[]);
    if (profiles.any((p) => p is RemoteProfileEntity && p.url == d.url)) {
      await prefs.setBool(doneKey, true);
      continue;
    }
    // New profiles are inserted as active; switching the active profile while
    // connected would reconnect the tunnel, so wait for a disconnected launch.
    final status = await ref.read(connectionNotifierProvider.future).catchError((_) => const Disconnected());
    if (status is! Disconnected) continue;

    final previous = profiles.where((p) => p.active).firstOrNull;
    final added = await repo.upsertRemote(d.url, userOverride: UserOverride(name: d.name)).run();
    if (added.isLeft()) continue;
    if (previous != null) await repo.setAsActive(previous.id).run();
    await prefs.setBool(doneKey, true);
  }
});
