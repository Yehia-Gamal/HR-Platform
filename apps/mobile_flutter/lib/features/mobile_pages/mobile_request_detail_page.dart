import 'dart:async';

import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/core/formatting/arabic_text.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/sharing/whatsapp_share_service.dart';
import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/location_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/employee_profile_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_self_service_page.dart'
    show NewRequestSheet;
import 'package:ahla_shabab_management_os/features/mobile_pages/request_decision_sheet.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/request_display.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

part 'request_detail/request_detail_actions.dart';
part 'request_detail/request_detail_banners.dart';
part 'request_detail/request_detail_hero_card.dart';
part 'request_detail/request_detail_cards.dart';
part 'request_detail/request_detail_context_cards.dart';
part 'request_detail/request_detail_mission_card.dart';
part 'request_detail/request_detail_end_mission_sheet.dart';
part 'request_detail/request_detail_journey.dart';
part 'request_detail/request_detail_timeline_tiles.dart';

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

    const delegateRoles = {
      'admin',
      'super-admin',
      'executive',
      'executive-director',
      'hr-manager',
      'hr-specialist',
      'operations-manager-1',
    };
    const adminOrHrRoles = {
      'admin',
      'super-admin',
      'executive',
      'executive-director',
      'general-manager',
      'hr-manager',
      'hr-specialist',
      'hr-officer',
      'operations-manager-1',
      'operations-manager',
    };
    final isAdminOrHr = (access?.roles.any(adminOrHrRoles.contains) ?? false) ||
        (access?.hasPermission('requests.approve') ?? false) ||
        (access?.hasPermission('leave.request.manage') ?? false);

    final current = currentStepIndex(request.steps, request.status);
    final currentStage = current >= 0
        ? requestStageName(
            request.steps[current].name,
            roleSlug: request.steps[current].roleSlug,
            order: request.steps[current].order,
          )
        : null;

    final isAbuAmmar = myEmployeeId == '767eae8e-e7be-458e-a6ca-879414e46b08' ||
        (access?.roles.contains('operations-manager-1') ?? false);
    final isCurrentStageOperations =
        currentStage?.contains('مدير التشغيل') ?? false;
    final canDelegate = !isClinicStaff &&
        !isMine &&
        !isAbuAmmar &&
        !isCurrentStageOperations &&
        request.status == 'pending' &&
        (access?.roles.any(delegateRoles.contains) ?? false);
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('تفاصيل الطلب'),
        actions: [
          IconButton(
            tooltip: 'مشاركة عبر واتساب',
            icon: const Icon(Icons.share_rounded),
            onPressed: () {
              WhatsAppShareService.shareRequest(
                number: request.number,
                typeLabel: requestTypeLabel(request.type),
                employeeName: request.employeeName,
                reason: request.reason ?? request.title ?? '',
                stage: currentStage,
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: (canDecide || canDelegate)
          ? _DecisionBar(
              request: request,
              awaitingMe: request.awaitingMe ?? true,
              canDecide: canDecide,
              canDelegate: canDelegate,
              currentStage: currentStage,
            )
          : null,
      body: SafeArea(
        top: false,
        bottom: !(canDecide || canDelegate),
        child: RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(mobileRequestDetailProvider(request.id)),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              (canDecide || canDelegate)
                  ? 20
                  : MediaQuery.paddingOf(context).bottom + 20,
            ),
            children: [
            _HeroCard(
              request: request,
              isMine: isMine,
              canDecide: canDecide,
              currentStage: currentStage,
            ),
            const SizedBox(height: 12),
            _SlaCountdownBanner(request: request, isMine: isMine),
            _DetailsCard(request: request),
            if (!isMine && _DecisionContextCard.hasContent(request)) ...[
              const SizedBox(height: 12),
              _DecisionContextCard(request: request),
            ] else if (request.substituteName != null ||
                request.conflicts.isNotEmpty) ...[
              const SizedBox(height: 12),
              _ContextCard(request: request),
            ],
            if (hasFieldExecution(request.type) &&
                (request.status != 'pending' ||
                    isMine ||
                    request.missionExecution?.startedAt != null)) ...[
              const SizedBox(height: 12),
              _MissionExecutionCard(request: request, isOwner: isMine),
            ],
            const SizedBox(height: 12),
            _JourneyCard(request: request),
            if ((isMine &&
                    ((request.canCancel && request.status == 'pending') ||
                        (isFieldAssignmentType(request.type) &&
                            (request.status == 'pending' || request.status == 'approved') &&
                            request.missionExecution?.status != 'completed'))) ||
                (isAdminOrHr && ((request.status == 'pending' && !canDecide) || request.status == 'approved'))) ...[
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
                icon: Icon(request.status == 'approved'
                    ? Icons.block_rounded
                    : isFieldAssignmentType(request.type)
                        ? Icons.cancel_outlined
                        : Icons.undo_rounded),
                label: Text(_cancelButtonLabel(request, isAdminOrHr, isMine)),
              ),
              const SizedBox(height: 12),
            ],
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
