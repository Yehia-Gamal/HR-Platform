import { employee360Schema, employeeSummarySchema, type Employee360, type EmployeeSummary } from '@ahla/shared-contracts';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
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
    department: 'الإدارة التجريبية',
    team: null,
    branch: 'المقر الرئيسي',
    jobTitle: 'موظف تجريبي',
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
    department: 'الإدارة التجريبية',
    team: null,
    branch: 'المقر الرئيسي',
    jobTitle: 'مدير مباشر',
    createdAt: new Date().toISOString(),
  },
];

export function useEmployees(search?: string, status?: string) {
  const auth = useAuth();
  return useQuery({
    queryKey: ['employees', search, status, auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<EmployeeSummary[]> => {
      if (auth.isMock) return developmentEmployees;

      const supabase = await getSupabase();
      const { data, error } = await supabase.rpc('get_employees_enriched', {
        p_search: search?.trim() || null,
        p_status: status && status !== 'all' ? status : null,
        p_limit: 500,
      });

      if (error) throw error;
      const rows = Array.isArray(data) ? data : [];
      return rows.map((row: Record<string, unknown>) => employeeSummarySchema.parse(row));
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

// خريطة أخطاء Edge Function → رسائل عربية
const INVITE_ERROR_MESSAGES: Record<string, string> = {
  forbidden: 'ليس لديك صلاحية لإرسال الدعوات.',
  no_linked_account: 'الموظف ليس لديه حساب مربوط بعد.',
  account_email_missing: 'لا يوجد بريد إلكتروني مسجّل للموظف.',
  too_many_requests: 'أُرسلت دعوة مؤخرًا. انتظر دقيقة ثم أعد المحاولة.',
  invite_send_failed: 'تعذر إرسال البريد. أعد المحاولة لاحقًا.',
  permission_check_failed: 'تعذر التحقق من الصلاحية.',
  lookup_failed: 'تعذر البحث عن بيانات الموظف.',
  server_not_configured: 'الخدمة غير مهيأة. تواصل مع الدعم.',
  validation_failed: 'بيانات الطلب غير صالحة.',
  rate_limit_check_failed: 'تعذر التحقق من حد الإرسال. أعد المحاولة.',
  invalid_session: 'انتهت صلاحية الجلسة. سجّل الدخول مجددًا.',
};

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
      if (error) {
        // FunctionsHttpError: استخراج رسالة الخطأ الفعلية من جسم الاستجابة
        const resp = (error as Record<string, unknown>).context;
        if (resp instanceof Response) {
          const body = await resp.json().catch(() => null) as { error?: string } | null;
          const code = body?.error;
          if (code && INVITE_ERROR_MESSAGES[code]) throw new Error(INVITE_ERROR_MESSAGES[code]);
        }
        throw error;
      }
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

export function useUpdateEmployee() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async ({ employeeId, changes, reason }: { employeeId: string; changes: Record<string, unknown>; reason: string }): Promise<void> => {
      if (auth.isMock) return;
      const supabase = await getSupabase();
      const { error } = await supabase.rpc('update_employee_admin', {
        p_employee_id: employeeId,
        p_changes: changes,
        p_reason: reason,
      });
      if (error) throw error;
    },
    onSuccess: async () => {
      await Promise.all([
        client.invalidateQueries({ queryKey: ['employees'] }),
        client.invalidateQueries({ queryKey: ['employee-360'] }),
      ]);
    },
  });
}

export function useArchiveEmployee() {
  const auth = useAuth();
  const client = useQueryClient();
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
    onSuccess: async () => {
      await Promise.all([
        client.invalidateQueries({ queryKey: ['employees'] }),
        client.invalidateQueries({ queryKey: ['employee-360'] }),
      ]);
    },
  });
}

// ---------------------------------------------------------------------------
// V17: تعدد الإدارات — Multi-Department hooks
// ---------------------------------------------------------------------------

export interface EmployeeDepartment {
  id: string;
  departmentId: string;
  departmentName: string;
  jobTitle: string | null;
  isPrimary: boolean;
  assignedAt: string;
}

export function useEmployeeDepartments(employeeId: string | undefined) {
  const auth = useAuth();
  return useQuery({
    queryKey: ['employee-departments', employeeId, auth.isMock],
    enabled: auth.status === 'authenticated' && Boolean(employeeId),
    queryFn: async (): Promise<EmployeeDepartment[]> => {
      if (!employeeId) return [];
      if (auth.isMock) return [];
      const supabase = await getSupabase();
      const { data, error } = await supabase.rpc('get_employee_departments', { p_employee_id: employeeId });
      if (error) throw error;
      return (data as EmployeeDepartment[]) ?? [];
    },
  });
}

export function useAssignDepartment() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (params: { employeeId: string; departmentId: string; jobTitle?: string; isPrimary?: boolean; note?: string }): Promise<string> => {
      if (auth.isMock) return 'mock-id';
      const supabase = await getSupabase();
      const { data, error } = await supabase.rpc('assign_employee_department', {
        p_employee_id: params.employeeId,
        p_department_id: params.departmentId,
        p_job_title: params.jobTitle ?? null,
        p_is_primary: params.isPrimary ?? false,
        p_note: params.note ?? null,
      });
      if (error) throw error;
      return data as string;
    },
    onSuccess: async () => {
      await Promise.all([
        client.invalidateQueries({ queryKey: ['employee-departments'] }),
        client.invalidateQueries({ queryKey: ['employee-360'] }),
        client.invalidateQueries({ queryKey: ['employees'] }),
      ]);
    },
  });
}

export function useRemoveDepartment() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (params: { employeeId: string; departmentId: string }): Promise<void> => {
      if (auth.isMock) return;
      const supabase = await getSupabase();
      const { error } = await supabase.rpc('remove_employee_department', {
        p_employee_id: params.employeeId,
        p_department_id: params.departmentId,
      });
      if (error) throw error;
    },
    onSuccess: async () => {
      await Promise.all([
        client.invalidateQueries({ queryKey: ['employee-departments'] }),
        client.invalidateQueries({ queryKey: ['employee-360'] }),
        client.invalidateQueries({ queryKey: ['employees'] }),
      ]);
    },
  });
}

// ---------------------------------------------------------------------------
// V17: حذف الموظف نهائياً
// ---------------------------------------------------------------------------

export function useDeleteEmployee() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async ({ employeeId, confirmationCode, reason }: { employeeId: string; confirmationCode: string; reason: string }): Promise<void> => {
      if (auth.isMock) return;
      const supabase = await getSupabase();
      const { error } = await supabase.rpc('hard_delete_employee_guarded', {
        p_employee_id: employeeId,
        p_confirmation_code: confirmationCode,
        p_reason: reason,
      });
      if (error) throw error;
    },
    onSuccess: async () => {
      await client.invalidateQueries({ queryKey: ['employees'] });
    },
  });
}
