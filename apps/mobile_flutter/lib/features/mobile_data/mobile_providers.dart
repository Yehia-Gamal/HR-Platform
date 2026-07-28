import 'dart:typed_data';

import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/network/offline_cache.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/location_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/passkey_attendance_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/release_governance.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, dynamic> _asMap(dynamic value) =>
    Map<String, dynamic>.from(value as Map<dynamic, dynamic>);
List<Map<String, dynamic>> _asList(dynamic value) =>
    (value as List<dynamic>? ?? const [])
        .map((e) => _asMap(e))
        .toList(growable: false);

/// Wraps an RPC call with a timeout to prevent infinite spinners (P0-21).
Future<T> _withTimeout<T>(
  Future<T> future, [
  Duration t = const Duration(seconds: 20),
]) => future.timeout(t);

final mobileActionTargetProvider =
    FutureProvider.family<MobileActionTarget, MobileActionItem>((
      ref,
      item,
    ) async {
      final data = await ref
          .watch(supabaseProvider)
          .rpc<dynamic>(
            'resolve_mobile_action_target',
            params: {'p_action_id': item.id, 'p_kind': item.kind},
          );
      return MobileActionTarget.fromJson(_asMap(data));
    });
final mobileRequestDetailProvider =
    FutureProvider.family<MobileRequestDetail, String>((ref, requestId) async {
      final data = await ref
          .watch(supabaseProvider)
          .rpc<dynamic>(
            'get_mobile_request_detail',
            params: {'p_request_id': requestId},
          );
      return MobileRequestDetail.fromJson(_asMap(data));
    });
final mobileFeedDetailProvider =
    FutureProvider.family<MobileFeedItem, ({String kind, String id})>((
      ref,
      key,
    ) async {
      final data = await ref
          .watch(supabaseProvider)
          .rpc<dynamic>(
            'get_mobile_feed_item',
            params: {'p_kind': key.kind, 'p_item_id': key.id},
          );
      return MobileFeedItem.fromJson(_asMap(data));
    });
final myPasskeysProvider = FutureProvider<List<PasskeyDevice>>((ref) async {
  final data = await rpcWithTimeout(
    ref.watch(supabaseProvider).rpc<dynamic>('get_my_passkeys'),
  );
  return _asList(data).map(PasskeyDevice.fromJson).toList(growable: false);
});

final myAttendanceHistoryProvider = FutureProvider<List<AttendanceHistoryItem>>(
  (ref) async {
    final data = await rpcWithTimeout(
      ref
          .watch(supabaseProvider)
          .rpc<dynamic>('get_my_attendance_history', params: {'p_limit': 100, 'p_days': 30}),
    );
    return _asList(
      data,
    ).map(AttendanceHistoryItem.fromJson).toList(growable: false);
  },
);

final myNotificationsProvider = FutureProvider<List<MobileNotificationItem>>((
  ref,
) async {
  final data = await rpcWithTimeout(
    ref
        .watch(supabaseProvider)
        .rpc<dynamic>('get_my_notifications', params: {'p_limit': 100}),
  );
  return _asList(
    data,
  ).map(MobileNotificationItem.fromJson).toList(growable: false);
});

final markNotificationOpenedProvider = FutureProvider.family<void, String>((
  ref,
  notificationId,
) async {
  await ref
      .watch(supabaseProvider)
      .rpc<void>(
        'mark_my_notification_delivery',
        params: {'p_notification_id': notificationId, 'p_status': 'opened'},
      );
});

final employeeHomeProvider = FutureProvider<EmployeeHomeSummary>((ref) async {
  try {
    final data = await _withTimeout(
      ref.watch(supabaseProvider).rpc<dynamic>('get_employee_home'),
    );
    final result = EmployeeHomeSummary.fromJson(_asMap(data));
    OfflineCache.instance.put(OfflineCache.employeeHome, _asMap(data));
    return result;
  } catch (e) {
    final cached = await OfflineCache.instance.get(OfflineCache.employeeHome);
    if (cached != null) return EmployeeHomeSummary.fromJson(_asMap(cached));
    rethrow;
  }
});
final managerDashboardProvider = FutureProvider<ManagerDashboardSummary>((
  ref,
) async {
  try {
    final data = await _withTimeout(
      ref.watch(supabaseProvider).rpc<dynamic>('get_manager_dashboard'),
    );
    final result = ManagerDashboardSummary.fromJson(_asMap(data));
    OfflineCache.instance.put(OfflineCache.managerDashboard, _asMap(data));
    return result;
  } catch (e) {
    final cached = await OfflineCache.instance.get(
      OfflineCache.managerDashboard,
    );
    if (cached != null) return ManagerDashboardSummary.fromJson(_asMap(cached));
    rethrow;
  }
});
final executiveDashboardProvider = FutureProvider<ExecutiveDashboardSummary>((
  ref,
) async {
  final data = await _withTimeout(
    ref.watch(supabaseProvider).rpc<dynamic>('get_executive_dashboard'),
  );
  return ExecutiveDashboardSummary.fromJson(_asMap(data));
});
final mobileRequestsProvider = FutureProvider<List<MobileRequest>>((ref) async {
  try {
    final data = await _withTimeout(
      ref
          .watch(supabaseProvider)
          .rpc<dynamic>('get_request_inbox', params: {'p_limit': 100}),
    );
    final result = _asList(
      data,
    ).map(MobileRequest.fromJson).toList(growable: false);
    OfflineCache.instance.put(OfflineCache.myRequests, _asList(data));
    return result;
  } catch (e) {
    final cached = await OfflineCache.instance.get(OfflineCache.myRequests);
    if (cached != null) {
      return (cached as List<dynamic>)
          .map((e) => MobileRequest.fromJson(_asMap(e)))
          .toList(growable: false);
    }
    rethrow;
  }
});
// تكليفات العمل (مأمورية/قافلة/فاندي). p_scope: 'mine' للموظف، 'team' للمدير.
final workAssignmentsProvider =
    FutureProvider.family<List<MobileWorkAssignment>, String>((
      ref,
      scope,
    ) async {
      final data = await rpcWithTimeout(
        ref
            .watch(supabaseProvider)
            .rpc<dynamic>(
              'get_work_assignments_inbox',
              params: {'p_scope': scope, 'p_limit': 100},
            ),
      );
      return _asList(
        data,
      ).map(MobileWorkAssignment.fromJson).toList(growable: false);
    });

