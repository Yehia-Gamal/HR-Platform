part of '../mobile_request_detail_page.dart';

class _MissionExecutionCard extends ConsumerWidget {
  const _MissionExecutionCard({required this.request, required this.isOwner});

  final MobileRequestDetail request;
  final bool isOwner;

  String get _noun => switch (request.type) {
    'convoy' => 'القافلة',
    'fundraising' => 'الفاندي',
    _ => 'المأمورية',
  };

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(mobileCommandsProvider).startMission(request.id);
      messenger.showSnackBar(
        SnackBar(content: Text('بدأت $_noun — بالتوفيق.')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر البدء: ${humanizeError(error)}')),
      );
    }
  }

  Future<void> _end(BuildContext context, WidgetRef ref) async {
    final result =
        await showModalBottomSheet<
          ({String report, String? outcome, bool withCheckout})
        >(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          useSafeArea: true,
          builder: (context) => _EndMissionSheet(noun: _noun),
        );
    if (result == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);

    Position? position;
    if (result.withCheckout) {
      try {
        position = await LocationService.current();
      } catch (locErr) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'الانصراف من الخارج يتطلب تفعيل الـ GPS وأخذ موقع مباشر: ${humanizeError(locErr)}',
            ),
            backgroundColor: AppColors.statusDanger,
          ),
        );
        return;
      }
    }

    try {
      await ref
          .read(mobileCommandsProvider)
          .endMission(
            requestId: request.id,
            report: result.report,
            outcome: result.outcome,
            withCheckout: result.withCheckout,
            latitude: position?.latitude,
            longitude: position?.longitude,
            accuracy: position?.accuracy,
            isMock: position?.isMocked ?? false,
          );
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.statusSuccess,
          content: Text(
            result.withCheckout
                ? 'تم إنهاء $_noun وتسجيل انصرافك الميداني بنجاح.'
                : 'تم إنهاء $_noun — دوامك مستمر.',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر الإنهاء: ${humanizeError(error)}')),
      );
    }
  }

  /// 0658: تقرير مأمورية أغلقها النظام — لا يغيّر الإغلاق ولا حضور يومها.
  Future<void> _writeReport(
    BuildContext context,
    WidgetRef ref,
    MobileMissionExecution execution,
  ) async {
    final result =
        await showModalBottomSheet<
          ({String report, String? outcome, bool withCheckout})
        >(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          useSafeArea: true,
          builder: (context) => _EndMissionSheet(
            noun: _noun,
            reportOnly: true,
            initialReport: execution.awaitsReport ? null : execution.report,
            initialOutcome: execution.outcome,
          ),
        );
    if (result == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(mobileCommandsProvider)
          .submitMissionReport(
            requestId: request.id,
            report: result.report,
            outcome: result.outcome,
          );
      messenger.showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.statusSuccess,
          content: Text('حُفظ التقرير.'),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر حفظ التقرير: ${humanizeError(error)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final execution = request.missionExecution;
    final status = request.status;
    final actionable = status == 'approved' || status == 'pending';
    final started = execution?.startedAt != null;
    // tg_mission_execution_close_on_cancel يغلق التنفيذ «completed» بهذا النص
    // لحظة الرفض/السحب — ليس إنجازًا من الموظف
    final closedAt = request.cancelledAt ?? request.decidedAt;
    final systemClosed =
        execution?.report?.trim() == 'أُلغي الطلب قبل إتمام التنفيذ' ||
        (const {
              'rejected',
              'cancelled',
              'withdrawn',
              'expired',
            }.contains(status) &&
            closedAt != null &&
            execution?.endedAt != null &&
            execution!.endedAt!.difference(closedAt).inMinutes.abs() <= 2);
    // 0658: أغلقها النظام لانقضاء يومها دون إنهاء — ليست «أُنجزت»، ولصاحبها
    // كتابة تقريرها خلال 14 يومًا.
    final autoClosed = !systemClosed && execution?.isAutoClosed == true;
    final reportDeadline = execution?.reportDeadline;
    final canWriteReport =
        isOwner &&
        autoClosed &&
        reportDeadline != null &&
        DateTime.now().isBefore(reportDeadline);
    final completed =
        execution != null &&
        !systemClosed &&
        !autoClosed &&
        (execution.isCompleted || execution.endedAt != null);
    final stopped =
        !completed &&
        !autoClosed &&
        (systemClosed ||
            execution?.status == 'cancelled' ||
            const {
              'rejected',
              'cancelled',
              'withdrawn',
              'expired',
              'returned',
            }.contains(status));
    final inProgress =
        execution != null && execution.isInProgress && !completed && !stopped;
    // مأمورية «قيد التنفيذ» انقضى يومها دون إنهاء: إنهاؤها اليوم يسجّل حضورًا
    // وانصرافًا لليوم الحالي، فلا يُعرض زر الإنهاء لها.
    final lastDay =
        requestLastDay(request.payload) ?? execution?.startedAt?.toLocal();
    final today = DateUtils.dateOnly(DateTime.now());
    final stale =
        inProgress &&
        lastDay != null &&
        DateUtils.dateOnly(lastDay).isBefore(today);
    // 0607: البدء والإنهاء متاحان لصاحب التكليف والطلب معلّق أو معتمد
    final canStart =
        isOwner && actionable && !started && !completed && !stopped;
    final canEnd = isOwner && actionable && inProgress && !stale;

    final (
      Color color,
      IconData icon,
      String headline,
      String? note,
    ) = switch ((autoClosed, completed, stopped, stale, inProgress)) {
      (true, _, _, _, _) when execution!.awaitsReport => (
        AppColors.statusWarning,
        Icons.history_toggle_off_rounded,
        'أغلق النظام $_noun لانقضاء يومها دون إنهاء',
        isOwner
            ? (canWriteReport
                  ? 'اكتب ما أنجزته قبل ${arDay(reportDeadline.toLocal())} — لا يغيّر ذلك حضور يومها.'
                  : 'انتهت مهلة كتابة التقرير.')
            : 'لم يسجّل الموظف إنهاءها وتقريرها في يومها.',
      ),
      (true, _, _, _, _) => (
        AppColors.statusSuccess,
        Icons.task_alt_rounded,
        'أُغلقت $_noun تلقائيًا وكُتب تقريرها لاحقًا',
        null,
      ),
      (_, true, _, _, _) => (
        AppColors.statusSuccess,
        Icons.task_alt_rounded,
        'أُنجزت $_noun وقُدِّم التقرير',
        null,
      ),
      (_, _, true, _, _) => (
        const Color(0xFF64748B),
        Icons.block_rounded,
        status == 'cancelled'
            ? 'سُحب الطلب فتوقف التنفيذ'
            : status == 'returned'
            ? 'أُعيد الطلب للتعديل فتوقف التنفيذ'
            : 'رُفض الطلب فتوقف التنفيذ',
        null,
      ),
      (_, _, _, true, _) => (
        AppColors.statusWarning,
        Icons.history_toggle_off_rounded,
        'لم يُسجَّل إنهاء $_noun في يومها',
        isOwner
            ? 'انقضى يومها دون تقرير — تواصل مع الموارد البشرية إن لزم تسوية الحضور.'
            : 'انقضى يومها دون أن يسجّل الموظف الإنهاء والتقرير.',
      ),
      (_, _, _, _, true) => (
        const Color(0xFF2563EB),
        Icons.directions_run_rounded,
        isOwner ? '$_noun جارية الآن' : 'الموظف في $_noun الآن',
        [
          if (status == 'pending')
            'بدأت قبل صدور القرار والطلب ما زال قيد المراجعة.',
          if (isOwner) 'عند الانتهاء اضغط «إنهاء $_noun» وقدّم تقريرك.',
        ].join(' '),
      ),
      _ => (
        status == 'pending' ? AppColors.statusInfo : const Color(0xFF64748B),
        status == 'pending'
            ? Icons.pending_actions_rounded
            : Icons.flag_outlined,
        status == 'pending'
            ? 'بانتظار الاعتماد لبدء التنفيذ'
            : 'لم يبدأ التنفيذ بعد',
        isOwner
            ? (status == 'approved'
                  ? 'اعتُمدت $_noun — ابدأها عند انطلاقك فعليًا.'
                  : (status == 'pending'
                        ? 'يبدأ التنفيذ الميداني بعد صدور قرار الإدارة واعتماد الطلب.'
                        : null))
            : (status == 'approved'
                  ? 'اعتُمدت وبانتظار أن يبدأ الموظف التنفيذ.'
                  : (status == 'pending'
                        ? 'لا يبدأ التنفيذ الميداني قبل اكتمال مسار الاعتماد والموافقة.'
                        : null)),
      ),
    };

    final rows = <(String, String)>[
      if (execution?.startedAt != null)
        ('بدأت', arDateTime(execution!.startedAt!)),
      if (execution?.endedAt != null)
        (
          systemClosed ? 'توقفت' : (autoClosed ? 'أُغلقت' : 'انتهت'),
          arDateTime(execution!.endedAt!),
        ),
      if (execution?.actualMinutes != null && completed)
        ('المدة الفعلية', arDurationMinutes(execution.actualMinutes!)),
    ];

    return _SectionCard(
      icon: requestTypeIcon(request.type),
      title: 'تنفيذ $_noun',
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: .25)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: color,
                        fontSize: 14,
                      ),
                    ),
                    if (note != null && note.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        note,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.5,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (rows.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 92,
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      value,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (!systemClosed &&
            execution?.awaitsReport != true &&
            execution?.report?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 8),
          _QuoteBox(label: 'تقرير التنفيذ', text: execution!.report!.trim()),
        ],
        if (execution?.outcome?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 8),
          _QuoteBox(label: 'النتيجة', text: execution!.outcome!.trim()),
        ],
        if (canStart) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () => _start(context, ref),
            icon: const Icon(Icons.play_circle_outline_rounded),
            label: Text('ابدأ $_noun الآن'),
          ),
        ],
        if (canEnd) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.statusSuccess,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () => _end(context, ref),
            icon: const Icon(Icons.flag_rounded),
            label: Text('إنهاء $_noun وتقديم التقرير'),
          ),
        ],
        if (canWriteReport && execution != null) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () => _writeReport(context, ref, execution),
            icon: const Icon(Icons.edit_note_rounded),
            label: Text(
              execution.awaitsReport ? 'كتابة تقرير $_noun' : 'تعديل التقرير',
            ),
          ),
        ],
      ],
    );
  }
}

class _QuoteBox extends StatelessWidget {
  const _QuoteBox({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 3),
          Text(text, style: const TextStyle(fontSize: 13, height: 1.55)),
        ],
      ),
    );
  }
}

/// ورقة إنهاء المأمورية: تقرير إلزامي + نتيجة اختيارية + إنهاء بالانصراف أو بدونه.
/// وبـ[reportOnly]: تقرير مأمورية أغلقها النظام — حفظ فقط، بلا إنهاء ولا انصراف.
