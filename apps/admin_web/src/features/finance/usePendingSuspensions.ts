import {
  pendingSuspensionSchema,
  suspendEmployeeForPenaltyResultSchema,
  type PendingSuspension,
  type SuspendEmployeeForPenaltyResult,
} from '@ahla/shared-contracts';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';
import { hasPermission } from '../workspaces/access';

export type { PendingSuspension };

const PENDING_SUSPENSIONS_KEY = 'instant-penalties-pending-suspensions';

/**
 * من يملك قرار التعليق — نفس شرط الخادم (0554) وحارسَي employees (0004)
 * و profiles (0289): full-access ('*') أو الصلاحيتان معاً.
 */
export function useCanSuspendEmployees(): boolean {
  const auth = useAuth();
  return hasPermission(auth.access, 'people.employee.update_sensitive') && hasPermission(auth.access, 'profiles.manage');
}

/** المستحقون للتعليق — بانتظار قرار بشري (منذ 0550 لا يعلّق الكرون أحداً). */
export function usePendingSuspensions(enabled: boolean) {
  const auth = useAuth();
  return useQuery({
    queryKey: [PENDING_SUSPENSIONS_KEY, auth.isMock],
    enabled: enabled && auth.status === 'authenticated',
    refetchInterval: 60_000,
    queryFn: async (): Promise<PendingSuspension[]> => {
      if (auth.isMock) return [];
      return pendingSuspensionSchema.array().parse(await rpc('get_pending_suspensions'));
    },
  });
}

/** تنفيذ قرار التعليق لغرامة واحدة، بسبب إلزامي يُحفظ في التدقيق. */
export function useSuspendEmployeeForPenalty() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (args: { penaltyId: string; reason: string }): Promise<SuspendEmployeeForPenaltyResult> =>
      suspendEmployeeForPenaltyResultSchema.parse(
        await rpc('suspend_employee_for_penalty', {
          p_penalty_id: args.penaltyId,
          p_reason: args.reason,
        }),
      ),
    // الخطأ يُعرض داخل نافذة التأكيد نفسها — لا نكرره بتنبيه عام.
    meta: { successMessage: 'تم تعليق الموظف وإشعار الفريق', silentError: true },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: [PENDING_SUSPENSIONS_KEY] });
      // مفاتيح useInstantPenalties.ts — تُكتب حرفياً لتجنّب تعديل ذلك الملف
      void queryClient.invalidateQueries({ queryKey: ['instant-penalties'] });
      void queryClient.invalidateQueries({ queryKey: ['instant-penalties-pending-employees'] });
      void queryClient.invalidateQueries({ queryKey: ['employees'] });
    },
  });
}
