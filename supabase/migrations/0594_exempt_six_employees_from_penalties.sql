-- Migration 0594: Exempt 6 employees from attendance penalties
-- Employees:
--   1. عبد الملك محمد يوسف (cc893835-ceb3-44b8-b4c4-9802c38e3195)
--   2. ياسين طارق الباسل (41751008-afdd-4537-a6db-05021f1c1e00)
--   3. عبدالله احمد نصر (c61c2a26-19db-49fb-ad8b-ace2d8a765af)
--   4. هاني احمد نصير (8e21d363-f87c-4c80-b06d-1b84a2dd3804)
--   5. عبدالعزيز طارق محمود الباسل (fad7044c-fe47-4db3-b7bb-54856e7ba851)
--   6. محمد عبده رجب مزار (8c529e5b-112d-45d2-9fb1-721b73086351)

-- 1) تحديث دالة فحص الإعفاء من الغرامات
CREATE OR REPLACE FUNCTION public.is_employee_penalty_exempt(p_employee_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  select public.is_employee_attendance_exempt(p_employee_id)
      or public.is_clinic_staff_exempt(p_employee_id)
      or p_employee_id in (
        'cc893835-ceb3-44b8-b4c4-9802c38e3195', -- عبد الملك محمد يوسف
        '41751008-afdd-4537-a6db-05021f1c1e00', -- ياسين طارق الباسل
        'c61c2a26-19db-49fb-ad8b-ace2d8a765af', -- عبدالله احمد نصر
        '8e21d363-f87c-4c80-b06d-1b84a2dd3804', -- هاني احمد نصير
        'fad7044c-fe47-4db3-b7bb-54856e7ba851', -- عبدالعزيز طارق محمود الباسل
        '8c529e5b-112d-45d2-9fb1-721b73086351'  -- محمد عبده رجب مزار
      )
      or exists (
        select 1 from public.employees e
        where e.id = p_employee_id and e.is_penalty_exempt = true
      );
$function$;

-- 2) تصحيح محفز منع الغرامات ليتيح تحديث الغرامة إلى ملغاة ويمنع الإدراج
CREATE OR REPLACE FUNCTION public.tg_prevent_admin_penalty_fn()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if public.is_employee_penalty_exempt(NEW.employee_id)
     or public.is_employee_attendance_exempt(NEW.employee_id) then
    if TG_OP = 'INSERT' then
      return null; -- منع إدراج أي غرامة جديدة للموظف المعفى
    elsif TG_OP = 'UPDATE' then
      NEW.status := 'cancelled';
      NEW.cancelled_reason := coalesce(NEW.cancelled_reason, 'إلغاء: الموظف معفى من الغرامات بقرار الإدارة');
      return NEW;
    end if;
  end if;
  return NEW;
end;
$function$;

