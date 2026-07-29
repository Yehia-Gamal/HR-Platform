import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// V18 — بوابة القضايا للجنة / التنفيذي / التشغيل.
/// تعرض جميع القضايا (ليست الشخصية فقط) مع ملخص إحصائي
/// وتتيح اتخاذ القرار الإداري عند توفر صلاحية action_proposed.
class CommitteeDisputeListPage extends ConsumerWidget {
  const CommitteeDisputeListPage({super.key});

  // ── Label maps ────────────────────────────────────────────────────────────
  static const _statusLabels = <String, String>{
    'submitted': 'جديدة',
    'needs_more_information': 'تحتاج معلومات',
    'accepted': 'مقبولة',
    'under_review': 'قيد المراجعة',
    'waiting_for_respondent': 'بانتظار المشتكى عليه',
    'waiting_for_witness': 'بانتظار الشهود',
    'session_scheduled': 'جلسة محددة',
    'session_completed': 'جلسة منتهية',
    'committee_deliberation': 'مداولة اللجنة',
    'settlement_pending': 'تسوية معلقة',
    'escalated_to_executive': 'مصعّدة للتنفيذي',
    'returned_to_committee': 'معادة للجنة',
    'decision_issued': 'صدر قرار',
    'resolved_friendly': 'حُلّت ودياً',
    'action_proposed': 'إجراء مقترح',
    'pending_execution': 'بانتظار التنفيذ',
    'executed': 'تم التنفيذ',
    'closed': 'مغلقة',
    'reopened': 'أعيد فتحها',
    'rejected': 'مرفوضة',
    'cancelled_by_employee': 'ملغاة',
    'mediated': 'تم الوساطة',
  };

  static const _statusColors = <String, Color>{
    'submitted': Color(0xFF1565C0),
    'needs_more_information': Color(0xFFF57C00),
    'accepted': Color(0xFF2E7D32),
    'under_review': Color(0xFF6A1B9A),
    'waiting_for_respondent': Color(0xFF00838F),
    'waiting_for_witness': Color(0xFF00838F),
    'session_scheduled': Color(0xFF4527A0),
    'session_completed': Color(0xFF5E35B1),
    'committee_deliberation': Color(0xFF7B1FA2),
    'settlement_pending': Color(0xFF00838F),
    'escalated_to_executive': Color(0xFFD84315),
    'returned_to_committee': Color(0xFFF57C00),
    'decision_issued': Color(0xFF1B5E20),
    'resolved_friendly': Color(0xFF00695C),
    'action_proposed': Color(0xFFE65100),
    'pending_execution': Color(0xFFF9A825),
    'executed': Color(0xFF2E7D32),
    'closed': Color(0xFF616161),
    'reopened': Color(0xFF0277BD),
    'rejected': Color(0xFFC62828),
    'cancelled_by_employee': Color(0xFF9E9E9E),
    'mediated': Color(0xFF00695C),
  };

  static const _severityColors = <String, Color>{
    'critical': Color(0xFFD32F2F),
    'urgent': Color(0xFFF57C00),
    'high': Color(0xFFFFA000),
    'medium': Color(0xFF1976D2),
    'normal': Color(0xFF757575),
    'low': Color(0xFF388E3C),
  };

  static const _caseTypeLabels = <String, String>{
    'complaint': 'شكوى',
    'grievance': 'تظلم',
    'disciplinary': 'تأديبي',
    'harassment': 'تحرش',
    'discrimination': 'تمييز',
    'policy_violation': 'مخالفة سياسة',
    'performance': 'أداء',
    'attendance': 'حضور وانصراف',
    'misconduct': 'سوء سلوك',
    'theft': 'سرقة',
    'safety': 'سلامة',
    'other': 'أخرى',
  };

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

