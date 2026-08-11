import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// دليل موظفين موحد بخاصية البحث الحي — متاح لجميع الأدوار.
class MobileDirectorySearchPage extends ConsumerStatefulWidget {
  const MobileDirectorySearchPage({super.key});

  @override
  ConsumerState<MobileDirectorySearchPage> createState() =>
      _MobileDirectorySearchPageState();
}

class _MobileDirectorySearchPageState
    extends ConsumerState<MobileDirectorySearchPage> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(employeeDirectoryProvider(_query));
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'ابحث بالاسم أو الكود أو الإدارة…',
            border: InputBorder.none,
          ),
          onChanged: (value) =>
              setState(() => _query = value.trim()),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'مسح البحث',
              onPressed: () {
                _controller.clear();
                setState(() => _query = '');
              },
            ),
        ],
      ),
      body: results.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.search_off_rounded, size: 48),
                const SizedBox(height: 12),
                const Text(
                  'تعذر تحميل الدليل',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () =>
                      ref.invalidate(employeeDirectoryProvider(_query)),
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
        ),
        data: (items) {
          if (_query.isEmpty) {
            return const _EmptyPrompt();
          }
          if (items.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_search_outlined, size: 52),
                  SizedBox(height: 10),
                  Text('لا توجد نتائج مطابقة.'),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) =>
                _DirectoryTile(employee: items[index]),
          );
        },
      ),
    );
  }
}

class _EmptyPrompt extends StatelessWidget {
  const _EmptyPrompt();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.manage_search_rounded,
          size: 64,
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
        ),
        const SizedBox(height: 14),
        Text(
          'ابحث عن موظف بالاسم أو الكود أو الإدارة',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

class _DirectoryTile extends StatelessWidget {
  const _DirectoryTile({required this.employee});

  final DirectoryEmployee employee;

  @override
  Widget build(BuildContext context) {
    final sub = [employee.jobTitle, employee.department]
        .where((s) => s != null && s.isNotEmpty)
        .join(' · ');
    return ListTile(
      leading: AppAvatar(
        name: employee.name,
        photoUrl: employee.photoUrl,
        radius: 22,
      ),
      title: Text(
        employee.name,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: sub.isNotEmpty ? Text(sub) : null,
      trailing: employee.employeeCode != null
          ? Text(
              employee.employeeCode!,
              style: Theme.of(context).textTheme.bodySmall,
            )
          : null,
    );
  }
}
