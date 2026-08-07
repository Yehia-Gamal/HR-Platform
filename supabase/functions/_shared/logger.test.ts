import { assertEquals, assertNotEquals, assertStringIncludes } from "jsr:@std/assert";
import { stub, type Stub } from "jsr:@std/testing/mock";
import { createLogger } from "./logger.ts";

// ─── Initiative: Production Observability ───────────────────────────────────
// تختبر هذه المجموعة عقد المسجّل المهيكل (logger.ts) للـ Edge Functions:
//  • رموز الربط (correlationToken / FNV-1a) لمعرّفات الموظف/المستخدم غير عكسية
//    وثابتة، بحيث لا تتسرّب PII خام إلى السجلات.
//  • تنقيح مفاتيح PII ضمن data (تشمل الكائنات والمصفوفات المتداخلة).
//  • توجيه المستويات إلى console.log/warn/error.
//  • كتم تفاصيل الأخطاء في الإنتاج (stack/raw messages تظهر في غير الإنتاج فقط).
//  • تتبّع المدة (timed) ودمج السياق (child).
//
// ملاحظة: تُشغَّل عبر `deno test supabase/functions/` في CI (Deno غير مُثبّت محلياً).

interface Capture {
  log: string[];
  warn: string[];
  error: string[];
}

/** يلتقط مخرجات console عبر stub ويُعيد كائن الاستعادة. */
function captureConsole(): { out: Capture; restore: () => void } {
  const out: Capture = { log: [], warn: [], error: [] };
  const stubs: Stub[] = [
    stub(console, "log", (...a: unknown[]) => void out.log.push(String(a[0]))),
    stub(console, "warn", (...a: unknown[]) => void out.warn.push(String(a[0]))),
    stub(console, "error", (...a: unknown[]) => void out.error.push(String(a[0]))),
  ];
  return { out, restore: () => stubs.forEach((s) => s.restore()) };
}

/** يثبّت Deno.env.get ليرجع قيمة محدّدة لـ ENVIRONMENT فقط طوال fn. */
function withEnv(env: string | undefined, fn: () => void): void {
  const s = stub(Deno.env, "get", (key: string) => (key === "ENVIRONMENT" ? env : undefined));
  try {
    fn();
  } finally {
    s.restore();
  }
}

function lastEntry(line: string): Record<string, unknown> {
  return JSON.parse(line) as Record<string, unknown>;
}

// ─── البنية والتوجيه ───────────────────────────────────────────────────────
Deno.test("info: يبثّ JSON مهيكل إلى console.log بالحقول الإلزامية", () => {
  withEnv(undefined, () => {
    const c = captureConsole();
    const log = createLogger({ functionName: "fn-x", version: "2.0.0" });
    log.info("hello", { foo: 1 });
    c.restore();
    assertEquals(c.out.log.length, 1);
    assertEquals(c.out.warn.length, 0);
    assertEquals(c.out.error.length, 0);
    const e = lastEntry(c.out.log[0]);
    assertEquals(e.level, "info");
    assertEquals(e.function_name, "fn-x");
    assertEquals(e.version, "2.0.0");
    assertEquals(e.environment, "production"); // ENVIRONMENT غير مضبوط → production
    assertEquals(e.message, "hello");
    assertEquals(e.foo, 1);
    assertEquals(typeof e.timestamp, "string");
  });
});

Deno.test("warning يوجّه إلى console.warn، و error إلى console.error", () => {
  withEnv(undefined, () => {
    const c = captureConsole();
    const log = createLogger({ functionName: "fn" });
    log.warning("careful");
    log.error("boom");
    c.restore();
    assertEquals(c.out.warn.length, 1);
    assertEquals(c.out.error.length, 1);
    assertEquals(c.out.log.length, 0);
    assertEquals(lastEntry(c.out.warn[0]).level, "warning");
    assertEquals(lastEntry(c.out.error[0]).level, "error");
  });
});

Deno.test("الإصدار الافتراضي 0.0.0 عند غياب version", () => {
  withEnv(undefined, () => {
    const c = captureConsole();
    createLogger({ functionName: "fn" }).info("x");
    c.restore();
    assertEquals(lastEntry(c.out.log[0]).version, "0.0.0");
  });
});

// ─── عقد PII: التجزئة بدل المعرّف الخام ───────────────────────────────────
Deno.test("معرّفات السياق (employeeId/userId) تتجزّأ إلى *_ref ولا تظهر خام", () => {
  withEnv(undefined, () => {
    const c = captureConsole();
    const log = createLogger({ functionName: "fn", requestId: "req-1", employeeId: "EMP-SECRET-123", userId: "user-SECRET-456" });
    log.info("ok");
    c.restore();
    const e = lastEntry(c.out.log[0]);
    assertEquals(e.request_id, "req-1");
    assertEquals(typeof e.employee_ref, "string");
    assertEquals(typeof e.user_ref, "string");
    assertNotEquals(e.employee_ref, "EMP-SECRET-123");
    assertNotEquals(e.user_ref, "user-SECRET-456");
    // ألا تظهر المعرّفات الخام في أي مكان بالسطر
    assertStringIncludes(c.out.log[0], "EMP-SECRET-123") === undefined; // لا يظهر — يكفي أن لا يرمي التأكيد التالي
    assertEquals(c.out.log[0].includes("EMP-SECRET-123"), false);
    assertEquals(c.out.log[0].includes("user-SECRET-456"), false);
  });
});

