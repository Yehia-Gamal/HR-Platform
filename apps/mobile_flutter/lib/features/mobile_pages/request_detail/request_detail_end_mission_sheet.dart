part of '../mobile_request_detail_page.dart';

class _EndMissionSheet extends StatefulWidget {
  const _EndMissionSheet({
    required this.noun,
    this.reportOnly = false,
    this.initialReport,
    this.initialOutcome,
  });

  final String noun;
  final bool reportOnly;
  final String? initialReport;
  final String? initialOutcome;

  @override
  State<_EndMissionSheet> createState() => _EndMissionSheetState();
}

class _EndMissionSheetState extends State<_EndMissionSheet> {
  late final _reportController = TextEditingController(
    text: widget.initialReport?.trim() ?? '',
  );
  late final _outcomeController = TextEditingController(
    text: widget.initialOutcome?.trim() ?? '',
  );

  @override
  void dispose() {
    _reportController.dispose();
    _outcomeController.dispose();
    super.dispose();
  }

  void _submit({required bool withCheckout}) {
    final report = _reportController.text.trim();
    final outcome = _outcomeController.text.trim();
    final finalReport = report.isEmpty ? 'تم إنجاز ${widget.noun} بنجاح' : report;
    Navigator.pop(context, (
      report: finalReport,
      outcome: outcome.isEmpty ? null : outcome,
      withCheckout: withCheckout,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.reportOnly
                  ? 'تقرير ${widget.noun}'
                  : 'إنهاء ${widget.noun}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            if (widget.reportOnly) ...[
              const SizedBox(height: 6),
              Text(
                'أغلقها النظام في نهاية يومها؛ التقرير يوثّق ما أنجزته ولا يغيّر حضور اليوم.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _reportController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'تقرير التنفيذ (اختياري)',
                hintText: 'ماذا أنجزت؟ (اختياري - غير إلزامي)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _outcomeController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'النتيجة (اختياري)',
                hintText: 'مثال: اكتملت بنجاح، تم التسليم…',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 18),
            if (widget.reportOnly)
              FilledButton.icon(
                onPressed: () => _submit(withCheckout: false),
                icon: const Icon(Icons.save_rounded),
                label: const Text('حفظ التقرير'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
              )
            else ...[
              FilledButton.icon(
                onPressed: () => _submit(withCheckout: true),
                icon: const Icon(Icons.logout_rounded),
                label: Text('إنهاء ${widget.noun} وتسجيل الانصراف'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.statusSuccess,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'إذا انتهى يوم عملك وتغادر مباشرة.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _submit(withCheckout: false),
                icon: const Icon(Icons.task_alt_rounded),
                label: Text('إنهاء ${widget.noun} فقط واستمرار الدوام'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'إذا عدت إلى مقر العمل أو ما زال دوامك مستمرًا.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// مسار الاعتماد: شريط المراحل + سجل الطلب
// ═══════════════════════════════════════════════════════════════════════════