// كشف الحضور والانصراف الشهري الشخصي (V12 §18 — get_my_monthly_attendance_statement).
final myMonthlyStatementProvider =
    FutureProvider.family<MonthlyAttendanceStatement, (int, int)>(
  (ref, params) async {
    final data = await rpcWithTimeout(
      ref.watch(supabaseProvider).rpc<dynamic>(
        'get_my_monthly_attendance_statement',
        params: {'p_year': params.$1, 'p_month': params.$2},
      ),
    );
    return MonthlyAttendanceStatement.fromJson(_asMap(data));
  },
);
final mobileKpiProvider = FutureProvider<List<MobileKpiEvaluation>>((
  ref,
) async {
  try {
    final data = await _withTimeout(ref
        .watch(supabaseProvider)
        .rpc<dynamic>('get_kpi_inbox', params: {'p_limit': 100}));
    final result = _asList(
      data,
    ).map(MobileKpiEvaluation.fromJson).toList(growable: false);
    OfflineCache.instance.put(OfflineCache.kpiList, _asList(data));
    return result;
  } catch (e) {
    final cached = await OfflineCache.instance.get(OfflineCache.kpiList);
    if (cached != null) {
      return (cached as List<dynamic>)
          .map((e) => MobileKpiEvaluation.fromJson(_asMap(e)))
          .toList(growable: false);
    }
    rethrow;
  }
});
final kpiEvaluationFormProvider =
    FutureProvider.family<KpiEvaluationForm, String>((ref, evaluationId) async {
      final data = await rpcWithTimeout(
        ref
            .watch(supabaseProvider)
            .rpc<dynamic>(
              'get_kpi_evaluation_form',
              params: {'p_evaluation_id': evaluationId},
            ),
      );
      return KpiEvaluationForm.fromJson(_asMap(data));
    });
final attendanceStateProvider = FutureProvider<AttendanceState>((ref) async {
  try {
    final data = await _withTimeout(ref
        .watch(supabaseProvider)
        .rpc<dynamic>('get_my_attendance_state'));
    final result = AttendanceState.fromJson(_asMap(data));
    // Cache for offline use.
    OfflineCache.instance.put(OfflineCache.attendanceState, _asMap(data));
    return result;
  } catch (e) {
    // Try cached data when offline.
    final cached = await OfflineCache.instance.get(
      OfflineCache.attendanceState,
    );
    if (cached != null) return AttendanceState.fromJson(_asMap(cached));
    rethrow;
  }
});
final mobileFeedProvider = FutureProvider<List<MobileFeedItem>>((ref) async {
  final data = await rpcWithTimeout(
    ref
        .watch(supabaseProvider)
        .rpc<dynamic>('get_official_feed_admin', params: {'p_limit': 100}),
  );
  return _asList(data).map(MobileFeedItem.fromJson).toList(growable: false);
});
final mobileActionCenterProvider = FutureProvider<List<MobileActionItem>>((
  ref,
) async {
  final data = await rpcWithTimeout(
    ref
        .watch(supabaseProvider)
        .rpc<dynamic>('get_universal_action_center', params: {'p_limit': 100}),
  );
  return _asList(data).map(MobileActionItem.fromJson).toList(growable: false);
});

/// P0-21: Auto-refresh critical providers when connectivity is restored.
/// Listens to [connectivityProvider] and invalidates stale data on reconnect.
final connectivityRefreshProvider = Provider<void>((ref) {
  var previous = ConnectivityState.online;
  ref.listen<ConnectivityState>(connectivityProvider, (prev, next) {
    if (previous == ConnectivityState.offline &&
        (next == ConnectivityState.reconnecting ||
            next == ConnectivityState.online)) {
      // Back online — refresh critical data.
      ref.invalidate(attendanceStateProvider);
      ref.invalidate(employeeHomeProvider);
      ref.invalidate(managerDashboardProvider);
    }
    previous = next;
  });
});

final locationDirectoryProvider = FutureProvider.autoDispose
    .family<List<LocationDirectoryEmployee>, String>((ref, search) async {
      final data = await ref
          .watch(supabaseProvider)
          .rpc<dynamic>(
            'get_location_directory',
            params: {'p_search': search, 'p_limit': 100},
          )
          .timeout(const Duration(seconds: 15));
      return _asList(
        data,
      ).map(LocationDirectoryEmployee.fromJson).toList(growable: false);
    });
