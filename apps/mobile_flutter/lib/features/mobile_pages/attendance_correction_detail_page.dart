import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/team_requests_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// صفحة مراجعة تفاصيل طلب تصحيح البصمة (للمدير والموظف).
class AttendanceCorrectionDetailPage extends ConsumerStatefulWidget {
  const AttendanceCorrectionDetailPage({required this.correctionId, super.key});

  final String correctionId;

  @override
  ConsumerState<AttendanceCorrectionDetailPage> createState() =>
      _AttendanceCorrectionDetailPageState();
}

class _AttendanceCorrectionDetailPageState
    extends ConsumerState<AttendanceCorrectionDetailPage> {
  bool _submitting = false;

  String _formatTime(DateTime? dt) {
    if (dt == null) return '—';
    return DateFormat('hh:mm a', 'ar').format(dt.toLocal());
  }

  String _typeLabel(String type) => switch (type) {
    'missing_check_in' => 'نسيان بصمة حضور (دخول)',
    'missing_check_out' => 'نسيان بصمة انصراف (خروج)',
    'wrong_time' => 'تعديل توقيت البصمة',
    'wrong_status' => 'تعديل حالة الحضور',
    'mission' => 'مأمورية عمل',
    'leave' => 'إجازة',
    _ => 'تصحيح بصمة أخرى',
  };

  IconData _typeIcon(String type) => switch (type) {
    'missing_check_in' => Icons.login_rounded,
    'missing_check_out' => Icons.logout_rounded,
    'wrong_time' => Icons.access_time_rounded,
    'wrong_status' => Icons.rule_rounded,
    _ => Icons.fingerprint_rounded,
  };

  Future<void> _decide(
    MobileAttendanceCorrectionDetail detail,
    String decision,
  ) async {
    final controller = TextEditingController();
    String? errorText;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDlgState) => AlertDialog(
          title: Text(decision == 'approved' ? 'اعتماد تصحيح البصمة' : 'رفض تصحيح البصمة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                decision == 'approved'
                    ? 'هل أنت متأكد من اعتماد تصحيح البصمة للموظف ${detail.employeeName} بتاريخ ${DateFormat('d MMMM y', 'ar').format(detail.workDate)}؟'
                    : 'يرجى توضيح سبب رفض تصحيح البصمة للموظف ${detail.employeeName}:',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: decision == 'approved' ? 'ملاحظة (اختيارية)' : 'سبب الرفض (إلزامي)',
                  errorText: errorText,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: decision == 'approved'
                    ? const Color(0xFF0F9F6E)
                    : Theme.of(context).colorScheme.error,
              ),
              onPressed: () {
                if (decision == 'rejected' && controller.text.trim().length < 3) {
                  setDlgState(() => errorText = 'سبب الرفض إلزامي (3 أحرف على الأقل)');
                  return;
                }
                Navigator.pop(dialogCtx, true);
              },
              child: Text(decision == 'approved' ? 'تأكيد الاعتماد' : 'تأكيد الرفض'),
            ),
          ],
        ),
      ),
    );

    final note = controller.text.trim();
    controller.dispose();
    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      await ref.read(mobileCommandsProvider).decideAttendanceCorrection(
            correctionId: detail.id,
            decision: decision,
            note: note.isNotEmpty ? note : null,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            decision == 'approved'
                ? 'تم اعتماد تصحيح البصمة بنجاح.'
                : 'تم رفض طلب تصحيح البصمة.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر اتخاذ القرار: ${humanizeError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final detailAsync = ref.watch(attendanceCorrectionDetailProvider(widget.correctionId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('تفاصيل تصحيح البصمة'),
        actions: [
          IconButton(
            tooltip: 'طلبات الفريق',
            icon: const Icon(Icons.fact_check_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TeamRequestsPage()),
            ),
          ),
        ],
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48, color: scheme.error),
                const SizedBox(height: 12),
                Text(
                  humanizeError(error),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () => ref.invalidate(
                    attendanceCorrectionDetailProvider(widget.correctionId),
                  ),
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
        ),
        data: (detail) {
          final isPending = detail.status == 'pending';
          final isApproved = detail.status == 'approved';
          final isRejected = detail.status == 'rejected';

          final statusColor = isApproved
              ? const Color(0xFF0F9F6E)
              : isRejected
                  ? const Color(0xFFDC3D4B)
                  : const Color(0xFFE58B00);

          final statusText = isApproved
              ? 'تم الاعتماد'
              : isRejected
                  ? 'مرفوض'
                  : 'قيد المراجعة والاعتماد';

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    // شريط حالة الطلب
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isApproved
                                ? Icons.check_circle_rounded
                                : isRejected
                                    ? Icons.cancel_rounded
                                    : Icons.hourglass_top_rounded,
                            color: statusColor,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              statusText,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: statusColor,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Text(
                            DateFormat('d MMM y', 'ar').format(detail.createdAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // بطاقة بيانات الموظف
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            AppAvatar(
                              name: detail.employeeName,
                              radius: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    detail.employeeName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${detail.jobTitle ?? "موظف"} · كود: ${detail.employeeCode}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // بطاقة تفاصيل البصمة واليوم
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'تفاصيل البصمة المطلوبة',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                            const Divider(height: 20),
                            _detailRow(
                              context,
                              icon: Icons.calendar_today_rounded,
                              label: 'تاريخ يوم العمل',
                              value: DateFormat('EEEE، d MMMM y', 'ar').format(detail.workDate),
                            ),
                            const SizedBox(height: 10),
                            _detailRow(
                              context,
                              icon: _typeIcon(detail.type),
                              label: 'نوع التصحيح',
                              value: _typeLabel(detail.type),
                              highlight: true,
                            ),
                            if (detail.requestedCheckIn != null) ...[
                              const SizedBox(height: 10),
                              _detailRow(
                                context,
                                icon: Icons.login_rounded,
                                label: 'وقت الحضور المطلوب',
                                value: _formatTime(detail.requestedCheckIn),
                              ),
                            ],
                            if (detail.requestedCheckOut != null) ...[
                              const SizedBox(height: 10),
                              _detailRow(
                                context,
                                icon: Icons.logout_rounded,
                                label: 'وقت الانصراف المطلوب',
                                value: _formatTime(detail.requestedCheckOut),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // بطاقة سبب الطلب
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.notes_rounded, size: 18, color: scheme.primary),
                                const SizedBox(width: 8),
                                const Text(
                                  'سبب التصحيح',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                detail.reason.isNotEmpty ? detail.reason : 'لم يُذكر سبب إضافي.',
                                style: const TextStyle(fontSize: 14, height: 1.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // بطاقة رد المراجعة إن وُجدت
                    if (detail.reviewedAt != null || detail.reviewNote != null) ...[
                      const SizedBox(height: 10),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.rate_review_outlined, size: 18, color: statusColor),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'بيانات المراجعة والقرار',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 20),
                              if (detail.reviewerName != null) ...[
                                _detailRow(
                                  context,
                                  icon: Icons.person_outline_rounded,
                                  label: 'المراجع',
                                  value: detail.reviewerName!,
                                ),
                                const SizedBox(height: 8),
                              ],
                              if (detail.reviewedAt != null) ...[
                                _detailRow(
                                  context,
                                  icon: Icons.access_time_rounded,
                                  label: 'تاريخ القرار',
                                  value: DateFormat('d MMM y - hh:mm a', 'ar').format(detail.reviewedAt!.toLocal()),
                                ),
                                const SizedBox(height: 8),
                              ],
                              if (detail.reviewNote != null && detail.reviewNote!.isNotEmpty) ...[
                                _detailRow(
                                  context,
                                  icon: Icons.chat_bubble_outline_rounded,
                                  label: 'ملاحظة القرار',
                                  value: detail.reviewNote!,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),
                    // زر التوجه لكافة طلبات الفريق
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const TeamRequestsPage()),
                      ),
                      icon: const Icon(Icons.list_alt_rounded),
                      label: const Text('عرض كافة طلبات الموظفين والفريق'),
                    ),
                  ],
                ),
              ),

              // أزرار اتخاذ القرار للمدير عند وجود صلاحية والطلب معلق
              if (isPending && detail.canDecide)
                SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      border: Border(
                        top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF0F9F6E),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: _submitting ? null : () => _decide(detail, 'approved'),
                            icon: _submitting
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.check_circle_outline_rounded),
                            label: const Text(
                              'اعتماد الطلب',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: scheme.error,
                              side: BorderSide(color: scheme.error),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: _submitting ? null : () => _decide(detail, 'rejected'),
                            icon: const Icon(Icons.cancel_outlined),
                            label: const Text(
                              'رفض الطلب',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _detailRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    bool highlight = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: highlight ? scheme.primary : scheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Text(
          '$label:',
          style: TextStyle(
            fontSize: 13,
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: highlight ? FontWeight.w900 : FontWeight.w700,
              color: highlight ? scheme.primary : scheme.onSurface,
            ),
            textAlign: TextAlign.start,
          ),
        ),
      ],
    );
  }
}