  static const _severityLabels = <String, String>{
    'critical': 'حرجة',
    'urgent': 'عاجلة',
    'high': 'عالية',
    'medium': 'متوسطة',
    'normal': 'عادية',
    'low': 'منخفضة',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portal = ref.watch(committeeDisputePortalProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('بوابة القضايا')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(committeeDisputePortalProvider);
          ref.invalidate(executiveDisputeInboxProvider);
        },
        child: portal.when(
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
                    const SizedBox(height: 4),
                    Text('$error',
                        style: theme.textTheme.bodySmall,
                        textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: () =>
                          ref.invalidate(committeeDisputePortalProvider),
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          data: (data) {
            if (data.cases.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 200),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.gavel_outlined,
                            size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('لا توجد قضايا حالياً',
                            style: TextStyle(fontSize: 18)),
                      ],
                    ),
                  ),
                ],
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _SummaryRow(summary: data.summary),
                const SizedBox(height: 16),
                ...data.cases.map((c) => _CaseCard(
                      caseItem: c,
                      onTap: () => _showCaseDetail(context, ref, c),
                    )),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showCaseDetail(
      BuildContext context, WidgetRef ref, CommitteeDisputeCase c) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (ctx, scroll) => _CaseDetailSheet(
          caseItem: c,
          scrollController: scroll,
        ),
      ),
    );
  }
}

// ── Summary row ─────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.summary});
  final CommitteeDisputeSummary summary;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Overdue / urgent warnings
        if (summary.overdue > 0)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.red.shade700, size: 18),
                const SizedBox(width: 8),
                Text('${summary.overdue} قضية متأخرة',
                    style: TextStyle(
                        color: Colors.red.shade700,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        if (summary.urgent > 0)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.priority_high,
                    color: Colors.orange.shade700, size: 18),
                const SizedBox(width: 8),
                Text('${summary.urgent} قضية عاجلة/حرجة',
                    style: TextStyle(
                        color: Colors.orange.shade700,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        // Count chips — two rows of 3
        Row(
          children: [
            _chip(context, '${summary.total}', 'الإجمالي',
                const Color(0xFF37474F)),
            const SizedBox(width: 6),
            _chip(context, '${summary.submitted}', 'جديدة',
                const Color(0xFF1565C0)),
            const SizedBox(width: 6),
            _chip(context, '${summary.underReview}', 'قيد المراجعة',
                const Color(0xFF6A1B9A)),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _chip(context, '${summary.actionProposed}', 'إجراء مقترح',
                const Color(0xFFE65100)),
            const SizedBox(width: 6),
            _chip(context, '${summary.pendingExecution}', 'بانتظار التنفيذ',
                const Color(0xFFF9A825)),
            const SizedBox(width: 6),
            _chip(context, '${summary.closed}', 'مغلقة',
                const Color(0xFF616161)),
          ],
        ),
      ],
    );
  }

  Widget _chip(
          BuildContext context, String count, String label, Color color) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Text(count,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: color)),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(fontSize: 10, color: color),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}

// ── Case card ───────────────────────────────────────────────────────────────

class _CaseCard extends StatelessWidget {
  const _CaseCard({required this.caseItem, required this.onTap});
  final CommitteeDisputeCase caseItem;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = caseItem;
    final statusColor =
        CommitteeDisputeListPage._statusColors[c.status] ?? Colors.grey;
    final severityColor =
        CommitteeDisputeListPage._severityColors[c.severity] ?? Colors.grey;
    final df = DateFormat('d MMM y', 'ar');

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
              // ── Header: title + severity ──
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: statusColor.withValues(alpha: 0.15),
                    child: Icon(Icons.gavel, color: statusColor, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.title,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        Text(
                          '${c.caseNumber} • ${CommitteeDisputeListPage._caseTypeLabels[c.caseType] ?? c.caseType}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: severityColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      CommitteeDisputeListPage._severityLabels[c.severity] ??
                          c.severity,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: severityColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // ── Parties ──
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (c.actorName != null)
                    _partyChip(context, 'مقدم', c.actorName!),
                  if (c.respondentName != null)
                    _partyChip(context, 'مشتكى عليه', c.respondentName!),
                ],
              ),
              const SizedBox(height: 8),

