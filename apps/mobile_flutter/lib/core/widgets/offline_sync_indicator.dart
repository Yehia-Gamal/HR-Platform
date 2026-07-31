import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/network/offline_sync_queue.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';

/// مؤشر صغير يعرض عدد العمليات المعلقة في طابور المزامنة.
/// عند الضغط يعرض BottomSheet بتفاصيل العمليات وزر مزامنة يدوية.
class OfflineSyncIndicator extends ConsumerStatefulWidget {
  const OfflineSyncIndicator({super.key});

  @override
  ConsumerState<OfflineSyncIndicator> createState() =>
      _OfflineSyncIndicatorState();
}

class _OfflineSyncIndicatorState extends ConsumerState<OfflineSyncIndicator> {
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    // تحميل العدد الأولي.
    OfflineSyncQueue.instance.initialize();
  }

  Future<void> _autoSync() async {
    final currentCount = await OfflineSyncQueue.instance.count;
    if (currentCount == 0) return;
    await _doSync();
  }

  Future<void> _doSync() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final client = ref.read(supabaseProvider);
      final succeeded = await OfflineSyncQueue.instance.processQueue(client);
      if (mounted && succeeded > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تمت مزامنة $succeeded عملية بنجاح'),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (_) {
      // فشل المزامنة — سيُعاد المحاولة لاحقاً.
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // مراقبة تغيير حالة الاتصال للمزامنة التلقائية.
    // ref.listen داخل build يُدار تلقائياً بواسطة Riverpod (بدون تكرار).
    ref.listen<ConnectivityState>(connectivityProvider, (prev, next) {
      if (prev == ConnectivityState.offline &&
          (next == ConnectivityState.reconnecting ||
              next == ConnectivityState.online)) {
        _autoSync();
      }
    });

    final asyncCount = ref.watch(syncQueueCountProvider);
    final count = asyncCount.value ?? 0;

    if (count == 0 && !_syncing) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => _showSyncSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _syncing ? Colors.orange.shade700 : Colors.red.shade700,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_syncing)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            else
              const Icon(Icons.sync_problem_rounded,
                  color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Text(
              _syncing ? 'جارٍ المزامنة...' : '$count معلّق',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSyncSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => _SyncQueueSheet(
        onSync: _doSync,
        syncing: _syncing,
      ),
    );
  }
}

class _SyncQueueSheet extends StatefulWidget {
  const _SyncQueueSheet({required this.onSync, required this.syncing});

  final Future<void> Function() onSync;
  final bool syncing;

  @override
  State<_SyncQueueSheet> createState() => _SyncQueueSheetState();
}

class _SyncQueueSheetState extends State<_SyncQueueSheet> {
  List<SyncQueueItem> _items = [];
  DateTime? _lastSync;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final items = await OfflineSyncQueue.instance.getAll();
    final lastSync = await OfflineSyncQueue.instance.lastSyncTime;
    if (mounted) {
      setState(() {
        _items = items;
        _lastSync = lastSync;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // مقبض السحب
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // العنوان
              Row(
                children: [
                  Icon(Icons.sync_rounded, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'طابور المزامنة',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (_lastSync != null)
                    Text(
                      'آخر مزامنة: ${_formatTime(_lastSync!)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // قائمة العمليات
              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.check_circle_outline_rounded,
                            color: Colors.green.shade600, size: 48),
                        const SizedBox(height: 8),
                        Text(
                          'لا توجد عمليات معلقة',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.4,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _items.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final item = _items[index];
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: item.retryCount > 2
                              ? Colors.red.shade100
                              : Colors.orange.shade100,
                          child: Icon(
                            item.retryCount > 2
                                ? Icons.error_outline_rounded
                                : Icons.schedule_rounded,
                            size: 18,
                            color: item.retryCount > 2
                                ? Colors.red.shade700
                                : Colors.orange.shade700,
                          ),
                        ),
                        title: Text(
                          item.actionLabel,
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(
                          'محاولة ${item.retryCount}/5 · ${_formatTime(DateTime.parse(item.createdAt).toLocal())}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 16),
              // زر المزامنة
              if (_items.isNotEmpty)
                FilledButton.icon(
                  onPressed: widget.syncing
                      ? null
                      : () async {
                          await widget.onSync();
                          await _loadData();
                        },
                  icon: widget.syncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.sync_rounded),
                  label: Text(
                      widget.syncing ? 'جارٍ المزامنة...' : 'مزامنة الآن'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final mo = local.month.toString().padLeft(2, '0');
    return '$h:$m · $d/$mo';
  }
}
