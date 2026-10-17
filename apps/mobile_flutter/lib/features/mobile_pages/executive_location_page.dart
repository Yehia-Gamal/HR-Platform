import 'dart:async';

import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/core/widgets/phone_display.dart';
import 'package:ahla_shabab_management_os/core/formatting/arabic_text.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_location_employee_file_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:ahla_shabab_management_os/shared/hierarchy_sort.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

/// طلب الموقع من الموظفين — صفحة مستقلة بشريطها (تُفتح من ملف الموظف).
/// كانت تضم تبويب «حضور اليوم» نسخةً مكررة من تبويب الحضور، بعنوان ثالث فوقه.
class ExecutiveLocationPage extends StatelessWidget {
  const ExecutiveLocationPage({super.key});

  @override
  Widget build(BuildContext context) => const MobileSubpage(
    title: 'طلب الموقع',
    child: ExecutiveLocationRequestsView(),
  );
}

/// محتوى طلب الموقع (بلا Scaffold): بحث + طلب من الجميع + دليل الموظفين.
/// يُستخدم في تبويب «الموظفون» بالمساحة التنفيذية وفي [ExecutiveLocationPage].
class ExecutiveLocationRequestsView extends ConsumerStatefulWidget {
  const ExecutiveLocationRequestsView({super.key});

  @override
  ConsumerState<ExecutiveLocationRequestsView> createState() =>
      _ExecutiveLocationRequestsViewState();
}

class _ExecutiveLocationRequestsViewState
    extends ConsumerState<ExecutiveLocationRequestsView> {
  final TextEditingController search = TextEditingController();
  Timer? debounce;

  @override
  void dispose() {
    search.dispose();
    debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: _LocationDirectoryTab(search: search, onDebounce: _scheduleDebounce),
  );

  void _scheduleDebounce() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() {});
    });
  }
}

