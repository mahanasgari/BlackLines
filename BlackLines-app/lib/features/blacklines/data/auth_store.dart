import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BlackLinesAuthStore {
  BlackLinesAuthStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'bl_access_token';
  static const _expiresKey = 'bl_expires_at';

  final FlutterSecureStorage _storage;

  Future<String?> getToken() => _storage.read(key: _tokenKey);

  Future<bool> get isLoggedIn async {
    final t = await getToken();
    return t != null && t.isNotEmpty;
  }

  Future<void> saveSession({required String accessToken, String? expiresAt}) async {
    await _storage.write(key: _tokenKey, value: accessToken);
    if (expiresAt != null) {
      await _storage.write(key: _expiresKey, value: expiresAt);
    }
  }

  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _expiresKey);
  }
}
