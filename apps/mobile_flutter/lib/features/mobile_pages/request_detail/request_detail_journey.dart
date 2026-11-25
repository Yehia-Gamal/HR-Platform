part of '../mobile_request_detail_page.dart';

class _JourneyEvent {
  const _JourneyEvent({
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.at,
    this.comment,
    this.chip,
    this.chipDanger = false,
    this.live = false,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final DateTime? at;
  final String? comment;
  final String? chip;
  final bool chipDanger;
  final bool live;
}

class _JourneyCard extends StatelessWidget {
  const _JourneyCard({required this.request});

  final MobileRequestDetail request;

  static const _returnColor = Color(0xFFC2410C);
  static const _muted = Color(0xFF64748B);

  String _stage(String? name, String? role, int? order) =>
      requestStageName(name, roleSlug: role, order: order);

  List<_JourneyEvent> _events() {
    final events = <_JourneyEvent>[];
    final history = request.history;
    if (history != null && history.isNotEmpty) {
      for (final h in history) {
        final stage = h.stepOrder == null && h.stepName == null
            ? null
            : _stage(h.stepName, h.stepRole, h.stepOrder);
        switch (h.action) {
          case 'submit':
            events.add(
              _JourneyEvent(
                icon: h.isResubmit ? Icons.replay_rounded : Icons.send_rounded,
                color: AppColors.brandPrimary,
                title: h.isResubmit
                    ? 'أُعيد رفع الطلب بعد التعديل'
                    : 'قُدِّم الطلب',
                subtitle: h.actorName ?? request.employeeName,
                at: h.at,
              ),
            );
          case 'escalate':
            final repeat = h.repeat ?? 1;
            events.add(
              _JourneyEvent(
                icon: Icons.trending_up_rounded,
                color: AppColors.statusWarning,
                title:
                    'صُعِّد تلقائيًا إلى ${escalationTargetLabel(h.targetRole)}',
                subtitle: repeat > 1
                    ? 'لعدم صدور قرار في المهلة · تكرر التذكير ${arCount(repeat, one: 'مرة', two: 'مرتين', few: 'مرات', many: 'مرة', base: 'مرة')}'
                    : 'لعدم صدور قرار في المهلة',
                at: h.at,
              ),
            );
          case 'approve':
            events.add(
              _JourneyEvent(
                icon: Icons.check_rounded,
                color: AppColors.statusSuccess,
                title: 'اعتمده ${h.actorName ?? 'المعتمِد'}',
                subtitle: stage,
                at: h.at,
                comment: h.comment,
              ),
            );
          case 'reject':
            events.add(
              _JourneyEvent(
                icon: Icons.close_rounded,
                color: AppColors.statusDanger,
                title: 'رفضه ${h.actorName ?? 'المعتمِد'}',
                subtitle: stage,
                at: h.at,
                comment: h.comment,
              ),
            );
          case 'return' || 'request_changes':
            events.add(
              _JourneyEvent(
                icon: Icons.undo_rounded,
                color: _returnColor,
                title: 'أعاده ${h.actorName ?? 'المعتمِد'} للتعديل',
                subtitle: stage,
                at: h.at,
                comment: h.comment,
              ),
            );
          case 'cancel' || 'withdraw':
            events.add(
              _JourneyEvent(
                icon: Icons.block_rounded,
                color: _muted,
                title: 'سُحب الطلب',
                subtitle:
                    h.actorName == null || h.actorName == request.employeeName
                    ? 'بواسطة صاحب الطلب'
                    : 'بواسطة ${h.actorName}',
                at: h.at,
                comment: h.comment,
              ),
            );
          case 'expire':
            events.add(
              _JourneyEvent(
                icon: Icons.timer_off_outlined,
                color: _muted,
                title: 'انتهت مهلة الطلب',
                at: h.at,
              ),
            );
          case 'reassign':
            events.add(
              _JourneyEvent(
                icon: Icons.swap_horiz_rounded,
                color: AppColors.statusViolet,
                title: 'أُعيد إسناد الطلب',
                subtitle: h.actorName,
                at: h.at,
                comment: h.comment,
              ),
            );
        }
      }
    } else {
      // خادم أقدم بلا سجل: يُبنى من المراحل
      events.add(
        _JourneyEvent(
          icon: Icons.send_rounded,
          color: AppColors.brandPrimary,
          title: 'قُدِّم الطلب',
          subtitle: request.employeeName,
          at: request.createdAt,
        ),
      );
      for (final s in request.steps) {
        final stage = _stage(s.name, s.roleSlug, s.order);
        if (s.status == 'escalated' || s.escalatedAt != null) {
          events.add(
            _JourneyEvent(
              icon: Icons.trending_up_rounded,
              color: AppColors.statusWarning,
              title: 'صُعِّد من $stage لتأخر الرد',
              at: s.escalatedAt,
            ),
          );
        }
        final state = requestStageState(s, request.status, isCurrent: false);
        if (state.isDecision) {
          events.add(
            _JourneyEvent(
              icon: state.icon,
              color: state.color,
              title: switch (state) {
                RequestStageState.approved =>
                  'اعتمده ${s.actorName ?? 'المعتمِد'}',
                RequestStageState.returned =>
                  'أعاده ${s.actorName ?? 'المعتمِد'} للتعديل',
                _ => 'رفضه ${s.actorName ?? 'المعتمِد'}',
              },
              subtitle: stage,
              at: s.decidedAt,
              comment: s.comment,
            ),
          );
        }
      }
      if (request.status == 'cancelled') {
        events.add(
          _JourneyEvent(
            icon: Icons.block_rounded,
            color: _muted,
            title: 'سُحب الطلب',
            at: request.cancelledAt ?? request.updatedAt,
            comment: request.cancelReason,
          ),
        );
      }
    }

    if (request.status == 'pending') {
      final i = currentStepIndex(request.steps, request.status);
      final step = i >= 0 ? request.steps[i] : null;
      final due = requestDueStatus(step?.dueAt ?? request.decisionDueAt);
      events.add(
        _JourneyEvent(
          icon: Icons.hourglass_top_rounded,
          color: AppColors.statusInfo,
          title: step == null
              ? 'بانتظار القرار'
              : 'بانتظار قرار ${_stage(step.name, step.roleSlug, step.order)}',
          chip: due?.label,
          chipDanger: due?.overdue ?? false,
          live: true,
        ),
      );
    }

    // استبعاد تكرار الاعتماد لنفس الشخص بنفس التعليق والتوقيت
    final deduplicated = <_JourneyEvent>[];
    for (final ev in events) {
      final isDup = deduplicated.any((existing) =>
          existing.title == ev.title &&
          existing.comment == ev.comment &&
          existing.icon == ev.icon &&
          (existing.at == null ||
              ev.at == null ||
              existing.at!.difference(ev.at!).inMinutes.abs() <= 2));
      if (!isDup) {
        deduplicated.add(ev);
      }
    }
    return deduplicated;
  }

  @override
  Widget build(BuildContext context) {
    final events = _events();
    final current = currentStepIndex(request.steps, request.status);
    return _SectionCard(
      icon: Icons.route_rounded,
      title: 'مسار الاعتماد',
      children: [
        if (request.steps.isNotEmpty) ...[
          _StageStrip(
            steps: request.steps,
            requestStatus: request.status,
            currentIndex: current,
          ),
          const SizedBox(height: 12),
          Divider(
            height: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          const SizedBox(height: 12),
        ] else if (request.status == 'pending') ...[
          Text(
            'لم تُنشأ مراحل اعتماد لهذا الطلب — يبت فيه المعتمِد مباشرة.',
            style: TextStyle(
              fontSize: 12.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
        ],
        for (var i = 0; i < events.length; i++)
          _EventTile(
            event: events[i],
            isFirst: i == 0,
            isLast: i == events.length - 1,
          ),
      ],
    );
  }
}

/// المراحل متتالية مع حالة كل منها: «المدير المباشر ✓ — مدير التشغيل 1 لم يلزم».
