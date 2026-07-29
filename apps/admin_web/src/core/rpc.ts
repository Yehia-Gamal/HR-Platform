import type { ZodType } from 'zod';
import { getSupabase } from './supabase';

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
export async function rpc<T = unknown>(
  name: string,
  args?: Record<string, unknown>,
  schema?: ZodType<T>,
): Promise<T> {
  const supabase = await getSupabase();
  const { data, error } = await supabase.rpc(name, args);
  if (error) throw error;
  if (schema) return schema.parse(data);
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
      const parsed = await resp.json().catch(() => null) as { error?: string } | null;
      if (parsed?.error && errorMap[parsed.error]) message = errorMap[parsed.error];
    }
    throw new Error(message);
  }
  if (schema) return schema.parse(data);
  return data as T;
}
