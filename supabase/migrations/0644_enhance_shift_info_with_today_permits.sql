-- ===========================================================================
-- 0644: ترقية جلب بيانات الوردية ليشمل أذونات اليوم والتوقيت الفعلي المصرح به
-- ===========================================================================

create or replace function public.get_my_work_shift_info()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me            uuid := public.current_employee_id();
  v_today         date := (now() at time zone 'Africa/Cairo')::date;
  v_assign        record;
  v_default_shift record;
  v_current_shift jsonb;
  v_available     jsonb;
  v_pending       jsonb := null;
  v_req           record;
  v_today_permit  record;
  v_permit_obj    jsonb := null;
  v_shift_start   time;
  v_shift_end     time;
  v_shift_grace   integer := 15;
  v_eff_start     time;
  v_eff_grace_end time;
  v_eff_end       time;
  v_has_permit    boolean := false;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  -- 1) فحص الوردية المعتمدة المسندة حالياً للموظف
  select sa.id as assignment_id, sa.effective_from, sa.notes,
         s.id as shift_id, s.code, s.name, s.name_en, s.start_time, s.end_time,
         coalesce(s.grace_in_minutes, 15) as grace_in_minutes
    into v_assign
    from public.shift_assignments sa
    join public.shifts s on s.id = sa.shift_id
   where sa.employee_id = v_me
     and sa.is_active = true
     and sa.effective_from <= v_today
     and (sa.effective_to is null or sa.effective_to >= v_today)
   order by sa.effective_from desc
   limit 1;

  if v_assign.shift_id is not null then
    v_shift_start := coalesce(v_assign.start_time, '10:00:00'::time);
    v_shift_end := coalesce(v_assign.end_time, '18:00:00'::time);
    v_shift_grace := coalesce(v_assign.grace_in_minutes, 15);
  else
    -- الدوام الأساسي الافتراضي العام
    select s.id, s.code, s.name, s.name_en, s.start_time, s.end_time,
           coalesce(s.grace_in_minutes, 15) as grace_in_minutes
      into v_default_shift
      from public.shifts s
     where s.code = 'OFFICIAL' and s.is_active
     limit 1;

    if v_default_shift.id is null then
      select s.id, s.code, s.name, s.name_en, s.start_time, s.end_time,
             coalesce(s.grace_in_minutes, 15) as grace_in_minutes
        into v_default_shift
        from public.shifts s
       where s.id = public.default_shift_id();
    end if;

    v_shift_start := coalesce(v_default_shift.start_time, '10:00:00'::time);
    v_shift_end := coalesce(v_default_shift.end_time, '18:00:00'::time);
    v_shift_grace := coalesce(v_default_shift.grace_in_minutes, 15);
  end if;

  -- 2) فحص أي إذن معتمد لليوم (late_permit / early_permit / permit / errand / permission)
  select r.id, r.request_type, r.title, r.status, r.payload,
         coalesce(
           (r.payload->>'minutes')::integer,
           (r.payload->>'duration')::integer,
           ((r.payload->>'hours')::numeric * 60)::integer,
           120
         ) as permit_minutes,
         coalesce(r.payload->>'permitKind',
                  case when r.request_type = 'early_permit' then 'early_departure' else 'late_arrival' end) as permit_kind
    into v_today_permit
    from public.requests r
   where r.employee_id = v_me
     and r.status not in ('rejected', 'cancelled')
     and r.request_type in ('late_permit', 'early_permit', 'permit', 'permission', 'errand', 'late_excuse')
     and coalesce(
       public.try_cast_date(r.payload->>'permitDate'),
       public.try_cast_date(r.payload->>'date'),
       public.try_cast_date(r.payload->>'startDate'),
       public.try_cast_date(r.payload->>'start_date'),
       public.try_cast_date(r.payload->>'workDate'),
       r.created_at::date
     ) = v_today
   order by r.created_at desc
   limit 1;

  v_eff_start := v_shift_start;
  v_eff_grace_end := (v_shift_start + (v_shift_grace || ' minutes')::interval)::time;
  v_eff_end := v_shift_end;

  if v_today_permit.id is not null then
    v_has_permit := true;
    if v_today_permit.permit_kind = 'late_arrival' then
      v_eff_start := (v_shift_start + (v_today_permit.permit_minutes || ' minutes')::interval)::time;
      v_eff_grace_end := (v_eff_start + (v_shift_grace || ' minutes')::interval)::time;
    elsif v_today_permit.permit_kind = 'early_departure' then
      v_eff_end := (v_shift_end - (v_today_permit.permit_minutes || ' minutes')::interval)::time;
    end if;

    v_permit_obj := jsonb_build_object(
      'id', v_today_permit.id,
      'requestType', v_today_permit.request_type,
      'title', coalesce(v_today_permit.title, 'إذن معتمد'),
      'permitMinutes', v_today_permit.permit_minutes,
      'permitKind', v_today_permit.permit_kind,
      'status', v_today_permit.status,
      'effectiveStartTime', to_char(v_eff_start, 'HH24:MI:SS'),
      'effectiveGraceEndTime', to_char(v_eff_grace_end, 'HH24:MI:SS'),
      'effectiveEndTime', to_char(v_eff_end, 'HH24:MI:SS')
    );
  end if;

  -- بناء كائن الوردية الحالية
  if v_assign.shift_id is not null then
    v_current_shift := jsonb_build_object(
      'id', v_assign.shift_id,
      'code', v_assign.code,
      'name', v_assign.name,
      'nameEn', v_assign.name_en,
      'startTime', to_char(v_shift_start, 'HH24:MI:SS'),
      'endTime', to_char(v_shift_end, 'HH24:MI:SS'),
      'graceInMinutes', v_shift_grace,
      'isAssigned', true,
      'assignmentId', v_assign.assignment_id,
      'effectiveFrom', v_assign.effective_from,
      'status', 'approved',
      'hasPermitToday', v_has_permit,
      'effectiveStartTime', to_char(v_eff_start, 'HH24:MI:SS'),
      'effectiveGraceEndTime', to_char(v_eff_grace_end, 'HH24:MI:SS'),
      'effectiveEndTime', to_char(v_eff_end, 'HH24:MI:SS')
    );
  else
    v_current_shift := jsonb_build_object(
      'id', v_default_shift.id,
      'code', coalesce(v_default_shift.code, 'OFFICIAL'),
      'name', coalesce(v_default_shift.name, 'الدوام الأساسي (10 ص – 6 م)'),
      'nameEn', v_default_shift.name_en,
      'startTime', to_char(v_shift_start, 'HH24:MI:SS'),
      'endTime', to_char(v_shift_end, 'HH24:MI:SS'),
      'graceInMinutes', v_shift_grace,
      'isAssigned', false,
      'assignmentId', null,
      'effectiveFrom', v_today,
      'status', 'default',
      'hasPermitToday', v_has_permit,
      'effectiveStartTime', to_char(v_eff_start, 'HH24:MI:SS'),
      'effectiveGraceEndTime', to_char(v_eff_grace_end, 'HH24:MI:SS'),
      'effectiveEndTime', to_char(v_eff_end, 'HH24:MI:SS')
    );
  end if;

  -- 3) قائمة الورديات المرنة المتاحة للاختيار (مرتبة حسب موعد البداية)
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'id', s.id,
             'code', s.code,
             'name', s.name,
             'nameEn', s.name_en,
             'startTime', to_char(s.start_time, 'HH24:MI:SS'),
             'endTime', to_char(s.end_time, 'HH24:MI:SS'),
             'graceInMinutes', coalesce(s.grace_in_minutes, 15),
             'isDefault', (s.code = 'OFFICIAL'),
             'description', case s.code
               when 'SHIFT_9_5' then 'فترة صباحية تبدأ 9:00 ص (سماح حتى 9:15 ص) وتنتهي 5:00 م'
               when 'OFFICIAL' then 'الدوام الأساسي العام يبدأ 10:00 ص (سماح حتى 10:15 ص) وينتهي 6:00 م'
               when 'SHIFT_11_7' then 'فترة مسائية تبدأ 11:00 ص (سماح حتى 11:15 ص) وتنتهي 7:00 م'
               else 'فترة عمل معتمدة'
             end
           ) order by s.start_time asc
         ), '[]'::jsonb)
    into v_available
    from public.shifts s
   where s.is_active = true
     and s.code in ('SHIFT_9_5', 'OFFICIAL', 'SHIFT_11_7');

  -- 4) فحص أي طلب معلق لتغيير فترة العمل
  select r.id, r.title, r.reason, r.created_at, r.status,
         r.payload->>'shiftId' as requested_shift_id,
         r.payload->>'shiftName' as requested_shift_name
    into v_req
    from public.requests r
   where r.employee_id = v_me
     and r.request_type = 'shift_change'
     and r.status = 'pending'
   order by r.created_at desc
   limit 1;

  if v_req.id is not null then
    v_pending := jsonb_build_object(
      'requestId', v_req.id,
      'title', v_req.title,
      'reason', v_req.reason,
      'requestedShiftId', v_req.requested_shift_id,
      'requestedShiftName', v_req.requested_shift_name,
      'createdAt', v_req.created_at,
      'status', v_req.status
    );
  end if;

  return jsonb_build_object(
    'currentShift', v_current_shift,
    'availableShifts', v_available,
    'pendingRequest', v_pending,
    'todayPermit', v_permit_obj
  );
end;
$$;

revoke all on function public.get_my_work_shift_info() from public, anon;
grant execute on function public.get_my_work_shift_info() to authenticated;
comment on function public.get_my_work_shift_info() is
  '0644: جلب بيانات الوردية المعتمدة مع احتساب الإذن اليومي والمواعيد المصرح بها بدقة.';
