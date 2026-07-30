/// صفحة التقييم الصاعد — الموظف يقيّم مديره بشكل مجهول الهوية.
/// معايير التقييم: القيادة، التواصل، العدالة، الدعم، التطوير.
library;

import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/kpi_360_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';

class KpiUpwardFeedbackPage extends StatefulWidget {
  const KpiUpwardFeedbackPage({super.key});

  @override
  State<KpiUpwardFeedbackPage> createState() => _KpiUpwardFeedbackPageState();
}

class _KpiUpwardFeedbackPageState extends State<KpiUpwardFeedbackPage>
    with SingleTickerProviderStateMixin {
  // TODO: جلب اسم المدير وبيانات الدورة من RPC: get_upward_feedback_target
  late final List<UpwardCriterion> _criteria =
      UpwardFeedback.defaultCriteria().toList();
  final _overallController = TextEditingController();
  bool _submitting = false;
  bool _submitted = false;
  late final AnimationController _successAnim;
  late final Animation<double> _successScale;

  @override
  void initState() {
    super.initState();
    _successAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _successScale = CurvedAnimation(
      parent: _successAnim,
      curve: Curves.elasticOut,
    );
  }

  @override
  void dispose() {
    _overallController.dispose();
    _successAnim.dispose();
    super.dispose();
  }

  bool get _isValid => _criteria.every((c) => c.score != null && c.score! > 0);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // ─── حالة النجاح بعد الإرسال ───────────────────────────
    if (_submitted) {
      return Scaffold(
        appBar: AppBar(title: const Text('تقييم المدير')),
        body: Center(
          child: ScaleTransition(
            scale: _successScale,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.verified_rounded,
                      size: 48,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'تم إرسال تقييمك بنجاح',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w900),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'شكراً لملاحظاتك — ستساعد في تطوير بيئة العمل',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: 18,
                          color: scheme.onSecondaryContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'تقييمك مجهول الهوية ولن يُربط باسمك',
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: scheme.onSecondaryContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('العودة'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // ─── النموذج ─────────────────────────────────────────────
    return Scaffold(
      appBar: AppBar(title: const Text('تقييم المدير')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
        children: [
          // ─── إخلاء المسؤولية ────────────────────────────────
          Card(
            color: scheme.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: 24,
                    color: scheme.onTertiaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'هذا التقييم مجهول الهوية ولن يُربط باسمك',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: scheme.onTertiaryContainer,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'ملاحظاتك تساعد في تطوير بيئة العمل وتحسين '
                          'أسلوب الإدارة. أجب بصدق وموضوعية.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: scheme.onTertiaryContainer,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ─── معايير التقييم ──────────────────────────────────
          const MobileSectionHeader(
            title: 'معايير التقييم',
            subtitle: 'قيّم مديرك في كل معيار من 1 إلى 5',
          ),
          const SizedBox(height: 8),
          ...List.generate(_criteria.length, (i) {
            final criterion = _criteria[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              _criterionIcon(criterion.id),
                              size: 18,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  criterion.name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                Text(
                                  criterion.description,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // شريط التقييم المرئي
                      Row(
                        children: List.generate(5, (star) {
                          final starNum = star + 1;
                          final selected = criterion.score != null &&
                              criterion.score! >= starNum;
                          return Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() {
                                _criteria[i] =
                                    criterion.copyWith(score: starNum);
                              }),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                margin: EdgeInsetsDirectional.only(
                                  end: star < 4 ? 6 : 0,
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? _ratingColor(starNum)
                                          .withValues(alpha: .15)
                                      : scheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(10),
                                  border: selected
                                      ? Border.all(
                                          color: _ratingColor(starNum),
                                          width: 1.5,
                                        )
                                      : null,
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      '$starNum',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w900,
                                            color: selected
                                                ? _ratingColor(starNum)
                                                : scheme.onSurfaceVariant,
                                          ),
                                    ),
                                    Text(
                                      _ratingLabel(starNum),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                            color: selected
                                                ? _ratingColor(starNum)
                                                : scheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 12),

                      // تعليق اختياري
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'تعليق (اختياري)',
                          alignLabelWithHint: true,
                        ),
                        maxLines: 2,
                        textDirection: TextDirection.rtl,
                        onChanged: (value) => setState(() {
                          _criteria[i] = criterion.copyWith(comment: value);
                        }),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 16),

          // ─── تعليق عام ──────────────────────────────────────
          const MobileSectionHeader(title: 'ملاحظات إضافية'),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _overallController,
                decoration: const InputDecoration(
                  labelText: 'هل لديك ملاحظات عامة لتحسين بيئة العمل؟',
                  alignLabelWithHint: true,
                ),
                maxLines: 4,
                textDirection: TextDirection.rtl,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ─── زر الإرسال ─────────────────────────────────────
          FilledButton.icon(
            onPressed: _isValid && !_submitting ? _confirmSubmit : null,
            icon: _submitting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send_rounded),
            label:
                Text(_submitting ? 'جاري الإرسال...' : 'إرسال التقييم'),
          ),
          if (!_isValid)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'يرجى تقييم جميع المعايير قبل الإرسال',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.error,
                    ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  // ─── مساعدات ───────────────────────────────────────────────

  IconData _criterionIcon(String id) => switch (id) {
        'leadership' => Icons.military_tech_outlined,
        'communication' => Icons.forum_outlined,
        'fairness' => Icons.balance_outlined,
        'support' => Icons.support_agent_outlined,
        'development' => Icons.school_outlined,
        _ => Icons.star_outline_rounded,
      };

  String _ratingLabel(int score) => switch (score) {
        1 => 'ضعيف',
        2 => 'مقبول',
        3 => 'متوسط',
        4 => 'جيد',
        5 => 'ممتاز',
        _ => '',
      };

  Color _ratingColor(int score) => switch (score) {
        1 => AppColors.statusDanger,
        2 => AppColors.statusWarning,
        3 => AppColors.statusInfo,
        4 => AppColors.statusSuccess,
        5 => AppColors.brandPrimary,
        _ => AppColors.statusInfo,
      };

  // ─── تأكيد + إرسال ─────────────────────────────────────────

  void _confirmSubmit() {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الإرسال'),
        content: const Text(
          'هل أنت متأكد من إرسال التقييم؟\n\n'
          'التقييم مجهول الهوية ولن يمكن تعديله بعد الإرسال.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد الإرسال'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) _submit();
    });
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      // TODO: إرسال التقييم عبر RPC: submit_upward_feedback
      // final feedback = UpwardFeedback(
      //   id: 'new',
      //   managerId: managerId,
      //   managerName: managerName,
      //   periodMonth: DateTime.now(),
      //   criteria: _criteria,
      //   overallComment: _overallController.text.trim(),
      // );
      // await ref.read(mobileCommandsProvider).submitUpwardFeedback(feedback);
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      setState(() => _submitted = true);
      _successAnim.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل إرسال التقييم: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }
}
