import { attendanceStatementSchema, type AttendanceStatement } from '@ahla/shared-contracts';
import { useQuery } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';
import { loadDomainMocks } from '../mock/loadDomainMocks';

// كشف الحضور والانصراف الشهري لموظف محدد (V12 §18 — HR/Main Admin/المدير).
export function useEmployeeMonthlyStatement(employeeId: string | null, year: number, month: number) {
  const auth = useAuth();
  return useQuery({
    queryKey: ['attendance-statement', employeeId, year, month, auth.isMock],
    enabled: auth.status === 'authenticated' && Boolean(employeeId),
    queryFn: async (): Promise<AttendanceStatement> => {
      if (auth.isMock) return (await loadDomainMocks()).mockAttendanceStatement;
      const data = await rpc('get_employee_monthly_attendance_statement', {
        p_employee_id: employeeId,
        p_year: year,
        p_month: month,
      });

      // Defensive filtering for any null/falsy days from database edge cases
      if (data && typeof data === 'object' && Array.isArray((data as Record<string, unknown>).days)) {
        (data as { days: unknown[] }).days = (data as { days: unknown[] }).days.filter(Boolean);
      }

      const parsed = attendanceStatementSchema.safeParse(data);
      if (!parsed.success) {
        console.error('[useMonthlyStatement] schema parse error:', parsed.error, data);
        if (data && typeof data === 'object' && 'employee' in data && 'days' in data) {
          return data as AttendanceStatement;
        }
        throw parsed.error;
      }
      return parsed.data;
    },
  });
}
