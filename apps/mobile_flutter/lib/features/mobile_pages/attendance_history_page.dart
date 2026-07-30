import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class AttendanceHistoryPage extends ConsumerWidget {
  const AttendanceHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(myAttendanceHistoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('سجل الحضور والانصراف')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(myAttendanceHistoryProvider),
          child: history.when(
            loading: () => LayoutBuilder(
              builder: (context, constraints) => ListView(
                children: [
                  SizedBox(
                    height: constraints.maxHeight,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ],
              ),
            ),
            error: (error, _) => ListView(
              padding: const EdgeInsets.all(20),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 40,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          humanizeError(error),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () =>
                              ref.invalidate(myAttendanceHistoryProvider),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            data: (items) => items.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(20),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            children: [
                              Icon(
                                Icons.history_toggle_off,
                                size: 46,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'لا توجد عمليات حضور حتى الآن',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 16,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'آخر ${items.length} عملية مسجلة',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        );
                      }
                      return _HistoryCard(item: items[index - 1]);
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.item});

  final AttendanceHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mutedStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final dateFormatter = DateFormat('d MMM', 'ar');
    final timeFormatter = DateFormat('h:mm a', 'ar');
    final local = item.eventAt.toLocal();
    final checkIn = item.eventType == 'CHECK_IN';
    const checkInColor = Color(0xFF0F9F6E);
    final accentColor = checkIn ? checkInColor : scheme.onSurfaceVariant;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── السطر الأول: نوع العملية + الحالة ──
            Row(
              children: [
                // أيقونة صغيرة
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    checkIn ? Icons.login : Icons.logout,
                    size: 18,
                    color: accentColor,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        checkIn ? 'تسجيل حضور' : 'تسجيل انصراف',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        '${dateFormatter.format(local)} · ${timeFormatter.format(local)}',
                        style: mutedStyle,
                      ),
                    ],
                  ),
                ),
                MobileStatusPill(item.status),
              ],
            ),
            const SizedBox(height: 10),

            // ── السطر الثاني: شرائح التفاصيل ──
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                // التحقق
                _MiniChip(
                  icon: _verificationIcon(item.verificationStatus),
                  label: _verificationLabel(item.verificationStatus),
                  color: _verificationColor(item.verificationStatus, scheme),
                ),
                // التأخير
                if (item.lateMinutes > 0)
                  _MiniChip(
                    icon: Icons.schedule,
                    label: 'تأخير ${item.lateMinutes} د',
                    color: const Color(0xFFF59E0B),
                  ),
                // دقة الموقع
                if (item.accuracyMeters != null)
                  _MiniChip(
                    icon: Icons.gps_fixed,
                    label: '${item.accuracyMeters!.round()} م',
                    color: scheme.onSurfaceVariant,
                  ),
                // المسافة من المركز (فقط للمقبولة)
                if (item.status == 'accepted' && item.distanceMeters != null)
                  _MiniChip(
                    icon: Icons.near_me,
                    label: '${item.distanceMeters!.round()} م من المركز',
                    color: checkInColor,
                  ),
                // يحتاج مراجعة
                if (item.requiresReview)
                  _MiniChip(
                    icon: Icons.flag_outlined,
                    label: 'يحتاج مراجعة',
                    color: scheme.error,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _verificationIcon(String value) => switch (value) {
    'passkey_verified' => Icons.key,
    'biometric_verified' => Icons.fingerprint,
    'failed' => Icons.close,
    _ => Icons.help_outline,
  };

  String _verificationLabel(String value) => switch (value) {
    'passkey_verified' => 'مفتاح المرور',
    'biometric_verified' => 'بيومتري',
    'failed' => 'فشل التحقق',
    _ => 'غير موثق',
  };

  Color _verificationColor(String value, ColorScheme scheme) => switch (value) {
    'passkey_verified' || 'biometric_verified' => const Color(0xFF0F9F6E),
    'failed' => scheme.error,
    _ => scheme.onSurfaceVariant,
  };
}

/// شريحة معلومات صغيرة (أيقونة + نص)
class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.icon,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    ),
  );
}
