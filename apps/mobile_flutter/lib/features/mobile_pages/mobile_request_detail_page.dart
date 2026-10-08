import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/core/formatting/arabic_text.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/employee_profile_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_self_service_page.dart'
    show NewRequestSheet;
import 'package:ahla_shabab_management_os/features/mobile_pages/request_decision_sheet.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/request_display.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// تفاصيل الطلب: الحالة وصاحب الطلب، بيانات الطلب وسببه، تنفيذ المأمورية،
/// مسار الاعتماد وسجله، وقرار المعتمِد أو إجراءات صاحب الطلب.
class MobileRequestDetailPage extends ConsumerWidget {
  const MobileRequestDetailPage({
    required this.requestId,
    this.initialAction,
    super.key,
  });

  final String requestId;

  /// من أزرار إشعار القرار (approve/reject) — يفتح ورقة القرار جاهزة
  /// بعد تحميل الطلب، بشرط أن يكون المستخدم مخوّلاً للقرار.
  final String? initialAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(mobileRequestDetailProvider(requestId));
    return detail.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('تفاصيل الطلب')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('تفاصيل الطلب')),
        body: _ErrorState(
          message: requestErrorMessage(error) ?? humanizeError(error),
          onRetry: () => ref.invalidate(mobileRequestDetailProvider(requestId)),
        ),
      ),
      data: (request) =>
          _RequestScreen(request: request, initialAction: initialAction),
    );
  }
}

/// حارس تكرار الفتح التلقائي لورقة القرار — مرة واحدة لكل طلب لكل تشغيل.
final _autoDecisionOpened = <String>{};

class _RequestScreen extends ConsumerWidget {
  const _RequestScreen({required this.request, this.initialAction});

  final MobileRequestDetail request;
  final String? initialAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(accessContextProvider).value;
    final isClinicStaff = access?.isClinicStaff == true;
    final myEmployeeId = access?.employeeId;
    final isMine = request.isMineFor(myEmployeeId);
    final canDecide =
        !isClinicStaff &&
        request.canDecide &&
        request.status == 'pending' &&
        !isMine;

