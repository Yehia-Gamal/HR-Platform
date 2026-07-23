import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/widgets/brand_logo.dart';
import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/core/theme/theme_mode_controller.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_learning_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_service_portal_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_privacy_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
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
              const _ThemePreferenceCard(),
              const SizedBox(height: 14),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.school_outlined),
                  title: const Text('تدريبي ومهاراتي'),
                  subtitle: const Text('الدورات الإلزامية والتقدم والشهادات'),
                  trailing: const Icon(Icons.chevron_left_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const MobileLearningPage(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.support_agent_outlined),
                  title: const Text('الخدمات الداخلية'),
                  subtitle: const Text('HR وIT والتشغيل والإدارة'),
                  trailing: const Icon(Icons.chevron_left_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const MobileServicePortalPage(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: const Text('كشوف الرواتب'),
                  subtitle: const Text('تظهر عند تفعيل واعتماد وحدة الرواتب'),
                  trailing: const Icon(Icons.chevron_left_rounded),
                  enabled: false,
                ),
              ),
              const SizedBox(height: 10),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('الخصوصية وبياناتي'),
                  subtitle: const Text(
                    'طلبات الاطلاع والتصحيح والتقييد والحذف',
                  ),
                  trailing: const Icon(Icons.chevron_left_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const MobilePrivacyPage(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
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
              _DocumentsSection(items: item.documents),
              const SizedBox(height: 14),
              _AssetsSection(items: item.assets),
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
      );
      final url = bucket.getPublicUrl(path);

      await Supabase.instance.client.from('employees').update({'photo_url': url}).eq('id', widget.item.id);
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
    const marker = '/storage/v1/object/public/employee-avatars/';
    final index = url.indexOf(marker);
    if (index < 0) return null;
    return Uri.decodeComponent(url.substring(index + marker.length));
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          GestureDetector(
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
                  Positioned(
                    bottom: 0,
                    right: 0,
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
          _row(Icons.groups_outlined, 'الفريق', item.team),
          _row(Icons.badge_outlined, 'المنصب', item.position ?? item.jobTitle),
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
          _row(
            Icons.description_outlined,
            'نهاية العقد',
            item.contractEnd == null
                ? null
                : DateFormat('d MMM y', 'ar').format(item.contractEnd!),
          ),
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
              phone ?? '—',
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

class _DocumentsSection extends StatelessWidget {
  const _DocumentsSection({required this.items});
  final List<MobileDocumentSummary> items;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MobileSectionHeader(title: 'مستنداتي (${items.length})'),
          const SizedBox(height: 8),
          if (items.isEmpty)
            _EmptyLine(
              icon: Icons.description_outlined,
              message: 'لا توجد مستندات متاحة.',
            )
          else
            ...items.map(
              (item) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.description_outlined),
                title: Text(item.title),
                subtitle: item.expiryDate == null
                    ? null
                    : Text(
                        'ينتهي ${DateFormat('d MMM y', 'ar').format(item.expiryDate!)}',
                      ),
                trailing: MobileStatusPill(
                  item.status == 'expired' ? 'expired' : 'active',
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _AssetsSection extends StatelessWidget {
  const _AssetsSection({required this.items});
  final List<MobileAssetSummary> items;
  @override
  Widget build(BuildContext context) {
    final active = items
        .where((item) => item.returnedAt == null)
        .toList(growable: false);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MobileSectionHeader(title: 'العهد الحالية (${active.length})'),
            const SizedBox(height: 8),
            if (active.isEmpty)
              _EmptyLine(
                icon: Icons.devices_other_outlined,
                message: 'لا توجد عهد مسجلة عليك.',
              )
            else
              ...active.map(
                (item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.devices_other_outlined),
                  title: Text(item.assetName),
                  subtitle: item.serial == null
                      ? null
                      : Text('الرقم: ${item.serial}'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine({required this.icon, required this.message});
  final IconData icon;
  final String message;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Icon(icon, size: 32, color: scheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
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
      final response = await Supabase.instance.client.auth.updateUser(
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
    } on AuthException {
      if (mounted) setState(() => _error = 'تعذر تغيير الرقم السري. تحقق من المتطلبات وأعد المحاولة.');
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
                if (val == null || val.length < 6) {
                  return 'الرقم السري يجب أن يكون 6 أحرف على الأقل';
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
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('حفظ الرقم السري'),
            ),
          ],
        ),
      ),
    );
  }
}
