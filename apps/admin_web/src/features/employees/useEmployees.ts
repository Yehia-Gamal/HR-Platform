import { z } from 'zod';
import { employee360Schema, employeeSummarySchema, type Employee360, type EmployeeSummary } from '@ahla/shared-contracts';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { invokeEdgeFunction } from '../../core/rpc';
import { getSupabase } from '../../core/supabase';
import { useAuth } from '../auth/AuthProvider';
import { loadDomainMocks } from '../mock/loadDomainMocks';

export function useEmployees(search?: string, status?: string) {
  const auth = useAuth();
  return useQuery({
    queryKey: ['employees', search, status, auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<EmployeeSummary[]> => {
      if (auth.isMock) return (await loadDomainMocks()).mockDevelopmentEmployees;

      const data = await rpc('get_employees_enriched', {
        p_search: search?.trim() || null,
        p_status: status && status !== 'all' ? status : null,
        p_limit: 500,
      });

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
        const devEmployees = (await loadDomainMocks()).mockDevelopmentEmployees;
        const source = devEmployees.find((item) => item.id === employeeId) ?? devEmployees[0];
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
      const data = await rpc('get_employee_360', { p_employee_id: employeeId });
      // معالجة الحالة التي ترجع فيها الـ RPC null (موظف محذوف أو خارج نطاق RLS)
      if (data === null || data === undefined) {
        throw new Error('employee_not_found');
      }
      try {
        return employee360Schema.parse(data);
      } catch {
        // إذا فشل Zod parse، نرمي رسالة واضحة بدل خطأ تقني غامض
        throw new Error('employee_data_incomplete');
      }
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
      const result = await invokeEdgeFunction<{ email?: string }>(
        'admin-resend-invite',
        { employeeId },
        INVITE_ERROR_MESSAGES,
        'تعذر إرسال البريد. أعد المحاولة لاحقًا.',
      );
      const email = result?.email;
      return email
        ? `أُعيد إرسال رابط التفعيل إلى ${email} — الموظف يضبط كلمة مروره من الرابط.`
        : 'أُعيد إرسال رابط التفعيل — الموظف يضبط كلمة مروره من الرابط.';
    },
    meta: { successMessage: 'تم إرسال رابط التفعيل بنجاح' },
  });
}

// خريطة أخطاء تعيين كلمة المرور → رسائل عربية. تطابق أكواد validateHrIssuedPassword
// في admin-set-password Edge Function + errors العامة.
const SET_PASSWORD_ERROR_MESSAGES: Record<string, string> = {
  forbidden: 'ليس لديك صلاحية تعيين كلمة مرور هذا الموظف.',
  no_linked_account: 'الموظف ليس لديه حساب مربوط بعد.',
  account_lookup_failed: 'تعذر العثور على حساب الموظف.',
  password_update_failed: 'تعذر تحديث كلمة المرور. أعد المحاولة لاحقًا.',
  permission_check_failed: 'تعذر التحقق من الصلاحية.',
  validation_failed: 'كلمة المرور غير صالحة. راجع الشروط بالأسفل.',
  password_too_short_min_12: 'كلمة المرور يجب ألا تقل عن 12 حرفًا.',
  password_too_long_max_72: 'كلمة المرور يجب ألا تزيد عن 72 حرفًا.',
  password_needs_uppercase: 'كلمة المرور يجب أن تحتوي حرفًا كبيرًا واحدًا على الأقل (A-Z).',
  password_needs_lowercase: 'كلمة المرور يجب أن تحتوي حرفًا صغيرًا واحدًا على الأقل (a-z).',
  password_needs_digit: 'كلمة المرور يجب أن تحتوي رقمًا واحدًا على الأقل (0-9).',
  password_needs_symbol: 'كلمة المرور يجب أن تحتوي رمزًا خاصًا واحدًا على الأقل (!@#$%^&*...).',
  password_too_repetitive: 'كلمة المرور تحتوي تكرارًا مفرطًا لنفس الحرف (5+ على التوالي).',
  password_keyboard_sequence: 'كلمة المرور تحتوي تسلسلًا مألوفًا من لوحة المفاتيح أو أرقام.',
  password_contains_common_word: 'كلمة المرور تحتوي كلمة شائعة يسهل تخمينها.',
  password_contains_identifier: 'كلمة المرور تشبه بيانات الموظف (الاسم/الهاتف/البريد/الكود). اختر كلمة مختلفة.',
  weak_password: 'كلمة المرور ضعيفة. استخدم 12+ حرفًا بأحرف كبيرة وصغيرة وأرقام ورموز.',
  lookup_failed: 'تعذر البحث عن بيانات الموظف.',
  server_not_configured: 'الخدمة غير مهيأة. تواصل مع الدعم.',
  invalid_session: 'انتهت صلاحية الجلسة. سجّل الدخول مجددًا.',
  INTERNAL_ERROR: 'حدث خطأ غير متوقع في الخادم. أعد المحاولة أو تواصل مع الدعم.',
};

// Sets an employee's password from the admin panel. The edge function is
// permission-gated (update_sensitive) and forces the employee to change the
// password on first sign-in so the admin-chosen value does not stay in use.
export function useSetEmployeePassword() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async ({ employeeId, password }: { employeeId: string; password: string }): Promise<void> => {
      if (auth.isMock) return;
      await invokeEdgeFunction('admin-set-password', { employeeId, password }, SET_PASSWORD_ERROR_MESSAGES, 'تعذر تعيين كلمة المرور. أعد المحاولة لاحقًا.');
    },
    meta: { successMessage: 'تم تعيين كلمة المرور بنجاح' },
    onSuccess: async (_, { employeeId }) => {
      await Promise.all([
        client.invalidateQueries({ queryKey: ['employee-360'] }),
        client.invalidateQueries({ queryKey: ['employees'] }),
        client.invalidateQueries({ queryKey: ['employee-audit', employeeId] }),
      ]);
    },
  });
}

