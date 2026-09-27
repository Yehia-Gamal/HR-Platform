import 'dart:async';
import 'dart:io';

import 'package:ahla_shabab_management_os/core/config/app_config.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

enum MobileReleaseAction {
  none,
  updateAvailable,
  updateRequired,
  maintenance,
  blocked;

  static MobileReleaseAction fromWire(String value) => switch (value) {
    'update_available' => MobileReleaseAction.updateAvailable,
    'update_required' => MobileReleaseAction.updateRequired,
    'maintenance' => MobileReleaseAction.maintenance,
    'blocked' => MobileReleaseAction.blocked,
    _ => MobileReleaseAction.none,
  };
}

class MobileReleasePolicy {
  const MobileReleasePolicy({
    required this.action,
    required this.platform,
    required this.environment,
    required this.currentVersion,
    required this.currentBuild,
    required this.latestVersion,
    required this.latestBuild,
    required this.minSupportedVersion,
    required this.minSupportedBuild,
    required this.forceUpdate,
    required this.maintenance,
    required this.messageAr,
    required this.storeUrl,
    required this.checkedAt,
  });

  factory MobileReleasePolicy.fromJson(Map<String, dynamic> json) {
    return MobileReleasePolicy(
      action: MobileReleaseAction.fromWire(json['action'] as String? ?? 'none'),
      platform: json['platform'] as String? ?? _platformName,
      environment: json['environment'] as String? ?? AppConfig.environment,
      currentVersion: json['currentVersion'] as String? ?? '0.0.0',
      currentBuild: (json['currentBuild'] as num?)?.toInt() ?? 0,
      latestVersion: json['latestVersion'] as String? ?? '0.0.0',
      latestBuild: (json['latestBuild'] as num?)?.toInt() ?? 0,
      minSupportedVersion: json['minSupportedVersion'] as String? ?? '0.0.0',
      minSupportedBuild: (json['minSupportedBuild'] as num?)?.toInt() ?? 0,
      forceUpdate: json['forceUpdate'] as bool? ?? false,
      maintenance: json['maintenance'] as bool? ?? false,
      messageAr: json['messageAr'] as String?,
      storeUrl: json['storeUrl'] as String?,
      checkedAt:
          DateTime.tryParse(json['checkedAt'] as String? ?? '') ??
          DateTime.now().toUtc(),
    );
  }

  /// Default "continue" policy used when the server is unreachable (offline).
  /// Prevents the app from bricking on startup during network failures.
  factory MobileReleasePolicy.continueAction() => MobileReleasePolicy(
    action: MobileReleaseAction.none,
    platform: _platformName,
    environment: AppConfig.environment,
    currentVersion: '0.0.0',
    currentBuild: 0,
    latestVersion: '0.0.0',
    latestBuild: 0,
    minSupportedVersion: '0.0.0',
    minSupportedBuild: 0,
    forceUpdate: false,
    maintenance: false,
    messageAr: null,
    storeUrl: null,
    checkedAt: DateTime.now().toUtc(),
  );

  final MobileReleaseAction action;
  final String platform;
  final String environment;
  final String currentVersion;
  final int currentBuild;
  final String latestVersion;
  final int latestBuild;
  final String minSupportedVersion;
  final int minSupportedBuild;
  final bool forceUpdate;
  final bool maintenance;
  final String? messageAr;
  final String? storeUrl;
  final DateTime checkedAt;

  bool get blocksApplication =>
      action == MobileReleaseAction.updateRequired ||
      action == MobileReleaseAction.maintenance ||
      action == MobileReleaseAction.blocked;
}

const _secureStorage = FlutterSecureStorage();
const _installationKey = 'management_os_installation_id_v1';
const _uuid = Uuid();
String? _cachedInstallationId;

String get _platformName {
  if (kIsWeb) return 'web';
  return Platform.isIOS ? 'ios' : 'android';
}

final installationIdProvider = FutureProvider<String>((ref) async {
  if (_cachedInstallationId != null && _cachedInstallationId!.length >= 12) {
    return _cachedInstallationId!;
  }

  // 1. فحص التخزين الآمن
  try {
    final existing = await _secureStorage.read(key: _installationKey);
    if (existing != null && existing.length >= 12) {
      _cachedInstallationId = existing;
      return existing;
    }
  } catch (e) {
    if (kDebugMode) debugPrint('[installationId] secureStorage read failed: $e');
  }

  // 2. فحص SharedPreferences كبديل احتياطي مستقر
  try {
    final prefs = await SharedPreferences.getInstance();
    final existingPref = prefs.getString(_installationKey);
    if (existingPref != null && existingPref.length >= 12) {
      _cachedInstallationId = existingPref;
      try {
        await _secureStorage.write(key: _installationKey, value: existingPref);
      } catch (_) {}
      return existingPref;
    }
  } catch (e) {
    if (kDebugMode) debugPrint('[installationId] prefs read failed: $e');
  }

  // 3. إنشاء معرّف جديد وتخزينه في كلا المكانين
  final created = _uuid.v4();
  _cachedInstallationId = created;

  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_installationKey, created);
  } catch (_) {}

  try {
    await _secureStorage.write(key: _installationKey, value: created);
  } catch (_) {}

  return created;
});

