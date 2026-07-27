import 'dart:typed_data';

import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// صفحة إنشاء إعلان أو تعميم رسمي من الموبايل (للمدير التنفيذي والأدمن).
/// تستدعي RPC publish_official_announcement لنشر فوري لجميع الموظفين.
class ExecutiveAnnouncementPage extends ConsumerStatefulWidget {
  const ExecutiveAnnouncementPage({super.key});

  @override
  ConsumerState<ExecutiveAnnouncementPage> createState() =>
      _ExecutiveAnnouncementPageState();
}

class _ExecutiveAnnouncementPageState
    extends ConsumerState<ExecutiveAnnouncementPage> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  String _category = 'general';
  String _priority = 'normal';
  String _postType = 'announcement';
  bool _requiresAcknowledgement = false;
  bool _submitting = false;

  // ─── صورة مرفقة ───
  XFile? _pickedImage;
  Uint8List? _imageBytes;
  bool _uploading = false;

  static const _postTypes = <String, String>{
    'announcement': 'إعلان',
    'alert': 'تنبيه',
    'poll': 'تصويت',
    'meeting': 'اجتماع',
    'holiday_notice': 'إشعار عطلة',
    'kpi_notice': 'إشعار أداء',
    'attendance_notice': 'إشعار حضور',
  };

  static const _categories = <String, String>{
    'general': 'تعميم عام',
    'hr': 'شؤون موظفين',
    'operational': 'تشغيلي',
    'financial': 'مالي',
    'event': 'فعالية أو مناسبة',
    'safety': 'سلامة وأمان',
  };

  static const _priorities = <String, String>{
    'low': 'منخفضة',
    'normal': 'عادية',
    'high': 'مهمة',
    'urgent': 'عاجلة',
  };

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('نشر إعلان أو تعميم')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: scheme.primaryContainer.withValues(alpha: 0.3),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: scheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'سيُنشر الإعلان فوراً ويصل كإشعار لجميع الموظفين.',
                      style: TextStyle(color: scheme.onPrimaryContainer),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            value: _postType,
            decoration: const InputDecoration(
              labelText: 'نوع المنشور',
              prefixIcon: Icon(Icons.article_outlined),
              border: OutlineInputBorder(),
            ),
            items: _postTypes.entries
                .map((e) =>
                    DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) => setState(() => _postType = v!),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _category,
            decoration: const InputDecoration(
              labelText: 'التصنيف',
              prefixIcon: Icon(Icons.category_outlined),
              border: OutlineInputBorder(),
            ),
            items: _categories.entries
                .map((e) =>
                    DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) => setState(() => _category = v!),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _priority,
            decoration: const InputDecoration(
              labelText: 'الأولوية',
              prefixIcon: Icon(Icons.flag_outlined),
              border: OutlineInputBorder(),
            ),
            items: _priorities.entries
                .map((e) =>
                    DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) => setState(() => _priority = v!),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'عنوان الإعلان',
              prefixIcon: Icon(Icons.title),
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _bodyController,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'نص الإعلان أو التعميم',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          // ─── صورة مرفقة (اختياري) ───
          Text('صورة مرفقة (اختياري)',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (_imageBytes != null)
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(_imageBytes!,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover),
                ),
                Positioned(
                  top: 6,
                  left: 6,
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: scheme.error,
                    child: IconButton(
                      iconSize: 16,
                      padding: EdgeInsets.zero,
                      icon: Icon(Icons.close, color: scheme.onError),
                      onPressed: () => setState(() {
                        _pickedImage = null;
                        _imageBytes = null;
                      }),
                    ),
                  ),
                ),
              ],
            )
          else
            OutlinedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('اختر صورة للإعلان (حتى 5 ميجابايت)'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('يتطلب إقرار بالاطلاع'),
            subtitle: const Text('سيُطلب من كل موظف تأكيد قراءته'),
            value: _requiresAcknowledgement,
            onChanged: (v) => setState(() => _requiresAcknowledgement = v),
            contentPadding: EdgeInsets.zero,
          ),
          if (_priority == 'urgent') ...[
            const SizedBox(height: 8),
            Card(
              color: scheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: scheme.onErrorContainer),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'الإعلانات العاجلة تظهر بشكل بارز لجميع الموظفين.',
                        style: TextStyle(color: scheme.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
            label: Text(_uploading
                ? 'جارٍ رفع الصورة...'
                : _submitting
                    ? 'جارٍ النشر...'
                    : 'نشر الإعلان الآن'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 85,
    );
    if (xfile == null) return;
    final bytes = await xfile.readAsBytes();
    // حد 5 ميجابايت
    if (bytes.lengthInBytes > 5 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('حجم الصورة يتجاوز 5 ميجابايت')),
        );
      }
      return;
    }
    setState(() {
      _pickedImage = xfile;
      _imageBytes = bytes;
    });
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    if (title.length < 3 || body.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('العنوان (3 أحرف على الأقل) والمحتوى (10 أحرف) مطلوبان'),
        ),
      );
      return;
    }

    // تأكيد قبل النشر العاجل
    if (_priority == 'urgent') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('تأكيد النشر العاجل'),
          content: const Text(
            'سيصل هذا الإعلان فوراً كإشعار عاجل لجميع الموظفين.\nهل أنت متأكد؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('تراجع'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('نعم، انشر'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _submitting = true);
    try {
      // ─── رفع الصورة إن وُجدت ───
      String? bannerUrl;
      if (_pickedImage != null && _imageBytes != null) {
        setState(() => _uploading = true);
        try {
          final ext = _pickedImage!.name.split('.').last.toLowerCase();
          final path =
              '${DateTime.now().millisecondsSinceEpoch}_${_pickedImage!.name.hashCode}.$ext';
          final bucket =
              Supabase.instance.client.storage.from('announcements');
          await bucket.uploadBinary(
            path,
            _imageBytes!,
            fileOptions: FileOptions(
              contentType: _pickedImage!.mimeType ?? 'image/jpeg',
              upsert: false,
            ),
          );
          bannerUrl = bucket.getPublicUrl(path);
        } finally {
          if (mounted) setState(() => _uploading = false);
        }
      }

      await ref.read(supabaseProvider).rpc<dynamic>(
        'publish_official_announcement',
        params: {
          'p_title': title,
          'p_body': body,
          'p_category': _category,
          'p_priority': _priority,
          'p_requires_acknowledgement': _requiresAcknowledgement,
          'p_banner_url': bannerUrl,
          'p_post_type': _postType,
        },
      );
      // تحديث القائمة
      ref.invalidate(mobileFeedProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('تم نشر الإعلان بنجاح ✓'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(humanizeError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
