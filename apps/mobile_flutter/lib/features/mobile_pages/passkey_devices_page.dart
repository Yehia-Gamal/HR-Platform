import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class PasskeyDevicesPage extends ConsumerStatefulWidget {
  const PasskeyDevicesPage({super.key});

  @override
  ConsumerState<PasskeyDevicesPage> createState() => _PasskeyDevicesPageState();
}

class _PasskeyDevicesPageState extends ConsumerState<PasskeyDevicesPage> {
  String? _workingId;
  bool _registering = false;
  bool _replacingDevice = false;

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(myPasskeysProvider);
    final hasActiveDevice = devices.asData?.value.any(
          (d) => d.status == 'active',
        ) ??
        false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('أجهزة البصمة الموثوقة'),
        actions: [
          if (hasActiveDevice)
            IconButton(
              onPressed: _replacingDevice ? null : _requestReplacement,
              tooltip: 'فقدت هاتفي — طلب استبدال',
              icon: const Icon(Icons.phonelink_erase_outlined),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _registering ? null : _register,
        icon: _registering
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add_moderator_outlined),
        label: const Text('تسجيل هذا الجهاز'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(myPasskeysProvider),
          child: devices.when(
            loading: () => ListView(
              children: [
                SizedBox(height: 260),
                Center(child: CircularProgressIndicator()),
              ],
            ),
            error: (error, _) => ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _InfoCard(
                  icon: Icons.error_outline,
                  title: 'تعذر تحميل الأجهزة',
                  body: 'تحقق من الاتصال وأعد المحاولة.',
                ),
              ],
            ),
            data: (items) => _body(items),
          ),
        ),
      ),
    );
  }

  Widget _body(List<PasskeyDevice> items) {
    if (items.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          _InfoCard(
            icon: Icons.phonelink_lock_outlined,
            title: 'لا توجد أجهزة مسجلة',
            body:
                'سجل هذا الهاتف لاستخدام قفل الشاشة أو البصمة في إثبات الحضور.',
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: items.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          return const _InfoCard(
            icon: Icons.security_outlined,
            title: 'إدارة آمنة للأجهزة',
            body:
                'ألغِ أي جهاز فقدته أو لم تعد تستخدمه. إلغاء الجهاز لا يكشف بيانات البصمة ولا يحذف سجل الحضور السابق.',
          );
        }
        final device = items[index - 1];
        return _DeviceCard(
          device: device,
          working: _workingId == device.id,
          onRevoke: device.status == 'active' ? () => _revoke(device) : null,
        );
      },
    );
  }

  Future<void> _register() async {
    setState(() => _registering = true);
      try {
      await ref.read(mobileCommandsProvider).registerPasskey();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(
          content: Text('تم تأمين الجهاز وتفعيله تلقائيًا'),
        ));
      }
    } catch (error) {
      if (mounted) {
        final msg = error.toString();
        final text = msg.contains('cancelled')
            ? 'تم إلغاء التحقق.'
            : msg.contains('الجهاز لا يدعم')
                ? 'فعّل قفل الشاشة (نقش أو PIN) من إعدادات الجهاز.'
                : 'تعذر تسجيل الجهاز. أعد المحاولة.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(text)));
      }
    } finally {
      if (mounted) setState(() => _registering = false);
    }
  }

  Future<void> _revoke(PasskeyDevice device) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إلغاء الجهاز الموثوق'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('سيتم منع ${device.deviceLabel} من إثبات الحضور مستقبلًا.'),
            const SizedBox(height: 14),
            TextField(
              controller: reasonController,
              maxLength: 240,
              decoration: const InputDecoration(
                labelText: 'سبب الإلغاء',
                hintText: 'مثال: تم تغيير الهاتف أو فقد الجهاز',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('تراجع'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إلغاء الجهاز'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      reasonController.dispose();
      return;
    }

    setState(() => _workingId = device.id);
    try {
      await ref
          .read(mobileCommandsProvider)
          .revokePasskey(device.id, reasonController.text);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم إلغاء الجهاز.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تعذر إلغاء الجهاز. أعد المحاولة.')));
      }
    } finally {
      reasonController.dispose();
      if (mounted) setState(() => _workingId = null);
    }
  }

  /// طلب استبدال الجهاز (هاتف مفقود)
  Future<void> _requestReplacement() async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.phonelink_erase_outlined, size: 40),
        title: const Text('طلب استبدال الجهاز'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'سيتم إلغاء جهازك النشط الحالي وتسجيل خروجك من جميع الجلسات. '
              'بعد ذلك يمكنك تسجيل جهاز جديد.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: reasonController,
              maxLength: 240,
              decoration: const InputDecoration(
                labelText: 'سبب الاستبدال',
                hintText: 'مثال: فقدت الهاتف أو تعطل الجهاز',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('تراجع'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إلغاء الجهاز وطلب استبدال'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      reasonController.dispose();
      return;
    }

    setState(() => _replacingDevice = true);
    try {
      await ref
          .read(mobileCommandsProvider)
          .requestDeviceReplacement(reasonController.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إلغاء الجهاز القديم. يمكنك الآن تسجيل جهاز جديد.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر طلب الاستبدال. أعد المحاولة.')),
        );
      }
    } finally {
      reasonController.dispose();
      if (mounted) setState(() => _replacingDevice = false);
    }
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.working,
    required this.onRevoke,
  });

  final PasskeyDevice device;
  final bool working;
  final VoidCallback? onRevoke;

  static const _revocationSourceLabels = <String, String>{
    'admin': 'إلغاء إداري',
    'employee': 'طلب الموظف',
    'replacement': 'استبدال بجهاز جديد',
  };

  /// أيقونة ولون ونص الحالة حسب status الجهاز.
  static ({IconData icon, Color color, String label}) _statusInfo(
    String status,
    BuildContext context,
  ) =>
      switch (status) {
        'pending' => (
          icon: Icons.hourglass_top_outlined,
          color: Colors.orange,
          label: 'ينتظر الموافقة',
        ),
        'active' => (
          icon: Icons.phonelink_lock,
          color: Colors.green,
          label: 'نشط',
        ),
        'blocked' => (
          icon: Icons.block_outlined,
          color: Colors.red,
          label: 'محظور',
        ),
        'revoked' => (
          icon: Icons.mobile_off_outlined,
          color: Colors.grey,
          label: 'ملغي',
        ),
        'replaced' => (
          icon: Icons.swap_horiz_outlined,
          color: Colors.grey,
          label: 'مُستبدَل',
        ),
        'auto_revoked' => (
          icon: Icons.warning_amber_outlined,
          color: Colors.orange,
          label: 'إلغاء تلقائي',
        ),
        _ => (
          icon: Icons.device_unknown_outlined,
          color: Colors.grey,
          label: status,
        ),
      };

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('d MMMM y، h:mm a', 'ar');
    final info = _statusInfo(device.status, context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: info.color.withValues(alpha: 0.15),
                  child: Icon(info.icon, color: info.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.deviceLabel,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        info.label,
                        style: TextStyle(color: info.color),
                      ),
                    ],
                  ),
                ),
                if (device.trusted)
                  const Tooltip(
                    message: 'موثوق من الخادم',
                    child: Icon(Icons.verified_user_outlined),
                  ),
              ],
            ),
            const Divider(height: 24),
            Text('أضيف: ${formatter.format(device.createdAt.toLocal())}'),
            if (device.approvedAt != null)
              Text(
                'وُوفق عليه: ${formatter.format(device.approvedAt!.toLocal())}',
              ),
            Text(
              device.lastUsedAt == null
                  ? 'لم يُستخدم بعد'
                  : 'آخر استخدام: ${formatter.format(device.lastUsedAt!.toLocal())}',
            ),
            if (device.revocationSource != null &&
                device.revocationSource!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 18, color: Colors.grey),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'سبب الإلغاء: ${_revocationSourceLabels[device.revocationSource] ?? device.revocationSource}',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),
            if (device.status == 'blocked' &&
                device.rejectionReason != null &&
                device.rejectionReason!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 18, color: Colors.red),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'سبب الحظر: ${device.rejectionReason}',
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            if (device.canResubmit && device.status == 'blocked')
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Icon(Icons.refresh_outlined, size: 18, color: Colors.blue),
                    const SizedBox(width: 6),
                    Text(
                      'يمكنك إعادة تسجيل جهاز جديد',
                      style: TextStyle(color: Colors.blue),
                    ),
                  ],
                ),
              ),
            if (device.backedUp)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('المفتاح مدعوم بواسطة مزود الجهاز'),
              ),
            if (onRevoke != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: working ? null : onRevoke,
                icon: working
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.block_outlined),
                label: const Text('إلغاء هذا الجهاز'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(body),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