// ── تبويب دليل الموقع ─────────────────────────────────────────────────────
class _LocationDirectoryTab extends ConsumerWidget {
  const _LocationDirectoryTab({required this.search, required this.onDebounce});
  final TextEditingController search;
  final VoidCallback onDebounce;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final query = ref.watch(locationDirectoryProvider(search.text.trim()));
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final allItems = query.value ?? const <LocationDirectoryEmployee>[];
    // استبعاد تيم الطاقم الطبي للعيادات قطيعاً من طلب المواقع
    final eligibleItems = allItems
        .where((e) => !isClinicGirl(
              name: e.name,
              jobTitle: e.jobTitle,
              department: e.department,
            ))
        .toList(growable: false);
    // الترتيب بالهيكل الإداري المعتمد
    final sortedItems = sortByHierarchy<LocationDirectoryEmployee>(
      eligibleItems,
      (e) => e.jobTitle ?? '',
      (e) => e.name,
      getDepartment: (e) => e.department ?? '',
    );
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(locationDirectoryProvider),
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomPad),
        children: [
          // لوحة التتبع الميداني اللحظي مع زر الطلب الجماعي
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.satellite_alt_rounded,
                    color: scheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'التتبع الميداني اللحظي',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'طلب موقع فوري من عموم الميدان',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => _confirmBroadcast(context, ref),
                  icon: const Icon(Icons.campaign_rounded, size: 16),
                  label: const Text(
                    'طلب من الجميع',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: search,
            onChanged: (_) => onDebounce(),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'ابحث باسم الموظف أو القسم أو الكود',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: search.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        search.clear();
                        onDebounce();
                      },
                    )
                  : null,
              filled: true,
              fillColor: scheme.surfaceContainerLow,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                arEmployees(sortedItems.length),
                style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              if (query.isRefreshing)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 8),
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
                      onPressed: () =>
                          ref.invalidate(locationDirectoryProvider),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            ),
            data: (_) => sortedItems.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(30),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.location_off_rounded,
                            size: 40,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
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
                    children: sortedItems
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

  /// يطلب موقعاً فورياً من جميع الموظفين النشطين دفعة واحدة
  /// عبر request_live_location_broadcast (0491).
  Future<void> _confirmBroadcast(BuildContext context, WidgetRef ref) async {
    final reasonCtrl = TextEditingController(text: 'تحقق ميداني جماعي');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('طلب موقع من الجميع'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'سيُرسل طلب موقع فوري إلى كل الموظفين النشطين (باستثناء الطاقم الطبي للعيادات) ضمن نطاق صلاحيتك والذين لا يملكون طلباً معلقاً.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: reasonCtrl,
              maxLength: 60,
              maxLines: 1,
              decoration: const InputDecoration(
                labelText: 'سبب الطلب',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('إرسال للجميع'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final reason = reasonCtrl.text.trim();
    try {
      final created = await ref
          .read(mobileCommandsProvider)
          .requestLocationBroadcast(reason: reason);
      if (!context.mounted) return;
      ref.invalidate(locationDirectoryProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            created > 0
                ? 'تم إرسال طلب الموقع إلى $created موظف.'
                : 'لا يوجد موظفون متاحون للطلب حالياً.',
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        final msg = e.toString();
        final display = msg.contains('reason is required')
            ? 'السبب مطلوب — 5 أحرف على الأقل.'
            : msg.contains('live location request permission')
            ? 'لا تملك صلاحية طلب المواقع.'
            : 'تعذر إرسال الطلب الجماعي. تحقق من الاتصال.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(display)));
      }
    }
  }
}

class _EmployeeLocationCard extends ConsumerStatefulWidget {
  const _EmployeeLocationCard({required this.employee});
  final LocationDirectoryEmployee employee;

  @override
  ConsumerState<_EmployeeLocationCard> createState() =>
      _EmployeeLocationCardState();
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bool inCooldown = _lastRequestedAt != null;
    final int cooldownRemaining = inCooldown
        ? 30 - DateTime.now().difference(_lastRequestedAt!).inSeconds
        : 0;

    final rawCode = widget.employee.employeeCode;
    final cleanCode = (rawCode != null && rawCode.isNotEmpty)
        ? PhoneDisplay.stripCountryCode(rawCode)
        : null;
    final dept = widget.employee.department;
    final metaParts = [
      if (dept != null && dept.trim().isNotEmpty) dept.trim(),
      if (cleanCode != null && cleanCode.trim().isNotEmpty) 'كود: $cleanCode',
    ];

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => ExecutiveLocationEmployeeFilePage(
              employeeId: widget.employee.id,
              employeeName: widget.employee.name,
              photoUrl: widget.employee.photoUrl,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Employee row: Avatar + Name & Role + Status / Chevron
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  AppAvatar(
                    name: widget.employee.name,
                    photoUrl: widget.employee.photoUrl,
                    radius: 23,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.employee.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.employee.jobTitle != null &&
                            widget.employee.jobTitle!.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.employee.jobTitle!.trim(),
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: scheme.primary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (metaParts.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            metaParts.join(' · '),
                            style: TextStyle(
                              fontSize: 11.5,
                              color: scheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (widget.employee.activeRequestStatus != null)
                    MobileStatusPill(widget.employee.activeRequestStatus!)
                  else
                    Icon(
                      Icons.chevron_left_rounded,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                      size: 22,
                    ),
                ],
              ),

              // Location preview box (if recorded)
              if (widget.employee.lastRecordedAt != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.location_on_rounded,
                          size: 17,
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'آخر رصد: ${DateFormat('d MMMM · h:mm a', 'ar').format(widget.employee.lastRecordedAt!.toLocal())}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'الدقة: ${widget.employee.lastAccuracy?.round() ?? 0} متر',
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (widget.employee.lastLatitude != null &&
                          widget.employee.lastLongitude != null)
                        FilledButton.tonalIcon(
                          onPressed: () => launchUrl(
                            Uri.parse(
                              'https://maps.google.com/?q=${widget.employee.lastLatitude},${widget.employee.lastLongitude}',
                            ),
                            mode: LaunchMode.externalApplication,
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: const Icon(Icons.map_rounded, size: 15),
                          label: const Text(
                            'الخريطة',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],

              // Request location action
              const SizedBox(height: 12),
              SizedBox(
                height: 38,
                child: FilledButton.tonalIcon(
                  onPressed:
                      inCooldown ? null : () => _sendRequest(context, ref),
                  icon: Icon(
                    inCooldown
                        ? Icons.hourglass_top_rounded
                        : Icons.my_location_rounded,
                    size: 17,
                  ),
                  label: Text(
                    inCooldown
                        ? 'يرجى الانتظار ($cooldownRemaining ث)'
                        : 'طلب موقع فوري',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendRequest(BuildContext context, WidgetRef ref) async {
    try {
      // يُلغي DB أي طلب نشط سابق تلقائياً (migration 0071)
      await ref
          .read(mobileCommandsProvider)
          .requestLocation(widget.employee.id, 'تحقق ميداني');
      if (!mounted) return;
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
    } catch (e) {
      if (context.mounted) {
        final msg = e.toString();
        final display = msg.contains('cooldown_active')
            ? 'يرجى الانتظار 30 ثانية بين الطلبات.'
            : msg.contains('cannot request own location')
            ? 'لا يمكن طلب موقعك الخاص.'
            : msg.contains('not active')
            ? 'الموظف غير نشط أو لا يملك حساباً مرتبطاً.'
            : 'تعذر إرسال الطلب. تحقق من الاتصال وأعد المحاولة.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(display)));
      }
    }
  }
}
