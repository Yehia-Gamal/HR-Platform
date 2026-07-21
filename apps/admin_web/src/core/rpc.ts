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
