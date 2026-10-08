import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/core/formatting/arabic_text.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/kpi_evaluation_detail_page.dart'
    show kpiStageLabel;
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_action_router.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_request_detail_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/request_decision_sheet.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/request_display.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// صندوق الإجراءات: ما ينتظر قرارك (طلبات، تقييمات، قرارات للاطلاع) ثم
/// طلباتك قيد المراجعة للمتابعة — الأحدث أولًا داخل كل قسم.
class MobileActionInboxPage extends ConsumerWidget {
  const MobileActionInboxPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.watch(mobileActionCenterProvider);
    // الطلبات نفسها من صندوق الطلبات لإثراء البطاقة (النوع، المرحلة، دورك)
    final requests =
        ref.watch(mobileRequestsProvider).value ?? const <MobileRequest>[];
    final me = ref.watch(accessContextProvider).value?.employeeId;
    final byId = {for (final r in requests) r.id: r};

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(mobileActionCenterProvider);
        ref.invalidate(mobileRequestsProvider);
      },
      child: actions.when(
        loading: () => ListView(
          children: const [
            SizedBox(height: 220),
            Center(
              child: CircularProgressIndicator(semanticsLabel: 'جاري التحميل'),
            ),
          ],
        ),
        error: (error, _) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 80),
            Icon(
              Icons.cloud_off_rounded,
              size: 44,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
            Text(humanizeError(error), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Center(
              child: OutlinedButton(
                onPressed: () => ref.invalidate(mobileActionCenterProvider),
                child: const Text('إعادة المحاولة'),
              ),
            ),
          ],
        ),
        data: (items) {
          final toDecide = <_RequestEntry>[];
          final mine = <_RequestEntry>[];
          final kpis = <MobileActionItem>[];
          final others = <MobileActionItem>[];
          for (final item in items) {
            if (item.kind == 'request') {
              final id = item.id.startsWith('request-')
                  ? item.id.substring('request-'.length)
                  : null;
              final request = id == null ? null : byId[id];
              final entry = _RequestEntry(item: item, request: request, id: id);
              (request?.isMineFor(me) ?? false ? mine : toDecide).add(entry);
            } else if (item.kind == 'kpi') {
              kpis.add(item);
            } else {
              others.add(item);
            }
          }
          final now = DateTime.now();
          // الأحدث أولًا (قرار المالك) — التأخر شارة على البطاقة وعدّاد أعلاه.
          // بلا تاريخ = خارج أحدث 100 طلب في get_request_inbox، أي أقدم ← آخرًا.
          final unknown = DateTime.fromMillisecondsSinceEpoch(0);
          int newestFirst(_RequestEntry a, _RequestEntry b) =>
              (b.createdAt ?? unknown).compareTo(a.createdAt ?? unknown);
          toDecide.sort(newestFirst);
          mine.sort(newestFirst);
          final overdue = toDecide
              .where((e) => e.dueAt?.isBefore(now) ?? false)
              .length;

          if (items.isEmpty) {
            return ListView(
              children: [
                const SizedBox(height: 160),
                Icon(
                  Icons.task_alt_rounded,
                  size: 52,
                  color: AppColors.statusSuccess.withValues(alpha: .7),
                ),
                const SizedBox(height: 10),
                const Center(
                  child: Text(
                    'لا توجد إجراءات معلّقة — كل شيء منجز.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              if (toDecide.isNotEmpty || kpis.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (toDecide.isNotEmpty)
                      RequestMetaChip(
                        icon: Icons.approval_rounded,
                        text: '${arRequests(toDecide.length)} بانتظار القرار',
                        color: AppColors.brandPrimary,
                        strong: true,
                      ),
                    if (overdue > 0)
                      RequestMetaChip(
                        icon: Icons.warning_amber_rounded,
                        text: 'متأخرة: $overdue',
                        color: AppColors.statusDanger,
                        strong: true,
                      ),
                    if (kpis.isNotEmpty)
                      RequestMetaChip(
                        icon: Icons.speed_rounded,
                        text: 'تقييمات: ${kpis.length}',
                        color: AppColors.statusViolet,
                      ),
                  ],
                ),
              if (toDecide.isNotEmpty) ...[
                const _SectionTitle(
                  icon: Icons.approval_rounded,
                  title: 'طلبات بانتظار القرار',
                ),
                for (final e in toDecide)
                  _RequestActionCard(
                    entry: e,
                    onOpen: () => _openRequest(context, ref, e),
                  ),
              ],
              if (kpis.isNotEmpty) ...[
                const _SectionTitle(
                  icon: Icons.speed_rounded,
                  title: 'تقييمات الأداء',
                ),
                for (final item in kpis)
                  _GenericActionCard(
                    item: item,
                    // مرحلة «ذاتي» لا تصل إلا لصاحب التقييم نفسه
                    title: item.status == 'self'
                        ? 'تقييمك الذاتي بانتظارك'
                        : null,
                    icon: Icons.speed_rounded,
                    color: AppColors.statusViolet,
                    subtitle: item.status == 'self'
                        ? 'أكمل تقييمك الذاتي ليتابع مديرك المراجعة.'
                        : 'المرحلة: ${kpiStageLabel(item.status)}',
                    onOpen: () => _openResolved(context, ref, item),
                  ),
              ],
              if (others.isNotEmpty) ...[
                const _SectionTitle(
                  icon: Icons.gavel_rounded,
                  title: 'للاطلاع والمتابعة',
                ),
                for (final item in others)
                  _GenericActionCard(
                    item: item,
                    icon: item.kind == 'decision'
                        ? Icons.gavel_rounded
                        : Icons.task_alt_rounded,
                    color: AppColors.brandPrimary,
                    subtitle: item.subtitle,
                    onOpen: () => _openResolved(context, ref, item),
                  ),
              ],
              if (mine.isNotEmpty) ...[
                const _SectionTitle(
                  icon: Icons.outbox_rounded,
                  title: 'طلباتك قيد المراجعة',
                ),
                for (final e in mine)
                  _RequestActionCard(
                    entry: e,
                    isMine: true,
                    onOpen: () => _openRequest(context, ref, e),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _openRequest(
    BuildContext context,
    WidgetRef ref,
    _RequestEntry entry,
  ) async {
    if (entry.id == null) return _openResolved(context, ref, entry.item);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MobileRequestDetailPage(requestId: entry.id!),
      ),
    );
    ref.invalidate(mobileActionCenterProvider);
  }

  Future<void> _openResolved(
    BuildContext context,
    WidgetRef ref,
    MobileActionItem item,
  ) async {
    try {
      final target = await ref.read(mobileCommandsProvider).resolveAction(item);
      if (!context.mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => mobilePageForActionTarget(target)),
      );
      ref.invalidate(mobileActionCenterProvider);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(humanizeError(error))));
      }
    }
  }
}