final myLocationRequestsProvider = FutureProvider<List<MobileLocationRequest>>((
  ref,
) async {
  final data = await ref
      .watch(supabaseProvider)
      .rpc<dynamic>('get_my_live_location_requests', params: {'p_limit': 30});
  return _asList(
    data,
  ).map(MobileLocationRequest.fromJson).toList(growable: false);
});

final locationRequestByIdProvider = FutureProvider.autoDispose
    .family<MobileLocationRequest, String>((ref, requestId) async {
      final requests = await ref.watch(myLocationRequestsProvider.future);
      return requests.firstWhere(
        (request) => request.id == requestId,
        orElse: () => throw StateError('location_request_not_available'),
      );
    });

/// لوحة الحضور اليومي للمدير التنفيذي — تستدعي get_executive_attendance_today().
final executiveAttendanceTodayProvider =
    FutureProvider.autoDispose<List<AttendanceTodayEmployee>>((ref) async {
      final data = await ref
          .watch(supabaseProvider)
          .rpc<dynamic>('get_executive_attendance_today')
          .timeout(const Duration(seconds: 15));
      return _asList(
        data,
      ).map(AttendanceTodayEmployee.fromJson).toList(growable: false);
    });

/// يستطلع طلبات الموقع المعلقة للمستخدم الحالي كل 15 ثانية.
/// يُستخدم بواسطة [LocationIncomingListener] لعرض الشاشة المنبثقة عند ورود طلب.
final pendingIncomingLocationRequestProvider =
    StreamProvider<MobileLocationRequest?>((ref) async* {
      final supabase = ref.watch(supabaseProvider);
      while (true) {
        try {
          final data = await supabase.rpc<dynamic>(
            'get_my_live_location_requests',
            params: {'p_limit': 10},
          );
          final all = _asList(
            data,
          ).map(MobileLocationRequest.fromJson).toList();
          final pending = all.where((r) => r.status == 'pending').toList();
          yield pending.isEmpty ? null : pending.first;
        } catch (_) {
          yield null;
        }
        await Future<void>.delayed(const Duration(seconds: 15));
      }
    });

final disputeDirectoryProvider =
    FutureProvider.family<List<DisputeDirectoryEmployee>, String>((
      ref,
      search,
    ) async {
      final data = await ref
          .watch(supabaseProvider)
          .rpc<dynamic>(
            'get_dispute_participant_directory',
            params: {'p_search': search, 'p_limit': 100},
          );
      return _asList(
        data,
      ).map(DisputeDirectoryEmployee.fromJson).toList(growable: false);
    });

final mobileCommandsProvider = Provider<MobileCommands>(
  (ref) => MobileCommands(ref),
);