    // فتح تلقائي لورقة القرار عند القدوم من زر إشعار — مرة واحدة،
    // وبشرط أن يكون المستخدم مخوّلاً والطلب ما زال معلقاً.
    final auto = switch (initialAction) {
      'approve' => 'approve',
      'reject' => 'reject',
      _ => null,
    };
    if (auto != null && canDecide && _autoDecisionOpened.add(request.id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) _openDecision(context, ref, request, auto);
      });
    }

    final current = currentStepIndex(request.steps, request.status);
    final currentStage = current >= 0
        ? requestStageName(
            request.steps[current].name,
            roleSlug: request.steps[current].roleSlug,
            order: request.steps[current].order,
          )
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('تفاصيل الطلب')),
      bottomNavigationBar: canDecide
          ? _DecisionBar(
              request: request,
              awaitingMe: request.awaitingMe ?? true,
              currentStage: currentStage,
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.invalidate(mobileRequestDetailProvider(request.id)),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            _HeroCard(
              request: request,
              isMine: isMine,
              canDecide: canDecide,
              currentStage: currentStage,
            ),
            const SizedBox(height: 12),
            _DetailsCard(request: request),
            if (!isMine && _DecisionContextCard.hasContent(request)) ...[
              const SizedBox(height: 12),
              _DecisionContextCard(request: request),
            ] else if (request.substituteName != null ||
                request.conflicts.isNotEmpty) ...[
              const SizedBox(height: 12),
              _ContextCard(request: request),
            ],
            if (isFieldAssignmentType(request.type)) ...[
              const SizedBox(height: 12),
              _MissionExecutionCard(request: request, isOwner: isMine),
            ],
            const SizedBox(height: 12),
            _JourneyCard(request: request),
            if (isMine && request.canCancel && request.status == 'pending') ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.statusDanger,
                  side: BorderSide(
                    color: AppColors.statusDanger.withValues(alpha: .5),
                  ),
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () => _openWithdraw(context, ref, request),
                icon: const Icon(Icons.undo_rounded),
                label: const Text('سحب الطلب قبل صدور القرار'),
              ),
            ],
            // 0452: صاحب الطلب يعدّل الطلب المرفوض/المُعاد ويعيد رفعه
            if (isMine &&
                request.canResubmit &&
                (request.status == 'rejected' ||
                    request.status == 'returned')) ...[
              const SizedBox(height: 14),
              _ResubmitBanner(returned: request.status == 'returned'),
              const SizedBox(height: 10),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                onPressed: () => _resubmit(context, ref, request),
                icon: const Icon(Icons.edit_note_rounded),
                label: const Text('تعديل الطلب وإعادة رفعه'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// الإجراءات: القرار، السحب، إعادة الرفع، فتح المرفق
// ═══════════════════════════════════════════════════════════════════════════

Future<void> _openDecision(
  BuildContext context,
  WidgetRef ref,
  MobileRequestDetail request,
  String decision,
) async {
  final done = await showRequestDecisionSheet(
    context,
    ref,
    requestId: request.id,
    number: request.number,
    type: request.type,
    employeeName: request.employeeName,
    decision: decision,
  );
  if (done) ref.invalidate(mobileRequestDetailProvider(request.id));
}

Future<void> _openWithdraw(
  BuildContext context,
  WidgetRef ref,
  MobileRequestDetail request,
) async {
  final done = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => RequestActionSheet(
      config: const RequestSheetConfig(
        title: 'سحب الطلب',
        icon: Icons.undo_rounded,
        color: AppColors.statusDanger,
        explanation:
            'يتوقف مسار الاعتماد ولا يصل الطلب للمعتمدين. يمكنك تقديم طلب جديد لاحقًا.',
        inputLabel: 'سبب السحب (إلزامي)',
        required: true,
        suggestions: [
          'لم أعد بحاجة إلى الطلب',
          'قُدِّم بالخطأ',
          'سأقدّم طلبًا آخر ببيانات صحيحة',
        ],
        confirmLabel: 'تأكيد السحب',
        successMessage: 'تم سحب الطلب وإيقاف مسار الاعتماد.',
      ),
      subject: '${requestTypeLabel(request.type)} · طلب رقم ${request.number}',
      onSubmit: (note) =>
          ref.read(mobileCommandsProvider).cancelRequest(request.id, note),
    ),
  );
  if (done != true || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('تم سحب الطلب وإيقاف مسار الاعتماد.')),
  );
}

/// 0452: فتح نموذج التعديل معبّأً بالقيم الحالية ثم إعادة الرفع.
Future<void> _resubmit(
  BuildContext context,
  WidgetRef ref,
  MobileRequestDetail request,
) async {
  final result = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => NewRequestSheet(
      type: request.type,
      permitKind: request.payload['permitKind']?.toString(),
      initial: {
        'title': request.title,
        'reason': request.reason,
        'payload': request.payload,
      },
    ),
  );
  if (result == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref
        .read(mobileCommandsProvider)
        .resubmitRequest(
          requestId: request.id,
          title: result['title'] as String,
          reason: result['reason'] as String,
          payload: result['payload'] as Map<String, dynamic>,
        );
    ref.invalidate(mobileRequestDetailProvider(request.id));
    messenger.showSnackBar(
      const SnackBar(
        content: Text('تم تعديل الطلب وإعادة رفعه — بدأ مسار اعتماد جديد.'),
      ),
    );
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(requestErrorMessage(error) ?? humanizeError(error)),
      ),
    );
  }
}

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

// ═══════════════════════════════════════════════════════════════════════════
// شريط القرار الثابت أسفل الشاشة
// ═══════════════════════════════════════════════════════════════════════════

class _DecisionBar extends ConsumerWidget {
  const _DecisionBar({
    required this.request,
    required this.awaitingMe,
    required this.currentStage,
  });