// خريطة أخطاء تعديل البريد الإلكتروني → رسائل عربية
const UPDATE_EMAIL_ERROR_MESSAGES: Record<string, string> = {
  forbidden: 'ليس لديك صلاحية تعديل بريد الموظف.',
  no_linked_account: 'الموظف ليس لديه حساب مربوط بعد.',
  account_lookup_failed: 'تعذر العثور على حساب الموظف.',
  email_already_exists: 'هذا البريد الإلكتروني مستخدم لحساب آخر.',
  email_update_failed: 'تعذر تحديث البريد الإلكتروني. أعد المحاولة لاحقًا.',
  permission_check_failed: 'تعذر التحقق من الصلاحية.',
  validation_failed: 'البريد الإلكتروني غير صالح.',
  lookup_failed: 'تعذر البحث عن بيانات الموظف.',
  server_not_configured: 'الخدمة غير مهيأة. تواصل مع الدعم.',
  invalid_session: 'انتهت صلاحية الجلسة. سجّل الدخول مجددًا.',
};

// Updates an employee's sign-in email. The edge function is permission-gated
// (update_sensitive) and updates auth.users via the GoTrue admin REST API.
export function useUpdateEmployeeEmail() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async ({ employeeId, email }: { employeeId: string; email: string }): Promise<void> => {
      if (auth.isMock) return;
      await invokeEdgeFunction('admin-update-email', { employeeId, email }, UPDATE_EMAIL_ERROR_MESSAGES, 'تعذر تحديث البريد الإلكتروني. أعد المحاولة لاحقًا.');
    },
    meta: { successMessage: 'تم تحديث البريد الإلكتروني بنجاح' },
    onSuccess: async () => {
      await Promise.all([client.invalidateQueries({ queryKey: ['employees'] }), client.invalidateQueries({ queryKey: ['employee-360'] })]);
    },
  });
}

export function useChangeManager() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async ({ employeeId, managerId, reason }: { employeeId: string; managerId: string | null; reason: string }): Promise<void> => {
      if (auth.isMock) return;
      await rpc('change_employee_manager_admin', {
        p_employee_id: employeeId,
        p_manager_id: managerId,
        p_reason: reason,
      });
    },
    meta: { successMessage: 'تم تغيير المدير المباشر بنجاح' },
    onSuccess: () => client.invalidateQueries({ queryKey: ['employees'] }),
  });
}

export function useGrantWeeklyRestCredit() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async ({ employeeId, workDate, days }: { employeeId: string; workDate: string; days: number }): Promise<number> => {
      if (auth.isMock) return days;
      const data = await rpc<number>('grant_weekly_rest_credit', {
        p_employee_id: employeeId,
        p_work_date: workDate,
        p_days: days,
      });
      return Number(data) || days;
    },
    meta: { successMessage: 'تم منح رصيد بدل الراحة بنجاح' },
    onSuccess: async () => {
      await Promise.all([client.invalidateQueries({ queryKey: ['employees'] }), client.invalidateQueries({ queryKey: ['employee-360'] })]);
    },
  });
}

