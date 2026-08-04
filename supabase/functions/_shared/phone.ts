// تطبيع رقم الهاتف إلى صيغة E.164.
// المحلي المصري 01XXXXXXXXX ← ‎+20XXXXXXXXX. الأرقام الدولية تُترك كما هي.
// يضمن ثبات الفهرس الفريد ux_employees_phone_e164_active.
export function normalizePhone(raw: string): string {
  const trimmed = raw.trim();
  if (/^01\d{9}$/.test(trimmed)) return `+20${trimmed.slice(1)}`;
  return trimmed;
}

// كلمة المرور المؤقتة عند إنشاء الحساب/إعادة ضبطها = رقم هاتف الموظف،
// بصيغة يعرفها الموظف نفسه: المصري 01XXXXXXXXX، والدولي يُترك كما هو بـ +...
// تُفرض سياسة تغييرها عند أول دخول عبر must_change_password فلا تبقى سارية.
export function temporaryPasswordFromPhone(phoneE164: string): string {
  const local = /^\+20(1\d{9})$/.exec(phoneE164);
  return local ? `0${local[1]}` : phoneE164;
}