  final MobileRequestDetail request;
  final bool awaitingMe;
  final String? currentStage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                awaitingMe
                    ? 'الطلب بانتظار قرارك'
                    : 'الطلب الآن عند ${currentStage ?? 'مرحلة أخرى'} — ويمكنك البت فيه بصلاحيتك',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: awaitingMe
                      ? AppColors.statusInfo
                      : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.statusSuccess,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: () =>
                          _openDecision(context, ref, request, 'approve'),
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('اعتماد'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: requestReturnColor,
                        side: BorderSide(
                          color: requestReturnColor.withValues(alpha: .5),
                        ),
                        minimumSize: const Size.fromHeight(48),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: () =>
                          _openDecision(context, ref, request, 'return'),
                      icon: const Icon(Icons.undo_rounded, size: 19),
                      label: const Text('إرجاع'),
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
                        minimumSize: const Size.fromHeight(48),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: () =>
                          _openDecision(context, ref, request, 'reject'),
                      icon: const Icon(Icons.close_rounded, size: 19),
                      label: const Text('رفض'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// البطاقة الرئيسية: النوع والرقم والحالة وصاحب الطلب
// ═══════════════════════════════════════════════════════════════════════════

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
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w900,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
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
        final awaiting = canDecide && (request.awaitingMe ?? true);
        main = awaiting
            ? 'الطلب بانتظار قرارك'
            : 'بانتظار قرار ${currentStage ?? 'الإدارة'}';
        if (awaiting) {
          if (currentStage != null) detail = 'المرحلة الحالية: $currentStage';
        } else if (canDecide) {
          detail = 'يمكنك البت فيه بصلاحيتك قبل وصوله إليك';
        }
        final current = currentStepIndex(request.steps, request.status);
        final due = requestDueStatus(
          current >= 0 ? request.steps[current].dueAt : request.decisionDueAt,
        );
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
                if (chip != null) ...[const SizedBox(height: 8), chip],
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

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.request});

  final MobileRequestDetail request;

  Map<String, dynamic> get _p => request.payload;

  String? _text(String key) {
    final v = _p[key]?.toString().trim();
    return v == null || v.isEmpty || v == 'null' ? null : v;
  }

  String? _day(String key) {
    final d = DateTime.tryParse(_p[key]?.toString() ?? '');
    return d == null ? null : arDay(d);
  }

  List<(IconData, String, String)> _rows() {
    final rows = <(IconData, String, String)>[];
    void add(IconData icon, String label, String? value) {
      if (value != null && value.trim().isNotEmpty) {
        rows.add((icon, label, value.trim()));
      }
    }

    final period = requestPeriodLabel(_p);
    final days = requestDays(_p);
    switch (request.type) {
      case 'leave':
        add(
          Icons.category_rounded,
          'نوع الإجازة',
          leaveTypeLabel(_text('leaveType')),
        );
        add(Icons.date_range_rounded, 'الفترة', period);
        if (days != null) {
          add(Icons.event_available_rounded, 'المدة', arDays(days));
        }
      case 'mission' || 'convoy' || 'fundraising':
        add(Icons.place_rounded, 'الوجهة', _text('location'));
        add(
          Icons.date_range_rounded,
          days != null && days > 1 ? 'الفترة' : 'اليوم',
          period,
        );
        if (days != null && days > 1) {
          add(Icons.event_available_rounded, 'المدة', arDays(days));
        }
        add(Icons.logout_rounded, 'وقت الانطلاق', time12(_p['startTime']));
        add(Icons.login_rounded, 'وقت العودة', time12(_p['endTime']));
      case 'late_permit' || 'early_permit':
        add(
          Icons.category_rounded,
          'نوع الإذن',
          permitKindLabel(_text('permitKind'), request.type),
        );
        add(Icons.today_rounded, 'اليوم', period);
        add(Icons.timer_outlined, 'المدة', permitDurationLabel(_p['minutes']));
      case 'shift_change':
        add(Icons.schedule_rounded, 'الفترة المطلوبة', _text('shiftName'));
        add(Icons.event_available_rounded, 'تبدأ من', _day('effectiveFrom'));
      case 'attendance_correction':
        add(Icons.today_rounded, 'اليوم', _day('workDate') ?? period);
        add(Icons.login_rounded, 'الحضور المطلوب', time12(_p['checkInTime']));
        add(
          Icons.logout_rounded,
          'الانصراف المطلوب',
          time12(_p['checkOutTime']),
        );
      default:
        add(Icons.date_range_rounded, 'الفترة', period);
        add(Icons.place_rounded, 'المكان', _text('location'));
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = _rows();
    final reason = request.reason?.trim();
    final showReason =
        reason != null && reason.isNotEmpty && reason != request.title?.trim();
    if (rows.isEmpty && !showReason && request.attachments.isEmpty) {
      return const SizedBox.shrink();
    }
    return _SectionCard(
      icon: Icons.assignment_outlined,
      title:
          'بيانات ${requestTypeLabel(request.type) == 'طلب' ? 'الطلب' : requestTypeLabel(request.type)}',
      children: [
        for (final (icon, label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: scheme.primary),
                const SizedBox(width: 10),
                SizedBox(
                  width: 92,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (showReason) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: .45),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.format_quote_rounded,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'السبب والتفاصيل',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  reason,
                  style: const TextStyle(fontSize: 13.5, height: 1.6),
                ),
              ],
            ),
          ),
        ],
        if (_p['startLocation'] is Map) ...[
          const SizedBox(height: 10),
          _StartLocationTile(
            location: Map<String, dynamic>.from(_p['startLocation'] as Map),
          ),
        ],
        if (request.attachments.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (var i = 0; i < request.attachments.length; i++)
            _AttachmentTile(attachment: request.attachments[i], index: i),
        ],
      ],
    );
  }
}

