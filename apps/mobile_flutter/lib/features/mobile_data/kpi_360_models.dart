/// نماذج بيانات تقييم 360° — مراجعة الزملاء، ملخص شامل، تقييم صاعد.
library;

import 'package:flutter/foundation.dart';

// ─── معيار تقييم من منظورات متعددة ──────────────────────────────

@immutable
class Kpi360Criterion {
  const Kpi360Criterion({
    required this.id,
    required this.name,
    required this.weight,
    this.selfScore,
    this.peerAvgScore,
    this.managerScore,
    this.maxScore = 5,
  });

  final String id;
  final String name;
  final double weight;
  final double? selfScore;
  final double? peerAvgScore;
  final double? managerScore;
  final double maxScore;

  /// أكبر فجوة بين التقييم الذاتي وأي منظور آخر.
  double get maxGap {
    final self = selfScore;
    if (self == null) return 0;
    double gap = 0;
    if (peerAvgScore != null) gap = (self - peerAvgScore!).abs();
    if (managerScore != null) {
      final mGap = (self - managerScore!).abs();
      if (mGap > gap) gap = mGap;
    }
    return gap;
  }

  /// متوسط كل المنظورات المتوفرة.
  double? get combinedAvg {
    final scores = <double>[
      if (selfScore != null) selfScore!,
      if (peerAvgScore != null) peerAvgScore!,
      if (managerScore != null) managerScore!,
    ];
    if (scores.isEmpty) return null;
    return scores.reduce((a, b) => a + b) / scores.length;
  }

  factory Kpi360Criterion.fromJson(Map<String, dynamic> json) =>
      Kpi360Criterion(
        id: json['id'] as String,
        name: json['name'] as String,
        weight: (json['weight'] as num).toDouble(),
        selfScore: (json['self_score'] as num?)?.toDouble(),
        peerAvgScore: (json['peer_avg_score'] as num?)?.toDouble(),
        managerScore: (json['manager_score'] as num?)?.toDouble(),
        maxScore: (json['max_score'] as num?)?.toDouble() ?? 5,
      );
}

// ─── تقييم زميل (مراجعة أقران) ────────────────────────────────

/// حالة المراجعة.
enum ReviewStatus { pending, inProgress, completed }

@immutable
class Kpi360PeerTarget {
  const Kpi360PeerTarget({
    required this.employeeId,
    required this.employeeName,
    required this.department,
    this.employeePhotoUrl,
    required this.status,
    this.submittedAt,
  });

  final String employeeId;
  final String employeeName;
  final String department;
  final String? employeePhotoUrl;
  final ReviewStatus status;
  final DateTime? submittedAt;

  factory Kpi360PeerTarget.fromJson(Map<String, dynamic> json) =>
      Kpi360PeerTarget(
        employeeId: json['employee_id'] as String,
        employeeName: json['employee_name'] as String,
        department: json['department'] as String,
        employeePhotoUrl: json['employee_photo_url'] as String?,
        status: ReviewStatus.values.byName(json['status'] as String),
        submittedAt: json['submitted_at'] == null
            ? null
            : DateTime.parse(json['submitted_at'] as String),
      );
}

@immutable
class Kpi360CriterionRating {
  const Kpi360CriterionRating({
    required this.criterionId,
    required this.criterionName,
    this.score,
    this.comment,
    this.maxScore = 5,
  });

  final String criterionId;
  final String criterionName;
  final int? score;
  final String? comment;
  final int maxScore;

  Kpi360CriterionRating copyWith({int? score, String? comment}) =>
      Kpi360CriterionRating(
        criterionId: criterionId,
        criterionName: criterionName,
        score: score ?? this.score,
        comment: comment ?? this.comment,
        maxScore: maxScore,
      );
}

@immutable
class Kpi360Review {
  const Kpi360Review({
    required this.id,
    required this.targetEmployeeId,
    required this.targetEmployeeName,
    required this.reviewerId,
    required this.periodMonth,
    required this.ratings,
    this.overallComment,
    this.recommendation,
    this.submittedAt,
  });

  final String id;
  final String targetEmployeeId;
  final String targetEmployeeName;
  final String reviewerId;
  final DateTime periodMonth;
  final List<Kpi360CriterionRating> ratings;
  final String? overallComment;
  final String? recommendation;
  final DateTime? submittedAt;

  bool get isSubmitted => submittedAt != null;

  Map<String, dynamic> toSubmitPayload() => {
        'evaluation_id': id,
        'ratings': ratings
            .map((r) => {
                  'criterion_id': r.criterionId,
                  'score': r.score,
                  'comment': r.comment,
                })
            .toList(),
        'overall_comment': overallComment,
        'recommendation': recommendation,
      };
}

