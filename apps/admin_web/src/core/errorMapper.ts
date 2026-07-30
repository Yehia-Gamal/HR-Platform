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
  [/violates not.null/i, 'حقل مطلوب لم يتم ملؤه.'],
  [/no rows returned/i, 'لم يُعثر على السجل المطلوب.'],
  [/invalid input syntax/i, 'القيمة المدخلة غير صالحة.'],

  // Supabase RPC / Edge Functions
  [/Could not find.*function/i, 'الخدمة غير متوفرة حاليًا. أعد المحاولة لاحقًا.'],
  [/function.*does not exist/i, 'الخدمة غير متوفرة حاليًا. أعد المحاولة لاحقًا.'],
  [/Edge Function returned a non-2xx/i, 'فشل تنفيذ العملية على الخادم. أعد المحاولة لاحقًا.'],

  // مصادقة / JWT
  [/JWT expired/i, 'انتهت صلاحية الجلسة. سجّل الدخول مجددًا.'],
  [/invalid.*token/i, 'انتهت صلاحية الجلسة. سجّل الدخول مجددًا.'],
  [/refresh_token_not_found/i, 'انتهت صلاحية الجلسة. سجّل الدخول مجددًا.'],
  [/Invalid login credentials/i, 'بيانات الدخول غير صحيحة.'],
  [/Email not confirmed/i, 'البريد الإلكتروني غير مفعّل بعد.'],

  // HTTP status codes في الرسائل
  [/\b401\b/, 'انتهت صلاحية الجلسة. سجّل الدخول مجددًا.'],
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
  const raw = error instanceof Error
    ? error.message
    : typeof error === 'string' ? error : String(error ?? '');

  // تسجيل الخطأ الأصلي مع رمز التتبع — لا يظهر للمستخدم
  if (import.meta.env.DEV) console.error(`[خطأ ${cid}]`, error);

  for (const [pattern, arabicMessage] of ERROR_PATTERNS) {
    if (pattern.test(raw)) {
      return `${arabicMessage} (${cid})`;
    }
  }

  return `${FALLBACK_MESSAGE} (${cid})`;
}
