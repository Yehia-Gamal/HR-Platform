/**
 * محرك احتساب مؤشر مخاطر التسرب الوظيفي (Turnover Risk Index Engine)
 * خوارزمية ذكية مدمجة (Zero-Cost On-Premise Algorithm) تحلل بيانات الموظف
 * (الحضور، التقييمات، النزاعات، الإجازات، وساعات العمل) للتنبؤ باحتمالية ترك العمل مبكراً.
 */

export type RiskLevel = 'low' | 'medium' | 'high' | 'critical';

export interface TurnoverRiskFactor {
  id: string;
  name: string;
  impactScore: number; // 0-100
  severity: 'low' | 'medium' | 'high';
  description: string;
}

export interface TurnoverRiskAssessment {
  employeeId: string;
  employeeName: string;
  overallScore: number; // 0 - 100
  riskLevel: RiskLevel;
  confidenceScore: number; // 0 - 100
  assessedAt: string;
  topFactors: TurnoverRiskFactor[];
  recommendedAction: string;
}

export interface EmployeeTurnoverMetrics {
  employeeId: string;
  fullName: string;
  // مؤشرات الحضور
  unexcusedAbsencesLast60Days: number;
  latePunchesLast30Days: number;
  weekendAdjacentAbsences: number; // غياب ملتصق بالعطلات
  // مؤشرات الأداء
  currentKpiScore?: number; // 0 - 100
  previousKpiScore?: number; // 0 - 100
  kpiDropPercentage?: number;
  // النزاعات والجزاءات
  activeDisputesCount: number;
  warningsLast90Days: number;
  // الإجازات والإرهاق
  daysSinceLastAnnualLeave: number;
  overtimeHoursLastMonth: number;
  // الأقدمية
  monthsInRole: number;
}

/**
 * احتساب درجة مخاطر التسرب بناءً على الأوزان القياسية لعلم الموارد البشرية
 */
