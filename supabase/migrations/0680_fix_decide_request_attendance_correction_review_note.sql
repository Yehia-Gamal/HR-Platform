-- ==============================================================================
-- Migration 0680: إصلاح اعتماد طلبات الموظفين وتصحيح الحضور (review_note & work_minutes)
-- ==============================================================================
-- 1. إصلاح خطأ "عمود في قاعدة البيانات مفقود" (review_notes does not exist):
--    - العمود الصحيح في جدول attendance_corrections هو review_note وليس review_notes.
--    - حقل reviewed_by يربط بجدول employees(id) وليس auth.users(id).
-- 2. حماية قيد attendance_daily_work_chk (work_minutes >= 0):
--    - في trg_fn_calculate_daily_overtime، منع القيمة السالبة لدقائق العمل باستخدام greatest(0, ...).
-- 3. معالجة التوقيت المسائي لبصمة الانصراف:
--    - إذا كان وقت الانصراف المطلوب أقل من وقت الحضور لنفس اليوم (بسبب إدخاله بصيغة 12 ساعة)،
--      يتم احتسابه تلقائياً بالتوقيت المسائي الصحيح (+12 ساعة) لمنع تعارض الفارق الزمني.
-- 4. إتاحة اعتماد تصحيح البصمة للمدير المباشر والإدارة التنفيذية وHR بسلاسة.
-- ==============================================================================

begin;

-- ─── 1) trg_fn_calculate_daily_overtime: حماية دقائق العمل من القيم السالبة ────
create or replace function public.trg_fn_calculate_daily_overtime()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_req_mins integer := 480;
  v_shift_mins integer;
begin
  if new.first_check_in is not null and new.last_check_out is not null then
    if new.shift_id is not null then
      select round(extract(epoch from (s.end_time - s.start_time)) / 60)::integer
        into v_shift_mins
        from public.shifts s
       where s.id = new.shift_id;
      if v_shift_mins is not null and v_shift_mins > 0 then
        v_req_mins := v_shift_mins;
      end if;
    end if;

    -- حساب دقائق العمل الفعلية مع ضمان عدم وجود قيم سالبة
    if new.work_minutes is null or new.work_minutes = 0 then
      new.work_minutes := greatest(0, floor(extract(epoch from (date_trunc('minute', new.last_check_out) - date_trunc('minute', new.first_check_in))) / 60)::integer);
    end if;

    -- احتساب دقائق الوقت الإضافي
    if new.work_minutes > v_req_mins then
      new.overtime_minutes := new.work_minutes - v_req_mins;
    else
      new.overtime_minutes := 0;
    end if;
  end if;

  return new;
end;
$$;

