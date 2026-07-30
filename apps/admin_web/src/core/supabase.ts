import type { SupabaseClient } from '@supabase/supabase-js';
import { env, hasSupabaseConfig } from './env';

let clientPromise: Promise<SupabaseClient> | null = null;

export async function getSupabase(): Promise<SupabaseClient> {
  if (!hasSupabaseConfig) {
    throw new Error('Supabase configuration is missing.');
  }

  clientPromise ??= import('@supabase/supabase-js').then(({ createClient }) =>
    createClient(env.supabaseUrl, env.supabasePublishableKey, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true,
      },
    }),
  ).catch((err) => {
    clientPromise = null;
    throw err;
  });

  return clientPromise;
}
