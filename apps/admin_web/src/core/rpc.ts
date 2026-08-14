import type { ZodType } from 'zod';
import { addBreadcrumb } from './sentry';
import { getSupabase } from './supabase';

/**
 * حقول PII/الأسرار التي تُنقّح من وسائط RPC قبل تسجيلها في breadcrumbs.
 *
 * تطابق المفتاح كـ substring (case-insensitive) على كل مستويات التداخل،
 * لأن بيانات الموظفين قد تمر داخل كائنات متداخلة (مثل { employee: { national_id, salary } }).
 * القائمة موحّدة مع sentry.ts/redactKeys لضمان تغطية متّسقة.
 */
const PII_KEYS =
  /password|passwd|token|secret|api[_-]?key|private[_-]?key|authorization|credential|name|email|phone|national|iban|bic|swift|bank[_-]?account|account[_-]?number|salary|wage|compensation|address|birth|dob|nationality|note|comment|reason/i;

function sanitizeArgs(args: Record<string, unknown> | undefined): Record<string, unknown> | undefined {
  if (!args) return undefined;
  return scrubValue(args) as Record<string, unknown>;
}

/** تنظيف متكرر للكائنات/المصفوفات المتداخلة — يُنقّح أي مفتاح يطابق PII_KEYS. */
function scrubValue(value: unknown): unknown {
  if (value === null || value === undefined) return value;
  if (Array.isArray(value)) return value.map(scrubValue);
  if (typeof value === 'object') {
    const clean: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value)) {
      clean[k] = PII_KEYS.test(k) ? '[REDACTED]' : scrubValue(v);
    }
    return clean;
  }
  return value;
}

/**
 * Shared Supabase RPC helper (audit ARCH-01).
 *
 * Previously copy-pasted across six feature hooks with divergent signatures.
 * Centralizing it means error handling / telemetry / typing changes apply once.
 *
 * When `schema` is provided the raw response is validated at runtime through Zod
 * before being returned — this catches shape mismatches between the DB function
 * and the TypeScript type early instead of surfacing them as silent `undefined`
 * accesses deep in the rendering tree.  Callers that omit it get the old cast
 * behaviour so adoption can be incremental.
 */
export async function rpc<T = unknown>(name: string, args?: Record<string, unknown>, schema?: ZodType<T>): Promise<T> {
  const supabase = await getSupabase();
  const sanitized = sanitizeArgs(args);
  const { data, error } = await supabase.rpc(name, args);
  if (error) {
    addBreadcrumb('rpc', name, { args: sanitized, error: error.message });
    throw error;
  }
  addBreadcrumb('rpc', name, { args: sanitized });
  if (schema) return schema.parse(data);
  // تحذير تطويري: استدعاء RPC بلا Zod schema يثق بشكل أعمى ببنية البيانات من الخادم.
  // يساعد على تحديد الـ call sites التي تحتاج migration إلى schema تدريجياً.
  if (import.meta.env.DEV && data != null) {
    console.warn(`[rpc] استدعاء "${name}" بلا Zod schema — البيانات غير مُتحقَّق منها وقت التشغيل.`);
  }
  return data as T;
}

/**
 * Shared Edge Function invocation helper (audit ARCH-02).
 *
 * Extracts error codes from FunctionsHttpError response bodies and maps them
 * to localized (Arabic) messages via the provided errorMap.
 * Eliminates duplicated error-extraction logic across useEmployees / useControlCenters.
 */
export async function invokeEdgeFunction<T = unknown>(
  name: string,
  body: Record<string, unknown>,
  errorMap: Record<string, string>,
  fallbackMessage: string,
  schema?: ZodType<T>,
): Promise<T> {
  const supabase = await getSupabase();
  const { data, error } = await supabase.functions.invoke(name, { body });
  if (error) {
    let message = fallbackMessage;
    const resp = (error as Record<string, unknown>).context;
    if (resp instanceof Response) {
      const parsed = (await resp.json().catch(() => null)) as { error?: string } | null;
      if (parsed?.error && errorMap[parsed.error]) message = errorMap[parsed.error];
    }
    throw new Error(message);
  }
  if (schema) return schema.parse(data);
  return data as T;
}