              // ── Status + date row ──
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      CommitteeDisputeListPage._statusLabels[c.status] ??
                          c.status,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: statusColor),
                    ),
                  ),
                  if (c.overdue) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.schedule,
                              size: 12, color: Colors.red.shade700),
                          const SizedBox(width: 2),
                          Text('متأخرة',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red.shade700)),
                        ],
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    c.openedAt != null ? df.format(c.openedAt!) : '',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),

              // ── Admin-action info (if proposed) ──
              if (c.proposedAdminAction != null) ...[
                const Divider(height: 16),
                Row(
                  children: [
                    Icon(Icons.arrow_forward,
                        size: 14, color: theme.colorScheme.primary),
                    const SizedBox(width: 4),
                    Text('الإجراء المقترح: ',
                        style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant)),
                    Expanded(
                      child: Text(
                        CommitteeDisputeListPage
                                ._actionLabels[c.proposedAdminAction] ??
                            c.proposedAdminAction!,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary),
                      ),
                    ),
                  ],
                ),
              ],

              // ── Counters ──
              if (c.partyCount > 0 || c.sessionCount > 0) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (c.partyCount > 0) ...[
                      Icon(Icons.people_outline,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 2),
                      Text('${c.partyCount}',
                          style: theme.textTheme.bodySmall),
                      const SizedBox(width: 10),
                    ],
                    if (c.sessionCount > 0) ...[
                      Icon(Icons.event_note,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 2),
                      Text('${c.sessionCount} جلسة',
                          style: theme.textTheme.bodySmall),
                    ],
                    if (c.hasDecision) ...[
                      const SizedBox(width: 10),
                      Icon(Icons.task_alt,
                          size: 14, color: Colors.green.shade700),
                      const SizedBox(width: 2),
                      Text('يوجد قرار',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.green.shade700)),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _partyChip(BuildContext context, String role, String name) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text('$role: $name',
            style: const TextStyle(fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      );
}

// ── Detail bottom sheet ─────────────────────────────────────────────────────