class MobileCommands {
  MobileCommands(this.ref);
  final Ref ref;
  Future<void> submitRequest(
    String type,
    String title,
    String reason,
    Map<String, dynamic> payload,
  ) async {
    await ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'submit_my_request',
          params: {
            'p_request_type': type,
            'p_title': title,
            'p_reason': reason,
            'p_payload': payload,
          },
        );
    ref.invalidate(mobileRequestsProvider);
    ref.invalidate(employeeHomeProvider);
  }

  Future<Map<String, dynamic>> uploadRequestAttachment({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final client = ref.read(supabaseProvider);
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw StateError('AUTHENTICATION_REQUIRED');
    final normalizedMime = _allowedImageMime(mimeType, fileName);
    final extension = switch (normalizedMime) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
    final path = '$userId/${const Uuid().v4()}.$extension';
    await client.storage.from('request-attachments').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: normalizedMime, upsert: false),
        );
    return {
      'path': path,
      'name': fileName,
      'mimeType': normalizedMime,
      'sizeBytes': bytes.length,
    };
  }

  Future<void> deleteRequestAttachments(Iterable<String> paths) async {
    final values = paths.where((path) => path.trim().isNotEmpty).toList();
    if (values.isEmpty) return;
    await ref
        .read(supabaseProvider)
        .storage
        .from('request-attachments')
        .remove(values);
  }

  static String _allowedImageMime(String mimeType, String fileName) {
    final value = mimeType.toLowerCase();
    if (value == 'image/png' || value == 'image/webp' || value == 'image/jpeg') {
      return value;
    }
    final lowerName = fileName.toLowerCase();
    if (lowerName.endsWith('.png')) return 'image/png';
    if (lowerName.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> decideRequest(
    String id,
    String decision,
    String? comment,
  ) async {
    await ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'decide_request',
          params: {
            'p_request_id': id,
            'p_decision': decision,
            'p_comment': comment,
          },
        );
    ref.invalidate(mobileRequestsProvider);
    ref.invalidate(mobileActionCenterProvider);
    ref.invalidate(managerDashboardProvider);
    ref.invalidate(executiveDashboardProvider);
  }

  Future<void> cancelRequest(String id, String reason) async {
    await ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'cancel_request',
          params: {'p_request_id': id, 'p_reason': reason.trim()},
        );
    ref.invalidate(mobileRequestsProvider);
    ref.invalidate(mobileRequestDetailProvider(id));
    ref.invalidate(mobileActionCenterProvider);
    ref.invalidate(employeeHomeProvider);
  }

  // إنشاء تكليف عمل (مأمورية/قافلة/فاندي) بواسطة المدير لتابعيه.
  Future<void> createWorkAssignment({
    required String assignmentType,
    required String title,
    required DateTime startAt,
    required DateTime endAt,
    required List<String> participantIds,
    String? description,
    String? location,
    bool isFullDay = true,
    bool needsReport = false,
    double? targetAmount,
  }) async {
    final payload = <String, dynamic>{
      'isFullDay': isFullDay,
      'targetAmount': ?targetAmount,
    };
    await ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'create_work_assignment',
          params: {
            'p_assignment_type': assignmentType,
            'p_title': title.trim(),
            'p_start_at': startAt.toUtc().toIso8601String(),
            'p_end_at': endAt.toUtc().toIso8601String(),
            'p_participant_ids': participantIds,
            'p_description': description?.trim(),
            'p_location': location?.trim(),
            'p_needs_report': needsReport,
            'p_payload': payload,
          },
        );
    ref.invalidate(workAssignmentsProvider('team'));
    ref.invalidate(workAssignmentsProvider('mine'));
    ref.invalidate(employeeHomeProvider);
  }

  // قرار على تكليف عمل (اعتماد/رفض).
  Future<void> decideWorkAssignment(
    String id,
    String decision,
    String? comment,
  ) async {
    await ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'decide_work_assignment',
          params: {
            'p_assignment_id': id,
            'p_decision': decision,
            'p_comment': comment?.trim(),
          },
        );
    ref.invalidate(workAssignmentsProvider('team'));
    ref.invalidate(workAssignmentsProvider('mine'));
  }

  // إرسال تقرير تنفيذ التكليف من المشارك.
  Future<void> submitAssignmentReport(
    String id,
    String report, {
    String? outcome,
    double? achievedAmount,
  }) async {
    await ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'submit_assignment_report',
          params: {
            'p_assignment_id': id,
            'p_report': report.trim(),
            'p_outcome': outcome?.trim(),
            'p_achieved_amount': achievedAmount,
          },
        );
    ref.invalidate(workAssignmentsProvider('mine'));
    ref.invalidate(workAssignmentsProvider('team'));
  }

  Future<void> advanceKpi(
    String id,
    String action,
    String? note, {
    List<Map<String, dynamic>>? scores,
  }) async {
    await ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'advance_kpi_stage',
          params: {
            'p_evaluation_id': id,
            'p_action': action,
            'p_scores': scores,
            'p_note': note,
          },
        );
    ref.invalidate(mobileKpiProvider);
    ref.invalidate(kpiEvaluationFormProvider(id));
    ref.invalidate(mobileActionCenterProvider);
    ref.invalidate(employeeHomeProvider);
    ref.invalidate(managerDashboardProvider);
    ref.invalidate(executiveDashboardProvider);
  }

  Future<void> returnKpi(String id, String targetStage, String note) async {
    await ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'return_kpi_stage',
          params: {
            'p_evaluation_id': id,
            'p_target_stage': targetStage,
            'p_note': note,
          },
        );
    ref.invalidate(mobileKpiProvider);
    ref.invalidate(kpiEvaluationFormProvider(id));
    ref.invalidate(mobileActionCenterProvider);
    ref.invalidate(employeeHomeProvider);
    ref.invalidate(managerDashboardProvider);
    ref.invalidate(executiveDashboardProvider);
  }

  Future<void> saveKpiGoalProgress(
    String evaluationId,
    KpiGoalForm goal, {
    required double achievedValue,
    required String status,
    String? evidenceSource,
    String? employeeNote,
  }) async {
    await ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'save_kpi_goal',
          params: {
            'p_evaluation_id': evaluationId,
            'p_goal_id': goal.id,
            'p_title': goal.title,
            'p_description': null,
            'p_target_value': goal.targetValue,
            'p_achieved_value': achievedValue,
            'p_unit': goal.unit,
            'p_weight': goal.weight,
            'p_due_date': null,
            'p_evidence_source': evidenceSource,
            'p_employee_note': employeeNote,
            'p_manager_note': null,
            'p_status': status,
          },
        );
    ref.invalidate(kpiEvaluationFormProvider(evaluationId));
  }

  Future<void> saveKpiSession(
    String evaluationId,
    Map<String, dynamic> session,
  ) async {
    await ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'save_kpi_review_session',
          params: {'p_evaluation_id': evaluationId, 'p_session': session},
        );
    ref.invalidate(kpiEvaluationFormProvider(evaluationId));
  }

  Future<void> saveKpiCompliance(
    String evaluationId,
    String metric,
    int required,
    int actual,
    int exempt,
    int cancelled,
    String? note,
  ) async {
    await ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'save_kpi_compliance_metric',
          params: {
            'p_evaluation_id': evaluationId,
            'p_metric': metric,
            'p_required': required,
            'p_actual': actual,
            'p_exempt': exempt,
            'p_cancelled': cancelled,
            'p_note': note,
          },
        );
    ref.invalidate(kpiEvaluationFormProvider(evaluationId));
  }

  Future<void> acknowledgeKpi(
    String evaluationId,
    String? note,
    String? appealReason,
  ) async {
    await ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'acknowledge_kpi_evaluation',
          params: {
            'p_evaluation_id': evaluationId,
            'p_note': note,
            'p_appeal_reason': appealReason,
          },
        );
    ref.invalidate(mobileKpiProvider);
    ref.invalidate(kpiEvaluationFormProvider(evaluationId));
    ref.invalidate(mobileActionCenterProvider);
  }

  Future<void> requestLocation(
    String employeeId,
    String reason,
  ) async {
    await ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'request_live_location',
          params: {
            'p_employee_id': employeeId,
            'p_mode': 'snapshot',
            'p_reason': reason,
          },
        );
    ref.invalidate(locationDirectoryProvider);
    ref.invalidate(executiveDashboardProvider);
  }

  Future<void> cancelLocationRequest(String requestId) async {
    await ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'cancel_location_request_as_requester',
          params: {'p_request_id': requestId},
        );
    ref.invalidate(locationDirectoryProvider);
    ref.invalidate(executiveDashboardProvider);
  }

  Future<void> respondLocation(String requestId, bool accept) async {
    await ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'respond_live_location_request',
          params: {'p_request_id': requestId, 'p_accept': accept},
        );
    ref.invalidate(myLocationRequestsProvider);
    ref.invalidate(employeeHomeProvider);
  }

  Future<void> submitLocationPoint(
    String requestId, {
    required double latitude,
    required double longitude,
    required double accuracy,
    double? altitude,
    double? speed,
    double? heading,
    bool isMock = false,
    String? addressAr,
  }) async {
    await ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'submit_live_location_point',
          params: {
            'p_request_id': requestId,
            'p_latitude': latitude,
            'p_longitude': longitude,
            'p_accuracy': accuracy,
            'p_altitude': altitude,
            'p_speed': speed,
            'p_heading': heading,
            'p_is_mock': isMock,
            'p_address_ar': addressAr,
          },
        );
    ref.invalidate(myLocationRequestsProvider);
  }

  Future<void> upsertPushToken(String fcmToken, String platform) async {
    await ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'upsert_my_push_token',
          params: {'p_fcm_token': fcmToken, 'p_platform': platform},
        );
  }

  Future<void> completeLocation(String requestId) async {
    await ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'complete_my_live_location_request',
          params: {'p_request_id': requestId},
        );
    ref.invalidate(myLocationRequestsProvider);
  }

  // V17 §9: registerLocationVideo removed — video permanently disabled.

  Future<void> registerLocationMapSnapshot(
    String requestId, {
    required String storagePath,
  }) async {
    await ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'register_live_location_map_snapshot',
          params: {'p_request_id': requestId, 'p_storage_path': storagePath},
        );
    ref.invalidate(myLocationRequestsProvider);
  }

  Future<bool> supportsPasskeys() =>
      ref.read(passkeyAttendanceServiceProvider).isSupported();
  Future<void> registerPasskey({String deviceLabel = 'هاتف الموظف'}) async {
    await ref
        .read(passkeyAttendanceServiceProvider)
        .register(deviceLabel: deviceLabel);
    ref.invalidate(attendanceStateProvider);
    ref.invalidate(myPasskeysProvider);
  }

  Future<void> registerLocalBiometricDevice() async {
    final localAuth = LocalAuthentication();
    final supported = await localAuth.isDeviceSupported() &&
        await localAuth.canCheckBiometrics;
    if (!supported) {
      throw StateError('الجهاز لا يدعم بصمة محلية مفعلة. فعّل البصمة وقفل الشاشة أولاً.');
    }
    // فحص وجود بصمات مسجلة على الجهاز.
    final available = await localAuth.getAvailableBiometrics();
    if (available.isEmpty) {
      throw StateError(
        'لا توجد بصمة مسجلة على الجهاز. أضف بصمة من إعدادات الأمان ثم أعد المحاولة.',
      );
    }
    // تحقق فعلي من البصمة — يظهر نافذة البصمة للمستخدم.
    final didAuthenticate = await localAuth.authenticate(
      localizedReason: 'تأكيد تسجيل البصمة لنظام الحضور',
      options: const AuthenticationOptions(
        stickyAuth: true,
        biometricOnly: true,
        useErrorDialogs: true,
      ),
    );
    if (!didAuthenticate) {
      throw StateError('تم إلغاء التحقق بالبصمة. لم يتم التسجيل.');
    }
    ref.invalidate(deviceRegistrationProvider);
    await ref.read(deviceRegistrationProvider.future);
    ref.invalidate(attendanceStateProvider);
  }

  Future<Map<String, dynamic>> punchAttendance({
    required String eventType,
  }) async {
    final result = await ref
        .read(passkeyAttendanceServiceProvider)
        .punch(eventType);
    ref.invalidate(attendanceStateProvider);
    ref.invalidate(myAttendanceHistoryProvider);
    ref.invalidate(employeeHomeProvider);
    return result;
  }

  /// حضور انفرادي: بصمة محلية + موقع → RPC مبسط (بدون WebAuthn/Samsung Pass).
  Future<Map<String, dynamic>> punchAttendanceLocal({
    required String eventType,
  }) async {
    final localAuth = LocalAuthentication();
    // فحص دعم البصمة قبل المحاولة — يمنع خطأ غير واضح على أجهزة بلا مستشعر.
    final canCheck = await localAuth.canCheckBiometrics;
    final isDeviceSupported = await localAuth.isDeviceSupported();
    if (!canCheck && !isDeviceSupported) {
      throw StateError(
        'الجهاز لا يدعم البصمة أو قفل الشاشة الآمن. تحقق من إعدادات الأمان.',
      );
    }
    if (canCheck) {
      final available = await localAuth.getAvailableBiometrics();
      if (available.isEmpty) {
        throw StateError(
          'لا توجد بصمة مسجلة على الجهاز. أضف بصمة من إعدادات الأمان ثم أعد المحاولة.',
        );
      }
    }
    final didAuthenticate = await localAuth.authenticate(
      localizedReason: 'تأكيد تسجيل الحضور بالبصمة',
      options: const AuthenticationOptions(
        stickyAuth: true,
        biometricOnly: true,
        useErrorDialogs: true,
      ),
    );
    if (!didAuthenticate) {
      throw StateError('تم إلغاء التحقق بالبصمة.');
    }

    final position = await LocationService.current();
    final operationId = const Uuid().v4();
    final installationId = await ref.read(installationIdProvider.future);
    final data = await retryWithBackoff(
      () => ref
          .read(supabaseProvider)
          .rpc<Map<String, dynamic>>(
            'punch_attendance_local_biometric_v1',
            params: {
              'p_operation_id': operationId,
              'p_event_type': eventType,
              'p_installation_id': installationId,
              'p_latitude': position.latitude,
              'p_longitude': position.longitude,
              'p_accuracy_meters': position.accuracy,
              'p_is_mock': position.isMocked,
            },
          ),
    );
    ref.invalidate(attendanceStateProvider);
    ref.invalidate(myAttendanceHistoryProvider);
    ref.invalidate(employeeHomeProvider);
    return data;
  }

  Future<void> revokePasskey(String credentialId, String reason) async {
    await ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'revoke_my_passkey',
          params: {
            'p_credential_id': credentialId,
            'p_reason': reason.trim().isEmpty ? null : reason.trim(),
          },
        );
    ref.invalidate(myPasskeysProvider);
    ref.invalidate(attendanceStateProvider);
  }

  /// هاتف مفقود — يلغي الجهاز النشط ويسمح بتسجيل جهاز جديد
  Future<void> requestDeviceReplacement(String reason) async {
    await ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'request_device_replacement',
          params: {
            'p_reason': reason.trim().isEmpty ? null : reason.trim(),
          },
        );
    ref.invalidate(myPasskeysProvider);
    ref.invalidate(attendanceStateProvider);
  }

  Future<MobileActionTarget> resolveAction(MobileActionItem item) async {
    return ref.read(mobileActionTargetProvider(item).future);
  }

  Future<void> acknowledge(MobileFeedItem item) async {
    final function = item.kind == 'decision'
        ? 'acknowledge_decision'
        : 'acknowledge_announcement';
    final params = item.kind == 'decision'
        ? {'p_decision_id': item.id, 'p_acknowledge': true}
        : {'p_announcement_id': item.id};
    await ref.read(supabaseProvider).rpc<dynamic>(function, params: params);
    ref.invalidate(mobileFeedProvider);
    ref.invalidate(employeeHomeProvider);
  }
}

