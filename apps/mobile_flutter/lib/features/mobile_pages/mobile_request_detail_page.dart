import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

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
                if (request.decisionActorName != null)
                  _row(
                    request.decisionOnBehalfOfExecutive
                        ? 'منفذ القرار بالإنابة'
                        : 'منفذ القرار',
                    request.decisionActorName!,
                  ),
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
        if (request.type == 'mission' ||
            request.type == 'convoy' ||
            request.type == 'fundraising') ...[
          const SizedBox(height: 12),
          _MissionExecutionCard(request: request),
        ],
        if (request.substituteName != null || request.conflicts.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'البديل والتعارضات',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  _row('البديل', request.substituteName ?? 'لم يحدد'),
                  if (request.conflicts.isEmpty)
                    const Text('لا توجد طلبات متعارضة في الفترة المحددة.')
                  else
                    for (final conflict in request.conflicts)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '• $conflict',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ],
        if (request.attachments.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'المرفقات',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  for (
                    var index = 0;
                    index < request.attachments.length;
                    index++
                  )
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.attachment_rounded),
                      title: Text('مرفق ${index + 1}'),
                      subtitle: Text(request.attachments[index].mimeType),
                      trailing: const Icon(Icons.open_in_new_rounded),
                      onTap: () => _openAttachment(
                        context,
                        request.attachments[index].path,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        const MobileSectionHeader(title: 'مسار الاعتماد'),
        if (request.steps.isNotEmpty) ...[
          const SizedBox(height: 12),
          _RequestJourneySummary(
            steps: request.steps,
            createdAt: request.createdAt,
          ),
        ],
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
          _RequestTimeline(steps: request.steps, createdAt: request.createdAt),
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
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _decide(context, ref, 'return'),
              icon: const Icon(Icons.replay_outlined),
              label: const Text('إرجاع للموظف للتعديل'),
            ),
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
                  setState(
                    () => errorText = 'يرجى إدخال سبب لا يقل عن 3 أحرف.',
                  );
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
          title: Text(
            decision == 'approve'
                ? 'اعتماد الطلب'
                : decision == 'return'
                ? 'إرجاع الطلب'
                : 'رفض الطلب',
          ),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: decision == 'approve'
                  ? 'ملاحظة اختيارية'
                  : decision == 'return'
                  ? 'سبب الإرجاع (إلزامي)'
                  : 'سبب الرفض (إلزامي)',
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
                if (decision != 'approve' &&
                    controller.text.trim().length < 3) {
                  setState(
                    () => errorText = decision == 'return'
                        ? 'سبب الإرجاع إلزامي ولا يقل عن 3 أحرف.'
                        : 'سبب الرفض إلزامي ولا يقل عن 3 أحرف.',
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
    'late_permit' => 'إذن حضور',
    'early_permit' => 'إذن انصراف',
    'attendance_correction' => 'تصحيح حضور',
    'convoy' => 'تكليف قافلة',
    'fundraising' => 'فاندي',
    _ => 'طلب عام',
  };

  Future<void> _openAttachment(BuildContext context, String path) async {
    try {
      final url = await Supabase.instance.client.storage
          .from('request-attachments')
          .createSignedUrl(path, 120)
          .timeout(const Duration(seconds: 20));
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(humanizeError(error))));
      }
    }
  }
}

/// بطاقة تنفيذ المأمورية/القافلة: بدء، إنهاء بالتقرير، أو عرض نتيجة منجزة.
class _MissionExecutionCard extends ConsumerWidget {
  const _MissionExecutionCard({required this.request});

  final MobileRequestDetail request;

