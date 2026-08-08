import { peopleFinanceCatalogSchema, type PeopleFinanceCatalog } from '@ahla/shared-contracts';
import { useQuery } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';

const QUERY_KEY = 'people-finance-catalog';

export function usePeopleFinanceCatalog() {
  const auth = useAuth();
  return useQuery({
    queryKey: [QUERY_KEY, auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<PeopleFinanceCatalog> => {
      if (auth.isMock) {
        return {
          workforcePlans: [],
          capacity: [],
          salaryStructures: [],
          payrollRuns: [],
          loans: [],
          campaigns: [],
          lastUpdatedAt: new Date().toISOString(),
        };
      }
      return peopleFinanceCatalogSchema.parse(await rpc('get_people_finance_catalog'));
    },
  });
}

export const PAYROLL_RUN_STATUS_LABELS: Record<string, string> = {
  draft: 'مسودة',
  calculated: 'محسوبة',
  validation_failed: 'فشل التحقق',
  ready_for_review: 'جاهزة للمراجعة',
  approved: 'معتمدة',
  posted: 'مرحّلة',
  paid: 'مدفوعة',
  closed: 'مغلقة',
  cancelled: 'ملغية',
};

export const SALARY_STRUCTURE_STATUS_LABELS: Record<string, string> = {
  active: 'نشط',
  inactive: 'غير نشط',
};

export const LOAN_STATUS_LABELS: Record<string, string> = {
  pending: 'قيد الانتظار',
  approved: 'معتمد',
  active: 'نشط',
  settled: 'مسوّى',
  cancelled: 'ملغي',
};

export const CAMPAIGN_STATUS_LABELS: Record<string, string> = {
  draft: 'مسودة',
  active: 'نشطة',
  completed: 'مكتملة',
  cancelled: 'ملغاة',
};

export const WORKFORCE_PLAN_STATUS_LABELS: Record<string, string> = {
  draft: 'مسودة',
  review: 'قيد المراجعة',
  approved: 'معتمدة',
  locked: 'مقفلة',
};