final mobileProfileProvider = FutureProvider<MobileProfile>((ref) async {
  final data = await rpcWithTimeout(
    ref.watch(supabaseProvider).rpc<dynamic>('get_my_mobile_profile'),
  );
  return MobileProfile.fromJson(_asMap(data));
});

final mobileTasksProvider = FutureProvider<List<MobileTask>>((ref) async {
  final data = await rpcWithTimeout(
    ref.watch(supabaseProvider).rpc<dynamic>('get_my_mobile_tasks', params: {'p_limit': 100}),
  );
  return _asList(data).map(MobileTask.fromJson).toList(growable: false);
});

final mobileTeamProvider = FutureProvider<List<MobileTeamMember>>((ref) async {
  final data = await rpcWithTimeout(
    ref.watch(supabaseProvider).rpc<dynamic>('get_my_mobile_team', params: {'p_limit': 100}),
  );
  return _asList(data).map(MobileTeamMember.fromJson).toList(growable: false);
});

final mobileDailyReportsProvider =
    FutureProvider.family<List<MobileDailyReport>, String?>((
      ref,
      employeeId,
    ) async {
      final data = await rpcWithTimeout(
        ref
            .watch(supabaseProvider)
            .rpc<dynamic>(
              'get_mobile_daily_reports',
              params: {'p_employee_id': employeeId, 'p_limit': 30},
            ),
      );
      return _asList(
        data,
      ).map(MobileDailyReport.fromJson).toList(growable: false);
    });

