import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// V17 §14 — Executive admin-action workflow page.
/// Workflow: Propose (secretary) → Decide (executive) → Execute (HR) → Done
class ExecutiveDisputesPage extends ConsumerWidget {
  const ExecutiveDisputesPage({super.key});

  static const _actionLabels = <String, String>{
    'verbal_warning': 'إنذار شفهي',
    'written_warning': 'إنذار كتابي',
    'final_warning': 'إنذار نهائي',
    'salary_deduction': 'خصم من الراتب',
    'suspension': 'إيقاف عن العمل',
    'demotion': 'تخفيض الدرجة',
    'termination': 'إنهاء الخدمة',
    'transfer': 'نقل',
    'training_requirement': 'تدريب إلزامي',
    'no_action': 'لا إجراء',
  };

  static const _severityColors = <String, Color>{
    'critical': Color(0xFFD32F2F),
    'urgent': Color(0xFFF57C00),
    'high': Color(0xFFFFA000),
    'medium': Color(0xFF1976D2),
    'low': Color(0xFF388E3C),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(executiveDisputeInboxProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('الإجراءات الإدارية')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(executiveDisputeInboxProvider),
        child: inbox.when(
          loading: () => ListView(
            children: const [
              SizedBox(height: 240),
              Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (error, _) => ListView(
            children: [
              const SizedBox(height: 200),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48),
                    const SizedBox(height: 12),
                    Text('تعذر تحميل القضايا',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: () =>
                          ref.invalidate(executiveDisputeInboxProvider),
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          data: (data) {
            final hasAny = data.awaitingDecision.isNotEmpty ||
                data.pendingExecution.isNotEmpty ||
                data.recentlyExecuted.isNotEmpty;

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                // ── Summary chips ────────────────────────────────
                _CountChipsRow(counts: data.counts),
                const SizedBox(height: 16),

                // ── Awaiting decision ────────────────────────────
                if (data.awaitingDecision.isNotEmpty) ...[
                  _SectionHeader(
                    title: 'تتطلب قرارك',
                    count: data.awaitingDecision.length,
                    color: Colors.redAccent,
                  ),
                  ...data.awaitingDecision.map((c) => _AdminActionCard(
                        dispute: c,
                        onTap: () =>
                            _showDecisionDialog(context, ref, c),
                      )),
                  const SizedBox(height: 20),
                ],

                // ── Pending execution ────────────────────────────
                if (data.pendingExecution.isNotEmpty) ...[
                  _SectionHeader(
                    title: 'بانتظار التنفيذ',
                    count: data.pendingExecution.length,
                    color: Colors.orange,
                  ),
                  ...data.pendingExecution.map((c) => _TrackingCard(
                        dispute: c,
                        onTap: () => _showTrackingDetail(context, c),
                      )),
                  const SizedBox(height: 20),
                ],

                // ── Recently executed ────────────────────────────
                if (data.recentlyExecuted.isNotEmpty) ...[
                  _SectionHeader(
                    title: 'تم التنفيذ',
                    count: data.recentlyExecuted.length,
                    color: Colors.green,
                  ),
                  ...data.recentlyExecuted.map((c) => _TrackingCard(
                        dispute: c,
                        onTap: () => _showTrackingDetail(context, c),
                      )),
                ],

                if (!hasAny)
                  const Padding(
                    padding: EdgeInsets.only(top: 120),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 64, color: Colors.green),
                          SizedBox(height: 16),
                          Text('لا توجد إجراءات إدارية حالياً',
                              style: TextStyle(fontSize: 18)),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ── Decision dialog ──────────────────────────────────────────────────────

  void _showDecisionDialog(
      BuildContext context, WidgetRef ref, MobileDisputeCase c) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _DecisionSheet(dispute: c),
    );
  }

  // ── Tracking detail dialog ───────────────────────────────────────────────

  void _showTrackingDetail(BuildContext context, MobileDisputeCase c) {
    final df = DateFormat('d MMM y', 'ar');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(c.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow(context, 'الحالة', _statusLabel(c.status)),
              if (c.approvedAdminAction != null)
                _infoRow(context, 'الإجراء المعتمد',
                    _actionLabels[c.approvedAdminAction] ?? c.approvedAdminAction!),
              if (c.approvedActionDetail != null)
                _infoRow(context, 'التفاصيل', c.approvedActionDetail!),
              if (c.executiveDecisionAt != null)
                _infoRow(context, 'تاريخ القرار',
                    df.format(c.executiveDecisionAt!)),
              if (c.executedAt != null)
                _infoRow(context, 'تاريخ التنفيذ', df.format(c.executedAt!)),
              if (c.executedByName != null)
                _infoRow(context, 'نفذ بواسطة', c.executedByName!),
              if (c.executionNotes != null)
                _infoRow(context, 'ملاحظات التنفيذ', c.executionNotes!),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  static String _statusLabel(String status) => switch (status) {
        'action_proposed' => 'بانتظار القرار',
        'pending_execution' => 'بانتظار التنفيذ',
        'executed' => 'تم التنفيذ',
        _ => status,
      };

  Widget _infoRow(BuildContext context, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            Text(value),
          ],
        ),
      );
}

// ── Decision bottom sheet (stateful) ──────────────────────────────────────

class _DecisionSheet extends ConsumerStatefulWidget {
  const _DecisionSheet({required this.dispute});
  final MobileDisputeCase dispute;

  @override
  ConsumerState<_DecisionSheet> createState() => _DecisionSheetState();
}

class _DecisionSheetState extends ConsumerState<_DecisionSheet> {
  String _decision = 'approved';
  String? _modifiedAction;
  final _reasonController = TextEditingController();
  final _modifiedDetailController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _reasonController.dispose();
    _modifiedDetailController.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    if (_submitting) return false;
    if (_reasonController.text.trim().length < 3) return false;
    if (_decision == 'modified' && _modifiedAction == null) return false;
    return true;
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    try {
      await ref.read(mobileCommandsProvider).decideAdminAction(
        caseId: widget.dispute.id,
        decision: _decision,
        reason: _reasonController.text.trim(),
        modifiedAction: _decision == 'modified' ? _modifiedAction : null,
        modifiedDetail: _decision == 'modified'
            ? _modifiedDetailController.text.trim().isEmpty
                ? null
                : _modifiedDetailController.text.trim()
            : null,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(_decision == 'approved'
                  ? 'تم اعتماد الإجراء'
                  : _decision == 'modified'
                      ? 'تم تعديل واعتماد الإجراء'
                      : _decision == 'rejected'
                          ? 'تم رفض الإجراء المقترح'
                          : 'تم تأجيل القرار')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.dispute;
    final theme = Theme.of(context);
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Title
            Text('قرار الإجراء الإداري',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            // Case info card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.title,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (c.description != null) ...[
                      const SizedBox(height: 4),
                      Text(c.description!,
                          style: theme.textTheme.bodySmall,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (c.actorName != null)
                          Chip(
                              label: Text('مقدم: ${c.actorName}'),
                              visualDensity: VisualDensity.compact),
                        if (c.respondentName != null)
                          Chip(
                              label: Text('مشتكى عليه: ${c.respondentName}'),
                              visualDensity: VisualDensity.compact),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Proposed action
            Card(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.gavel,
                            size: 18, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text('الإجراء المقترح',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      ExecutiveDisputesPage
                              ._actionLabels[c.proposedAdminAction] ??
                          c.proposedAdminAction ??
                          '—',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (c.proposedActionDetail != null) ...[
                      const SizedBox(height: 4),
                      Text(c.proposedActionDetail!,
                          style: theme.textTheme.bodyMedium),
                    ],
                    if (c.proposedByName != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'اقتراح: ${c.proposedByName} • ${c.proposedAt != null ? DateFormat('d MMM', 'ar').format(c.proposedAt!) : ''}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Decision radio
            Text('قرارك', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            ...['approved', 'modified', 'rejected', 'deferred'].map(
              (d) => RadioListTile<String>(
                value: d,
                groupValue: _decision,
                dense: true,
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => setState(() => _decision = v!),
                title: Text(_decisionLabel(d)),
              ),
            ),

            // Modified action picker
            if (_decision == 'modified') ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _modifiedAction,
                decoration: const InputDecoration(
                  labelText: 'الإجراء البديل',
                  border: OutlineInputBorder(),
                ),
                items: ExecutiveDisputesPage._actionLabels.entries
                    .map((e) =>
                        DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) => setState(() => _modifiedAction = v),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _modifiedDetailController,
                maxLines: 2,
                maxLength: 300,
                decoration: const InputDecoration(
                  labelText: 'تفاصيل التعديل (اختياري)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],

            // Reason
            const SizedBox(height: 8),
            TextField(
              controller: _reasonController,
              maxLines: 3,
              maxLength: 300,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'سبب القرار',
                hintText: '3 أحرف على الأقل',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Submit
            FilledButton.icon(
              onPressed: _canSubmit ? _submit : null,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(_decisionIcon(_decision)),
              label: Text(_submitLabel(_decision)),
            ),
          ],
        ),
      ),
    );
  }

  static String _decisionLabel(String d) => switch (d) {
        'approved' => 'اعتماد الإجراء كما هو',
        'modified' => 'تعديل الإجراء واعتماده',
        'rejected' => 'رفض الإجراء المقترح',
        'deferred' => 'تأجيل القرار',
        _ => d,
      };

  static IconData _decisionIcon(String d) => switch (d) {
        'approved' => Icons.check_circle,
        'modified' => Icons.edit_note,
        'rejected' => Icons.cancel,
        'deferred' => Icons.schedule,
        _ => Icons.send,
      };

  static String _submitLabel(String d) => switch (d) {
        'approved' => 'اعتماد',
        'modified' => 'تعديل واعتماد',
        'rejected' => 'رفض',
        'deferred' => 'تأجيل',
        _ => 'إرسال',
      };
}

// ── Widgets ─────────────────────────────────────────────────────────────────

class _CountChipsRow extends StatelessWidget {
  const _CountChipsRow({required this.counts});
  final ExecutiveDisputeCounts counts;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _chip(context, '${counts.awaitingDecision}', 'بانتظار القرار',
            Colors.redAccent),
        const SizedBox(width: 8),
        _chip(context, '${counts.pendingExecution}', 'بانتظار التنفيذ',
            Colors.orange),
        const SizedBox(width: 8),
        _chip(context, '${counts.executedLast30Days}', 'تم التنفيذ',
            Colors.green),
      ],
    );
  }

  Widget _chip(
          BuildContext context, String count, String label, Color color) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Text(count,
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: color)),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(fontSize: 11, color: color),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.color,
  });
  final String title;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('$count',
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          const SizedBox(width: 8),
          Text(title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _AdminActionCard extends StatelessWidget {
  const _AdminActionCard({required this.dispute, required this.onTap});
  final MobileDisputeCase dispute;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actionLabel = ExecutiveDisputesPage
            ._actionLabels[dispute.proposedAdminAction] ??
        dispute.proposedAdminAction ??
        '';
    final severity = ExecutiveDisputesPage._severityColors[dispute.severity] ??
        Colors.grey;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.redAccent,
                    child: const Icon(Icons.gavel, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(dispute.title,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                          '${dispute.caseNumber ?? ''} • ${DateFormat('d MMM', 'ar').format(dispute.openedAt)}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: severity.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(dispute.severity,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: severity)),
                  ),
                ],
              ),
              const Divider(height: 16),
              Row(
                children: [
                  Icon(Icons.arrow_forward, size: 14, color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                  Text('الإجراء المقترح: ',
                      style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant)),
                  Expanded(
                    child: Text(actionLabel,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary)),
                  ),
                ],
              ),
              if (dispute.proposedByName != null) ...[
                const SizedBox(height: 4),
                Text(
                  'اقتراح: ${dispute.proposedByName}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TrackingCard extends StatelessWidget {
  const _TrackingCard({required this.dispute, required this.onTap});
  final MobileDisputeCase dispute;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExecuted = dispute.status == 'executed';
    final actionLabel = ExecutiveDisputesPage._actionLabels[
            dispute.approvedAdminAction ?? dispute.proposedAdminAction] ??
        '—';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isExecuted ? Colors.green : Colors.orange,
          child: Icon(
            isExecuted ? Icons.check : Icons.hourglass_top,
            color: Colors.white,
            size: 20,
          ),
        ),
        title: Text(dispute.title,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          '$actionLabel • ${isExecuted && dispute.executedAt != null ? DateFormat('d MMM', 'ar').format(dispute.executedAt!) : 'قيد التنفيذ'}',
          style: theme.textTheme.bodySmall,
        ),
        trailing: const Icon(Icons.chevron_left),
        onTap: onTap,
      ),
    );
  }
}
