import { employee360Schema, employeeSummarySchema, type Employee360, type EmployeeSummary } from '@ahla/shared-contracts';
import { useMutation, useQuery } from '@tanstack/react-query';
import { getSupabase } from '../../core/supabase';
import { useAuth } from '../auth/AuthProvider';

const developmentEmployees: EmployeeSummary[] = [
  {
    id: '30000000-0000-4000-8000-000000000001',
    employeeCode: 'EMP-001',
    fullNameAr: 'موظف تجريبي للتطوير',
    fullNameEn: null,
    phoneE164: '+201000000001',
    status: 'active',
    isActive: true,
    photoUrl: null,
    departmentId: null,
    teamId: null,
    branchId: null,
    createdAt: new Date().toISOString(),
  },
  {
    id: '30000000-0000-4000-8000-000000000002',
    employeeCode: 'EMP-002',
    fullNameAr: 'مدير مباشر تجريبي',
    fullNameEn: null,
    phoneE164: '+201000000002',
    status: 'onboarding',
    isActive: true,
    photoUrl: null,
    departmentId: null,
    teamId: null,
    branchId: null,
    createdAt: new Date().toISOString(),
  },
];

export function useEmployees() {
  const auth = useAuth();
  return useQuery({
    queryKey: ['employees', auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<EmployeeSummary[]> => {
      if (auth.isMock) return developmentEmployees;

      const supabase = await getSupabase();
      const { data, error } = await supabase
        .from('employees')
        .select('id,employee_code,full_name_ar,full_name_en,phone_e164,status,is_active,photo_url,department_id,team_id,branch_id,created_at')
        .eq('is_deleted', false)
        .order('created_at', { ascending: false })
        .limit(100);

      if (error) throw error;
      return (data ?? []).map((row) => employeeSummarySchema.parse({
        id: row.id,
        employeeCode: row.employee_code,
        fullNameAr: row.full_name_ar,
        fullNameEn: row.full_name_en,
        phoneE164: row.phone_e164,
        status: row.status,
        isActive: row.is_active,
        photoUrl: row.photo_url,
        departmentId: row.department_id,
        teamId: row.team_id,
        branchId: row.branch_id,
        createdAt: row.created_at,
      }));
    },
  });
}

export function useEmployee360(employeeId: string | undefined) {
  const auth = useAuth();
  return useQuery({
    queryKey: ['employee-360', employeeId, auth.isMock],
    enabled: auth.status === 'authenticated' && Boolean(employeeId),
    queryFn: async (): Promise<Employee360> => {
      if (!employeeId) throw new Error('معرف الموظف غير موجود.');
      if (auth.isMock) {
        const source = developmentEmployees.find((item) => item.id === employeeId) ?? developmentEmployees[0];
        return employee360Schema.parse({
          ...source,
          hireDate: null,
          contractEnd: null,
          probationEnd: null,
          jobTitle: 'موظف تجريبي',
          position: null,
          grade: null,
          department: 'الإدارة التجريبية',
          team: null,
          branch: 'المقر الرئيسي',
          workSite: null,
          managerName: 'مدير مباشر تجريبي',
          accountStatus: 'active',
          roles: [{ slug: 'employee', name: 'موظف' }],
          directReports: 0,
          attendance30: { present: 20, lateDays: 2, absent: 1, workMinutes: 9600 },
          requestCounts: { pending: 1, approved: 4, rejected: 0 },
          latestKpi: null,
          documents: [],
          assets: [],
          recentRequests: [],
          recentTasks: [],
          lastUpdatedAt: new Date().toISOString(),
        });
      }
      const supabase = await getSupabase();
      const { data, error } = await supabase.rpc('get_employee_360', { p_employee_id: employeeId });
      if (error) throw error;
      return employee360Schema.parse(data);
    },
  });
}

// Re-sends the account-activation / password-setup email for an employee whose
// account is not yet active. The edge function is permission-gated and uses the
// server-configured redirect (Vercel), so the link never points at localhost.
export function useResendInvite() {
  const auth = useAuth();
  return useMutation({
    mutationFn: async (employeeId: string): Promise<string> => {
      if (auth.isMock) return 'وضع التطوير: لم يُرسل بريد فعلي.';
      const supabase = await getSupabase();
      const { data, error } = await supabase.functions.invoke('admin-resend-invite', { body: { employeeId } });
      if (error) throw error;
      const email = (data as { email?: string } | null)?.email;
      return email ? `أُعيد إرسال رابط التفعيل إلى ${email}.` : 'أُعيد إرسال رابط التفعيل.';
    },
  });
}

export function useChangeManager() {
  const auth = useAuth();
  return useMutation({
    mutationFn: async ({ employeeId, managerId, reason }: { employeeId: string; managerId: string | null; reason: string }): Promise<void> => {
      if (auth.isMock) return;
      const supabase = await getSupabase();
      const { error } = await supabase.rpc('change_employee_manager_admin', {
        p_employee_id: employeeId,
        p_manager_id: managerId,
        p_reason: reason,
      });
      if (error) throw error;
    },
  });
}

export function useArchiveEmployee() {
  const auth = useAuth();
  return useMutation({
    mutationFn: async ({ employeeId, reason }: { employeeId: string; reason: string }): Promise<void> => {
      if (auth.isMock) return;
      const supabase = await getSupabase();
      const { error } = await supabase.rpc('archive_employee_secure', {
        p_employee_id: employeeId,
        p_reason: reason,
      });
      if (error) throw error;
    },
  });
}