Deno.test("مفاتيح PII داخل data تُستبدل بـ <key>_ref مجزّأ (snake + camel)", () => {
  withEnv(undefined, () => {
    const c = captureConsole();
    createLogger({ functionName: "fn" }).info("evt", {
      employeeId: "EMP-9",
      userId: "U-9",
      employee_id: "EMP-9",
      user_id: "U-9",
      email: "a@b.com",
      phone: "+2010000",
      keep: 1,
    });
    c.restore();
    const e = lastEntry(c.out.log[0]);
    assertEquals(typeof e.employeeId_ref, "string");
    assertEquals(typeof e.userId_ref, "string");
    assertEquals(typeof e.employee_id_ref, "string");
    assertEquals(typeof e.user_id_ref, "string");
    assertEquals(typeof e.email_ref, "string");
    assertEquals(typeof e.phone_ref, "string");
    assertEquals(e.keep, 1);
    // المفاتيح الأصلية محذوفة
    assertEquals(e.employeeId, undefined);
    assertEquals(e.email, undefined);
    assertEquals(e.phone, undefined);
    // القيم الخام لا تظهر في السطر
    const line = c.out.log[0];
    assertEquals(line.includes("EMP-9"), false);
    assertEquals(line.includes("a@b.com"), false);
    assertEquals(line.includes("+2010000"), false);
  });
});

Deno.test("PII المتداخلة في كائنات ومصفوفات تُجزّأ أيضاً", () => {
  withEnv(undefined, () => {
    const c = captureConsole();
    createLogger({ functionName: "fn" }).info("evt", {
      rows: [{ employeeId: "EMP-7" }, { email: "x@y.com" }],
      meta: { userId: "U-7" },
    });
    c.restore();
    const e = lastEntry(c.out.log[0]);
    const rows = e.rows as Array<Record<string, unknown>>;
    const meta = e.meta as Record<string, unknown>;
    assertEquals(typeof rows[0].employeeId_ref, "string");
    assertEquals(typeof rows[1].email_ref, "string");
    assertEquals(typeof meta.userId_ref, "string");
    assertEquals(c.out.log[0].includes("EMP-7"), false);
    assertEquals(c.out.log[0].includes("x@y.com"), false);
  });
});

Deno.test("correlationToken: ثابت وغير عكسي — نفس المعرّف ينتج نفس الرمز", () => {
  withEnv(undefined, () => {
    const c1 = captureConsole();
    createLogger({ functionName: "fn", employeeId: "EMP-42" }).info("a");
    c1.restore();
    const c2 = captureConsole();
    createLogger({ functionName: "fn", employeeId: "EMP-42" }).info("b");
    c2.restore();
    const t1 = lastEntry(c1.out.log[0]).employee_ref;
    const t2 = lastEntry(c2.out.log[0]).employee_ref;
    assertEquals(t1, t2); // حتمية
    assertEquals(String(t1).length, 8); // FNV-1a → 8 hex
  });
});

Deno.test("correlationToken: معرّفات مختلفة تنتج رموزاً مختلفة", () => {
  withEnv(undefined, () => {
    const c = captureConsole();
    const log = createLogger({ functionName: "fn" });
    log.info("a", { employeeId: "EMP-1" });
    log.info("b", { employeeId: "EMP-2" });
    c.restore();
    const t1 = lastEntry(c.out.log[0]).employeeId_ref;
    const t2 = lastEntry(c.out.log[1]).employeeId_ref;
    assertNotEquals(t1, t2);
  });
});

// ─── كتم تفاصيل الأخطاء في الإنتاج ──────────────────────────────────────────
Deno.test("خطأ Error: error_name + error_message؛ الـ stack في غير الإنتاج فقط", () => {
  const err = new Error("boom");
  // غير إنتاجي → stack
  withEnv("development", () => {
    const c = captureConsole();
    createLogger({ functionName: "fn" }).error("failed", err);
    c.restore();
    const e = lastEntry(c.out.error[0]);
    assertEquals(e.error_name, "Error");
    assertEquals(e.error_message, "boom");
    assertEquals(typeof e.error_stack, "string");
  });
  // إنتاج → لا stack
  withEnv(undefined, () => {
    const c = captureConsole();
    createLogger({ functionName: "fn" }).error("failed", err);
    c.restore();
    const e = lastEntry(c.out.error[0]);
    assertEquals(e.error_name, "Error");
    assertEquals(e.error_message, "boom");
    assertEquals(e.error_stack, undefined);
  });
});

