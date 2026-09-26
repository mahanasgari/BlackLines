import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/blacklines/core/api.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';

/// Imports a shop subscription URL (or raw share link) into Hiddify core and starts the tunnel.
class BlackLinesAutoConnect {
  BlackLinesAutoConnect(this.ref);
  final Ref ref;

  static bool _isHttpSubscription(String url) {
    final u = url.trim().toLowerCase();
    return u.startsWith('https://') || u.startsWith('http://');
  }

  Future<void> importAndConnect({
    required String subscriptionUrl,
    String? name,
  }) async {
    final url = subscriptionUrl.trim();
    if (url.isEmpty) {
      throw BLApiError('لینک اشتراک خالی است');
    }

    final repo = await ref.read(profileRepositoryProvider.future);
    final label = (name ?? 'BlackLines').trim().isEmpty ? 'BlackLines' : (name ?? 'BlackLines').trim();
    final override = UserOverride(name: label);

    // Remote HTTP(S) subscription feeds (shop `/shop/sub/...`) vs local share URIs (vless://…).
    if (_isHttpSubscription(url)) {
      final upsert = await repo.upsertRemote(url, userOverride: override).run();
      upsert.mapLeft((err) => throw err);
    } else {
      final local = await repo.addLocal(url, userOverride: override).run();
      local.mapLeft((err) => throw err);
    }

    final listEither = await repo.watchAll().first;
    final profiles = listEither.getOrElse((_) => <ProfileEntity>[]);

    ProfileEntity? match;
    if (_isHttpSubscription(url)) {
      for (final p in profiles) {
        if (p is RemoteProfileEntity && p.url == url) {
          match = p;
          break;
        }
      }
    }
    match ??= profiles.cast<ProfileEntity?>().firstWhere(
          (p) => p?.name == label,
          orElse: () => null,
        );
    if (match == null) {
      final remotes = profiles.whereType<RemoteProfileEntity>().toList()
        ..sort((a, b) => b.lastUpdate.compareTo(a.lastUpdate));
      if (remotes.isNotEmpty) {
        match = remotes.first;
      } else if (profiles.isNotEmpty) {
        final locals = profiles.toList()..sort((a, b) => b.lastUpdate.compareTo(a.lastUpdate));
        match = locals.first;
      }
    }
    if (match == null) {
      throw BLApiError('پروفایل پس از ایمپورت پیدا نشد');
    }

    final activate = await repo.setAsActive(match.id).run();
    activate.mapLeft((err) => throw err);

    await ref.read(Preferences.startedByUser.notifier).update(true);

    // Wait until activeProfileProvider sees the new profile (avoids "no active profile").
    for (var i = 0; i < 30; i++) {
      final active = await ref.read(activeProfileProvider.future);
      if (active?.id == match.id) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    final conn = ref.read(connectionNotifierProvider.notifier);
    final status = ref.read(connectionNotifierProvider).valueOrNull;
    if (status is Connected) {
      await conn.reconnect(match);
    } else {
      await conn.mayConnect();
      final after = ref.read(connectionNotifierProvider).valueOrNull;
      if (after is! Connected && after is! Connecting) {
        await conn.toggleConnection();
      }
    }
  }
}

final blackLinesAutoConnectProvider = Provider<BlackLinesAutoConnect>((ref) {
  return BlackLinesAutoConnect(ref);
});