  String _statusLabel(BuildContext context, String status) => switch (status) {
        'in_progress' => 'قيد التنفيذ',
        'completed' => 'منجزة',
        _ => 'لم تبدأ',
      };

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

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(mobileCommandsProvider).startMission(request.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('بدأت المأمورية بنجاح')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر البدء: ${humanizeError(error)}')),
        );
      }
    }
  }

  Future<void> _end(BuildContext context, WidgetRef ref) async {
    final result = await showModalBottomSheet<({String report, String? outcome})>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _EndMissionSheet(),
    );
    if (result == null) return;
    try {
      await ref
          .read(mobileCommandsProvider)
          .endMission(requestId: request.id, report: result.report, outcome: result.outcome);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إنهاء المأمورية وحفظ التقرير')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر الإنهاء: ${humanizeError(error)}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final execution = request.missionExecution;
    final formatter = DateFormat('d MMMM y، h:mm a', 'ar');
    final isOwner = request.status == 'approved';
    final canStart = isOwner && (execution == null || !execution.isInProgress);
    final canEnd = isOwner && execution != null && execution.isInProgress;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.flag_circle_outlined),
                const SizedBox(width: 8),
                const Text(
                  'تنفيذ المأمورية',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: execution == null || !execution.isInProgress
                        ? Theme.of(context).colorScheme.surfaceContainerHighest
                        : Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _statusLabel(context, execution?.status ?? 'not_started'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (execution != null && execution.startedAt != null) ...[
              _row(
                'وقت البدء',
                formatter.format(execution.startedAt!.toLocal()),
              ),
              if (execution.endedAt != null)
                _row('وقت الإنهاء', formatter.format(execution.endedAt!.toLocal())),
              if (execution.actualMinutes != null)
                _row('المدة الفعلية', '${execution.actualMinutes} دقيقة'),
            ],
            if (execution != null && execution.report != null) ...[
              const SizedBox(height: 6),
              Text(
                'التقرير: ${execution.report}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
            if (execution == null)
              const Text(
                'لم يبدأ الموظف التنفيذ بعد. تبدأ المأمورية بعد الاعتماد.',
              ),
            if (canStart) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _start(context, ref),
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('ابدأ المأمورية الآن'),
                ),
              ),
            ],
            if (canEnd) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _end(context, ref),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('إنهاء المأمورية وتقديم التقرير'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// ورقة إنهاء المأمورية: تقرير إلزامي + نتيجة اختيارية.
class _EndMissionSheet extends StatefulWidget {
  @override
  State<_EndMissionSheet> createState() => _EndMissionSheetState();
}

class _EndMissionSheetState extends State<_EndMissionSheet> {
  final _reportController = TextEditingController();
  final _outcomeController = TextEditingController();

  @override
  void dispose() {
    _reportController.dispose();
    _outcomeController.dispose();
    super.dispose();
  }

  void _submit() {
    final report = _reportController.text.trim();
    if (report.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('التقرير إلزامي (3 أحرف على الأقل)')),
      );
      return;
    }
    final outcome = _outcomeController.text.trim();
    Navigator.pop(context, (report: report, outcome: outcome.isEmpty ? null : outcome));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: bottomInset > 0 ? bottomInset + 16 : 40,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'إنهاء المأمورية',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _reportController,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'تقرير التنفيذ (إلزامي)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _outcomeController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'النتيجة (اختياري)',
              hintText: 'مثال: اكتمل التسليم، تأجل جزئيًا…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _submit,
            child: const Text('حفظ التقرير وإنهاء المأمورية'),
          ),
        ],
      ),
    );
  }
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
    } else if (requestType == 'mission' ||
        requestType == 'convoy' ||
        requestType == 'fundraising') {
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
    } else if (requestType == 'late_permit' || requestType == 'early_permit') {
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
    'casual' => 'عارضة',
    'unpaid' => 'بدون راتب',
    _ => value ?? '—',
  };

  static String _permitType(String? value) => switch (value) {
    'late_arrival' => 'إذن حضور',
    'early_departure' => 'إذن انصراف',
    _ => value ?? '—',
  };
}

/// ملخص مسار الاعتماد — بطاقة مدمجة تعرض التقدم الإجمالي
class _RequestJourneySummary extends StatelessWidget {
  const _RequestJourneySummary({required this.steps, required this.createdAt});

  final List<MobileRequestStep> steps;
  final DateTime createdAt;

