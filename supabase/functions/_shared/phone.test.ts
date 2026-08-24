import { assertEquals } from "jsr:@std/assert";
import { generateSecureTemporaryPassword, normalizePhone, validateHrIssuedPassword } from "./phone.ts";

Deno.test("normalizePhone: local Egyptian 01… -> +20…", () => {
  assertEquals(normalizePhone("01154869616"), "+201154869616");
  assertEquals(normalizePhone("01012345678"), "+201012345678");
});

Deno.test("normalizePhone: already E.164 is unchanged", () => {
  assertEquals(normalizePhone("+201154869616"), "+201154869616");
  assertEquals(normalizePhone("+14155552671"), "+14155552671");
});

Deno.test("normalizePhone: trims surrounding whitespace", () => {
  assertEquals(normalizePhone("  01154869616  "), "+201154869616");
  assertEquals(normalizePhone(" +201154869616 "), "+201154869616");
});

Deno.test("normalizePhone: non-local formats pass through untouched", () => {
  // ليس 11 رقماً يبدأ بـ 01 — يُترك كما هو ليتكفّل به التحقق في الـ schema.
  assertEquals(normalizePhone("0115486"), "0115486");
  assertEquals(normalizePhone("201154869616"), "201154869616");
});

const noIds = {};

// السياسة المبسّطة (طلب الإدارة): 6–72 حرفاً بلا شروط تعقيد أخرى.

Deno.test("validateHrIssuedPassword: rejects <6 chars", () => {
  const r1 = validateHrIssuedPassword("Ab1!x", noIds); // 5 أحرف
  assertEquals(r1.ok, false);
  if (!r1.ok) assertEquals(r1.reason, "password_too_short_min_6");
  const r2 = validateHrIssuedPassword("", noIds);
  assertEquals(r2.ok, false);
});

Deno.test("validateHrIssuedPassword: rejects >72 chars", () => {
  const long = "x".repeat(73);
  const r = validateHrIssuedPassword(long, noIds);
  assertEquals(r.ok, false);
  if (!r.ok) assertEquals(r.reason, "password_too_long_max_72");
});

Deno.test("validateHrIssuedPassword: accepts simple 6-char passwords", () => {
  // بلا شروط تعقيد: أرقام فقط / أحرف بسيطة — كلها مقبولة من 6 أحرف.
  for (const p of ["123456", "abc123", "000000", "Pass1!"]) {
    const r = validateHrIssuedPassword(p, noIds);
    assertEquals(r.ok, true, `simple password must pass: ${p}`);
  }
});

Deno.test("validateHrIssuedPassword: accepts 6-char boundary and long passwords", () => {
  assertEquals(validateHrIssuedPassword("Abc12!", noIds).ok, true); // 6 بالضبط
  assertEquals(validateHrIssuedPassword("Aa1!" + "x".repeat(68), noIds).ok, true); // 72 بالضبط
  // كلمات قوية قديمة تبقى صالحة (توافق backward لمن يملكها).
  assertEquals(validateHrIssuedPassword("Vk9!xN2@wQ7$mP4", noIds).ok, true);
});

Deno.test("validateHrIssuedPassword: identifiers no longer reject (سياسة مبسطة)", () => {
  // أُزيلت قواعد المعرّفات/القواميس/التسلسلات — كلمات تحويها تُقبل الآن.
  const r = validateHrIssuedPassword("Ahmed.work1!", { email: "ahmed.work@org.com" });
  assertEquals(r.ok, true);
});

// كلمة المرور المؤقتة المولّدة: 6 أرقام بسيطة وتجتاز الـ validator دائماً.
Deno.test("generateSecureTemporaryPassword: produces 6-digit numeric passwords", () => {
  const seen = new Set<string>();
  for (let i = 0; i < 50; i++) {
    const p = generateSecureTemporaryPassword();
    assertEquals(p.length, 6);
    assertEquals(/^\d{6}$/.test(p), true, `must be 6 digits: ${p}`);
    assertEquals(p.startsWith("0"), false, "must not start with 0");
    const r = validateHrIssuedPassword(p, noIds);
    assertEquals(r.ok, true, `generated password must validate: ${p}`);
    seen.add(p);
  }
  // 50 توليداً من 900,000 احتمال — التكرار شبه مستحيل لكن لا نفرضه صرامة.
  assertEquals(seen.size > 40, true, "should be mostly unique");
});