extension MobileDailyCommands on MobileCommands {
  Future<void> transitionTask(String taskId, String status) async {
    await ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'transition_my_task',
          params: {'p_task_id': taskId, 'p_status': status},
        );
    ref.invalidate(mobileTasksProvider);
    ref.invalidate(employeeHomeProvider);
  }

  Future<void> markNotificationsRead([List<String>? ids]) async {
    await ref
        .read(supabaseProvider)
        .rpc<dynamic>('mark_my_notifications_read', params: {'p_ids': ids});
    ref.invalidate(myNotificationsProvider);
    ref.invalidate(employeeHomeProvider);
  }

  Future<void> saveDailyReport({
    required DateTime reportDate,
    required String achievements,
    String? blockers,
    String? tomorrowPlan,
  }) async {
    final date =
        '${reportDate.year.toString().padLeft(4, '0')}-${reportDate.month.toString().padLeft(2, '0')}-${reportDate.day.toString().padLeft(2, '0')}';
    await ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'upsert_my_daily_report',
          params: {
            'p_report_date': date,
            'p_achievements': achievements,
            'p_blockers': blockers,
            'p_tomorrow_plan': tomorrowPlan,
          },
        );
    ref.invalidate(mobileDailyReportsProvider(null));
    ref.invalidate(employeeHomeProvider);
  }

  Future<void> reviewDailyReport({
    required String reportId,
    required String comment,
    required String employeeId,
  }) async {
    await ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'review_daily_report',
          params: {
            'p_report_id': reportId,
            'p_manager_comment': comment.trim(),
          },
        );
    ref.invalidate(mobileDailyReportsProvider(employeeId));
    ref.invalidate(mobileTeamProvider);
  }

  Future<void> createTeamTask({
    required String employeeId,
    required String title,
    String? description,
    String priority = 'medium',
    DateTime? dueDate,
  }) async {
    final due = dueDate == null
        ? null
        : '${dueDate.year.toString().padLeft(4, '0')}-${dueDate.month.toString().padLeft(2, '0')}-${dueDate.day.toString().padLeft(2, '0')}';
    await ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'create_team_task',
          params: {
            'p_employee_id': employeeId,
            'p_title': title,
            'p_description': description,
            'p_priority': priority,
            'p_due_date': due,
          },
        );
    ref.invalidate(mobileTeamProvider);
    ref.invalidate(managerDashboardProvider);
  }
}

