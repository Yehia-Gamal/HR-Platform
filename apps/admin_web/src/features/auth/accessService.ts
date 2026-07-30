import { accessContextSchema, type AccessContext } from '@ahla/shared-contracts';
import { rpc } from '../../core/rpc';

export async function loadAccessContext(): Promise<AccessContext> {
  const data = await rpc('get_my_access_context');
  const context = accessContextSchema.parse(data);
  if (!context.employeeId) return context;

  try {
    const photoUrl = await rpc<string | null>('get_employee_photo_url', {
      p_employee_id: context.employeeId,
    });
    return { ...context, photoUrl: typeof photoUrl === 'string' ? photoUrl : null };
  } catch {
    // photo_url is cosmetic — don't block access context load
    return context;
  }
}
