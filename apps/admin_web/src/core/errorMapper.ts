/**
 * V23 — خريطة أخطاء عربية
 * يُحوّل رسائل الأخطاء التقنية (Supabase / Zod / HTTP / شبكة) إلى رسائل عربية آمنة
 * مع تسجيل التفاصيل التقنية ورمز تتبع في وحدة التحكم لفريق الدعم.
 *
 * المتطلبات V23 §05:
 *  – لا Zod/Supabase stack للمستخدم
 *  – Error mapper عربي
 *  – Correlation ID
 */

// ─── أنماط معروفة ← رسائل عربية ─────────────────────────────────────────────
const ERROR_PATTERNS: Array<[RegExp, string]> = [
  // RLS / صلاحيات
  [/^FORBIDDEN$/i, 'ليس لديك صلاحية لهذا الإجراء.'],
  [/row.level security/i, 'ليس لديك صلاحية لهذا الإجراء.'],
  [/permission denied/i, 'ليس لديك صلاحية لهذا الإجراء.'],
  [/insufficient_privilege/i, 'ليس لديك صلاحية لهذا الإجراء.'],

  // قيود قاعدة البيانات
  [/violates unique constraint|duplicate key/i, 'هذا السجل موجود بالفعل.'],
  [/violates foreign key/i, 'لا يمكن تنفيذ الإجراء — توجد سجلات مرتبطة.'],
  [/violates check constraint/i, 'القيمة المدخلة غير مقبولة.'],
  [/violates not.null|null value in column/i, 'حقل مطلوب في قاعدة البيانات مفقود القيمة. تحقق من بيانات الإعداد الأساسية.'],
  [/no rows returned/i, 'لم يُعثر على السجل المطلوب.'],
  [/invalid input syntax/i, 'القيمة المدخلة غير صالحة.'],
  [/column .* does not exist|column .* of relation .* does not exist/i, 'عمود في قاعدة البيانات مفقود (ربما لم تكتمل ترقية).'],
  [/relation .* does not exist/i, 'جدول في قاعدة البيانات مفقود (ربما لم تكتمل ترقية).'],

  // Supabase RPC / Edge Functions
  [/Could not find.*function|PGRST202|schema cache/i, 'الخدمة لم تُحدَّث بعد آخر تغيير. أعد تحميل الصفحة بعد قليل أو تواصل مع مدير النظام لتحديث مخزن الخدمة.'],
  [/function.*does not exist/i, 'الخدمة غير متوفرة حاليًا. أعد المحاولة لاحقًا.'],
  [/Edge Function returned a non-2xx/i, 'فشل تنفيذ العملية على الخادم. أعد المحاولة لاحقًا.'],

  // مصادقة / JWT
  [/JWT expired/i, 'انتهت صلاحية الجلسة. سجّل الدخول مجددًا.'],
  [/invalid.*token/i, 'انتهت صلاحية الجلسة. سجّل الدخول مجددًا.'],
  [/refresh_token_not_found/i, 'انتهت صلاحية الجلسة. سجّل الدخول مجددًا.'],
  [/Invalid login credentials/i, 'بيانات الدخول غير صحيحة.'],
  [/Email not confirmed/i, 'البريد الإلكتروني غير مفعّل بعد.'],

  // أخطاء اعتبارية شائعة من إجراءات KPI المُخزنة
  [/ONLY_OFFICIAL_KPI_TEMPLATE_IS_ALLOWED/i, 'لا يمكن إنشاء دورة إلا بالقالب الرسمي OFFICIAL_KPI_100.'],
  [/INVALID_CYCLE_STATE/i, 'حالة الدورة الحالية لا تسمح بهذا الإجراء.'],
  [/INVALID_CYCLE_ACTION/i, 'الإجراء المطلوب على الدورة غير معروف.'],
  [/CONTROL_REASON_REQUIRED/i, 'سبب الإجراء الإداري مطلوب (٥ أحرف على الأقل).'],
  [/\bREASON_REQUIRED\b/i, 'سبب التعديل مطلوب (٥ أحرف على الأقل).'],
  [/CYCLE_ALREADY_STARTED/i, 'لا يمكن إلغاء فتح الدورة — بدأها بعض الموظفين بالفعل.'],
  [/CYCLE_MUST_BE_CLOSED/i, 'يجب إغلاق الدورة قبل هذه الخطوة.'],
  [/CYCLE_NOT_FOUND/i, 'لم يُعثر على دورة KPI المطلوبة.'],
  [/INVALID_SCHEDULE/i, 'تواريخ الجدولة غير صالحة.'],
  [/APPEAL_ALREADY_DECIDED/i, 'هذا الاعتراض تم البتّ فيه سابقًا.'],
  [/INVALID_APPEAL_DECISION/i, 'قرار الاعتراض أو ملاحظاته غير مكتملة.'],

  // أخطاء إجراءات الموظفين (أرشفة / حذف نهائي)
  [/delete_confirmation_mismatch/i, 'رمز التأكيد غير صحيح. اكتب كود الموظف تماماً كما هو معروض في الحقل.'],
  [/employee_history_requires_archive/i, 'لا يمكن الحذف النهائي — توجد سجلات مرتبطة (حضور، طلبات، أداء، مستندات...). أرشِف الموظف بدلاً من الحذف.'],
  [/manager_has_direct_reports/i, 'لا يمكن حذف هذا الموظف — لديه مرؤوسون مباشرون. أعد إسنادهم لمدير آخر أولاً.'],
  [/main_admin_required/i, 'ليست لديك صلاحية حذف هذا الموظف.'],
  [/self_delete_not_allowed/i, 'لا يمكن حذف حسابك الحالي.'],
  [/delete_reason_required/i, 'سبب الحذف مطلوب (١٠ أحرف على الأقل).'],
  [/self_archive_not_allowed/i, 'لا يمكن أرشفة حسابك الحالي.'],
  [/archive_reason_required/i, 'سبب الأرشفة مطلوب (٥ أحرف على الأقل).'],
  [/employee_not_found/i, 'لم يُعثر على الموظف — ربما حُذف من مستخدم آخر. أعد تحميل الصفحة.'],
  [/employee_data_incomplete/i, 'بيانات الموظف غير مكتملة — بعض الحقول الأساسية ناقصة. تواصل مع الإدارة لإكمال الملف.'],

  // HTTP status codes في الرسائل
  [/\b401\b/, 'انتهت صلاحية الجلسة. سجّل الدخول مجددًا.'],
  [/\b42501\b/, 'ليس لديك صلاحية لهذا الإجراء.'],
  [/\b403\b/, 'ليس لديك صلاحية لهذا الإجراء.'],
  [/\b404\b/, 'لم يُعثر على المورد المطلوب.'],
  [/\b409\b/, 'تعارض — السجل تم تعديله من مستخدم آخر. أعد التحميل.'],
  [/\b429\b/, 'طلبات كثيرة. انتظر قليلاً ثم أعد المحاولة.'],
  [/\b50[0-9]\b/, 'خطأ في الخادم. أعد المحاولة لاحقًا.'],

  // شبكة
  [/Failed to fetch/i, 'تعذر الاتصال بالخادم. تحقق من اتصال الإنترنت.'],
  [/NetworkError/i, 'تعذر الاتصال بالخادم. تحقق من اتصال الإنترنت.'],
  [/timeout/i, 'انتهت مهلة الاتصال. أعد المحاولة.'],
  [/aborted/i, 'تم إلغاء العملية.'],

  // تخزين / رفع ملفات
  [/Payload too large|413/i, 'حجم الملف كبير جدًا.'],
  [/unsupported.*media/i, 'نوع الملف غير مدعوم.'],
];

