import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/core/formatting/arabic_text.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/approval_delegations_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/attendance_correction_detail_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_request_detail_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/request_decision_sheet.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/request_display.dart';
import 'package:ahla_shabab_management_os/shared/permission_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

/// اعتماد طلبات الفريق: الإجازات والمأموريات والأذونات وتغيير الفترة وتصحيحات
/// البصمة — الأحدث أولًا، مع اعتماد/رفض سريع وفتح التفاصيل.
class TeamRequestsPage extends ConsumerStatefulWidget {
  const TeamRequestsPage({super.key});

  @override
  ConsumerState<TeamRequestsPage> createState() => _TeamRequestsPageState();
}

enum _Category {
  all('الكل', null),
  leaves('الإجازات', Icons.beach_access_rounded),
  missions('المأموريات والقوافل', Icons.business_center_rounded),
  permits('الأذونات', Icons.schedule_rounded),
  shifts('فترات العمل', Icons.more_time_rounded),
  corrections('تصحيحات البصمة', Icons.fingerprint_rounded);

  const _Category(this.label, this.icon);

  final String label;
  final IconData? icon;

  bool matches(String type) => switch (this) {
    _Category.all => true,
    _Category.leaves => type == 'leave',
    _Category.missions => isFieldAssignmentType(type),
    _Category.permits =>
      type == 'late_permit' || type == 'early_permit' || type == 'excuse',
    _Category.shifts => type == 'shift_change',
    _Category.corrections => false,
  };
}

class _TeamRequestsPageState extends ConsumerState<TeamRequestsPage> {
  final _search = TextEditingController();
  String _query = '';
  String _statusFilter = 'pending';
  _Category _category = _Category.all;

  /// اعتماد جماعي: معرّفات الطلبات المحددة (معلّقة ويملك المستخدم قرارها).
  final _selected = <String>{};
  bool get _selecting => _selected.isNotEmpty;

  bool _selectable(MobileRequest r) =>
      r.status == 'pending' && (r.canDecide ?? true);

  void _toggle(MobileRequest r) {
    if (!_selectable(r)) return;
    setState(() {
      if (!_selected.remove(r.id)) _selected.add(r.id);
    });
  }