class _CaseDetailSheet extends ConsumerWidget {
  const _CaseDetailSheet({
    required this.caseItem,
    required this.scrollController,
  });
  final CommitteeDisputeCase caseItem;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = caseItem;
    final df = DateFormat('d MMM y', 'ar');
    final statusColor =
        CommitteeDisputeListPage._statusColors[c.status] ?? Colors.grey;

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        // Handle
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color:
                  theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        // Title + case number
        Text(c.title,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('${c.caseNumber} • ${CommitteeDisputeListPage._caseTypeLabels[c.caseType] ?? c.caseType}',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 12),

        // Status + severity badges
        Row(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                CommitteeDisputeListPage._statusLabels[c.status] ?? c.status,
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: statusColor),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: (CommitteeDisputeListPage._severityColors[c.severity] ??
                        Colors.grey)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                CommitteeDisputeListPage._severityLabels[c.severity] ??
                    c.severity,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color:
                        CommitteeDisputeListPage._severityColors[c.severity] ??
                            Colors.grey),
              ),
            ),
            if (c.overdue) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('متأخرة',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade700)),
              ),
            ],
          ],
        ),
        const Divider(height: 24),

        // Description
        if (c.description != null && c.description!.isNotEmpty) ...[
          Text('الوصف',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 13)),
          const SizedBox(height: 4),
          Text(c.description!),
          const Divider(height: 24),
        ],

        // Parties
        _detailRow(context, 'مقدم الشكوى', c.actorName ?? '—'),
        if (c.actorDepartment != null)
          _detailRow(context, 'القسم', c.actorDepartment!),
        _detailRow(context, 'المشتكى عليه', c.respondentName ?? '—'),
        _detailRow(context, 'المحقق', c.assignedName ?? '—'),
        const Divider(height: 20),

        // Dates
        if (c.openedAt != null) _detailRow(context, 'تاريخ الفتح', df.format(c.openedAt!)),
        if (c.updatedAt != null)
          _detailRow(context, 'آخر تحديث', df.format(c.updatedAt!)),

        // Stats
        _detailRow(context, 'عدد الأطراف', '${c.partyCount}'),
        _detailRow(context, 'عدد الجلسات', '${c.sessionCount}'),
        if (c.hasDecision) _detailRow(context, 'قرار اللجنة', 'نعم ✓'),

        // ── Admin-action section ──
        if (c.proposedAdminAction != null) ...[
          const Divider(height: 24),
          Text('الإجراء الإداري',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Card(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detailRow(
                      context,
                      'المقترح',
                      CommitteeDisputeListPage
                              ._actionLabels[c.proposedAdminAction] ??
                          c.proposedAdminAction!),
                  if (c.proposedActionDetail != null)
                    _detailRow(
                        context, 'التفاصيل', c.proposedActionDetail!),
                  if (c.proposedByName != null)
                    _detailRow(context, 'اقتراح', c.proposedByName!),
                  if (c.proposedAt != null)
                    _detailRow(context, 'تاريخ الاقتراح',
                        df.format(c.proposedAt!)),
                ],
              ),
            ),
          ),
        ],

        // Executive decision
        if (c.executiveDecision != null) ...[
          const SizedBox(height: 8),
          Card(
            color: c.executiveDecision == 'approved'
                ? Colors.green.shade50
                : c.executiveDecision == 'rejected'
                    ? Colors.red.shade50
                    : Colors.orange.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detailRow(context, 'قرار المدير التنفيذي',
                      _decisionLabel(c.executiveDecision!)),
                  if (c.executiveDecisionReason != null)
                    _detailRow(
                        context, 'السبب', c.executiveDecisionReason!),
                  if (c.executiveDecisionAt != null)
                    _detailRow(context, 'تاريخ القرار',
                        df.format(c.executiveDecisionAt!)),
                  if (c.approvedAdminAction != null)
                    _detailRow(
                        context,
                        'الإجراء المعتمد',
                        CommitteeDisputeListPage
                                ._actionLabels[c.approvedAdminAction] ??
                            c.approvedAdminAction!),
                  if (c.approvedActionDetail != null)
                    _detailRow(context, 'تفاصيل الإجراء',
                        c.approvedActionDetail!),
                ],
              ),
            ),
          ),
        ],

        // Execution
        if (c.executedAt != null) ...[
          const SizedBox(height: 8),
          Card(
            color: Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detailRow(
                      context, 'تاريخ التنفيذ', df.format(c.executedAt!)),
                  if (c.executedByName != null)
                    _detailRow(context, 'نفذ بواسطة', c.executedByName!),
                  if (c.executionNotes != null)
                    _detailRow(context, 'ملاحظات', c.executionNotes!),
                ],
              ),
            ),
          ),
        ],

        // ── آراء وتوصيات أعضاء اللجنة (0198) ──
        _RecommendationsSection(caseId: c.id),

        // ── Decision button — only for executive / full-access ──
        if (c.status == 'action_proposed' &&
            (ref.watch(accessContextProvider).value?.hasAnyPermission(
                  const [
                    'disputes.admin_action.decide',
                    'disputes.executive.manage',
                  ],
                ) ??
                false)) ...[
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context); // close detail sheet
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(20))),
                builder: (ctx) => _DecisionSheet(caseItem: c),
              );
            },
            icon: const Icon(Icons.gavel),
            label: const Text('القرار التنفيذي النهائي'),
          ),
        ],
      ],
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
            Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );

  static String _decisionLabel(String d) => switch (d) {
        'approved' => 'تم توقيع الجزاء الإداري ✓',
        'modified' => 'تم تعديل الجزاء وتوقيعه ✓',
        'rejected' => 'تم العفو ✗',
        'deferred' => 'مؤجل',
        _ => d,
      };
}

// ── Decision bottom sheet ───────────────────────────────────────────────────

