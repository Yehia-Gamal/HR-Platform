part of '../monthly_attendance_statement_page.dart';

class _QuickCorrectionSheet extends StatefulWidget {
  const _QuickCorrectionSheet({
    required this.dateStr,
    required this.allowedTypes,
    required this.onSubmit,
  });
  final String dateStr;
  final List<String> allowedTypes;
  final Future<void> Function(
    String type,
    String reason,
    DateTime? checkIn,
    DateTime? checkOut,
  )
  onSubmit;
  @override
  State<_QuickCorrectionSheet> createState() => _QuickCorrectionSheetState();
}

class _QuickCorrectionSheetState extends State<_QuickCorrectionSheet> {
  final _reasonCtrl = TextEditingController();
  late String _type;
  late TimeOfDay _time;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _type = widget.allowedTypes.first;
    _time = _type == 'missing_check_in'
        ? const TimeOfDay(hour: 9, minute: 0)
        : const TimeOfDay(hour: 17, minute: 0);
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
      helpText: _type == 'missing_check_in'
          ? 'تحديد وقت الحضور التقريبي'
          : 'تحديد وقت الانصراف التقريبي',
      cancelText: 'إلغاء',
      confirmText: 'تأكيد',
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked != null && mounted) {
      setState(() => _time = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final scheme = Theme.of(context).colorScheme;
    final isCheckIn = _type == 'missing_check_in';
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: .3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.error.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.fingerprint_rounded,
                  color: scheme.error,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'نسيان بصمة',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: scheme.error,
                    ),
                  ),
                  Text(
                    'اليوم: ${widget.dateStr}',
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (widget.allowedTypes.length > 1)
            SegmentedButton<String>(
              segments: [
                for (final type in widget.allowedTypes)
                  ButtonSegment(
                    value: type,
                    label: Text(
                      type == 'missing_check_in'
                          ? 'نسيان حضور'
                          : 'نسيان انصراف',
                    ),
                  ),
              ],
              selected: {_type},
              onSelectionChanged: _sending
                  ? null
                  : (v) {
                      setState(() {
                        final newType = v.first;
                        if (newType != _type) {
                          if (_type == 'missing_check_in' &&
                              _time == const TimeOfDay(hour: 9, minute: 0)) {
                            _time = const TimeOfDay(hour: 17, minute: 0);
                          } else if (_type == 'missing_check_out' &&
                              _time == const TimeOfDay(hour: 17, minute: 0)) {
                            _time = const TimeOfDay(hour: 9, minute: 0);
                          }
                          _type = newType;
                        }
                      });
                    },
            ),
          const SizedBox(height: 14),
          // ── حقل الساعة لاختيار الوقت التقريبي ──
          InkWell(
            onTap: _sending ? null : _pickTime,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: scheme.primary.withValues(alpha: .35),
                  width: 1.2,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: .12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.access_time_filled_rounded,
                      color: scheme.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isCheckIn
                              ? 'وقت الحضور التقريبي'
                              : 'وقت الانصراف التقريبي',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _time.format(context),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: scheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.edit_rounded,
                          size: 14,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'تغيير',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: scheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _reasonCtrl,
            enabled: !_sending,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'السبب',
              hintText: 'اكتب سبب نسيان البصمة...',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: scheme.error)),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _sending ? null : _submit,
            icon: const Icon(Icons.send_rounded),
            label: Text(_sending ? 'جارٍ الإرسال…' : 'إرسال الطلب'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final reason = _reasonCtrl.text.trim();
    if (reason.length < 3) {
      setState(() => _error = 'أدخل سبب التصحيح (3 أحرف على الأقل).');
      return;
    }
    final date = DateTime.parse(widget.dateStr);
    final time = DateTime(
      date.year,
      date.month,
      date.day,
      _time.hour,
      _time.minute,
    );
    final isCheckIn = _type == 'missing_check_in';
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.onSubmit(
        _type,
        reason,
        isCheckIn ? time : null,
        isCheckIn ? null : time,
      );
      if (mounted && ModalRoute.of(context)?.isCurrent == true)
        Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = humanizeError(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

// ─── نموذج إذن سريع ─────────────────────────────────────────────────
