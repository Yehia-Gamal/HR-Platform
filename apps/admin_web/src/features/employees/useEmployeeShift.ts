import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { cairoTodayIso } from '../../core/cairoTime';
import { rpc } from '../../core/rpc';
import { getSupabase } from '../../core/supabase';
import { useAuth } from '../auth/AuthProvider';

export interface Shift {
  id: string;
  code: string;
  name: string;
  nameEn: string | null;
  startTime: string;
  endTime: string;
  graceInMinutes: number;
}

export interface EmployeeShiftAssignment {
  assignmentId: string | null;
  shiftId: string;
  shiftCode: string;
  shiftName: string;
  startTime: string;
  endTime: string;
  graceInMinutes: number;
  effectiveFrom: string;
  effectiveTo: string | null;
  isAssigned: boolean;
  notes: string | null;
}

export const MOCK_SHIFTS: Shift[] = [
  {
    id: '00000000-0000-0000-0000-000000000010',
    code: 'SHIFT_9_5',
    name: 'الوردية الصباحية (9:00 ص – 5:00 م)',
    nameEn: 'Morning Shift (9:00 AM – 5:00 PM)',
    startTime: '09:00:00',
    endTime: '17:00:00',
    graceInMinutes: 15,
  },
  {
    id: '00000000-0000-0000-0000-000000000011',
    code: 'OFFICIAL',
    name: 'الدوام الأساسي العام (10:00 ص – 6:00 م)',
    nameEn: 'General Official (10:00 AM – 6:00 PM)',
    startTime: '10:00:00',
    endTime: '18:00:00',
    graceInMinutes: 15,
  },
  {
    id: '00000000-0000-0000-0000-000000000012',
    code: 'SHIFT_11_7',
    name: 'الوردية المسائية (11:00 ص – 7:00 م)',
    nameEn: 'Evening Shift (11:00 AM – 7:00 PM)',
    startTime: '11:00:00',
    endTime: '19:00:00',
    graceInMinutes: 15,
  },
];

export function formatTimeString(timeStr?: string | null): string {
  if (!timeStr) return '—';
  const parts = timeStr.split(':');
  if (parts.length < 2) return timeStr;
  const h = parseInt(parts[0], 10);
  const m = parseInt(parts[1], 10);
  if (isNaN(h) || isNaN(m)) return timeStr;
  const isPm = h >= 12;
  const displayH = h % 12 === 0 ? 12 : h % 12;
  const paddedM = m < 10 ? `0${m}` : `${m}`;
  return `${displayH}:${paddedM} ${isPm ? 'م' : 'ص'}`;
}

export function formatShiftTiming(startTime: string, endTime: string, graceInMinutes = 15): string {
  const startFmt = formatTimeString(startTime);
  const endFmt = formatTimeString(endTime);
  return `${startFmt} – ${endFmt} (سماح حتى ${formatGraceTime(startTime, graceInMinutes)})`;
}

function formatGraceTime(startTime: string, graceMinutes: number): string {
  const parts = startTime.split(':');
  if (parts.length < 2) return startTime;
  let h = parseInt(parts[0], 10);
  let m = parseInt(parts[1], 10) + graceMinutes;
  while (m >= 60) {
    m -= 60;
    h += 1;
  }
  const isPm = h >= 12;
  const displayH = h % 12 === 0 ? 12 : h % 12;
  const paddedM = m < 10 ? `0${m}` : `${m}`;
  return `${displayH}:${paddedM} ${isPm ? 'م' : 'ص'}`;
}

