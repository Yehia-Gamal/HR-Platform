import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class MobileRequestDetailPage extends ConsumerWidget {
  const MobileRequestDetailPage({required this.requestId, super.key});

  final String requestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(mobileRequestDetailProvider(requestId));
    return Scaffold(
      appBar: AppBar(title: const Text('تفاصيل الطلب')),
      body: SafeArea(
        child: detail.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _ErrorState(
            message: humanizeError(error),
            onRetry: () =>
                ref.invalidate(mobileRequestDetailProvider(requestId)),
          ),
          data: (request) => RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(mobileRequestDetailProvider(requestId)),
            child: _RequestContent(request: request),
          ),
        ),
      ),
    );
  }
}

class _RequestContent extends ConsumerWidget {
  const _RequestContent({required this.request});

  final MobileRequestDetail request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formatter = DateFormat('d MMMM y، h:mm a', 'ar');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    MobileStatusPill(request.status),
                    const Spacer(),
                    Text(
                      '#${request.number}',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  request.title ?? _typeLabel(request.type),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${request.employeeName} · ${request.employeeCode ?? 'بدون كود'}',
                ),
                const Divider(height: 28),
                _row('نوع الطلب', _typeLabel(request.type)),
                _row('حالة المسار', request.workflowStatus),
                _row(
                  'تاريخ الإنشاء',
                  formatter.format(request.createdAt.toLocal()),
                ),
                if (request.updatedAt != null)
                  _row(
                    'آخر تحديث',
                    formatter.format(request.updatedAt!.toLocal()),
                  ),
              ],
            ),
          ),
        ),
        if (request.payload.isNotEmpty) ...[
          const SizedBox(height: 12),
          _RequestPayloadCard(
            requestType: request.type,
            payload: request.payload,
          ),
        ],
        const SizedBox(height: 12),
        const MobileSectionHeader(title: 'مسار الاعتماد'),
        const SizedBox(height: 12),
        if (request.steps.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Icon(
                    Icons.route_outlined,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'لم تُنشأ خطوات اعتماد لهذا الطلب.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          for (final step in request.steps) _StepCard(step: step),
        if (request.canCancel && request.status == 'pending') ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _cancel(context, ref),
              icon: const Icon(Icons.undo_outlined),
              label: const Text('سحب الطلب قبل القرار'),
            ),
          ),
        ],
        if (request.canDecide && request.status == 'pending') ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _decide(context, ref, 'approve'),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('اعتماد'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _decide(context, ref, 'reject'),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('رفض'),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    String? errorText;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('سحب الطلب'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'سبب سحب الطلب',
              errorText: errorText,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('رجوع'),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().length < 3) {
                  setState(() => errorText = 'يرجى إدخال سبب لا يقل عن 3 أحرف.');
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('تأكيد السحب'),
            ),
          ],
        ),
      ),
    );
    final reason = controller.text.trim();
    controller.dispose();
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(mobileCommandsProvider).cancelRequest(request.id, reason);
      ref.invalidate(mobileRequestDetailProvider(request.id));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم سحب الطلب وإيقاف مسار الاعتماد.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(humanizeError(error))));
      }
    }
  }

  Future<void> _decide(
    BuildContext context,
    WidgetRef ref,
    String decision,
  ) async {
    final controller = TextEditingController();
    String? errorText;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(decision == 'approve' ? 'اعتماد الطلب' : 'رفض الطلب'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: decision == 'reject'
                  ? 'سبب الرفض (إلزامي)'
                  : 'ملاحظة اختيارية',
              errorText: errorText,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                if (decision == 'reject' &&
                    controller.text.trim().length < 3) {
                  setState(
                    () => errorText = 'سبب الرفض إلزامي ولا يقل عن 3 أحرف.',
                  );
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('تأكيد'),
            ),
          ],
        ),
      ),
    );
    final comment = controller.text.trim();
    controller.dispose();
    if (confirmed != true || !context.mounted) return;

    try {
      await ref
          .read(mobileCommandsProvider)
          .decideRequest(request.id, decision, comment);
      ref.invalidate(mobileRequestDetailProvider(request.id));
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم تنفيذ القرار بنجاح.')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(humanizeError(error))));
      }
    }
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 110, child: Text(label)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );

  static String _typeLabel(String type) => switch (type) {
    'leave' => 'طلب إجازة',
    'mission' => 'مأمورية',
    'attendance_permit' => 'إذن حضور أو انصراف',
    'convoy' => 'تكليف قافلة',
    _ => 'طلب عام',
  };
}

