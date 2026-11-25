part of '../mobile_request_detail_page.dart';

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.request,
    required this.isMine,
    required this.canDecide,
    required this.currentStage,
  });

  final MobileRequestDetail request;
  final bool isMine;
  final bool canDecide;
  final String? currentStage;

  /// المرحلة التي صدر فيها القرار ومن أصدره.
  ({String? who, String? stage}) _decisionInfo() {
    final decided = request.steps.where(
      (s) => s.status == 'approved' || s.status == 'rejected',
    );
    final step = decided.isEmpty ? null : decided.last;
    return (
      who:
          request.decidedByName ?? step?.actorName ?? request.decisionActorName,
      stage: step == null
          ? null
          : requestStageName(
              step.name,
              roleSlug: step.roleSlug,
              order: step.order,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final typeColor = requestTypeColor(request.type);
    final typeLabel = requestTypeLabel(request.type);
    final title = request.title?.trim();
    final showTitle = title != null && title.isNotEmpty && title != typeLabel;
    final subtitleParts = [
      if (request.employeeJobTitle?.trim().isNotEmpty == true)
        request.employeeJobTitle!.trim(),
      if (request.employeeDepartment?.trim().isNotEmpty == true)
        request.employeeDepartment!.trim(),
    ];

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: AlignmentDirectional.centerStart,
                end: AlignmentDirectional.centerEnd,
                colors: [
                  typeColor.withValues(alpha: .14),
                  typeColor.withValues(alpha: .04),
                ],
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: typeColor.withValues(alpha: .16),
                  child: Icon(
                    requestTypeIcon(request.type),
                    color: typeColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        typeLabel,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: typeColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'طلب رقم ${request.number} · قُدِّم ${arAgo(request.createdAt)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Builder(builder: (_) {
                        final retro = checkRetroactiveRequest(
                          request.createdAt,
                          request.payload,
                        );
                        if (!retro.isRetroactive) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: RetroactiveRequestBadge(daysDiff: retro.daysDiff),
                        );
                      }),
                    ],
                  ),
                ),
                RequestStatusChip(request.status),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showTitle) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: .07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: typeColor.withValues(alpha: .28),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.bookmark_rounded,
                              size: 15,
                              color: typeColor,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'موضوع ${requestTypeDefiniteLabel(request.type)}',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: typeColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            height: 1.45,
                            color: scheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _statusBanner(context),
                const SizedBox(height: 12),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: isMine || request.employeeId == null
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EmployeeProfilePage(
                              employeeId: request.employeeId!,
                              employeeName: request.employeeName,
                            ),
                          ),
                        ),
                  child: Row(
                    children: [
                      AppAvatar(
                        name: request.employeeName,
                        photoUrl: request.employeePhotoUrl,
                        radius: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              request.employeeName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              subtitleParts.isEmpty
                                  ? 'صاحب الطلب'
                                  : subtitleParts.join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isMine)
                        const RequestMetaChip(
                          icon: Icons.person_rounded,
                          text: 'طلبك',
                          color: AppColors.brandPrimary,
                        )
                      else if (request.employeeId != null)
                        Icon(
                          Icons.chevron_left_rounded,
                          color: scheme.onSurfaceVariant,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBanner(BuildContext context) {
    final style = requestStatusStyle(request.status);
    String main;
    String? detail;
    Widget? chip;
    switch (request.status) {
      case 'pending':
        final isEscalatedToOps = request.workflowStatus == 'awaiting_operator' ||
            (currentStage?.contains('مدير التشغيل') ?? false);
        final awaiting = canDecide && (request.awaitingMe ?? true);
        if (isEscalatedToOps && canDecide) {
          main = 'الطلب مصعّد لمدير التشغيل (أبو عمار)';
        } else {
          main = awaiting
              ? 'الطلب بانتظار قرارك'
              : 'بانتظار قرار ${currentStage ?? 'الإدارة'}';
        }
        final current = currentStepIndex(request.steps, request.status);
        final dueAt = current >= 0 ? request.steps[current].dueAt : request.decisionDueAt;
        if (isEscalatedToOps && canDecide) {
          detail = dueAt != null
              ? 'المرحلة: مدير التشغيل 1 (أبو عمار) · متاح لك كمدير مباشر اعتماده أو رفضه فوراً'
              : 'المرحلة: مدير التشغيل 1 (أبو عمار) · متاح لك كمدير مباشر اعتماده أو رفضه فوراً';
        } else if (awaiting) {
          if (currentStage != null) {
            detail = dueAt != null
                ? 'المرحلة الحالية: $currentStage · أقصى موعد للبت: ${arDateTime(dueAt)}'
                : 'المرحلة الحالية: $currentStage';
          }
        } else if (canDecide) {
          detail = dueAt != null
              ? 'يمكنك البت فيه بصلاحيتك · أقصى موعد: ${arDateTime(dueAt)}'
              : 'يمكنك البت فيه بصلاحيتك قبل وصوله إليك';
        } else if (dueAt != null) {
          detail = 'أقصى موعد للرد: ${arDateTime(dueAt)}';
        }
        final due = requestDueStatus(dueAt);
        if (due != null) {
          chip = RequestMetaChip(
            icon: due.overdue
                ? Icons.warning_amber_rounded
                : Icons.schedule_rounded,
            text: due.label,
            color: due.overdue ? AppColors.statusDanger : AppColors.statusInfo,
            strong: due.overdue,
          );
        }
      case 'approved' || 'rejected' || 'returned':
        final info = _decisionInfo();
        final verb = switch (request.status) {
          'approved' => 'اعتمده',
          'rejected' => 'رفضه',
          _ => 'أعاده للتعديل',
        };
        main = info.who == null
            ? style.label
            : request.status == 'returned'
            ? 'أعاده ${info.who} للتعديل'
            : '$verb ${info.who}';
        final when =
            request.decidedAt ??
            request.steps
                .where((s) => s.decidedAt != null)
                .map((s) => s.decidedAt!)
                .fold<DateTime?>(
                  null,
                  (a, b) => a == null || b.isAfter(a) ? b : a,
                );
        detail = [
          if (info.stage != null) info.stage!,
          if (request.decisionOnBehalfOfExecutive)
            'بالإنابة عن المدير التنفيذي',
          if (when != null) arDateTime(when),
        ].join(' · ');
      case 'cancelled' || 'withdrawn':
        main =
            request.cancelledByName == null ||
                request.cancelledByName == request.employeeName
            ? 'سحبه صاحب الطلب'
            : 'سحبه ${request.cancelledByName}';
        final when = request.cancelledAt ?? request.updatedAt;
        detail = [
          if (when != null) arDateTime(when),
          if (request.cancelReason?.trim().isNotEmpty == true)
            'السبب: ${request.cancelReason!.trim()}',
        ].join(' · ');
      default:
        main = style.label;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: style.color.withValues(alpha: .25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(style.icon, color: style.color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  main,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14.5,
                    color: style.color,
                  ),
                ),
                if (detail != null && detail.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    detail,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Builder(
                  builder: (_) {
                    final activeStep = request.steps
                        .where((s) => s.isCurrent == true || s.status == 'active')
                        .firstOrNull;
                    final sla = calculateRequestSla(
                      createdAt: request.createdAt,
                      status: request.status,
                      decidedAt: request.decidedAt,
                      activeStepName: activeStep?.name ?? currentStage,
                      activeStepRole: activeStep?.roleSlug,
                      activeStepActor: activeStep?.actorName,
                      decidedByName: request.decidedByName,
                    );
                    return Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        RequestSlaChip(sla: sla),
                        ?chip,
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// تفاصيل الطلب: البيانات حسب النوع + السبب + المرفقات
// ═══════════════════════════════════════════════════════════════════════════

