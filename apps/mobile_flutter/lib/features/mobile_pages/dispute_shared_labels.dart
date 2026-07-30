import 'package:flutter/material.dart';

/// ثوابت مشتركة لنظام القضايا والنزاعات.
/// مصدر الحقيقة: CommitteeDisputeListPage (الأكثر شمولاً).

// ── حالات القضايا ────────────────────────────────────────────────────────────

const disputeStatusLabels = <String, String>{
  'submitted': 'جديدة',
  'needs_more_information': 'تحتاج معلومات',
  'accepted': 'مقبولة',
  'under_review': 'قيد المراجعة',
  'waiting_for_respondent': 'بانتظار المشتكى عليه',
  'waiting_for_witness': 'بانتظار الشهود',
  'session_scheduled': 'جلسة محددة',
  'session_completed': 'جلسة منتهية',
  'committee_deliberation': 'مداولة اللجنة',
  'settlement_pending': 'تسوية معلقة',
  'escalated_to_executive': 'مصعّدة للتنفيذي',
  'returned_to_committee': 'معادة للجنة',
  'decision_issued': 'صدر قرار',
  'resolved_friendly': 'حُلّت ودياً',
  'action_proposed': 'إجراء مقترح',
  'pending_execution': 'بانتظار التنفيذ',
  'executed': 'تم التنفيذ',
  'closed': 'مغلقة',
  'reopened': 'أعيد فتحها',
  'rejected': 'مرفوضة',
  'cancelled_by_employee': 'ملغاة',
  'mediated': 'تم الوساطة',
};

const disputeStatusColors = <String, Color>{
  'submitted': Color(0xFF1565C0),
  'needs_more_information': Color(0xFFF57C00),
  'accepted': Color(0xFF2E7D32),
  'under_review': Color(0xFF6A1B9A),
  'waiting_for_respondent': Color(0xFF00838F),
  'waiting_for_witness': Color(0xFF00838F),
  'session_scheduled': Color(0xFF4527A0),
  'session_completed': Color(0xFF5E35B1),
  'committee_deliberation': Color(0xFF7B1FA2),
  'settlement_pending': Color(0xFF00838F),
  'escalated_to_executive': Color(0xFFD84315),
  'returned_to_committee': Color(0xFFF57C00),
  'decision_issued': Color(0xFF1B5E20),
  'resolved_friendly': Color(0xFF00695C),
  'action_proposed': Color(0xFFE65100),
  'pending_execution': Color(0xFFF9A825),
  'executed': Color(0xFF2E7D32),
  'closed': Color(0xFF616161),
  'reopened': Color(0xFF0277BD),
  'rejected': Color(0xFFC62828),
  'cancelled_by_employee': Color(0xFF9E9E9E),
  'mediated': Color(0xFF00695C),
};

// ── الإجراءات الإدارية ───────────────────────────────────────────────────────

const disputeAdminActionLabels = <String, String>{
  'verbal_warning': 'إنذار شفهي',
  'written_warning': 'إنذار كتابي',
  'final_warning': 'إنذار نهائي',
  'salary_deduction': 'خصم من الراتب',
  'suspension': 'إيقاف عن العمل',
  'demotion': 'تخفيض الدرجة',
  'termination': 'إنهاء الخدمة',
  'transfer': 'نقل',
  'training_requirement': 'تدريب إلزامي',
  'no_action': 'لا إجراء',
};

// ── الخطورة / الأولوية ──────────────────────────────────────────────────────

const disputeSeverityLabels = <String, String>{
  'critical': 'حرجة',
  'urgent': 'عاجلة',
  'high': 'عالية',
  'medium': 'متوسطة',
  'normal': 'عادية',
  'low': 'منخفضة',
};

const disputeSeverityColors = <String, Color>{
  'critical': Color(0xFFD32F2F),
  'urgent': Color(0xFFF57C00),
  'high': Color(0xFFFFA000),
  'medium': Color(0xFF1976D2),
  'normal': Color(0xFF757575),
  'low': Color(0xFF388E3C),
};

// ── أنواع القضايا ───────────────────────────────────────────────────────────

const disputeCaseTypeLabels = <String, String>{
  'complaint': 'شكوى',
  'grievance': 'تظلم',
  'disciplinary': 'تأديبي',
  'harassment': 'تحرش',
  'discrimination': 'تمييز',
  'policy_violation': 'مخالفة سياسة',
  'performance': 'أداء',
  'attendance': 'حضور وانصراف',
  'misconduct': 'سوء سلوك',
  'theft': 'سرقة',
  'safety': 'سلامة',
  'other': 'أخرى',
};

// ── دوال مساعدة ─────────────────────────────────────────────────────────────

/// تُرجع تسمية الحالة بالعربية، أو الكود الخام كـ fallback.
String disputeStatusLabel(String status) =>
    disputeStatusLabels[status] ?? status;

/// تُرجع لون الحالة، أو رمادي كـ fallback.
Color disputeStatusColor(String status) =>
    disputeStatusColors[status] ?? const Color(0xFF757575);

/// تُرجع تسمية الخطورة بالعربية، أو الكود الخام كـ fallback.
String disputeSeverityLabel(String severity) =>
    disputeSeverityLabels[severity] ?? severity;

/// تُرجع لون الخطورة، أو رمادي كـ fallback.
Color disputeSeverityColor(String severity) =>
    disputeSeverityColors[severity] ?? const Color(0xFF757575);

/// تُرجع تسمية الإجراء الإداري بالعربية، أو الكود الخام كـ fallback.
String disputeAdminActionLabel(String action) =>
    disputeAdminActionLabels[action] ?? action;

/// تُرجع تسمية نوع القضية بالعربية، أو الكود الخام كـ fallback.
String disputeCaseTypeLabel(String caseType) =>
    disputeCaseTypeLabels[caseType] ?? caseType;
