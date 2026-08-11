import { useQuery } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';
import { loadDomainMocks } from '../mock/loadDomainMocks';

// اتجاه الحضور آخر 7 أيام — منحنّى مصغّر بجانب بطاقة «حضروا اليوم».
// يجلب get_attendance_dashboard لكل يوم من آخر 7 أيام ويعيد مصفوفة
// { date, present, scheduled } مرتّبة تصاعديًا (الأقدم أولًا).

export interface AttendanceTrendPoint {
  /** تاريخ اليوم بصيغة YYYY-MM-DD */
  date: string;
  /** عدد الحاضرين اليوم */
  present: number;
  /** عدد المجدولين اليوم */
  scheduled: number;
}

const CAIRO_TZ = 'Africa/Cairo';

/** تاريخ بصيغة YYYY-MM-DD في توقيت القاهرة مع إزاحة بالأيام (0 = اليوم). */
export function cairoDateIso(daysOffset = 0): string {
  const d = new Date();
  d.setDate(d.getDate() + daysOffset);
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: CAIRO_TZ,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(d);
  const map: Record<string, string> = {};
  for (const part of parts) map[part.type] = part.value;
  return `${map.year}-${map.month}-${map.day}`;
}

/** يبني قائمة آخر `days` أيام بصيغة YYYY-MM-DD مرتّبة تصاعديًا (الأقدم أولًا). */
function lastDaysIso(days: number): string[] {
  const dates: string[] = [];
  for (let i = days - 1; i >= 0; i--) dates.push(cairoDateIso(-i));
  return dates;
}

/**
 * يجلب اتجاه الحضور لآخر `days` يومًا (افتراضيًا 7).
 * في الوضع الوهمي يُرجع بيانات متغيّرة لتغطية سيناريوهات الألوان.
 */
export function useAttendanceTrend(days = 7, enabled = true) {
  const auth = useAuth();
  return useQuery({
    queryKey: ['attendance-trend-7d', auth.isMock],
    enabled: enabled && auth.status === 'authenticated',
    staleTime: 5 * 60_000,
    queryFn: async (): Promise<AttendanceTrendPoint[]> => {
      const dates = lastDaysIso(days);
      if (auth.isMock) {
        // نتائج متغيّرة تُظهر أعمدة خضراء/برتقالية/حمراء في المعاينة الوهمية.
        const seed = (await loadDomainMocks()).mockAttendanceDashboard;
        const baseScheduled = seed.scheduled;
        const basePresent = seed.present;
        const ratios = [0.92, 0.85, 0.78, 0.46, 0.6, 0.82, 0.88];
        return dates.map((date, idx) => {
          const scheduled = baseScheduled + ((idx % 3) - 1) * 2;
          const ratio = ratios[idx % ratios.length];
          return {
            date,
            present: Math.round((basePresent / baseScheduled) * scheduled * ratio),
            scheduled,
          };
        });
      }
      const results = await Promise.all(
        dates.map(async (date) => {
          const data = await rpc<{ scheduled?: number; present?: number } | null>(
            'get_attendance_dashboard',
            { p_date: date },
          );
          return {
            date,
            present: data?.present ?? 0,
            scheduled: data?.scheduled ?? 0,
          } satisfies AttendanceTrendPoint;
        }),
      );
      return results;
    },
  });
}
