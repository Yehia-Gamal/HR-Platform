import 'dart:convert';
import 'dart:typed_data';

import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/shared/permission_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// صفحة مبسطة وسريعة لإصدار ونشر القرارات والتعاميم الرسمية.
/// مصممة بأسلوب عصري خفيف بدون تعقيدات أو حقول إجبارية مرهقة.
class ExecutiveAnnouncementPage extends ConsumerStatefulWidget {
  const ExecutiveAnnouncementPage({
    super.key,
    this.initialType = 'announcement',
  });

  /// النوع الأولي للمنشور (إعلان/تعميم أو قرار إداري أو استطلاع)
  final String initialType;

  @override
  ConsumerState<ExecutiveAnnouncementPage> createState() =>
      _ExecutiveAnnouncementPageState();
}

class _ExecutiveAnnouncementPageState
    extends ConsumerState<ExecutiveAnnouncementPage> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final List<TextEditingController> _pollControllers = [
    TextEditingController(text: 'موافق'),
    TextEditingController(text: 'غير موافق'),
  ];

  late String _postType;
  String _category = 'general';
  String _priority = 'normal';
  bool _requiresAcknowledgement = false;
  bool _submitting = false;

  // ─── صورة مرفقة ───
  XFile? _pickedImage;
  Uint8List? _imageBytes;
  bool _uploading = false;

  static const _categories = <String, String>{
    'general': 'عام ورسمي',
    'policy': 'سياسة ولائحة جديدة',
    'directive': 'توجيه تنفيذي',
    'hr': 'شؤون موظفين',
    'operational': 'تشغيلي وميداني',
    'financial': 'مالي وإداري',
    'event': 'فعالية أو مناسبة',
    'safety': 'سلامة وأمان',
  };

  @override
  void initState() {
    super.initState();
    _postType = widget.initialType == 'poll'
        ? 'poll'
        : widget.initialType == 'decision'
            ? 'standard'
            : 'announcement';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    for (final c in _pollControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return PermissionGate(
      permission: 'comms.announcement.manage',
      child: Scaffold(
        appBar: AppBar(
          title: const Text('نشر قرار أو تعميم'),
          centerTitle: true,
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    // ─── نوع المنشور (أزرار مدمجة سريعة بنقرة واحدة) ───
                    Center(
                      child: SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: 'announcement',
                            icon: Icon(Icons.campaign_outlined, size: 18),
                            label: Text('تعميم عام'),
                          ),
                          ButtonSegment(
                            value: 'standard',
                            icon: Icon(Icons.gavel_outlined, size: 18),
                            label: Text('قرار إداري'),
                          ),
                          ButtonSegment(
                            value: 'poll',
                            icon: Icon(Icons.poll_outlined, size: 18),
                            label: Text('استطلاع'),
                          ),
                        ],
                        selected: {_postType},
                        onSelectionChanged: (newSet) {
                          setState(() => _postType = newSet.first);
                        },
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ─── بطاقة الكتابة الموحدة (Composer Card) ───
                    Container(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.6),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // عنوان مختصر (اختياري بالكامل)
                          TextField(
                            controller: _titleController,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                            decoration: InputDecoration(
                              hintText: 'عنوان المنشور (اختياري)',
                              hintStyle: TextStyle(
                                color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                                fontWeight: FontWeight.normal,
                              ),
                              prefixIcon: const Icon(Icons.title, size: 20),
                              prefixIconConstraints: const BoxConstraints(minWidth: 32),
                              isDense: true,
                              border: InputBorder.none,
                            ),
                            textInputAction: TextInputAction.next,
                          ),
                          Divider(
                            color: scheme.outlineVariant.withValues(alpha: 0.4),
                            height: 16,
                          ),

                          // المحتوى الرئيسي
                          TextField(
                            controller: _bodyController,
                            minLines: 4,
                            maxLines: 8,
                            autofocus: true,
                            decoration: InputDecoration(
                              hintText: _postType == 'standard'
                                  ? 'اكتب نص القرار الإداري هنا...'
                                  : _postType == 'poll'
                                      ? 'اكتب موضوع أو سؤال الاستطلاع...'
                                      : 'اكتب نص التعميم أو الإعلان هنا...',
                              hintStyle: TextStyle(
                                color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                              ),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),

                          // معاينة الصورة المرفقة إن وُجدت
                          if (_imageBytes != null) ...[
                            const SizedBox(height: 10),
                            Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.memory(
                                    _imageBytes!,
                                    height: 140,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                PositionedDirectional(
                                  top: 8,
                                  end: 8,
                                  child: Material(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    shape: const CircleBorder(),
                                    child: InkWell(
                                      customBorder: const CircleBorder(),
                                      onTap: () => setState(() {
                                        _pickedImage = null;
                                        _imageBytes = null;
                                      }),
                                      child: const Padding(
                                        padding: EdgeInsets.all(6),
                                        child: Icon(
                                          Icons.close,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ─── خيارات الاستطلاع (تظهر فقط عند اختيار استطلاع) ───
                    if (_postType == 'poll') ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.how_to_vote_outlined, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'خيارات التصويت',
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const Spacer(),
                            if (_pollControllers.length < 5)
                              TextButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _pollControllers.add(TextEditingController());
                                  });
                                },
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('إضافة خيار'),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...List.generate(_pollControllers.length, (index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TextField(
                            controller: _pollControllers[index],
                            decoration: InputDecoration(
                              hintText: 'الخيار ${index + 1}',
                              prefixIcon: CircleAvatar(
                                radius: 10,
                                backgroundColor: scheme.primaryContainer,
                                child: Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onPrimaryContainer,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              prefixIconConstraints: const BoxConstraints(
                                minWidth: 36,
                                minHeight: 36,
                              ),
                              suffixIcon: _pollControllers.length > 2
                                  ? IconButton(
                                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                                      onPressed: () {
                                        setState(() {
                                          _pollControllers.removeAt(index).dispose();
                                        });
                                      },
                                    )
                                  : null,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 10),
                    ],

                    // ─── شريط الخيارات السريعة (رقائق بنقرة واحدة) ───
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // صورة
                        ActionChip(
                          avatar: Icon(
                            _pickedImage != null
                                ? Icons.check_circle_rounded
                                : Icons.add_photo_alternate_outlined,
                            size: 16,
                            color: _pickedImage != null ? scheme.primary : null,
                          ),
                          label: Text(
                            _pickedImage != null ? 'تغيير الصورة' : 'إرفاق صورة',
                          ),
                          onPressed: _pickImage,
                        ),

                        // عاجل
                        FilterChip(
                          avatar: Icon(
                            _priority == 'urgent'
                                ? Icons.warning_amber_rounded
                                : Icons.flag_outlined,
                            size: 16,
                            color: _priority == 'urgent' ? Colors.white : null,
                          ),
                          label: Text(
                            _priority == 'urgent' ? 'إشعار عاجل 🚨' : 'عاجل',
                          ),
                          selected: _priority == 'urgent',
                          selectedColor: scheme.error,
                          labelStyle: TextStyle(
                            color: _priority == 'urgent' ? scheme.onError : null,
                            fontWeight:
                                _priority == 'urgent' ? FontWeight.bold : null,
                          ),
                          onSelected: (val) {
                            setState(() => _priority = val ? 'urgent' : 'normal');
                          },
                        ),

                        // إقرار بالقراءة
                        FilterChip(
                          avatar: Icon(
                            _requiresAcknowledgement
                                ? Icons.check_circle_rounded
                                : Icons.fact_check_outlined,
                            size: 16,
                          ),
                          label: const Text('إلزام بتأكيد القراءة'),
                          selected: _requiresAcknowledgement,
                          onSelected: (val) {
                            setState(() => _requiresAcknowledgement = val);
                          },
                        ),

                        // التصنيف (اختياري - افتراضي عام)
                        ActionChip(
                          avatar: const Icon(Icons.label_outline, size: 16),
                          label: Text(
                            _category == 'general'
                                ? 'التصنيف: عام'
                                : _categories[_category] ?? 'التصنيف',
                          ),
                          onPressed: () => _showCategoryPicker(context),
                        ),
                      ],
                    ),

                    if (_priority == 'urgent') ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: scheme.error.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, size: 18, color: scheme.error),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'المنشور العاجل يرسل تنبيهاً فورياً لكافة الموظفين.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // ─── زر النشر الثابت في الأسفل ───
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.icon(
                      onPressed: _submitting ? null : _submit,
                      icon: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded),
                      label: Text(
                        _uploading
                            ? 'جارٍ رفع الصورة...'
                            : _submitting
                                ? 'جارٍ النشر...'
                                : 'نشر الآن للجميع',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'يُنشر فوراً في الخلاصة الرسمية ويصل كإشعار للموظفين المعنيين',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                            fontSize: 11,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCategoryPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                'اختر تصنيف المنشور (اختياري)',
                style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
            ),
            const Divider(),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: _categories.entries.map((entry) {
                  final isSelected = _category == entry.key;
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                      color: isSelected ? Theme.of(ctx).colorScheme.primary : null,
                      size: 20,
                    ),
                    title: Text(entry.value),
                    selected: isSelected,
                    onTap: () {
                      setState(() => _category = entry.key);
                      Navigator.pop(ctx);
                    },
                  );
                }).toList(),
              ),
            ),
          ],
        ),
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
    final body = _bodyController.text.trim();
    if (body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى كتابة نص المنشور أو القرار أولاً'),
        ),
      );
      return;
    }

    // ─── استخراج ذكي للعنوان إن تُرِك فارغاً ───
    var title = _titleController.text.trim();
    if (title.isEmpty) {
      final firstLine = body.split('\n').first.trim();
      title = firstLine.length > 50 ? '${firstLine.substring(0, 47)}...' : firstLine;
    }
    if (title.isEmpty) {
      title = _postType == 'standard'
          ? 'قرار إداري'
          : _postType == 'poll'
              ? 'استطلاع رأي'
              : 'تعميم عام';
    }

    // خيارات الاستطلاع إن وُجدت
    List<String>? pollOptions;
    if (_postType == 'poll') {
      pollOptions = _pollControllers
          .map((c) => c.text.trim())
          .where((t) => t.isNotEmpty)
          .toList();
      if (pollOptions.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('الاستطلاع يتطلب خيارين على الأقل')),
        );
        return;
      }
    }

    // تأكيد قبل النشر العاجل
    if (_priority == 'urgent') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('تأكيد النشر العاجل'),
          content: const Text(
            'سيصل هذا المنشور فوراً كإشعار عاجل لجميع الموظفين.\nهل أنت متأكد؟',
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

    if (!mounted) return;
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
          final bucket = Supabase.instance.client.storage.from('announcements');
          await bucket
              .uploadBinary(
                path,
                _imageBytes!,
                fileOptions: FileOptions(
                  contentType: _pickedImage!.mimeType ?? 'image/jpeg',
                  upsert: false,
                ),
              )
              .timeout(const Duration(seconds: 60));
          bannerUrl = bucket.getPublicUrl(path);
        } finally {
          if (mounted) setState(() => _uploading = false);
        }
      }

      final rpcParams = <String, dynamic>{
        'p_title': title,
        'p_body': body,
        'p_category': _category,
        'p_priority': _priority,
        'p_requires_acknowledgement': _requiresAcknowledgement,
        'p_banner_url': bannerUrl,
        'p_post_type': _postType,
      };

      if (pollOptions != null) {
        rpcParams['p_poll_options'] = jsonEncode(pollOptions);
      }

      await rpcWithTimeout(
        ref
            .read(supabaseProvider)
            .rpc<dynamic>('publish_official_announcement', params: rpcParams),
      );

      // تحديث قائمة المنشورات
      ref.invalidate(mobileFeedProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('تم نشر المنشور بنجاح ✓'),
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
