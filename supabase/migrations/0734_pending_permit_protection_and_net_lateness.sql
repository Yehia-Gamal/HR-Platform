-- ============================================================================
-- Migration: 0734_pending_permit_protection_and_net_lateness.sql
-- Description:
--   1) حماية الموظف صاحب إذن الحضور/التأخير المعلق (pending) أو المعتمد (approved)
--      من إنشاء أي غرامات تأخير فورية أو احتساب تأخير عليه أثناء سريان الإذن.
--   2) احتساب صافي التأخير فقط (Net Lateness): إذا طلب الموظف إذن ساعتين وحضر بعد ساعتين و10 دقائق،
--      يُحسب عليه 10 دقائق فقط (الزائدة عن فترة الإذن وسماحه)، وليس الوقت بالكامل!
--   3) تحديث دالة get_my_work_shift_info لدعم إرجاع تفاصيل الأذونات المعلقة بدقة.
--   4) معالجة رجعية: تعليق/إلغاء الغرامات المسجلة على الموظفين الذين لديهم أذونات معلقة أو معتمدة.
-- ============================================================================

begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) دالة التحقق من وجود إذن معلق للموظف في تاريخ معين
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.is_employee_on_pending_permit(
  p_employee_id uuid,
  p_date        date
) returns boolean
language sql
stable security definer
set search_path = public, pg_temp
as $$
  select exists(
    select 1 from public.requests r
    where r.employee_id = p_employee_id
      and r.status = 'pending'
      and r.request_type in ('late_permit', 'early_permit', 'attendance_permit', 'permit', 'permission', 'errand', 'late_excuse')
      and coalesce(
        public.try_cast_date(r.payload->>'permitDate'),
        public.try_cast_date(r.payload->>'date'),
        public.try_cast_date(r.payload->>'startDate'),
        public.try_cast_date(r.payload->>'start_date'),
        public.try_cast_date(r.payload->>'workDate'),
        r.created_at::date
      ) = p_date
  );
$$;

revoke all on function public.is_employee_on_pending_permit(uuid, date) from public, anon;
grant execute on function public.is_employee_on_pending_permit(uuid, date) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) دالة احتساب صافي دقائق التأخير بعد خصم الأذونات المعتمدة والمعلقة
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.get_net_late_minutes(
  p_employee_id      uuid,
  p_date             date,
  p_actual_late_mins int
) returns int
language plpgsql
stable security definer
set search_path = public, pg_temp
as $$
declare
  v_permit_minutes int := 0;
begin
  if p_actual_late_mins <= 0 then
    return 0;
  end if;

  select coalesce(max(
    coalesce(
      (r.payload->>'minutes')::int,
      (r.payload->>'duration')::int,
      ((r.payload->>'hours')::numeric * 60)::int,
      120
    )
  ), 0)
    into v_permit_minutes
  from public.requests r
  where r.employee_id = p_employee_id
    and r.status in ('approved', 'pending')
    and r.request_type in ('late_permit', 'attendance_permit', 'permit', 'permission', 'errand', 'late_excuse')
    and coalesce(r.payload->>'permitKind', 'late_arrival') <> 'early_departure'
    and coalesce(
      public.try_cast_date(r.payload->>'permitDate'),
      public.try_cast_date(r.payload->>'date'),
      public.try_cast_date(r.payload->>'startDate'),
      public.try_cast_date(r.payload->>'start_date'),
      public.try_cast_date(r.payload->>'workDate'),
      r.created_at::date
    ) = p_date;

  return greatest(0, p_actual_late_mins - v_permit_minutes);
end;
$$;

revoke all on function public.get_net_late_minutes(uuid, date, int) from public, anon;
grant execute on function public.get_net_late_minutes(uuid, date, int) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) تحديث دالة احتساب دقائق التأخير عند البصمة attendance_policy_late_minutes
--    لتخصم دقائق الإذن وتحسب الصافي فقط، وتعفي تماماً إذا كان الإذن يغطي الوقت
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.attendance_policy_late_minutes(
  p_employee_id uuid,
  p_work_date date,
  p_check_in timestamptz,
  p_shift_id uuid default null
)
returns integer
language plpgsql
stable security definer
set search_path = public, pg_temp
as $fn$
declare
  v_shift public.shifts%rowtype;
  v_diff integer;
  v_target_shift_id uuid;
  v_permit_minutes integer := null;
  v_effective_start_epoch timestamptz;
  v_permit_req record;
