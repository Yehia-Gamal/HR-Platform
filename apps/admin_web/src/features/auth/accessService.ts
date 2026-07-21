import { accessContextSchema, type AccessContext } from '@ahla/shared-contracts';
import { getSupabase } from '../../core/supabase';

export async function loadAccessContext(): Promise<AccessContext> {
  const supabase = await getSupabase();
  const { data, error } = await supabase.rpc('get_my_access_context');
  if (error) throw error;
  return accessContextSchema.parse(data);
}
