import 'dart:io' show Platform;
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/widgets/brand_logo.dart';
import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/core/widgets/phone_display.dart';
import 'package:ahla_shabab_management_os/core/theme/theme_mode_controller.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/location_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/passkey_devices_page.dart';
import 'package:local_auth/local_auth.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MobileProfilePage extends ConsumerWidget {
  const MobileProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(mobileProfileProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('حسابي وملفي الوظيفي'),
        actions: const [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Center(child: BrandLogoMark(size: 34)),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(mobileProfileProvider),
        child: profile.when(
          loading: () => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(height: 220),
              Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (error, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 120),
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(humanizeError(error), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Center(
                child: FilledButton.icon(
                  onPressed: () => ref.invalidate(mobileProfileProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
              ),
            ],
          ),
          data: (item) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Header(item: item),
              const SizedBox(height: 14),
              _InfoSection(item: item),
              const SizedBox(height: 14),
              const _DeviceSecuritySection(),
              const SizedBox(height: 14),
              const _ThemePreferenceCard(),
              const SizedBox(height: 14),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.password_outlined),
                  title: const Text('تغيير الرقم السري'),
                  subtitle: const Text('تحديث بيانات الدخول الخاصة بك'),
                  trailing: const Icon(Icons.chevron_left_rounded),
                  onTap: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (context) => const _ChangePasswordDialog(),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _ShareLocationCard(),
              const SizedBox(height: 14),
              const _AppVersionCard(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemePreferenceCard extends ConsumerWidget {
  const _ThemePreferenceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'مظهر التطبيق',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'اختر المظهر أو اتركه متوافقًا مع إعداد الجهاز.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.brightness_auto_outlined),
                    label: Text('النظام'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode_outlined),
                    label: Text('فاتح'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode_outlined),
                    label: Text('داكن'),
                  ),
                ],
                selected: {mode},
                showSelectedIcon: false,
                onSelectionChanged: (selection) {
                  ref.read(themeModeProvider.notifier).setMode(selection.first);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends ConsumerStatefulWidget {
  const _Header({required this.item});
  final MobileProfile item;

  @override
  ConsumerState<_Header> createState() => _HeaderState();
}

class _HeaderState extends ConsumerState<_Header> {
  bool _isUploading = false;

  Future<void> _pickAndUploadPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 2048,
      maxHeight: 2048,
    );
    if (picked == null) return;

    setState(() => _isUploading = true);
    try {
      final originalBytes = await picked.readAsBytes();
      if (originalBytes.length > 5 * 1024 * 1024) {
        throw StateError('حجم الصورة أكبر من 5 ميجابايت.');
      }
      final sourceExt = picked.name.split('.').last.toLowerCase();
      if (!{'jpg', 'jpeg', 'png', 'webp'}.contains(sourceExt)) {
        throw StateError('الصيغة غير مدعومة. استخدم JPG أو PNG أو WEBP.');
      }
      final bytes = await _prepareSquareAvatar(originalBytes);
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final path = '$userId/avatar_${DateTime.now().millisecondsSinceEpoch}.png';
      final bucket = Supabase.instance.client.storage.from('employee-avatars');

      await bucket.uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(contentType: 'image/png', upsert: false),
      ).timeout(const Duration(seconds: 60));
      final rawUrl = bucket.getPublicUrl(path);

      await Supabase.instance.client.rpc("set_my_photo_url", params: {"p_photo_url": rawUrl}).timeout(const Duration(seconds: 20));
      final previousPath = _employeeAvatarPath(widget.item.photoUrl);
      if (previousPath != null && previousPath != path) {
        try {
          await bucket.remove([previousPath]);
        } catch (_) {
          // The new photo is already active; cleanup can be retried later.
        }
      }
      ref.invalidate(mobileProfileProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث الصورة بنجاح')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(humanizeError(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<Uint8List> _prepareSquareAvatar(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    final source = frame.image;
    try {
      if (source.width < 512 || source.height < 512) {
        throw StateError('دقة الصورة منخفضة. استخدم صورة لا تقل عن 512×512 بكسل.');
      }
      final sourceEdge = source.width < source.height
          ? source.width.toDouble()
          : source.height.toDouble();
      final outputEdge = sourceEdge > 1024 ? 1024 : sourceEdge.round();
      final sourceRect = ui.Rect.fromLTWH(
        (source.width - sourceEdge) / 2,
        (source.height - sourceEdge) / 2,
        sourceEdge,
        sourceEdge,
      );
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImageRect(
        source,
        sourceRect,
        ui.Rect.fromLTWH(0, 0, outputEdge.toDouble(), outputEdge.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      final picture = recorder.endRecording();
      final output = await picture.toImage(outputEdge, outputEdge);
      picture.dispose();
      try {
        final data = await output.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw StateError('تعذر تجهيز الصورة.');
        final result = data.buffer.asUint8List();
        if (result.length > 5 * 1024 * 1024) {
          throw StateError('تعذر ضغط الصورة إلى أقل من 5 ميجابايت.');
        }
        return result;
      } finally {
        output.dispose();
      }
    } finally {
      source.dispose();
    }
  }

  String? _employeeAvatarPath(String? url) {
    if (url == null || url.isEmpty) return null;
    for (final marker in [
      '/storage/v1/object/public/employee-avatars/',
      '/storage/v1/object/authenticated/employee-avatars/',
    ]) {
      final index = url.indexOf(marker);
      if (index < 0) continue;
      final raw = url.substring(index + marker.length).split('?').first;
      try {
        return Uri.decodeComponent(raw);
      } catch (_) {
        return raw;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Semantics(
            button: true,
            enabled: !_isUploading,
            label: 'تغيير الصورة الشخصية',
            child: GestureDetector(
              onTap: _isUploading ? null : _pickAndUploadPhoto,
              child: Stack(
              children: [
                AppAvatar(
                  name: widget.item.fullNameAr,
                  photoUrl: widget.item.photoUrl,
                  radius: 36,
                ),
                if (_isUploading)
                  const Positioned.fill(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  PositionedDirectional(
                    bottom: 0,
                    end: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.camera_alt,
                        size: 14,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ),
              ],
            ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.item.fullNameAr,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (widget.item.jobTitle != null) Text(widget.item.jobTitle!),
                Text(
                  widget.item.employeeCode,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
          ),
          MobileStatusPill(widget.item.status),
        ],
      ),
    ),
  );
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({required this.item});
  final MobileProfile item;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MobileSectionHeader(title: 'البيانات الوظيفية'),
          const SizedBox(height: 10),
          _row(Icons.account_tree_outlined, 'الإدارة', item.department),
          _row(Icons.badge_outlined, 'المسمى الوظيفي', item.jobTitle),
          _row(Icons.business_outlined, 'الفرع', item.branch),
          _row(Icons.location_on_outlined, 'موقع العمل', item.workSite),
          _row(
            Icons.supervisor_account_outlined,
            'المدير المباشر',
            item.managerName,
          ),
          _phoneRow(item.phoneE164),
          _row(
            Icons.event_outlined,
            'تاريخ التعيين',
            item.hireDate == null
                ? null
                : DateFormat('d MMM y', 'ar').format(item.hireDate!),
          ),
          /// V17 §4.2.5 — Contract end date hidden (not relevant for current org).
        ],
      ),
    ),
  );

  Widget _phoneRow(String? phone) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        const Icon(Icons.phone_outlined, size: 20),
        const SizedBox(width: 16),
        const Text('الهاتف'),
        const SizedBox(width: 12),
        Expanded(
          child: Directionality(
            textDirection: ui.TextDirection.ltr,
            child: Text(
              phone?.fixIntlPhoneOrder() ?? '—',
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _row(IconData icon, String label, String? value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 16),
        Text(label),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value ?? '—',
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

/// V17 §4.2.3/§4.2.4 — _DocumentsSection and _AssetsSection removed;
/// re-add when the backend journey is ready.

class _DeviceSecuritySection extends ConsumerStatefulWidget {
  const _DeviceSecuritySection();

  @override
  ConsumerState<_DeviceSecuritySection> createState() =>
      _DeviceSecuritySectionState();
}

class _DeviceSecuritySectionState
    extends ConsumerState<_DeviceSecuritySection> {
  bool _registering = false;
  String? _revokingId;
  bool? _localBiometricSupported;

  @override
  void initState() {
    super.initState();
    _checkBiometricSupport();
  }

  Future<void> _checkBiometricSupport() async {
    try {
      final localAuth = LocalAuthentication();
      final supported = await localAuth.isDeviceSupported() &&
          await localAuth.canCheckBiometrics;
      if (mounted) setState(() => _localBiometricSupported = supported);
    } catch (_) {
      if (mounted) setState(() => _localBiometricSupported = false);
    }
  }

  Future<void> _register() async {
    setState(() => _registering = true);
    try {
      await ref.read(mobileCommandsProvider).registerPasskey();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تسجيل الجهاز بنجاح.')),
        );
      }
    } catch (error) {
      if (mounted) {
        final msg = error.toString();
        final text = msg.contains('cancelled')
            ? 'تم إلغاء التحقق.'
            : msg.contains('الجهاز لا يدعم')
                ? 'فعّل قفل الشاشة (نقش أو PIN) من إعدادات الجهاز.'
                : 'تعذر تسجيل الجهاز. أعد المحاولة.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(text)),
        );
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

    setState(() => _revokingId = device.id);
    try {
      await ref
          .read(mobileCommandsProvider)
          .revokePasskey(device.id, reasonController.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إلغاء الجهاز.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(humanizeError(error))),
        );
      }
    } finally {
      reasonController.dispose();
      if (mounted) setState(() => _revokingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final devices = ref.watch(myPasskeysProvider);
    final formatter = DateFormat('d MMMM y، h:mm a', 'ar');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const MobileSectionHeader(
              title: 'أمان الجهاز والبصمة',
              subtitle: 'إدارة أجهزتك الموثوقة لإثبات الحضور.',
            ),
            const SizedBox(height: 12),
            // حالة دعم البصمة على هذا الجهاز
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _localBiometricSupported == true
                    ? scheme.primaryContainer.withValues(alpha: 0.4)
                    : _localBiometricSupported == false
                        ? scheme.errorContainer.withValues(alpha: 0.4)
                        : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    _localBiometricSupported == true
                        ? Icons.fingerprint
                        : _localBiometricSupported == false
                            ? Icons.fingerprint
                            : Icons.hourglass_empty_rounded,
                    color: _localBiometricSupported == true
                        ? scheme.primary
                        : _localBiometricSupported == false
                            ? scheme.error
                            : scheme.onSurfaceVariant,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'أمان هذا الجهاز',
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          _localBiometricSupported == null
                              ? 'جارٍ الفحص…'
                              : _localBiometricSupported!
                                  ? 'الجهاز يدعم البصمة وقفل الشاشة الآمن'
                                  : 'لا توجد بصمة — يمكن استخدام النقش أو PIN',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // قائمة الأجهزة المسجلة
            devices.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: scheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'تعذر تحميل الأجهزة. اسحب لأسفل لإعادة المحاولة.',
                        style: TextStyle(color: scheme.error),
                      ),
                    ),
                  ],
                ),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.phonelink_lock_outlined,
                          size: 36,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'لا توجد أجهزة مسجلة',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'سجل هذا الجهاز لاستخدام البصمة أو النقش في إثبات الحضور.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return Column(
                  children: items.map((device) {
                    final active = device.status == 'active';
                    final isRevoking = _revokingId == device.id;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: active
                                ? scheme.primary.withValues(alpha: 0.3)
                                : scheme.outlineVariant,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: active
                                      ? scheme.primaryContainer
                                      : scheme.surfaceContainerHighest,
                                  child: Icon(
                                    active
                                        ? Icons.phonelink_lock
                                        : Icons.mobile_off_outlined,
                                    size: 20,
                                    color: active
                                        ? scheme.onPrimaryContainer
                                        : scheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        device.deviceLabel,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      MobileStatusPill(
                                        active ? 'active' : device.status,
                                      ),
                                    ],
                                  ),
                                ),
                                if (device.trusted)
                                  Tooltip(
                                    message: 'موثوق من الخادم',
                                    child: Icon(
                                      Icons.verified_user_outlined,
                                      color: scheme.primary,
                                    ),
                                  ),
                              ],
                            ),
                            const Divider(height: 18),
                            Text(
                              'أضيف: ${formatter.format(device.createdAt.toLocal())}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Text(
                              device.lastUsedAt == null
                                  ? 'لم يُستخدم بعد'
                                  : 'آخر استخدام: ${formatter.format(device.lastUsedAt!.toLocal())}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (active) ...[
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed:
                                      isRevoking ? null : () => _revoke(device),
                                  icon: isRevoking
                                      ? const SizedBox.square(
                                          dimension: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.block_outlined),
                                  label: const Text('إلغاء هذا الجهاز'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _registering ? null : _register,
                icon: _registering
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.add_moderator_outlined),
                label: const Text('تسجيل هذا الجهاز'),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PasskeyDevicesPage(),
                  ),
                ),
                icon: const Icon(Icons.devices_outlined),
                label: const Text('إدارة جميع الأجهزة'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;

      // 0457: تحقق من قوة كلمة المرور على الخادم أولاً
      final strengthResult = await client
          .rpc<Map<String, dynamic>>('validate_password_strength',
              params: {'p_password': _passwordController.text})
          .timeout(const Duration(seconds: 10));
      final valid = strengthResult['valid'] == true;
      if (!valid) {
        final issues = (strengthResult['issues'] as List<dynamic>?)
                ?.map((e) => '• $e')
                .join('\n') ??
            '';
        if (mounted) {
          setState(() => _error =
              'كلمة المرور لا تلبي متطلبات الأمان:\n$issues');
        }
        return;
      }

      final response = await client.auth.updateUser(
        UserAttributes(password: _passwordController.text),
      );
      if (response.user == null) {
        throw Exception('تعذر التحديث');
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تغيير الرقم السري بنجاح')),
        );
      }
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      String errorMsg;
      if (msg.contains('reauthentication') || msg.contains('recent login')) {
        errorMsg = 'يجب إعادة تسجيل الدخول قبل تغيير كلمة المرور. سجّل الدخول ثم أعد المحاولة.';
      } else if (msg.contains('session') || msg.contains('expired')) {
        errorMsg = 'انتهت صلاحية الجلسة. سجّل الدخول من جديد.';
      } else {
        errorMsg = 'تعذر تغيير الرقم السري. تحقق من المتطلبات وأعد المحاولة.';
      }
      if (mounted) setState(() => _error = errorMsg);
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر تغيير الرقم السري بأمان. أعد المحاولة.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: bottomInset > 0 ? bottomInset + 24 : 48,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'تغيير الرقم السري',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                ),
              ),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'الرقم السري الجديد',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (val) {
                if (val == null || val.length < 12) {
                  return 'الرقم السري يجب أن يكون 12 حرفًا على الأقل';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _confirmController,
              obscureText: _obscureConfirm,
              decoration: InputDecoration(
                labelText: 'تأكيد الرقم السري',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscureConfirm ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
              validator: (val) {
                if (val != _passwordController.text) {
                  return 'كلمتا المرور غير متطابقتين';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isLoading ? null : _submit,
              child: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('حفظ الرقم السري'),
            ),
          ],
        ),
      ),
    );
  }
}
class _AppVersionCard extends StatefulWidget {
  const _AppVersionCard();

