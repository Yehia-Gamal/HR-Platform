-- ===========================================================================
-- 0727: Business Hours SLA Engine, Dynamic Shift Coverage & Anti-Overnight Escalation
-- ===========================================================================
-- 1) calculate_business_deadline:
--    - حساب المهل بالساعات التشغيلية الرسمية (9:00 ص إلى 6:00 م) بتوقيت القاهرة
--    - استبعاد عطلة الجمعة تلقائياً
--    - عدم احتساب ساعات الليل، وبدء العداد من الساعة 9:00 ص لليوم التالي عند التقديم ليلاً
-- 2) _submit_request_for:
--    - استبدال مهلة الـ 5 دقائق الخاطئة لمرؤوسي المدير التنفيذي بمهلة تشغيلية عادلة (12 ساعة عمل)
--    - ضبط مهل خطوات الطلب تلقائياً بواسطة calculate_business_deadline
-- 3) process_request_sla:
--    - منع التصعيد التلقائي في ساعات الليل المتأخرة (بين 8 م و 8:30 ص) أو يوم الجمعة
--    - عند تصعيد الطلب لمدير التشغيل 1 (أبو عمار)، منحه مهلة تشغيلية كاملة (24 ساعة عمل)
--    - إزالة عبارة "ساعتان" الثابتة في سجل الإجراءات
-- 4) تغطية الورديات لكافة الموظفين (26 موظفاً):
--    - إسناد وردية العيادات (SHIFT_CLINIC_3_11) لطاقم التمريض والاستقبال بالعيادات
--    - إسناد وردية الدوام الأساسي (OFFICIAL) لباقي موظفي الحركة والتشغيل والإدارة
-- 5) تصحيح المهل للطلبات المعلقة الحالية لرفع إنذار "متأخر منذ 12 ساعة"
-- ===========================================================================

begin;

-- ─── 1) دالة حساب المهلة بساعات العمل الرسمية (Africa/Cairo) ───
create or replace function public.calculate_business_deadline(
  p_start_at timestamptz,
  p_hours integer default 24
)
returns timestamptz
language plpgsql
immutable
as $$
declare
  v_tz text := 'Africa/Cairo';
  v_cur timestamp := (coalesce(p_start_at, now()) at time zone v_tz);
  v_rem_hours integer := greatest(1, coalesce(p_hours, 24));
  v_dow integer;
  v_work_start time := '09:00:00'::time;
  v_work_end time := '18:00:00'::time;
  v_avail_today numeric;
begin
  loop
    v_dow := extract(dow from v_cur)::integer; -- 0=Sun, 1=Mon, ..., 5=Fri, 6=Sat

    -- إذا كان يوم الجمعة (5)، الانتقال لصباح السبت 9:00 ص
    if v_dow = 5 then
      v_cur := (v_cur::date + 1) + v_work_start;
      continue;
    end if;

    -- إذا كان الوقت قبل بداية الدوام (قبل 9:00 ص)، ضبطه على 9:00 ص
    if v_cur::time < v_work_start then
      v_cur := v_cur::date + v_work_start;
    end if;

    -- إذا كان الوقت بعد نهاية الدوام (بعد 6:00 م)، الانتقال لصباح اليوم التالي
    if v_cur::time >= v_work_end then
      v_cur := (v_cur::date + 1) + v_work_start;
      continue;
    end if;

    -- الساعات المتبقية في دوام اليوم الحالي
    v_avail_today := extract(epoch from (v_work_end - v_cur::time)) / 3600.0;

    if v_rem_hours <= v_avail_today then
      v_cur := v_cur + (v_rem_hours || ' hours')::interval;
      exit;
    else
      v_rem_hours := v_rem_hours - ceil(v_avail_today)::integer;
      if v_rem_hours <= 0 then
        v_cur := v_cur::date + v_work_end;
        exit;
      end if;
      v_cur := (v_cur::date + 1) + v_work_start;
    end if;
  end loop;

  return v_cur at time zone v_tz;
end;
$$;

