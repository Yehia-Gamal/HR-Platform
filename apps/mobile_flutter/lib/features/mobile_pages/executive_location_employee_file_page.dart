import 'dart:async';

import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_employee_summary_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

/// ملف موقع موظف للمدير التنفيذي — يعرض آخر نقطة مسجّلة + سجلّ الأماكن
/// (نقاط الموقع) + سجلّ طلبات الموقع، مع زر عرض الخريطة لكل نقطة.
class ExecutiveLocationEmployeeFilePage extends ConsumerStatefulWidget {
  const ExecutiveLocationEmployeeFilePage({
    required this.employeeId,
    required this.employeeName,
    this.photoUrl,
    super.key,
  });

  final String employeeId;
  final String employeeName;
  final String? photoUrl;

  @override
  ConsumerState<ExecutiveLocationEmployeeFilePage> createState() =>
      _ExecutiveLocationEmployeeFilePageState();
}

class _ExecutiveLocationEmployeeFilePageState
    extends ConsumerState<ExecutiveLocationEmployeeFilePage> {
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
        setState(() {});
      }
    });
  }

  void _openMap(double lat, double lng) {
    launchUrl(
      Uri.parse('https://maps.google.com/?q=$lat,$lng'),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _sendRequest(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(mobileCommandsProvider)
          .requestLocation(widget.employeeId, 'تحقق ميداني');
      if (!mounted) return;
      _startCooldown();
      ref.invalidate(employeeLocationDossierProvider(widget.employeeId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم إرسال طلب الموقع إلى ${widget.employeeName} — سيتلقى إشعاراً فورياً.',
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

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(employeeLocationDossierProvider(widget.employeeId));
    return Scaffold(
      appBar: AppBar(title: Text(widget.employeeName)),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(employeeLocationDossierProvider(widget.employeeId));
            await Future<void>.delayed(const Duration(milliseconds: 300));
          },
          child: query.when(
            loading: () => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 200),
                // رأس فوري أثناء التحميل (الاسم والصورة المتوافران مسبقاً)
                _HeaderCard(
                  name: widget.employeeName,
                  photoUrl: widget.photoUrl,
                  subtitle: null,
                  status: null,
                ),
                const SizedBox(height: 260),
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('جارٍ تحميل سجلّ المواقع…'),
                  trailing: const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ],
            ),
            error: (error, _) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 40),
                Icon(
                  Icons.location_off_rounded,
                  size: 52,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 12),
                Text(humanizeError(error), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                Center(
                  child: FilledButton.tonalIcon(
                    onPressed: () => ref.invalidate(
                      employeeLocationDossierProvider(widget.employeeId),
                    ),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('إعادة المحاولة'),
                  ),
                ),
              ],
            ),
            data: (dossier) => _content(context, ref, dossier),
          ),
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    WidgetRef ref,
    ExecutiveEmployeeLocationDossier dossier,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final f = DateFormat('d MMM - h:mm a', 'ar');
    final emp = dossier.employee;
    final inCooldown = _lastRequestedAt != null;
    final cooldownRemaining = inCooldown
        ? 30 - DateTime.now().difference(_lastRequestedAt!).inSeconds
        : 0;
    final last = dossier.lastPoint;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _HeaderCard(
          name: emp.name,
          photoUrl: emp.photoUrl,
          subtitle: [
            emp.employeeCode,
            emp.jobTitle,
            emp.department,
          ].whereType<String>().join(' · '),
          status: emp.status,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: inCooldown || !mounted
                    ? null
                    : () => _sendRequest(context, ref),
                icon: const Icon(Icons.location_on_rounded),
                label: Text(
                  inCooldown
                      ? 'انتظر $cooldownRemaining ثانية'
                      : 'طلب موقع الآن',
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (last?.hasCoordinates ?? false)
              FilledButton.tonalIcon(
                onPressed: () => _openMap(last!.latitude!, last.longitude!),
                icon: const Icon(Icons.map_rounded, size: 18),
                label: const Text('افتح الخريطة'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ExecutiveEmployeeSummaryPage(
                employeeId: emp.id,
                employeeName: emp.name,
              ),
            ),
          ),
          icon: const Icon(Icons.badge_outlined),
          label: const Text('الملف الكامل للموظف'),
        ),
        const SizedBox(height: 18),
        const MobileSectionHeader(
          title: 'آخر نقطة مسجّلة',
          subtitle: 'أحدث موقع أرسله الموظف عبر التطبيق.',
        ),
        const SizedBox(height: 10),
        if (last == null)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(22),
              child: Center(child: Text('لا يوجد موقع مسجّل لهذا الموظف بعد.')),
            ),
          )
        else ...[
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 6,
              ),
              leading: const CircleAvatar(
                child: Icon(Icons.my_location_rounded),
              ),
              title: Text(
                last.addressAr?.isNotEmpty == true
                    ? last.addressAr!
                    : last.latitude != null && last.longitude != null
                    ? '${last.latitude!.toStringAsFixed(5)}, ${last.longitude!.toStringAsFixed(5)}'
                    : 'بدون إحداثيات',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                [
                  if (last.recordedAt != null)
                    f.format(last.recordedAt!.toLocal()),
                  if (last.accuracy != null)
                    'دقة ${last.accuracy!.round()} متر',
                  if (last.isMock) 'بيانات محاكاة',
                ].join(' · '),
              ),
              trailing: last.hasCoordinates
                  ? IconButton.filledTonal(
                      tooltip: 'عرض الخريطة',
                      icon: const Icon(Icons.map_rounded),
                      onPressed: () =>
                          _openMap(last.latitude!, last.longitude!),
                    )
                  : null,
            ),
          ),
        ],
        const SizedBox(height: 18),
        const MobileSectionHeader(
          title: 'الأماكن والمواقع الحديثة',
          subtitle:
              'سجلّ نقاط الموقع التي تواجد فيها الموظف — اضغط أيقونة الخريطة للعرض.',
        ),
        const SizedBox(height: 10),
        if (dossier.points.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(22),
              child: Center(child: Text('لا توجد نقاط موقع في السجل.')),
            ),
          )
        else
          Card(
            child: Column(
              children: dossier.points
                  .map(
                    (p) => _PointTile(
                      point: p,
                      onOpenMap: p.hasCoordinates
                          ? () => _openMap(p.latitude!, p.longitude!)
                          : null,
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        const SizedBox(height: 18),
        const MobileSectionHeader(
          title: 'طلبات الموقع',
          subtitle: 'سجلّ طلبات إرسال الموقع الموجهة لهذا الموظف.',
        ),
        const SizedBox(height: 10),
        if (dossier.requests.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(22),
              child: Center(child: Text('لا توجد طلبات موقع لهذا الموظف.')),
            ),
          )
        else
          Card(
            child: Column(
              children: dossier.requests
                  .map(
                    (r) => ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: scheme.primary.withValues(alpha: .1),
                        child: Icon(
                          r.status == 'pending'
                              ? Icons.hourglass_top_rounded
                              : Icons.location_on_outlined,
                          color: scheme.primary,
                        ),
                      ),
                      title: Text(
                        r.reason?.isNotEmpty == true ? r.reason! : 'طلب موقع',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        [
                          if (r.requestedAt != null)
                            f.format(r.requestedAt!.toLocal()),
                          if (r.requestedByName?.isNotEmpty == true)
                            'من ${r.requestedByName}',
                          if (r.pointCount > 0) '${r.pointCount} نقاط',
                        ].join(' · '),
                      ),
                      trailing: MobileStatusPill(r.status),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
      ],
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.name,
    required this.photoUrl,
    required this.subtitle,
    required this.status,
  });

  final String name;
  final String? photoUrl;
  final String? subtitle;
  final String? status;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            AppAvatar(name: name, photoUrl: photoUrl, radius: 30),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (subtitle?.isNotEmpty == true) Text(subtitle!),
                ],
              ),
            ),
            if (status != null) MobileStatusPill(status!),
          ],
        ),
      ),
    );
  }
}