class _DecisionSheet extends ConsumerStatefulWidget {
  const _DecisionSheet({required this.caseItem});
  final CommitteeDisputeCase caseItem;

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
        caseId: widget.caseItem.id,
        decision: _decision,
        reason: _reasonController.text.trim(),
        modifiedAction: _decision == 'modified' ? _modifiedAction : null,
        modifiedDetail: _decision == 'modified'
            ? _modifiedDetailController.text.trim().isEmpty
                ? null
                : _modifiedDetailController.text.trim()
            : null,
      );
      ref.invalidate(committeeDisputePortalProvider);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(_decision == 'approved'
                  ? 'تم توقيع الجزاء الإداري'
                  : _decision == 'modified'
                      ? 'تم تعديل الجزاء وتوقيعه'
                      : _decision == 'rejected'
                          ? 'تم العفو وإغلاق القضية'
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
    final c = widget.caseItem;
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
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Title
            Text('القرار التنفيذي النهائي',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('قرارك نهائي ويُحسم به الأمر',
                style: theme.textTheme.bodySmall),
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
                              label:
                                  Text('مشتكى عليه: ${c.respondentName}'),
                              visualDensity: VisualDensity.compact),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── آراء اللجنة — يراها المدير التنفيذي قبل القرار ──
            _DecisionRecommendationsPreview(caseId: c.id),
            const SizedBox(height: 12),

            // Proposed action
            Card(
              color:
                  theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
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
                      CommitteeDisputeListPage
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
            Text('قرارك التنفيذي', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            ...['approved', 'modified', 'rejected', 'deferred'].map(
              (d) => RadioListTile<String>(
                value: d,
                groupValue: _decision,
                dense: true,
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => setState(() => _decision = v!),
                title: Text(_decisionLabel(d)),
                subtitle: Text(_decisionSubtitle(d),
                    style: theme.textTheme.bodySmall),
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
                items: CommitteeDisputeListPage._actionLabels.entries
                    .map((e) => DropdownMenuItem(
                        value: e.key, child: Text(e.value)))
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
        'approved' => 'تطبيق الجزاء الإداري',
        'modified' => 'تعديل الجزاء وتطبيقه',
        'rejected' => 'العفو',
        'deferred' => 'تأجيل القرار',
        _ => d,
      };

  static String _decisionSubtitle(String d) => switch (d) {
        'approved' => 'سيتم توقيع الجزاء الإداري المقترح كما هو',
        'modified' => 'سيتم تعديل الجزاء المقترح ثم تطبيقه',
        'rejected' => 'سيتم العفو وإغلاق القضية بدون جزاء إداري',
        'deferred' => 'سيتم تأجيل البت في القضية لوقت لاحق',
        _ => '',
      };

  static IconData _decisionIcon(String d) => switch (d) {
        'approved' => Icons.check_circle,
        'modified' => Icons.edit_note,
        'rejected' => Icons.cancel,
        'deferred' => Icons.schedule,
        _ => Icons.send,
      };

  static String _submitLabel(String d) => switch (d) {
        'approved' => 'توقيع الجزاء',
        'modified' => 'تعديل وتوقيع',
        'rejected' => 'العفو وإغلاق القضية',
        'deferred' => 'تأجيل',
        _ => 'إرسال',
      };
}

// ── ملخص آراء اللجنة داخل شاشة القرار التنفيذي ─────────────────────────────

class _DecisionRecommendationsPreview extends ConsumerWidget {
  const _DecisionRecommendationsPreview({required this.caseId});
  final String caseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(disputeCaseRecommendationsProvider(caseId));

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, _) => Card(
        color: theme.colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 18, color: theme.colorScheme.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'تعذر تحميل آراء اللجنة',
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
              TextButton.icon(
                onPressed: () => ref.invalidate(
                    disputeCaseRecommendationsProvider(caseId)),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('إعادة'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: theme.colorScheme.onErrorContainer,
                ),
              ),
            ],
          ),
        ),
      ),
      data: (data) {
        if (data.recommendations.isEmpty) {
          return Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('لا توجد آراء من أعضاء اللجنة بعد'),
                  ),
                ],
              ),
            ),
          );
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.groups, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'آراء أعضاء اللجنة (${data.totalCount})',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 8),
                ...data.recommendations.take(5).map((r) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 14,
                            child: Text(
                              r.submittedByName.isNotEmpty
                                  ? r.submittedByName[0]
                                  : '؟',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.submittedByName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13),
                                ),
                                Text(
                                  r.statementText,
                                  style: theme.textTheme.bodySmall,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )),
                if (data.recommendations.length > 5)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '+ ${data.recommendations.length - 5} آراء أخرى',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.primary),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── آراء وتوصيات أعضاء اللجنة (0198) ───────────────────────────────────────

class _RecommendationsSection extends ConsumerWidget {
  const _RecommendationsSection({required this.caseId});
  final String caseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final recsAsync = ref.watch(disputeCaseRecommendationsProvider(caseId));

