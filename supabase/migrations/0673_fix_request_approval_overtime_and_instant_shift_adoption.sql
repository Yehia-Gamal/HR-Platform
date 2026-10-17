-- ==============================================================================
-- Migration 0673: تصحيح اعتماد الطلبات + اختفاء صفة متأخر عند إتمام 8 ساعات وحساب الإضافي + الاعتماد الفوري للورديات
-- ==============================================================================
-- 1. إصلاح عطل اعتماد الطلبات في decide_request:
--    - تصحيح تحديث request_steps باستخدام acted_at, acted_by, comment (بدلاً من الأعمدة غير الموجودة).
--    - تصحيح workflow_status ليلتزم بقيد requests_workflow_status_check ('completed' / 'terminated').
-- 2. اختفاء صفة "متأخر" بمجرد إتمام 8 ساعات عمل وحساب الوقت الإضافي بالدقائق:
--    - في record_attendance_local_biometric و get_my_attendance_state:
--      إذا كانت دقائق العمل work_minutes >= 480 (8 ساعات) تصبح الحالة 'present' تلقائياً.
--      إذا زادت الدقائق عن 480 يُحسب الوقت الإضافي بدقة: overtime_minutes = work_minutes - 480.
-- 3. الاعتماد والتثبيت الفوري للوردية المختارة عند البصمة:
--    - دالة adopt_my_work_shift(p_shift_id uuid) لتثبيت فترة العمل للموظف فورياً دون الحاجة لموافقة المدير.
-- ==============================================================================

begin;

