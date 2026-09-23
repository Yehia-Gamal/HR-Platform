import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Stores the Supabase session in Keychain/Android Keystore-backed storage
/// with an active SharedPreferences mirror fallback.
///
/// Prevents unexpected logouts when Android Keystore becomes locked or
/// throws BadPaddingException / KeyStoreException during Doze mode or reboot.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage({required this.persistSessionKey});

  final String persistSessionKey;
  final FlutterSecureStorage _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: true,
    ),
  );
  late final SharedPreferencesLocalStorage _legacy =
      SharedPreferencesLocalStorage(persistSessionKey: persistSessionKey);

  @override
  Future<void> initialize() async {
    await _legacy.initialize();
    if (kIsWeb) return;

    try {
      final secureValue = await _secure.read(key: persistSessionKey);
      final legacyValue = await _legacy.accessToken();

      if (secureValue == null && legacyValue != null) {
        // Restore to secure storage
        try {
          await _secure.write(key: persistSessionKey, value: legacyValue);
        } catch (_) {}
      } else if (secureValue != null && legacyValue == null) {
        // Mirror to legacy storage
        try {
          await _legacy.persistSession(secureValue);
        } catch (_) {}
      }
    } catch (_) {
      // Keystore might be temporarily inaccessible during cold boot.
    }
  }

  @override
  Future<bool> hasAccessToken() async {
    final token = await accessToken();
    return token != null && token.trim().isNotEmpty;
  }

  @override
  Future<String?> accessToken() async {
    if (kIsWeb) return _legacy.accessToken();

    // 1. Try reading from secure storage
    try {
      final secureValue = await _secure.read(key: persistSessionKey);
      if (secureValue != null && secureValue.trim().isNotEmpty) {
        return secureValue;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SecureSessionStorage] KeyStore read failed, falling back to mirror: $e');
      }
    }

    // 2. Resilient fallback to SharedPreferences mirror
    try {
      final legacyValue = await _legacy.accessToken();
      if (legacyValue != null && legacyValue.trim().isNotEmpty) {
        // Best effort: re-seed secure storage for next time
        try {
          await _secure.write(key: persistSessionKey, value: legacyValue);
        } catch (_) {}
        return legacyValue;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SecureSessionStorage] Mirror read failed: $e');
      }
    }

    return null;
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    // Always persist to SharedPreferences mirror first for absolute reliability
    try {
      await _legacy.persistSession(persistSessionString);
    } catch (_) {}

    if (!kIsWeb) {
      // Also write to encrypted Keystore
      try {
        await _secure.write(key: persistSessionKey, value: persistSessionString);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[SecureSessionStorage] KeyStore write failed: $e');
        }
      }
    }
  }

  @override
  Future<void> removePersistedSession() async {
    try {
      await _legacy.removePersistedSession();
    } catch (_) {}

    if (!kIsWeb) {
      try {
        await _secure.delete(key: persistSessionKey);
      } catch (_) {}
    }
  }
}

/// Protects the short-lived OAuth/PKCE verifier on native platforms as well.
class SecurePkceStorage extends GotrueAsyncStorage {
  final FlutterSecureStorage _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: true,
    ),
  );
  final SharedPreferencesGotrueAsyncStorage _fallback =
      SharedPreferencesGotrueAsyncStorage();

  String _key(String key) => 'pkce_$key';

  @override
  Future<String?> getItem({required String key}) async {
    if (kIsWeb) return _fallback.getItem(key: key);
    try {
      final val = await _secure.read(key: _key(key));
      if (val != null && val.isNotEmpty) return val;
    } catch (_) {}
    return _fallback.getItem(key: key);
  }

  @override
  Future<void> removeItem({required String key}) async {
    try {
      await _fallback.removeItem(key: key);
    } catch (_) {}
    if (!kIsWeb) {
      try {
        await _secure.delete(key: _key(key));
      } catch (_) {}
    }
  }

  @override
  Future<void> setItem({required String key, required String value}) async {
    try {
      await _fallback.setItem(key: key, value: value);
    } catch (_) {}
    if (!kIsWeb) {
      try {
        await _secure.write(key: _key(key), value: value);
      } catch (_) {}
    }
  }
}