/// موقع بدء المأمورية كما سُجِّل لحظة إرسالها: العنوان/الإحداثيات، الدقة، الوقت،
/// فتح الخريطة، وتحذير صريح إن كان الموقع من تطبيق تزييف.
class _StartLocationTile extends StatelessWidget {
  const _StartLocationTile({required this.location});

  final Map<String, dynamic> location;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lat = (location['lat'] as num?)?.toDouble();
    final lng = (location['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return const SizedBox.shrink();
    final mocked = location['mocked'] == true;
    final accuracy = (location['accuracy'] as num?)?.round();
    final at = DateTime.tryParse(location['capturedAt']?.toString() ?? '');
    final address = location['address']?.toString().trim();
    final color = mocked ? AppColors.statusDanger : const Color(0xFF2563EB);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.my_location_rounded, size: 20, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'موقع بدء المأمورية',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      address != null && address.isNotEmpty
                          ? address
                          : '${lat.toStringAsFixed(5)}، ${lng.toStringAsFixed(5)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (at != null) arDateTime(at),
                        if (accuracy != null) 'الدقة ± $accuracy م',
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (mocked) ...[
            const SizedBox(height: 8),
            const Text(
              'تحذير: الموقع صادر عن تطبيق لتزييف المواقع، وليس من GPS الجهاز.',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
                color: AppColors.statusDanger,
              ),
            ),
          ],
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: () => launchUrl(
                Uri.parse(
                  'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
                ),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.map_outlined, size: 18),
              label: const Text('فتح على الخريطة'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({required this.attachment, required this.index});

  final MobileRequestAttachment attachment;
  final int index;

  @override
  Widget build(BuildContext context) {
    final mime = attachment.mimeType.toLowerCase();
    final isImage = mime.startsWith('image/');
    final isPdf = mime.contains('pdf');
    final kb = attachment.sizeBytes / 1024;
    final size = attachment.sizeBytes <= 0
        ? null
        : kb < 1024
        ? '${kb.round()} كيلوبايت'
        : '${(kb / 1024).toStringAsFixed(1)} ميجابايت';
    return Card(
      margin: const EdgeInsets.only(top: 6),
      elevation: 0,
      color: Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withValues(alpha: .35),
      child: ListTile(
        dense: true,
        leading: Icon(
          isImage
              ? Icons.image_outlined
              : isPdf
              ? Icons.picture_as_pdf_outlined
              : Icons.attach_file_rounded,
        ),
        title: Text(
          isImage
              ? 'صورة ${index + 1}'
              : isPdf
              ? 'ملف PDF ${index + 1}'
              : 'مرفق ${index + 1}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: size == null ? null : Text(size),
        trailing: const Icon(Icons.open_in_new_rounded, size: 18),
        onTap: () => _openAttachment(context, attachment.path),
      ),
    );
  }
}

/// بطاقة قسم بعنوان وأيقونة.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .6)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: AppColors.brandPrimary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// سياق القرار للمعتمِد: الرصيد، الزملاء خارج المقر، طلبات الشهر، البديل
// ═══════════════════════════════════════════════════════════════════════════

class _DecisionContextCard extends StatelessWidget {
  const _DecisionContextCard({required this.request});

  final MobileRequestDetail request;

  static bool hasContent(MobileRequestDetail r) =>
      r.insights != null || r.substituteName != null || r.conflicts.isNotEmpty;

  static String _units(double v) => arDays(v.round());

  String _awayLabel(String type) => switch (type) {
    'leave' => 'إجازة',
    'mission' => 'مأمورية',
    'convoy' => 'قافلة',
    'fundraising' => 'فاندي',
    _ => requestTypeLabel(type),
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ins = request.insights;
    final days = requestDays(request.payload);
    final rows = <Widget>[];

    Widget row({
      required IconData icon,
      required Color color,
      required String title,
      String? subtitle,
      Widget? extra,
    }) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: color.withValues(alpha: .12),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    height: 1.45,
                  ),
                ),
                if (subtitle != null && subtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ?extra,
              ],
            ),
          ),
        ],
      ),
    );

    // الرصيد (للإجازات)
    if (ins?.leaveAvailable != null) {
      final available = ins!.leaveAvailable!;
      final short =
          days != null && request.status == 'pending' && available < 0;
      rows.add(
        row(
          icon: Icons.account_balance_wallet_outlined,
          color: short ? AppColors.statusDanger : AppColors.statusSuccess,
          title:
              'المتاح من ${ins.leaveName ?? 'رصيد الإجازة'}: ${_units(available < 0 ? 0 : available)}',
          subtitle: [
            'مستهلك ${fmtUnits(ins.leaveConsumed ?? 0)}',
            'محجوز ${fmtUnits(ins.leaveReserved ?? 0)}',
            if (short) 'الرصيد لا يغطي هذه المدة',
          ].join(' · '),
        ),
      );
    }

    // الزملاء خارج المقر في الفترة نفسها
    if (ins != null && requestPeriodLabel(request.payload) != null) {
      final away = ins.teamAway;
      rows.add(
        row(
          icon: away.isEmpty ? Icons.groups_rounded : Icons.group_off_rounded,
          color: away.isEmpty
              ? AppColors.statusSuccess
              : AppColors.statusWarning,
          title: away.isEmpty
              ? (ins.teamSize == 0
                    ? 'لا زملاء آخرين في إدارته'
                    : 'لا أحد من زملاء إدارته خارج المقر في الفترة نفسها')
              : '${arEmployees(away.length)} من إدارته خارج المقر في الفترة نفسها',
          subtitle: away.isEmpty || ins.teamSize == 0
              ? null
              : 'من أصل ${arEmployees(ins.teamSize)} في الإدارة',
          extra: away.isEmpty
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final a in away.take(8))
                        RequestMetaChip(
                          icon: requestTypeIcon(a.type),
                          text:
                              '${a.name} · ${_awayLabel(a.type)}${a.status == 'pending' ? ' (قيد المراجعة)' : ''}',
                          color: requestTypeColor(a.type),
                        ),
                      if (away.length > 8)
                        RequestMetaChip(
                          icon: Icons.more_horiz_rounded,
                          text: 'و${away.length - 8} آخرون',
                        ),
                    ],
                  ),
                ),
        ),
      );
    }

    // طلبات الموظف هذا الشهر
    if (ins != null) {
      final parts = [
        if (ins.monthMissions > 0)
          arCount(
            ins.monthMissions,
            one: 'مأمورية واحدة',
            two: 'مأموريتان',
            few: 'مأموريات',
            many: 'مأمورية',
            base: 'مأمورية',
          ),
        if (ins.monthLeaves > 0)
          arCount(
            ins.monthLeaves,
            one: 'إجازة واحدة',
            two: 'إجازتان',
            few: 'إجازات',
            many: 'إجازة',
            base: 'إجازة',
          ),
        if (ins.monthPermits > 0)
          arCount(
            ins.monthPermits,
            one: 'إذن واحد',
            two: 'إذنان',
            few: 'أذونات',
            many: 'إذنًا',
            base: 'إذن',
          ),
      ];
      rows.add(
        row(
          icon: Icons.insights_rounded,
          color: AppColors.statusViolet,
          title: ins.monthTotal == 0
              ? 'لا طلبات أخرى له هذا الشهر'
              : 'طلباته الأخرى هذا الشهر: ${arRequests(ins.monthTotal)}',
          subtitle: [
            if (parts.isNotEmpty) parts.join(' · '),
            if (ins.monthPending > 0) 'قيد المراجعة: ${ins.monthPending}',
            if (ins.monthRejected > 0) 'مرفوض أو مُعاد: ${ins.monthRejected}',
          ].join(' — '),
        ),
      );
    }

    // البديل والتعارضات
    if (request.type == 'leave' || request.substituteName != null) {
      rows.add(
        row(
          icon: Icons.swap_horiz_rounded,
          color: AppColors.brandPrimary,
          title: request.substituteName == null
              ? 'لم يُحدِّد بديلًا أثناء غيابه'
              : 'البديل أثناء غيابه: ${request.substituteName}',
        ),
      );
    }
    for (final conflict in request.conflicts) {
      rows.add(
        row(
          icon: Icons.warning_amber_rounded,
          color: AppColors.statusDanger,
          title: _ContextCard._humanize(conflict),
        ),
      );
    }

    if (rows.isEmpty) return const SizedBox.shrink();
    return _SectionCard(
      icon: Icons.fact_check_outlined,
      title: 'سياق القرار',
      children: rows,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// البديل والتعارضات
// ═══════════════════════════════════════════════════════════════════════════

class _ContextCard extends StatelessWidget {
  const _ContextCard({required this.request});

  final MobileRequestDetail request;

  /// «2026-10-05» داخل رسالة التعارض → «5 أكتوبر».
  static String _humanize(String text) => text
      .replaceAllMapped(RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})'), (m) {
        final d = DateTime.tryParse(
          '${m[1]}-${m[2]!.padLeft(2, '0')}-${m[3]!.padLeft(2, '0')}',
        );
        return d == null ? m[0]! : DateFormat('d MMMM', 'ar').format(d);
      })
      .replaceAllMapped(
        RegExp(r'\(([^()]+) إلى ([^()]+)\)'),
        (m) => m[1]!.trim() == m[2]!.trim() ? '(${m[1]!.trim()})' : m[0]!,
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _SectionCard(
      icon: Icons.people_alt_outlined,
      title: 'البديل والتعارضات',
      children: [
        Row(
          children: [
            Icon(Icons.swap_horiz_rounded, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Text(
              'البديل أثناء الغياب: ',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
            Expanded(
              child: Text(
                request.substituteName ?? 'لم يُحدَّد',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (request.conflicts.isEmpty)
          Row(
            children: [
              const Icon(
                Icons.check_circle_outline_rounded,
                size: 18,
                color: AppColors.statusSuccess,
              ),
              const SizedBox(width: 8),
              Text(
                'لا توجد طلبات متداخلة في الفترة نفسها.',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
            ],
          )
        else
          for (final conflict in request.conflicts)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: AppColors.statusDanger,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _humanize(conflict),
                      style: const TextStyle(
                        color: AppColors.statusDanger,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// تنفيذ المأمورية / القافلة / الفاندي
// ═══════════════════════════════════════════════════════════════════════════

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
          builder: (context) => _EndMissionSheet(noun: _noun),
        );
    if (result == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(mobileCommandsProvider)
          .endMission(
            requestId: request.id,
            report: result.report,
            outcome: result.outcome,
            withCheckout: result.withCheckout,
          );
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.statusSuccess,
          content: Text(
            result.withCheckout
                ? 'تم إنهاء $_noun وتسجيل انصرافك.'
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
        const Color(0xFF64748B),
        Icons.flag_outlined,
        'لم يبدأ التنفيذ بعد',
        isOwner
            ? (status == 'approved'
                  ? 'اعتُمدت $_noun — ابدأها عند انطلاقك فعليًا.'
                  : 'يمكنك بدؤها الآن ولو كان الطلب قيد المراجعة.')
            : (status == 'approved'
                  ? 'اعتُمدت وبانتظار أن يبدأ الموظف التنفيذ.'
                  : null),
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
class _EndMissionSheet extends StatefulWidget {
  const _EndMissionSheet({
    required this.noun,
    this.reportOnly = false,
    this.initialReport,
    this.initialOutcome,
  });

  final String noun;
  final bool reportOnly;
  final String? initialReport;
  final String? initialOutcome;

  @override
  State<_EndMissionSheet> createState() => _EndMissionSheetState();
}

class _EndMissionSheetState extends State<_EndMissionSheet> {
  late final _reportController = TextEditingController(
    text: widget.initialReport?.trim() ?? '',
  );
  late final _outcomeController = TextEditingController(
    text: widget.initialOutcome?.trim() ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _reportController.dispose();
    _outcomeController.dispose();
    super.dispose();
  }

  void _submit({required bool withCheckout}) {
    final report = _reportController.text.trim();
    if (report.length < 3) {
      setState(() => _error = 'التقرير إلزامي (ثلاثة أحرف على الأقل).');
      return;
    }
    final outcome = _outcomeController.text.trim();
    Navigator.pop(context, (
      report: report,
      outcome: outcome.isEmpty ? null : outcome,
      withCheckout: withCheckout,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.reportOnly
                  ? 'تقرير ${widget.noun}'
                  : 'إنهاء ${widget.noun}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            if (widget.reportOnly) ...[
              const SizedBox(height: 6),
              Text(
                'أغلقها النظام في نهاية يومها؛ التقرير يوثّق ما أنجزته ولا يغيّر حضور اليوم.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _reportController,
              maxLines: 3,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: InputDecoration(
                labelText: 'تقرير التنفيذ (إلزامي)',
                hintText: 'ماذا أنجزت؟',
                errorText: _error,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _outcomeController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'النتيجة (اختياري)',
                hintText: 'مثال: اكتملت بنجاح، تم التسليم…',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 18),
            if (widget.reportOnly)
              FilledButton.icon(
                onPressed: () => _submit(withCheckout: false),
                icon: const Icon(Icons.save_rounded),
                label: const Text('حفظ التقرير'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
              )
            else ...[
              FilledButton.icon(
                onPressed: () => _submit(withCheckout: true),
                icon: const Icon(Icons.logout_rounded),
                label: Text('إنهاء ${widget.noun} وتسجيل الانصراف'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.statusSuccess,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'إذا انتهى يوم عملك وتغادر مباشرة.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _submit(withCheckout: false),
                icon: const Icon(Icons.task_alt_rounded),
                label: Text('إنهاء ${widget.noun} فقط واستمرار الدوام'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'إذا عدت إلى مقر العمل أو ما زال دوامك مستمرًا.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// مسار الاعتماد: شريط المراحل + سجل الطلب
// ═══════════════════════════════════════════════════════════════════════════

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
    return events;
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
class _StageStrip extends StatelessWidget {
  const _StageStrip({
    required this.steps,
    required this.requestStatus,
    required this.currentIndex,
  });

  final List<MobileRequestStep> steps;
  final String requestStatus;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final children = <Widget>[];
    for (var i = 0; i < steps.length; i++) {
      final s = steps[i];
      final state = requestStageState(
        s,
        requestStatus,
        isCurrent: i == currentIndex,
      );
      final faded =
          state == RequestStageState.skipped ||
          state == RequestStageState.waiting ||
          state == RequestStageState.stopped;
      children.add(
        Expanded(
          child: Column(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: faded ? scheme.surface : state.color,
                  border: Border.all(color: state.color, width: 2),
                ),
                child: Icon(
                  state.icon,
                  size: 18,
                  color: faded ? state.color : Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                requestStageName(s.name, roleSlug: s.roleSlug, order: s.order),
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: faded ? scheme.onSurfaceVariant : null,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                state.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: state.color,
                ),
              ),
            ],
          ),
        ),
      );
      if (i < steps.length - 1) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: SizedBox(
              width: 28,
              child: Divider(thickness: 2, color: scheme.outlineVariant),
            ),
          ),
        );
      }
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.event,
    required this.isFirst,
    required this.isLast,
  });

  final _JourneyEvent event;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final line = scheme.outlineVariant.withValues(alpha: .7);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 34,
            child: Column(
              children: [
                Container(
                  width: 2,
                  height: 6,
                  color: isFirst ? Colors.transparent : line,
                ),
                event.live
                    ? _PulsingDot(color: event.color, size: 28)
                    : Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: event.color.withValues(alpha: .14),
                          border: Border.all(
                            color: event.color.withValues(alpha: .5),
                          ),
                        ),
                        child: Icon(event.icon, size: 15, color: event.color),
                      ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: isLast ? Colors.transparent : line,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 8, bottom: isLast ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13.5,
                      color: event.live ? event.color : null,
                    ),
                  ),
                  if (event.subtitle != null && event.subtitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        event.subtitle!,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (event.at != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        arDateTime(event.at!),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  if (event.comment != null && event.comment!.trim().isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: event.color.withValues(alpha: .07),
                        borderRadius: const BorderRadiusDirectional.only(
                          topEnd: Radius.circular(12),
                          bottomStart: Radius.circular(12),
                          bottomEnd: Radius.circular(12),
                        ),
                      ),
                      child: Text(
                        '«${event.comment!.trim()}»',
                        style: const TextStyle(fontSize: 12.5, height: 1.5),
                      ),
                    ),
                  if (event.chip != null) ...[
                    const SizedBox(height: 6),
                    RequestMetaChip(
                      icon: event.chipDanger
                          ? Icons.warning_amber_rounded
                          : Icons.schedule_rounded,
                      text: event.chip!,
                      color: event.chipDanger
                          ? AppColors.statusDanger
                          : AppColors.statusInfo,
                      strong: event.chipDanger,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// دائرة نابضة للمرحلة الحالية.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // نبض محدود لا يستنزف البطارية ولا يُبقي الشاشة ترسم بلا نهاية، ويحترم
    // إعداد تقليل الحركة في الجهاز.
    if (!MediaQuery.disableAnimationsOf(context)) {
      _controller.repeat(reverse: true, count: 6);
    }
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
        builder: (context, _) {
          final t = Curves.easeInOut.transform(_controller.value);
          return Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: 1 + .3 * t,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: .35 * (1 - t)),
                  ),
                ),
              ),
              Container(
                width: widget.size * .62,
                height: widget.size * .62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                ),
                child: const Icon(
                  Icons.hourglass_top_rounded,
                  size: 11,
                  color: Colors.white,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// بانر إعادة الرفع — يوضّح لصاحب الطلب أنه رُفض/أُعيد ويمكن تعديله.
class _ResubmitBanner extends StatelessWidget {
  const _ResubmitBanner({required this.returned});

  final bool returned;

  @override
  Widget build(BuildContext context) {
    final color = returned ? const Color(0xFFC2410C) : AppColors.statusDanger;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.edit_note_rounded, color: color, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  returned ? 'أُعيد إليك الطلب للتعديل' : 'رُفض هذا الطلب',
                  style: TextStyle(fontWeight: FontWeight.w900, color: color),
                ),
                const SizedBox(height: 4),
                Text(
                  'اقرأ ملاحظة المعتمِد في مسار الاعتماد، عدّل ما يلزم ثم أعد رفعه '
                  'ليبدأ مسار اعتماد جديد.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
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