-- ─── 1) تصحيح دالة اعتماد الطلبات decide_request ─────────────────────────────
create or replace function public.decide_request(
  p_request_id uuid,
  p_decision text,
  p_comment text default null
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me              uuid := public.current_employee_id();
  v_req             public.requests;
  v_step            public.request_steps;
  v_authorized      boolean := false;
  v_is_direct_mgr   boolean;
  v_is_operations   boolean;
  v_is_hr           boolean;
  v_is_exec         boolean;
  v_is_clinic_mgr   boolean;
  v_current_step    integer;
  v_final_status    text;
  v_actor_role      text;
  v_exec_emp        uuid;
  v_correction_id   uuid;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;
  if p_decision not in ('approve','reject','return') then
    raise exception 'invalid decision: %', p_decision using errcode = '22023';
  end if;
  if p_decision = 'return'
     and nullif(trim(coalesce(p_comment, '')), '') is null then
    raise exception 'return_requires_comment' using errcode = '22023';
  end if;

  select * into v_req from public.requests where id = p_request_id for update;
  if not found then
    raise exception 'request not found: %', p_request_id using errcode = 'P0002';
  end if;
  if v_req.status <> 'pending' then
    raise exception 'request is not pending (current: %)', v_req.status using errcode = '22023';
  end if;

  v_is_exec := public.current_has_active_role(array['executive','executive-director','general-manager']);
  v_is_hr   := public.current_has_active_role(array['hr-manager','hr-specialist','hr-officer']);

  -- حظر الاعتماد الذاتي للجميع باستثناء من يملك صلاحية إدارية عليا
  if v_req.employee_id = v_me
     and not (public.current_is_full_access() or v_is_hr or v_is_exec or public.current_has_active_role(array['admin','super-admin'])) then
    raise exception 'الاعتماد الذاتي غير مسموح' using errcode = '42501';
  end if;

  -- الخطوة الحالية: نفضّل الخطوة النشطة (active)، وإن لم توجد نأخذ أول escalated/pending
  select * into v_step
  from public.request_steps
  where request_id = p_request_id
    and status in ('active','escalated','pending')
  order by (status = 'active') desc, step_order
  limit 1
  for update;

  v_current_step  := coalesce(v_step.step_order, 0);

  -- التحقق من كون المعتمِد مدير العيادات (مصطفى أحمد أو يوسف رسمي أو دور clinics-manager)
  v_is_clinic_mgr := (
    v_me in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid)
    or public.current_has_active_role(array['clinics-manager'])
  );

  -- التحقق من صفة المدير المباشر:
  v_is_direct_mgr := (v_req.manager_employee_id = v_me)
    or (
      v_is_clinic_mgr and (
        public.is_clinic_team_member(v_req.employee_id)
        or v_req.manager_employee_id in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid)
        or exists (
          select 1 from public.workflow_definitions wd
          where wd.id = v_req.workflow_definition_id and wd.code like 'medical_%'
        )
      )
    )
    or exists (
      select 1 from public.manager_relations mr
      where mr.employee_id = v_req.employee_id
        and mr.manager_employee_id = v_me
        and mr.relation_type = 'primary'
        and (mr.effective_to is null or mr.effective_to >= current_date)
    );

  v_is_operations := public.current_has_active_role(array['operations-manager-1']);

  -- الصلاحية الشاملة لاعتماد الطلبات:
  v_authorized :=
    public.current_is_full_access()
    or v_is_exec
    or v_is_hr
    or v_is_direct_mgr
    or (v_step.id is not null and (
      v_step.assignee_employee_id = v_me
      or (v_is_clinic_mgr and v_step.assignee_employee_id in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid))
    ))
    or public.current_has_active_role(array['admin','super-admin'])
    or (v_is_operations
        and (
          v_current_step >= 2
          or (v_step.escalation_deadline is not null and v_step.escalation_deadline < now())
          or public.employee_on_leave(coalesce(v_step.assignee_employee_id, v_req.manager_employee_id), (now() at time zone 'Africa/Cairo')::date)
        )
    );

  if not v_authorized then
    raise exception 'غير مصرح لك باتخاذ قرار بشأن هذا الطلب' using errcode = '42501';
  end if;

  -- تحديد الدور الفعلي للمتخذ القرار
  if public.current_is_full_access() or public.current_has_active_role(array['admin','super-admin']) then
    v_actor_role := 'admin';
  elsif v_is_exec then
    v_actor_role := 'executive';
  elsif v_is_hr then
    v_actor_role := 'hr';
  elsif v_is_direct_mgr then
    v_actor_role := 'direct_manager';
  elsif v_is_operations then
    v_actor_role := 'operations';
  else
    v_actor_role := 'manager';
  end if;

  -- 1) إذا كان القرار هو الرفض أو الإرجاع: يُغلق الطلب مباشرة
  if p_decision in ('reject', 'return') then
    v_final_status := case when p_decision = 'reject' then 'rejected' else 'returned' end;

    update public.requests
    set status = v_final_status,
        workflow_status = case when p_decision = 'reject' then 'terminated' else 'in_review' end,
        decided_at = now(),
        decided_by = v_me,
        updated_at = now()
    where id = p_request_id
    returning * into v_req;

    if v_step.id is not null then
      update public.request_steps
      set status = v_final_status,
          acted_at = now(),
          acted_by = v_me,
          comment = p_comment,
          updated_at = now()
      where id = v_step.id;
    end if;

    update public.workflow_instances
    set status = 'completed', completed_at = now(), updated_at = now()
    where request_id = p_request_id and status = 'running';

    insert into public.request_actions (
      request_id, request_step_id, actor_employee_id, action, from_status, to_status, comment, created_by
    ) values (
      p_request_id, v_step.id, v_me, p_decision, 'pending', v_final_status, p_comment, auth.uid()
    );

    perform public.notify_employee(
      v_req.employee_id,
      case when p_decision = 'reject' then 'تم رفض طلبك' else 'تمت إعادة طلبك للمراجعة' end,
      coalesce(v_req.title, '') || case when p_comment is not null then ' — ' || p_comment else '' end,
      'request', 'normal', 'request', v_req.id,
      jsonb_build_object('status', v_final_status, 'decision', p_decision, 'requestId', v_req.id)
    );

    return v_req;
  end if;

  -- 2) إذا كان القرار هو الموافقة (approve):
  if v_step.id is not null then
    update public.request_steps
    set status = 'approved',
        acted_at = now(),
        acted_by = v_me,
        comment = p_comment,
        updated_at = now()
    where id = v_step.id;
  end if;

  insert into public.request_actions (
    request_id, request_step_id, actor_employee_id, action, from_status, to_status, comment, created_by
  ) values (
    p_request_id, v_step.id, v_me, 'approve', 'pending', 'approved', p_comment, auth.uid()
  );

  -- فحص ما إذا كانت هناك خطوات لاحقة تحتاج اعتماداً أعلى
  if exists (
    select 1 from public.request_steps
    where request_id = p_request_id
      and step_order > v_current_step
      and status = 'pending'
  ) and not (public.current_is_full_access() or v_is_exec) then
    -- تنشيط الخطوة التالية
    update public.request_steps
    set status = 'active',
        updated_at = now()
    where request_id = p_request_id
      and step_order = (
        select min(step_order) from public.request_steps
        where request_id = p_request_id and step_order > v_current_step and status = 'pending'
      );

    select * into v_req from public.requests where id = p_request_id;
    return v_req;
  end if;

  -- اعتماد نهائي للطلب:
  update public.requests
  set status = 'approved',
      workflow_status = 'completed',
      decided_at = now(),
      decided_by = v_me,
      updated_at = now()
  where id = p_request_id
  returning * into v_req;

  update public.workflow_instances
  set status = 'completed', completed_at = now(), updated_at = now()
  where request_id = p_request_id and status = 'running';

  -- تطبيق الآثار التلقائية للطلب المعتمد:
  -- أ) تغيير الوردية (shift_change):
  if v_req.request_type = 'shift_change' and v_req.payload->>'shiftId' is not null then
    declare
      v_target_shift_id uuid := nullif(v_req.payload->>'shiftId','')::uuid;
      v_eff_date date := coalesce(nullif(v_req.payload->>'effectiveFrom','')::date, (now() at time zone 'Africa/Cairo')::date);
    begin
      if v_target_shift_id is not null then
        update public.shift_assignments
        set is_active = false,
            effective_to = least(coalesce(effective_to, v_eff_date), v_eff_date),
            updated_at = now()
        where employee_id = v_req.employee_id and is_active = true;

        insert into public.shift_assignments (
          employee_id, shift_id, effective_from, is_active, notes, created_by
        ) values (
          v_req.employee_id, v_target_shift_id, v_eff_date, true,
          'معتمد بطلب تغيير وردية: ' || coalesce(v_req.title, ''), auth.uid()
        );

        update public.attendance_daily
        set shift_id = v_target_shift_id, updated_at = now()
        where employee_id = v_req.employee_id and work_date = v_eff_date;
      end if;
    end;
  end if;

  -- ب) مأمورية / قافلة / فاندي
  if v_req.request_type in ('mission', 'convoy', 'fundraising') then
    insert into public.mission_executions (request_id, employee_id, status, started_at)
    values (v_req.id, v_req.employee_id, 'in_progress', coalesce(v_req.created_at, now()))
    on conflict (request_id) do update
      set status = case when public.mission_executions.status = 'completed' then 'completed' else 'in_progress' end,
          started_at = coalesce(public.mission_executions.started_at, v_req.created_at, now()),
          updated_at = now();
  end if;

  -- ج) تصحيح البصمة (attendance_correction):
  if v_req.request_type = 'attendance_correction' then
    v_correction_id := nullif(v_req.payload->>'correctionId', '')::uuid;
    if v_correction_id is not null then
      begin
        perform public.decide_attendance_correction(v_correction_id, 'approved', p_comment);
      exception when others then
        update public.attendance_corrections
        set status = 'approved',
            reviewed_by = auth.uid(),
            reviewed_at = now(),
            review_notes = coalesce(p_comment, 'معتمد تلقائياً مع الطلب')
        where id = v_correction_id;
      end;
    end if;
  end if;

  perform public.notify_employee(
    v_req.employee_id,
    'تمت الموافقة على طلبك بنجاح',
    coalesce(v_req.title, '') || case when p_comment is not null then ' — ' || p_comment else '' end,
    'request', 'normal', 'request', v_req.id,
    jsonb_build_object('status', 'approved', 'decision', 'approve', 'requestId', v_req.id)
  );

  return v_req;
