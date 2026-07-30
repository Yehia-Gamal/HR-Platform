import { useQuery } from '@tanstack/react-query';

/** بيانات لوحة التحليلات — مؤقتًا بيانات عرض حتى يُنشأ RPC مخصص */
export function useAnalyticsDashboard() {
  return useQuery({
    queryKey: ['analytics', 'dashboard'],
    queryFn: async () => ({
      monthlyRequests: [
        { name: 'يناير', approved: 12, rejected: 3, pending: 5 },
        { name: 'فبراير', approved: 15, rejected: 2, pending: 3 },
        { name: 'مارس', approved: 18, rejected: 4, pending: 7 },
        { name: 'أبريل', approved: 14, rejected: 1, pending: 4 },
        { name: 'مايو', approved: 20, rejected: 3, pending: 6 },
        { name: 'يونيو', approved: 16, rejected: 2, pending: 3 },
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
        { name: 'الموارد البشرية', value: 4 },
        { name: 'التقنية', value: 7 },
      ],
      kpiScores: [
        { subject: 'الحضور', actual: 85, target: 90 },
        { subject: 'الإنتاجية', actual: 78, target: 80 },
        { subject: 'الجودة', actual: 92, target: 85 },
        { subject: 'التعاون', actual: 88, target: 85 },
        { subject: 'المبادرة', actual: 72, target: 75 },
      ],
    }),
    staleTime: 5 * 60 * 1000,
  });
}