class _PointTile extends StatelessWidget {
  const _PointTile({required this.point, required this.onOpenMap});

  final EmployeeLocationPoint point;
  final VoidCallback? onOpenMap;

  @override
  Widget build(BuildContext context) {
    final f = DateFormat('d MMM - h:mm a', 'ar');
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      leading: const CircleAvatar(
        radius: 16,
        child: Icon(Icons.place_outlined, size: 18),
      ),
      title: Text(
        point.addressAr?.isNotEmpty == true
            ? point.addressAr!
            : point.latitude != null && point.longitude != null
            ? '${point.latitude!.toStringAsFixed(5)}, ${point.longitude!.toStringAsFixed(5)}'
            : 'نقطة موقع',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
      subtitle: Text(
        [
          if (point.recordedAt != null) f.format(point.recordedAt!.toLocal()),
          if (point.accuracy != null) 'دقة ${point.accuracy!.round()} م',
          if (point.isMock) 'محاكاة',
          if (point.requestMode != null &&
              point.requestMode!.startsWith('track_'))
            'تتبّع',
        ].join(' · '),
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: onOpenMap == null
          ? null
          : IconButton.filledTonal(
              tooltip: 'عرض الخريطة',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.map_rounded, size: 18),
              onPressed: onOpenMap,
            ),
    );
  }
}
