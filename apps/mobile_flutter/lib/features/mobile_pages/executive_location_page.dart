import 'dart:async';

import 'package:ahla_shabab_management_os/core/widgets/brand_logo.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_attendance_tab.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class ExecutiveLocationPage extends ConsumerStatefulWidget {
  const ExecutiveLocationPage({super.key});

  @override
  ConsumerState<ExecutiveLocationPage> createState() =>
      _ExecutiveLocationPageState();
}

class _ExecutiveLocationPageState extends ConsumerState<ExecutiveLocationPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final TextEditingController search = TextEditingController();
  Timer? debounce;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    search.dispose();
    debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Material wrapper يضمن وراثة الثيم الصحيحة داخل IndexedStack
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const BrandLogoMark(size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'المتابعة الميدانية',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TabBar(
                  controller: _tabs,
                  tabs: const [
                    Tab(
                      icon: Icon(Icons.people_alt_rounded),
                      text: 'حضور اليوم',
                    ),
                    Tab(
                      icon: Icon(Icons.location_searching_rounded),
                      text: 'طلب الموقع',
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                const ExecutiveAttendanceTab(),
                _LocationDirectoryTab(
                  search: search,
                  onDebounce: _scheduleDebounce,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _scheduleDebounce() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() {});
    });
  }
}

// ── تبويب دليل الموقع ─────────────────────────────────────────────────────
class _LocationDirectoryTab extends ConsumerWidget {
  const _LocationDirectoryTab({
    required this.search,
    required this.onDebounce,
  });
  final TextEditingController search;
  final VoidCallback onDebounce;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(locationDirectoryProvider(search.text.trim()));
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(locationDirectoryProvider),
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPad),
        children: [
          Text(
            'اطلب موقعاً حديثاً من أي موظف في الجمعية فوراً.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          MobileFilterBar(
            searchHint: 'بحث باسم الموظف أو الكود',
            controller: search,
            onSearchChanged: (_) => onDebounce(),
            options: const [],
            selected: '',
            onSelected: (_) {},
            resultLabel: '${query.value?.length ?? 0} موظف',
          ),
          const SizedBox(height: 16),
          query.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(30),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.all(30),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 40,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'تعذر تحميل الموظفين',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () => ref.invalidate(locationDirectoryProvider),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            ),
            data: (items) => items.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(30),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.location_off_rounded,
                            size: 40,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'لا يوجد موظفون',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  )
                : Column(
                    children: items
                        .map(
                          (employee) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _EmployeeLocationCard(employee: employee),
                          ),
                        )
                        .toList(growable: false),
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmployeeLocationCard extends ConsumerStatefulWidget {
  const _EmployeeLocationCard({required this.employee});
  final LocationDirectoryEmployee employee;

  @override
  ConsumerState<_EmployeeLocationCard> createState() => _EmployeeLocationCardState();
}

class _EmployeeLocationCardState extends ConsumerState<_EmployeeLocationCard> {
  DateTime? _lastRequestedAt;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    setState(() => _lastRequestedAt = DateTime.now());
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final elapsed = DateTime.now().difference(_lastRequestedAt!).inSeconds;
      if (elapsed >= 30) {
        timer.cancel();
        setState(() => _lastRequestedAt = null);
      } else {
        setState(() {}); // Update the cooldown text
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool inCooldown = _lastRequestedAt != null;
    final int cooldownRemaining = inCooldown 
        ? 30 - DateTime.now().difference(_lastRequestedAt!).inSeconds 
        : 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  child: ExcludeSemantics(
                    child: Text(
                      widget.employee.name.isEmpty
                          ? '؟'
                          : widget.employee.name.characters.first,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.employee.name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        [
                          widget.employee.employeeCode,
                          widget.employee.jobTitle,
                          widget.employee.department,
                        ].whereType<String>().join(' · '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (widget.employee.activeRequestStatus != null)
                  MobileStatusPill(widget.employee.activeRequestStatus!),
              ],
            ),
            if (widget.employee.lastRecordedAt != null) ...[
              const Divider(height: 26),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'آخر موقع: ${DateFormat('d MMM - h:mm a', 'ar').format(widget.employee.lastRecordedAt!.toLocal())}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          'دقة ${widget.employee.lastAccuracy?.round() ?? 0} متر',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // زر فتح خريطة Google Maps لموقع الموظف مباشرة
                  if (widget.employee.lastLatitude != null &&
                      widget.employee.lastLongitude != null)
                    FilledButton.tonalIcon(
                      onPressed: () => launchUrl(
                        Uri.parse(
                          'https://maps.google.com/?q=${widget.employee.lastLatitude},${widget.employee.lastLongitude}',
                        ),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.map_rounded, size: 18),
                      label: const Text('افتح الخريطة'),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: inCooldown ? null : () => _sendRequest(context, ref),
              icon: const Icon(Icons.videocam_rounded),
              label: Text(
                inCooldown
                    ? 'انتظر $cooldownRemaining ثانية'
                    : 'طلب موقع فوري',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendRequest(BuildContext context, WidgetRef ref) async {
    try {
      // يُلغي DB أي طلب نشط سابق تلقائياً (migration 0071)
      await ref.read(mobileCommandsProvider).requestLocation(
        widget.employee.id,
        'location_video',
        'تحقق ميداني',
      );
      _startCooldown();
      ref.invalidate(locationDirectoryProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم إرسال طلب الموقع لـ${widget.employee.name} — سيتلقى إشعاراً فورياً.',
            ),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر إرسال الطلب. تحقق من الاتصال وأعد المحاولة.')),
        );
      }
    }
  }
}
