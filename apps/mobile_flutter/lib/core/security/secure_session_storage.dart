import 'dart:async';

import 'package:ahla_shabab_management_os/core/observability/crash_reporter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Stores native Supabase sessions in Keychain/Android Keystore-backed storage.
/// Existing SharedPreferences sessions are migrated on startup.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage({required this.persistSessionKey});

  final String persistSessionKey;
  final FlutterSecureStorage _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: true),
  );
  late final SharedPreferencesLocalStorage _legacy =
      SharedPreferencesLocalStorage(persistSessionKey: persistSessionKey);
  String? _session;
  Future<void> _pending = Future<void>.value();

  Future<void> _serialize(Future<void> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  Future<void> initialize() async {
    await _legacy.initialize();
    if (kIsWeb) return;

    final legacyValue = await _legacy.accessToken();
    try {
      _session = await _secure.read(key: persistSessionKey);
      if (_session == null && legacyValue != null && legacyValue.isNotEmpty) {
        await persistSession(legacyValue);
      }
    } catch (error, stackTrace) {
      // Keystore might be temporarily inaccessible during cold boot.
      unawaited(
        CrashReporter.instance.captureError(
          error,
          stackTrace,
          context: 'secure_session_storage_init',
        ),
      );
    }
    if (legacyValue != null) await _legacy.removePersistedSession();
  }

  @override
  Future<bool> hasAccessToken() async {
    final token = await accessToken();
    return token != null && token.trim().isNotEmpty;
  }

  @override
  Future<String?> accessToken() async =>
      kIsWeb ? _legacy.accessToken() : _session;

  @override
  Future<void> persistSession(String persistSessionString) async {
    if (kIsWeb) return _legacy.persistSession(persistSessionString);
    _session = persistSessionString;
    try {
      await _serialize(
        () =>
            _secure.write(key: persistSessionKey, value: persistSessionString),
      );
    } catch (error, stackTrace) {
      unawaited(
        CrashReporter.instance.captureError(
          error,
          stackTrace,
          context: 'secure_session_storage_write',
        ),
      );
      if (kDebugMode) {
        debugPrint('[SecureSessionStorage] Secure session write failed.');
      }
    }
  }

  @override
  Future<void> removePersistedSession() async {
    if (kIsWeb) return _legacy.removePersistedSession();
    _session = null;
    await _serialize(() => _secure.delete(key: persistSessionKey));
  }
}

/// Protects the short-lived OAuth/PKCE verifier on native platforms as well.
class SecurePkceStorage extends GotrueAsyncStorage {
  final FlutterSecureStorage _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: true),
  );
  final SharedPreferencesGotrueAsyncStorage _fallback =
      SharedPreferencesGotrueAsyncStorage();

  String _key(String key) => 'pkce_$key';

  @override
  Future<String?> getItem({required String key}) async {
    if (kIsWeb) return _fallback.getItem(key: key);
    final value = await _secure.read(key: _key(key));
    final legacyValue = await _fallback.getItem(key: key);
    if (legacyValue != null) {
      if (value == null) {
        await _secure.write(key: _key(key), value: legacyValue);
      }
      await _fallback.removeItem(key: key);
    }
    return value ?? legacyValue;
  }

  @override
  Future<void> removeItem({required String key}) async {
    await _fallback.removeItem(key: key);
    if (!kIsWeb) await _secure.delete(key: _key(key));
  }

  @override
  Future<void> setItem({required String key, required String value}) async {
    if (kIsWeb) return _fallback.setItem(key: key, value: value);
    await _fallback.removeItem(key: key);
    await _secure.write(key: _key(key), value: value);
  }
}
