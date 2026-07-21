import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Stores the Supabase session in Keychain/Android Keystore-backed storage.
/// Existing SharedPreferences sessions are migrated once, then deleted.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage({required this.persistSessionKey});

  final String persistSessionKey;
  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  late final SharedPreferencesLocalStorage _legacy =
      SharedPreferencesLocalStorage(persistSessionKey: persistSessionKey);

  @override
  Future<void> initialize() async {
    await _legacy.initialize();
    if (kIsWeb) return;

    final secureValue = await _secure.read(key: persistSessionKey);
    if (secureValue != null) return;
    final legacyValue = await _legacy.accessToken();
    if (legacyValue == null) return;
    await _secure.write(key: persistSessionKey, value: legacyValue);
    await _legacy.removePersistedSession();
  }

  @override
  Future<bool> hasAccessToken() async => (await accessToken()) != null;

  @override
  Future<String?> accessToken() =>
      kIsWeb ? _legacy.accessToken() : _secure.read(key: persistSessionKey);

  @override
  Future<void> persistSession(String persistSessionString) => kIsWeb
      ? _legacy.persistSession(persistSessionString)
      : _secure.write(key: persistSessionKey, value: persistSessionString);

  @override
  Future<void> removePersistedSession() async {
    if (kIsWeb) {
      await _legacy.removePersistedSession();
      return;
    }
    await _secure.delete(key: persistSessionKey);
    await _legacy.removePersistedSession();
  }
}

/// Protects the short-lived OAuth/PKCE verifier on native platforms as well.
class SecurePkceStorage extends GotrueAsyncStorage {
  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  final SharedPreferencesGotrueAsyncStorage _web =
      SharedPreferencesGotrueAsyncStorage();

  String _key(String key) => 'pkce_$key';

  @override
  Future<String?> getItem({required String key}) =>
      kIsWeb ? _web.getItem(key: key) : _secure.read(key: _key(key));

  @override
  Future<void> removeItem({required String key}) =>
      kIsWeb ? _web.removeItem(key: key) : _secure.delete(key: _key(key));

  @override
  Future<void> setItem({required String key, required String value}) => kIsWeb
      ? _web.setItem(key: key, value: value)
      : _secure.write(key: _key(key), value: value);
}
