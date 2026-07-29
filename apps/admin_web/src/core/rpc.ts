import { getSupabase } from './supabase';

/**
 * Shared Supabase RPC helper (audit ARCH-01).
 *
 * Previously copy-pasted across six feature hooks with divergent signatures.
 * Centralizing it means error handling / telemetry / typing changes apply once.
 * Callers that validate the result with a zod schema can leave T as the default;
 * callers that want a typed passthrough can supply T.
 */
export async function rpc<T = unknown>(name: string, args?: Record<string, unknown>): Promise<T> {
  const supabase = await getSupabase();
  const { data, error } = await supabase.rpc(name, args);
  if (error) throw error;
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
  return data as T;
}