-- ─── 2) تحديث دالة _submit_request_for بالمهل التشغيلية العادلة ───
create or replace function public._submit_request_for(
  p_employee_id uuid,
  p_request_type text,
  p_workflow_definition_id uuid default null::uuid,
  p_manager_employee_id uuid default null::uuid,
  p_title text default null::text,
  p_reason text default null::text,
  p_payload jsonb default '{}'::jsonb
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me               uuid := public.current_employee_id();
  v_def              public.workflow_definitions;
  v_due              timestamptz;
  v_esc              timestamptz;
  v_row              public.requests;
  v_first_approver   uuid;
  v_label            text;
  v_title_approver   text;
  v_is_clinic        boolean := false;
  v_is_mgr_executive boolean := false;
  v_emp_name         text;
  v_two_names        text;
  v_req_label        text;
  v_ops_emp          uuid;
  v_sla_hours        integer := 24;
begin
  if p_employee_id is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  if p_request_type not in (
    'leave','mission','convoy','fundraising',
    'late_permit','early_permit','attendance_correction',
    'attendance_permit','shift_change','generic'
  ) then
    raise exception 'invalid request_type: %', p_request_type using errcode = '22023';
  end if;

  select e.full_name_ar into v_emp_name from public.employees e where e.id = p_employee_id;
  v_two_names := trim(split_part(coalesce(v_emp_name, ''), ' ', 1) || ' ' || split_part(coalesce(v_emp_name, ''), ' ', 2));
  if v_two_names is null or v_two_names = '' then
    v_two_names := coalesce(nullif(v_emp_name, ''), 'موظف');
  end if;
  v_req_label := public.request_type_label(p_request_type);

  -- فحص طاقم العيادات المقيد
  v_is_clinic := public.is_clinic_staff_restricted_from_field(p_employee_id);

  -- تحديد المدير المعتمد
  if v_is_clinic then
    if p_manager_employee_id is null or p_manager_employee_id not in (
         '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid,
         'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid
       ) then
      p_manager_employee_id := coalesce(
        public.resolve_request_approver(p_employee_id),
        '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid
      );
    end if;
  elsif p_manager_employee_id is null or p_manager_employee_id = p_employee_id then
    p_manager_employee_id := public.resolve_request_approver(p_employee_id);
  end if;

  -- فحص إذا كان المدير المباشر هو المدير التنفيذي
  v_is_mgr_executive := (
    p_manager_employee_id = '7b0740fa-66ba-4616-8674-3dbd8e14109e'::uuid
    or public.is_employee_executive(p_manager_employee_id)
  );

  -- التعرف التلقائي لتعريف سير العمل
  if p_workflow_definition_id is not null then
    select * into v_def from public.workflow_definitions where id = p_workflow_definition_id;
  else
    if v_is_clinic then
      select * into v_def from public.workflow_definitions
        where code like 'medical_%' and request_type = p_request_type and is_active = true
        order by version desc limit 1;
    end if;

    if v_def.id is null and public.is_employee_isolated(p_employee_id) then
      select * into v_def from public.workflow_definitions
        where code = 'medical_leave_v1' and request_type = p_request_type and is_active = true
        order by version desc limit 1;
    end if;

    if v_def.id is null then
      select * into v_def from public.workflow_definitions
        where request_type = p_request_type and is_default = true and is_active = true
        order by version desc limit 1;
    end if;
  end if;

  -- حساب المهلة التشغيلية العادلة بساعات العمل الرسمية
  if v_def.id is not null then
    v_sla_hours := case
      when v_is_mgr_executive then 12
      else coalesce(v_def.default_due_hours, 24)
    end;
    v_due := public.calculate_business_deadline(now(), v_sla_hours);
    if v_def.auto_escalate and not v_is_clinic then
      v_esc := v_due;
    end if;
  else
    v_sla_hours := case when v_is_mgr_executive then 12 else 48 end;
    v_due := public.calculate_business_deadline(now(), v_sla_hours);
    v_esc := case when v_is_mgr_executive then v_due else null end;
  end if;

  insert into public.requests (
    request_type, employee_id, manager_employee_id, workflow_definition_id,
    status, workflow_status, title, reason, decision_due_at, escalation_deadline,
    payload, created_by
  ) values (
    p_request_type, p_employee_id, p_manager_employee_id, v_def.id,
    'pending', 'submitted', p_title, p_reason, v_due, v_esc,
    coalesce(p_payload, '{}'::jsonb), auth.uid()
  )
  returning * into v_row;

  if v_def.id is not null then
    insert into public.request_steps (
      request_id, workflow_step_id, step_order, name_ar, step_type,
      assignee_employee_id, assignee_role_slug, status, sla_hours,
      due_at, escalation_deadline, created_by
    )
    select
      v_row.id,
      ws.id,
      ws.step_order,
      ws.name_ar,
      ws.step_type,
      case
        when ws.assignee_type = 'manager' then p_manager_employee_id
        when ws.assignee_type = 'specific_employee' then ws.specific_employee_id
        else null
      end,
      case
        when ws.assignee_type = 'role' then ws.role_slug
        else null
      end,
      case when ws.step_order = 1 then 'active' else 'pending' end,
      ws.sla_hours,
      case
        when ws.step_order = 1 then
          public.calculate_business_deadline(now(), case when v_is_mgr_executive then 12 else coalesce(ws.sla_hours, 24) end)
        else null
      end,
      case
        when ws.step_order = 1 and coalesce(ws.auto_escalate, false) and not v_is_clinic then
          public.calculate_business_deadline(now(), case when v_is_mgr_executive then 12 else coalesce(ws.sla_hours, 24) end)
        else null
      end,
      auth.uid()
    from public.workflow_steps ws
    where ws.definition_id = v_def.id
    order by ws.step_order;

    update public.requests
    set current_step_id = (
      select rs.id from public.request_steps rs
      where rs.request_id = v_row.id and rs.step_order = 1
      limit 1
    )
    where id = v_row.id;
  end if;

  insert into public.workflow_instances (
    request_id, workflow_definition_id, status, current_step_order, created_by
  ) values (
    v_row.id, v_def.id, 'running', 1, auth.uid()
  );

  insert into public.request_actions (
    request_id, actor_employee_id, action, from_status, to_status, comment
  ) values (
    v_row.id, p_employee_id, 'submit', null, 'pending',
    case when p_reason is not null and length(trim(p_reason)) > 0 then trim(p_reason) else p_title end
  );

  -- إشعار صاحب الاعتماد الأول
  select assignee_employee_id into v_first_approver
  from public.request_steps
  where request_id = v_row.id and step_order = 1;

  if v_first_approver is null then
    v_first_approver := p_manager_employee_id;
  end if;

  if v_first_approver is not null and v_first_approver <> p_employee_id then
    v_label := coalesce(v_row.title, v_req_label);
    v_title_approver := 'طلب ' || v_req_label || ' جديد — ' || v_two_names;

    perform public.notify_employee(
      v_first_approver,
      v_title_approver,
      'قدّم ' || v_two_names || ' طلب ' || v_req_label || ' (' || v_label || ') يحتاج إلى موافقتك.',
      'request',
      case when p_request_type in ('leave','mission') then 'high' else 'normal' end,
      'request',
      v_row.id,
      jsonb_build_object(
        'requestId', v_row.id,
        'requestNumber', v_row.request_number,
        'requestType', p_request_type,
        'employeeId', p_employee_id,
        'employeeName', v_emp_name,
        'workflowStep', 1,
        'channel', 'request_submitted',
        'deepLink', '/requests/' || v_row.id
      )
    );
  end if;

  return v_row;
end;
$$;

-- ─── 3) تحديث دالة process_request_sla بحماية الليل وحساب المهل الواقعية ───
create or replace function public.process_request_sla(p_limit integer default 200)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count      integer := 0;
  v_row        record;
  v_next       record;
  v_ops_emp    uuid;
  v_target     uuid;
  v_role       text;
  v_today      date := (now() at time zone 'Africa/Cairo')::date;
  v_now_time   time := (now() at time zone 'Africa/Cairo')::time;
  v_dow        integer := extract(dow from (now() at time zone 'Africa/Cairo'))::integer;
  v_absent     boolean;
  v_due        boolean;
  v_delegate   uuid;
  v_del_name   text;
