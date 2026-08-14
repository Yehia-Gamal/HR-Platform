import { z } from 'zod';
import { useQuery } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';

const monthlyRequestSchema = z.object({
  month: z.string(),
  monthKey: z.string(),
  approved: z.number(),
  rejected: z.number(),
  pending: z.number(),
  cancelled: z.number(),
});

const deptDistSchema = z.object({
  name: z.string(),
  value: z.number(),
});

const attendanceDaySchema = z.object({
  name: z.string(),
  date: z.string().optional(),
  present: z.number(),
  late: z.number(),
  absent: z.number(),
});

const kpiScoreSchema = z.object({
  subject: z.string(),
  actual: z.number(),
  target: z.number(),
});

const analyticsDashboardSchema = z.object({
  monthlyRequests: z.array(monthlyRequestSchema),
  departmentDistribution: z.array(deptDistSchema),
  attendanceTrend: z.array(attendanceDaySchema),
  kpiScores: z.array(kpiScoreSchema),
  generatedAt: z.string().optional(),
});

export type AnalyticsDashboard = z.infer<typeof analyticsDashboardSchema>;

export function useAnalyticsDashboard(monthsBack = 6) {
  const auth = useAuth();
  return useQuery({
    queryKey: ['analytics', 'dashboard', monthsBack],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<AnalyticsDashboard> => {
      if (auth.isMock) {
        return {
          monthlyRequests: [
            { month: 'مارس 2026', monthKey: '2026-03', approved: 18, rejected: 4, pending: 7, cancelled: 1 },
            { month: 'أبريل 2026', monthKey: '2026-04', approved: 14, rejected: 1, pending: 4, cancelled: 0 },
            { month: 'مايو 2026', monthKey: '2026-05', approved: 20, rejected: 3, pending: 6, cancelled: 2 },
            { month: 'يونيو 2026', monthKey: '2026-06', approved: 16, rejected: 2, pending: 3, cancelled: 1 },
          ],
          attendanceTrend: [
            { name: 'الأحد', present: 45, late: 5, absent: 3 },
            { name: 'الإثنين', present: 48, late: 3, absent: 2 },
            { name: 'الثلاثاء', present: 44, late: 6, absent: 3 },
            { name: 'الأربعاء', present: 47, late: 4, absent: 2 },
            { name: 'الخميس', present: 42, late: 5, absent: 6 },
          ],
          departmentDistribution: [
            { name: 'الإدارة', value: 8 },
            { name: 'التشغيل', value: 15 },
            { name: 'المالية', value: 6 },
          ],
          kpiScores: [
            { subject: 'الحضور', actual: 85, target: 100 },
            { subject: 'الإنتاجية', actual: 78, target: 100 },
          ],
        };
      }
      const raw = await rpc('get_analytics_dashboard', { p_months_back: monthsBack });
      return analyticsDashboardSchema.parse(raw);
    },
    staleTime: 5 * 60 * 1000,
  });
}