begin
  if p_check_in is null then
    return 0;
  end if;

  -- 1) فحص الأعذار الكاملة (إجازة، عطلة، استثناء دائم، مأمورية صباحية)
  if public.is_lateness_excused(p_employee_id, p_work_date) then
    return 0;
  end if;

  v_target_shift_id := p_shift_id;

  -- 2) تحديد الوردية المعتمدة
  if v_target_shift_id is null and p_employee_id is not null then
    select sa.shift_id into v_target_shift_id
      from public.shift_assignments sa
     where sa.employee_id = p_employee_id
       and sa.is_active = true
       and sa.effective_from <= p_work_date
       and (sa.effective_to is null or sa.effective_to >= p_work_date)
     order by sa.effective_from desc
     limit 1;
  end if;

  if v_target_shift_id is null then
    v_target_shift_id := public.match_flexible_shift(p_check_in);
  end if;

  select * into v_shift from public.shifts where id = v_target_shift_id;
  if v_shift.id is null or v_shift.start_time is null then
    return 0;
  end if;

  -- 3) فحص هل يوجد إذن تأخير صباحي (approved أو pending بانتظار القرار)
  select r.id, r.request_type, r.status, r.payload into v_permit_req
    from public.requests r
   where r.employee_id = p_employee_id
     and r.status in ('approved', 'pending')
     and r.request_type in ('late_permit', 'permit', 'permission', 'errand', 'late_excuse')
     and coalesce(r.payload->>'permitKind', 'late_arrival') <> 'early_departure'
     and coalesce(
       public.try_cast_date(r.payload->>'permitDate'),
       public.try_cast_date(r.payload->>'date'),
       public.try_cast_date(r.payload->>'startDate'),
       public.try_cast_date(r.payload->>'start_date'),
       public.try_cast_date(r.payload->>'workDate'),
       r.created_at::date
     ) = p_work_date
   order by case when r.status = 'approved' then 1 else 2 end, r.created_at desc
   limit 1;

  if v_permit_req.id is not null then
    v_permit_minutes := coalesce(
      (v_permit_req.payload->>'minutes')::integer,
      (v_permit_req.payload->>'duration')::integer,
      ((v_permit_req.payload->>'hours')::numeric * 60)::integer,
      120
    );
  end if;

  -- 4) حساب وقت البداية الفعلي مع إضافة دقائق الإذن إن وُجد
  v_effective_start_epoch := ((p_work_date + v_shift.start_time)::timestamp at time zone 'Africa/Cairo')
    + (coalesce(v_permit_minutes, 0) || ' minutes')::interval;

  v_diff := floor(extract(epoch from (p_check_in - v_effective_start_epoch)) / 60)::integer;

  -- التأخير هو فقط ما زاد عن فترة الإذن وسماح الوردية
  return case when v_diff > coalesce(v_shift.grace_in_minutes, 0) then least(greatest(0, v_diff), 120) else 0 end;
end;
$fn$;

