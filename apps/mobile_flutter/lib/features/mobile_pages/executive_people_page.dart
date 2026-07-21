import 'package:ahla_shabab_management_os/core/widgets/brand_logo.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_executive_insights_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_executive_insights_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_employee_summary_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ExecutivePeoplePage extends ConsumerStatefulWidget {
  const ExecutivePeoplePage({super.key});

  @override
  ConsumerState<ExecutivePeoplePage> createState() =>
      _ExecutivePeoplePageState();
}

class _ExecutivePeoplePageState extends ConsumerState<ExecutivePeoplePage> {
  final searchController = TextEditingController();
  String search = '';
  String filter = 'all';

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final people = ref.watch(mobileExecutivePeopleProvider(search));
    return Scaffold(
      appBar: AppBar(title: const Text('دليل الموظفين التنفيذي')),
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.invalidate(mobileExecutivePeopleProvider(search)),
        child: people.when(
          loading: () => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: 230),
              Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (error, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 72),
              const Center(child: BrandLogoMark()),
              const SizedBox(height: 20),
              Icon(
                Icons.groups_outlined,
                size: 52,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              const Text(
                'تعذر تحميل دليل الموظفين',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),
              Center(
                child: FilledButton.tonalIcon(
                  onPressed: () =>
                      ref.invalidate(mobileExecutivePeopleProvider(search)),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('إعادة المحاولة'),
                ),
              ),
            ],
          ),
          data: _content,
        ),
      ),
    );
  }

  Widget _content(List<ExecutivePersonItem> items) {
    final visible = items
        .where(
          (item) => switch (filter) {
            'attention' => item.pendingRequests > 0 || item.openTasks > 0,
            'late' => item.attendanceStatus == 'late',
            'absent' => item.attendanceStatus == 'absent',
            _ => true,
          },
        )
        .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 27,
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: Icon(
                  Icons.manage_search_rounded,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ملخص موظف يحترم الخصوصية',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'يعرض التنظيم والعمل والحضور المجمع فقط، دون حقول شخصية غير لازمة.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        MobileFilterBar(
          searchHint: 'ابحث بالاسم أو كود الموظف',
          controller: searchController,
          onSearchChanged: (value) => setState(() => search = value.trim()),
          options: const [
            MobileFilterOption('all', 'الكل'),
            MobileFilterOption('attention', 'تحتاج متابعة'),
            MobileFilterOption('late', 'متأخرون'),
            MobileFilterOption('absent', 'غائبون'),
          ],
          selected: filter,
          onSelected: (value) => setState(() => filter = value),
          resultLabel: '${visible.length} موظفًا',
          onClear: () {
            searchController.clear();
            setState(() {
              search = '';
              filter = 'all';
            });
          },
        ),
        const SizedBox(height: 9),
        if (visible.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(26),
              child: Column(
                children: [
                  Icon(Icons.search_off_rounded, size: 42),
                  SizedBox(height: 9),
                  Text('لا توجد نتائج مطابقة.'),
                ],
              ),
            ),
          )
        else
          ...visible.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PersonCard(
                item: item,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ExecutiveEmployeeSummaryPage(
                      employeeId: item.id,
                      employeeName: item.name,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.item, required this.onTap});

  final ExecutivePersonItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundImage: item.photoUrl == null
                      ? null
                      : NetworkImage(item.photoUrl!),
                  child: item.photoUrl == null
                      ? Text(item.name.substring(0, 1))
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        [item.jobTitle, item.employeeCode]
                            .where((value) => value != null && value.isNotEmpty)
                            .join(' · '),
                      ),
                      if (item.department != null)
                        Text(
                          item.department!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                MobileStatusPill(_attendancePillKey(item.attendanceStatus)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _mini('طلبات', item.pendingRequests.toString()),
                ),
                Expanded(child: _mini('مهام', item.openTasks.toString())),
                Expanded(
                  child: _mini(
                    'KPI',
                    item.latestKpiScore?.toStringAsFixed(1) ?? '—',
                  ),
                ),
                const Icon(Icons.chevron_left_rounded),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  static Widget _mini(String label, String value) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
      ),
      Text(label, style: const TextStyle(fontSize: 10)),
    ],
  );
}

String _attendancePillKey(String? status) => switch (status) {
  'present' || 'late' || 'absent' || 'on_leave' => status!,
  _ => 'unregistered',
};
