import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/core/theme/brand_gradients.dart';
import 'package:ahla_shabab_management_os/core/widgets/host_app_bar_scope.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class ApprovalDelegationsPage extends ConsumerStatefulWidget {
  const ApprovalDelegationsPage({super.key});

  @override
  ConsumerState<ApprovalDelegationsPage> createState() =>
      _ApprovalDelegationsPageState();
}

class _ApprovalDelegationsPageState
    extends ConsumerState<ApprovalDelegationsPage> {
  @override
  Widget build(BuildContext context) {
    final delegationsAsync = ref.watch(myApprovalDelegationsProvider);
    final isHostActive = HostAppBarScope.isActive(context);

    return Scaffold(
      appBar: isHostActive
          ? null
          : AppBar(
              title: const Text('تفويض الاعتمادات'),
              actions: [
                IconButton(
                  tooltip: 'تحديث',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () =>
                      ref.invalidate(myApprovalDelegationsProvider),
                ),
              ],
            ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myApprovalDelegationsProvider);
        },
        child: delegationsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 60),
              Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(
                'تعذر تحميل التفويضات: $err',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Center(
                child: FilledButton.icon(
                  onPressed: () =>
                      ref.invalidate(myApprovalDelegationsProvider),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('إعادة المحاولة'),
                ),
              ),
            ],
          ),
          data: (delegations) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                // بطاقة التعريف والهدف
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: BrandGradients.hero),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.swap_horiz_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'تفويض صلاحيات الاعتماد',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        'عند قيامك بإجازة أو غياب، يمكنك تفويض زميل معتمد للبت في طلبات الفريق نيابةً عنك لضمان عدم تأخر سير العمل.',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // زر إنشاء تفويض جديد
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => _showNewDelegationSheet(context),
                    icon: const Icon(Icons.add_task_rounded),
                    label: const Text(
                      'تعيين تفويض جديد',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // قائمة التفويضات السابقة والحالية
                const MobileSectionHeader(
                  title: 'سجل التفويضات',
                  subtitle: 'سجل تفويضاتك وتفويضات الزملاء الموجهة إليك (الأحدث أولاً).',
                ),
                const SizedBox(height: 10),

                if (delegations.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(32),
                    alignment: Alignment.center,
                    child: Column(
                      children: [
                        Icon(
                          Icons.assignment_ind_outlined,
                          size: 48,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: .5),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'لا توجد تفويضات مسجلة حالياً',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'اضغط على «تعيين تفويض جديد» لتفويض صلاحياتك لبديل.',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                else
                  ...delegations.map((d) => _DelegationCard(
                        delegation: d,
                        onCancelled: () =>
                            ref.invalidate(myApprovalDelegationsProvider),
                      )),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showNewDelegationSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _NewDelegationSheet(
        onSuccess: () {
          ref.invalidate(myApprovalDelegationsProvider);
        },
      ),
    );
  }
}

class _DelegationCard extends ConsumerWidget {
  const _DelegationCard({
    required this.delegation,
    required this.onCancelled,
  });

  final ApprovalDelegation delegation;
  final VoidCallback onCancelled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final statusBadge = _buildStatusBadge(delegation.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: .6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            delegation.isMine
                              ? Icons.arrow_circle_up_rounded
                              : Icons.arrow_circle_down_rounded,
                            size: 18,
                            color: delegation.isMine
                              ? theme.colorScheme.primary
                              : AppColors.statusSuccess,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            delegation.isMine
                                ? 'مفوَّض منك إلى: ${delegation.delegateName}'
                                : 'مفوَّض إليك من: ${delegation.managerName}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      if (delegation.isMine && delegation.delegateCode.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2, right: 24),
                          child: Text(
                            'كود البديل: ${delegation.delegateCode}',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                statusBadge,
              ],
            ),
            const Divider(height: 20),
            Row(
              children: [
                const Icon(Icons.date_range_rounded, size: 16, color: Colors.grey),
                const SizedBox(width: 6),
                Text(
                  'من: ${delegation.startsAt}  إلى: ${delegation.endsAt}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            if (delegation.reason != null && delegation.reason!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.notes_rounded, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'السبب: ${delegation.reason}',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (delegation.isMine &&
                (delegation.status == 'active' ||
                    delegation.status == 'scheduled')) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    side: BorderSide(color: theme.colorScheme.error),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => _confirmCancel(context, ref),
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: const Text('إلغاء التفويض'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case 'active':
        bg = AppColors.statusSuccess.withValues(alpha: .15);
        fg = AppColors.statusSuccess;
        label = 'سارٍ حالياً';
        break;
      case 'scheduled':
        bg = AppColors.statusInfo.withValues(alpha: .15);
        fg = AppColors.statusInfo;
        label = 'مجدول';
        break;
      case 'cancelled':
        bg = Colors.red.withValues(alpha: .15);
        fg = Colors.red;
        label = 'ملغى';
        break;
      case 'expired':
      default:
        bg = Colors.grey.withValues(alpha: .15);
        fg = Colors.grey;
        label = 'منتهٍ';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد إلغاء التفويض'),
        content: const Text(
          'هل أنت متأكد من رغبتك في إلغاء هذا التفويض فوراً واستعادة صلاحيات البت المباشرة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('تراجع'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('نعم، إلغاء التفويض'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ref
          .read(mobileCommandsProvider)
          .cancelApprovalDelegation(delegation.id);
      onCancelled();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إلغاء التفويض بنجاح.'),
            backgroundColor: AppColors.statusSuccess,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل إلغاء التفويض: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _NewDelegationSheet extends ConsumerStatefulWidget {
  const _NewDelegationSheet({required this.onSuccess});

  final VoidCallback onSuccess;

  @override
  ConsumerState<_NewDelegationSheet> createState() =>
      _NewDelegationSheetState();
}

class _NewDelegationSheetState extends ConsumerState<_NewDelegationSheet> {
  String? _selectedDelegateId;
  DateTime _startsAt = DateTime.now();
  DateTime _endsAt = DateTime.now().add(const Duration(days: 7));
  final _reasonCtrl = TextEditingController();
  bool _isSubmitting = false;

  final _fmt = DateFormat('yyyy-MM-dd');

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final teamAsync = ref.watch(mobileTeamProvider);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 20, 16, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_add_alt_1_rounded, color: Colors.blue),
              const SizedBox(width: 8),
              const Text(
                'تعيين تفويض جديد',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // اختيار البديل
          teamAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (err, _) => Text(
              'تعذر جلب الموظفين: $err',
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
            data: (team) {
              return DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: 'اختر الموظف البديل',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                value: _selectedDelegateId,
                items: team.map((m) {
                  final title = m.jobTitle?.isNotEmpty == true
                      ? m.jobTitle!
                      : (m.employeeCode ?? '');
                  return DropdownMenuItem<String>(
                    value: m.id,
                    child: Text(
                      title.isNotEmpty ? '${m.name} ($title)' : m.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _selectedDelegateId = val),
              );
            },
          ),
          const SizedBox(height: 14),

          // اختيار الفترة
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickStartDate,
                  icon: const Icon(Icons.calendar_today_rounded, size: 16),
                  label: Text('من: ${_fmt.format(_startsAt)}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickEndDate,
                  icon: const Icon(Icons.calendar_month_rounded, size: 16),
                  label: Text('إلى: ${_fmt.format(_endsAt)}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // سبب التفويض
          TextField(
            controller: _reasonCtrl,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'سبب التفويض (اختياري)',
              hintText: 'مثال: إجازة سنوية، مهمة عمل خارج المحافظة...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // زر الحفظ
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: _isSubmitting ? null : _submitDelegation,
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'تأكيد وحفظ التفويض',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startsAt,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _startsAt = picked;
        if (_endsAt.isBefore(_startsAt)) {
          _endsAt = _startsAt.add(const Duration(days: 1));
        }
      });
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endsAt.isBefore(_startsAt) ? _startsAt : _endsAt,
      firstDate: _startsAt,
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _endsAt = picked);
    }
  }

  Future<void> _submitDelegation() async {
    if (_selectedDelegateId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار الموظف البديل.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ref.read(mobileCommandsProvider).setApprovalDelegation(
            delegateEmployeeId: _selectedDelegateId!,
            startsAt: _fmt.format(_startsAt),
            endsAt: _fmt.format(_endsAt),
            reason: _reasonCtrl.text.trim().isNotEmpty
                ? _reasonCtrl.text.trim()
                : null,
          );

      widget.onSuccess();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تسجيل تفويض الاعتماد بنجاح.'),
            backgroundColor: AppColors.statusSuccess,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل تسجيل التفويض: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
