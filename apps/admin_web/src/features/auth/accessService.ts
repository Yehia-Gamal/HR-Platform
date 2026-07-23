import { accessContextSchema, type AccessContext } from '@ahla/shared-contracts';
import { getSupabase } from '../../core/supabase';

export async function loadAccessContext(): Promise<AccessContext> {
  const supabase = await getSupabase();
  const { data, error } = await supabase.rpc('get_my_access_context');
  if (error) throw error;
  const context = accessContextSchema.parse(data);
  if (!context.employeeId) return context;

  const { data: profile } = await supabase
    .from('employees')
    .select('photo_url')
    .eq('id', context.employeeId)
    .maybeSingle();
  return {
    ...context,
    photoUrl: typeof profile?.photo_url === 'string' ? profile.photo_url : null,
  };
}
