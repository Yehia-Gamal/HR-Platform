-- =====================================================================
-- 0632: دعم اختيار واعتماد وتغيير فترات العمل (الورديات المرنة) واحتساب التأخيرات
--
--  بناءً على طلب المستخدم:
--  1) إضافة إمكانية عرض واختيار فترات العمل الثلاث:
--     • الوردية الصباحية: 09:00 ص إلى 05:00 م (سماح 15 دقيقة حتى 09:15 ص).
--     • الدوام الأساسي (الافتراضي العام): 10:00 ص إلى 06:00 م (سماح 15 دقيقة حتى 10:15 ص).
--     • الوردية المسائية: 11:00 ص إلى 07:00 م (سماح 15 دقيقة حتى 11:15 ص).
--  2) عرض الفترة الأساسية المعتمدة للموظف المقبولة من الإدارة.
--  3) احتساب التأخيرات والخصومات الفردية بناءً على الوردية المعتمدة في shift_assignments.
--  4) إمكانية تقديم طلب تغيير فترة العمل بسهولة وسلاسة واعتمادها من الإدارة.
-- =====================================================================

begin;

-- ─── 1) تحديث CHECK Constraints لجدول requests و workflow_definitions ───────

alter table public.requests drop constraint if exists requests_request_type_check;
alter table public.requests
  add constraint requests_request_type_check
    check (request_type in (
      'leave',
      'mission',
      'convoy',
      'fundraising',
      'late_permit',
      'early_permit',
      'attendance_correction',
      'shift_change'
    ));

alter table public.workflow_definitions drop constraint if exists workflow_definitions_request_type_check;
alter table public.workflow_definitions
  add constraint workflow_definitions_request_type_check
    check (request_type in (
      'leave',
      'mission',
      'convoy',
      'fundraising',
      'late_permit',
      'early_permit',
      'attendance_correction',
      'attendance_permit',
      'generic',
      'shift_change'
    ));

-- ─── 2) تهيئة سير عمل اعتماد تغيير فترة العمل إن لم يكن موجوداً ─────────────

insert into public.workflow_definitions (
  code, name_ar, name_en, request_type, is_active, is_default, description, default_due_hours
)
values (
  'WORKFLOW_SHIFT_CHANGE',
  'سير اعتماد تغيير فترة العمل',
  'Shift Change Approval Workflow',
  'shift_change',
  true,
  true,
  'سير عمل طلب تغيير الوردية الأساسية للموظف واعتمادها من الإدارة',
  2
)
on conflict (code, version) do update set
  is_active = true,
  is_default = true,
  default_due_hours = 2;

insert into public.workflow_steps (
  definition_id, step_order, name_ar, name_en, step_type, approver_type, approver_permission, is_active
)
select id, 1, 'اعتماد مدير الإدارة / الموارد البشرية', 'Manager / HR Approval', 'approval', 'direct_manager', 'attendance.record.manage', true
from public.workflow_definitions
where code = 'WORKFLOW_SHIFT_CHANGE'
  and not exists (
    select 1 from public.workflow_steps where definition_id = public.workflow_definitions.id
  );

-- ─── 3) تحديث دالة احتساب دقائق التأخير لتعطي الأولوية للوردية المعتمدة للموظف ──

create or replace function public.attendance_policy_late_minutes(
  p_employee_id uuid,
  p_work_date date,
  p_check_in timestamptz,
  p_shift_id uuid default null
)
returns integer
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_shift public.shifts%rowtype;
  v_diff integer;
  v_target_shift_id uuid;
begin
  if p_check_in is null or public.is_lateness_excused(p_employee_id, p_work_date) then
    return 0;
  end if;

  v_target_shift_id := p_shift_id;

  -- 1) إذا لم تُمرر الوردية، نبحث عن الوردية المعتمدة للموظف في shift_assignments
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

  -- 2) إذا لم توجد وردية مسندة، تُطابق الوردية المرنة بحسب وقت الحضور
  if v_target_shift_id is null then
    v_target_shift_id := public.match_flexible_shift(p_check_in);
  end if;

  select * into v_shift from public.shifts where id = v_target_shift_id;
  if v_shift.id is null or v_shift.start_time is null then
    return 0;
  end if;

  v_diff := floor(extract(epoch from (
    p_check_in - ((p_work_date + v_shift.start_time)::timestamp at time zone 'Africa/Cairo')
  )) / 60)::integer;

  return case when v_diff > coalesce(v_shift.grace_in_minutes, 0) then least(greatest(0, v_diff), 120) else 0 end;
