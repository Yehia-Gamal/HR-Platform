import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/attendance_correction_detail_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_request_detail_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:ahla_shabab_management_os/shared/permission_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// اعتماد طلبات وتصحيحات بصمة الفريق — يشمل طلبات الإجازات والمأموريات وتصحيحات بصمة الحضور والانصراف.
class TeamRequestsPage extends ConsumerStatefulWidget {
  const TeamRequestsPage({super.key});

  @override
  ConsumerState<TeamRequestsPage> createState() => _TeamRequestsPageState();
}

class _TeamRequestsPageState extends ConsumerState<TeamRequestsPage> {
  final _search = TextEditingController();
  String _query = '';
  String _statusFilter = 'pending';
  String _categoryFilter = 'all'; // all, corrections, leaves, missions, excuses

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<MobileRequest> _filterRequests(
    List<MobileRequest> requests,
    Set<String> teamIds,
  ) {
    var result = requests
        .where((r) => r.employeeId != null && teamIds.contains(r.employeeId))
        .toList(growable: false);

    // فلترة حسب الفئة
    result = switch (_categoryFilter) {
      'leaves' => result.where((r) => r.type == 'leave').toList(growable: false),
      'missions' => result
          .where((r) => r.type == 'mission' || r.type == 'convoy' || r.type == 'fundraising')
          .toList(growable: false),
      'excuses' => result
          .where((r) => r.type == 'excuse' || r.type == 'late_permit' || r.type == 'early_permit')
          .toList(growable: false),
      'corrections' => <MobileRequest>[], // لا توجد طلبات عادية في تصحيحات البصمة
      _ => result,
    };

    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      result = result
          .where(
            (r) =>
                r.employeeName.toLowerCase().contains(q) ||
                (r.title?.toLowerCase().contains(q) ?? false) ||
                (r.reason?.toLowerCase().contains(q) ?? false),
          )
          .toList(growable: false);
    }
    return switch (_statusFilter) {
      'pending' =>
        result.where((r) => r.status == 'pending').toList(growable: false),
      'approved' =>
        result
            .where(
              (r) =>
                  r.status == 'approved' ||
                  r.status == 'completed' ||
                  r.status == 'escalated',
            )
            .toList(growable: false),
      'closed' =>
        result
            .where(
              (r) =>
                  r.status == 'rejected' ||
                  r.status == 'returned' ||
                  r.status == 'cancelled',
            )
            .toList(growable: false),
      _ => result,
    };
  }

  List<MobileTeamAttendanceCorrection> _filterCorrections(
    List<MobileTeamAttendanceCorrection> corrections,
  ) {
    // إذا كانت الفئة مختارة لغير تصحيحات البصمة، لا نعرض تصحيحات
    if (_categoryFilter == 'leaves' ||
        _categoryFilter == 'missions' ||
        _categoryFilter == 'excuses') {
      return const <MobileTeamAttendanceCorrection>[];
    }

    var result = corrections;
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      result = result
          .where(
            (c) =>
                c.employeeName.toLowerCase().contains(q) ||
                (c.employeeCode.toLowerCase().contains(q)) ||
                (c.jobTitle?.toLowerCase().contains(q) ?? false) ||
                c.reason.toLowerCase().contains(q) ||
                DateFormat('yyyy-MM-dd').format(c.workDate).contains(q),
          )
          .toList(growable: false);
    }
    return result;
  }

  Future<void> _openRequestDetail(MobileRequest request) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MobileRequestDetailPage(requestId: request.id),
      ),
    );
    if (mounted) {
      ref.invalidate(mobileRequestsProvider);
      ref.invalidate(mobileTeamProvider);
    }
  }

  Future<void> _openCorrectionDetail(
    MobileTeamAttendanceCorrection correction,
  ) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AttendanceCorrectionDetailPage(
          correctionId: correction.id,
        ),
      ),
    );
    if (mounted) {
      ref.invalidate(teamAttendanceCorrectionsProvider(_statusFilter));
      ref.invalidate(mobileTeamProvider);
    }
  }

  Future<void> _decideRequest(MobileRequest request, String decision) async {
    final controller = TextEditingController();
    String? errorText;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDlgState) => AlertDialog(
          title: Text(decision == 'approve' ? 'اعتماد الطلب' : 'رفض الطلب'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: decision == 'approve'
                  ? 'ملاحظة اختيارية'
                  : 'سبب الرفض (إلزامي)',
              errorText: errorText,
              border: const OutlineInputBorder(),
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
                  setDlgState(
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
    if (confirmed != true || !mounted) return;

    try {
      await ref
          .read(mobileCommandsProvider)
          .decideRequest(request.id, decision, comment);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              decision == 'approve'
                  ? 'تم اعتماد الطلب بنجاح.'
                  : 'تم رفض الطلب.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(humanizeError(error))));
      }
    }
  }

  Future<void> _decideCorrection(
    MobileTeamAttendanceCorrection correction,
    String decision,
  ) async {
    final controller = TextEditingController();
    String? errorText;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDlgState) => AlertDialog(
          title: Text(
            decision == 'approved' ? 'اعتماد تصحيح البصمة' : 'رفض تصحيح البصمة',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                decision == 'approved'
                    ? 'هل تؤكد اعتماد تصحيح البصمة للموظف ${correction.employeeName}؟'
                    : 'يرجى كتابة سبب رفض تصحيح البصمة للموظف ${correction.employeeName}:',
                style: const TextStyle(fontSize: 13.5),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: decision == 'approved'
                      ? 'ملاحظة اختيارية'
                      : 'سبب الرفض (إلزامي)',
                  errorText: errorText,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: decision == 'approved'
                    ? const Color(0xFF0F9F6E)
                    : Theme.of(context).colorScheme.error,
              ),
              onPressed: () {
                if (decision != 'approved' &&
                    controller.text.trim().length < 3) {
                  setDlgState(
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
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(mobileCommandsProvider).decideAttendanceCorrection(
            correctionId: correction.id,
            decision: decision,
            note: comment.isNotEmpty ? comment : null,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              decision == 'approved'
                  ? 'تم اعتماد تصحيح البصمة بنجاح.'
                  : 'تم رفض طلب تصحيح البصمة.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(humanizeError(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final teamAsync = ref.watch(mobileTeamProvider);
    final requestsAsync = ref.watch(mobileRequestsProvider);
    final correctionsAsync =
        ref.watch(teamAttendanceCorrectionsProvider(_statusFilter));

    final teamIds = switch (teamAsync) {
      AsyncData(value: final members) => members.map((m) => m.id).toSet(),
      _ => <String>{},
    };

    final filteredRequests = switch (requestsAsync) {
      AsyncData(value: final requests) => _filterRequests(requests, teamIds),
      _ => <MobileRequest>[],
    };

    final filteredCorrections = switch (correctionsAsync) {
      AsyncData(value: final corrections) => _filterCorrections(corrections),
      _ => <MobileTeamAttendanceCorrection>[],
    };

    final totalCount = filteredRequests.length + filteredCorrections.length;

    // حساب المعلق
    final pendingRequestsCount = switch (requestsAsync) {
      AsyncData(value: final requests) => _filterRequests(
        requests,
        teamIds,
      ).where((r) => r.status == 'pending').length,
      _ => 0,
    };
    final pendingCorrectionsCount = switch (correctionsAsync) {
      AsyncData(value: final corrections) =>
        corrections.where((c) => c.status == 'pending').length,
      _ => 0,
    };
    final totalPendingCount =
        pendingRequestsCount + pendingCorrectionsCount;

    return PermissionGate(
      permission: null,
      anyOf: const [
        'requests.request.approve',
        'requests.request.reject',
        'attendance.correction.review',
        'attendance.manage',
      ],
      child: Scaffold(
        appBar: AppBar(title: const Text('اعتماد طلبات الفريق')),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(mobileRequestsProvider);
              ref.invalidate(teamAttendanceCorrectionsProvider(_statusFilter));
              ref.invalidate(mobileTeamProvider);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
              children: [
                const MobileSectionHeader(
                  title: 'اعتماد طلبات وتصحيحات الفريق',
                  subtitle:
                      'طلبات الإجازات، المأموريات، وتصحيحات بصمة الحضور والانصراف.',
                ),
                const SizedBox(height: 8),

                // شريط تبويبات الفئات
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _CategoryChip(
                        label: 'الكل',
                        selected: _categoryFilter == 'all',
                        onTap: () => setState(() => _categoryFilter = 'all'),
                      ),
                      const SizedBox(width: 6),
                      _CategoryChip(
                        label: 'تصحيحات البصمة',
                        icon: Icons.fingerprint_rounded,
                        selected: _categoryFilter == 'corrections',
                        onTap: () =>
                            setState(() => _categoryFilter = 'corrections'),
                      ),
                      const SizedBox(width: 6),
                      _CategoryChip(
                        label: 'الإجازات',
                        icon: Icons.beach_access_rounded,
                        selected: _categoryFilter == 'leaves',
                        onTap: () => setState(() => _categoryFilter = 'leaves'),
                      ),
                      const SizedBox(width: 6),
                      _CategoryChip(
                        label: 'المأموريات',
                        icon: Icons.near_me_rounded,
                        selected: _categoryFilter == 'missions',
                        onTap: () =>
                            setState(() => _categoryFilter = 'missions'),
                      ),
                      const SizedBox(width: 6),
                      _CategoryChip(
                        label: 'الأذونات',
                        icon: Icons.schedule_rounded,
                        selected: _categoryFilter == 'excuses',
                        onTap: () =>
                            setState(() => _categoryFilter = 'excuses'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // شريط تصفية الحالة والبحث
                MobileFilterBar(
                  searchHint: 'بحث بالاسم، التاريخ، أو السبب',
                  controller: _search,
                  onSearchChanged: (v) => setState(() => _query = v),
                  options: const [
                    MobileFilterOption('pending', 'معلّقة'),
                    MobileFilterOption('approved', 'معتمدة'),
                    MobileFilterOption('closed', 'مرفوضة/ملغاة'),
                    MobileFilterOption('all', 'الكل'),
                  ],
                  selected: _statusFilter,
                  onSelected: (v) => setState(() => _statusFilter = v),
                  resultLabel: totalCount == 0 ? 'لا نتائج' : '$totalCount طلب',
                ),

                if (totalPendingCount > 0 && _statusFilter == 'pending') ...[
                  const SizedBox(height: 8),
                  _PendingBanner(count: totalPendingCount),
                ],
                const SizedBox(height: 10),

                // حالة التحميل
                if (requestsAsync.isLoading || correctionsAsync.isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (totalCount == 0)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: Text(
                        'لا توجد طلبات أو تصحيحات بصمة مطابقة',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  )
                else ...[
                  // أولاً: تصحيحات البصمة
                  if (filteredCorrections.isNotEmpty) ...[
                    if (_categoryFilter == 'all')
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6, top: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.fingerprint_rounded,
                              size: 16,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'تصحيحات البصمة (${filteredCorrections.length})',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ...filteredCorrections.map(
                      (correction) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _AttendanceCorrectionCard(
                          correction: correction,
                          onTap: () => _openCorrectionDetail(correction),
                          onApprove: correction.status == 'pending' &&
                                  correction.canDecide
                              ? () => _decideCorrection(correction, 'approved')
                              : null,
                          onReject: correction.status == 'pending' &&
                                  correction.canDecide
                              ? () => _decideCorrection(correction, 'rejected')
                              : null,
                        ),
                      ),
                    ),
                  ],

                  // ثانياً: طلبات الفريق (إجازات ومأموريات وأذونات)
                  if (filteredRequests.isNotEmpty) ...[
                    if (_categoryFilter == 'all' &&
                        filteredCorrections.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6, top: 8),
                        child: Row(
                          children: [
                            Icon(
                              Icons.rule_rounded,
                              size: 16,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'طلبات الإجازات والتكليفات (${filteredRequests.length})',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ...filteredRequests.map(
                      (request) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _RequestCard(
                          request: request,
                          onTap: () => _openRequestDetail(request),
                          onApprove: request.status == 'pending'
                              ? () => _decideRequest(request, 'approve')
                              : null,
                          onReject: request.status == 'pending'
                              ? () => _decideRequest(request, 'reject')
                              : null,
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primary : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 14,
                  color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingBanner extends StatelessWidget {
  const _PendingBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.pending_actions_rounded, color: scheme.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$count طلب وتصحيح بصمة بانتظار قرارك.',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// بطاقة تصحيح البصمة — رشيقة ومصممة بعناية للمدير
class _AttendanceCorrectionCard extends StatelessWidget {
  const _AttendanceCorrectionCard({
    required this.correction,
    required this.onTap,
    required this.onApprove,
    required this.onReject,
  });

  final MobileTeamAttendanceCorrection correction;
  final VoidCallback onTap;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  String _typeLabel(String type) => switch (type) {
    'missing_check_in' => 'نسيان بصمة حضور (دخول)',
    'missing_check_out' => 'نسيان بصمة انصراف (خروج)',
    'wrong_time' => 'تعديل توقيت البصمة',
    'wrong_status' => 'تعديل حالة الدوام',
    'mission' => 'مأمورية عمل',
    'leave' => 'إجازة',
    _ => 'تصحيح بصمة',
  };

  IconData _typeIcon(String type) => switch (type) {
    'missing_check_in' => Icons.login_rounded,
    'missing_check_out' => Icons.logout_rounded,
    'wrong_time' => Icons.access_time_rounded,
    _ => Icons.fingerprint_rounded,
  };

  String _formatTime(DateTime? dt) {
    if (dt == null) return '';
    return DateFormat('hh:mm a', 'ar').format(dt.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isPending = correction.status == 'pending';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // رأس البطاقة: صورة الموظف والاسم والمنصب
              Row(
                children: [
                  AppAvatar(
                    name: correction.employeeName,
                    radius: 20,
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
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          [
                            if (correction.jobTitle?.isNotEmpty ?? false)
                              correction.jobTitle,
                            if (correction.employeeCode.isNotEmpty)
                              '#${correction.employeeCode}',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  MobileStatusPill(correction.status),
                ],
              ),
              const SizedBox(height: 8),

              // نوع التصحيح والتاريخ
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _typeIcon(correction.type),
                          size: 13,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _typeLabel(correction.type),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: scheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    DateFormat('d MMM y', 'ar').format(correction.workDate),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),

              // الأوقات المطلوبة (إن وجدت)
              if (correction.requestedCheckIn != null ||
                  correction.requestedCheckOut != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (correction.requestedCheckIn != null) ...[
                      const Icon(
                        Icons.login_rounded,
                        size: 13,
                        color: Color(0xFF0F9F6E),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'حضور: ${_formatTime(correction.requestedCheckIn)}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0F9F6E),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    if (correction.requestedCheckOut != null) ...[
                      Icon(Icons.logout_rounded, size: 13, color: scheme.error),
                      const SizedBox(width: 3),
                      Text(
                        'انصراف: ${_formatTime(correction.requestedCheckOut)}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: scheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ],

              // سبب التصحيح
              if (correction.reason.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  correction.reason,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],

              // أزرار اتخاذ القرار السريع (إذا كان معلّقاً)
              if (isPending && (onApprove != null || onReject != null)) ...[
                const Divider(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0F9F6E),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        onPressed: onApprove,
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('اعتماد'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: scheme.error,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        onPressed: onReject,
                        icon: const Icon(Icons.close, size: 16),
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

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.onTap,
    required this.onApprove,
    required this.onReject,
  });

  final MobileRequest request;
  final VoidCallback onTap;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formatter = DateFormat('d MMM y', 'ar');
    final isPending = request.status == 'pending';
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AppAvatar(
                    name: request.employeeName,
                    photoUrl: request.employeePhotoUrl,
                    radius: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          request.employeeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${_typeLabel(request.type)} · #${request.number}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  MobileStatusPill(request.status),
                ],
              ),
              if (request.title?.isNotEmpty ?? false) ...[
                const SizedBox(height: 10),
                Text(
                  request.title!,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
              if (request.reason?.isNotEmpty ?? false) ...[
                const SizedBox(height: 4),
                Text(
                  request.reason!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _metaChip(
                    theme,
                    icon: Icons.rule_rounded,
                    text: request.activeStepName ?? 'قيد الاعتماد',
                  ),
                  _metaChip(
                    theme,
                    icon: Icons.calendar_today_outlined,
                    text: formatter.format(request.createdAt),
                  ),
                ],
              ),
              if (isPending && (onApprove != null || onReject != null)) ...[
                const Divider(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onApprove,
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('اعتماد'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onReject,
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('رفض'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                        ),
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

  Widget _metaChip(
    ThemeData theme, {
    required IconData icon,
    required String text,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 3),
        Text(
          text,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );

  static String _typeLabel(String type) => switch (type) {
    'leave' => 'طلب إجازة',
    'mission' => 'مأمورية',
    'convoy' => 'قافلة',
    'fundraising' => 'فاندي',
    'late_permit' => 'تصريح تأخير',
    'early_permit' => 'تصريح انصراف مبكر',
    'excuse' => 'إذن',
    'overtime' => 'عمل إضافي',
    'schedule_change' => 'تعديل جدول',
    'location' => 'موقع فوري',
    _ => type,
  };
}