end;
$$;

revoke all on function public.decide_request(uuid, text, text) from public, anon;
grant execute on function public.decide_request(uuid, text, text) to authenticated;
comment on function public.decide_request(uuid, text, text) is
  '0673: تصحيح أخطاء أسماء الأعمدة في request_steps وقيد requests_workflow_status_check لضمان عمل اعتماد الطلبات بسلاسة.';


-- ─── 2) دالة التثبيت والاعتماد الفوري للوردية adopt_my_work_shift ─────────────
create or replace function public.adopt_my_work_shift(p_shift_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_shift public.shifts%rowtype;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  select * into v_shift from public.shifts where id = p_shift_id and is_active = true;
  if not found then
    raise exception 'فترة العمل المحددة غير موجودة أو غير مفعلة' using errcode = '22023';
  end if;

  -- 1) إنهاء أي تعيين وردية نشط سابق
  update public.shift_assignments
  set is_active = false,
      effective_to = least(coalesce(effective_to, v_today), v_today),
      updated_at = now()
  where employee_id = v_me and is_active = true;

  -- 2) إسناد الوردية المختارة فوراً للموظف
  insert into public.shift_assignments (
    employee_id, shift_id, effective_from, is_active, notes, created_by
  ) values (
    v_me, p_shift_id, v_today, true,
    'اعتماد وتثبيت فوري بطلب الموظف عند البصمة', auth.uid()
  );

  -- 3) تحديث سجل attendance_daily لليوم فوراً إن وجد
  update public.attendance_daily
  set shift_id = p_shift_id,
      updated_at = now()
  where employee_id = v_me and work_date = v_today;

  -- 4) اعتماد وإغلاق أي طلب تغيير وردية معلق للموظف
  update public.requests
  set status = 'approved',
      workflow_status = 'completed',
      decided_at = now(),
      decided_by = v_me,
      updated_at = now()
  where employee_id = v_me
    and request_type = 'shift_change'
    and status = 'pending';

  return jsonb_build_object(
    'ok', true,
    'shiftId', v_shift.id,
    'shiftName', v_shift.name_ar,
    'startTime', v_shift.start_time,
    'endTime', v_shift.end_time
  );
end;
$$;

revoke all on function public.adopt_my_work_shift(uuid) from public, anon;
grant execute on function public.adopt_my_work_shift(uuid) to authenticated;
comment on function public.adopt_my_work_shift(uuid) is
  '0673: تثبيت واعتماد فترة العمل للموظف فورياً دون اشتراط موافقة المدير المباشر.';