// ─── ملخص 360° ─────────────────────────────────────────────────

@immutable
class Kpi360Summary {
  const Kpi360Summary({
    required this.employeeId,
    required this.employeeName,
    required this.periodMonth,
    required this.criteria,
    required this.selfScore,
    required this.peerAvgScore,
    required this.managerScore,
    required this.overallScore,
    required this.peerCount,
  });

  final String employeeId;
  final String employeeName;
  final DateTime periodMonth;
  final List<Kpi360Criterion> criteria;
  final double selfScore;
  final double peerAvgScore;
  final double managerScore;

  /// درجة 360° الإجمالية (متوسط مرجّح).
  final double overallScore;

  /// عدد الزملاء المشاركين.
  final int peerCount;

  /// أعلى 3 معايير حسب المتوسط الكلي.
  List<Kpi360Criterion> get strengths {
    final sorted = criteria
        .where((c) => c.combinedAvg != null)
        .toList()
      ..sort((a, b) => (b.combinedAvg ?? 0).compareTo(a.combinedAvg ?? 0));
    return sorted.take(3).toList();
  }

  /// المعايير ذات أكبر فجوة بين التقييم الذاتي والمنظورات الأخرى.
  List<Kpi360Criterion> get developmentAreas {
    final sorted = criteria
        .where((c) => c.selfScore != null)
        .toList()
      ..sort((a, b) => b.maxGap.compareTo(a.maxGap));
    return sorted.where((c) => c.maxGap >= 0.5).take(3).toList();
  }

  factory Kpi360Summary.fromJson(Map<String, dynamic> json) => Kpi360Summary(
        employeeId: json['employee_id'] as String,
        employeeName: json['employee_name'] as String,
        periodMonth: DateTime.parse(json['period_month'] as String),
        criteria: (json['criteria'] as List)
            .map(
                (e) => Kpi360Criterion.fromJson(e as Map<String, dynamic>))
            .toList(),
        selfScore: (json['self_score'] as num).toDouble(),
        peerAvgScore: (json['peer_avg_score'] as num).toDouble(),
        managerScore: (json['manager_score'] as num).toDouble(),
        overallScore: (json['overall_score'] as num).toDouble(),
        peerCount: json['peer_count'] as int,
      );
}

// ─── تقييم صاعد (الموظف يقيّم مديره) ──────────────────────────

@immutable
class UpwardCriterion {
  const UpwardCriterion({
    required this.id,
    required this.name,
    required this.description,
    this.score,
    this.comment,
  });

  final String id;
  final String name;
  final String description;
  final int? score;
  final String? comment;

  UpwardCriterion copyWith({int? score, String? comment}) => UpwardCriterion(
        id: id,
        name: name,
        description: description,
        score: score ?? this.score,
        comment: comment ?? this.comment,
      );
}

@immutable
class UpwardFeedback {
  const UpwardFeedback({
    required this.id,
    required this.managerId,
    required this.managerName,
    required this.periodMonth,
    required this.criteria,
    this.overallComment,
    this.submittedAt,
  });

  final String id;
  final String managerId;
  final String managerName;
  final DateTime periodMonth;
  final List<UpwardCriterion> criteria;
  final String? overallComment;
  final DateTime? submittedAt;

  bool get isSubmitted => submittedAt != null;

  Map<String, dynamic> toSubmitPayload() => {
        'feedback_id': id,
        'manager_id': managerId,
        'ratings': criteria
            .map((c) => {
                  'criterion_id': c.id,
                  'score': c.score,
                  'comment': c.comment,
                })
            .toList(),
        'overall_comment': overallComment,
      };

  /// المعايير الافتراضية لتقييم المدير.
  static List<UpwardCriterion> defaultCriteria() => const [
        UpwardCriterion(
          id: 'leadership',
          name: 'القيادة',
          description:
              'القدرة على توجيه الفريق وتحفيزه نحو الأهداف المشتركة',
        ),
        UpwardCriterion(
          id: 'communication',
          name: 'التواصل',
          description:
              'وضوح التعليمات والاستماع الفعّال وتقديم الملاحظات البنّاءة',
        ),
        UpwardCriterion(
          id: 'fairness',
          name: 'العدالة',
          description:
              'المعاملة المنصفة لجميع أعضاء الفريق وتوزيع العمل بعدالة',
        ),
        UpwardCriterion(
          id: 'support',
          name: 'الدعم',
          description:
              'توفير الموارد والأدوات اللازمة ومساعدة الفريق في تجاوز العقبات',
        ),
        UpwardCriterion(
          id: 'development',
          name: 'التطوير',
          description:
              'الاهتمام بتطوير مهارات الفريق وتوفير فرص التعلّم والنمو المهني',
        ),
      ];
}
