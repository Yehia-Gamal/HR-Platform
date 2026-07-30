/// صفحة ملخص تقييم 360° — رسم بياني عنكبوتي (رادار) ومقارنة المنظورات
/// ونقاط القوة ومجالات التطوير.
library;

import 'dart:math' as math;

import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/kpi_360_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';

class Kpi360SummaryPage extends StatelessWidget {
  const Kpi360SummaryPage({super.key});

  @override
  Widget build(BuildContext context) {
    // TODO: جلب البيانات من الباك إند عبر RPC: get_360_summary
    final summary = _mockSummary();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('ملخص تقييم 360°')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
        children: [
          // ─── الدرجة الإجمالية ──────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    'الدرجة الإجمالية 360°',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 12),
                  _ScoreCircle(
                    score: summary.overallScore,
                    maxScore: 5,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _overallRating(summary.overallScore),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'بناءً على ${summary.peerCount} مراجعة من الزملاء',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ─── بطاقات الدرجات حسب المنظور ─────────────────────
          MetricGrid(cards: [
            (
              'التقييم الذاتي',
              summary.selfScore.toStringAsFixed(1),
              Icons.person_outline_rounded,
              null,
            ),
            (
              'تقييم الزملاء',
              summary.peerAvgScore.toStringAsFixed(1),
              Icons.groups_outlined,
              null,
            ),
            (
              'تقييم المدير',
              summary.managerScore.toStringAsFixed(1),
              Icons.supervisor_account_outlined,
              null,
            ),
            (
              'الدرجة الإجمالية',
              summary.overallScore.toStringAsFixed(1),
              Icons.radar_rounded,
              null,
            ),
          ]),
          const SizedBox(height: 24),

          // ─── الرسم البياني العنكبوتي ────────────────────────
          const MobileSectionHeader(
            title: 'مقارنة المنظورات',
            subtitle: 'رؤية شاملة للتقييم من كل الزوايا',
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  SizedBox(
                    height: 300,
                    child: CustomPaint(
                      size: const Size(300, 300),
                      painter: _RadarChartPainter(
                        criteria: summary.criteria,
                        isDark: scheme.brightness == Brightness.dark,
                        gridColor: scheme.outlineVariant,
                        labelColor: scheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // دليل الألوان
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _LegendDot(
                        color: AppColors.statusInfo,
                        label: 'التقييم الذاتي',
                      ),
                      const SizedBox(width: 16),
                      _LegendDot(
                        color: AppColors.statusSuccess,
                        label: 'الزملاء',
                      ),
                      const SizedBox(width: 16),
                      _LegendDot(
                        color: AppColors.statusViolet,
                        label: 'المدير',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ─── نقاط القوة ────────────────────────────────────
          const MobileSectionHeader(
            title: 'نقاط القوة',
            subtitle: 'أعلى المعايير أداءً من كل المنظورات',
          ),
          const SizedBox(height: 8),
          if (summary.strengths.isEmpty)
            _EmptyHint(
              icon: Icons.emoji_events_outlined,
              text: 'لا توجد بيانات كافية لتحديد نقاط القوة',
            )
          else
            ...summary.strengths.map(
              (c) => _InsightCard(
                criterion: c,
                icon: Icons.trending_up_rounded,
                color: AppColors.statusSuccess,
              ),
            ),
          const SizedBox(height: 24),

          // ─── مجالات التطوير ─────────────────────────────────
          const MobileSectionHeader(
            title: 'مجالات التطوير',
            subtitle: 'المعايير ذات أكبر فجوة بين التقييم الذاتي والآخرين',
          ),
          const SizedBox(height: 8),
          if (summary.developmentAreas.isEmpty)
            _EmptyHint(
              icon: Icons.psychology_outlined,
              text: 'لا توجد فجوات ملحوظة — استمر في التطوير!',
            )
          else
            ...summary.developmentAreas.map(
              (c) => _InsightCard(
                criterion: c,
                icon: Icons.trending_down_rounded,
                color: AppColors.statusWarning,
              ),
            ),
        ],
      ),
    );
  }

  String _overallRating(double score) => switch (score) {
        >= 4.5 => 'ممتاز',
        >= 3.5 => 'جيد جداً',
        >= 2.5 => 'جيد',
        >= 1.5 => 'مقبول',
        _ => 'يحتاج تحسين',
      };
}

// ─── دائرة الدرجة ────────────────────────────────────────────

class _ScoreCircle extends StatelessWidget {
  const _ScoreCircle({required this.score, required this.maxScore});

  final double score;
  final double maxScore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ratio = (score / maxScore).clamp(0.0, 1.0);
    return SizedBox.square(
      dimension: 100,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: ratio,
            strokeWidth: 8,
            strokeCap: StrokeCap.round,
            backgroundColor: scheme.surfaceContainerHighest,
            color: scheme.primary,
            semanticsLabel: 'الدرجة الإجمالية',
          ),
          Center(
            child: Text(
              score.toStringAsFixed(1),
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── نقطة دليل الألوان ──────────────────────────────────────

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      );
}

// ─── بطاقة رؤية (قوة / تطوير) ────────────────────────────────

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.criterion,
    required this.icon,
    required this.color,
  });

  final Kpi360Criterion criterion;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
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
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (criterion.selfScore != null) ...[
                          _MiniScore(
                            label: 'ذاتي',
                            value: criterion.selfScore!,
                            color: AppColors.statusInfo,
                          ),
                          const SizedBox(width: 10),
                        ],
                        if (criterion.peerAvgScore != null) ...[
                          _MiniScore(
                            label: 'زملاء',
                            value: criterion.peerAvgScore!,
                            color: AppColors.statusSuccess,
                          ),
                          const SizedBox(width: 10),
                        ],
                        if (criterion.managerScore != null)
                          _MiniScore(
                            label: 'مدير',
                            value: criterion.managerScore!,
                            color: AppColors.statusViolet,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (criterion.maxGap >= 0.5) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'فجوة ${criterion.maxGap.toStringAsFixed(1)}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onErrorContainer,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniScore extends StatelessWidget {
  const _MiniScore({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 3),
          Text(
            '$label: ${value.toStringAsFixed(1)}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      );
}

// ─── تلميح فارغ ──────────────────────────────────────────────

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Icon(
              icon,
              size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
}

// ─── رسّام الرسم البياني العنكبوتي (رادار) ───────────────────

class _RadarChartPainter extends CustomPainter {
  _RadarChartPainter({
    required this.criteria,
    required this.isDark,
    required this.gridColor,
    required this.labelColor,
  });

  final List<Kpi360Criterion> criteria;
  final bool isDark;
  final Color gridColor;
  final Color labelColor;

  static const _maxScore = 5.0;
  static const _gridLevels = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 32;
    final n = criteria.length;
    if (n < 3) return;

    final angleStep = 2 * math.pi / n;
    // نبدأ من الأعلى (−π/2)
    const startAngle = -math.pi / 2;

    // ─── خطوط الشبكة ──────────────────────────────────
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = gridColor;

    for (var level = 1; level <= _gridLevels; level++) {
      final r = radius * level / _gridLevels;
      final path = Path();
      for (var i = 0; i < n; i++) {
        final angle = startAngle + i * angleStep;
        final point = Offset(
          center.dx + r * math.cos(angle),
          center.dy + r * math.sin(angle),
        );
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      path.close();
      canvas.drawPath(path, gridPaint);
    }

    // خطوط المحاور
    for (var i = 0; i < n; i++) {
      final angle = startAngle + i * angleStep;
      final end = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      canvas.drawLine(center, end, gridPaint);
    }

    // ─── مساحات البيانات ──────────────────────────────
    _drawDataPolygon(
      canvas, center, radius, n, angleStep, startAngle,
      criteria.map((c) => c.selfScore ?? 0).toList(),
      AppColors.statusInfo,
    );
    _drawDataPolygon(
      canvas, center, radius, n, angleStep, startAngle,
      criteria.map((c) => c.peerAvgScore ?? 0).toList(),
      AppColors.statusSuccess,
    );
    _drawDataPolygon(
      canvas, center, radius, n, angleStep, startAngle,
      criteria.map((c) => c.managerScore ?? 0).toList(),
      AppColors.statusViolet,
    );

    // ─── تسميات المحاور ───────────────────────────────
    for (var i = 0; i < n; i++) {
      final angle = startAngle + i * angleStep;
      final labelRadius = radius + 20;
      final point = Offset(
        center.dx + labelRadius * math.cos(angle),
        center.dy + labelRadius * math.sin(angle),
      );

      final tp = TextPainter(
        text: TextSpan(
          text: criteria[i].name,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: labelColor,
            fontFamily: 'Cairo',
          ),
        ),
        textDirection: TextDirection.rtl,
        textAlign: TextAlign.center,
      )..layout(maxWidth: 80);

      tp.paint(
        canvas,
        Offset(point.dx - tp.width / 2, point.dy - tp.height / 2),
      );
    }
  }

  void _drawDataPolygon(
    Canvas canvas,
    Offset center,
    double radius,
    int n,
    double angleStep,
    double startAngle,
    List<double> scores,
    Color color,
  ) {
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: .15);
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color;
    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color;

    final path = Path();
    final points = <Offset>[];

    for (var i = 0; i < n; i++) {
      final angle = startAngle + i * angleStep;
      final value = (scores[i] / _maxScore).clamp(0.0, 1.0);
      final r = radius * value;
      final point = Offset(
        center.dx + r * math.cos(angle),
        center.dy + r * math.sin(angle),
      );
      points.add(point);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, strokePaint);

    for (final p in points) {
      canvas.drawCircle(p, 3.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarChartPainter oldDelegate) =>
      oldDelegate.criteria != criteria || oldDelegate.isDark != isDark;
}

// ─── بيانات وهمية ────────────────────────────────────────────

Kpi360Summary _mockSummary() => Kpi360Summary(
      employeeId: 'emp-current',
      employeeName: 'الموظف الحالي',
      periodMonth: DateTime(2026, 7),
      selfScore: 4.2,
      peerAvgScore: 3.8,
      managerScore: 3.9,
      overallScore: 3.97,
      peerCount: 4,
      criteria: const [
        Kpi360Criterion(
          id: 'teamwork',
          name: 'العمل الجماعي',
          weight: 20,
          selfScore: 4.5,
          peerAvgScore: 4.2,
          managerScore: 4.0,
        ),
        Kpi360Criterion(
          id: 'communication',
          name: 'التواصل',
          weight: 20,
          selfScore: 4.0,
          peerAvgScore: 3.5,
          managerScore: 3.8,
        ),
        Kpi360Criterion(
          id: 'initiative',
          name: 'المبادرة',
          weight: 15,
          selfScore: 4.5,
          peerAvgScore: 3.2,
          managerScore: 3.5,
        ),
        Kpi360Criterion(
          id: 'reliability',
          name: 'الاعتمادية',
          weight: 20,
          selfScore: 3.8,
          peerAvgScore: 4.0,
          managerScore: 4.2,
        ),
        Kpi360Criterion(
          id: 'professionalism',
          name: 'الاحترافية',
          weight: 15,
          selfScore: 4.2,
          peerAvgScore: 4.3,
          managerScore: 4.0,
        ),
        Kpi360Criterion(
          id: 'problemSolving',
          name: 'حل المشكلات',
          weight: 10,
          selfScore: 4.0,
          peerAvgScore: 3.6,
          managerScore: 4.1,
        ),
      ],
    );