  Future<void> _bulkApprove(List<MobileRequest> visible) async {
    final picked = visible.where((r) => _selected.contains(r.id)).toList();
    if (picked.isEmpty) return;
    final approved = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => _BulkApproveSheet(requests: picked),
    );
    if (!mounted) return;
    setState(_selected.clear);
    ref.invalidate(mobileRequestsProvider);
    if (approved != null && approved > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.statusSuccess,
          content: Text('تم اعتماد ${arRequests(approved)} وإبلاغ أصحابها.'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// حالة التصحيحات المرسلة للخادم.
  String? get _correctionStatus => switch (_statusFilter) {
    'pending' => 'pending',
    'approved' => 'approved',
    'closed' => 'rejected',
    _ => null,
  };

  /// طلبات الآخرين في نطاقي: الخادم (0646) يحدّد النطاق ويعلّم طلباتي؛
  /// الخادم الأقدم يُكتفى معه بأعضاء الفريق المباشر.
  bool _inScope(MobileRequest r, String? me, Set<String> teamIds) {
    if (r.isMineFor(me)) return false;
    if (r.isMine != null) return true;
    return r.employeeId != null && teamIds.contains(r.employeeId);
  }

  bool _matchesStatus(MobileRequest r) => switch (_statusFilter) {
    'pending' => r.status == 'pending' && (r.canDecide ?? true),
    'approved' => r.status == 'approved',
    'closed' =>
      r.status == 'rejected' ||
          r.status == 'returned' ||
          r.status == 'cancelled',
    _ => true,
  };

  bool _matchesQuery(MobileRequest r) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [
      r.employeeName,
      r.title ?? '',
      r.reason ?? '',
      r.employeeDepartment ?? '',
      requestTypeLabel(r.type),
      '${r.number}',
    ].any((v) => v.toLowerCase().contains(q));
  }

  List<MobileRequest> _filtered(
    List<MobileRequest> all,
    String? me,
    Set<String> teamIds,
  ) {
    if (_category == _Category.corrections) return const [];
    final list = all
        .where(
          (r) =>
              _inScope(r, me, teamIds) &&
              _category.matches(r.type) &&
              _matchesStatus(r) &&
              _matchesQuery(r),
        )
        .toList();
    // الأحدث أولًا في كل الحالات (قرار المالك) — «دورك» و«متأخر» شارات على
    // البطاقة وأعداد في الملخص، لا ترتيب يدفع القديم إلى الأعلى.
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  List<MobileTeamAttendanceCorrection> _filteredCorrections(
    List<MobileTeamAttendanceCorrection> corrections,
  ) {
    if (_category != _Category.all && _category != _Category.corrections) {
      return const [];
    }
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return corrections;
    return corrections
        .where(
          (c) =>
              c.employeeName.toLowerCase().contains(q) ||
              (c.jobTitle?.toLowerCase().contains(q) ?? false) ||
              c.reason.toLowerCase().contains(q),
        )
        .toList(growable: false);
  }

  Future<void> _openRequest(MobileRequest request) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MobileRequestDetailPage(requestId: request.id),
      ),
    );
    if (mounted) ref.invalidate(mobileRequestsProvider);
  }

  Future<void> _openCorrection(MobileTeamAttendanceCorrection c) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AttendanceCorrectionDetailPage(correctionId: c.id),
      ),
    );
    if (mounted) ref.invalidate(teamAttendanceCorrectionsProvider(_correctionStatus));
  }

  Widget _card(MobileRequest r) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: _TeamRequestCard(
      request: r,
      selecting: _selecting,
      selected: _selected.contains(r.id),
      onTap: _selecting ? () => _toggle(r) : () => _openRequest(r),
      onLongPress: _selectable(r) ? () => _toggle(r) : null,
      onApprove: !_selecting && _selectable(r)
          ? () => _quickDecide(r, 'approve')
          : null,
      onReject: !_selecting && _selectable(r)
          ? () => _quickDecide(r, 'reject')
          : null,
    ),
  );

  Widget _correctionCard(MobileTeamAttendanceCorrection c) {
    final decidable = c.status == 'pending' && c.canDecide;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _CorrectionCard(
        correction: c,
        onTap: () => _openCorrection(c),
        onApprove: decidable ? () => _decideCorrection(c, 'approved') : null,
        onReject: decidable ? () => _decideCorrection(c, 'rejected') : null,
      ),
    );
  }

  Future<void> _quickDecide(MobileRequest r, String decision) =>
      showRequestDecisionSheet(
        context,
        ref,
        requestId: r.id,
        number: r.number,
        type: r.type,
        employeeName: r.employeeName,
        decision: decision,
      );

  Future<void> _decideCorrection(
    MobileTeamAttendanceCorrection correction,
    String decision,
  ) async {
    final approve = decision == 'approved';
    final commands = ref.read(mobileCommandsProvider);
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => RequestActionSheet(
        config: RequestSheetConfig(
          title: approve ? 'اعتماد تصحيح البصمة' : 'رفض تصحيح البصمة',
          icon: approve ? Icons.check_circle_rounded : Icons.cancel_rounded,
          color: approve ? AppColors.statusSuccess : AppColors.statusDanger,
          explanation: approve
              ? 'يُصحَّح سجل ${correction.employeeName} ليوم ${arDay(correction.workDate)} كما طلب.'
              : 'يبقى سجل اليوم كما هو ويُبلَّغ ${correction.employeeName} بالسبب.',
          inputLabel: approve ? 'ملاحظة (اختياري)' : 'سبب الرفض (إلزامي)',
          required: !approve,
          suggestions: approve
              ? const ['تمت المراجعة والموافقة']
              : const [
                  'لا يوجد ما يثبت الحضور في هذا الوقت',
                  'يُرجى التواصل مع مديرك المباشر',
                ],
          confirmLabel: approve ? 'تأكيد الاعتماد' : 'تأكيد الرفض',
          successMessage: approve
              ? 'تم اعتماد تصحيح البصمة.'
              : 'تم رفض طلب تصحيح البصمة.',
        ),
        subject: 'تصحيح بصمة · ${correction.employeeName}',
        onSubmit: (note) => commands.decideAttendanceCorrection(
          correctionId: correction.id,
          decision: decision,
          note: note.isEmpty ? null : note,
        ),
      ),
    );
    if (done != true || !mounted) return;
    ref.invalidate(teamAttendanceCorrectionsProvider(_correctionStatus));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          approve ? 'تم اعتماد تصحيح البصمة.' : 'تم رفض طلب تصحيح البصمة.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(accessContextProvider).value?.employeeId;
    final teamAsync = ref.watch(mobileTeamProvider);
    final requestsAsync = ref.watch(mobileRequestsProvider);
    final correctionsAsync = ref.watch(
      teamAttendanceCorrectionsProvider(_correctionStatus),
    );

    final teamIds = switch (teamAsync) {
      AsyncData(value: final members) => members.map((m) => m.id).toSet(),
      _ => <String>{},
    };
    final allRequests = requestsAsync.value ?? const <MobileRequest>[];
    final requests = _filtered(allRequests, me, teamIds);
    final corrections = _filteredCorrections(
      correctionsAsync.value ?? const <MobileTeamAttendanceCorrection>[],
    );

    // ملخص ما ينتظر القرار (بغض النظر عن التصفية الحالية)
    final now = DateTime.now();
    final pendingMine = allRequests
        .where(
          (r) =>
              _inScope(r, me, teamIds) &&
              r.status == 'pending' &&
              (r.canDecide ?? true),
        )
        .toList(growable: false);
    final awaiting = pendingMine.where((r) => r.awaitingMe ?? true).length;
    final overdue = pendingMine
        .where((r) => r.effectiveDueAt?.isBefore(now) ?? false)
        .length;
    final pendingCorrections = _statusFilter == 'pending'
        ? (correctionsAsync.value ?? const <MobileTeamAttendanceCorrection>[])
              .where((c) => c.status == 'pending')
              .length
        : 0;

    final loading =
        (requestsAsync.isLoading && !requestsAsync.hasValue) ||
        (correctionsAsync.isLoading && !correctionsAsync.hasValue);
    final total = requests.length + corrections.length;

    // الأحدث أولًا في كل شيء (قرار المالك): التصحيحات والطلبات خط زمني واحد
    // بتاريخ التقديم — لا كتلة تصحيحات (قد تكون قديمة) فوق الطلبات الأحدث.
    final timeline = <({DateTime at, Widget card})>[
      for (final c in corrections) (at: c.createdAt, card: _correctionCard(c)),
      for (final r in requests) (at: r.createdAt, card: _card(r)),
    ]..sort((a, b) => b.at.compareTo(a.at));

    return PermissionGate(
      permission: null,
      anyOf: const [
        'requests.request.approve',
        'requests.request.reject',
        'attendance.correction.review',
        'attendance.manage',
      ],
      child: Scaffold(
        appBar: _selecting
            ? AppBar(
                leading: IconButton(
                  tooltip: 'إلغاء التحديد',
                  onPressed: () => setState(_selected.clear),
                  icon: const Icon(Icons.close_rounded),
                ),
                title: Text('تحديد ${arRequests(_selected.length)}'),
                actions: [
                  TextButton(
                    onPressed: () => setState(
                      () => _selected.addAll(
                        requests.where(_selectable).map((r) => r.id),
                      ),
                    ),
                    child: const Text('تحديد الكل'),
                  ),
                ],
              )
            : AppBar(
                title: const Text('اعتماد طلبات الفريق'),
                actions: [
                  IconButton(
                    tooltip: 'تفويض الاعتماد',
                    icon: const Icon(Icons.swap_horiz_rounded),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ApprovalDelegationsPage(),
                      ),
                    ),
                  ),
                  if (_statusFilter == 'pending' &&
                      requests.where(_selectable).length > 1)
                    TextButton.icon(
                      onPressed: () => setState(
                        () => _selected.add(
                          requests.firstWhere(_selectable).id,
                        ),
                      ),
                      icon: const Icon(Icons.checklist_rounded, size: 20),
                      label: const Text('اعتماد جماعي'),
                    ),
                ],
              ),
        bottomNavigationBar: _selecting
            ? Material(
                elevation: 8,
                color: Theme.of(context).colorScheme.surface,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.statusSuccess,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(50),
                      ),
                      onPressed: () => _bulkApprove(requests),
                      icon: const Icon(Icons.done_all_rounded),
                      label: Text('اعتماد ${arRequests(_selected.length)}'),
                    ),
                  ),
                ),
              )
            : null,
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(mobileRequestsProvider);
              ref.invalidate(teamAttendanceCorrectionsProvider(_correctionStatus));
              ref.invalidate(mobileTeamProvider);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
              children: [
                _SummaryCard(
                  awaiting: awaiting,
                  canDecideOther: pendingMine.length - awaiting,
                  overdue: overdue,
                  corrections: pendingCorrections,
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _Category.values.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (context, i) {
                      final c = _Category.values[i];
                      return ChoiceChip(
                        avatar: c.icon == null ? null : Icon(c.icon, size: 16),
                        label: Text(c.label),
                        selected: _category == c,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _category = c),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                MobileFilterBar(
                  searchHint: 'بحث بالاسم أو الإدارة أو رقم الطلب',
                  controller: _search,
                  onSearchChanged: (v) => setState(() => _query = v),
                  options: const [
                    MobileFilterOption('pending', 'بانتظار القرار'),
                    MobileFilterOption('approved', 'معتمدة'),
                    MobileFilterOption('closed', 'مرفوضة ومسحوبة'),
                    MobileFilterOption('all', 'الكل'),
                  ],
                  selected: _statusFilter,
                  onSelected: (v) => setState(() => _statusFilter = v),
                  resultLabel: total == 0 ? 'لا نتائج' : arRequests(total),
                ),
                const SizedBox(height: 10),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (requestsAsync.hasError && !requestsAsync.hasValue)
                  _EmptyState(
                    icon: Icons.cloud_off_rounded,
                    text: humanizeError(requestsAsync.error!),
                    onRetry: () => ref.invalidate(mobileRequestsProvider),
                  )
                else if (total == 0)
                  _EmptyState(
                    icon: _statusFilter == 'pending'
                        ? Icons.task_alt_rounded
                        : Icons.search_off_rounded,
                    text: _statusFilter == 'pending'
                        ? 'لا توجد طلبات بانتظار قرارك الآن.'
                        : 'لا توجد طلبات مطابقة.',
                  )
                else
                  ...(_statusFilter == 'pending'
                      ? timeline.map((e) => e.card)
                      : withRequestGroupHeaders<({DateTime at, Widget card})>(
                          timeline,
                          (e) => e.at,
                          (e) => e.card,
                        )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.awaiting,
    required this.canDecideOther,
    required this.overdue,
    required this.corrections,
  });

  final int awaiting;
  final int canDecideOther;
  final int overdue;
  final int corrections;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nothing = awaiting + canDecideOther + corrections == 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            AppColors.brandPrimary.withValues(alpha: .10),
            AppColors.accent.withValues(alpha: .05),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.brandPrimary.withValues(alpha: .15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.approval_rounded, color: AppColors.brandPrimary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  nothing
                      ? 'لا شيء ينتظر قرارك الآن'
                      : awaiting > 0
                      ? '${arRequests(awaiting)} بانتظار قرارك'
                      : 'طلبات في نطاقك يمكنك البت فيها',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15.5,
                  ),
                ),
              ),
            ],
          ),
          if (!nothing) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (overdue > 0)
                  RequestMetaChip(
                    icon: Icons.warning_amber_rounded,
                    text: 'متأخرة: ${arRequests(overdue)}',
                    color: AppColors.statusDanger,
                    strong: true,
                  ),
                if (canDecideOther > 0)
                  RequestMetaChip(
                    icon: Icons.verified_user_outlined,
                    text: 'عند مرحلة أخرى ويمكنك البت فيها: $canDecideOther',
                    color: AppColors.statusInfo,
                  ),
                if (corrections > 0)
                  RequestMetaChip(
                    icon: Icons.fingerprint_rounded,
                    text: 'تصحيحات بصمة: $corrections',
                    color: AppColors.statusViolet,
                  ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 4),
            Text(
              'ستظهر هنا طلبات فريقك فور تقديمها.',
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.text, this.onRetry});

  final IconData icon;
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 16),
      child: Column(
        children: [
          Icon(icon, size: 46, color: scheme.onSurfaceVariant.withValues(alpha: .6)),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 10),
            OutlinedButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
          ],
        ],
      ),
    );
  }
}

