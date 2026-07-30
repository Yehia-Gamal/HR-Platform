import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// ---------------------------------------------------------------------------
// تفضيلات الإشعارات — تحكم المستخدم بأنواع الإشعارات التي يريد استقبالها.
//
// القنوات:
//   requests   — إشعارات الطلبات والاعتمادات
//   kpi        — إشعارات تقييم الأداء KPI
//   attendance — إشعارات الحضور والغياب
//   alerts     — التنبيهات العاجلة (موقع، حالات طوارئ)
//   general    — الإشعارات العامة (تعاميم، قرارات، أخرى)
// ---------------------------------------------------------------------------

const _storageKeyPrefix = 'ahla_notif_pref_';
const _storage = FlutterSecureStorage();

/// قنوات الإشعارات المتاحة للتحكم.
enum NotificationChannel {
  requests('requests', 'الطلبات والاعتمادات', Icons.approval_outlined),
  kpi('kpi', 'تقييم الأداء', Icons.trending_up_rounded),
  attendance('attendance', 'الحضور والغياب', Icons.access_time_rounded),
  alerts('alerts', 'التنبيهات العاجلة', Icons.warning_amber_rounded),
  general('general', 'إشعارات عامة', Icons.notifications_outlined);

  const NotificationChannel(this.key, this.label, this.icon);

  /// مفتاح التخزين الفريد.
  final String key;

  /// التسمية بالعربية للعرض في الواجهة.
  final String label;

  /// أيقونة القناة.
  final IconData icon;
}

/// حالة تفضيلات الإشعارات — خريطة من القناة إلى تفعيل/تعطيل.
typedef NotificationPreferencesState = Map<NotificationChannel, bool>;

/// مزوّد تفضيلات الإشعارات.
///
/// يستخدم [Notifier] + [FlutterSecureStorage] لحفظ الإعدادات محلياً.
/// جميع القنوات مفعّلة افتراضياً عند أول استخدام.
final notificationPreferencesProvider = NotifierProvider<
    NotificationPreferencesController, NotificationPreferencesState>(
  NotificationPreferencesController.new,
);

class NotificationPreferencesController
    extends Notifier<NotificationPreferencesState> {
  @override
  NotificationPreferencesState build() {
    // تحميل القيم المحفوظة بشكل غير متزامن ثم تحديث الحالة.
    _loadSaved();
    // الحالة الأولية: جميع القنوات مفعّلة.
    return {for (final ch in NotificationChannel.values) ch: true};
  }

  Future<void> _loadSaved() async {
    final loaded = <NotificationChannel, bool>{};
    for (final ch in NotificationChannel.values) {
      try {
        final value = await _storage.read(key: '$_storageKeyPrefix${ch.key}');
        loaded[ch] = value != 'false'; // مفعّل افتراضياً.
      } catch (_) {
        loaded[ch] = true;
      }
    }
    state = loaded;
  }

  /// تبديل حالة قناة (تفعيل ↔ تعطيل).
  Future<void> toggle(NotificationChannel channel) async {
    final current = state[channel] ?? true;
    final updated = !current;
    state = {...state, channel: updated};
    try {
      await _storage.write(
        key: '$_storageKeyPrefix${channel.key}',
        value: updated.toString(),
      );
    } catch (_) {
      // الإعداد يبقى في الذاكرة حتى لو فشل التخزين.
    }
  }

  /// تعيين حالة قناة محددة.
  Future<void> setEnabled(NotificationChannel channel, bool enabled) async {
    if (state[channel] == enabled) return;
    state = {...state, channel: enabled};
    try {
      await _storage.write(
        key: '$_storageKeyPrefix${channel.key}',
        value: enabled.toString(),
      );
    } catch (_) {
      // الإعداد يبقى في الذاكرة.
    }
  }

  /// هل قناة معينة مفعّلة؟
  bool isEnabled(NotificationChannel channel) => state[channel] ?? true;

  /// تفعيل جميع القنوات.
  Future<void> enableAll() async {
    state = {for (final ch in NotificationChannel.values) ch: true};
    for (final ch in NotificationChannel.values) {
      try {
        await _storage.write(
          key: '$_storageKeyPrefix${ch.key}',
          value: 'true',
        );
      } catch (_) {}
    }
  }
}

// ---------------------------------------------------------------------------
// بطاقة واجهة المستخدم — مفاتيح تبديل قنوات الإشعارات.
// ---------------------------------------------------------------------------

/// بطاقة إعدادات الإشعارات — تعرض مفاتيح تبديل لكل قناة.
///
/// استخدام:
/// ```dart
/// const NotificationPreferencesCard()
/// ```
class NotificationPreferencesCard extends ConsumerWidget {
  const NotificationPreferencesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(notificationPreferencesProvider);
    final controller =
        ref.read(notificationPreferencesProvider.notifier);
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'تفضيلات الإشعارات',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'تحكّم بأنواع الإشعارات التي تصلك.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 4),
            ...NotificationChannel.values.map((channel) {
              final enabled = prefs[channel] ?? true;
              return SwitchListTile(
                secondary: Icon(channel.icon),
                title: Text(
                  channel.label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: _channelDescription(channel) != null
                    ? Text(
                        _channelDescription(channel)!,
                        style: theme.textTheme.bodySmall,
                      )
                    : null,
                value: enabled,
                onChanged: (_) => controller.toggle(channel),
              );
            }),
          ],
        ),
      ),
    );
  }

  String? _channelDescription(NotificationChannel channel) => switch (channel) {
    NotificationChannel.requests =>
      'إشعار عند تقديم طلب أو صدور قرار',
    NotificationChannel.kpi =>
      'إشعار عند بدء تقييم أو تحديث أداء',
    NotificationChannel.attendance =>
      'تنبيهات الحضور والغياب والتأخر',
    NotificationChannel.alerts =>
      'طلبات الموقع العاجلة وحالات الطوارئ',
    NotificationChannel.general =>
      'التعاميم والقرارات والإشعارات الأخرى',
  };
}