export function useUpdateEmployee() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async ({ employeeId, changes, reason }: { employeeId: string; changes: Record<string, unknown>; reason?: string }): Promise<void> => {
      if (auth.isMock) return;
      await rpc('update_employee_admin', {
        p_employee_id: employeeId,
        p_changes: changes,
        p_reason: reason ?? '',
      });
    },
    meta: { successMessage: 'تم تحديث بيانات الموظف بنجاح' },
    onSuccess: async () => {
      await Promise.all([client.invalidateQueries({ queryKey: ['employees'] }), client.invalidateQueries({ queryKey: ['employee-360'] })]);
    },
  });
}

export function useArchiveEmployee() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async ({ employeeId, reason }: { employeeId: string; reason: string }): Promise<void> => {
      if (auth.isMock) return;
      await rpc('archive_employee_secure', {
        p_employee_id: employeeId,
        p_reason: reason,
      });
    },
    meta: { successMessage: 'تم أرشفة الموظف بنجاح', silentError: true },
    onSuccess: async () => {
      await Promise.all([client.invalidateQueries({ queryKey: ['employees'] }), client.invalidateQueries({ queryKey: ['employee-360'] })]);
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
      return (await rpc<EmployeeDepartment[]>('get_employee_departments', { p_employee_id: employeeId })) ?? [];
    },
  });
}

export function useAssignDepartment() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (params: { employeeId: string; departmentId: string; jobTitle?: string; isPrimary?: boolean; note?: string }): Promise<string> => {
      if (auth.isMock) return 'mock-id';
      return await rpc<string>('assign_employee_department', {
        p_employee_id: params.employeeId,
        p_department_id: params.departmentId,
        p_job_title: params.jobTitle ?? null,
        p_is_primary: params.isPrimary ?? false,
        p_note: params.note ?? null,
      });
    },
    meta: { successMessage: 'تم إسناد الإدارة بنجاح' },
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
      await rpc('remove_employee_department', {
        p_employee_id: params.employeeId,
        p_department_id: params.departmentId,
      });
    },
    meta: { successMessage: 'تم إزالة الإدارة بنجاح' },
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
      await rpc('hard_delete_employee_guarded', {
        p_employee_id: employeeId,
        p_confirmation_code: confirmationCode,
        p_reason: reason,
      });
    },
    meta: { successMessage: 'تم حذف الموظف نهائيًا بنجاح', silentError: true },
    onSuccess: async () => {
      await Promise.all([client.invalidateQueries({ queryKey: ['employees'] }), client.invalidateQueries({ queryKey: ['employee-360'] })]);
    },
  });
}

// ---------------------------------------------------------------------------
// سجل التدقيق الخاص بملف موظف — قراءة من audit_events (RLS: audit.view).
// ---------------------------------------------------------------------------
export interface EmployeeAuditEvent {
  id: string;
  summary: string | null;
  occurredAt: string;
  description: string | null;
  metadata: Record<string, unknown> | null;
}

const auditEventRowSchema = z.object({
  id: z.string(),
  summary_ar: z.string().nullable(),
  occurred_at: z.string(),
  description: z.string().nullable(),
  metadata: z.unknown().nullable(),
});

export function useEmployeeAuditTrail(employeeId: string | undefined) {
  const auth = useAuth();
  return useQuery({
    queryKey: ['employee-audit', employeeId, auth.isMock],
    enabled: auth.status === 'authenticated' && Boolean(employeeId),
    queryFn: async (): Promise<EmployeeAuditEvent[]> => {
      if (!employeeId) return [];
      if (auth.isMock) return [];
      const supabase = await getSupabase();
      const { data, error } = await supabase
        .from('audit_events')
        .select('id, summary_ar, occurred_at, description, metadata')
        .eq('target_table', 'employees')
        .eq('target_id', employeeId)
        .order('occurred_at', { ascending: false })
        .limit(50);
      if (error) throw new Error(error.message);
      return (data ?? []).map((row) => {
        const parsed = auditEventRowSchema.parse(row);
        return {
          id: parsed.id,
          summary: parsed.summary_ar,
          occurredAt: parsed.occurred_at,
          description: parsed.description,
          metadata: (parsed.metadata ?? null) as Record<string, unknown> | null,
        };
      });
    },
  });
}