revoke all on function public.attendance_policy_late_minutes(uuid, date, timestamptz, uuid) from public, anon;
grant execute on function public.attendance_policy_late_minutes(uuid, date, timestamptz, uuid) to service_role, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4) تحديث دالة الإعفاء من الغرامات الفورية is_employee_exempt_from_instant_penalty
--    لحماية الموظف الذي لديه طلب إذن معلق أو معتمد يغطي وقته
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.is_employee_exempt_from_instant_penalty(
  p_employee_id uuid,
  p_work_date   date
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_req record;
  v_wa record;
  v_att record;
  v_loc text;
begin
  -- 1) فحص الاستثناء الإداري الدائم
  if public.is_employee_penalty_exempt(p_employee_id) or public.is_employee_attendance_exempt(p_employee_id) then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'permanent_exemption',
      'reason', case
        when public.is_employee_attendance_exempt(p_employee_id)
          then 'معفى دائماً بقرار إداري من الحضور والانصراف والغرامات'
        else
          'معفى دائماً بقرار إداري من جميع الغرامات والخصومات'
      end
    );
  end if;

  -- 2) عطلة نهاية الأسبوع (الجمعة)
  if extract(isodow from p_work_date)::integer = 5 then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'weekend',
      'reason', 'عطلة نهاية الأسبوع الرسمية (يوم الجمعة)'
    );
  end if;

  -- 3) العطلات الرسمية
  if exists (select 1 from public.public_holidays where holiday_date = p_work_date) then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'holiday',
      'reason', 'عطلة رسمية معتمدة'
    );
  end if;

  -- 4) فحص الإجازات
  select r.request_type, coalesce(lt.name_ar, r.payload->>'leaveType', 'إجازة') as leave_type, r.status into v_req
    from public.leave_requests lr
    join public.requests r on r.id = lr.request_id
    left join public.leave_types lt on lt.id = lr.leave_type_id
   where lr.employee_id = p_employee_id
     and r.status not in ('rejected', 'cancelled')
     and p_work_date between lr.start_date and lr.end_date
   limit 1;

  if v_req.request_type is not null then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'leave',
      'reason', 'إجازة ' || coalesce(v_req.leave_type, 'رسمية') || case when v_req.status = 'pending' then ' (طلب مسجل قيد المراجعة)' else ' (معتمدة)' end
    );
  end if;

  -- 5) فحص أذونات الحضور والتأخير (سواء معتمدة أو معلقة قيد القرار)
  for v_req in
    select r.id, r.request_type, r.status, r.payload
      from public.requests r
     where r.employee_id = p_employee_id
       and r.status not in ('rejected', 'cancelled')
       and r.request_type in ('late_permit', 'early_permit', 'permit', 'permission', 'errand', 'late_excuse')
       and coalesce(
         public.try_cast_date(r.payload->>'permitDate'),
         public.try_cast_date(r.payload->>'date'),
         public.try_cast_date(r.payload->>'startDate'),
         public.try_cast_date(r.payload->>'start_date'),
         public.try_cast_date(r.payload->>'workDate'),
         r.created_at::date
       ) = p_work_date
     order by case when r.status = 'approved' then 1 else 2 end, r.created_at desc
     limit 1
  loop
    if v_req.request_type in ('late_permit', 'permit', 'permission', 'errand', 'late_excuse')
       and coalesce(v_req.payload->>'permitKind', 'late_arrival') <> 'early_departure' then
      declare
        v_first_punch timestamptz;
        v_emp_shift public.shifts%rowtype;
        v_permit_mins integer;
        v_deadline timestamptz;
      begin
        select coalesce(
          (select ad.first_check_in from public.attendance_daily ad where ad.employee_id = p_employee_id and ad.work_date = p_work_date limit 1),
          (select min(ae.event_at) from public.attendance_events ae where ae.employee_id = p_employee_id and (ae.event_at at time zone 'Africa/Cairo')::date = p_work_date and ae.event_type = 'CHECK_IN' and ae.status in ('accepted', 'adjusted'))
        ) into v_first_punch;

        select s.* into v_emp_shift
          from public.shifts s
         where s.id = coalesce(
           (select sa.shift_id from public.shift_assignments sa where sa.employee_id = p_employee_id and sa.is_active = true and sa.effective_from <= p_work_date and (sa.effective_to is null or sa.effective_to >= p_work_date) order by sa.effective_from desc limit 1),
           public.match_flexible_shift(v_first_punch),
           public.default_shift_id()
         );

        v_permit_mins := coalesce(
          (v_req.payload->>'minutes')::integer,
          (v_req.payload->>'duration')::integer,
          ((v_req.payload->>'hours')::numeric * 60)::integer,
          120
        );

        -- إذا كان الطلب لا يزال معلقاً (Pending) ولم يبصم الموظف بعد، أو بصم ضمن فترة الإذن:
        -- يُعفى فوراً من أي غرامة لحين بت الإدارة في طلبه
        if v_req.status = 'pending' then
          return jsonb_build_object(
            'isExempt', true,
            'category', 'pending_permit',
            'reason', 'طلب إذن حضور مسجل (' || v_permit_mins || ' دقيقة) قيد انتظار قرار المدير — الغرامات موقوفة'
          );
        end if;

        if v_emp_shift.id is not null and v_emp_shift.start_time is not null then
          v_deadline := ((p_work_date + v_emp_shift.start_time)::timestamp at time zone 'Africa/Cairo')
            + (v_permit_mins || ' minutes')::interval
            + (coalesce(v_emp_shift.grace_in_minutes, 15) || ' minutes')::interval;

          if v_first_punch is not null and v_first_punch > v_deadline then
            null; -- تأخر لما بعد الإذن وسماحه
          else
            return jsonb_build_object(
              'isExempt', true,
              'category', 'permit',
              'reason', 'إذن حضور/تأخير رسمي مسجل (' || v_permit_mins || ' دقيقة) — الحضور ضمن فترة الإذن'
            );
          end if;
        else
          return jsonb_build_object(
            'isExempt', true,
            'category', 'permit',
            'reason', 'إذن حضور/تأخير رسمي مسجل' || case when v_req.status = 'pending' then ' (قيد المراجعة)' else ' (معتمد)' end
          );
        end if;
      end;
    else
      -- إذن انصراف مبكر
      return jsonb_build_object(
        'isExempt', true,
        'category', 'permit',
        'reason', 'إذن رسمي مسجل' || case when v_req.status = 'pending' then ' (قيد المراجعة)' else ' (معتمد)' end
      );
    end if;
  end loop;

  -- 6) مأمورية عمل
  if exists (
    select 1 from public.mission_executions me
      join public.requests rq on rq.id = me.request_id
     where me.employee_id = p_employee_id
       and me.status in ('in_progress', 'completed')
       and rq.status not in ('rejected', 'cancelled', 'returned')
       and (me.started_at at time zone 'Africa/Cairo')::date = p_work_date
       and me.started_at <= public.employee_lateness_deadline(p_employee_id, p_work_date)
  ) then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'mission',
      'reason', 'مأمورية عمل رسمية مبدوءة في الموعد'
    );
  end if;

  return jsonb_build_object('isExempt', false);
