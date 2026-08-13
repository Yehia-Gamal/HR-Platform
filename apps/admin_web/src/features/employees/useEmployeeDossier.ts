import {
  employeeDailyReportsSchema,
  employeeKpiEvaluationsSchema,
  employeeLocationRequestsSchema,
  employeePublishedDecisionsSchema,
  employeeTaskItemsSchema,
  type EmployeeDailyReports,
  type EmployeeKpiEvaluations,
  type EmployeeLocationRequests,
  type EmployeePublishedDecisions,
  type EmployeeTaskItems,
} from '@ahla/shared-contracts';
import { useQuery } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';

const EMPTY_ARRAY = [] as never[];

// طلبات المواقع الخاصة بالموظف — تبويب «طلبات المواقع» في ملف الموظف.
export function useEmployeeLocationRequests(employeeId: string | undefined) {
  const auth = useAuth();
  return useQuery({
    queryKey: ['employee-location-requests', employeeId, auth.isMock],
    enabled: auth.status === 'authenticated' && Boolean(employeeId),
    queryFn: async (): Promise<EmployeeLocationRequests> => {
      if (!employeeId) return [];
      if (auth.isMock) return EMPTY_ARRAY as unknown as EmployeeLocationRequests;
      const data = await rpc('get_employee_location_requests', { p_employee_id: employeeId });
      return employeeLocationRequestsSchema.parse(data ?? []);
    },
  });
}

// كل مهام الموظف المسندة إليه — تبويب «المهام».
export function useEmployeeTasks(employeeId: string | undefined) {
  const auth = useAuth();
  return useQuery({
    queryKey: ['employee-tasks', employeeId, auth.isMock],
    enabled: auth.status === 'authenticated' && Boolean(employeeId),
    queryFn: async (): Promise<EmployeeTaskItems> => {
      if (!employeeId) return [];
      if (auth.isMock) return EMPTY_ARRAY as unknown as EmployeeTaskItems;
      const data = await rpc('get_employee_tasks_admin', { p_employee_id: employeeId });
      return employeeTaskItemsSchema.parse(data ?? []);
    },
  });
}

// تقييمات KPI الخاصة بالموظف عبر كل الدورات — تبويب «الأداء».
export function useEmployeeKpiEvaluations(employeeId: string | undefined) {
  const auth = useAuth();
  return useQuery({
    queryKey: ['employee-kpi-evaluations', employeeId, auth.isMock],
    enabled: auth.status === 'authenticated' && Boolean(employeeId),
    queryFn: async (): Promise<EmployeeKpiEvaluations> => {
      if (!employeeId) return [];
      if (auth.isMock) return EMPTY_ARRAY as unknown as EmployeeKpiEvaluations;
      const data = await rpc('get_employee_kpi_evaluations_admin', { p_employee_id: employeeId });
      return employeeKpiEvaluationsSchema.parse(data ?? []);
    },
  });
}

// القرارات المنشورة الموجهة للموظف — تبويب «التقارير».
export function useEmployeePublishedDecisions(employeeId: string | undefined) {
  const auth = useAuth();
  return useQuery({
    queryKey: ['employee-published-decisions', employeeId, auth.isMock],
    enabled: auth.status === 'authenticated' && Boolean(employeeId),
    queryFn: async (): Promise<EmployeePublishedDecisions> => {
      if (!employeeId) return [];
      if (auth.isMock) return EMPTY_ARRAY as unknown as EmployeePublishedDecisions;
      const data = await rpc('get_employee_published_decisions_admin', { p_employee_id: employeeId });
      return employeePublishedDecisionsSchema.parse(data ?? []);
    },
  });
}

// التقارير اليومية التي كتبها الموظف — تبويب «التقارير».
export function useEmployeeDailyReports(employeeId: string | undefined) {
  const auth = useAuth();
  return useQuery({
    queryKey: ['employee-daily-reports', employeeId, auth.isMock],
    enabled: auth.status === 'authenticated' && Boolean(employeeId),
    queryFn: async (): Promise<EmployeeDailyReports> => {
      if (!employeeId) return [];
      if (auth.isMock) return EMPTY_ARRAY as unknown as EmployeeDailyReports;
      const data = await rpc('get_mobile_daily_reports', { p_employee_id: employeeId, p_limit: 50 });
      return employeeDailyReportsSchema.parse(data ?? []);
    },
  });
}
