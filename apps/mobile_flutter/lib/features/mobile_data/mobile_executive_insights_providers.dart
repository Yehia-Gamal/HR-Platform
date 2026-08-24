import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_executive_insights_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Map<String, dynamic> _asMap(dynamic value) =>
    Map<String, dynamic>.from(value as Map<dynamic, dynamic>);

List<Map<String, dynamic>> _asList(dynamic value) =>
    (value as List<dynamic>? ?? const []).map(_asMap).toList(growable: false);

/// اتجاه الحضور اليومي (0456) — سلسلة آخر N يوم للرسم البياني التنفيذي.
/// الدالة security invoker: RLS على attendance_daily يحدد النطاق
/// (التنفيذي يرى المنظمة، المدير فريقه).
final mobileAttendanceTrendProvider =
    FutureProvider.family<List<AttendanceTrendPoint>, int>((ref, days) async {
      final data = await rpcWithTimeout(
        ref
            .watch(supabaseProvider)
            .rpc<dynamic>(
              'get_mobile_attendance_trend',
              params: {'p_days': days},
            ),
      );
      return _asList(
        data,
      ).map(AttendanceTrendPoint.fromJson).toList(growable: false);
    });

final mobileExecutiveBriefProvider =
    FutureProvider.family<MobileExecutiveBrief, String>((ref, period) async {
      final data = await rpcWithTimeout(
        ref
            .watch(supabaseProvider)
            .rpc<dynamic>(
              'get_mobile_executive_brief',
              params: {'p_period': period},
            ),
      );
      return MobileExecutiveBrief.fromJson(_asMap(data));
    });

final mobileExecutivePeopleProvider =
    FutureProvider.family<List<ExecutivePersonItem>, String>((
      ref,
      search,
    ) async {
      final data = await rpcWithTimeout(
        ref
            .watch(supabaseProvider)
            .rpc<dynamic>(
              'get_mobile_executive_people',
              params: {'p_search': search, 'p_limit': 80},
            ),
      );
      return _asList(
        data,
      ).map(ExecutivePersonItem.fromJson).toList(growable: false);
    });

final mobileExecutiveEmployeeSummaryProvider =
    FutureProvider.family<ExecutiveEmployeeSummary, String>((
      ref,
      employeeId,
    ) async {
      final data = await rpcWithTimeout(
        ref
            .watch(supabaseProvider)
            .rpc<dynamic>(
              'get_mobile_executive_employee_summary',
              params: {'p_employee_id': employeeId},
            ),
      );
      return ExecutiveEmployeeSummary.fromJson(_asMap(data));
    });
