// تطبيع رقم الهاتف إلى صيغة E.164.
// المحلي المصري 01XXXXXXXXX ← ‎+20XXXXXXXXX. الأرقام الدولية تُترك كما هي.
// يضمن ثبات الفهرس الفريد ux_employees_phone_e164_active.
export function normalizePhone(raw: string): string {
  const trimmed = raw.trim();
  if (/^01\d{9}$/.test(trimmed)) return `+20${trimmed.slice(1)}`;
  return trimmed;
}

/**
 * التحقق من قوة كلمة المرور التي يحددها مسؤول HR يدوياً.
 * نفرض:
 *  - طول ≥ 12 حرفاً وألا يتجاوز 72 (حد argon2/GoTrue)
 *  - حرف كبير واحد على الأقل + حرف صغير واحد على الأقل + رقم واحد على الأقل + رمز خاص واحد على الأقل
 *  - لا تحتوي على جزء ≥ 4 أحرف متطابق مع بريد/هاتف/كود الموظف/اسمه
 *  - لا تتكون من كلمات قاموسية شائعة (عربية/لاتينية)
 *  - لا تتكون من سلاسل لوحة مفاتيح مألوفة (qwerty, 123456, …)
 *  - لا تكرار أكثر من 4 مرات لنفس الحرف على التوالي
 */
export function validateHrIssuedPassword(
  password: string,
  identifiers: { email?: string; phone?: string; employeeCode?: string; fullNameAr?: string },
): { ok: true } | { ok: false; reason: string } {
  if (typeof password !== "string" || password.length < 12) {
    return { ok: false, reason: "password_too_short_min_12" };
  }
  if (password.length > 72) {
    return { ok: false, reason: "password_too_long_max_72" };
  }

  if (!/[A-Z]/.test(password)) return { ok: false, reason: "password_needs_uppercase" };
  if (!/[a-z]/.test(password)) return { ok: false, reason: "password_needs_lowercase" };
  if (!/\d/.test(password)) return { ok: false, reason: "password_needs_digit" };
  if (!/[!@#$%^&*()_\-+=[\]{};':"\\|,.<>/?`~]/.test(password)) {
    return { ok: false, reason: "password_needs_symbol" };
  }

  // رفض التكرار المفرط: 5+ من نفس الحرف على التوالي ضعيف.
  if (/(.)\1{4,}/.test(password)) {
    return { ok: false, reason: "password_too_repetitive" };
  }

  // سلاسل لوحة/ترتيب شائعة (4+ أحرف متتالية)
  const sequences = [
    "qwertyuiop", "asdfghjkl", "zxcvbnm",
    "abcdefghijklmnopqrstuvwxyz",
    "0123456789", "١٢٣٤٥٦٧٨٩٠",
  ];
  const lower = password.toLowerCase();
  for (const seq of sequences) {
    const forward = seq.toLowerCase();
    const backward = [...forward].reverse().join("");
    for (let i = 0; i + 4 <= forward.length; i++) {
      const chunk = forward.slice(i, i + 4);
      if (lower.includes(chunk)) return { ok: false, reason: "password_keyboard_sequence" };
    }
    for (let i = 0; i + 4 <= backward.length; i++) {
      const chunk = backward.slice(i, i + 4);
      if (lower.includes(chunk)) return { ok: false, reason: "password_keyboard_sequence" };
    }
  }

  // كلمات قاموسية شائعة (عربية + لاتينية)
  const commonWords = [
    "password", "admin", "user", "login", "welcome", "letmein", "iloveyou",
    "احبتك", "مرحبا", "كلمهالسر", "كلمةالسر", "كلمةالمرور", "باسورد", "سكرت",
    "الله", "محمد", "احمد", "قاهرة", "مصر", "السعودية",
  ];
  for (const w of commonWords) {
    if (lower.includes(w.toLowerCase())) {
      return { ok: false, reason: "password_contains_common_word" };
    }
  }

  // لا تضمين معرّفات الموظف (سلاسل ≥ 4 أحرف متطابقة مع أي معرّف)
  const parts: string[] = [];
  for (const v of Object.values(identifiers)) {
    if (!v) continue;
    const s = String(v).toLowerCase();
    if (s.length >= 4) parts.push(s);
    // أجزاء البريد قبل @
    const local = s.split("@")[0];
    if (local && local.length >= 4) parts.push(local);
    // أجزاء الاسم (split بالمسافات)
    for (const token of s.split(/[\s\u0600-\u06FF]+/)) {
      if (token.length >= 4) parts.push(token.toLowerCase());
    }
    // للهاتف: نتجاهل رمز الدولة (+20) ونقارن الجوهر بلا الصفر المحلي
    if (s.startsWith("+2")) parts.push(s.slice(3));
    if (s.startsWith("+")) parts.push(s.slice(1));
  }
  // ملاحظة: لا نضيف أجزاءً من كلمة المرور نفسها إلى parts — أي جزء منها
  // سيُطابق دائماً (password.includes(first6)) ويرفض كل كلمة مرور صحيحة.

  for (const p of parts) {
    if (!p || p.length < 4) continue;
    if (lower.includes(p)) {
      return { ok: false, reason: "password_contains_identifier" };
    }
  }

  return { ok: true };
}

// مجموعات أحرف لكلمات المرور المؤقتة (نستبعد المحيّرة: 0/O, 1/l/I).
const TEMP_POOL = {
  upper: "ABCDEFGHJKLMNPQRSTUVWXYZ",
  lower: "abcdefghjkmnpqrstuvwxyz",
  digit: "23456789",
  symbol: "!@#$%&*?-_",
};

function tempRand(max: number): number {
  const buf = new Uint32Array(1);
  crypto.getRandomValues(buf);
  return buf[0] % max;
}

/**
 * كلمة مرور مؤقتة عشوائية آمنة (12 حرفاً) تُمرَّر للموظف عبر رابط البريد فقط.
 * نضمن حرفاً كبيراً وصغيراً ورقماً ورمزاً خاصاً واحداً على الأقل (سياسة
 * validateHrIssuedPassword الموحدة) ولا أي معرّف للموظف. تُفرض تغييرها عند
 * أول دخول عبر must_change_password فلا تبقى سارية. لا نعتمد أبداً على اشتقاق
 * من رقم الهاتف/الكود (كان ذلك قابلاً للتخمين من مسرِّب بيانات).
 */
export function generateSecureTemporaryPassword(): string {
  const length = 12;
  const alnum = TEMP_POOL.upper + TEMP_POOL.lower + TEMP_POOL.digit;
  const chars: string[] = [];
  for (const cat of Object.values(TEMP_POOL)) chars.push(cat[tempRand(cat.length)]);
  while (chars.length < length) chars.push(alnum[tempRand(alnum.length)]);
  // Fisher–Yates بخلط حقيقي عشوائي (لا نكتفي بالـ push البسيط).
  for (let i = chars.length - 1; i > 0; i--) {
    const j = tempRand(i + 1);
    [chars[i], chars[j]] = [chars[j], chars[i]];
  }
  return chars.join("");
}