-- 3) تحديث دالة عذر التأخير لتشمل المعفى من الغرامة
CREATE OR REPLACE FUNCTION public.is_lateness_excused(p_employee_id uuid, p_work_date date)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
  select public.is_employee_attendance_exempt(p_employee_id)
    or public.is_employee_penalty_exempt(p_employee_id)
    or extract(isodow from p_work_date) = 5
    or exists (
      select 1 from public.public_holidays h
      where coalesce(h.is_active, true)
        and p_work_date between h.holiday_date and coalesce(h.end_date, h.holiday_date))
    or exists (
      select 1 from public.attendance_day_overrides o
      where o.employee_id = p_employee_id and o.work_date = p_work_date and o.is_active
        and o.day_type in ('leave', 'mission', 'convoy', 'fundraising', 'holiday', 'rest'))
    or exists (
      select 1 from public.attendance_daily ad
      where ad.employee_id = p_employee_id and ad.work_date = p_work_date and ad.status = 'on_leave')
    or exists (
      select 1 from public.leave_requests lr
      join public.requests r on r.id = lr.request_id
      where lr.employee_id = p_employee_id and r.status not in ('rejected', 'cancelled')
        and p_work_date between lr.start_date and lr.end_date)
    or exists (
      select 1 from public.requests r
      where r.employee_id = p_employee_id and r.status not in ('rejected', 'cancelled')
        and r.request_type in ('late_permit', 'early_permit', 'permit', 'permission', 'errand', 'late_excuse')
        and coalesce(public.try_cast_date(r.payload->>'permitDate'), public.try_cast_date(r.payload->>'date'),
                     public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'),
                     public.try_cast_date(r.payload->>'workDate'), r.created_at::date) = p_work_date)
    or exists (
      select 1 from public.requests r
      where r.employee_id = p_employee_id and r.status in ('approved', 'in_progress')
        and r.request_type in ('mission', 'convoy', 'fundraising')
        and p_work_date between coalesce(public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'), r.created_at::date)
                            and coalesce(public.try_cast_date(r.payload->>'endDate'), public.try_cast_date(r.payload->>'end_date'), r.created_at::date));
$fn$;

-- 4) تحديث حقل is_penalty_exempt في جدول الموظفين
UPDATE public.employees
SET is_penalty_exempt = true
WHERE id IN (
  'cc893835-ceb3-44b8-b4c4-9802c38e3195', -- عبد الملك محمد يوسف
  '41751008-afdd-4537-a6db-05021f1c1e00', -- ياسين طارق الباسل
  'c61c2a26-19db-49fb-ad8b-ace2d8a765af', -- عبدالله احمد نصر
  '8e21d363-f87c-4c80-b06d-1b84a2dd3804', -- هاني احمد نصير
  'fad7044c-fe47-4db3-b7bb-54856e7ba851', -- عبدالعزيز طارق محمود الباسل
  '8c529e5b-112d-45d2-9fb1-721b73086351'  -- محمد عبده رجب مزار
);

-- 5) إلغاء كافة الغرامات المعلقة للموظفين الستة
UPDATE public.instant_attendance_penalties
SET status = 'cancelled',
    cancelled_reason = 'إلغاء: الموظف معفى من الغرامات بقرار الإدارة',
    notes = coalesce(notes, '') || ' | تم الإلغاء بقرار الإدارة: معفى من الغرامات',
    updated_at = now()
WHERE employee_id IN (
  'cc893835-ceb3-44b8-b4c4-9802c38e3195',
  '41751008-afdd-4537-a6db-05021f1c1e00',
  'c61c2a26-19db-49fb-ad8b-ace2d8a765af',
  '8e21d363-f87c-4c80-b06d-1b84a2dd3804',
  'fad7044c-fe47-4db3-b7bb-54856e7ba851',
  '8c529e5b-112d-45d2-9fb1-721b73086351'
)
AND status IN ('pending_payment', 'doubled', 'suspended');

-- 6) تصفير دقائق التأخير اليومية لليوم إن وُجدت
UPDATE public.attendance_daily
SET late_minutes = 0,
    status = case when status = 'late' then 'present' else status end
WHERE employee_id IN (
  'cc893835-ceb3-44b8-b4c4-9802c38e3195',
  '41751008-afdd-4537-a6db-05021f1c1e00',
  'c61c2a26-19db-49fb-ad8b-ace2d8a765af',
  '8e21d363-f87c-4c80-b06d-1b84a2dd3804',
  'fad7044c-fe47-4db3-b7bb-54856e7ba851',
  '8c529e5b-112d-45d2-9fb1-721b73086351'
)
AND work_date = '2026-10-01';

UPDATE public.attendance_events
SET late_minutes = 0
WHERE employee_id IN (
  'cc893835-ceb3-44b8-b4c4-9802c38e3195',
  '41751008-afdd-4537-a6db-05021f1c1e00',
  'c61c2a26-19db-49fb-ad8b-ace2d8a765af',
  '8e21d363-f87c-4c80-b06d-1b84a2dd3804',
  'fad7044c-fe47-4db3-b7bb-54856e7ba851',
  '8c529e5b-112d-45d2-9fb1-721b73086351'
)
AND (event_at at time zone 'Africa/Cairo')::date = '2026-10-01';

COMMENT ON FUNCTION public.is_employee_penalty_exempt(uuid) IS
  '0594: إعفاء دائم وشامل من الغرامات لكل من (عبد الملك، ياسين الباسل، عبدالله نصر، هاني نصير، عبد العزيز الباسل، محمد مزار) بقرار الإدارة.';