-- ─── 3) تحديث record_attendance_local_biometric لحساب الإضافي وإلغاء متأخر ──
create or replace function public.record_attendance_local_biometric(
  p_employee_id uuid,
  p_event_type text,
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy_meters double precision,
  p_is_mock boolean default false
)
returns uuid
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_event_id uuid;
  v_assignment public.shift_assignments%rowtype;
  v_geofence public.geofences%rowtype;
  v_shift public.shifts%rowtype;
  v_roster_shift_id uuid;
  v_roster_geofence_id uuid;
  v_now timestamptz := now();
  v_tz text;
  v_local_time time;
  v_work_date date;
  v_distance numeric(12,2);
  v_late integer := 0;
  v_first_check_in timestamptz;
  v_last_check_out timestamptz;
  v_last_event_type text;
  v_crosses_midnight boolean := false;
  v_period_start timestamptz;
  v_period_end timestamptz;
  v_prev_at timestamptz;
  v_prev_lat double precision;
  v_prev_lon double precision;
  v_gap_seconds numeric;
  v_travel double precision;
  v_impossible_speed constant double precision := 55.5;
  v_max_accuracy constant double precision := 100.0;
  v_requires_review boolean := false;
  v_notes text := '';
  v_calc_work_minutes integer := 0;
  v_calc_overtime_minutes integer := 0;
  v_calc_status text := 'present';