export function calculateTurnoverRisk(metrics: EmployeeTurnoverMetrics): TurnoverRiskAssessment {
  const factors: TurnoverRiskFactor[] = [];
  let totalWeightedScore = 0;

  // 1. تذبذب الحضور والغياب (وزن 35%)
  let attendanceScore = 0;
  if (metrics.unexcusedAbsencesLast60Days >= 3) {
    attendanceScore += 50;
    factors.push({
      id: 'unexcused_absences',
      name: 'تكرار الغياب غير المبرر',
      impactScore: 50,
      severity: 'high',
      description: `تم رصد ${metrics.unexcusedAbsencesLast60Days} أيام غياب خلال آخر 60 يوماً دون عذر رسمي.`,
    });
  } else if (metrics.unexcusedAbsencesLast60Days >= 1) {
    attendanceScore += 20;
  }

  if (metrics.latePunchesLast30Days >= 6) {
    attendanceScore += 30;
    factors.push({
      id: 'chronic_lateness',
      name: 'نمط تأخر متكرر عن الدوام',
      impactScore: 30,
      severity: 'medium',
      description: `تأخر الموظف ${metrics.latePunchesLast30Days} مرات خلال آخر 30 يوماً مما يشير لضعف الارتباط بالعمل.`,
    });
  }

  if (metrics.weekendAdjacentAbsences >= 2) {
    attendanceScore += 20;
    factors.push({
      id: 'weekend_adjacent',
      name: 'غياب دوري ملتصق بالعطلات الأسبوعية',
      impactScore: 20,
      severity: 'medium',
      description: 'ملاحظة غياب منتظم أيام الأحد أو الخميس لتمديد عطلة نهاية الأسبوع.',
    });
  }

  attendanceScore = Math.min(100, attendanceScore);
  totalWeightedScore += attendanceScore * 0.35;

  // 2. تراجع مؤشرات الأداء KPIs (وزن 25%)
  let kpiScore = 0;
  if (metrics.currentKpiScore !== undefined && metrics.previousKpiScore !== undefined) {
    const drop = metrics.previousKpiScore - metrics.currentKpiScore;
    if (drop >= 20) {
      kpiScore = 90;
      factors.push({
        id: 'kpi_plunge',
        name: 'هبوط حاد في تقييم الأداء',
        impactScore: 90,
        severity: 'high',
        description: `انخفاض التقييم من ${metrics.previousKpiScore}% إلى ${metrics.currentKpiScore}% بفارق سلبي (${drop}%).`,
      });
    } else if (drop >= 10) {
      kpiScore = 45;
      factors.push({
        id: 'kpi_drop',
        name: 'تراجع ملحوظ في الأداء',
        impactScore: 45,
        severity: 'medium',
        description: `تراجع تقييم الموظف بنسبة ${drop}% مقارنة بالدورة السابقة.`,
      });
    }
  }
  totalWeightedScore += kpiScore * 0.25;

  // 3. النزاعات والشكاوى الإدارية (وزن 20%)
  let disputeScore = 0;
  if (metrics.activeDisputesCount > 0) {
    disputeScore += 60;
    factors.push({
      id: 'active_disputes',
      name: 'وجود نزاع أو تظلم إداري معلق',
      impactScore: 60,
      severity: 'high',
      description: `يوجد ${metrics.activeDisputesCount} نزاع أو تظلم قيد النظر أمام لجنة الحوكمة والنزاعات.`,
    });
  }
  if (metrics.warningsLast90Days > 0) {
    disputeScore += 40;
    factors.push({
      id: 'recent_warnings',
      name: 'صدور إنذار إداري حديث',
      impactScore: 40,
      severity: 'medium',
      description: `تم توجيه ${metrics.warningsLast90Days} إنذار رسمي خلال آخر 90 يوماً.`,
    });
  }
  disputeScore = Math.min(100, disputeScore);
  totalWeightedScore += disputeScore * 0.20;

  // 4. الإرهاق وضغط العمل وعدم أخذ الإجازات (وزن 10%)
  let burnoutScore = 0;
  if (metrics.daysSinceLastAnnualLeave > 240) {
    burnoutScore += 50;
    factors.push({
      id: 'leave_stagnation',
      name: 'مؤشر إرهاق (لم يأخذ إجازة سنوية منذ فترة طويلة)',
      impactScore: 50,
      severity: 'medium',
      description: `لم يقم الموظف بأي إجازة سنوية منذ أكثر من ${Math.round(metrics.daysSinceLastAnnualLeave / 30)} شهراً.`,
    });
  }
  if (metrics.overtimeHoursLastMonth >= 40) {
    burnoutScore += 50;
    factors.push({
      id: 'excessive_overtime',
      name: 'ساعات عمل إضافية مفرطة',
      impactScore: 50,
      severity: 'medium',
      description: `تسجيل ${metrics.overtimeHoursLastMonth} ساعة إضافية خلال الشهر الماضي.`,
    });
  }
  burnoutScore = Math.min(100, burnoutScore);
  totalWeightedScore += burnoutScore * 0.10;

  // 5. الركود الوظيفي (وزن 10%)
  let stagnationScore = 0;
  if (metrics.monthsInRole >= 24 && (!metrics.currentKpiScore || metrics.currentKpiScore >= 80)) {
    stagnationScore = 60;
    factors.push({
      id: 'career_stagnation',
      name: 'ركود وظيفي لأصحاب الأداء العالي',
      impactScore: 60,
      severity: 'low',
      description: `الموظف في نفس المسمى الوظيفي منذ ${metrics.monthsInRole} شهراً رغم أدائه الجيد دون ترقية.`,
    });
  }
  totalWeightedScore += stagnationScore * 0.10;

  const finalScore = Math.round(Math.min(100, Math.max(0, totalWeightedScore)));

  // تحديد مستوى الخطورة
  let riskLevel: RiskLevel = 'low';
  let recommendedAction = 'الموظف في حالة استقرار ممتازة. يُنصح بمواصلة التقدير الدوري للدوافع.';

  if (finalScore >= 75) {
    riskLevel = 'critical';
    recommendedAction = 'تدخل عاجل من مسؤول الـ HR والمدير المباشر: عقد جلسة استماع مغلقة (1-on-1)، معالجة أسباب النزاع، ومراجعة بيئة العمل فوراً لمنع استقالة مفاجئة.';
  } else if (finalScore >= 50) {
    riskLevel = 'high';
    recommendedAction = 'مخاطر استقالة مرتفعة: يُوصى بتشجيع الموظف على استنفاد جزء من رصيد إجازاته، وتخفيف ضغط العمل، ومراجعة أسباب تراجع الأداء الحالية.';
  } else if (finalScore >= 25) {
    riskLevel = 'medium';
    recommendedAction = 'متابعة دورية: تنبيه المشرف المباشر لمراقبة انتظام الدوام والتأكد من وضوح الأهداف الوظيفية للموظف.';
  }

  // ترتيب العوامل حسب التأثير
  factors.sort((a, b) => b.impactScore - a.impactScore);

  return {
    employeeId: metrics.employeeId,
    employeeName: metrics.fullName,
    overallScore: finalScore,
    riskLevel,
    confidenceScore: 88,
    assessedAt: new Date().toISOString(),
    topFactors: factors,
    recommendedAction,
  };
}
