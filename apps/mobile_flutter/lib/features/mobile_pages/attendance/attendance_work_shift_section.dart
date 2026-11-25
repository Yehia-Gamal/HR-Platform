part of '../mobile_attendance_page.dart';

class _WorkShiftSection extends ConsumerWidget {
  const _WorkShiftSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shiftInfoAsync = ref.watch(myWorkShiftInfoProvider);
    final attendanceStateAsync = ref.watch(attendanceStateProvider);
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.schedule_rounded,
                    size: 20,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'فترة العمل والورديات',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      Text(
                        'الوردية الأساسية المعتمدة لحساب التأخير والخصومات',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                  label: const Text(
                    'تغيير الفترة',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                  onPressed: () => showWorkShiftSelectionSheet(context, ref),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(
              height: 1,
              thickness: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.25),
            ),
            const SizedBox(height: 12),
            shiftInfoAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              error: (err, _) => Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'الدوام الأساسي المعتمد: 10:00 ص – 06:00 م (سماح 15 د)',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              data: (info) {
                final current = info.currentShift;
                final pending = info.pendingRequest;
                final shiftIcon = _getShiftIcon(current.code);
                final shiftColor = _getShiftColor(current.code, scheme);
                final liveStatus = _computeShiftLiveStatus(
                  startTime: current.activeStartTime,
                  endTime: current.activeEndTime,
                  graceInMinutes: current.graceInMinutes,
                  hasPermit: current.hasTodayPermit,
                  permitActiveStartTime: current.activeStartTime,
                );
                final todayCheckIn = attendanceStateAsync.asData?.value.todayCheckInAt;
                final disciplineMetric = _computeShiftDisciplineMetric(
                  startTime: current.activeStartTime,
                  graceInMinutes: current.graceInMinutes,
                  todayCheckInAt: todayCheckIn,
                  hasPermit: current.hasTodayPermit,
                  permitMinutes: current.todayPermit?.permitMinutes,
                  originalStartTime: current.startTime,
                );

                return _WorkShiftActiveCard(
                  current: current,
                  pending: pending,
                  shiftIcon: shiftIcon,
                  shiftColor: shiftColor,
                  liveStatus: liveStatus,
                  disciplineMetric: disciplineMetric,
                  scheme: scheme,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
/// عرض نافذة منبثقة تشرح سياسة احتساب الحضور والتأخير بناءً على الوردية
void _showShiftPolicyDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          Icon(Icons.policy_rounded, color: Theme.of(ctx).colorScheme.primary),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'سياسة فترات العمل والتأخير',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      content: const SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _PolicyPoint(
              number: '1',
              title: 'الوردية المعتمدة رسمياً',
              body: 'تحدد مواعيد الحضور والانصراف المقررة لك، ويتم تطبيق السياسة الفردية بناءً عليها.',
            ),
            SizedBox(height: 10),
            _PolicyPoint(
              number: '2',
              title: 'فترة السماح (15 دقيقة)',
              body: 'لا يُحتسب أي تأخير أو خصم إذا سجّلت حضورك خلال فترة السماح (مثلاً حتى 10:15 ص للدوام الأساسي).',
            ),
            SizedBox(height: 10),
            _PolicyPoint(
              number: '3',
              title: 'احتساب التأخير الفردي',
              body: 'عند تجاوز فترة السماح، يُحتسب إجمالي دقائق التأخير بدءاً من موعد بداية الوردية الرسمي (مثلاً من 10:00 ص).',
            ),
            SizedBox(height: 10),
            _PolicyPoint(
              number: '4',
              title: 'تغيير فترة العمل',
              body: 'يمكنك اختيار فترة عمل بديلة وتقديم طلب مبرر، وتُطبق المواعيد الجديدة فور اعتمادها من الإدارة.',
            ),
            SizedBox(height: 10),
            _PolicyPoint(
              number: '5',
              title: 'أذونات الحضور والانصراف',
              body: 'أذونات التأخير المعتمدة تؤخر موعد الحضور الرسمي بمقدار مدة الإذن (مثلاً إذن ساعتان يؤخر الحضور من 11:00 ص إلى 1:00 م)، وتُطبق فترة السماح والخصومات الفردية بناءً على الموعد المصرح الجديد.',
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('حسناً، فهمت'),
        ),
      ],
    ),
  );
}

class _PolicyPoint extends StatelessWidget {
  const _PolicyPoint({
    required this.number,
    required this.title,
    required this.body,
  });

  final String number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: scheme.primary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ShiftDetailChip extends StatelessWidget {
  const _ShiftDetailChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

