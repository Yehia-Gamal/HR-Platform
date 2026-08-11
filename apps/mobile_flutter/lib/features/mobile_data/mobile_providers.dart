import 'dart:io';

import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/network/offline_cache.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/location_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/passkey_attendance_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/release_governance.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'mobile_location_providers.dart';
part 'mobile_commands.dart';

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
      final data = await _withTimeout(ref
          .watch(supabaseProvider)
          .rpc<dynamic>(
            'resolve_mobile_action_target',
            params: {'p_action_id': item.id, 'p_kind': item.kind},
          ));
      return MobileActionTarget.fromJson(_asMap(data));
    });
final mobileRequestDetailProvider =
    FutureProvider.family<MobileRequestDetail, String>((ref, requestId) async {
      final data = await _withTimeout(ref
          .watch(supabaseProvider)
          .rpc<dynamic>(
            'get_mobile_request_detail',
            params: {'p_request_id': requestId},
          ));
      return MobileRequestDetail.fromJson(_asMap(data));
    });
final mobileFeedDetailProvider =
    FutureProvider.family<MobileFeedItem, ({String kind, String id})>((
      ref,
      key,
    ) async {
      final data = await _withTimeout(ref
          .watch(supabaseProvider)
          .rpc<dynamic>(
            'get_mobile_feed_item',
            params: {'p_kind': key.kind, 'p_item_id': key.id},
          ));
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
  await _withTimeout(ref
      .watch(supabaseProvider)
      .rpc<void>(
        'mark_my_notification_delivery',
        params: {'p_notification_id': notificationId, 'p_status': 'opened'},
      ));
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
    // 0226: Pass installation_id so the server checks THIS device specifically,
    // not all devices. Prevents canPunch=true on a replaced/revoked device.
    final installationId = await ref.watch(installationIdProvider.future);
    final data = await _withTimeout(ref
        .watch(supabaseProvider)
        .rpc<dynamic>('get_my_attendance_state', params: {
          'p_installation_id': installationId,
        }));
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

/// دليل الموظفين الموحد — بحث بالاسم أو الكود أو الإدارة، متاح لجميع الأدوار.
final employeeDirectoryProvider = FutureProvider.autoDispose
    .family<List<DirectoryEmployee>, String>((ref, search) async {
      final data = await ref
          .watch(supabaseProvider)
          .rpc<dynamic>(
            'get_mobile_employee_directory',
            params: {'p_search': search, 'p_limit': 40},
          )
          .timeout(const Duration(seconds: 10));
      return _asList(data).map(DirectoryEmployee.fromJson).toList(growable: false);
    });

final disputeDirectoryProvider =
    FutureProvider.family<List<DisputeDirectoryEmployee>, String>((
      ref,
      search,
    ) async {
      final data = await _withTimeout(ref
          .watch(supabaseProvider)
          .rpc<dynamic>(
            'get_dispute_participant_directory',
            params: {'p_search': search, 'p_limit': 100},
          ));
      return _asList(
        data,
      ).map(DisputeDirectoryEmployee.fromJson).toList(growable: false);
    });

/// جلسات القضية المُعقدة — مطلوبة لإصدار قرار اللجنة
final disputeCaseHeldSessionsProvider =
    FutureProvider.family<List<DisputeHeldSession>, String>((
      ref,
      caseId,
    ) async {
      final data = await _withTimeout(ref
          .watch(supabaseProvider)
          .from('dispute_sessions')
          .select('id, session_type, status, scheduled_at, held_at, location')
          .eq('case_id', caseId)
          .eq('status', 'held')
          .order('held_at', ascending: false));
      return (data as List<dynamic>)
          .map((e) => DisputeHeldSession.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList(growable: false);
    });

/// أطراف القضية (مشتكى عليه / شاهد / مقدّم الشكوى / ذو صلة)
final disputeCasePartiesProvider =
    FutureProvider.family<List<DisputeCaseParty>, String>((
      ref,
      caseId,
    ) async {
      final data = await _withTimeout(ref
          .watch(supabaseProvider)
          .from('dispute_parties')
          .select('id, employee_id, party_type, notification_status, employees(full_name_ar)')
          .eq('case_id', caseId));
      return (data as List<dynamic>)
          .map((e) => DisputeCaseParty.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList(growable: false);
    });

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
  // نطاق زمني UTC ليظل متوافقاً مع الطابع الزمني المخزّن في قاعدة البيانات.
  final now = DateTime.now().toUtc();
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


/// V17 §14 — Executive admin-action commands
final myLearningCatalogProvider = FutureProvider<MobileLearningCatalog>((
  ref,
) async {
  final data = await rpcWithTimeout(
    ref.watch(supabaseProvider).rpc<dynamic>('get_my_learning_catalog'),
  );
  return MobileLearningCatalog.fromJson(_asMap(data));
});


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


// ─── الميزات الجديدة: مشاركة موقع استباقية + تفاعل التقارير ──────────────

/// صفحة التقارير اليومية العامة — يراها كل المستخدمين.
/// تستخدم cursor pagination (p_before) لتحميل لا نهائي.
final dailyReportsFeedProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String?>((ref, beforeDate) async {
  final params = <String, dynamic>{'p_limit': 20};
  if (beforeDate != null) params['p_before'] = beforeDate;
  final data = await rpcWithTimeout(
    ref.watch(supabaseProvider).rpc<dynamic>(
      'get_public_daily_reports_feed',
      params: params,
    ),
  );
  final list = data as List<dynamic>? ?? [];
  return list
      .map((e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>))
      .toList(growable: false);
});