final myLeaveBalancesProvider = FutureProvider<List<MobileLeaveBalance>>((
  ref,
) async {
  final data = await rpcWithTimeout(
    ref.watch(supabaseProvider).rpc<dynamic>(
          'get_my_leave_balances',
          params: {'p_year': DateTime.now().year},
        ),
  );
  return _asList(data).map(MobileLeaveBalance.fromJson).toList(growable: false);
});

final myAttendanceServicesProvider = FutureProvider<MobileAttendanceServices>((
  ref,
) async {
  final now = DateTime.now();
  final from = now.subtract(const Duration(days: 31));
  final to = now.add(const Duration(days: 45));
  String date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  final data = await rpcWithTimeout(
    ref.watch(supabaseProvider).rpc<dynamic>(
          'get_my_attendance_services',
          params: {'p_from': date(from), 'p_to': date(to)},
        ),
  );
  return MobileAttendanceServices.fromJson(_asMap(data));
});

final myDisputePortalProvider = FutureProvider<MobileDisputePortal>((
  ref,
) async {
  final data = await rpcWithTimeout(
    ref.watch(supabaseProvider).rpc<dynamic>('get_my_dispute_portal'),
  );
  return MobileDisputePortal.fromJson(_asMap(data));
});

/// V17 §14 — Executive dispute inbox (admin-action workflow)
final executiveDisputeInboxProvider = FutureProvider<ExecutiveDisputeInbox>((
  ref,
) async {
  final data = await rpcWithTimeout(
    ref.watch(supabaseProvider).rpc<dynamic>('get_executive_dispute_inbox'),
  );
  return ExecutiveDisputeInbox.fromJson(_asMap(data));
});

/// V18 — Committee dispute portal (all-cases card-list for committee members)
final committeeDisputePortalProvider = FutureProvider<CommitteeDisputePortal>((
  ref,
) async {
  final data = await rpcWithTimeout(
    ref.watch(supabaseProvider).rpc<dynamic>('get_committee_dispute_portal'),
  );
  return CommitteeDisputePortal.fromJson(_asMap(data));
});

/// 0198 — آراء/توصيات أعضاء اللجنة لقضية محددة
final disputeCaseRecommendationsProvider =
    FutureProvider.family<DisputeCaseRecommendations, String>((ref, caseId) async {
  final data = await rpcWithTimeout(
    ref.watch(supabaseProvider).rpc<dynamic>('get_dispute_case_recommendations', params: {
      'p_case_id': caseId,
    }),
  );
  return DisputeCaseRecommendations.fromJson(_asMap(data));
});

final myOffboardingPortalProvider = FutureProvider<MobileOffboardingPortal>((
  ref,
) async {
  final data = await rpcWithTimeout(
    ref.watch(supabaseProvider).rpc<dynamic>('get_my_offboarding_portal'),
  );
  return MobileOffboardingPortal.fromJson(_asMap(data));
});

