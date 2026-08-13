import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/employee_profile_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// إدارة الموظفين — دليل موظفين قابل للبحث والتصفية بالحالة، والضغط على
/// أي موظف يفتح ملفه الشامل (get_employee_360). كان سابقاً صفحة "ويب فقط".
class MobileEmployeesPage extends ConsumerStatefulWidget {
  const MobileEmployeesPage({super.key});

  @override
  ConsumerState<MobileEmployeesPage> createState() =>
      _MobileEmployeesPageState();
}

class _MobileEmployeesPageState extends ConsumerState<MobileEmployeesPage> {
  final _search = TextEditingController();
  String _query = '';
  String _status = 'all';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final employees = ref.watch(mobileEmployeesProvider((_query.trim(), _status)));
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة الموظفين')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(mobileEmployeesProvider((_query.trim(), _status))),
          child: employees.when(
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
                    onPressed: () => ref
                        .invalidate(mobileEmployeesProvider((_query.trim(), _status))),
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
            data: (data) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  MobileSectionHeader(
                    title: 'إدارة الموظفين',
                    subtitle: 'دليل الموظفين وحالة كل موظف، وافتح ملفه الشامل.',
                  ),
                  const SizedBox(height: 8),
                  MobileFilterBar(
                    searchHint: 'بحث بالاسم أو كود الموظف',
                    controller: _search,
                    onSearchChanged: (v) => setState(() => _query = v),
                    options: const [
                      MobileFilterOption('all', 'الكل'),
                      MobileFilterOption('active', 'نشط'),
                      MobileFilterOption('onboarding', 'قيد التهيئة'),
                      MobileFilterOption('invited', 'تمت الدعوة'),
                      MobileFilterOption('notice_period', 'فترة إخطار'),
                      MobileFilterOption('suspended', 'موقوف'),
                      MobileFilterOption('terminated', 'منتهي'),
                      MobileFilterOption('archived', 'مؤرشف'),
                    ],
                    selected: _status,
                    onSelected: (v) => setState(() => _status = v),
                    resultLabel: data.isEmpty
                        ? 'لا نتائج'
                        : '${data.length} موظف',
                  ),
                  const SizedBox(height: 8),
                  if (data.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: Text('لا يوجد موظفون مطابقون')),
                    )
                  else
                    ...data.map(
                      (employee) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _EmployeeCard(
                          employee: employee,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => EmployeeProfilePage(
                                  employeeId: employee.id,
                                  employeeName: employee.fullNameAr,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({required this.employee, required this.onTap});

  final MobileEmployeeSummary employee;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final orgInfo = [
      if (employee.jobTitle?.isNotEmpty ?? false) employee.jobTitle!,
      if (employee.department?.isNotEmpty ?? false) employee.department!,
      if (employee.team?.isNotEmpty ?? false) employee.team!,
    ].join(' — ');
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              AppAvatar(
                name: employee.fullNameAr,
                photoUrl: employee.photoUrl,
                radius: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employee.fullNameAr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (orgInfo.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        orgInfo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (employee.employeeCode != null) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _metaChip(
                            context,
                            icon: Icons.badge_outlined,
                            text: employee.employeeCode!,
                          ),
                          if (employee.branch?.isNotEmpty ?? false)
                            _metaChip(
                              context,
                              icon: Icons.location_on_outlined,
                              text: employee.branch!,
                            ),
                          MobileStatusPill(employee.status),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_left_rounded, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metaChip(
    BuildContext context, {
    required IconData icon,
    required String text,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 3),
            Text(
              text,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}