-- ─── 2) دالة decide_attendance_correction: الصلاحيات وتحديث review_note ───────
create or replace function public.decide_attendance_correction(
  p_id uuid,
  p_decision text,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row public.attendance_corrections;
  v_me  uuid := public.current_employee_id();
  v_effective_checkout timestamptz;
begin
  select * into strict v_row from public.attendance_corrections where id = p_id for update;

  if not (
    auth.role() = 'service_role'
    or public.current_is_full_access()
    or public.current_has_active_role(array['admin','super-admin','executive','executive-director','hr-manager','operations-manager-1'])
    or (
      v_row.employee_id is distinct from v_me
      and (
        public.can_access_employee(v_row.employee_id, 'attendance.correction.review')
        or public.is_manager_of(v_me, v_row.employee_id)
        or exists (
          select 1 from public.requests r
          where (r.payload->>'correctionId')::uuid = v_row.id
            and (r.manager_employee_id = v_me or r.created_by = auth.uid())
        )
      )
    )
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if v_row.status <> 'pending' or p_decision not in ('approved','rejected') then
    raise exception 'INVALID_DECISION' using errcode = '22023';
  end if;

  if p_decision = 'rejected' and length(trim(coalesce(p_note, '')))<3 then
    raise exception 'REASON_REQUIRED' using errcode = '22023';
  end if;

  -- معالجة انصراف مساءً تم إدخاله كصباحاً (أقل من وقت الحضور)
  v_effective_checkout := v_row.requested_check_out;
  if v_effective_checkout is not null then
    declare
      v_cur_checkin timestamptz;
    begin
      select first_check_in into v_cur_checkin from public.attendance_daily
       where employee_id = v_row.employee_id and work_date = v_row.work_date;
      if v_cur_checkin is not null and v_effective_checkout < v_cur_checkin then
        if v_effective_checkout + interval '12 hours' > v_cur_checkin then
          v_effective_checkout := v_effective_checkout + interval '12 hours';
        end if;
      end if;
    end;
  end if;

  update public.attendance_corrections
  set status = p_decision,
      reviewed_by = v_me,
      reviewed_at = now(),
      review_note = p_note,
      requested_check_out = v_effective_checkout,
      updated_at = now()
  where id = p_id;

  if p_decision = 'approved' then
    insert into public.attendance_daily(
      employee_id, work_date, first_check_in, last_check_out, status, is_finalized, created_by
    ) values (
      v_row.employee_id, v_row.work_date, v_row.requested_check_in, v_effective_checkout,
      coalesce(v_row.requested_status, 'present'), false, auth.uid()
    )
    on conflict (employee_id, work_date) do update
      set first_check_in = coalesce(v_row.requested_check_in, attendance_daily.first_check_in),
          last_check_out = coalesce(v_effective_checkout, attendance_daily.last_check_out),
          status = coalesce(v_row.requested_status, 'present'),
          updated_at = now();
  end if;

  perform public.log_audit_event(
    'attendance.correction.' || p_decision, 'workflow',
    case when p_decision = 'approved' then 'notice' else 'warning' end,
    'attendance_corrections', p_id, 'قرار تصحيح حضور',
    p_note, jsonb_build_object('employeeId', v_row.employee_id, 'workDate', v_row.work_date)
  );

  perform public.notify_employee(
    v_row.employee_id,
    case p_decision when 'approved' then 'تم قبول تصحيح الحضور' else 'تم رفض تصحيح الحضور' end,
    format('تصحيح حضور بتاريخ %s%s', v_row.work_date, case when p_note is not null then E'\n' || p_note else '' end),
    'attendance', case p_decision when 'approved' then 'normal' else 'high' end,
    'attendance_corrections', p_id,
    jsonb_build_object('decision', p_decision, 'workDate', v_row.work_date)
  );
end;
$$;

revoke all on function public.decide_attendance_correction(uuid, text, text) from public, anon;
grant execute on function public.decide_attendance_correction(uuid, text, text) to authenticated;

-- ─── 3) دالة decide_request: تصحيح أسماء الأعمدة وربط المراجعة ────────────────
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

  v_current_step := coalesce(v_step.step_order, 0);

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

    -- تصحيح البصمة عند الرفض أو الإرجاع:
    if v_req.request_type = 'attendance_correction' then
      v_correction_id := nullif(v_req.payload->>'correctionId', '')::uuid;
      if v_correction_id is not null then
        update public.attendance_corrections
        set status = case when p_decision = 'reject' then 'rejected' else 'cancelled' end,
            reviewed_by = v_me,
            reviewed_at = now(),
            review_note = coalesce(p_comment, case when p_decision = 'reject' then 'مرفوض مع الطلب' else 'معاد للمراجعة' end),
            updated_at = now()
        where id = v_correction_id and status = 'pending';
      end if;
    end if;

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
      declare
        v_corr public.attendance_corrections%rowtype;
        v_eff_out timestamptz;
        v_cur_in timestamptz;
      begin
        select * into v_corr from public.attendance_corrections where id = v_correction_id for update;
        if found and v_corr.status = 'pending' then
          v_eff_out := v_corr.requested_check_out;
          if v_eff_out is not null then
            select first_check_in into v_cur_in from public.attendance_daily
             where employee_id = v_corr.employee_id and work_date = v_corr.work_date;
            if v_cur_in is not null and v_eff_out < v_cur_in then
              if v_eff_out + interval '12 hours' > v_cur_in then
                v_eff_out := v_eff_out + interval '12 hours';
              end if;
            end if;
          end if;

          update public.attendance_corrections
          set status = 'approved',
              reviewed_by = v_me,
              reviewed_at = now(),
              review_note = coalesce(p_comment, 'معتمد تلقائياً مع الطلب'),
              requested_check_out = coalesce(v_eff_out, requested_check_out),
              updated_at = now()
          where id = v_correction_id;

          insert into public.attendance_daily(
            employee_id, work_date, first_check_in, last_check_out, status, is_finalized, created_by
          ) values (
            v_corr.employee_id, v_corr.work_date, v_corr.requested_check_in, v_eff_out,
            coalesce(v_corr.requested_status, 'present'), false, auth.uid()
          )
          on conflict(employee_id, work_date) do update
            set first_check_in = coalesce(v_corr.requested_check_in, attendance_daily.first_check_in),
                last_check_out = coalesce(v_eff_out, attendance_daily.last_check_out),
                status = coalesce(v_corr.requested_status, 'present'),
                updated_at = now();

          perform public.log_audit_event(
            'attendance.correction.approved', 'workflow', 'notice',
            'attendance_corrections', v_correction_id, 'قرار تصحيح حضور معتمد بالطلب',
            p_comment, jsonb_build_object('employeeId', v_corr.employee_id, 'workDate', v_corr.work_date, 'requestId', v_req.id)
          );
        end if;
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
  '0680: تصحيح اسم عمود review_note وتأمين اعتماد تصحيح البصمة وحماية قيد work_minutes من القيم السالبة.';

commit;
