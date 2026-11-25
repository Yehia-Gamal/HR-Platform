part of '../my_instant_penalties_page.dart';

class _SuspendedEmployeesTab extends ConsumerWidget {
  const _SuspendedEmployeesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final suspendedAsync = ref.watch(suspendedEmployeesProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(suspendedEmployeesProvider);
        ref.invalidate(teamInstantPenaltiesProvider);
      },
      child: suspendedAsync.when(
        loading: () => const _Loading(),
        error: (error, _) => _ErrorView(
          message: humanizeError(error),
          onRetry: () => ref.invalidate(suspendedEmployeesProvider),
        ),
        data: (employees) {
          if (employees.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(32),
              children: [
                const SizedBox(height: 60),
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.statusSuccess.withValues(alpha: .12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle_rounded,
                      size: 40,
                      color: AppColors.statusSuccess,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'لا يوجد موظفون موقوفون عن العمل',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'كافة الحسابات نشطة ومستقرة، ولا توجد غرامات متجاوزة لمهلة الإيقاف حالياً.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            );
          }

          final totalCurrent = employees.fold<double>(
            0,
            (s, e) => s + e.totalCurrentDue,
          );
          final totalOriginal = employees.fold<double>(
            0,
            (s, e) => s + e.totalOriginalDue,
          );

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              16,
              14,
              16,
              MediaQuery.paddingOf(context).bottom + 24,
            ),
            children: [
              Card(
                color: AppColors.statusDanger.withValues(alpha: .08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: AppColors.statusDanger.withValues(alpha: .3),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.statusDanger.withValues(alpha: .15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.person_off_rounded,
                          color: AppColors.statusDanger,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${arEmployees(employees.length)} موقوفون عن العمل',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: AppColors.statusDanger,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'المطلوب بالمضاعفة: ${_money(totalCurrent)} (الأصل: ${_money(totalOriginal)})\nالسداد يرفع الإيقاف فوراً، أو يمكن إرجاع الغرامات للأصل أو رفع الإيقاف إدارياً.',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // زر رفع إيقاف جميع الموظفين دفعة واحدة
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _liftAllEmployeesSuspensionAdmin(
                    context,
                    ref,
                    employees.length,
                  ),
                  icon: const Icon(Icons.lock_open_rounded, size: 20),
                  label: Text(
                    'رفع إيقاف جميع الموظفين (${employees.length}) دفعة واحدة',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.2,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.statusSuccess,
                    foregroundColor: Colors.white,
                    elevation: 1,
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              for (final emp in employees) ...[
                _SuspendedEmployeeCard(emp: emp),
                const SizedBox(height: 10),
              ],
            ],
          );
        },
      ),
    );
  }
}

