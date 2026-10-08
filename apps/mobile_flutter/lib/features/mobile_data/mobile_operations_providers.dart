import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_operations_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Map<String, dynamic> _asMap(dynamic value) =>
    Map<String, dynamic>.from(value as Map<dynamic, dynamic>);

String _wireDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

/// متحكم الشهر المختار لعرض الملخص التشغيلي للفريق
class ManagerOperationsMonthController extends Notifier<DateTime> {
  @override
  DateTime build() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, 1);
  }

  void setMonth(DateTime month) {
    state = DateTime(month.year, month.month, 1);
  }

  void changeMonth(int delta) {
    state = DateTime(state.year, state.month + delta, 1);
  }

  void resetToCurrentMonth() {
    final now = DateTime.now();
    state = DateTime(now.year, now.month, 1);
  }
}

final mobileManagerOperationsMonthProvider =
    NotifierProvider<ManagerOperationsMonthController, DateTime>(
  ManagerOperationsMonthController.new,
);

final mobileManagerOperationsProvider = FutureProvider<MobileManagerOperations>(
  (ref) async {
    final selectedMonth = ref.watch(mobileManagerOperationsMonthProvider);
    final startOfMonth = DateTime(selectedMonth.year, selectedMonth.month, 1);
    final endOfMonth = DateTime(selectedMonth.year, selectedMonth.month + 1, 0);

    final data = await rpcWithTimeout(
      ref
          .watch(supabaseProvider)
          .rpc<dynamic>(
            'get_mobile_manager_operations',
            params: {
              'p_from': _wireDate(startOfMonth),
              'p_to': _wireDate(endOfMonth),
            },
          ),
    );
    return MobileManagerOperations.fromJson(_asMap(data));
  },
);

final mobileExecutiveCommandCenterProvider =
    FutureProvider<MobileExecutiveCommandCenter>((ref) async {
      final data = await rpcWithTimeout(
        ref
            .watch(supabaseProvider)
            .rpc<dynamic>('get_mobile_executive_command_center'),
      );
      return MobileExecutiveCommandCenter.fromJson(_asMap(data));
    });

// مركز العمليات (إدارة التشغيل) — get_mobile_operations_center (mig 0408):
// المهام المفتوحة + المهمات + القوافل بنطاق صلاحية المستخدم.
final mobileOperationsCenterProvider =
    FutureProvider<MobileOperationsCenter>((ref) async {
      final data = await rpcWithTimeout(
        ref
            .watch(supabaseProvider)
            .rpc<dynamic>('get_mobile_operations_center'),
      );
      return MobileOperationsCenter.fromJson(_asMap(data));
    });

final mobileOperationsCommandsProvider = Provider<MobileOperationsCommands>(
  MobileOperationsCommands.new,
);

class MobileOperationsCommands {
  MobileOperationsCommands(this.ref);

  final Ref ref;

  Future<void> castDecisionVote({
    required String pollId,
    List<String> optionIds = const [],
    double? rating,
  }) async {
    await ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'cast_decision_vote',
          params: {
            'p_poll_id': pollId,
            'p_option_ids': optionIds,
            'p_rating': rating,
          },
        );
    ref.invalidate(mobileExecutiveCommandCenterProvider);
  }
}
