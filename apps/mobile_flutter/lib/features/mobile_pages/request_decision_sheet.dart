import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/network/offline_sync_queue.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/request_display.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// إعداد ورقة إجراء على طلب (قرار أو سحب).
class RequestSheetConfig {
  const RequestSheetConfig({
    required this.title,
    required this.icon,
    required this.color,
    required this.explanation,
    required this.inputLabel,
    required this.required,
    required this.suggestions,
    required this.confirmLabel,
    required this.successMessage,
  });

  final String title;
  final IconData icon;
  final Color color;
  final String explanation;
  final String inputLabel;
  final bool required;
  final List<String> suggestions;
  final String confirmLabel;
  final String successMessage;
}

const requestReturnColor = Color(0xFFC2410C);

/// إعداد قرار المعتمِد: approve / return / reject.
RequestSheetConfig requestDecisionConfig(String decision, String employeeName) =>
    switch (decision) {
      'approve' => RequestSheetConfig(
        title: 'اعتماد الطلب',
        icon: Icons.check_circle_rounded,
        color: AppColors.statusSuccess,
        explanation:
            'يُعتمد الطلب نهائيًا ويُبلَّغ $employeeName بالقرار فورًا.',
        inputLabel: 'ملاحظة للموظف (اختياري)',
        required: false,
        suggestions: const [
          'بالتوفيق إن شاء الله',
          'تمت الموافقة',
          'يُرجى التنسيق مع الفريق قبل الانطلاق',
        ],
        confirmLabel: 'تأكيد الاعتماد',
        successMessage: 'تم اعتماد الطلب وإبلاغ الموظف.',
      ),
      'return' => RequestSheetConfig(
        title: 'إرجاع الطلب للتعديل',
        icon: Icons.undo_rounded,
        color: requestReturnColor,
        explanation:
            'يعود الطلب إلى $employeeName ليعدّله ويعيد رفعه، ويصله ما تكتبه هنا.',
        inputLabel: 'ما المطلوب تعديله؟ (إلزامي)',
        required: true,
        suggestions: const [
          'يُرجى توضيح السبب بتفصيل أكثر',
          'يُرجى تعديل التاريخ',
          'يُرجى إرفاق ما يثبت الطلب',
        ],
        confirmLabel: 'تأكيد الإرجاع',
        successMessage: 'تم إرجاع الطلب للموظف للتعديل.',
      ),
      _ => RequestSheetConfig(
        title: 'رفض الطلب',
        icon: Icons.cancel_rounded,
        color: AppColors.statusDanger,
        explanation:
            'يُرفض الطلب نهائيًا ويُبلَّغ $employeeName بالقرار وسببه.',
        inputLabel: 'سبب الرفض (إلزامي)',
        required: true,
        suggestions: const [
          'يتعارض مع احتياج العمل في هذا اليوم',
          'الرصيد لا يسمح',
          'يُرجى التنسيق مع مديرك أولًا',
        ],
        confirmLabel: 'تأكيد الرفض',
        successMessage: 'تم رفض الطلب وإبلاغ الموظف بالسبب.',
      ),
    };

/// يفتح ورقة قرار المعتمِد وينفّذ القرار؛ يُرجع true عند النجاح ويعرض رسالة.
Future<bool> showRequestDecisionSheet(
  BuildContext context,
  WidgetRef ref, {
  required String requestId,
  required int number,
  required String type,
  required String employeeName,
  required String decision,
}) async {
  final config = requestDecisionConfig(decision, employeeName);
  final messenger = ScaffoldMessenger.of(context);
  final commands = ref.read(mobileCommandsProvider);
  final done = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => RequestActionSheet(
      config: config,
      subject: '${requestTypeLabel(type)} · طلب رقم $number · $employeeName',
      onSubmit: (note) =>
          commands.decideRequest(requestId, decision, note.isEmpty ? null : note),
    ),
  );
  if (done != true) return false;
  messenger.showSnackBar(
    SnackBar(
      backgroundColor: config.color,
      content: Text(config.successMessage),
    ),
  );
  return true;
}

/// ورقة إجراء بملاحظة/سبب: تملك متحكّم النص (يُتلف مع الورقة لا قبل حركة
/// إغلاقها)، وتعرض الخطأ داخلها بدل إغلاقها.
class RequestActionSheet extends StatefulWidget {
  const RequestActionSheet({
    required this.config,
    required this.subject,
    required this.onSubmit,
    super.key,
  });

  final RequestSheetConfig config;
  final String subject;
  final Future<void> Function(String note) onSubmit;

  @override
  State<RequestActionSheet> createState() => _RequestActionSheetState();
}

class _RequestActionSheetState extends State<RequestActionSheet> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final note = _controller.text.trim();
    if (widget.config.required && note.length < 3) {
      setState(() => _error = 'اكتب ثلاثة أحرف على الأقل.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(note);
      if (mounted) Navigator.of(context).pop(true);
    } on OfflineQueuedException catch (error) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(false);
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = requestErrorMessage(error) ?? humanizeError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: config.color.withValues(alpha: .12),
                  child: Icon(config.icon, color: config.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        config.title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.subject,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: config.color.withValues(alpha: .07),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                config.explanation,
                style: const TextStyle(fontSize: 13, height: 1.55),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final text in config.suggestions)
                  ActionChip(
                    label: Text(text, style: const TextStyle(fontSize: 12)),
                    onPressed: _busy
                        ? null
                        : () {
                            _controller.text = text;
                            _controller.selection = TextSelection.collapsed(
                              offset: text.length,
                            );
                            setState(() => _error = null);
                          },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              enabled: !_busy,
              maxLines: 3,
              maxLength: 300,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: InputDecoration(
                labelText: config.inputLabel,
                errorText: _error,
                errorMaxLines: 3,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: const Text('رجوع'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: config.color,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: _busy ? null : _submit,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(config.icon, size: 20),
                    label: Text(_busy ? 'جارٍ التنفيذ…' : config.confirmLabel),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