extension MobileSelfServiceCommands on MobileCommands {
  Future<void> requestAttendanceCorrection({
    required DateTime workDate,
    required String type,
    required String reason,
    DateTime? checkIn,
    DateTime? checkOut,
    String? requestedStatus,
  }) async {
    String date(DateTime value) =>
        '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    await ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'request_attendance_correction',
          params: {
            'p_work_date': date(workDate),
            'p_type': type,
            'p_reason': reason.trim(),
            'p_check_in': checkIn?.toUtc().toIso8601String(),
            'p_check_out': checkOut?.toUtc().toIso8601String(),
            'p_status': requestedStatus,
            'p_attachment_path': null,
          },
        );
    ref.invalidate(myAttendanceServicesProvider);
    ref.invalidate(myAttendanceHistoryProvider);
  }

  Future<String> submitDispute({
    required String title,
    required String description,
    required String caseType,
    required String priority,
    required List<String> respondentIds,
    List<String> witnessIds = const [],
    String? incidentLocation,
    String? requestedAction,
    bool confidential = true,
  }) async {
    final data = await ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'submit_my_dispute',
          params: {
            'p_title': title.trim(),
            'p_description': description.trim(),
            'p_case_type': caseType,
            'p_priority': priority,
            'p_incident_location': incidentLocation?.trim(),
            'p_parties': [
              for (final id in respondentIds)
                {'employeeId': id, 'type': 'respondent'},
            ],
            'p_witnesses': [
              for (final id in witnessIds)
                {'employeeId': id, 'type': 'witness'},
            ],
            'p_requested_action': requestedAction?.trim(),
            'p_confidential': confidential,
            'p_truth_confirmed': true,
            'p_confidentiality_accepted': true,
          },
        );
    ref.invalidate(myDisputePortalProvider);
    return data as String;
  }

  /// V23: نموذج مبسط — بدون أولوية أو موقع أو مرفقات
  Future<String> submitDisputeV23({
    required String title,
    required String description,
    required String caseType,
    required List<String> respondentIds,
    List<String> witnessIds = const [],
  }) async {
    final data = await ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'submit_my_dispute_v23',
          params: {
            'p_title': title.trim(),
            'p_description': description.trim(),
            'p_case_type': caseType,
            'p_parties': [
              for (final id in respondentIds)
                {'employeeId': id, 'type': 'respondent'},
            ],
            'p_witnesses': [
              for (final id in witnessIds)
                {'employeeId': id, 'type': 'witness'},
            ],
            'p_truth_confirmed': true,
            'p_confidentiality_accepted': true,
          },
        );
    ref.invalidate(myDisputePortalProvider);
    return data as String;
  }

  Future<void> uploadDisputeEvidence({
    required String caseId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final client = ref.read(supabaseProvider);
    final normalizedMime = MobileCommands._allowedImageMime(mimeType, fileName);
    final extension = switch (normalizedMime) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
    final path = '$caseId/${const Uuid().v4()}.$extension';
    await client.storage.from('dispute-evidence').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: normalizedMime, upsert: false),
        );
    try {
      await client.rpc<dynamic>(
        'register_dispute_evidence',
        params: {
          'p_case_id': caseId,
          'p_title': fileName,
          'p_storage_path': path,
          'p_mime_type': normalizedMime,
          'p_file_size_bytes': bytes.length,
          'p_visibility': 'submitter_and_committee',
          'p_description': null,
        },
      );
    } catch (_) {
      await client.storage.from('dispute-evidence').remove([path]);
      rethrow;
    }
    ref.invalidate(myDisputePortalProvider);
  }

  Future<void> cancelDispute(String caseId, String reason) async {
    await ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'cancel_my_dispute',
          params: {'p_case_id': caseId, 'p_reason': reason.trim()},
        );
    ref.invalidate(myDisputePortalProvider);
  }

  Future<void> appealDisputeDecision(String decisionId, String reason) async {
    await ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'submit_dispute_appeal',
          params: {'p_decision_id': decisionId, 'p_reason': reason.trim()},
        );
    ref.invalidate(myDisputePortalProvider);
  }
}

/// V17 §14 — Executive admin-action commands
extension ExecutiveDisputeCommands on MobileCommands {
  /// 0198 — تقديم رأي/توصية على قضية
  Future<void> submitDisputeRecommendation({
    required String caseId,
    required String text,
    String statementType = 'recommendation',
  }) async {
    await ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'submit_dispute_statement',
          params: {
            'p_case_id': caseId,
            'p_statement_type': statementType,
            'p_statement_text': text.trim(),
            'p_visibility': 'committee_only',
          },
        );
    ref.invalidate(disputeCaseRecommendationsProvider(caseId));
    ref.invalidate(committeeDisputePortalProvider);
  }

  Future<void> decideAdminAction({
    required String caseId,
    required String decision,
    required String reason,
    String? modifiedAction,
    String? modifiedDetail,
  }) async {
    await ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'decide_admin_action',
          params: {
            'p_case_id': caseId,
            'p_decision': decision,
            'p_reason': reason.trim(),
            'p_modified_action': modifiedAction,
            'p_modified_detail': modifiedDetail?.trim(),
          },
        );
    ref.invalidate(executiveDisputeInboxProvider);
    ref.invalidate(committeeDisputePortalProvider);
    ref.invalidate(myDisputePortalProvider);
  }
}

final myLearningCatalogProvider = FutureProvider<MobileLearningCatalog>((
  ref,
) async {
  final data = await rpcWithTimeout(
    ref.watch(supabaseProvider).rpc<dynamic>('get_my_learning_catalog'),
  );
  return MobileLearningCatalog.fromJson(_asMap(data));
});

extension MobileLearningCommands on MobileCommands {
  Future<void> transitionLearning(
    String enrollmentId,
    String status, {
    int? progress,
    double? score,
  }) async {
    await ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'transition_learning_enrollment',
          params: {
            'p_enrollment_id': enrollmentId,
            'p_status': status,
            'p_progress': progress,
            'p_score': score,
          },
        );
    ref.invalidate(myLearningCatalogProvider);
  }
}

final myServicePortalProvider = FutureProvider<MobileServicePortal>((
  ref,
) async {
  final data = await rpcWithTimeout(
    ref.watch(supabaseProvider).rpc<dynamic>('get_my_service_portal'),
  );
  return MobileServicePortal.fromJson(_asMap(data));
});
final myPayslipsProvider = FutureProvider<List<MobilePayslip>>((ref) async {
  final data = await rpcWithTimeout(
    ref.watch(supabaseProvider).rpc<dynamic>('get_my_payslips'),
  );
  return _asList(data).map(MobilePayslip.fromJson).toList(growable: false);
});

extension MobileServiceCommands on MobileCommands {
  Future<void> submitServiceRequest({
    required String catalogItemId,
    required String title,
    String? description,
    String priority = 'normal',
  }) async {
    await ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'submit_my_service_request',
          params: {
            'p_catalog_item_id': catalogItemId,
            'p_title': title.trim(),
            'p_description': description?.trim(),
            'p_priority': priority,
            'p_payload': <String, dynamic>{},
          },
        );
    ref.invalidate(myServicePortalProvider);
  }
}
