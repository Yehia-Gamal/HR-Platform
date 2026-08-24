import 'package:ahla_shabab_management_os/core/notifications/notification_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// مركز تفضيلات الإشعارات (بند 8): كتم القنوات + ساعات الهدوء.
/// طلبات الموقع العاجلة مستثناة عمداً — إشعار أمان لا يُكتم.
class NotificationSettingsPage extends ConsumerStatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  ConsumerState<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState
    extends ConsumerState<NotificationSettingsPage> {
  NotificationPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    NotificationPreferences.load().then((value) {
      if (mounted) setState(() => _prefs = value);
    });
  }

  Future<void> _update(NotificationPreferences prefs) async {
    await prefs.save();
    if (mounted) setState(() => _prefs = prefs);
  }

  Future<void> _pickTime({required bool isStart}) async {
    final current = _prefs;
    if (current == null) return;
    final initialMinutes = isStart
        ? current.quietStartMinutes
        : current.quietEndMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: initialMinutes ~/ 60,
        minute: initialMinutes % 60,
      ),
    );
    if (picked == null) return;
    final minutes = picked.hour * 60 + picked.minute;
    await _update(
      isStart
          ? current.copyWith(quietStartMinutes: minutes)
          : current.copyWith(quietEndMinutes: minutes),
    );
  }

  String _formatMinutes(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final prefs = _prefs;

    if (prefs == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('تفضيلات الإشعارات')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('تفضيلات الإشعارات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: SwitchListTile(
              secondary: Icon(Icons.bedtime_outlined, color: scheme.primary),
              title: const Text(
                'ساعات الهدوء',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: const Text(
                'كتم الإشعارات المنبثقة خلال نطاق زمني محدد — '
                'وتبقى متاحة في صفحة الإشعارات.',
              ),
              value: prefs.quietHoursEnabled,
              onChanged: (value) =>
                  _update(prefs.copyWith(quietHoursEnabled: value)),
            ),
          ),
          if (prefs.quietHoursEnabled) ...[
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.nightlight_round),
                    title: const Text('من'),
                    trailing: TextButton(
                      onPressed: () => _pickTime(isStart: true),
                      child: Text(
                        _formatMinutes(prefs.quietStartMinutes),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.wb_sunny_outlined),
                    title: const Text('إلى'),
                    trailing: TextButton(
                      onPressed: () => _pickTime(isStart: false),
                      child: Text(
                        _formatMinutes(prefs.quietEndMinutes),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'القنوات المكتومة',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final entry
                    in NotificationPreferences.mutableChannels.entries) ...[
                  SwitchListTile(
                    title: Text(entry.value),
                    value: !prefs.isKindMuted(entry.key),
                    onChanged: (enabled) {
                      final muted = {...prefs.mutedKinds};
                      if (enabled) {
                        muted.remove(entry.key);
                      } else {
                        muted.add(entry.key);
                      }
                      _update(prefs.copyWith(mutedKinds: muted));
                    },
                  ),
                  if (entry.key !=
                      NotificationPreferences.mutableChannels.keys.last)
                    const Divider(height: 1, indent: 16, endIndent: 16),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Card(
            color: scheme.secondaryContainer.withValues(alpha: .45),
            child: ListTile(
              leading: Icon(Icons.emergency_rounded, color: scheme.secondary),
              title: const Text(
                'طلبات الموقع العاجلة',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: const Text(
                'إشعار أمان بشاشة كاملة — يتجاوز الكتم وساعات الهدوء دائماً.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