end;
$function$;

revoke all on function public.is_employee_exempt_from_instant_penalty(uuid, date) from public, anon;
grant execute on function public.is_employee_exempt_from_instant_penalty(uuid, date) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5) معالجة رجعية: تعليق أو إلغاء أي غرامات تأخير صدرت لموظفين لديهم أذونات معلقة
-- ─────────────────────────────────────────────────────────────────────────────
update public.instant_attendance_penalties iap
set status = 'suspended',
    notes = coalesce(notes || ' | ', '') || 'إيقاف تلقائي: يوجد طلب إذن حضور/تأخير قيد الانتظار',
    updated_at = now()
where iap.status in ('pending_payment', 'doubled')
  and iap.work_date >= current_date - interval '7 days'
  and public.is_employee_on_pending_permit(iap.employee_id, iap.work_date);

-- إلغاء الغرامات التي اعتُمدت أذوناتها بالفعل
update public.instant_attendance_penalties iap
set status = 'cancelled',
    cancelled_reason = 'إلغاء تلقائي: اعتماد إذن الحضور/التأخير الرسمي للموظف',
    notes = coalesce(notes || ' | ', '') || 'إلغاء تلقائي: اعتماد إذن الحضور الرسمي',
    updated_at = now()
where iap.status in ('pending_payment', 'doubled', 'suspended')
  and iap.work_date >= current_date - interval '7 days'
  and exists (
    select 1 from public.requests r
    where r.employee_id = iap.employee_id
      and r.status = 'approved'
      and r.request_type in ('late_permit', 'early_permit', 'attendance_permit', 'permit', 'permission', 'errand', 'late_excuse')
      and coalesce(
        public.try_cast_date(r.payload->>'permitDate'),
        public.try_cast_date(r.payload->>'date'),
        public.try_cast_date(r.payload->>'startDate'),
        public.try_cast_date(r.payload->>'start_date'),
        public.try_cast_date(r.payload->>'workDate'),
        r.created_at::date
      ) = iap.work_date
  );

commit;