final releasePolicyProvider = FutureProvider<MobileReleasePolicy>((ref) async {
  final client = ref.watch(supabaseProvider);
  final installationId = await ref.watch(installationIdProvider.future);
  final packageInfo = await PackageInfo.fromPlatform();
  final build = int.tryParse(packageInfo.buildNumber) ?? 0;
  final params = {
    'p_platform': _platformName,
    'p_environment': AppConfig.environment,
    'p_current_version': packageInfo.version,
    'p_current_build': build,
    'p_installation_id': installationId,
  };
  try {
    final response = await client.rpc<dynamic>(
      'get_public_release_policy',
      params: params,
    );
    return MobileReleasePolicy.fromJson(
      Map<String, dynamic>.from(response as Map<dynamic, dynamic>),
    );
  } on PostgrestException catch (e) {
    if (e.code == 'PGRST303') {
      try {
        await client.auth.refreshSession();
        final retryResponse = await client.rpc<dynamic>(
          'get_public_release_policy',
          params: params,
        );
        return MobileReleasePolicy.fromJson(
          Map<String, dynamic>.from(retryResponse as Map<dynamic, dynamic>),
        );
      } catch (_) {
        // Refresh or retry failed — fall through safely without signing out.
      }
    }
    // أي خطأ Postgrest آخر (RPC غير موجود، خطأ في الجدول…) → لا نحجب التطبيق.
    return MobileReleasePolicy.continueAction();
  } on SocketException {
    // Offline: return default "continue" policy so the app doesn't brick.
    return MobileReleasePolicy.continueAction();
  } on TimeoutException {
    return MobileReleasePolicy.continueAction();
  } catch (_) {
    // أي استثناء آخر (DNS، SSL، ClientException…) → لا نحجب التطبيق.
    return MobileReleasePolicy.continueAction();
  }
});

/// تسجيل صريح للجهاز مع التحقق ورمي أي أخطاء للمنادي لتوجيه المستخدم.
Future<Map<String, dynamic>> registerMyDeviceExplicitly(
  Ref ref, {
  bool biometricHint = true,
}) async {
  final client = ref.read(supabaseProvider);
  final session = client.auth.currentSession;
  if (session == null) {
    throw StateError('يلزم تسجيل الدخول أولاً لتسجيل الجهاز.');
  }
  final installationId = await ref.read(installationIdProvider.future);
  final packageInfo = await PackageInfo.fromPlatform();
  final deviceInfo = DeviceInfoPlugin();
  String name;
  String model;
  String osVersion;

  try {
    if (kIsWeb) {
      final info = await deviceInfo.webBrowserInfo;
      name = info.browserName.name;
      model = info.userAgent ?? 'web';
      osVersion = info.platform ?? 'web';
    } else if (Platform.isIOS) {
      final info = await deviceInfo.iosInfo;
      name = info.name;
      model = info.utsname.machine;
      osVersion = info.systemVersion;
    } else {
      final info = await deviceInfo.androidInfo;
      name = info.device;
      model = '${info.manufacturer} ${info.model}'.trim();
      osVersion = info.version.release;
    }
  } catch (_) {
    name = 'unknown';
    model = 'unknown';
    osVersion = 'unknown';
  }

  final response = await client.rpc<dynamic>(
    'register_my_device',
    params: {
      'p_installation_id': installationId,
      'p_platform': _platformName,
      'p_device_name': name,
      'p_device_model': model,
      'p_os_version': osVersion,
      'p_app_version': packageInfo.version,
      'p_app_build': int.tryParse(packageInfo.buildNumber) ?? 0,
      'p_environment': AppConfig.environment,
      'p_push_enabled': false,
      'p_biometric_available': biometricHint,
      'p_metadata': {'packageName': packageInfo.packageName},
    },
  ).timeout(const Duration(seconds: 20));

  return response is Map ? Map<String, dynamic>.from(response) : <String, dynamic>{};
}

final deviceRegistrationProvider = FutureProvider<void>((ref) async {
  final session = ref.watch(authSessionProvider).value;
  if (session == null) return;
  bool biometricHint = false;
  if (!kIsWeb) {
    try {
      final localAuth = LocalAuthentication();
      biometricHint = await localAuth.isDeviceSupported();
    } catch (_) {
      biometricHint = false;
    }
  }
  try {
    await registerMyDeviceExplicitly(ref, biometricHint: biometricHint);
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[deviceRegistrationProvider] non-blocking background registration error: $e');
    }
  }
});