end;
$fn$;

comment on function public.attendance_policy_late_minutes(uuid, date, timestamptz, uuid) is
  '0632: احتساب دقائق التأخير مع إعطاء الأولوية للوردية المعتمدة للموظف في shift_assignments ثم المطابقة المرنة.';

revoke all on function public.attendance_policy_late_minutes(uuid, date, timestamptz, uuid) from public, anon;
grant execute on function public.attendance_policy_late_minutes(uuid, date, timestamptz, uuid) to service_role, authenticated;

-- ─── 4) دالة قراءة معلومات فترة العمل الحالية والورديات المتاحة والطلب المعلق ──

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
    v_current_shift := jsonb_build_object(
      'id', v_assign.shift_id,
      'code', v_assign.code,
      'name', v_assign.name,
      'nameEn', v_assign.name_en,
      'startTime', to_char(v_assign.start_time, 'HH24:MI:SS'),
      'endTime', to_char(v_assign.end_time, 'HH24:MI:SS'),
      'graceInMinutes', v_assign.grace_in_minutes,
      'isAssigned', true,
      'assignmentId', v_assign.assignment_id,
      'effectiveFrom', v_assign.effective_from,
      'status', 'approved'
    );
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

    v_current_shift := jsonb_build_object(
      'id', v_default_shift.id,
      'code', coalesce(v_default_shift.code, 'OFFICIAL'),
      'name', coalesce(v_default_shift.name, 'الدوام الأساسي (10 ص – 6 م)'),
      'nameEn', v_default_shift.name_en,
      'startTime', to_char(coalesce(v_default_shift.start_time, '10:00:00'::time), 'HH24:MI:SS'),
      'endTime', to_char(coalesce(v_default_shift.end_time, '18:00:00'::time), 'HH24:MI:SS'),
      'graceInMinutes', coalesce(v_default_shift.grace_in_minutes, 15),
      'isAssigned', false,
      'assignmentId', null,
      'effectiveFrom', v_today,
      'status', 'default'
    );
  end if;

  -- 2) قائمة الورديات المرنة المتاحة للاختيار (مرتبة حسب موعد البداية)
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

  -- 3) فحص أي طلب معلق لتغيير فترة العمل
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
    'pendingRequest', v_pending
  );
end;
$$;

revoke all on function public.get_my_work_shift_info() from public, anon;
grant execute on function public.get_my_work_shift_info() to authenticated;
comment on function public.get_my_work_shift_info() is
  '0632: جلب بيانات الوردية المعتمدة للموظف والورديات المتاحة وأي طلب تغيير قيد المراجعة.';

-- ─── 5) دالة تقديم طلب تغيير فترة العمل من الموظف ───────────────────────────

