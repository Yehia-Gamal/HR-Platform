import { attendanceStatementSchema, type AttendanceStatement } from '@ahla/shared-contracts';
import { useQuery } from '@tanstack/react-query';
import { getSupabase } from '../../core/supabase';
import { useAuth } from '../auth/AuthProvider';

// كشف الحضور والانصراف الشهري لموظف محدد (V12 §18 — HR/Main Admin/المدير).
export function useEmployeeMonthlyStatement(
  employeeId: string | null,
  year: number,
  month: number,
) {
  const auth = useAuth();
  return useQuery({
    queryKey: ['attendance-statement', employeeId, year, month, auth.isMock],
    enabled: auth.status === 'authenticated' && Boolean(employeeId),
    queryFn: async (): Promise<AttendanceStatement> => {
      const supabase = await getSupabase();
      const { data, error } = await supabase.rpc('get_employee_monthly_attendance_statement', {
        p_employee_id: employeeId,
        p_year: year,
        p_month: month,
      });
      if (error) throw error;
      return attendanceStatementSchema.parse(data);
    },
  });
}
