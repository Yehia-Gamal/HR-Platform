import 'dart:ui' as ui;
import 'package:ahla_shabab_management_os/core/widgets/brand_logo.dart';
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
              Text('تعذر تحميل الملف: $error', textAlign: TextAlign.center),
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
              const SizedBox(height: 14),
              _DocumentsSection(items: item.documents),
              const SizedBox(height: 14),
              _AssetsSection(items: item.assets),
            ],
          ),
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
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked == null) return;

    setState(() => _isUploading = true);
    try {
      final bytes = await picked.readAsBytes();
      final ext = picked.name.split('.').last;
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final path = '$userId/avatar_${DateTime.now().millisecondsSinceEpoch}.$ext';
      
      await Supabase.instance.client.storage.from('avatars').uploadBinary(path, bytes);
      final url = Supabase.instance.client.storage.from('avatars').getPublicUrl(path);
      
      await Supabase.instance.client.from('employees').update({'photo_url': url}).eq('id', userId);
      ref.invalidate(mobileProfileProvider);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث الصورة بنجاح')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ أثناء رفع الصورة: $e')));
      }
    } finally {
      setState(() => _isUploading = false);
    }
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
                CircleAvatar(
                  radius: 36,
                  backgroundImage: widget.item.photoUrl == null
                      ? null
                      : NetworkImage(widget.item.photoUrl!),
                  child: widget.item.photoUrl == null
                      ? Text(
                          widget.item.fullNameAr.substring(0, 1),
                          style: const TextStyle(fontSize: 26),
                        )
                      : null,
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
          const Divider(height: 32),
          const _ChangePasswordButton(),
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

class _ChangePasswordButton extends StatefulWidget {
  const _ChangePasswordButton();
  @override
  State<_ChangePasswordButton> createState() => _ChangePasswordButtonState();
}

class _ChangePasswordButtonState extends State<_ChangePasswordButton> {
  bool _isLoading = false;
  final _passwordController = TextEditingController();

  Future<void> _changePassword() async {
    final password = _passwordController.text;
    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرقم السري يجب أن يكون 6 أحرف على الأقل')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: password),
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تغيير الرقم السري بنجاح')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء التغيير: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showDialog() {
    _passwordController.clear();
    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('تغيير الرقم السري'),
          content: TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'الرقم السري الجديد',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _isLoading ? null : () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: _isLoading
                  ? null
                  : () async {
                      setStateDialog(() => _isLoading = true);
                      await _changePassword();
                      if (mounted) setStateDialog(() => _isLoading = false);
                    },
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _showDialog,
        icon: const Icon(Icons.password_rounded),
        label: const Text('تغيير الرقم السري'),
      ),
    );
  }
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
