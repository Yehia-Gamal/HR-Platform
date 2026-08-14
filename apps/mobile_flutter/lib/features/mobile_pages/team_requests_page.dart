import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_request_detail_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// اعتماد طلبات الفريق — قائمة طلبات فريقك المباشر مع اعتماد/رفض سريع.
/// تُفلتر الطلبات على أعضاء فريقك المباشر وتتيح القرار فوراً دون مغادرة القائمة،
/// وفتح التفاصيل الكاملة (مسار الاعتماد + تنفيذ المأمورية) بضغطة واحدة.
class TeamRequestsPage extends ConsumerStatefulWidget {
  const TeamRequestsPage({super.key});

  @override
  ConsumerState<TeamRequestsPage> createState() => _TeamRequestsPageState();
}

class _TeamRequestsPageState extends ConsumerState<TeamRequestsPage> {
  final _search = TextEditingController();
  String _query = '';
  String _filter = 'pending';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<MobileRequest> _apply(
    List<MobileRequest> requests,
    Set<String> teamIds,
  ) {
    var result = requests
        .where((r) => r.employeeId != null && teamIds.contains(r.employeeId))
        .toList(growable: false);
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
    return switch (_filter) {
      'pending' => result
          .where((r) => r.status == 'pending')
          .toList(growable: false),
      'approved' => result
          .where(
            (r) =>
                r.status == 'approved' ||
                r.status == 'completed' ||
                r.status == 'escalated',
          )
          .toList(growable: false),
      'closed' => result
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

  Future<void> _openDetail(MobileRequest request) async {
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

  Future<void> _decide(MobileRequest request, String decision) async {
    final controller = TextEditingController();
    String? errorText;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(decision == 'approve' ? 'اعتماد الطلب' : 'رفض الطلب'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: decision == 'approve'
                  ? 'ملاحظة اختيارية'
                  : 'سبب الرفض (إلزامي)',
              errorText: errorText,
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
                  setState(
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
              decision == 'approve' ? 'تم اعتماد الطلب بنجاح.' : 'تم رفض الطلب.',
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

    final teamIds = switch (teamAsync) {
      AsyncData(value: final members) =>
        members.map((m) => m.id).toSet(),
      _ => <String>{},
    };

    final filtered = switch (requestsAsync) {
      AsyncData(value: final requests) => _apply(requests, teamIds),
      _ => <MobileRequest>[],
    };
    final pendingCount = switch (requestsAsync) {
      AsyncData(value: final requests) => _apply(requests, teamIds)
          .where((r) => r.status == 'pending')
          .length,
      _ => 0,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('اعتماد طلبات الفريق')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(mobileRequestsProvider);
            ref.invalidate(mobileTeamProvider);
          },
          child: teamAsync.maybeWhen(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 40,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      humanizeError(error),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(mobileTeamProvider),
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
            orElse: () => requestsAsync.maybeWhen(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 40,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        humanizeError(error),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    TextButton(
                      onPressed: () => ref.invalidate(mobileRequestsProvider),
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
              orElse: () => ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  MobileSectionHeader(
                    title: 'اعتماد طلبات الفريق',
                    subtitle:
                        'طلبات أعضاء فريقك المباشر — اعتمد أو ارفض مباشرة من هنا.',
                  ),
                  const SizedBox(height: 8),
                  MobileFilterBar(
                    searchHint: 'بحث بالاسم أو العنوان أو السبب',
                    controller: _search,
                    onSearchChanged: (v) => setState(() => _query = v),
                    options: [
                      const MobileFilterOption('pending', 'معلّقة'),
                      const MobileFilterOption('approved', 'معتمدة'),
                      const MobileFilterOption('closed', 'مرفوضة/ملغاة'),
                      const MobileFilterOption('all', 'الكل'),
                    ],
                    selected: _filter,
                    onSelected: (v) => setState(() => _filter = v),
                    resultLabel: filtered.isEmpty
                        ? 'لا نتائج'
                        : '${filtered.length} طلب',
                  ),
                  if (pendingCount > 0 && _filter == 'pending') ...[
                    const SizedBox(height: 8),
                    _PendingBanner(count: pendingCount),
                  ],
                  const SizedBox(height: 8),
                  if (filtered.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: Text('لا توجد طلبات مطابقة')),
                    )
                  else
                    ...filtered.map(
                      (request) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _RequestCard(
                          request: request,
                          onTap: () => _openDetail(request),
                          onApprove: request.status == 'pending'
                              ? () => _decide(request, 'approve')
                              : null,
                          onReject: request.status == 'pending'
                              ? () => _decide(request, 'reject')
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.pending_actions_rounded, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$count طلب بانتظار قرارك.',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
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

  Widget _metaChip(ThemeData theme, {required IconData icon, required String text}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
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
