// تطبيع رقم الهاتف إلى صيغة E.164.
// المحلي المصري 01XXXXXXXXX ← ‎+20XXXXXXXXX. الأرقام الدولية تُترك كما هي.
// يضمن ثبات الفهرس الفريد ux_employees_phone_e164_active.
export function normalizePhone(raw: string): string {
  const trimmed = raw.trim();
  if (/^01\d{9}$/.test(trimmed)) return `+20${trimmed.slice(1)}`;
  return trimmed;
}

/**
 * التحقق من كلمة المرور التي يحددها مسؤول HR يدوياً — سياسة مبسّطة (طلب الإدارة):
 *  - طول ≥ 6 أحرف وألا يتجاوز 72 (حد argon2/GoTrue)
 *  - لا شروط تعقيد أخرى (أحرف كبيرة/صغيرة/أرقام/رموز اختيارية)
 */
export function validateHrIssuedPassword(
  password: string,
  _identifiers?: { email?: string; phone?: string; employeeCode?: string; fullNameAr?: string },
): { ok: true } | { ok: false; reason: string } {
  if (typeof password !== "string" || password.length < 6) {
    return { ok: false, reason: "password_too_short_min_6" };
  }
  if (password.length > 72) {
    return { ok: false, reason: "password_too_long_max_72" };
  }
  return { ok: true };
}

function tempRand(max: number): number {
  const buf = new Uint32Array(1);
  crypto.getRandomValues(buf);
  return buf[0] % max;
}

/**
 * كلمة مرور مؤقتة بسيطة: 6 أرقام (طلب الإدارة — سهلة الإملاء على الهاتف).
 * تطابق validateHrIssuedPassword (6+ أحرف بلا شروط أخرى) ويُفرض تغييرها عند
 * أول دخول عبر must_change_password فلا تبقى سارية.
 */
export function generateSecureTemporaryPassword(): string {
  let out = "";
  for (let i = 0; i < 6; i++) out += String(tempRand(10));
  // لا نبدأ بصفر (بعض الواجهات تقص الأصفار البادئة عند الإدخال الرقمي).
  if (out.startsWith("0")) out = String(1 + tempRand(9)) + out.slice(1);
  return out;
}
