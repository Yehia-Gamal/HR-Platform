import 'package:ahla_shabab_management_os/features/mobile_data/mobile_operations_models.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_operations_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/disputes_portal_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_location_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_risk_center_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_action_inbox_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class ExecutiveEmergencyPage extends ConsumerWidget {
  const ExecutiveEmergencyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(executiveDashboardProvider);
    final center = ref.watch(mobileExecutiveCommandCenterProvider);
    final locations = ref.watch(locationDirectoryProvider(''));

    return Scaffold(
      appBar: AppBar(title: const Text('وضع الاستجابة السريعة')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(executiveDashboardProvider)
            ..invalidate(mobileExecutiveCommandCenterProvider)
            ..invalidate(locationDirectoryProvider(''));
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    Color.alphaBlend(
                      Colors.black.withValues(alpha: .45),
                      Theme.of(context).colorScheme.error,
                    ),
                    Theme.of(context).colorScheme.error,
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.emergency_rounded,
                        color: Colors.white,
                        semanticLabel: 'استجابة سريعة',
                      ),
                      SizedBox(width: 9),
                      Text(
                        'لوحة الاستجابة السريعة',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'الأحداث الحرجة والفرق والإجراءات في شاشة واحدة.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'أي طلب موقع أو تحقق يظل بحاجة سبب وصلاحية وموافقة الموظف وفق السياسة.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .75),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            dashboard.when(
              loading: () => const _LoadingCard(),
              error: (error, _) => _ErrorCard(message: humanizeError(error)),
              data: (item) => MetricGrid(
                cards: [
                  (
                    'إجراءات عاجلة',
                    item.urgentActions.toString(),
                    Icons.priority_high_rounded,
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const MobileActionInboxPage(),
                      ),
                    ),
                  ),
                  (
                    'قضايا مفتوحة',
                    item.openCases.toString(),
                    Icons.balance_rounded,
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const DisputesPortalPage(),
                      ),
                    ),
                  ),
                  (
                    'طلبات موقع نشطة',
                    item.activeLocationRequests.toString(),
                    Icons.location_searching_rounded,
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ExecutiveLocationPage(),
                      ),
                    ),
                  ),
                  (
                    'اعتمادات معلقة',
                    item.pendingApprovals.toString(),
                    Icons.approval_rounded,
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const MobileActionInboxPage(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const MobileSectionHeader(
              title: 'إجراءات فورية',
              subtitle: 'تفتح الوحدة الأصلية مع الحفاظ على ضوابطها ومصادقتها.',
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _QuickAction(
                    icon: Icons.inbox_outlined,
                    label: 'الوارد العاجل',
                    onTap: () => _open(
                      context,
                      'الإجراءات العاجلة',
                      const MobileActionInboxPage(),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: _QuickAction(
                    icon: Icons.shield_outlined,
                    label: 'المخاطر',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ExecutiveRiskCenterPage(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: _QuickAction(
                    icon: Icons.location_on_outlined,
                    label: 'الفرق والموقع',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ExecutiveLocationPage(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            center.when(
              loading: () => const _LoadingCard(),
              error: (error, _) => _ErrorCard(message: humanizeError(error)),
              data: (item) => _critical(context, item),
            ),
            const SizedBox(height: 20),
            const MobileSectionHeader(
              title: 'آخر إشارات الموقع المصرح بها',
              subtitle: 'لا يبدأ أي تتبع جديد من هذه البطاقة.',
            ),
            const SizedBox(height: 10),
            locations.when(
              loading: () => const _LoadingCard(),
              error: (error, _) => _ErrorCard(message: humanizeError(error)),
              data: (items) {
                final recent =
                    items
                        .where((item) => item.lastRecordedAt != null)
                        .toList(growable: false)
                      ..sort(
                        (a, b) =>
                            b.lastRecordedAt!.compareTo(a.lastRecordedAt!),
                      );
                if (recent.isEmpty) {
                  return const Card(
                    child: ListTile(
                      contentPadding: EdgeInsets.all(16),
                      leading: CircleAvatar(
                        child: Icon(Icons.location_off_outlined),
                      ),
                      title: Text(
                        'لا توجد إشارات موقع مصرح بها حاليًا.',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  );
                }
                return Card(
                  child: Column(
                    children: recent
                        .take(5)
                        .map(
                          (person) => ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            leading: const CircleAvatar(
                              child: Icon(Icons.location_on_outlined),
                            ),
                            title: Text(
                              person.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            subtitle: Text(person.department ?? '—'),
                            trailing: Text(
                              DateFormat(
                                'h:mm a',
                                'ar',
                              ).format(person.lastRecordedAt!.toLocal()),
                            ),
                          ),
                        )
                        .toList(growable: false),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _critical(BuildContext context, MobileExecutiveCommandCenter item) {
    final risks = item.risks
        .where((risk) => risk.severity == 'critical')
        .take(3);
    final incidents = item.incidents
        .where((incident) => incident.severity == 'critical')
        .take(3);
    final entries = <(String, String, IconData, VoidCallback?)>[
      ...incidents.map(
        (incident) => (
          incident.title,
          'حادث · ${_incidentStatus(incident.status)}',
          Icons.crisis_alert_rounded,
          null,
        ),
      ),
      ...risks.map(
        (risk) => (
          risk.title,
          'مخاطرة · ${risk.ownerName ?? 'غير مسندة'}',
          Icons.warning_amber_rounded,
          null,
        ),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MobileSectionHeader(
          title: 'الأحداث الحرجة الآن',
          subtitle: '${entries.length} عناصر حرجة ظاهرة في مركز القيادة.',
        ),
        const SizedBox(height: 10),
        if (entries.isEmpty)
          const Card(
            child: ListTile(
              contentPadding: EdgeInsets.all(16),
              leading: CircleAvatar(child: Icon(Icons.verified_rounded)),
              title: Text(
                'لا توجد أحداث حرجة مفتوحة',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          )
        else
          Card(
            child: Column(
              children: entries
                  .map(
                    (entry) => ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 5,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.errorContainer,
                        child: Icon(
                          entry.$3,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      title: Text(
                        entry.$1,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      subtitle: Text(entry.$2),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ExecutiveRiskCenterPage(),
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
      ],
    );
  }

  static void _open(BuildContext context, String title, Widget child) =>
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(title)),
            body: child,
          ),
        ),
      );

  static String _incidentStatus(String status) => switch (status) {
    'open' => 'مفتوح',
    'investigating' => 'قيد التحقيق',
    _ => status,
  };
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 15),
          child: Column(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 7),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(28),
      child: Center(child: CircularProgressIndicator()),
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text('تعذر تحميل الجزء: $message', textAlign: TextAlign.center),
    ),
  );
}
