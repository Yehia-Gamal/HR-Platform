import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KPI Assessment Tests', () {
    group('KPI Stage Validation', () {
      test('valid stages', () {
        expect(isValidStage('self'), isTrue);
        expect(isValidStage('manager_review'), isTrue);
        expect(isValidStage('hr_review'), isTrue);
        expect(isValidStage('parallel_review'), isTrue);
        expect(isValidStage('secretary_review'), isTrue);
        expect(isValidStage('executive_review'), isTrue);
      });

      test('invalid stages', () {
        expect(isValidStage('unknown'), isFalse);
        expect(isValidStage(''), isFalse);
        expect(isValidStage('SELF'), isFalse); // case-sensitive
      });
    });

    group('KPI Score Calculation', () {
      test('calculate weighted score - single criterion', () {
        final criteria = [
          CriterionScore(weight: 30, score: 80),
        ];
        expect(calculateTotalScore(criteria), 24.0); // 30% * 80 = 24
      });

      test('calculate weighted score - multiple criteria', () {
        final criteria = [
          CriterionScore(weight: 30, score: 80),
          CriterionScore(weight: 40, score: 90),
          CriterionScore(weight: 30, score: 70),
        ];
        // (30% * 80) + (40% * 90) + (30% * 70) = 24 + 36 + 21 = 81
        expect(calculateTotalScore(criteria), 81.0);
      });

      test('calculate weighted score - perfect score', () {
        final criteria = [
          CriterionScore(weight: 50, score: 100),
          CriterionScore(weight: 50, score: 100),
        ];
        expect(calculateTotalScore(criteria), 100.0);
      });

      test('calculate weighted score - zero score', () {
        final criteria = [
          CriterionScore(weight: 50, score: 0),
          CriterionScore(weight: 50, score: 0),
        ];
        expect(calculateTotalScore(criteria), 0.0);
      });

      test('weights must sum to 100', () {
        final criteria = [
          CriterionScore(weight: 40, score: 80),
          CriterionScore(weight: 40, score: 90),
        ];
        expect(validateWeightSum(criteria), isFalse); // sum = 80, not 100
      });
    });

    group('KPI Score Validation', () {
      test('valid score range', () {
        expect(isValidScore(0), isTrue);
        expect(isValidScore(50), isTrue);
        expect(isValidScore(100), isTrue);
      });

      test('invalid score range', () {
        expect(isValidScore(-1), isFalse);
        expect(isValidScore(101), isFalse);
        expect(isValidScore(-100), isFalse);
        expect(isValidScore(200), isFalse);
      });
    });

    group('KPI Permission Checks', () {
      test('self assessment permission', () {
        final access = MockAccessContext(
          permissions: ['performance.kpi.self_assess'],
          employeeId: 'emp-123',
        );
        expect(canSelfAssess(access, 'emp-123'), isTrue);
        expect(canSelfAssess(access, 'emp-456'), isFalse); // different employee
      });

      test('manager assessment permission', () {
        final access = MockAccessContext(
          permissions: ['performance.kpi.manager_assess'],
          employeeId: 'mgr-123',
        );
        expect(canManagerAssess(access), isTrue);
      });

      test('hr assessment permission', () {
        final access = MockAccessContext(
          permissions: ['performance.kpi.hr_assess'],
          employeeId: 'hr-123',
        );
        expect(canHRAssess(access), isTrue);
      });

      test('secretary review permission', () {
        final access = MockAccessContext(
          permissions: ['performance.kpi.secretary_review'],
          employeeId: 'sec-123',
        );
        expect(canSecretaryReview(access), isTrue);
      });

      test('executive review permission', () {
        final access = MockAccessContext(
          permissions: ['performance.kpi.executive_review'],
          employeeId: 'exec-123',
        );
        expect(canExecutiveReview(access), isTrue);
      });

      test('parallel review - HR or Manager', () {
        final hrAccess = MockAccessContext(
          permissions: ['performance.kpi.hr_assess'],
          employeeId: 'hr-123',
        );
        final mgrAccess = MockAccessContext(
          permissions: ['performance.kpi.manager_assess'],
          employeeId: 'mgr-123',
        );
        final noAccess = MockAccessContext(
          permissions: [],
          employeeId: 'emp-123',
        );

        expect(canParallelReview(hrAccess), isTrue);
        expect(canParallelReview(mgrAccess), isTrue);
        expect(canParallelReview(noAccess), isFalse);
      });
    });

    group('KPI Evaluation Status', () {
      test('evaluation status labels', () {
        expect(getStatusLabel('draft'), 'مسودة');
        expect(getStatusLabel('self'), 'التقييم الذاتي');
        expect(getStatusLabel('manager_review'), 'مراجعة المدير');
        expect(getStatusLabel('hr_review'), 'مراجعة الموارد البشرية');
        expect(getStatusLabel('parallel_review'), 'المراجعة المتوازية');
        expect(getStatusLabel('secretary_review'), 'مراجعة السكرتير');
        expect(getStatusLabel('executive_review'), 'إقرار المدير التنفيذي');
        expect(getStatusLabel('completed'), 'مكتمل');
      });
    });

    group('KPI Comments Validation', () {
      test('valid comment', () {
        expect(validateComment('هذا تعليق صحيح على الأداء'), isNull);
      });

      test('comment too short', () {
        expect(validateComment('قص'), contains('التعليق'));
      });

      test('empty comment is optional', () {
        // التعليق اختياري، لذا فارغ مقبول
        expect(validateComment(''), isNull);
      });

      test('comment too long', () {
        final longComment = 'أ' * 1001;
        expect(validateComment(longComment), contains('التعليق'));
      });
    });
  });
}