  @override
  State<_AppVersionCard> createState() => _AppVersionCardState();
}

class _AppVersionCardState extends State<_AppVersionCard> {
  String _version = '';
  String _deviceModel = '';
  String _osVersion = '';

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final version = '${packageInfo.version}+${packageInfo.buildNumber}';

      String model;
      String os;
      try {
        final deviceInfo = DeviceInfoPlugin();
        if (Platform.isIOS) {
          final info = await deviceInfo.iosInfo;
          model = info.name;
          os = 'iOS ${info.systemVersion}';
        } else {
          final info = await deviceInfo.androidInfo;
          model = '${info.manufacturer} ${info.model}'.trim();
          os = 'Android ${info.version.release}';
        }
      } catch (_) {
        model = '';
        os = '';
      }

      if (mounted) {
        setState(() {
          _version = version;
          _deviceModel = model;
          _osVersion = os;
        });
      }
    } catch (_) {
      // PackageInfo failed — leave empty.
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'معلومات التطبيق والجهاز',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            if (_version.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else ...[
              _infoRow(Icons.info_outline, 'الإصدار', _version, muted),
              if (_deviceModel.isNotEmpty)
                _infoRow(Icons.phone_android, 'الجهاز', _deviceModel, muted),
              if (_osVersion.isNotEmpty)
                _infoRow(Icons.android, 'نظام التشغيل', _osVersion, muted),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, TextStyle? style) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: style?.color),
          const SizedBox(width: 8),
          Text('$label: ', style: style?.copyWith(fontWeight: FontWeight.w700)),
          Expanded(child: Text(value, style: style)),
        ],
      ),
    );
  }
}

