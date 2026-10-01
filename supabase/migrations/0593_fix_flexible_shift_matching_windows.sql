-- Migration 0593: Fix flexible shift matching arrival windows
-- Problem: Migration 0588 used a naive 09:30 cutoff (v_time <= 09:30 -> SHIFT_9_5).
-- This resulted in employees arriving early for the official shift (e.g. at 09:27 AM, before 10:00 AM)
-- being assigned to the 09:00 AM shift and penalized 27 minutes late, while someone arriving at 09:31 AM
-- was assigned to 10:00 AM shift with 0 late minutes.
-- Solution: Align matching windows with each shift's grace period:
--   • Up to 09:15 AM: Morning shift (09:00–17:00) — on time.
--   • 09:16 to 10:15 AM: Official shift (10:00–18:00) — on time / early.
--   • 10:16 to 11:15 AM: Evening shift (11:00–19:00) — on time / early.
--   • After 11:15 AM: Evening shift (11:00–19:00) — late from 11:00 AM.

CREATE OR REPLACE FUNCTION public.match_flexible_shift(p_check_in timestamptz)
RETURNS uuid
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
declare
  v_time time;
  v_shift_code text;
  v_shift_id uuid;
begin
  if p_check_in is null then
    return public.default_shift_id();
  end if;

  v_time := (p_check_in at time zone 'Africa/Cairo')::time;
  
  -- مطابقة نافذة الوصول للورديات المرنة الثلاث:
  -- 1) حضور حتى 09:15 ص (بداية 09:00 مع 15 دقيقة سماح) -> الوردية الصباحية (9 ص – 5 م)
  -- 2) حضور بين 09:16 ص و 10:15 ص (بداية 10:00 مع 15 دقيقة سماح) -> الدوام الأساسي (10 ص – 6 م)
  -- 3) حضور بعد 10:15 ص -> الوردية المسائية (11 ص – 7 م)
  if v_time <= '09:15:00'::time then
    v_shift_code := 'SHIFT_9_5';
  elsif v_time <= '10:15:00'::time then
    v_shift_code := 'OFFICIAL';
  else
    v_shift_code := 'SHIFT_11_7';
  end if;

  select id into v_shift_id
  from public.shifts
  where code = v_shift_code and is_active
  limit 1;

  return coalesce(v_shift_id, public.default_shift_id());
end;
$fn$;

-- تنظيف غرامات وسجلات اليوم 2026-10-01 التي تأثرت بالنافذة الخاطئة القديمة
UPDATE public.attendance_events ae
SET late_minutes = public.attendance_policy_late_minutes(ae.employee_id, (ae.event_at at time zone 'Africa/Cairo')::date, ae.event_at, null)
WHERE (ae.event_at at time zone 'Africa/Cairo')::date = '2026-10-01'
  AND ae.event_type = 'CHECK_IN'
  AND ae.status in ('accepted', 'adjusted');

UPDATE public.attendance_daily ad
SET shift_id = public.match_flexible_shift(ad.first_check_in),
    late_minutes = public.attendance_policy_late_minutes(ad.employee_id, ad.work_date, ad.first_check_in, null),
    status = case 
      when public.attendance_policy_late_minutes(ad.employee_id, ad.work_date, ad.first_check_in, null) > 0 then 'late'
      else 'present'
    end
WHERE ad.work_date = '2026-10-01'
  AND ad.first_check_in is not null;

-- إلغاء أي غرامة فورية نشأت عن تأخير حضور فعلي لحضور قبل 10:15 ص
UPDATE public.instant_attendance_penalties ip
SET status = 'cancelled',
    cancelled_reason = 'إلغاء: الحضور في موعد الوردية الأساسية (قبل 10:15 ص ضمن الفترات المرنة المعتمدة)',
    notes = coalesce(ip.notes, '') || ' | تم الإلغاء: الحضور يطابق الدوام الأساسي بدون تأخير وفق النوافذ المرنة المصححة'
WHERE ip.work_date = '2026-10-01'
  AND ip.status = 'pending_payment'
  AND exists (
    SELECT 1 FROM public.attendance_daily ad
    WHERE ad.employee_id = ip.employee_id
      AND ad.work_date = ip.work_date
      AND (ad.first_check_in at time zone 'Africa/Cairo')::time <= '10:15:00'::time
  );

COMMENT ON FUNCTION public.match_flexible_shift(timestamptz) IS
  '0593: تصحيح نوافذ مطابقة الورديات المرنة لتتوافق مع سماح كل وردية وتمنع معاقبة من يحضر مبكراً للدوام الأساسي.';
