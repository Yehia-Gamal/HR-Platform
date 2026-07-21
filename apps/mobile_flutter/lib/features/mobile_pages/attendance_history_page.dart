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
            loading: () => ListView(
              children: [
                SizedBox(height: 260),
                Center(child: CircularProgressIndicator()),
              ],
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
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) =>
                        _HistoryCard(item: items[index]),
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
    final mutedStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final formatter = DateFormat('EEEE، d MMMM y - h:mm a', 'ar');
    final checkIn = item.eventType == 'CHECK_IN';
    const checkInColor = Color(0xFF0F9F6E);
    final avatarColor = checkIn ? checkInColor : scheme.onSurfaceVariant;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Semantics(
          label: checkIn ? 'حضور' : 'انصراف',
          child: CircleAvatar(
            backgroundColor: avatarColor.withValues(alpha: .12),
            foregroundColor: avatarColor,
            child: Icon(checkIn ? Icons.login : Icons.logout),
          ),
        ),
        title: Text(
          checkIn ? 'تسجيل حضور' : 'تسجيل انصراف',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(formatter.format(item.eventAt.toLocal()), style: mutedStyle),
              const SizedBox(height: 6),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: MobileStatusPill(item.status),
              ),
              const SizedBox(height: 4),
              Text(
                'التحقق: ${_verification(item.verificationStatus)}',
                style: mutedStyle,
              ),
              if (item.lateMinutes > 0)
                Text('التأخير: ${item.lateMinutes} دقيقة', style: mutedStyle),
              if (item.accuracyMeters != null)
                Text(
                  'دقة الموقع: ${item.accuracyMeters!.round()} متر',
                  style: mutedStyle,
                ),
              if (item.status == 'accepted' && item.distanceMeters != null)
                Text(
                  'الموقع: داخل المجمع (${item.distanceMeters!.round()} متر من مركز النطاق)',
                  style: mutedStyle?.copyWith(color: checkInColor),
                ),
              if (item.requiresReview)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: MobileStatusPill('flagged'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _verification(String value) => switch (value) {
    'passkey_verified' => 'Passkey موثقة',
    'biometric_verified' => 'بيومتري موثق',
    'failed' => 'فشل التحقق',
    _ => 'غير موثق',
  };
}
