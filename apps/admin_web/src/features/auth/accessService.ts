import { accessContextSchema, type AccessContext } from '@ahla/shared-contracts';
import { rpc } from '../../core/rpc';
import { getSupabase } from '../../core/supabase';

export async function loadAccessContext(): Promise<AccessContext> {
  const data = await rpc('get_my_access_context');
  const context = accessContextSchema.parse(data);
  if (!context.employeeId) return context;

  const supabase = await getSupabase();
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
