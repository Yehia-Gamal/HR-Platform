import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_daily_reports_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class MobileTeamPage extends ConsumerStatefulWidget {
  const MobileTeamPage({super.key});

  @override
  ConsumerState<MobileTeamPage> createState() => _MobileTeamPageState();
}

class _MobileTeamPageState extends ConsumerState<MobileTeamPage> {
  final _searchController = TextEditingController();
  String _search = '';
  String _attendance = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final team = ref.watch(mobileTeamProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(mobileTeamProvider),
      child: team.when(
        loading: () => ListView(
          children: [
            const SizedBox(height: 220),
            const Center(child: CircularProgressIndicator(semanticsLabel: 'جاري التحميل')),
          ],
        ),
        error: (error, _) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 120),
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.error,
              semanticLabel: 'خطأ',
            ),
            const SizedBox(height: 12),
            Text(
              humanizeError(error),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () => ref.invalidate(mobileTeamProvider),
                child: const Text('إعادة المحاولة'),
              ),
            ),
          ],
        ),
        data: (items) {
          final visible = items.where(_matches).toList(growable: false);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              MobileFilterBar(
                searchHint: 'بحث باسم عضو الفريق أو الكود',
                controller: _searchController,
                onSearchChanged: (value) =>
                    setState(() => _search = value.trim().toLowerCase()),
                options: const [
                  MobileFilterOption('all', 'الكل'),
                  MobileFilterOption('present', 'حاضر'),
                  MobileFilterOption('late', 'متأخر'),
                  MobileFilterOption('mission', 'مأمورية'),
                  MobileFilterOption('absent', 'غائب'),
                ],
                selected: _attendance,
                onSelected: (value) => setState(() => _attendance = value),
                resultLabel: '${visible.length} من ${items.length} عضو',
                onClear: _search.isEmpty && _attendance == 'all'
                    ? null
                    : () {
                        _searchController.clear();
                        setState(() {
                          _search = '';
                          _attendance = 'all';
                        });
                      },
              ),
              const SizedBox(height: 12),
              if (visible.isEmpty) ...[
                const SizedBox(height: 100),
                Icon(
                  Icons.search_off_rounded,
                  size: 48,
                  semanticLabel: 'لا توجد نتائج',
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const Center(child: Text('لا يوجد أعضاء مطابقون للفلاتر')),
              ] else
                ...visible.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _MemberCard(item: item),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  bool _matches(MobileTeamMember item) {
    final haystack =
        '${item.name} ${item.employeeCode ?? ''} ${item.jobTitle ?? ''}'
            .toLowerCase();
    return (_search.isEmpty || haystack.contains(_search)) &&
        (_attendance == 'all' || item.attendanceStatus == _attendance);
  }
}

class _MemberCard extends ConsumerWidget {
  const _MemberCard({required this.item});

  final MobileTeamMember item;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
    child: ExpansionTile(
      leading: AppAvatar(name: item.name, photoUrl: item.photoUrl),
      title: Text(
        item.name,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      subtitle: Text(
        [item.jobTitle, item.employeeCode].whereType<String>().join(' • '),
      ),
      trailing: MobileStatusPill(item.attendanceStatus ?? 'unregistered'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        const Divider(),
        Row(
          children: [
            Expanded(
              child: _metric(
                context,
                'طلبات معلقة',
                item.pendingRequests.toString(),
              ),
            ),
            Expanded(
              child: _metric(context, 'مرحلة KPI', _stage(item.kpiStage)),
            ),
            Expanded(
              child: _metric(context, 'التأخير', '${item.lateMinutes} د'),
            ),
          ],
        ),
        if (item.firstCheckIn != null) ...[
          const SizedBox(height: 10),
          Text(
            'أول حضور اليوم: ${DateFormat('h:mm a', 'ar').format(item.firstCheckIn!.toLocal())}',
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MobileDailyReportsPage(
                      employeeId: item.id,
                      employeeName: item.name,
                    ),
                  ),
                ),
                icon: const Icon(Icons.summarize_outlined),
                label: const Text('التقارير'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _createTask(context, ref),
                icon: const Icon(Icons.add_task),
                label: const Text('إسناد مهمة'),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Future<void> _createTask(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();
    final description = TextEditingController();
    var priority = 'medium';
    DateTime? dueDate;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'إسناد مهمة إلى ${item.name}',
                style: Theme.of(
                  sheetContext,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: title,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'عنوان المهمة'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: description,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'التفاصيل'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: priority,
                decoration: const InputDecoration(labelText: 'الأولوية'),
                items: const [
                  DropdownMenuItem(value: 'low', child: Text('منخفضة')),
                  DropdownMenuItem(value: 'medium', child: Text('متوسطة')),
                  DropdownMenuItem(value: 'high', child: Text('مرتفعة')),
                  DropdownMenuItem(value: 'urgent', child: Text('عاجلة')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => priority = value);
                },
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: sheetContext,
                    initialDate: dueDate ?? DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) setState(() => dueDate = picked);
                },
                icon: const Icon(Icons.event_outlined),
                label: Text(
                  dueDate == null
                      ? 'تحديد موعد التسليم'
                      : DateFormat('d MMMM y', 'ar').format(dueDate!),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  if (title.text.trim().length < 3) {
                    ScaffoldMessenger.of(sheetContext).showSnackBar(
                      const SnackBar(content: Text('عنوان المهمة مطلوب.')),
                    );
                    return;
                  }
                  Navigator.pop(sheetContext, true);
                },
                child: const Text('إنشاء المهمة'),
              ),
            ],
          ),
        ),
      ),
    );

    final taskTitle = title.text.trim();
    final taskDescription = description.text.trim();
    title.dispose();
    description.dispose();
    if (confirmed != true) return;

    try {
      await ref
          .read(mobileCommandsProvider)
          .createTeamTask(
            employeeId: item.id,
            title: taskTitle,
            description: taskDescription,
            priority: priority,
            dueDate: dueDate,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إسناد المهمة للموظف.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(humanizeError(error))));
      }
    }
  }

  static Widget _metric(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  static String _stage(String? value) => switch (value) {
    'self' => 'ذاتي',
    'manager_review' => 'مراجعة المدير',
    'hr_review' => 'مراجعة HR',
    'parallel_review' => 'مراجعة متوازية',
    'secretary_review' => 'مراجعة السكرتارية',
    'executive_review' => 'المدير التنفيذي',
    'manager_final' => 'اعتماد المدير (قديم)',
    'finalized' => 'في التقرير',
    'closed' => 'مغلق',
    'archived' => 'مؤرشف',
    _ => '—',
  };
}