begin
  if p_employee_id is null then
    raise exception 'employee_id_required' using errcode = '22023';
  end if;
  if p_event_type not in ('CHECK_IN', 'CHECK_OUT') then
    raise exception 'invalid_event_type' using errcode = '22023';
  end if;
  if p_latitude is null or p_longitude is null or p_accuracy_meters is null then
    raise exception 'location_required' using errcode = '22023';
  end if;
  if p_is_mock then
    raise exception 'mock_location_forbidden' using errcode = '22023';
  end if;

  select s.timezone into v_tz
  from public.attendance_settings s
  where s.singleton_key;
  v_tz := coalesce(v_tz, 'Africa/Cairo');

  v_local_time := (v_now at time zone v_tz)::time;
  v_work_date  := (v_now at time zone v_tz)::date;

  select rd.shift_id, rd.geofence_id
    into v_roster_shift_id, v_roster_geofence_id
  from public.roster_days rd
  join public.work_rosters wr on wr.id = rd.roster_id and wr.status = 'published'
  where rd.employee_id = p_employee_id
    and rd.work_date = v_work_date
  limit 1;

  select sa.* into v_assignment
  from public.shift_assignments sa
  where sa.employee_id = p_employee_id
    and sa.is_active = true
    and sa.effective_from <= v_work_date
    and (sa.effective_to is null or sa.effective_to >= v_work_date)
  order by sa.effective_from desc
  limit 1;

  if coalesce(v_roster_shift_id, v_assignment.shift_id) is not null then
    select * into v_shift from public.shifts
    where id = coalesce(v_roster_shift_id, v_assignment.shift_id);
  end if;

  if v_crosses_midnight and v_shift.id is not null then
    v_period_start := (v_work_date + v_shift.start_time) at time zone v_tz;
    v_period_end   := ((v_work_date + 1) + v_shift.end_time) at time zone v_tz;
  else
    v_period_start := v_work_date::timestamp at time zone v_tz;
    v_period_end   := (v_work_date + 1)::timestamp at time zone v_tz;
  end if;

  if exists (
    select 1 from public.attendance_daily
    where employee_id = p_employee_id
      and work_date = v_work_date
      and is_finalized = true
  ) then
    raise exception 'attendance_period_finalized' using errcode = '55000';
  end if;

  select ae.event_at, ae.latitude, ae.longitude
    into v_prev_at, v_prev_lat, v_prev_lon
  from public.attendance_events ae
  where ae.employee_id = p_employee_id
    and ae.latitude is not null and ae.longitude is not null
    and ae.event_at > v_now - interval '6 hours'
  order by ae.event_at desc
  limit 1;

  if v_prev_at is not null then
    v_gap_seconds := greatest(extract(epoch from (v_now - v_prev_at)), 1);
    v_travel := public.geo_distance_meters(
      p_latitude, p_longitude, v_prev_lat, v_prev_lon
    );
    if v_travel is not null and (v_travel / v_gap_seconds) > v_impossible_speed then
      v_requires_review := true;
      v_notes := v_notes || ',impossible_travel';
    end if;
  end if;

  -- استعلام آخر حدث حضور مع الـ fallback لسجل attendance_daily
  select ae.event_type into v_last_event_type
  from public.attendance_events ae
  where ae.employee_id = p_employee_id
    and ae.event_at >= v_period_start
    and ae.event_at < v_period_end
    and ae.status in ('accepted', 'adjusted')
  order by ae.event_at desc
  limit 1;

  if v_last_event_type is null then
    select case
      when ad.last_check_out is not null then 'CHECK_OUT'
      when ad.first_check_in is not null then 'CHECK_IN'
      else null
    end into v_last_event_type
    from public.attendance_daily ad
    where ad.employee_id = p_employee_id
      and ad.work_date = v_work_date;
  end if;

  if p_event_type = 'CHECK_OUT' and v_last_event_type is distinct from 'CHECK_IN' then
    raise exception 'attendance_check_in_required' using errcode = '22023';
  end if;
  if p_event_type = 'CHECK_IN' and v_last_event_type = 'CHECK_IN' then
    raise exception 'attendance_check_out_required' using errcode = '22023';
  end if;

  if v_roster_geofence_id is not null then
    select * into v_geofence from public.geofences
    where id = v_roster_geofence_id and is_active = true;
  elsif v_assignment.geofence_id is not null then
    select * into v_geofence from public.geofences
    where id = v_assignment.geofence_id and is_active = true;
  end if;

  if v_geofence.id is null then
    select * into v_geofence from public.geofences
    where is_active = true
    order by created_at
    limit 1;
  end if;

  if v_geofence.id is null then
    raise exception 'attendance_geofence_not_configured' using errcode = '55000';
  end if;

  v_distance := public.geo_distance_meters(
    p_latitude, p_longitude, v_geofence.latitude, v_geofence.longitude
  )::numeric(12,2);

  -- التحقق من النطاق الجغرافي مع استثناء الانصراف الميداني للمأموريات
  if v_distance > v_geofence.radius_meters then
    if p_event_type = 'CHECK_OUT' and (
      exists (
        select 1 from public.mission_executions me
         where me.employee_id = p_employee_id
           and me.status in ('in_progress', 'completed')
           and (me.started_at at time zone 'Africa/Cairo')::date = v_work_date
      ) or exists (
        select 1 from public.requests r
         where r.employee_id = p_employee_id
           and r.status in ('approved', 'pending')
           and r.request_type in ('mission', 'convoy', 'fundraising')
           and v_work_date between coalesce(public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'), r.created_at::date)
                               and coalesce(public.try_cast_date(r.payload->>'endDate'), public.try_cast_date(r.payload->>'end_date'), public.try_cast_date(r.payload->>'startDate'), r.created_at::date)
      )
    ) then
      v_notes := 'mission_field_checkout';
    else
      raise exception 'attendance_outside_complex' using errcode = '22023';
    end if;
  end if;

  if coalesce(v_geofence.max_accuracy, v_max_accuracy) is not null
     and p_accuracy_meters > coalesce(v_geofence.max_accuracy, v_max_accuracy) then
    raise exception 'attendance_location_accuracy_too_low' using errcode = '22023';
  end if;

  -- حساب التأخير عند تسجيل أول حضور
  if p_event_type = 'CHECK_IN' and not exists (
    select 1 from public.attendance_events ae_prev
    where ae_prev.employee_id = p_employee_id
      and ae_prev.event_type = 'CHECK_IN'
      and ae_prev.status in ('accepted', 'adjusted')
      and ae_prev.event_at >= v_period_start
      and ae_prev.event_at < v_period_end
  ) then
    begin
      v_late := public.attendance_policy_late_minutes(p_employee_id, v_work_date, v_now, v_shift.id);
    exception when others then
      v_late := 0;
    end;
  end if;

  -- إدراج حدث الحضور/الانصراف
  insert into public.attendance_events (
    employee_id, shift_assignment_id, geofence_id, event_type, event_at,
    latitude, longitude, accuracy_meters, distance_meters, status,
    late_minutes, requires_review, verification_status,
    passkey_credential_id, biometric_method, selfie_path, server_verified,
    is_mock_location, notes, source, created_by
  ) values (
    p_employee_id, v_assignment.id, v_geofence.id, p_event_type, v_now,
    p_latitude, p_longitude, p_accuracy_meters, v_distance,
    case when v_requires_review then 'flagged' else 'accepted' end,
    v_late, v_requires_review, 'biometric_verified',
    null, 'fingerprint', null, true, false,
    v_notes, 'mobile', null
  ) returning id into v_event_id;

  -- تجميع بيانات الحضور اليومي في attendance_daily
  select min(event_at) filter (where event_type = 'CHECK_IN'),
         max(event_at) filter (where event_type = 'CHECK_OUT')
    into v_first_check_in, v_last_check_out
  from public.attendance_events
  where employee_id = p_employee_id
    and event_at >= v_period_start
    and event_at < v_period_end
    and status in ('accepted', 'adjusted');

  v_calc_work_minutes := case
    when v_first_check_in is not null and v_last_check_out is not null
    then greatest(0, floor(extract(epoch from (v_last_check_out - v_first_check_in)) / 60)::integer)
    else 0 end;

  v_calc_overtime_minutes := case
    when v_calc_work_minutes > 480 then v_calc_work_minutes - 480
    else 0 end;

  v_calc_status := case
    when v_first_check_in is null then 'partial'
    -- إذا أتم 8 ساعات عمل تختفي كلمة متأخر فوراً ويصبح حاضر:
    when v_calc_work_minutes >= 480 then 'present'
    when v_late > 0 then 'late'
    else 'present'
  end;

  insert into public.attendance_daily (
    employee_id, work_date, shift_id, first_check_in, last_check_out,
    work_minutes, late_minutes, overtime_minutes, status, is_finalized, created_by
  ) values (
    p_employee_id, v_work_date, coalesce(v_roster_shift_id, v_assignment.shift_id, public.match_flexible_shift(v_first_check_in)),
    v_first_check_in, v_last_check_out,
    v_calc_work_minutes,
    v_late,
    v_calc_overtime_minutes,
    v_calc_status,
    false, null
  )
  on conflict on constraint attendance_daily_uq do update set
    shift_id = coalesce(excluded.shift_id, attendance_daily.shift_id),
    first_check_in = coalesce(excluded.first_check_in, attendance_daily.first_check_in),
    last_check_out = coalesce(excluded.last_check_out, attendance_daily.last_check_out),
    work_minutes = excluded.work_minutes,
    overtime_minutes = excluded.overtime_minutes,
    late_minutes = greatest(attendance_daily.late_minutes, excluded.late_minutes),
    status = case
      when attendance_daily.status in ('on_leave', 'holiday', 'weekend')
        then attendance_daily.status
      when excluded.first_check_in is null then 'partial'
      -- إذا استوفى 8 ساعات عمل (480 دقيقة) تختفي صفة التأخير فوراً ويتحول إلى حاضر:
      when excluded.work_minutes >= 480 then 'present'
      when greatest(attendance_daily.late_minutes, excluded.late_minutes) > 0 then 'late'
      else 'present'
    end,
    updated_at = now();

  -- عند تسجيل الانصراف: إغلاق أي مأمورية جارية لليوم تلقائياً
  if p_event_type = 'CHECK_OUT' then
    update public.mission_executions
       set status = 'completed',
           ended_at = coalesce(ended_at, v_now),
           actual_minutes = greatest(1, round(extract(epoch from (v_now - started_at)) / 60)::integer),
           report = coalesce(report, 'تم تسجيل الانصراف وتوثيق إنهاء المأمورية بنجاح'),
           updated_at = v_now
     where employee_id = p_employee_id
       and status = 'in_progress'
       and (started_at at time zone 'Africa/Cairo')::date = v_work_date;
  end if;

  return v_event_id;
end;
$function$;

revoke all on function public.record_attendance_local_biometric(uuid, text, double precision, double precision, double precision, boolean) from public, anon;
grant execute on function public.record_attendance_local_biometric(uuid, text, double precision, double precision, double precision, boolean) to service_role;
comment on function public.record_attendance_local_biometric is
  '0673: تسجيل الحضور البيومتري مع تحويل الحالة تلقائياً إلى حاضر عند إتمام 8 ساعات وحساب الوقت الإضافي بدقة.';


-- ─── 4) تحديث get_my_attendance_state لإرجاع workMinutes و overtimeMinutes ──
create or replace function public.get_my_attendance_state(
  p_installation_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me                    uuid;
  v_today                 date := (now() at time zone 'Africa/Cairo')::date;
  v_is_split              boolean := false;
  v_hash                  text;
  v_last                  record;
  v_check_in_count        integer := 0;
  v_today_check_in        timestamptz;
  v_today_check_out       timestamptz;
  v_shift_end             timestamptz;
  v_local_device_status   text := 'not_registered';
  v_today_status          text;
  v_suggested             text;
  v_passkeys              integer;
  v_local_devices         integer;
  v_current_device_active boolean := false;
  v_current_device_status text;
  v_mission               jsonb := null;
  v_m_id                  uuid;
  v_m_type                text;
  v_m_start_time          text;
  v_m_exec                text;
  v_m_started             timestamptz;
  v_m_ended               timestamptz;
  v_cutoff                time;
  v_m_auto                boolean;
  v_work_minutes          integer := 0;
  v_overtime_minutes      integer := 0;
begin
  v_me := public.current_employee_id();

  if v_me is null then
    return jsonb_build_object(
      'attendanceRequired', false,
      'selfPunchEnabled', false,
      'canPunch', false,
      'reason', 'no_employee_linked'
    );
  end if;

  if public.is_employee_attendance_exempt(v_me) then
    return jsonb_build_object(
      'attendanceRequired', false,
      'selfPunchEnabled', false,
      'canPunch', false,
      'reason', 'executive_exempt'
    );
  end if;

  v_is_split := coalesce(public.is_employee_split_shift(v_me), false);

  select count(*) into v_local_devices
  from public.employee_devices ed
  where ed.employee_id = v_me
    and ed.user_id = auth.uid()
    and ed.status = 'active';

  if coalesce(v_local_devices, 0) = 0 then
    select count(*) into v_local_devices
    from public.managed_devices md
    where md.user_id = auth.uid()
      and md.employee_id = v_me
      and md.platform in ('android', 'ios')
      and md.status = 'active';
  end if;

  if p_installation_id is not null and trim(p_installation_id) <> '' then
    v_hash := encode(digest(trim(p_installation_id), 'sha256'), 'hex');

    if exists (
      select 1 from public.employee_devices ed
      where ed.employee_id = v_me
        and ed.user_id = auth.uid()
        and ed.device_identifier_hash = v_hash
        and ed.status = 'active'
    ) or exists (
      select 1 from public.managed_devices md
      where md.installation_id = trim(p_installation_id)
        and md.user_id = auth.uid()
        and md.employee_id = v_me
        and md.platform in ('android', 'ios')
        and md.status = 'active'
    ) then
      select ed.status into v_current_device_status
      from public.employee_devices ed
      where ed.employee_id = v_me
        and ed.user_id = auth.uid()
        and ed.device_identifier_hash = v_hash
      order by ed.created_at desc
      limit 1;

      if v_current_device_status = 'active' then
        v_current_device_active := true;
      end if;
    else
      select md.status into v_current_device_status
      from public.managed_devices md
      where md.installation_id = trim(p_installation_id)
        and md.user_id = auth.uid()
        and md.employee_id = v_me
      limit 1;

      if v_current_device_status is null then
        v_current_device_status := 'not_registered';
      end if;
    end if;
  end if;

  if v_local_devices > 0 then
    v_local_device_status := 'active';
  elsif v_current_device_status is not null then
    v_local_device_status := v_current_device_status;
  else
    perform 1 from public.employee_devices ed
    where ed.employee_id = v_me and ed.user_id = auth.uid() and ed.status = 'pending'
    limit 1;
    if found then
      v_local_device_status := 'pending';
    else
      perform 1 from public.managed_devices md
      where md.user_id = auth.uid() and md.employee_id = v_me
        and md.platform in ('android', 'ios')
        and md.status = 'pending'
      limit 1;
      if found then
        v_local_device_status := 'pending';
      end if;
    end if;
  end if;

  select count(*) into v_passkeys
  from public.passkey_credentials p
  where p.employee_id = v_me and p.user_id = auth.uid()
    and p.status = 'active' and p.trusted;

  select * into v_last from public.attendance_events
  where employee_id = v_me
    and (event_at at time zone 'Africa/Cairo')::date = v_today
    and status in ('accepted', 'adjusted')
  order by event_at desc limit 1;

  select status, work_minutes, overtime_minutes
    into v_today_status, v_work_minutes, v_overtime_minutes
  from public.attendance_daily
  where employee_id = v_me and work_date = v_today;

  select count(*) into v_check_in_count
  from public.attendance_events
  where employee_id = v_me
    and (event_at at time zone 'Africa/Cairo')::date = v_today
    and event_type = 'CHECK_IN'
    and status in ('accepted', 'adjusted');

  select event_at into v_today_check_in
  from public.attendance_events
  where employee_id = v_me
    and (event_at at time zone 'Africa/Cairo')::date = v_today
    and event_type = 'CHECK_IN'
    and status in ('accepted', 'adjusted')
  order by event_at asc limit 1;

  select event_at into v_today_check_out
  from public.attendance_events
  where employee_id = v_me
    and (event_at at time zone 'Africa/Cairo')::date = v_today
    and event_type = 'CHECK_OUT'
    and status in ('accepted', 'adjusted')
  order by event_at desc limit 1;

  if v_today_check_in is null then
    select d.first_check_in into v_today_check_in
      from public.attendance_daily d
     where d.employee_id = v_me and d.work_date = v_today;
  end if;

  if v_today_check_out is null then
    select d.last_check_out into v_today_check_out
      from public.attendance_daily d
     where d.employee_id = v_me and d.work_date = v_today;
  end if;

  -- حساب دقائق العمل الحية والوقت الإضافي
  if v_today_check_in is not null and v_today_check_out is not null then
    v_work_minutes := greatest(coalesce(v_work_minutes, 0), floor(extract(epoch from (v_today_check_out - v_today_check_in)) / 60)::integer);
  elsif v_today_check_in is not null and v_today_check_out is null then
    v_work_minutes := greatest(coalesce(v_work_minutes, 0), floor(extract(epoch from (now() - v_today_check_in)) / 60)::integer);
  end if;

  if v_work_minutes > 480 then
    v_overtime_minutes := v_work_minutes - 480;
  else
    v_overtime_minutes := coalesce(v_overtime_minutes, 0);
  end if;

  -- إذا استوفى الموظف 8 ساعات عمل تختفي كلمة متأخر فوراً ويصبح حاضراً
  if v_work_minutes >= 480 and v_today_status = 'late' then
    v_today_status := 'present';
  end if;

  -- فحص المأموريات والأنشطة اليوم
  select coalesce(s.shift_end_time, time '18:00') into v_cutoff
    from public.attendance_settings s where s.singleton_key;
  v_cutoff := coalesce(v_cutoff, time '18:00');

  select r.id, r.request_type, nullif(r.payload->>'startTime',''),
         coalesce(x.exec_status, case when r.status = 'approved' then 'approved' else 'pending' end),
         x.started_at, x.ended_at
    into v_m_id, v_m_type, v_m_start_time, v_m_exec, v_m_started, v_m_ended
    from public.requests r
    left join lateral (
      select m.status as exec_status, m.started_at, m.ended_at
        from public.mission_executions m
       where m.request_id = r.id
       order by m.created_at desc
       limit 1
    ) x on true
   where r.employee_id = v_me
     and r.status in ('approved', 'pending')
     and r.request_type in ('mission','convoy','fundraising')
     and v_today between coalesce(public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'), r.created_at::date)
                     and coalesce(public.try_cast_date(r.payload->>'endDate'), public.try_cast_date(r.payload->>'end_date'), public.try_cast_date(r.payload->>'startDate'), r.created_at::date)
   order by case when r.status = 'approved' then 1 else 2 end,
            x.started_at desc nulls last, r.created_at desc
   limit 1;

  if v_m_id is not null then
    v_m_auto := v_m_ended is not null
                and (v_m_ended at time zone 'Africa/Cairo')::time >= v_cutoff;

    if v_today_check_in is null and v_m_started is not null then
      v_today_check_in := v_m_started;
    end if;
    if v_today_check_out is null and v_m_ended is not null then
      v_today_check_out := v_m_ended;
    end if;

    v_mission := jsonb_build_object(
      'requestId', v_m_id,
      'type', v_m_type,
      'startTime', v_m_start_time,
      'execStatus', v_m_exec,
      'startedAt', v_m_started,
      'endedAt', v_m_ended,
      'autoCheckout', coalesce(v_m_auto, false)
    );
  end if;

  -- حسم الإجراء المقترح (suggestedAction)
  if v_today_check_out is not null and (not v_is_split or v_check_in_count >= 2) then
    v_suggested := 'DAY_COMPLETED';
  elsif v_today_check_out is not null and v_is_split and v_check_in_count < 2 then
    v_suggested := 'CHECK_IN';
  elsif v_today_check_in is not null or (v_last.id is not null and v_last.event_type = 'CHECK_IN') then
    v_suggested := 'CHECK_OUT';
  elsif v_m_id is not null and v_m_exec in ('approved', 'pending') and v_last.id is null and v_today_check_in is null then
    v_suggested := 'MISSION_START';
  else
    v_suggested := 'CHECK_IN';
  end if;

  if v_today_status is null or v_today_status = '' then
    if v_m_id is not null and v_m_exec in ('approved', 'in_progress', 'completed') then
      v_today_status := case v_m_type
        when 'convoy' then 'convoy'
        when 'fundraising' then 'fundraising'
        when 'mission' then 'mission'
        else 'mission'
      end;
    elsif exists (
      select 1 from public.requests r
      where r.employee_id = v_me
        and r.status = 'approved'
        and r.request_type = 'leave'
        and v_today between coalesce(public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'), r.created_at::date)
                        and coalesce(public.try_cast_date(r.payload->>'endDate'), public.try_cast_date(r.payload->>'end_date'), public.try_cast_date(r.payload->>'startDate'), r.created_at::date)
    ) then
      v_today_status := 'on_leave';
    elsif v_today_check_in is not null or v_last.id is not null then
      if v_work_minutes >= 480 then
        v_today_status := 'present';
      elsif coalesce(v_last.status, '') = 'late' or coalesce(v_last.late_minutes, 0) > 0 then
        v_today_status := 'late';
      else
        v_today_status := 'present';
      end if;
    elsif extract(dow from v_today) = 5 then
      v_today_status := 'weekend';
    elsif exists (select 1 from public.public_holidays where holiday_date = v_today) then
      v_today_status := 'holiday';
    elsif (now() at time zone 'Africa/Cairo')::time > '12:00:00'::time then
      v_today_status := 'absent';
    else
      v_today_status := 'not_recorded';
    end if;
  end if;

  select (v_today::text || ' ' || coalesce(s.shift_end_time, time '17:00')::text)::timestamptz
  into v_shift_end
  from public.attendance_settings s where s.singleton_key;

  return jsonb_build_object(
    'attendanceRequired', true,
    'selfPunchEnabled', true,
    'canPunch', true,
    'todayStatus', v_today_status,
    'workMinutes', coalesce(v_work_minutes, 0),
    'overtimeMinutes', coalesce(v_overtime_minutes, 0),
    'lastEventType', v_last.event_type,
    'lastEventAt', v_last.event_at,
    'lastEventStatus', v_last.status,
    'suggestedAction', v_suggested,
    'hasPasskeys', v_passkeys > 0,
    'passkeysCount', v_passkeys,
    'hasActiveLocalDevice', coalesce(v_local_devices, 0) > 0,
    'activeLocalDevicesCount', coalesce(v_local_devices, 0),
    'currentDeviceActive', v_current_device_active,
    'currentDeviceStatus', v_current_device_status,
    'localDeviceStatus', v_local_device_status,
    'todayCheckInAt', v_today_check_in,
    'todayCheckOutAt', v_today_check_out,
    'shiftEndTime', v_shift_end,
    'isSplitShift', v_is_split,
    'checkInCount', v_check_in_count,
    'missionToday', v_mission
  );
end;
$$;

revoke all on function public.get_my_attendance_state(text) from public, anon;
grant execute on function public.get_my_attendance_state(text) to authenticated;
comment on function public.get_my_attendance_state(text) is
  '0673: إرجاع الحالة مع workMinutes و overtimeMinutes وتحديث الحالة لحظياً إلى حاضر عند إتمام 8 ساعات.';

-- ─── 5) تسوية سجلات الحضور السابقة التي أتمت 8 ساعات ─────────────────────────
update public.attendance_daily
set status = 'present',
    overtime_minutes = greatest(0, work_minutes - 480),
    updated_at = now()
where work_minutes >= 480 and status = 'late';

commit;