/// بطاقة طلب للمعتمِد: من؟ ماذا؟ متى؟ أين يقف؟ مع قرار سريع.
class _TeamRequestCard extends StatelessWidget {
  const _TeamRequestCard({
    required this.request,
    required this.onTap,
    required this.onApprove,
    required this.onReject,
    this.onLongPress,
    this.selecting = false,
    this.selected = false,
  });

  final MobileRequest request;
  final VoidCallback onTap;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final VoidCallback? onLongPress;
  final bool selecting;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = request;
    final typeColor = requestTypeColor(r.type);
    final typeLabel = requestTypeLabel(r.type);
    final title = r.title?.trim();
    final brief = requestBriefLine(r.type, r.payload);
    final subtitle = [
      if (r.employeeJobTitle?.trim().isNotEmpty == true) r.employeeJobTitle!.trim(),
      if (r.employeeDepartment?.trim().isNotEmpty == true) r.employeeDepartment!.trim(),
    ].join(' · ');
    final pending = r.status == 'pending';
    final due = pending ? requestDueStatus(r.effectiveDueAt) : null;
    final stage = pending && r.activeStepName != null
        ? requestStageName(r.activeStepName, roleSlug: r.activeStepRole)
        : null;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected
              ? AppColors.statusSuccess
              : r.awaitingMe == true
              ? AppColors.statusInfo.withValues(alpha: .45)
              : (due?.overdue ?? false)
              ? AppColors.statusDanger.withValues(alpha: .35)
              : scheme.outlineVariant.withValues(alpha: .6),
          width: selected || r.awaitingMe == true ? 1.4 : 1,
        ),
      ),
      color: selected ? AppColors.statusSuccess.withValues(alpha: .06) : null,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (selecting) ...[
                    Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: selected
                          ? AppColors.statusSuccess
                          : scheme.outline,
                    ),
                    const SizedBox(width: 8),
                  ],
                  AppAvatar(
                    name: r.employeeName,
                    photoUrl: r.employeePhotoUrl,
                    radius: 21,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.employeeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5,
                          ),
                        ),
                        if (subtitle.isNotEmpty)
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  RequestStatusChip(r.status, dense: true),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(requestTypeIcon(r.type), size: 14, color: typeColor),
                        const SizedBox(width: 4),
                        Text(
                          typeLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: typeColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'رقم ${r.number}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    arAgo(r.createdAt),
                    style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
              if (title != null && title.isNotEmpty && title != typeLabel) ...[
                const SizedBox(height: 8),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ],
              if (brief.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  brief,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface.withValues(alpha: .8),
                  ),
                ),
              ],
              if (r.reason?.trim().isNotEmpty == true &&
                  r.reason!.trim() != title) ...[
                const SizedBox(height: 4),
                Text(
                  r.reason!.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (r.awaitingMe == true)
                    const RequestMetaChip(
                      icon: Icons.notifications_active_rounded,
                      text: 'دورك الآن',
                      color: AppColors.statusInfo,
                      strong: true,
                    ),
                  if (stage != null && r.awaitingMe != true)
                    RequestMetaChip(icon: Icons.route_rounded, text: 'عند $stage'),
                  if (due != null)
                    RequestMetaChip(
                      icon: due.overdue
                          ? Icons.warning_amber_rounded
                          : Icons.schedule_rounded,
                      text: due.label,
                      color: due.overdue ? AppColors.statusDanger : null,
                      strong: due.overdue,
                    ),
                  if (!pending && r.decidedAt != null)
                    RequestMetaChip(
                      icon: requestStatusStyle(r.status).icon,
                      text: [
                        if (r.decidedByName != null) r.decidedByName!,
                        arDateTime(r.decidedAt!),
                      ].join(' · '),
                      color: requestStatusStyle(r.status).color,
                    ),
                ],
              ),
              if (onApprove != null || onReject != null) ...[
                const Divider(height: 20),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.statusSuccess,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(42),
                        ),
                        onPressed: onApprove,
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('اعتماد'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.statusDanger,
                          side: BorderSide(
                            color: AppColors.statusDanger.withValues(alpha: .5),
                          ),
                          minimumSize: const Size.fromHeight(42),
                        ),
                        onPressed: onReject,
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: const Text('رفض'),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'التفاصيل والإرجاع للتعديل',
                      onPressed: onTap,
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// اعتماد جماعي: مراجعة المحدد، ملاحظة واحدة اختيارية، ثم تنفيذ متتابع مع
/// إظهار نتيجة كل طلب (الخادم يتحقق من صلاحية كل قرار على حدة).
class _BulkApproveSheet extends ConsumerStatefulWidget {
  const _BulkApproveSheet({required this.requests});

