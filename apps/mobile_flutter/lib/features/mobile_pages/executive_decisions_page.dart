import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ExecutiveDecisionsPage extends ConsumerStatefulWidget {
  const ExecutiveDecisionsPage({super.key});

  @override
  ConsumerState<ExecutiveDecisionsPage> createState() =>
      _ExecutiveDecisionsPageState();
}

class _ExecutiveDecisionsPageState extends ConsumerState<ExecutiveDecisionsPage> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _outcomeController = TextEditingController();
  String _category = 'general';
  bool _requiresReceipt = true;
  bool _submitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _outcomeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إصدار قرار أو تعميم')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'أصدر قراراً أو إعلاناً سيصل فوراً لجميع الموظفين المعنيين.',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 24),
          DropdownButtonFormField<String>(
            value: _category,
            decoration: const InputDecoration(
              labelText: 'النوع',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'general', child: Text('قرار إداري')),
              DropdownMenuItem(value: 'policy', child: Text('سياسة جديدة')),
              DropdownMenuItem(value: 'announcement', child: Text('تعميم داخلي')),
              DropdownMenuItem(value: 'directive', child: Text('توجيه تنفيذي')),
            ],
            onChanged: (v) => setState(() => _category = v!),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'العنوان',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _bodyController,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'نص القرار أو التعميم',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _outcomeController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'النتيجة المتوقعة (اختياري)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('يتطلب إقرار مقروء'),
            value: _requiresReceipt,
            onChanged: (v) => setState(() => _requiresReceipt = v),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
            label: Text(_submitting ? 'جارٍ الإصدار...' : 'إصدار ونشر'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    if (title.length < 3 || body.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('العنوان (3 أحرف على الأقل) والمحتوى (10 أحرف) مطلوبان'),
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await rpcWithTimeout(ref.read(supabaseProvider).rpc<dynamic>(
        'create_decision_draft',
        params: {
          'p_title': title,
          'p_body': body,
          'p_category': _category,
          'p_requires_read_receipt': _requiresReceipt,
          'p_expected_outcome':
              _outcomeController.text.trim().isEmpty
                  ? null
                  : _outcomeController.text.trim(),
        },
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إصدار القرار بنجاح')),
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
