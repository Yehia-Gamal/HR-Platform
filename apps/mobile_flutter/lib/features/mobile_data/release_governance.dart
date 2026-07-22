import 'dart:async';
import 'dart:io';

import 'package:ahla_shabab_management_os/core/config/app_config.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
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

String get _platformName {
  if (kIsWeb) return 'web';
  return Platform.isIOS ? 'ios' : 'android';
}

final installationIdProvider = FutureProvider<String>((ref) async {
  try {
    final existing = await _secureStorage.read(key: _installationKey);
    if (existing != null && existing.length >= 12) return existing;
    final created = _uuid.v4();
    await _secureStorage.write(key: _installationKey, value: created);
    return created;
  } catch (_) {
    // Fallback: generate a volatile ID if secure storage fails.
    return _uuid.v4();
  }
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
        await client.auth.signOut();
      } catch (_) {
        // Best-effort sign-out.
      }
      try {
        final retryResponse = await client.rpc<dynamic>(
          'get_public_release_policy',
          params: params,
        );
        return MobileReleasePolicy.fromJson(
          Map<String, dynamic>.from(retryResponse as Map<dynamic, dynamic>),
        );
      } catch (_) {
        // Retry also failed — fall through to default policy.
      }
    }
    rethrow;
  } on SocketException {
    // Offline: return default "continue" policy so the app doesn't brick.
    return MobileReleasePolicy.continueAction();
  } on TimeoutException {
    return MobileReleasePolicy.continueAction();
  }
});

final deviceRegistrationProvider = FutureProvider<void>((ref) async {
  final session = ref.watch(authSessionProvider).value;
  if (session == null) return;
  final client = ref.watch(supabaseProvider);
  final installationId = await ref.watch(installationIdProvider.future);
  final packageInfo = await PackageInfo.fromPlatform();
  final deviceInfo = DeviceInfoPlugin();
  String name;
  String model;
  String osVersion;
  bool biometricHint = false;

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
      biometricHint = info.isPhysicalDevice;
    } else {
      final info = await deviceInfo.androidInfo;
      name = info.device;
      model = '${info.manufacturer} ${info.model}'.trim();
      osVersion = info.version.release;
      biometricHint = info.isPhysicalDevice;
    }
  } catch (_) {
    // Device info failed — use safe defaults.
    name = 'unknown';
    model = 'unknown';
    osVersion = 'unknown';
  }

  if (!kIsWeb) {
    try {
      final localAuth = LocalAuthentication();
      biometricHint = await localAuth.isDeviceSupported() &&
          await localAuth.canCheckBiometrics;
    } catch (_) {
      biometricHint = false;
    }
  }

  try {
    await client.rpc<dynamic>(
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
    );
  } catch (_) {
    // Device registration is non-blocking — continue without it.
  }
});
