-- 0140: V17 §4.2 — إضافة معامل p_days إلى get_my_attendance_history.
-- Flutter يرسل p_days: 30 لتصفية آخر 30 يومًا بدلاً من استرجاع كل السجلات.
-- المعامل اختياري (default null) للتوافق مع الاستدعاءات القديمة.
-- ============================================================================

-- إسقاط النسخة القديمة (معاملان فقط) لأن CREATE OR REPLACE لا يسمح بتغيير المعاملات
drop function if exists public.get_my_attendance_history(integer, timestamptz);

create or replace function public.get_my_attendance_history(
  p_limit  integer       default 60,
  p_before timestamptz   default null,
  p_days   integer       default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_employee_id uuid := public.current_employee_id();
  v_limit       integer := greatest(1, least(coalesce(p_limit, 60), 200));
  v_cutoff      timestamptz;
  v_result      jsonb;
begin
  if auth.uid() is null or v_employee_id is null then
    raise exception 'authenticated employee is required' using errcode = '42501';
  end if;

  -- p_days: تصفية إلى آخر N يوم (اختياري)
  if p_days is not null and p_days > 0 then
    v_cutoff := now() - make_interval(days => p_days);
  end if;

  select coalesce(jsonb_agg(item order by event_at desc), '[]'::jsonb)
  into v_result
  from (
    select
      ae.event_at,
      jsonb_build_object(
        'id',                 ae.id,
        'eventType',          ae.event_type,
        'eventAt',            ae.event_at,
        'status',             ae.status,
        'verificationStatus', ae.verification_status,
        'lateMinutes',        ae.late_minutes,
        'requiresReview',     ae.requires_review,
        'accuracyMeters',     ae.accuracy_meters,
        'distanceMeters',     ae.distance_meters,
        'source',             ae.source,
        'notes',              ae.notes
      ) as item
    from public.attendance_events ae
    where ae.employee_id = v_employee_id
      and (p_before is null or ae.event_at < p_before)
      and (v_cutoff  is null or ae.event_at >= v_cutoff)
    order by ae.event_at desc
    limit v_limit
  ) history;

  return v_result;
end;
$$;

revoke execute on function public.get_my_attendance_history(integer, timestamptz, integer) from public;
grant execute on function public.get_my_attendance_history(integer, timestamptz, integer) to authenticated;

comment on function public.get_my_attendance_history(integer, timestamptz, integer) is
  'V17 §4.2: سجل حضور الموظف الشخصي مع تصفية اختيارية بعدد الأيام (p_days). 0140: أُضيف p_days.';