begin
  if auth.role() <> 'service_role' and not public.current_is_full_access() then
    raise exception 'PERMISSION_DENIED' using errcode = '42501';
  end if;

  -- 🛑 حماية الليل والعطلات: عدم تنفيذ التصعيد التلقائي بعد الساعة 8 مساءً أو قبل 8:30 صباحاً أو يوم الجمعة
  if v_dow = 5 or v_now_time < '08:30:00'::time or v_now_time >= '20:00:00'::time then
    return 0;
  end if;

  v_ops_emp := public.first_active_employee_for_role('operations-manager-1');

  for v_row in
    select
      rs.id          as step_id,
      rs.request_id,
      rs.step_order,
      rs.status      as step_status,
      rs.assignee_employee_id,
      rs.escalation_deadline,
      r.employee_id,
      r.manager_employee_id,
      r.title,
      r.request_type,
      r.workflow_definition_id
    from public.request_steps rs
    join public.requests r on r.id = rs.request_id
    where r.status = 'pending'
      and (
        (rs.status in ('active', 'escalated')
         and rs.escalation_deadline is not null
         and rs.escalation_deadline < now())
        or (rs.status = 'active' and rs.step_order = 1
            and public.employee_on_leave(coalesce(rs.assignee_employee_id, r.manager_employee_id), v_today))
      )
    order by rs.escalation_deadline nulls first
    limit greatest(1, least(coalesce(p_limit, 200), 2000))
    for update of rs skip locked
  loop
    v_due := v_row.escalation_deadline is not null and v_row.escalation_deadline < now();
    v_absent := not v_due and v_row.step_order = 1 and v_row.step_status = 'active';

    -- استثناء طاقم العيادات: يبقى كل شيء بالعيادات حصراً لدى مصطفى أحمد
    if public.is_clinic_team_member(v_row.employee_id)
       or v_row.manager_employee_id = '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'
       or exists (
         select 1 from public.workflow_definitions wd
         where wd.id = v_row.workflow_definition_id
           and wd.code like 'medical_%'
       ) then
      if not v_due then
        continue;
      end if;

      if v_row.manager_employee_id is not null then
        perform public.notify_employee(
          v_row.manager_employee_id,
          'تذكير: طلب من طاقم العيادات بانتظار قرارك',
          coalesce(v_row.title, '') || ' — يحتاج قرارك كمدير مباشر.',
          'request', 'normal', 'request', v_row.request_id,
          jsonb_build_object(
            'escalation', 'clinic_reminder',
            'deepLink', '/requests/' || v_row.request_id
          )
        );
      end if;

      update public.request_steps
        set escalation_deadline = public.calculate_business_deadline(now(), 24),
            updated_at = now()
      where id = v_row.step_id;

      continue;
    end if;

    -- تفضيل البديل الساري للمدير عند الغياب قبل التصعيد
    if v_absent and v_row.step_order = 1 then
      v_delegate := public.get_active_approval_delegate(
        coalesce(v_row.assignee_employee_id, v_row.manager_employee_id),
        v_today
      );

      if v_delegate is not null and v_delegate <> v_row.employee_id then
        select full_name_ar into v_del_name from public.employees where id = v_delegate;

        update public.request_steps
          set assignee_employee_id = v_delegate,
              escalation_deadline  = public.calculate_business_deadline(now(), 12),
              updated_at           = now()
        where id = v_row.step_id;

        insert into public.request_actions(
          request_id, actor_employee_id, action, from_status, to_status, comment, metadata
        ) values (
          v_row.request_id, null, 'delegate', 'pending', 'pending',
          'تحويل تلقائي للبديل المفوض (' || coalesce(v_del_name, 'البديل') || ') — المدير الأصيل في إجازة اليوم',
          jsonb_build_object('delegateEmployeeId', v_delegate, 'reason', 'manager_on_leave_delegated')
        );

        perform public.notify_employee(
          v_delegate,
          'طلب محوَّل إليك كبديل مفوض',
          coalesce(v_row.title, '') || ' — المدير الأصيل في إجازة، الطلب محول لك للبت فيه.',
          'request', 'high', 'request', v_row.request_id,
          jsonb_build_object(
            'escalation', 'delegated_on_leave',
            'deepLink', '/requests/' || v_row.request_id
          )
        );

        v_count := v_count + 1;
        continue;
      end if;
    end if;

    -- الخطوة النهائية (أبو عمار أو أي مرحلة >= 2): لا ترقية أبعد
    if v_row.step_order >= 2 then
      if v_ops_emp is not null then
        update public.request_steps
          set assignee_employee_id = coalesce(assignee_employee_id, v_ops_emp),
              assignee_role_slug   = 'operations-manager-1',
              updated_at = now()
        where id = v_row.step_id;

        perform public.notify_employee(
          v_ops_emp,
          'تذكير: طلب لم يُبتَّ فيه بعد',
          coalesce(v_row.title, '') || ' — يحتاج قرارك الآن. الطلب محوَّل لك كقرار نهائي.',
          'request', 'high', 'request', v_row.request_id,
          jsonb_build_object(
            'escalation', 'final_reminder',
            'deepLink', '/requests/' || v_row.request_id
          )
        );
      end if;

      update public.request_steps
        set escalation_deadline = public.calculate_business_deadline(now(), 24), updated_at = now()
      where id = v_row.step_id;
      continue;
    end if;

    -- الخطوة 1 (المدير المباشر): تصعيد إلى الخطوة 2 (مدير التشغيل 1)
    if v_row.step_status = 'escalated' then
      update public.request_steps
        set escalation_deadline = null, updated_at = now()
      where id = v_row.step_id;
      continue;
    end if;

    select * into v_next
    from public.request_steps
    where request_id = v_row.request_id
      and step_order = v_row.step_order + 1
    limit 1;

    update public.request_steps
      set status = 'escalated',
          escalated_at = coalesce(escalated_at, now()),
          escalation_deadline = null,
          updated_at = now()
    where id = v_row.step_id;

    if v_next.id is not null then
      v_target := v_ops_emp;
      v_role   := 'operations-manager-1';

      update public.request_steps
        set status = 'active',
            assignee_employee_id = coalesce(v_target, assignee_employee_id),
            assignee_role_slug = coalesce(v_role, assignee_role_slug),
            due_at = public.calculate_business_deadline(now(), 24),
            escalation_deadline = public.calculate_business_deadline(now(), 24),
            updated_at = now()
      where id = v_next.id;

      update public.workflow_instances
        set current_step_order = v_next.step_order, updated_at = now()
      where request_id = v_row.request_id and status = 'running';

      update public.requests
        set workflow_status = 'awaiting_operator',
            escalated_at = coalesce(escalated_at, now()),
            decision_due_at = public.calculate_business_deadline(now(), 24),
            updated_at = now()
      where id = v_row.request_id;

      insert into public.request_actions(
        request_id, actor_employee_id, action, from_status, to_status, comment, metadata
      ) values (
        v_row.request_id, null, 'escalate', 'pending', 'pending',
        case when v_absent then 'تصعيد تلقائي — المدير المباشر في إجازة اليوم'
             else 'تصعيد تلقائي — تجاوز مهلة البت للمدير المباشر' end,
        jsonb_build_object('tier', v_next.step_order, 'targetRole', v_role,
                           'reason', case when v_absent then 'manager_on_leave' else 'timeout' end)
      );

      if v_target is not null then
        perform public.notify_employee(
          v_target,
          'طلب محوَّل إليك — مدير التشغيل 1',
          coalesce(v_row.title, '') || ' — يمكنك البت فيه الآن.',
          'request', 'high', 'request', v_row.request_id,
          jsonb_build_object(
            'escalation', case when v_absent then 'manager_absent' else 'timeout_tier1' end,
            'deepLink', '/requests/' || v_row.request_id
          )
        );
      end if;

      v_count := v_count + 1;
    end if;
  end loop;

  return v_count;
