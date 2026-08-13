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

final mobileManagerOperationsProvider = FutureProvider<MobileManagerOperations>(
  (ref) async {
    final today = DateTime.now();
    final data = await rpcWithTimeout(
      ref
          .watch(supabaseProvider)
          .rpc<dynamic>(
            'get_mobile_manager_operations',
            params: {
              'p_from': _wireDate(today),
              'p_to': _wireDate(today.add(const Duration(days: 14))),
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