// Data classes للاختبار
class CriterionScore {
  CriterionScore({required this.weight, required this.score});
  final int weight;
  final int score;
}

class MockAccessContext {
  MockAccessContext({
    required this.permissions,
    required this.employeeId,
  });

  final List<String> permissions;
  final String employeeId;

  bool hasPermission(String permission) => permissions.contains(permission);
}

// Helper functions
bool isValidStage(String stage) {
  const validStages = [
    'self',
    'manager_review',
    'hr_review',
    'parallel_review',
    'secretary_review',
    'executive_review',
  ];
  return validStages.contains(stage);
}

double calculateTotalScore(List<CriterionScore> criteria) {
  var total = 0.0;
  for (final criterion in criteria) {
    total += (criterion.weight / 100) * criterion.score;
  }
  return total;
}

bool validateWeightSum(List<CriterionScore> criteria) {
  final sum = criteria.fold(0, (sum, c) => sum + c.weight);
  return sum == 100;
}

bool isValidScore(int score) {
  return score >= 0 && score <= 100;
}

bool canSelfAssess(MockAccessContext access, String employeeId) {
  return access.hasPermission('performance.kpi.self_assess') &&
      access.employeeId == employeeId;
}

bool canManagerAssess(MockAccessContext access) {
  return access.hasPermission('performance.kpi.manager_assess');
}

bool canHRAssess(MockAccessContext access) {
  return access.hasPermission('performance.kpi.hr_assess');
}

bool canSecretaryReview(MockAccessContext access) {
  return access.hasPermission('performance.kpi.secretary_review');
}

bool canExecutiveReview(MockAccessContext access) {
  return access.hasPermission('performance.kpi.executive_review');
}

bool canParallelReview(MockAccessContext access) {
  return access.hasPermission('performance.kpi.hr_assess') ||
      access.hasPermission('performance.kpi.manager_assess');
}

String getStatusLabel(String status) {
  const labels = {
    'draft': 'مسودة',
    'self': 'التقييم الذاتي',
    'manager_review': 'مراجعة المدير',
    'hr_review': 'مراجعة الموارد البشرية',
    'parallel_review': 'المراجعة المتوازية',
    'secretary_review': 'مراجعة السكرتير',
    'executive_review': 'إقرار المدير التنفيذي',
    'completed': 'مكتمل',
  };
  return labels[status] ?? 'غير معروف';
}

String? validateComment(String comment) {
  if (comment.isEmpty) return null; // اختياري
  if (comment.length < 3) return 'التعليق يجب أن يكون 3 أحرف على الأقل';
  if (comment.length > 1000) return 'التعليق يجب ألا يتجاوز 1000 حرف';
  return null;
}