    return recsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, _) => Card(
        color: theme.colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 18, color: theme.colorScheme.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'تعذر تحميل آراء اللجنة',
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
              TextButton.icon(
                onPressed: () => ref.invalidate(
                    disputeCaseRecommendationsProvider(caseId)),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('إعادة'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: theme.colorScheme.onErrorContainer,
                ),
              ),
            ],
          ),
        ),
      ),
      data: (data) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 24),
            Row(
              children: [
                Icon(Icons.rate_review_outlined,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text('آراء وتوصيات اللجنة',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                if (data.totalCount > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('${data.totalCount}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onPrimaryContainer)),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // قائمة الآراء الحالية
            if (data.recommendations.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'لم يتم تقديم أي آراء أو توصيات بعد',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
              )
            else
              ...data.recommendations.map((r) => _RecommendationCard(rec: r)),

            const SizedBox(height: 12),

            // زر إضافة رأي
            if (!data.myRecommendationExists)
              OutlinedButton.icon(
                onPressed: () => _showAddRecommendation(context, ref),
                icon: const Icon(Icons.add_comment_outlined),
                label: const Text('أضف رأيك'),
              )
            else
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 16, color: Colors.green.shade700),
                    const SizedBox(width: 6),
                    Text('تم تقديم رأيك',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700)),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  void _showAddRecommendation(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _AddRecommendationSheet(caseId: caseId),
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({required this.rec});
  final DisputeRecommendation rec;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final df = DateFormat('d MMM y — HH:mm', 'ar');
    final isNote = rec.statementType == 'committee_note';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: rec.isOwn
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25)
          : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: isNote
                      ? Colors.orange.shade100
                      : theme.colorScheme.primaryContainer,
                  child: Icon(
                    isNote ? Icons.note_outlined : Icons.thumb_up_outlined,
                    size: 14,
                    color: isNote
                        ? Colors.orange.shade800
                        : theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rec.submittedByName,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Text(
                        isNote ? 'ملاحظة' : 'توصية',
                        style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (rec.isOwn)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('أنت',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(rec.statementText,
                style: const TextStyle(fontSize: 13, height: 1.6)),
            const SizedBox(height: 6),
            if (rec.submittedAt != null)
              Text(
                df.format(rec.submittedAt!),
                style: TextStyle(
                    fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}

class _AddRecommendationSheet extends ConsumerStatefulWidget {
  const _AddRecommendationSheet({required this.caseId});
  final String caseId;

  @override
  ConsumerState<_AddRecommendationSheet> createState() =>
      _AddRecommendationSheetState();
}

class _AddRecommendationSheetState
    extends ConsumerState<_AddRecommendationSheet> {
  final _controller = TextEditingController();
  String _type = 'recommendation';
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_submitting && _controller.text.trim().length >= 10;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    try {
      await ref.read(mobileCommandsProvider).submitDisputeRecommendation(
            caseId: widget.caseId,
            text: _controller.text,
            statementType: _type,
          );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تقديم رأيك بنجاح')),
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
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            Text('أضف رأيك',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('سيتم مشاركة رأيك مع أعضاء اللجنة فقط',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),

            // نوع المشاركة
            Text('نوع المشاركة', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            RadioListTile<String>(
              value: 'recommendation',
              groupValue: _type,
              dense: true,
              contentPadding: EdgeInsets.zero,
              onChanged: (v) => setState(() => _type = v!),
              title: const Text('توصية'),
              subtitle: const Text('رأيك النهائي في القضية'),
            ),
            RadioListTile<String>(
              value: 'committee_note',
              groupValue: _type,
              dense: true,
              contentPadding: EdgeInsets.zero,
              onChanged: (v) => setState(() => _type = v!),
              title: const Text('ملاحظة'),
              subtitle: const Text('ملاحظة أو ملحوظة للمناقشة'),
            ),
            const SizedBox(height: 12),

            // نص الرأي
            TextField(
              controller: _controller,
              maxLines: 5,
              maxLength: 1000,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'نص الرأي أو التوصية',
                hintText: '10 أحرف على الأقل',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),

            FilledButton.icon(
              onPressed: _canSubmit ? _submit : null,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
              label: Text(_type == 'recommendation'
                  ? 'إرسال التوصية'
                  : 'إرسال الملاحظة'),
            ),
          ],
        ),
      ),
    );
  }
}