  final List<MobileRequest> requests;

  @override
  ConsumerState<_BulkApproveSheet> createState() => _BulkApproveSheetState();
}

class _BulkApproveSheetState extends ConsumerState<_BulkApproveSheet> {
  final _note = TextEditingController();
  final _results = <String, String?>{}; // id → null نجاح / رسالة خطأ
  bool _running = false;
  bool get _done => _results.length == widget.requests.length;
  int get _okCount => _results.values.where((e) => e == null).length;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() => _running = true);
    final commands = ref.read(mobileCommandsProvider);
    final note = _note.text.trim();
    for (final r in widget.requests) {
      if (!mounted) return;
      try {
        await commands.decideRequest(r.id, 'approve', note.isEmpty ? null : note);
        _results[r.id] = null;
      } catch (error) {
        _results[r.id] = requestErrorMessage(error) ?? humanizeError(error);
      }
      if (mounted) setState(() {});
    }
    if (mounted) setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.statusSuccess.withValues(alpha: .12),
                  child: const Icon(Icons.done_all_rounded, color: AppColors.statusSuccess),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _done
                        ? 'اكتمل الاعتماد الجماعي'
                        : 'اعتماد ${arRequests(widget.requests.length)} دفعة واحدة',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final r in widget.requests)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      !_results.containsKey(r.id)
                          ? requestTypeIcon(r.type)
                          : _results[r.id] == null
                          ? Icons.check_circle_rounded
                          : Icons.error_rounded,
                      size: 20,
                      color: !_results.containsKey(r.id)
                          ? requestTypeColor(r.type)
                          : _results[r.id] == null
                          ? AppColors.statusSuccess
                          : AppColors.statusDanger,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${requestTypeLabel(r.type)} · ${r.employeeName}',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                          ),
                          Text(
                            _results[r.id] ?? requestBriefLine(r.type, r.payload),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: _results[r.id] != null
                                  ? AppColors.statusDanger
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            if (!_done) ...[
              TextField(
                controller: _note,
                enabled: !_running,
                maxLines: 2,
                maxLength: 300,
                decoration: InputDecoration(
                  labelText: 'ملاحظة تصل للجميع (اختياري)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(
                    onPressed: _running ? null : () => Navigator.of(context).pop(0),
                    child: const Text('رجوع'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.statusSuccess,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: _running ? null : _run,
                      icon: _running
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.done_all_rounded),
                      label: Text(
                        _running
                            ? 'جارٍ الاعتماد ${_results.length + 1} من ${widget.requests.length}…'
                            : 'تأكيد اعتماد الكل',
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Text(
                _okCount == widget.requests.length
                    ? 'اعتُمدت كلها بنجاح وأُبلغ أصحابها.'
                    : 'اعتُمد $_okCount من ${widget.requests.length} — راجع سبب تعذّر الباقي أعلاه.',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () => Navigator.of(context).pop(_okCount),
                child: const Text('تم'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// بطاقة تصحيح البصمة للمدير.
class _CorrectionCard extends StatelessWidget {
  const _CorrectionCard({
    required this.correction,
    required this.onTap,
    required this.onApprove,
    required this.onReject,
  });

  final MobileTeamAttendanceCorrection correction;
  final VoidCallback onTap;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  String get _typeLabel => switch (correction.type) {
    'missing_check_in' => 'نسيان بصمة الحضور',
    'missing_check_out' => 'نسيان بصمة الانصراف',
    'wrong_time' => 'تعديل توقيت البصمة',
    'wrong_status' => 'تعديل حالة اليوم',
    'mission' => 'مأمورية عمل',
    'leave' => 'إجازة',
    _ => 'تصحيح بصمة',
  };

  IconData get _typeIcon => switch (correction.type) {
    'missing_check_in' => Icons.login_rounded,
    'missing_check_out' => Icons.logout_rounded,
    'wrong_time' => Icons.access_time_rounded,
    _ => Icons.fingerprint_rounded,
  };

  String _time(DateTime? dt) =>
      dt == null ? '' : DateFormat('h:mm a', 'ar').format(dt.toLocal());

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const color = Color(0xFF4F46E5);
    final isPending = correction.status == 'pending';
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .6)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AppAvatar(
                    name: correction.employeeName,
                    photoUrl: correction.employeePhotoUrl,
                    radius: 21,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          correction.employeeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5,
                          ),
                        ),
                        if (correction.jobTitle?.trim().isNotEmpty == true)
                          Text(
                            correction.jobTitle!.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  RequestStatusChip(correction.status, dense: true),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  RequestMetaChip(icon: _typeIcon, text: _typeLabel, color: color),
                  RequestMetaChip(
                    icon: Icons.today_rounded,
                    text: arDay(correction.workDate),
                  ),
                  if (correction.requestedCheckIn != null)
                    RequestMetaChip(
                      icon: Icons.login_rounded,
                      text: 'حضور ${_time(correction.requestedCheckIn)}',
                      color: AppColors.statusSuccess,
                    ),
                  if (correction.requestedCheckOut != null)
                    RequestMetaChip(
                      icon: Icons.logout_rounded,
                      text: 'انصراف ${_time(correction.requestedCheckOut)}',
                      color: AppColors.statusDanger,
                    ),
                ],
              ),
              if (correction.reason.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  correction.reason.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (isPending && (onApprove != null || onReject != null)) ...[
                const Divider(height: 20),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.statusSuccess,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(42),
                        ),
                        onPressed: onApprove,
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('اعتماد'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.statusDanger,
                          side: BorderSide(
                            color: AppColors.statusDanger.withValues(alpha: .5),
                          ),
                          minimumSize: const Size.fromHeight(42),
                        ),
                        onPressed: onReject,
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: const Text('رفض'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