/// بطاقة مشاركة الموقع استباقياً مع المدير التنفيذي (الشيخ محمد).
class _ShareLocationCard extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ShareLocationCard> createState() => _ShareLocationCardState();
}

class _ShareLocationCardState extends ConsumerState<_ShareLocationCard> {
  bool _sending = false;
  String? _result;

  Future<void> _share() async {
    setState(() { _sending = true; _result = null; });
    try {
      final location = await LocationService.current();
      final address = await LocationService.reverseGeocode(
        location.latitude, location.longitude,
      );
      await ref.read(mobileCommandsProvider)
          .shareMyLocationProactively(
            latitude: location.latitude,
            longitude: location.longitude,
            accuracy: location.accuracy,
            durationMinutes: 30,
            reason: 'مشاركة موقع استباقية من البروفايل',
            batteryLevel: null,
          );
      final addr = address ?? 'غير متاح';
      if (mounted) {
        setState(() {
          _result = 'تم إرسال موقعك للشيخ محمد. العنوان: $addr';
          _sending = false;
        });
      }
    } catch (e, stack) {
      if (mounted) {
        setState(() {
          _result = humanizeError(e, stack);
          _sending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.location_on_rounded, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'مشاركة موقعي مع الشيخ محمد',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'إرسل موقعك الحالي مباشرة للشيخ محمد دون انتظار طلب منه.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
            if (_result != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: .3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_result!, style: TextStyle(fontSize: 12)),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _sending ? null : _share,
              icon: _sending
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(_sending ? 'جارٍ الإرسال…' : 'مشاركة موقعي الآن'),
            ),
          ],
        ),
      ),
    );
  }
}