create or replace function public.request_my_shift_change(
  p_shift_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me            uuid := public.current_employee_id();
  v_today         date := (now() at time zone 'Africa/Cairo')::date;
  v_shift         public.shifts%rowtype;
  v_current_id    uuid;
  v_existing_id   uuid;
  v_req_id        uuid;
  v_title         text;
  v_reason        text;
  v_manager_id    uuid;
  v_wf_def_id     uuid;
  v_auto_approve  boolean := false;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  if p_shift_id is null then
    raise exception 'يجب تحديد الوردية المراد الانتقال إليها' using errcode = '22023';
  end if;

  select * into v_shift from public.shifts where id = p_shift_id and is_active;
  if v_shift.id is null then
    raise exception 'الوردية المطلوبة غير موجودة أو غير نشطة' using errcode = 'P0002';
  end if;

  -- فحص الوردية الحالية للموظف
  select sa.shift_id into v_current_id
    from public.shift_assignments sa
   where sa.employee_id = v_me
     and sa.is_active = true
     and sa.effective_from <= v_today
     and (sa.effective_to is null or sa.effective_to >= v_today)
   order by sa.effective_from desc
   limit 1;

  if v_current_id is null then
    select s.id into v_current_id
      from public.shifts s
     where s.code = 'OFFICIAL' and s.is_active
     limit 1;
  end if;

  if v_current_id = p_shift_id then
    raise exception 'هذه الوردية هي ورديتك المعتمدة الحالية بالفعل' using errcode = '22023';
  end if;

  -- فحص وجود طلب معلق مسبقاً
  select r.id into v_existing_id
    from public.requests r
   where r.employee_id = v_me
     and r.request_type = 'shift_change'
     and r.status = 'pending'
   limit 1;

  if v_existing_id is not null then
    raise exception 'لديك بالفعل طلب تغيير فترة عمل قيد المراجعة والاعتماد' using errcode = '23505';
  end if;

  v_title := 'طلب تغيير فترة العمل إلى ' || v_shift.name;
  v_reason := coalesce(nullif(trim(p_reason), ''), 'طلب الموظف اختيار فترة عمل أساسية تناسب جدول الدوام');

  -- جلب المدير المباشر (employees.manager_id غير موجود — السلسلة في manager_relations)
  select mr.manager_employee_id into v_manager_id
    from public.manager_relations mr
   where mr.employee_id = v_me
     and mr.relation_type = 'primary'
     and mr.effective_from <= v_today
     and (mr.effective_to is null or mr.effective_to >= v_today)
   order by mr.effective_from desc
   limit 1;

  -- جلب سير العمل الافتراضي
  select id into v_wf_def_id
    from public.workflow_definitions
   where request_type = 'shift_change' and is_active and is_default
   limit 1;

  -- هل يملك صلاحية الاعتماد الفوري (إدارة عليا أو HR)؟
  if public.current_is_full_access()
     or public.current_has_active_role(array['executive','executive-director','general-manager','hr-manager','admin','super-admin']) then
    v_auto_approve := true;
  end if;

  insert into public.requests (
    request_type, employee_id, manager_employee_id, workflow_definition_id,
    title, reason, status, workflow_status, payload, decided_at, decided_by
  ) values (
    'shift_change',
    v_me,
    v_manager_id,
    v_wf_def_id,
    v_title,
    v_reason,
    case when v_auto_approve then 'approved' else 'pending' end,
    case when v_auto_approve then 'completed' else 'submitted' end,
    jsonb_build_object(
      'shiftId', v_shift.id,
      'shiftCode', v_shift.code,
      'shiftName', v_shift.name,
      'effectiveFrom', v_today,
      'reason', v_reason
    ),
    case when v_auto_approve then now() else null end,
    case when v_auto_approve then v_me else null end
  )
  returning id into v_req_id;

  -- إذا كان اعتماداً فورياً، نطبق الإسناد مباشرة
  if v_auto_approve then
    update public.shift_assignments
       set is_active = false,
           effective_to = least(coalesce(effective_to, v_today), v_today),
           updated_at = now()
     where employee_id = v_me
       and is_active = true;

    insert into public.shift_assignments (
      employee_id, shift_id, effective_from, is_active, notes, created_by
    ) values (
      v_me, v_shift.id, v_today, true,
      'اعتماد فوري بطلب صاحب الصلاحية: ' || v_title,
      auth.uid()
    );
  else
    -- إدراج نسخة سير العمل والخطوات لتبدأ دورة الاعتماد
    declare
      v_wf_inst_id uuid;
    begin
      insert into public.workflow_instances (
        definition_id, request_id, status, started_at
      ) values (
        v_wf_def_id, v_req_id, 'running', now()
      ) returning id into v_wf_inst_id;

      insert into public.request_steps (
        request_id, step_order, name_ar, step_type, assignee_employee_id, status
      ) values (
        v_req_id, 1, 'اعتماد مدير الإدارة / الموارد البشرية', 'approval',
        v_manager_id, 'active'
      );
    exception when others then
      -- إذا لم تتوفر جداول سير العمل، يبقى الطلب معلقاً بصورة قياسية
      null;
    end;
  end if;

  return jsonb_build_object(
    'requestId', v_req_id,
    'status', case when v_auto_approve then 'approved' else 'pending' end,
    'message', case
      when v_auto_approve then 'تم اعتماد وتفعيل فترة العمل الجديدة بنجاح.'
      else 'تم إرسال طلب تغيير فترة العمل للمراجعة والاعتماد من الإدارة.'
    end
  );
end;
$$;

revoke all on function public.request_my_shift_change(uuid, text) from public, anon;
grant execute on function public.request_my_shift_change(uuid, text) to authenticated;
comment on function public.request_my_shift_change(uuid, text) is
  '0632: تقديم طلب تغيير الوردية الأساسية من الموظف وإحالته للاعتماد أو تفعيله فورياً إن كان صاحب صلاحية.';

-- ─── 6) تحديث decide_request لدعم اعتماد طلبات تغيير فترات العمل ────────────

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
  v_is_direct_mgr := (v_req.manager_employee_id = v_me) or exists (
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
    or (v_step.id is not null and v_step.assignee_employee_id = v_me)
    or public.current_has_active_role(array['admin','super-admin'])
    or (v_is_operations
        and (
          v_current_step >= 2
          or coalesce(v_step.escalation_deadline, v_req.escalation_deadline) < now()
          or v_req.workflow_status in ('escalated', 'awaiting_operator')
          or v_req.request_type in ('mission','convoy','fundraising')
        ));

  if not v_authorized then
    raise exception 'not authorized for the active workflow step (step: %, role required)',
      v_current_step using errcode = '42501';
  end if;

  -- تحديد دور الفاعل للسجل
  v_actor_role := case
    when public.current_is_full_access() and not v_is_direct_mgr then 'admin'
    when v_is_exec then 'executive'
    when v_is_direct_mgr then 'direct_manager'
    when v_is_hr then 'hr'
    when v_is_operations then 'operations'
    else 'authorized'
  end;

  v_final_status := case p_decision
    when 'approve' then 'approved'
    when 'return'  then 'returned'
    else 'rejected'
  end;

  if v_step.id is not null then
    update public.request_steps
      set status = case p_decision when 'approve' then 'approved' else 'rejected' end,
          acted_at = now(), acted_by = v_me,
          comment = p_comment, updated_at = now()
    where id = v_step.id;
  end if;

  update public.request_steps
    set status = 'skipped', updated_at = now()
  where request_id = p_request_id
    and status in ('pending','active','escalated')
    and id is distinct from v_step.id;

  update public.workflow_instances
    set status = 'completed', completed_at = now(), updated_at = now()
  where request_id = p_request_id and status = 'running';

  update public.requests
    set status = v_final_status,
        workflow_status = 'completed',
        decided_at = now(), decided_by = v_me, updated_at = now()
  where id = p_request_id
  returning * into v_req;

  -- ── إذا كانت مأمورية أو قافلة أو فاندي وتم اعتمادها → تثبيت تنفيذ المأمورية
  if v_final_status = 'approved' and v_req.request_type in ('mission', 'convoy', 'fundraising') then
    insert into public.mission_executions(request_id, employee_id, status, started_at)
    values (v_req.id, v_req.employee_id, 'in_progress', coalesce(v_req.created_at, now()))
    on conflict (request_id) do update
      set status = case when public.mission_executions.status = 'completed' then 'completed' else 'in_progress' end,
          started_at = coalesce(public.mission_executions.started_at, v_req.created_at, now()),
          updated_at = now();
  end if;

  if v_final_status = 'rejected' and v_req.request_type in ('mission', 'convoy', 'fundraising') then
    update public.mission_executions
       set status = 'cancelled',
           updated_at = now()
     where request_id = p_request_id
       and status = 'in_progress';
  end if;

  -- ── 0632: إذا كان تغيير فترة عمل وتم اعتماده → تحديث shift_assignments فوراً
  if v_final_status = 'approved' and v_req.request_type = 'shift_change' then
    declare
      v_target_shift_id uuid := nullif(v_req.payload->>'shiftId','')::uuid;
      v_eff_date date := coalesce(nullif(v_req.payload->>'effectiveFrom','')::date, (now() at time zone 'Africa/Cairo')::date);
    begin
      if v_target_shift_id is not null then
        update public.shift_assignments
           set is_active = false,
               effective_to = least(coalesce(effective_to, v_eff_date), v_eff_date),
               updated_at = now()
         where employee_id = v_req.employee_id
           and is_active = true;

        insert into public.shift_assignments(
          employee_id, shift_id, effective_from, is_active, notes, created_by
        ) values (
          v_req.employee_id, v_target_shift_id, v_eff_date, true,
          coalesce(v_req.reason, 'اعتماد تغيير الوردية الأساسية بطلب الموظف'),
          auth.uid()
        );
      end if;
    end;
  end if;

  -- ── إذا كان تصحيح حضور
  if v_final_status = 'approved' and v_req.request_type = 'attendance_correction' then
    v_correction_id := (v_req.payload->>'correctionId')::uuid;
    if v_correction_id is not null then
      begin
        perform public.decide_attendance_correction(v_correction_id, 'approved', p_comment);
      exception when others then
        raise notice 'decide_attendance_correction fallback: %', sqlerrm;
      end;
    end if;
  end if;

  if v_final_status = 'rejected' and v_req.request_type = 'attendance_correction' then
    v_correction_id := (v_req.payload->>'correctionId')::uuid;
    if v_correction_id is not null then
      begin
        perform public.decide_attendance_correction(v_correction_id, 'rejected', coalesce(p_comment, 'تم الرفض من سير العمل'));
      exception when others then
        raise notice 'decide_attendance_correction reject fallback: %', sqlerrm;
      end;
    end if;
  end if;

  insert into public.request_actions(
    request_id, request_step_id, actor_employee_id, action,
    from_status, to_status, comment, created_by
  ) values (
    p_request_id, v_step.id, v_me, p_decision,
    'pending', v_final_status, p_comment, auth.uid()
  );

  -- إشعار الموظف بالنتيجة
  perform public.notify_employee(
    v_req.employee_id,
    case v_req.status
      when 'approved' then 'تمت الموافقة على طلبك'
      when 'rejected' then 'تم رفض طلبك'
      else 'تم إعادة طلبك لتعديله'
    end,
    coalesce(v_req.title, '') ||
      case when p_comment is not null then E'\n' || p_comment else '' end,
    'request',
    case when v_req.status = 'approved' then 'normal' else 'high' end,
    'request', v_req.id,
    jsonb_build_object(
      'decision', p_decision,
      'request_type', v_req.request_type,
      'actorRole', v_actor_role,
      'deepLink', '/requests/' || v_req.id
    )
  );

  -- إشعار المدير التنفيذي (كامل الشاشة)
  v_exec_emp := public.first_active_employee_for_role('executive-director');
  if v_exec_emp is null then
    v_exec_emp := public.first_active_employee_for_role('executive');
  end if;
  if v_exec_emp is not null
     and v_exec_emp <> v_req.employee_id
     and v_exec_emp is distinct from v_me then
    perform public.notify_executive_fullscreen(
      'قرار طلب — ' || case v_req.status
        when 'approved' then 'موافقة'
        when 'rejected' then 'رفض'
        else 'إعادة طلب' end,
      coalesce(v_req.title, '') ||
        case when p_comment is not null then E'\n' || p_comment else '' end,
      'request',
      'request', v_req.id,
      '/requests/' || v_req.id,
      jsonb_build_object(
        'decision', p_decision,
        'request_type', v_req.request_type,
        'actorRole', v_actor_role
      )
    );
  end if;

  return v_req;
end;
$$;

revoke all on function public.decide_request(uuid, text, text) from public, anon;
grant execute on function public.decide_request(uuid, text, text) to authenticated;

-- ─── 7) دالة إدارية لإسناد فترة العمل مباشرة لموظف (Admin / HR) ────────────