class _RequestEntry {
  const _RequestEntry({required this.item, required this.request, this.id});

  final MobileActionItem item;
  final MobileRequest? request;
  final String? id;

  DateTime? get dueAt => request?.effectiveDueAt ?? item.dueAt;
  DateTime? get createdAt => request?.createdAt;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// حالة مسار الطلب كما يرسلها مركز الإجراءات.
String _workflowLabel(String status) => switch (status) {
  'submitted' => 'جديد',
  'escalated' => 'مُصعَّد لتأخر الرد',
  'awaiting_operator' => 'عند مدير التشغيل 1',
  'in_review' => 'قيد المراجعة',
  _ => 'قيد المراجعة',
};

class _RequestActionCard extends ConsumerWidget {
  const _RequestActionCard({
    required this.entry,
    required this.onOpen,
    this.isMine = false,
  });

  final _RequestEntry entry;
  final VoidCallback onOpen;
  final bool isMine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final r = entry.request;
    final type = r?.type ?? '';
    final color = r == null ? AppColors.brandPrimary : requestTypeColor(type);
    final due = requestDueStatus(entry.dueAt);
    final stage = r?.activeStepName == null
        ? null
        : requestStageName(r!.activeStepName, roleSlug: r.activeStepRole);
    final headline = r == null
        ? entry.item.title
        : isMine
        ? '${requestTypeLabel(type)} · طلب رقم #${r.number}'
        : '${requestTypeLabel(type)} · ${r.employeeName} (#${r.number})';
    final title = r?.title?.trim();
    final reason = r?.reason?.trim();
    final second = r == null
        ? entry.item.subtitle
        : (title != null && title.isNotEmpty && title != requestTypeLabel(type))
        ? (reason != null && reason.isNotEmpty && reason != title
            ? '$title — $reason'
            : title)
        : requestBriefLine(type, r.payload);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: r?.awaitingMe == true
              ? AppColors.statusInfo.withValues(alpha: .45)
              : (due?.overdue ?? false) && !isMine
              ? AppColors.statusDanger.withValues(alpha: .35)
              : scheme.outlineVariant.withValues(alpha: .6),
        ),
      ),
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 21,
                backgroundColor: color.withValues(alpha: .12),
                child: Icon(
                  r == null ? Icons.approval_outlined : requestTypeIcon(type),
                  color: color,
                  size: 21,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    if (second != null && second.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        second.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (r?.awaitingMe == true && !isMine)
                          const RequestMetaChip(
                            icon: Icons.notifications_active_rounded,
                            text: 'دورك الآن',
                            color: AppColors.statusInfo,
                            strong: true,
                          ),
                        if (stage != null && (r?.awaitingMe != true || isMine))
                          RequestMetaChip(
                            icon: Icons.route_rounded,
                            text: 'عند $stage',
                          )
                        else if (r == null)
                          RequestMetaChip(
                            icon: Icons.route_rounded,
                            text: _workflowLabel(entry.item.status),
                          ),
                        if (due != null)
                          RequestMetaChip(
                            icon: due.overdue
                                ? Icons.warning_amber_rounded
                                : Icons.schedule_rounded,
                            text: due.label,
                            color: due.overdue ? AppColors.statusDanger : null,
                            strong: due.overdue,
                          ),
                        if (r != null)
                          RequestMetaChip(
                            icon: Icons.history_rounded,
                            text: 'قُدِّم ${arAgo(r.createdAt)}',
                          ),
                      ],
                    ),
                    if (r?.awaitingMe == true && !isMine && entry.id != null) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.tonalIcon(
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                visualDensity: VisualDensity.compact,
                                backgroundColor:
                                    AppColors.statusSuccess.withValues(alpha: .14),
                                foregroundColor: AppColors.statusSuccess,
                              ),
                              icon: const Icon(
                                Icons.check_circle_outline_rounded,
                                size: 18,
                              ),
                              label: const Text(
                                'اعتماد سريع',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                              onPressed: () async {
                                final done = await showRequestDecisionSheet(
                                  context,
                                  ref,
                                  requestId: entry.id!,
                                  number: r?.number ?? 0,
                                  type: r?.type ?? '',
                                  employeeName: r?.employeeName ?? '',
                                  decision: 'approve',
                                );
                                if (done) {
                                  ref.invalidate(mobileActionCenterProvider);
                                  ref.invalidate(mobileRequestsProvider);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                visualDensity: VisualDensity.compact,
                                side: BorderSide(
                                  color: AppColors.statusDanger.withValues(
                                    alpha: .5,
                                  ),
                                ),
                                foregroundColor: AppColors.statusDanger,
                              ),
                              icon: const Icon(Icons.close_rounded, size: 18),
                              label: const Text(
                                'رفض / إعادة',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                              onPressed: () async {
                                final done = await showRequestDecisionSheet(
                                  context,
                                  ref,
                                  requestId: entry.id!,
                                  number: r?.number ?? 0,
                                  type: r?.type ?? '',
                                  employeeName: r?.employeeName ?? '',
                                  decision: 'reject',
                                );
                                if (done) {
                                  ref.invalidate(mobileActionCenterProvider);
                                  ref.invalidate(mobileRequestsProvider);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_left_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _GenericActionCard extends StatelessWidget {
  const _GenericActionCard({
    required this.item,
    required this.icon,
    required this.color,
    required this.subtitle,
    required this.onOpen,
    this.title,
  });

  final MobileActionItem item;

  /// عنوان بديل لعنوان الخادم عند الحاجة.
  final String? title;
  final IconData icon;
  final Color color;
  final String? subtitle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final due = requestDueStatus(item.dueAt);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .6)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        leading: CircleAvatar(
          radius: 21,
          backgroundColor: color.withValues(alpha: .12),
          child: Icon(icon, color: color, size: 21),
        ),
        title: Text(
          title ?? item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (subtitle != null && subtitle!.trim().isNotEmpty)
              Text(
                subtitle!.trim(),
                style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
              ),
            if (due != null) ...[
              const SizedBox(height: 6),
              RequestMetaChip(
                icon: due.overdue
                    ? Icons.warning_amber_rounded
                    : Icons.schedule_rounded,
                text: due.label,
                color: due.overdue ? AppColors.statusDanger : null,
                strong: due.overdue,
              ),
            ],
          ],
        ),
        trailing: Icon(Icons.chevron_left_rounded, color: scheme.onSurfaceVariant),
        onTap: onOpen,
      ),
    );
  }
}