end;
$$;

-- ─── 4) إسناد الورديات لكافة الموظفين الـ 26 غير المسندين ───
-- أ) طاقم العيادات الطبية (وردية العيادات المسائية SHIFT_CLINIC_3_11):
insert into public.shift_assignments (
  employee_id, shift_id, effective_from, is_active, notes, created_at, updated_at
)
select e.id, '3905c122-db6c-4c82-bd3a-6c07f701f47c'::uuid, '2026-01-01'::date, true,
       'تثبيت وردية العيادات الطبية المسائية (3 ع – 11 م) بقرار إداري 0727', now(), now()
from public.employees e
where e.is_active = true
  and e.id in (
    'b97d9e90-d815-42f7-b192-255dd34129b8'::uuid, -- سميرة سعيد
    '9ab2509b-4000-4933-8610-d67dbdcc4737'::uuid, -- ساميه أشرف
    '7cd1c291-c9bf-4cbc-82c7-3eae58ecd67d'::uuid, -- سمر احمد
    '040c1fe5-1b2b-4f74-95a8-abea297432f5'::uuid, -- نجلاء عادل
    'eb5fd675-ce45-4209-aea7-a0dfb2bb2a87'::uuid, -- رحاب مجدي
    '59a727ba-6710-405a-ab0d-5efe719275d5'::uuid  -- شروق عبد العليم
  )
  and not exists (
    select 1 from public.shift_assignments sa
    where sa.employee_id = e.id and sa.is_active = true
  );

-- ب) باقي الموظفين غير المسندين (وردية الدوام الأساسي OFFICIAL 10 ص – 6 م):
insert into public.shift_assignments (
  employee_id, shift_id, effective_from, is_active, notes, created_at, updated_at
)
select e.id, 'a8026263-c235-4a55-8d10-d31e8dde9f32'::uuid, '2026-01-01'::date, true,
       'تثبيت وردية الدوام الأساسي (10 ص – 6 م) بقرار إداري 0727', now(), now()
from public.employees e
where e.is_active = true
  and not exists (
    select 1 from public.shift_assignments sa
    where sa.employee_id = e.id and sa.is_active = true
  );

-- ─── 5) تصحيح المهل للطلبات المعلقة الحالية لرفع إنذار "متأخر منذ 12 ساعة" ───
update public.request_steps
   set due_at = public.calculate_business_deadline(now(), 24),
       escalation_deadline = public.calculate_business_deadline(now(), 24),
       updated_at = now()
 where status = 'active'
   and due_at < now();

update public.requests
   set decision_due_at = public.calculate_business_deadline(now(), 24),
       updated_at = now()
 where status = 'pending'
   and decision_due_at < now();

commit;