  @override
  Widget build(BuildContext context) {
    final total = steps.length;
    final completed = steps
        .where((s) => s.status == 'approved' || s.status == 'completed')
        .length;
    final currentStep = steps.cast<MobileRequestStep?>().firstWhere(
      (s) => s!.status == 'pending',
      orElse: () => null,
    );
    final progress = total > 0 ? completed / total : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.route_rounded,
                  color: AppColors.brandPrimary,
                  size: 22,
                ),
                const SizedBox(width: 8),
                const Text(
                  'ملخص المسار',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const Spacer(),
                Text(
                  '$completed / $total',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppColors.brandPrimary,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            if (currentStep != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    'الخطوة الحالية: ',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      currentStep.name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
                valueColor: const AlwaysStoppedAnimation(
                  AppColors.statusSuccess,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// الجدول الزمني العمودي — خط عمودي يربط جميع الخطوات (RTL)
class _RequestTimeline extends StatelessWidget {
  const _RequestTimeline({required this.steps, required this.createdAt});

  final List<MobileRequestStep> steps;
  final DateTime createdAt;

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('d MMMM y، h:mm a', 'ar');
    // تحديد أول خطوة معلقة لتمييزها كـ "حالية"
    final firstPendingIndex = steps.indexWhere((s) => s.status == 'pending');

    return Column(
      children: [
        // عقدة إنشاء الطلب
        _TimelineNode(
          isFirst: true,
          isLast: steps.isEmpty,
          nodeColor: AppColors.statusSuccess,
          icon: Icons.flag_rounded,
          isPending: false,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4, top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'تم إنشاء الطلب',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  formatter.format(createdAt.toLocal()),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        // خطوات الاعتماد
        for (var i = 0; i < steps.length; i++)
          _buildStepNode(context, steps[i], i, firstPendingIndex),
      ],
    );
  }

  Widget _buildStepNode(
    BuildContext context,
    MobileRequestStep step,
    int index,
    int firstPendingIndex,
  ) {
    final formatter = DateFormat('d MMM y، h:mm a', 'ar');
    final scheme = Theme.of(context).colorScheme;

    // تحديد حالة العقدة ولونها
    final bool isCurrent = index == firstPendingIndex;
    final bool isFuture =
        firstPendingIndex >= 0 &&
        index > firstPendingIndex &&
        step.status == 'pending';

    final Color nodeColor;
    final IconData? icon;
    final bool isPending;

    switch (step.status) {
      case 'approved' || 'completed':
        nodeColor = AppColors.statusSuccess;
        icon = Icons.check_rounded;
        isPending = false;
      case 'rejected':
        nodeColor = AppColors.statusDanger;
        icon = Icons.close_rounded;
        isPending = false;
      case 'cancelled':
        nodeColor = AppColors.statusWarning;
        icon = Icons.block_rounded;
        isPending = false;
      case 'pending' when isCurrent:
        nodeColor = AppColors.statusInfo;
        icon = null;
        isPending = true;
      default: // مستقبلية / في الانتظار
        nodeColor = scheme.outlineVariant;
        icon = null;
        isPending = false;
    }

    // حساب الوقت المتبقي للخطوات المعلقة
    String? remainingLabel;
    if (step.status == 'pending' && step.dueAt != null) {
      final diff = step.dueAt!.difference(DateTime.now());
      if (diff.isNegative) {
        final days = diff.inDays.abs();
        remainingLabel = days > 0
            ? 'متأخر ${_arabicNum(days)} ${days == 1 ? "يوم" : "أيام"}'
            : 'متأخر ${_arabicNum(diff.inHours.abs())} ساعات';
      } else {
        final days = diff.inDays;
        if (days > 0) {
          remainingLabel =
              'متبقي ${_arabicNum(days)} ${days == 1 ? "يوم" : "أيام"}';
        } else {
          final hours = diff.inHours;
          remainingLabel = hours > 0
              ? 'متبقي ${_arabicNum(hours)} ساعات'
              : 'متبقي أقل من ساعة';
        }
      }
    }

    return _TimelineNode(
      isFirst: false,
      isLast: index == steps.length - 1,
      nodeColor: nodeColor,
      icon: icon,
      isPending: isPending,
      isFuture: isFuture,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4, top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // اسم الخطوة + حالة
            Row(
              children: [
                Expanded(
                  child: Text(
                    step.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      color: isFuture ? scheme.onSurfaceVariant : null,
                    ),
                  ),
                ),
                MobileStatusPill(step.status),
              ],
            ),
            // القرار
            if (step.decision?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(
                step.decision!,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
            // المنفذ
            if (step.actorName?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(
                    Icons.person_outline_rounded,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      step.actorName!,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            // التعليق
            if (step.comment?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.comment_outlined,
                      size: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        step.comment!,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // التاريخ
            if (step.decidedAt != null) ...[
              const SizedBox(height: 2),
              Text(
                formatter.format(step.decidedAt!.toLocal()),
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
            // الوقت المتبقي
            if (remainingLabel != null) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color:
                      (step.dueAt!.difference(DateTime.now()).isNegative
                              ? AppColors.statusDanger
                              : AppColors.statusInfo)
                          .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  remainingLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: step.dueAt!.difference(DateTime.now()).isNegative
                        ? AppColors.statusDanger
                        : AppColors.statusInfo,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// تحويل رقم إلى أرقام عربية شرقية
  static String _arabicNum(int n) {
    const eastern = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return n.toString().split('').map((c) {
      final d = int.tryParse(c);
      return d != null ? eastern[d] : c;
    }).join();
  }
}

/// عقدة واحدة في الجدول الزمني — دائرة + خط + محتوى
class _TimelineNode extends StatelessWidget {
  const _TimelineNode({
    required this.isFirst,
    required this.isLast,
    required this.nodeColor,
    required this.icon,
    required this.isPending,
    required this.child,
    this.isFuture = false,
  });

  final bool isFirst;
  final bool isLast;
  final Color nodeColor;
  final IconData? icon;
  final bool isPending;
  final bool isFuture;
  final Widget child;

  static const double _circleSize = 28.0;
  static const double _lineWidth = 2.5;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lineColor = isFuture
        ? scheme.outlineVariant.withValues(alpha: 0.3)
        : nodeColor.withValues(alpha: 0.4);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // عمود المؤشر الزمني (يظهر على اليمين في RTL)
          SizedBox(
            width: 40,
            child: Column(
              children: [
                // خط علوي
                if (!isFirst)
                  Container(width: _lineWidth, height: 8, color: lineColor)
                else
                  const SizedBox(height: 8),
                // الدائرة
                if (isPending)
                  _PulsingDot(color: nodeColor, size: _circleSize)
                else if (isFuture)
                  // دائرة مفرغة للخطوات المستقبلية
                  Container(
                    width: _circleSize,
                    height: _circleSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: scheme.outlineVariant,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: scheme.outlineVariant.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                  )
                else
                  // دائرة ملونة مع أيقونة
                  Container(
                    width: _circleSize,
                    height: _circleSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: nodeColor,
                      boxShadow: [
                        BoxShadow(
                          color: nodeColor.withValues(alpha: 0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: icon != null
                        ? Icon(icon, size: 16, color: Colors.white)
                        : null,
                  ),
                // خط سفلي
                if (!isLast)
                  Expanded(
                    child: Container(width: _lineWidth, color: lineColor),
                  )
                else
                  const Expanded(child: SizedBox()),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // المحتوى
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// دائرة نابضة للخطوة الحالية المعلقة
class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.35,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _opacityAnimation = Tween<double>(
      begin: 0.6,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Stack(
          alignment: Alignment.center,
          children: [
            // هالة خارجية نابضة
            Transform.scale(
              scale: _scaleAnimation.value,
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(
                    alpha: _opacityAnimation.value,
                  ),
                ),
              ),
            ),
            // الدائرة الداخلية الثابتة
            Container(
              width: widget.size * 0.65,
              height: widget.size * 0.65,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color,
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.4),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ],
        ),
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
