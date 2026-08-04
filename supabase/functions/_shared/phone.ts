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
 *  - طول ≥ 12 حرف
 *  - حرف كبير + حرف صغير + رقم + رمز على الأقل واحد من كل
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
    // GoTrue/argon2 يقوّم ما بعد 72 بايت — نقيّد مسبقاً لتجنب مفاجآت.
    return { ok: false, reason: "password_too_long_max_72" };
  }

  if (!/[A-Z]/.test(password)) return { ok: false, reason: "password_needs_uppercase" };
  if (!/[a-z]/.test(password)) return { ok: false, reason: "password_needs_lowercase" };
  if (!/\d/.test(password)) return { ok: false, reason: "password_needs_digit" };
  if (!/[!@#$%^&*()_\-+=[\]{};':"\\|,.<>/?`~]/.test(password)) {
    return { ok: false, reason: "password_needs_symbol" };
  }

  // رفض التكرار المفرط: 5+ من نفس الحرب على التوالي ضعيف.
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
    // للهاتف: نتجاهل رمز الدولة (+20) ونقارن الجوهر
    if (s.startsWith("+2")) parts.push(s.slice(2));
    if (s.startsWith("+")) parts.push(s.slice(1));
  }
  parts.push(password.slice(0, 6).toLowerCase()); // منع self-match trivial

  for (const p of parts) {
    if (!p || p.length < 4) continue;
    if (lower.includes(p)) {
      return { ok: false, reason: "password_contains_identifier" };
    }
  }

  return { ok: true };
}