const FALLBACK_MESSAGE = 'حدث خطأ غير متوقع. أعد المحاولة أو تواصل مع الدعم.';

/** رمز تتبع قصير (8 أحرف) — مطابق لنمط AppErrorBoundary */
function correlationId(): string {
  return crypto.randomUUID().slice(0, 8).toUpperCase();
}

/**
 * يُحوّل خطأ تقني إلى رسالة عربية آمنة مع رمز تتبع.
 * يُسجّل الخطأ الأصلي مع رمز التتبع في console.error للدعم.
 *
 * الاستخدام:
 * ```tsx
 * <ErrorState description={safeErrorMessage(query.error)} onRetry={...} />
 * ```
 */
export function safeErrorMessage(error: unknown): string {
  const cid = correlationId();
  const raw = error instanceof Error ? error.message : typeof error === 'string' ? error : String(error ?? '');

  // تسجيل الخطأ الأصلي مع رمز التتبع — لا يظهر للمستخدم
  if (import.meta.env.DEV) console.error(`[خطأ ${cid}]`, error);

  for (const [pattern, arabicMessage] of ERROR_PATTERNS) {
    if (pattern.test(raw)) {
      return `${arabicMessage} (${cid})`;
    }
  }

  return `${FALLBACK_MESSAGE} (${cid})`;
}