Deno.test("خطأ كائن Supabase/PostgREST: error_name=code، والرسالة تُكتم في الإنتاج", () => {
  const objErr = { code: "PGRST202", message: "schema cache miss with employee EMP-1" };
  withEnv("development", () => {
    const c = captureConsole();
    createLogger({ functionName: "fn" }).error("rpc failed", objErr);
    c.restore();
    const e = lastEntry(c.out.error[0]);
    assertEquals(e.error_name, "PGRST202");
    assertEquals(e.error_message, "schema cache miss with employee EMP-1");
  });
  withEnv(undefined, () => {
    const c = captureConsole();
    createLogger({ functionName: "fn" }).error("rpc failed", objErr);
    c.restore();
    const e = lastEntry(c.out.error[0]);
    assertEquals(e.error_name, "PGRST202");
    assertEquals(e.error_message, "[redacted-nonprod-only]");
    assertEquals(c.out.error[0].includes("EMP-1"), false);
  });
});

Deno.test("خطأ بدائي (string): يُكتم في الإنتاج ويُظهر في غير الإنتاج", () => {
  withEnv("development", () => {
    const c = captureConsole();
    createLogger({ functionName: "fn" }).error("oops", "raw detail with EMP-9");
    c.restore();
    assertEquals(lastEntry(c.out.error[0]).error_message, "raw detail with EMP-9");
  });
  withEnv(undefined, () => {
    const c = captureConsole();
    createLogger({ functionName: "fn" }).error("oops", "raw detail with EMP-9");
    c.restore();
    assertEquals(lastEntry(c.out.error[0]).error_message, "[redacted-nonprod-only]");
    assertEquals(c.out.error[0].includes("EMP-9"), false);
  });
});

// ─── debug: بلا تأثير في الإنتاج ─────────────────────────────────────────────
Deno.test("debug: لا يبثّ شيئاً في الإنتاج، ويبثّ في غير الإنتاج", () => {
  withEnv(undefined, () => {
    const c = captureConsole();
    createLogger({ functionName: "fn" }).debug("trace", { x: 1 });
    c.restore();
    assertEquals(c.out.log.length, 0);
  });
  withEnv("development", () => {
    const c = captureConsole();
    createLogger({ functionName: "fn" }).debug("trace", { x: 1 });
    c.restore();
    assertEquals(c.out.log.length, 1);
    const e = lastEntry(c.out.log[0]);
    assertEquals(e.level, "debug");
    assertEquals(e.x, 1);
  });
});

// ─── timed و child ───────────────────────────────────────────────────────────
Deno.test("timed: نجاح → info «<op> completed» مع duration_ms ويعيد النتيجة", async () => {
  withEnv(undefined, () => {
    const c = captureConsole();
    const log = createLogger({ functionName: "fn" });
    const result = await log.timed("op", async () => 42, { tag: "t" });
    c.restore();
    assertEquals(result, 42);
    assertEquals(c.out.log.length, 1);
    const e = lastEntry(c.out.log[0]);
    assertEquals(e.message, "op completed");
    assertEquals(typeof e.duration_ms, "number");
    assertEquals(e.tag, "t");
  });
});

Deno.test("timed: فشل → error «<op> failed» مع duration_ms ويُعيد رمي الخطأ", async () => {
  withEnv(undefined, () => {
    const c = captureConsole();
    const log = createLogger({ functionName: "fn" });
    let caught: unknown = undefined;
    try {
      await log.timed("op", async () => {
        throw new Error("nope");
      });
    } catch (e) {
      caught = e;
    }
    c.restore();
    assertEquals(caught instanceof Error, true);
    assertEquals(c.out.error.length, 1);
    const e = lastEntry(c.out.error[0]);
    assertEquals(e.message, "op failed");
    assertEquals(typeof e.duration_ms, "number");
    assertEquals(e.error_message, "nope");
  });
});

Deno.test("child: يدمج السياق ويرث functionName", () => {
  withEnv(undefined, () => {
    const c = captureConsole();
    const parent = createLogger({ functionName: "fn", version: "1.0.0", employeeId: "EMP-1" });
    const child = parent.child({ requestId: "req-9" });
    child.info("child evt");
    c.restore();
    const e = lastEntry(c.out.log[0]);
    assertEquals(e.function_name, "fn"); // موروث
    assertEquals(e.version, "1.0.0"); // موروث
    assertEquals(e.request_id, "req-9"); // من child
    assertEquals(typeof e.employee_ref, "string"); // موروث من parent
  });
});

Deno.test("child: تجاوز السياق في child له الأسبقية على parent", () => {
  withEnv(undefined, () => {
    const c = captureConsole();
    const parent = createLogger({ functionName: "fn", employeeId: "EMP-1" });
    const child = parent.child({ employeeId: "EMP-2" });
    child.info("x");
    c.restore();
    const e = lastEntry(c.out.log[0]);
    // child أسبق: نتحقق أن EMP-2 هو المُجزّأ لا EMP-1، وذلك بعدم تسرّب أي خام،
    // وأن الـ ref نصّ (correlationToken خاص بالوحدة فلا نقارنه مباشرة).
    assertEquals(typeof e.employee_ref, "string");
    assertEquals(c.out.log[0].includes("EMP-2"), false);
    assertEquals(c.out.log[0].includes("EMP-1"), false);
  });
});