export function useAvailableShifts() {
  const auth = useAuth();
  return useQuery({
    queryKey: ['available-shifts', auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<Shift[]> => {
      if (auth.isMock) return MOCK_SHIFTS;
      const supabase = await getSupabase();
      const { data, error } = await supabase
        .from('shifts')
        .select('id, code, name, name_en, start_time, end_time, grace_in_minutes')
        .eq('is_active', true)
        .order('start_time', { ascending: true });
      if (error) throw new Error(error.message);
      return (data ?? []).map((row: any) => ({
        id: row.id,
        code: row.code,
        name: row.name,
        nameEn: row.name_en ?? null,
        startTime: row.start_time,
        endTime: row.end_time,
        graceInMinutes: row.grace_in_minutes ?? 15,
      }));
    },
  });
}

export function useEmployeeActiveShift(employeeId: string | undefined) {
  const auth = useAuth();
  return useQuery({
    queryKey: ['employee-shift', employeeId, auth.isMock],
    enabled: auth.status === 'authenticated' && Boolean(employeeId),
    queryFn: async (): Promise<EmployeeShiftAssignment> => {
      if (!employeeId) throw new Error('معرف الموظف غير موجود');
      const today = cairoTodayIso();
      if (auth.isMock) {
        const defaultShift = MOCK_SHIFTS[1]; // OFFICIAL
        return {
          assignmentId: null,
          shiftId: defaultShift.id,
          shiftCode: defaultShift.code,
          shiftName: defaultShift.name,
          startTime: defaultShift.startTime,
          endTime: defaultShift.endTime,
          graceInMinutes: defaultShift.graceInMinutes,
          effectiveFrom: today,
          effectiveTo: null,
          isAssigned: false,
          notes: null,
        };
      }

      const supabase = await getSupabase();
      // 1) فحص shift_assignments المعتمدة النشطة
      const { data, error } = await supabase
        .from('shift_assignments')
        .select(`
          id,
          shift_id,
          effective_from,
          effective_to,
          notes,
          shifts (
            id,
            code,
            name,
            name_en,
            start_time,
            end_time,
            grace_in_minutes
          )
        `)
        .eq('employee_id', employeeId)
        .eq('is_active', true)
        .lte('effective_from', today)
        .or(`effective_to.is.null,effective_to.gte.${today}`)
        .order('effective_from', { ascending: false })
        .limit(1)
        .maybeSingle();

      if (error) {
        console.warn('Failed to fetch employee shift assignment:', error.message);
      }

      if (data && data.shifts) {
        const s = Array.isArray(data.shifts) ? data.shifts[0] : (data.shifts as any);
        return {
          assignmentId: data.id,
          shiftId: s.id,
          shiftCode: s.code,
          shiftName: s.name,
          startTime: s.start_time,
          endTime: s.end_time,
          graceInMinutes: s.grace_in_minutes ?? 15,
          effectiveFrom: data.effective_from,
          effectiveTo: data.effective_to,
          isAssigned: true,
          notes: data.notes ?? null,
        };
      }

      // 2) إذا لم يوجد إسناد، جلب الوردية الرسمية العامة الافتراضية
      const { data: defaultShiftData } = await supabase
        .from('shifts')
        .select('id, code, name, name_en, start_time, end_time, grace_in_minutes')
        .eq('code', 'OFFICIAL')
        .eq('is_active', true)
        .maybeSingle();

      if (defaultShiftData) {
        return {
          assignmentId: null,
          shiftId: defaultShiftData.id,
          shiftCode: defaultShiftData.code,
          shiftName: defaultShiftData.name,
          startTime: defaultShiftData.start_time,
          endTime: defaultShiftData.end_time,
          graceInMinutes: defaultShiftData.grace_in_minutes ?? 15,
          effectiveFrom: today,
          effectiveTo: null,
          isAssigned: false,
          notes: null,
        };
      }

      // Fallback
      return {
        assignmentId: null,
        shiftId: '00000000-0000-0000-0000-000000000011',
        shiftCode: 'OFFICIAL',
        shiftName: 'الدوام الأساسي العام (10:00 ص – 6:00 م)',
        startTime: '10:00:00',
        endTime: '18:00:00',
        graceInMinutes: 15,
        effectiveFrom: today,
        effectiveTo: null,
        isAssigned: false,
        notes: null,
      };
    },
  });
}

export function useSetEmployeeShiftAdmin() {
  const auth = useAuth();
  const client = useQueryClient();

  return useMutation({
    mutationFn: async ({
      employeeId,
      shiftId,
      effectiveFrom,
      notes,
    }: {
      employeeId: string;
      shiftId: string;
      effectiveFrom?: string;
      notes?: string;
    }) => {
      if (auth.isMock) {
        return { success: true };
      }
      return rpc('set_employee_shift_admin', {
        p_employee_id: employeeId,
        p_shift_id: shiftId,
        p_effective_from: effectiveFrom ?? null,
        p_notes: notes ?? null,
      });
    },
    onSuccess: async (_, variables) => {
      await Promise.all([
        client.invalidateQueries({ queryKey: ['employee-shift', variables.employeeId] }),
        client.invalidateQueries({ queryKey: ['employee-360', variables.employeeId] }),
        client.invalidateQueries({ queryKey: ['available-shifts'] }),
      ]);
    },
  });
}
