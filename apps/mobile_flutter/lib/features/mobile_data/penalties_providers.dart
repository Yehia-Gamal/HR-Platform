import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// غرامات الحضور الفورية للموظفين بأسمائهم — get_instant_penalties (0642):
/// الإدارة وHR والمالية يرون الجميع، والمدير فريقه المباشر، والموظف نفسه.
final teamInstantPenaltiesProvider =
    FutureProvider.autoDispose<List<MobileInstantPenalty>>((ref) async {
      final data = await rpcWithTimeout(
        ref
            .watch(supabaseProvider)
            .rpc<dynamic>('get_instant_penalties', params: {'p_limit': 500}),
      );
      return (data as List<dynamic>? ?? const [])
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (e) => MobileInstantPenalty.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(growable: false);
    });

/// ملخص صندوق الزمالة والتكافل — get_fellowship_fund_summary.
final fellowshipFundSummaryProvider =
    FutureProvider.autoDispose<FellowshipFundSummary>((ref) async {
      final data = await rpcWithTimeout(
        ref.watch(supabaseProvider).rpc<dynamic>('get_fellowship_fund_summary'),
      );
      return FellowshipFundSummary.fromJson(
        Map<String, dynamic>.from(data as Map<dynamic, dynamic>),
      );
    });

/// حركات صندوق الزمالة (الأسماء للإدارة وHR فقط — 0642).
final fellowshipFundTransactionsProvider =
    FutureProvider.autoDispose<List<FellowshipFundTransaction>>((ref) async {
      final data = await rpcWithTimeout(
        ref
            .watch(supabaseProvider)
            .rpc<dynamic>(
              'get_fellowship_fund_transactions',
              params: {'p_limit': 100, 'p_offset': 0},
            ),
      );
      return (data as List<dynamic>? ?? const [])
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (e) => FellowshipFundTransaction.fromJson(
              Map<String, dynamic>.from(e),
            ),
          )
          .toList(growable: false);
    });

double _num(dynamic v) =>
    v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

String? _str(dynamic v) {
  final s = v?.toString().trim();
  return s == null || s.isEmpty || s == 'null' ? null : s;
}

class FellowshipFundSummary {
  const FellowshipFundSummary({
    required this.currentBalance,
    required this.totalInflows,
    required this.totalOutflows,
    required this.inflowsCount,
    required this.outflowsCount,
    required this.monthlyInflows,
    required this.monthlyOutflows,
    required this.categories,
  });

  factory FellowshipFundSummary.fromJson(Map<String, dynamic> j) =>
      FellowshipFundSummary(
        currentBalance: _num(j['currentBalance']),
        totalInflows: _num(j['totalInflows']),
        totalOutflows: _num(j['totalOutflows']),
        inflowsCount: _int(j['inflowsCount']),
        outflowsCount: _int(j['outflowsCount']),
        monthlyInflows: _num(j['monthlyInflows']),
        monthlyOutflows: _num(j['monthlyOutflows']),
        categories: (j['categoryBreakdown'] as List<dynamic>? ?? const [])
            .whereType<Map<dynamic, dynamic>>()
            .map(
              (e) => (
                category: _str(e['category']) ?? 'غير مصنّف',
                type: _str(e['type']) ?? 'inflow',
                total: _num(e['totalAmount']),
                count: _int(e['count']),
              ),
            )
            .toList(growable: false),
      );

  final double currentBalance;
  final double totalInflows;
  final double totalOutflows;
  final int inflowsCount;
  final int outflowsCount;
  final double monthlyInflows;
  final double monthlyOutflows;
  final List<({String category, String type, double total, int count})>
  categories;
}

class FellowshipFundTransaction {
  const FellowshipFundTransaction({
    required this.id,
    required this.isInflow,
    required this.amount,
    required this.createdAt,
    this.sourceType,
    this.category,
    this.reason,
    this.employeeName,
    this.performerName,
    this.balanceAfter,
    this.notes,
  });

  factory FellowshipFundTransaction.fromJson(Map<String, dynamic> j) =>
      FellowshipFundTransaction(
        id: _str(j['id']) ?? '',
        isInflow: (_str(j['transactionType']) ?? 'inflow') == 'inflow',
        amount: _num(j['amount']),
        createdAt:
            DateTime.tryParse('${j['createdAt'] ?? ''}')?.toLocal() ??
            DateTime.now(),
        sourceType: _str(j['sourceType']),
        category: _str(j['category']),
        reason: _str(j['reason']),
        employeeName: _str(j['employeeName']),
        performerName: _str(j['performerName']),
        balanceAfter: j['balanceAfter'] == null
            ? null
            : _num(j['balanceAfter']),
        notes: _str(j['notes']),
      );

