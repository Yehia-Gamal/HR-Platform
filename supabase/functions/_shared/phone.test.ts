import { assertEquals } from "jsr:@std/assert";
import { normalizePhone, validateHrIssuedPassword } from "./phone.ts";

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

Deno.test("validateHrIssuedPassword: rejects <12 chars", () => {
  const r1 = validateHrIssuedPassword("Short1!aA", noIds);
  assertEquals(r1.ok, false);
  if (!r1.ok) assertEquals(r1.reason, "password_too_short_min_12");
});

Deno.test("validateHrIssuedPassword: rejects >72 chars", () => {
  const long = "Aa1!" + "x".repeat(80);
  const r = validateHrIssuedPassword(long, noIds);
  assertEquals(r.ok, false);
  if (!r.ok) assertEquals(r.reason, "password_too_long_max_72");
});

Deno.test("validateHrIssuedPassword: rejects missing uppercase", () => {
  const r = validateHrIssuedPassword("alllowercase1!ab", noIds);
  assertEquals(r.ok, false);
  if (!r.ok) assertEquals(r.reason, "password_needs_uppercase");
});

Deno.test("validateHrIssuedPassword: rejects missing lowercase", () => {
  const r = validateHrIssuedPassword("ALLUPPERCASE1!AB", noIds);
  assertEquals(r.ok, false);
  if (!r.ok) assertEquals(r.reason, "password_needs_lowercase");
});

Deno.test("validateHrIssuedPassword: rejects missing digit", () => {
  const r = validateHrIssuedPassword("NoDigitsHere!ab", noIds);
  assertEquals(r.ok, false);
  if (!r.ok) assertEquals(r.reason, "password_needs_digit");
});

Deno.test("validateHrIssuedPassword: rejects missing symbol", () => {
  const r = validateHrIssuedPassword("NoSymbolsHere1ab", noIds);
  assertEquals(r.ok, false);
  if (!r.ok) assertEquals(r.reason, "password_needs_symbol");
});

Deno.test("validateHrIssuedPassword: rejects character repetition (5+)", () => {
  const r = validateHrIssuedPassword("Aaaaa1!bbbbbcd", noIds);
  assertEquals(r.ok, false);
  if (!r.ok) assertEquals(r.reason, "password_too_repetitive");
});

Deno.test("validateHrIssuedPassword: rejects keyboard sequences", () => {
  const r1 = validateHrIssuedPassword("MyQwerty123!xz", noIds); // qwerty
  assertEquals(r1.ok, false);
  const r2 = validateHrIssuedPassword("MyPass1234!xzz", noIds); // 1234
  assertEquals(r2.ok, false);
});

Deno.test("validateHrIssuedPassword: rejects common words", () => {
  const r = validateHrIssuedPassword("MyPassword123!x", noIds);
  assertEquals(r.ok, false);
  if (!r.ok) assertEquals(r.reason, "password_contains_common_word");
});

Deno.test("validateHrIssuedPassword: rejects password containing email local part", () => {
  const r = validateHrIssuedPassword("Ahmed.work1!xy", { email: "ahmed.work@org.com" });
  assertEquals(r.ok, false);
  if (!r.ok) assertEquals(r.reason, "password_contains_identifier");
});

Deno.test("validateHrIssuedPassword: rejects password containing phone digits", () => {
  const r = validateHrIssuedPassword("Call1154869616!", { phone: "+201154869616" });
  assertEquals(r.ok, false);
});

Deno.test("validateHrIssuedPassword: accepts strong unique password", () => {
  const r = validateHrIssuedPassword("Tkx#vN2@pQ7!wJ4$", noIds);
  assertEquals(r.ok, true);
});

Deno.test("validateHrIssuedPassword: accepts 12-char strong boundary", () => {
  const r = validateHrIssuedPassword("Xk2!pNq#zM8@", noIds);
  assertEquals(r.ok, true);
});
