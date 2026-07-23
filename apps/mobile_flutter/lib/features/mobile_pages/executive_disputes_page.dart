import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class ExecutiveDisputesPage extends ConsumerWidget {
  const ExecutiveDisputesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portal = ref.watch(myDisputePortalProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة الشكاوى والمشاكل')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myDisputePortalProvider),
        child: portal.when(
          loading: () => ListView(
            children: const [
              SizedBox(height: 240),
              Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (error, _) => ListView(
            children: [
              const SizedBox(height: 200),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      'تعذر تحميل القضايا',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: () => ref.invalidate(myDisputePortalProvider),
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          data: (portal) {
            final escalated = portal.cases
                .where((c) => c.status == 'escalated_to_executive')
                .toList();
            final pending = portal.cases
                .where((c) => c.status == 'decision_pending')
                .toList();
            final recent = portal.cases
                .where((c) =>
                    !['escalated_to_executive', 'decision_pending']
                        .contains(c.status))
                .toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (escalated.isNotEmpty) ...[
                  _SectionHeader(
                    title: 'قضايا مصعدة',
                    count: escalated.length,
                    color: Colors.redAccent,
                  ),
                  ...escalated.map((c) => _DisputeCard(
                    dispute: c,
                    onTap: () => _showDecisionDialog(context, ref, c),
                  )),
                  const SizedBox(height: 16),
                ],
                if (pending.isNotEmpty) ...[
                  _SectionHeader(
                    title: 'تتطلب قرارك',
                    count: pending.length,
                    color: Colors.orange,
                  ),
                  ...pending.map((c) => _DisputeCard(
                    dispute: c,
                    onTap: () => _showDecisionDialog(context, ref, c),
                  )),
                  const SizedBox(height: 16),
                ],
                if (recent.isNotEmpty) ...[
                  _SectionHeader(
                    title: 'قضايا سابقة',
                    count: recent.length,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  ...recent.map((c) => _DisputeCard(
                    dispute: c,
                    onTap: () => _showCaseDetail(context, c),
                  )),
                ],
                if (escalated.isEmpty && pending.isEmpty && recent.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.only(top: 120),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 64, color: Colors.green),
                          SizedBox(height: 16),
                          Text('لا توجد قضايا حالياً',
                              style: TextStyle(fontSize: 18)),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showDecisionDialog(
      BuildContext context, WidgetRef ref, MobileDisputeCase c) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('قرار للمشكلة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(c.description ?? '',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'قرار أو توجيه',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم تسجيل التوجيه')),
              );
            },
            child: const Text('اعتماد'),
          ),
        ],
      ),
    );
  }

  void _showCaseDetail(BuildContext context, MobileDisputeCase c) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(c.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow(context, 'الحالة', c.status),
              _detailRow(context, 'تاريخ الفتح',
                  DateFormat('d MMM y', 'ar').format(c.openedAt)),
              if (c.description != null) _detailRow(context, 'التفاصيل', c.description!),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            Text(value),
          ],
        ),
      );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.color,
  });
  final String title;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('$count',
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _DisputeCard extends StatelessWidget {
  const _DisputeCard({required this.dispute, required this.onTap});
  final MobileDisputeCase dispute;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isEscalated = dispute.status == 'escalated_to_executive';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isEscalated ? Colors.redAccent : Colors.orange,
          child: Icon(
            isEscalated ? Icons.arrow_upward : Icons.gavel,
            color: Colors.white,
            size: 20,
          ),
        ),
        title: Text(dispute.title,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          '${dispute.status} • ${DateFormat('d MMM', 'ar').format(dispute.openedAt)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: const Icon(Icons.chevron_left),
        onTap: onTap,
      ),
    );
  }
}