  final String id;
  final bool isInflow;
  final double amount;
  final DateTime createdAt;
  final String? sourceType;
  final String? category;
  final String? reason;

  /// اسم صاحب الحركة — متاح بشفافية للجميع لترسيخ التكافل الاجتماعي والانضباط.
  final String? employeeName;
  final String? performerName;
  final double? balanceAfter;
  final String? notes;
}

/// هل يملك المستخدم رؤية غرامات غيره؟ أصبحت متاحة لجميع منسوبي الجمعية بشفافية.
bool canSeeOthersPenalties(WidgetRef ref) {
  final access = ref.watch(accessContextProvider).value;
  return access != null;
}

/// هل يملك المستخدم إجراءات الغرامات (تأكيد السداد، الإلغاء، رفع الإيقاف،
/// مراجعة الأعذار)؟ الخادم يتحقق من الصلاحية في كل إجراء.
bool canManagePenalties(WidgetRef ref) {
  final access = ref.watch(accessContextProvider).value;
  if (access == null) return false;
  const roles = {
    'admin',
    'system-admin',
    'executive-secretary',
    'executive',
    'executive-director',
    'hr-manager',
    'hr-specialist',
  };
  return access.roles.any(roles.contains);
}

/// الصرف من صندوق الزمالة: الإدارة العليا والوصول الكامل فقط.
bool canWithdrawFromFund(WidgetRef ref) {
  final access = ref.watch(accessContextProvider).value;
  if (access == null) return false;
  const roles = {
    'admin',
    'system-admin',
    'executive-secretary',
    'executive',
    'executive-director',
  };
  return access.roles.any(roles.contains);
}


/// بيانات الموظف الموقوف عن العمل والغرامات المترتبة عليه
class SuspendedEmployeeInfo {
  const SuspendedEmployeeInfo({
    required this.employeeId,
    required this.employeeName,
    this.employeeCode,
    this.departmentName,
    this.jobTitle,
    this.photoUrl,
    this.phone,
    required this.status,
    required this.isActive,
    required this.totalCurrentDue,
    required this.totalOriginalDue,
    required this.has500Penalty,
    required this.unpaidCount,
    required this.penalties,
  });

  factory SuspendedEmployeeInfo.fromJson(Map<String, dynamic> j) =>
      SuspendedEmployeeInfo(
        employeeId: _str(j['employeeId']) ?? '',
        employeeName: _str(j['employeeName']) ?? 'موظف',
        employeeCode: _str(j['employeeCode']),
        departmentName: _str(j['departmentName']),
        jobTitle: _str(j['jobTitle']),
        photoUrl: _str(j['photoUrl']),
        phone: _str(j['phone']),
        status: _str(j['status']) ?? 'active',
        isActive: j['isActive'] == true,
        totalCurrentDue: _num(j['totalCurrentDue']),
        totalOriginalDue: _num(j['totalOriginalDue']),
        has500Penalty: j['has500Penalty'] == true,
        unpaidCount: _int(j['unpaidCount']),
        penalties: (j['penalties'] as List<dynamic>? ?? const [])
            .whereType<Map<dynamic, dynamic>>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(growable: false),
      );

  final String employeeId;
  final String employeeName;
  final String? employeeCode;
  final String? departmentName;
  final String? jobTitle;
  final String? photoUrl;
  final String? phone;
  final String status;
  final bool isActive;
  final double totalCurrentDue;
  final double totalOriginalDue;
  final bool has500Penalty;
  final int unpaidCount;
  final List<Map<String, dynamic>> penalties;
}

/// قائمة الموظفين الموقوفين عن العمل للإدارة — get_suspended_employees_admin (0712).
final suspendedEmployeesProvider =
    FutureProvider.autoDispose<List<SuspendedEmployeeInfo>>((ref) async {
      final data = await rpcWithTimeout(
        ref.watch(supabaseProvider).rpc<dynamic>('get_suspended_employees_admin'),
      );
      return (data as List<dynamic>? ?? const [])
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (e) => SuspendedEmployeeInfo.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(growable: false);
    });
