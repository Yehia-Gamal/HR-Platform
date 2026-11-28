/**
 * قاموس الترجمة الموحد لجميع حالات النظام والقيم القادمة من قاعدة البيانات.
 * القاعدة: أي حالة أو قيمة enum قادمة من الخادم يجب تمريرها عبر `translateStatus`
 * قبل عرضها للمستخدم لضمان واجهة عربية متسقة وخالية من القيم الخام.
 */

export const STATUS_LABELS: Record<string, string> = {
  // الحالات العامة ودورة الحياة والتوظيف
  draft: 'مسودة',
  invited: 'تمت الدعوة',
  onboarding: 'قيد التهيئة',
  active: 'نشط',
  inactive: 'غير نشط',
  posted: 'منشور',
  applied: 'طلب جديد',
  new: 'جديد',
  screening: 'فرز أولي',
  shortlisted: 'القائمة المختصرة',
  interview: 'مقابلة',
  interviewing: 'قيد المقابلة',
  offer: 'عرض وظيفي',
  offered: 'تم تقديم العرض',
  hired: 'تم التعيين',
  accepted: 'مقبول',
  approved: 'معتمد',
  rejected: 'مرفوض',
  cancelled: 'ملغي',
  withdrawn: 'منسحب',
  declined: 'مرفوض من المرشح',
  revoked: 'ملغي الصلاحية',
  retired: 'متقاعد',
  suspended: 'موقوف',
  notice_period: 'فترة إخطار',
  terminated: 'منتهي',
  archived: 'مؤرشف',
  open: 'مفتوح',
  closed: 'مغلق',
  pending: 'قيد المراجعة',
  returned: 'معاد',
  escalated: 'مُصعَّدة',
  expired: 'منتهي الصلاحية',
  in_progress: 'قيد التنفيذ',
  completed: 'مكتمل',
  done: 'مكتمل',
  skipped: 'تم التجاوز',
  probation_failed: 'لم يجتز التجربة',

  // مراحل وحالات تقييم الأداء (KPI)
  self: 'التقييم الذاتي',
  manager_review: 'عند المدير المباشر',
  hr_review: 'مراجعة الموارد البشرية',
  parallel_review: 'مراجعة متوازية',
  manager_final: 'اعتماد المدير',
  secretary_review: 'مراجعة السكرتارية',
  executive_review: 'مراجعة الإدارة التنفيذية',
  finalized: 'مدرج في التقرير',
  not_started: 'لم يبدأ',
  overdue: 'متجاوز الموعد',
  employee_acknowledgement_pending: 'بانتظار إقرار الموظف',

  // النظام والنسخ الاحتياطي والقنوات والبيئات
  running: 'قيد التشغيل',
  queued: 'في الانتظار',
  succeeded: 'ناجح',
  success: 'ناجح',
  failed: 'فشل',
  error: 'خطأ',
  warning: 'تحذير',
  info: 'معلومات',
  notice: 'تنبيه',
  critical: 'حرج',
  edge: 'الدوال الخادمية',
  push: 'إشعار فوري',
  fcm: 'إشعار فوري',
  web_push: 'إشعارات المتصفح',
  email: 'البريد الإلكتروني',
  sms: 'الرسائل النصية',
  all: 'الكل',
  production: 'الإنتاج',
  staging: 'التجريب',
  development: 'التطوير',
};

function normalizeStatusKey(raw: string): string {
  return raw
    .trim()
    .toLowerCase()
    .replace(/[\s-]+/g, '_');
}

/**
 * يترجم أي قيمة حالة / enum إلى العربية من القاموس المركزي `STATUS_LABELS`.
 * يدعم اختلاف حالة الأحرف أو المسافات والشرطات (مثل `manager review` و`manager_review` و`MANAGER_REVIEW`).
 */
export function translateStatus(raw: string | null | undefined, fallback = '—'): string {
  if (!raw || !raw.trim()) return fallback;
  const trimmed = raw.trim();
  const normalized = normalizeStatusKey(trimmed);
  return STATUS_LABELS[trimmed] ?? STATUS_LABELS[normalized] ?? trimmed;
}

/**
 * يعرّب مصطلحات النظام الإنجليزية الشائعة داخل الرسائل التشخيصية القادمة من الخادم.
 */
export function translateSystemMessage(message: string | null | undefined): string {
  if (!message) return '—';
  return message
    .replace(/\bPush\b/g, 'فوري')
    .replace(/\bFeature Flags\b/gi, 'مفاتيح الميزات')
    .replace(/\bcompleted\b/gi, 'مكتمل')
    .replace(/\bhr_review\b/gi, 'مراجعة الموارد البشرية')
    .replace(/\bmanager[_\s]review\b/gi, 'عند المدير المباشر');
}
