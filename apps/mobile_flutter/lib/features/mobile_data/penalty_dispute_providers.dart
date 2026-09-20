import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── نموذج الطعن ──────────────────────────────────────────────────────────

/// طعن على غرامة حضور فورية — يُعرض للموظف في صفحة الطعون.
class MobilePenaltyDispute {
  const MobilePenaltyDispute({
    required this.id,
    required this.penaltyId,
    required this.reason,
    required this.status,
    required this.reviewedBy,
    required this.reviewNotes,
    required this.createdAt,
    this.reviewedAt,
  });

  factory MobilePenaltyDispute.fromJson(Map<String, dynamic> j) =>
      MobilePenaltyDispute(
        id: j['id'] as String? ?? '',
        penaltyId: j['penalty_id'] as String? ?? j['penaltyId'] as String? ?? '',
        reason: j['reason'] as String? ?? '',
        status: j['status'] as String? ?? 'pending',
        reviewedBy: j['reviewed_by'] as String? ?? j['reviewedBy'] as String?,
        reviewNotes:
            j['review_notes'] as String? ?? j['reviewNotes'] as String?,
        createdAt: _reqDate(j['created_at'] ?? j['createdAt']),
        reviewedAt: _optDate(j['reviewed_at'] ?? j['reviewedAt']),
      );

  final String id;
  final String penaltyId;
  final String reason;
  final String status;
  final String? reviewedBy;
  final String? reviewNotes;
  final DateTime createdAt;
  final DateTime? reviewedAt;
}

DateTime _reqDate(dynamic value) =>
    DateTime.tryParse(value?.toString() ?? '') ?? DateTime(0);

DateTime? _optDate(dynamic value) =>
    value == null ? null : DateTime.tryParse(value.toString());

// ── مزوّد جلب الطعون ───────────────────────────────────────────────────

/// جلب طعون الموظف الحالية عبر get_penalty_disputes RPC.
final penaltyDisputesProvider =
    FutureProvider<List<MobilePenaltyDispute>>((ref) async {
  final data = await rpcWithTimeout(
    ref
        .watch(supabaseProvider)
        .rpc<dynamic>('get_penalty_disputes'),
  );
  return _asList(data)
      .map(MobilePenaltyDispute.fromJson)
      .toList(growable: false);
});

List<Map<String, dynamic>> _asList(dynamic value) =>
    (value as List<dynamic>? ?? const [])
        .where((e) => e != null)
        .map((e) => _asMap(e))
        .toList(growable: false);

Map<String, dynamic> _asMap(dynamic value) {
  if (value == null) return const {};
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

// ── تقديم طعن ───────────────────────────────────────────────────────────

/// تقديم طعن على غرامة عبر submit_penalty_dispute RPC.
/// تُعيد الـ new dispute id عند النجاح.
Future<String> submitPenaltyDispute({
  required String penaltyId,
  required String reason,
}) async {
  final data = await rpcWithTimeout(
    Supabase.instance.client.rpc<dynamic>(
      'submit_penalty_dispute',
      params: {
        'p_penalty_id': penaltyId,
        'p_reason': reason,
      },
    ),
  );
  final map = _asMap(data);
  return map['id'] as String? ?? map['dispute_id'] as String? ?? '';
}
