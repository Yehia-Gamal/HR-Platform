import { assertEquals } from "jsr:@std/assert";
import { normalizePhone } from "./phone.ts";

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