class _RequestPayloadCard extends StatelessWidget {
  const _RequestPayloadCard({required this.requestType, required this.payload});

  final String requestType;
  final Map<String, dynamic> payload;

  @override
  Widget build(BuildContext context) {
    final rows = _rows();
    if (rows.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'بيانات الطلب',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 120, child: Text(row.$1)),
                    Expanded(
                      child: Text(
                        row.$2,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<(String, String)> _rows() {
    final rows = <(String, String)>[];
    String? dateLabel(String key) {
      final raw = payload[key]?.toString();
      if (raw == null || raw.isEmpty) return null;
      final parsed = DateTime.tryParse(raw);
      return parsed == null
          ? raw
          : DateFormat('EEEE، d MMMM y', 'ar').format(parsed);
    }

    if (requestType == 'leave') {
      rows.add(('نوع الإجازة', _leaveType(payload['leaveType']?.toString())));
      final start = dateLabel('startDate');
      final end = dateLabel('endDate');
      if (start != null) rows.add(('تاريخ البداية', start));
      if (end != null) rows.add(('تاريخ النهاية', end));
      if (payload['days'] != null) {
        rows.add(('عدد الأيام', '${payload['days']}'));
      }
    } else if (requestType == 'mission' || requestType == 'convoy') {
      final start = dateLabel('startDate');
      final end = dateLabel('endDate');
      if (start != null) rows.add(('تاريخ البداية', start));
      if (end != null) rows.add(('تاريخ النهاية', end));
      if (payload['location'] != null) {
        rows.add(('المكان', '${payload['location']}'));
      }
      if (payload['days'] != null) {
        rows.add(('عدد الأيام', '${payload['days']}'));
      }
    } else if (requestType == 'attendance_permit') {
      final date = dateLabel('permitDate');
      if (date != null) rows.add(('تاريخ الإذن', date));
      rows.add(('نوع الإذن', _permitType(payload['permitKind']?.toString())));
      if (payload['minutes'] != null) {
        rows.add(('المدة', '${payload['minutes']} دقيقة'));
      }
    } else {
      for (final entry in payload.entries) {
        rows.add((entry.key, '${entry.value}'));
      }
    }
    return rows;
  }

  static String _leaveType(String? value) => switch (value) {
    'annual' => 'اعتيادية',
    'sick' => 'مرضية',
    'emergency' => 'عارضة / طارئة',
    'unpaid' => 'بدون راتب',
    _ => value ?? '—',
  };

  static String _permitType(String? value) => switch (value) {
    'late_arrival' => 'تأخير وصول',
    'early_departure' => 'انصراف مبكر',
    _ => value ?? '—',
  };
}

class _StepCard extends StatelessWidget {
  const _StepCard({required this.step});

  final MobileRequestStep step;

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('d MMM، h:mm a', 'ar');
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          child: Text(
            '${step.order}',
            style: TextStyle(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        title: Text(
          step.name,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(step.decision ?? step.status),
            if (step.comment?.trim().isNotEmpty == true) Text(step.comment!),
            if (step.decidedAt != null)
              Text(formatter.format(step.decidedAt!.toLocal())),
          ],
        ),
        trailing: MobileStatusPill(step.status),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 40,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRetry,
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    ),
  );
}