create or replace function public.set_employee_shift_admin(
  p_employee_id uuid,
  p_shift_id uuid,
  p_effective_from date default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me            uuid := public.current_employee_id();
  v_eff_date      date := coalesce(p_effective_from, (now() at time zone 'Africa/Cairo')::date);
  v_shift         public.shifts%rowtype;
  v_assign_id     uuid;
begin
  if not (public.current_is_full_access()
          or public.has_any_permission(array['attendance.record.manage', 'payroll.run.manage'])
          or public.current_has_active_role(array['admin','super-admin','hr-manager','operations-manager'])) then
    raise exception 'غير مصرح لك بإسناد ورديات الموظفين' using errcode = '42501';
  end if;

  select * into v_shift from public.shifts where id = p_shift_id and is_active;
  if v_shift.id is null then
    raise exception 'الوردية غير موجودة أو غير نشطة' using errcode = 'P0002';
  end if;

  -- إيقاف أي إسناد نشط سابق
  update public.shift_assignments
     set is_active = false,
         effective_to = least(coalesce(effective_to, v_eff_date), v_eff_date),
         updated_at = now()
   where employee_id = p_employee_id
     and is_active = true;

  insert into public.shift_assignments (
    employee_id, shift_id, effective_from, is_active, notes, created_by
  ) values (
    p_employee_id, p_shift_id, v_eff_date, true,
    coalesce(p_notes, 'إسناد إداري مباشر للوردية: ' || v_shift.name),
    auth.uid()
  ) returning id into v_assign_id;

  return jsonb_build_object(
    'assignmentId', v_assign_id,
    'employeeId', p_employee_id,
    'shiftId', p_shift_id,
    'shiftName', v_shift.name,
    'effectiveFrom', v_eff_date,
    'success', true
  );
end;
$$;

revoke all on function public.set_employee_shift_admin(uuid, uuid, date, text) from public, anon;
grant execute on function public.set_employee_shift_admin(uuid, uuid, date, text) to authenticated;
comment on function public.set_employee_shift_admin(uuid, uuid, date, text) is
  '0632: إسناد فترة العمل مباشرة لموظف بواسطة مسؤولي الموارد البشرية أو الإدارة العليا.';

commit;
