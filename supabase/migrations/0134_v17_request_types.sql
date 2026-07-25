-- 0134_v17_request_types.sql
-- V17 §8: محاذاة أنواع الطلبات + §1.2 توجيه طلبات التشغيل للمدير التنفيذي
-- ─────────────────────────────────────────────────────────────────────────────
-- التغييرات:
--   1) ترحيل بيانات: attendance_permit → late_permit/early_permit حسب permitKind
--   2) ترحيل بيانات: generic → attendance_correction
--   3) تحديث CHECK على request_type: 6 أنواع V17
--   4) إعادة كتابة submit_request مع أنواع V17
--   5) إعادة كتابة submit_my_request مع أنواع V17 (late_permit, early_permit, attendance_correction)
--   6) تحديث resolve_request_approver: توجيه طلبات التشغيل للمدير التنفيذي
-- ─────────────────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. ترحيل البيانات القائمة
-- ═══════════════════════════════════════════════════════════════════════════════

-- attendance_permit مع permitKind='early_departure' → early_permit
update public.requests
  set request_type = 'early_permit'
where request_type = 'attendance_permit'
  and payload->>'permitKind' = 'early_departure';

-- attendance_permit مع permitKind='late_arrival' أو أي قيمة أخرى → late_permit
update public.requests
  set request_type = 'late_permit'
where request_type = 'attendance_permit';

-- generic → attendance_correction
update public.requests
  set request_type = 'attendance_correction'
where request_type = 'generic';

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2. تحديث CHECK constraint — أنواع V17 الستة
-- ═══════════════════════════════════════════════════════════════════════════════

alter table public.requests drop constraint if exists requests_request_type_check;
alter table public.requests
  add constraint requests_request_type_check
    check(request_type in ('leave','mission','convoy','late_permit','early_permit','attendance_correction'));

-- تحديث workflow_definitions أيضاً إن كان لديها CHECK على request_type
alter table public.workflow_definitions drop constraint if exists workflow_definitions_request_type_check;
alter table public.workflow_definitions
  add constraint workflow_definitions_request_type_check
    check(request_type in ('leave','mission','convoy','late_permit','early_permit','attendance_correction'))
  not valid;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 3. إعادة كتابة resolve_request_approver — توجيه التشغيل للتنفيذي
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.resolve_request_approver(
  p_employee_id uuid,
  p_as_of date default (now() at time zone 'Africa/Cairo')::date
)
returns uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_mgr uuid;
  v_dept_id uuid;
  v_is_operations boolean := false;
  v_executive_employee_id uuid;
begin
  -- المدير المباشر (primary) من الهيكل الإداري
  select manager_employee_id into v_mgr
  from public.manager_relations
  where employee_id = p_employee_id
    and relation_type = 'primary'
    and effective_from <= p_as_of
    and (effective_to is null or effective_to >= p_as_of)
  order by effective_from desc
  limit 1;

  -- منع الموافقة الذاتية: لو صار المدير هو المُقدِّم نفسه، اصعد لمديره
  if v_mgr is not null and v_mgr = p_employee_id then
    select manager_employee_id into v_mgr
    from public.manager_relations
    where employee_id = p_employee_id
      and relation_type = 'primary'
      and manager_employee_id <> p_employee_id
      and effective_from <= p_as_of
      and (effective_to is null or effective_to >= p_as_of)
    order by effective_from desc
    limit 1;
  end if;

  -- V17 §1.2: توجيه طلبات التشغيل للمدير التنفيذي
  -- نتحقق هل الموظف تابع لإدارة تشغيل (slug يبدأ بـ operations)
  select e.department_id into v_dept_id
  from public.employees e
  where e.id = p_employee_id and e.is_active and not e.is_deleted;

  if v_dept_id is not null then
    -- تحقق من شجرة الإدارات: هل الإدارة أو أحد أسلافها هي "operations"
    select exists(
      with recursive dept_tree as (
        select d.id, d.slug, d.parent_id
        from public.departments d where d.id = v_dept_id
        union all
        select p.id, p.slug, p.parent_id
        from public.departments p
        join dept_tree dt on dt.parent_id = p.id
      )
      select 1 from dept_tree where slug like 'operations%'
    ) into v_is_operations;
  end if;

  if v_is_operations then
    -- ابحث عن موظف نشط بدور executive
    select e.id into v_executive_employee_id
    from public.employees e
    join public.role_assignments ra on ra.employee_id = e.id
      and ra.is_active = true
    join public.roles r on r.id = ra.role_id
    where r.slug = 'executive'
      and e.is_active and not e.is_deleted
      and e.id <> p_employee_id  -- لا يعتمد المدير التنفيذي طلبه لنفسه
    limit 1;

    if v_executive_employee_id is not null then
      v_mgr := v_executive_employee_id;
    end if;
  end if;

  return v_mgr;
end $$;

comment on function public.resolve_request_approver(uuid, date) is
  'V17 §1.2+§8: يحدد المدير المسؤول عن طلب الموظف — التشغيل يُوجَّه للمدير التنفيذي، مع منع الموافقة الذاتية.';

revoke execute on function public.resolve_request_approver(uuid, date) from public;
grant execute on function public.resolve_request_approver(uuid, date) to authenticated, service_role;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 4. إعادة كتابة submit_request — أنواع V17
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.submit_request(
  p_request_type          text,
  p_workflow_definition_id uuid    default null,
  p_manager_employee_id    uuid    default null,
  p_title                  text    default null,
  p_reason                 text    default null,
  p_payload                jsonb   default '{}'::jsonb
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me       uuid := public.current_employee_id();
  v_def      public.workflow_definitions;
  v_due      timestamptz;
  v_esc      timestamptz;
  v_row      public.requests;
begin
  if v_me is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;

  -- V17 §8: 6 أنواع طلبات رسمية بالضبط
  if p_request_type not in ('leave','mission','convoy','late_permit','early_permit','attendance_correction') then
    raise exception 'invalid request_type: %', p_request_type using errcode = '22023';
  end if;

  if p_manager_employee_id is not null and p_manager_employee_id = v_me then
    raise exception 'self-approval is not allowed (manager cannot be requester)' using errcode = '42501';
  end if;

  -- اختر التعريف الافتراضي إن لم يُمرَّر
  if p_workflow_definition_id is not null then
    select * into v_def from public.workflow_definitions where id = p_workflow_definition_id;
  else
    select * into v_def from public.workflow_definitions
      where request_type = p_request_type and is_default = true and is_active = true
      order by version desc limit 1;
  end if;

  if v_def.id is not null then
    v_due := now() + make_interval(hours => coalesce(v_def.default_due_hours, 48));
    if v_def.auto_escalate then
      v_esc := v_due;
    end if;
  else
    v_due := now() + interval '48 hours';
  end if;

  insert into public.requests (
    request_type, employee_id, manager_employee_id, workflow_definition_id,
    status, workflow_status, title, reason, decision_due_at, escalation_deadline,
    payload, created_by
  ) values (
    p_request_type, v_me, p_manager_employee_id, v_def.id,
    'pending', 'submitted', p_title, p_reason, v_due, v_esc,
    coalesce(p_payload, '{}'::jsonb), auth.uid()
  )
  returning * into v_row;

  -- إنشاء الخطوات الجارية من تعريف سير العمل (إن وُجد)
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
      case when ws.approver_type = 'specific_employee' then ws.approver_employee_id
           when ws.approver_type in ('direct_manager','department_manager') then p_manager_employee_id
           else null end,
      ws.approver_role_slug,
      case when ws.step_order = 1 then 'active' else 'pending' end,
      ws.sla_hours,
      case when ws.step_order = 1 then now() + make_interval(hours => coalesce(ws.sla_hours, 48)) end,
      case when ws.step_order = 1 and ws.escalate_after_hours is not null
           then now() + make_interval(hours => ws.escalate_after_hours) end,
      auth.uid()
    from public.workflow_steps ws
    where ws.definition_id = v_def.id and ws.is_active = true
    order by ws.step_order;

    insert into public.workflow_instances (
      definition_id, request_id, definition_version, status, current_step_order, created_by
    ) values (
      v_def.id, v_row.id, coalesce(v_def.version, 1), 'running', 1, auth.uid()
    );
  end if;

  -- سجل إجراء submit
  insert into public.request_actions (
    request_id, actor_employee_id, action, to_status, comment, created_by
  ) values (
    v_row.id, v_me, 'submit', 'pending', p_reason, auth.uid()
  );

  return v_row;
end;
$$;
comment on function public.submit_request(text, uuid, uuid, text, text, jsonb) is
  'V17 §8: إنشاء طلب موحّد — 6 أنواع رسمية، مع سير عمل وخطوات وتسجيل إجراء.';
revoke execute on function public.submit_request(text, uuid, uuid, text, text, jsonb) from public;
grant  execute on function public.submit_request(text, uuid, uuid, text, text, jsonb) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 5. إعادة كتابة submit_my_request — أنواع V17 مع أذونات التأخير والانصراف وتصحيح الحضور
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.submit_my_request(
  p_request_type text,
  p_title text,
  p_reason text,
  p_payload jsonb default '{}'::jsonb
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_manager uuid;
  v_row public.requests;
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_start_date date;
  v_end_date date;
  v_permit_date date;
  v_minutes integer;
  v_leave_type text;
  v_leave_type_id uuid;
  v_affects boolean;
  v_days numeric;
  v_substitute uuid;
  v_correction_date date;
  v_correction_type text;
  v_corrected_time text;
begin
  if v_me is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;

  -- V17 §8: 6 أنواع رسمية بالضبط
  if p_request_type not in ('leave','mission','convoy','late_permit','early_permit','attendance_correction') then
    raise exception 'invalid request type' using errcode = '22023';
  end if;

  if length(trim(coalesce(p_title,''))) < 3
     or length(trim(coalesce(p_reason,''))) < 3 then
    raise exception 'title and reason are required (min 3 chars)' using errcode = '22023';
  end if;

  begin
    case p_request_type
      -- ─── إجازة ──────────────────────────────────────────────────────────────
      when 'leave' then
        v_leave_type := v_payload->>'leaveType';
        -- توافق خلفي: emergency → casual
        if v_leave_type = 'emergency' then v_leave_type := 'casual'; end if;
        v_start_date := nullif(v_payload->>'startDate', '')::date;
        v_end_date := nullif(v_payload->>'endDate', '')::date;
        v_substitute := nullif(v_payload->>'substituteEmployeeId', '')::uuid;
        if v_leave_type not in ('annual','casual','sick','unpaid') then
          raise exception 'unsupported leave type' using errcode = '22023';
        end if;
        if v_start_date is null or v_end_date is null then
          raise exception 'leave start and end dates are required' using errcode = '22023';
        end if;
        if v_end_date < v_start_date then
          raise exception 'leave end date cannot precede start date' using errcode = '22023';
        end if;
        if v_start_date < v_today then
          raise exception 'retroactive leave requests are not allowed' using errcode = '22023';
        end if;
        select id, affects_balance into v_leave_type_id, v_affects
        from public.leave_types where code = v_leave_type and is_active = true;
        if v_leave_type_id is null then
          raise exception 'leave type is inactive or unknown: %', v_leave_type using errcode = '22023';
        end if;
        v_days := (v_end_date - v_start_date) + 1;
        v_payload := v_payload || jsonb_build_object(
          'leaveType', v_leave_type,
          'startDate', v_start_date,
          'endDate', v_end_date,
          'days', v_days,
          'immediate', (v_leave_type = 'casual'));

      -- ─── مأمورية / قافلة ────────────────────────────────────────────────────
      when 'mission', 'convoy' then
        v_start_date := nullif(v_payload->>'startDate', '')::date;
        v_end_date := nullif(v_payload->>'endDate', '')::date;
        if v_start_date is null or v_end_date is null then
          raise exception 'assignment start and end dates are required' using errcode = '22023';
        end if;
        if v_end_date < v_start_date then
          raise exception 'assignment end date cannot precede start date' using errcode = '22023';
        end if;
        if v_start_date < v_today then
          raise exception 'retroactive assignments are not allowed' using errcode = '22023';
        end if;
        if length(trim(coalesce(v_payload->>'location', ''))) < 2 then
          raise exception 'assignment location is required' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'startDate', v_start_date,
          'endDate', v_end_date,
          'location', trim(v_payload->>'location'),
          'days', (v_end_date - v_start_date) + 1);

      -- ─── إذن تأخير (V17 §8 — كان attendance_permit + late_arrival) ─────────
      when 'late_permit' then
        v_permit_date := nullif(v_payload->>'permitDate', '')::date;
        v_minutes := nullif(v_payload->>'minutes', '')::integer;
        if v_permit_date is null then
          raise exception 'permit date is required' using errcode = '22023';
        end if;
        if v_permit_date < v_today then
          raise exception 'retroactive permits are not allowed' using errcode = '22023';
        end if;
        if v_minutes is null or v_minutes < 1 or v_minutes > 240 then
          raise exception 'permit minutes must be between 1 and 240' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'permitDate', v_permit_date,
          'permitKind', 'late_arrival',
          'minutes', v_minutes);

      -- ─── إذن انصراف مبكر (V17 §8 — كان attendance_permit + early_departure) ─
      when 'early_permit' then
        v_permit_date := nullif(v_payload->>'permitDate', '')::date;
        v_minutes := nullif(v_payload->>'minutes', '')::integer;
        if v_permit_date is null then
          raise exception 'permit date is required' using errcode = '22023';
        end if;
        if v_permit_date < v_today then
          raise exception 'retroactive permits are not allowed' using errcode = '22023';
        end if;
        if v_minutes is null or v_minutes < 1 or v_minutes > 240 then
          raise exception 'permit minutes must be between 1 and 240' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'permitDate', v_permit_date,
          'permitKind', 'early_departure',
          'minutes', v_minutes);

      -- ─── تصحيح حضور (V17 §8 — نوع جديد) ──────────────────────────────────
      when 'attendance_correction' then
        v_correction_date := nullif(v_payload->>'correctionDate', '')::date;
        v_correction_type := v_payload->>'correctionType';
        v_corrected_time := v_payload->>'correctedTime';
        if v_correction_date is null then
          raise exception 'correction date is required' using errcode = '22023';
        end if;
        if v_correction_type not in ('check_in','check_out','both') then
          raise exception 'correctionType must be check_in, check_out, or both' using errcode = '22023';
        end if;
        if v_corrected_time is null or v_corrected_time !~ '^\d{2}:\d{2}$' then
          raise exception 'correctedTime must be in HH:MM format' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'correctionDate', v_correction_date,
          'correctionType', v_correction_type,
          'correctedTime', v_corrected_time);

      else
        null;
    end case;
  exception
    when invalid_text_representation or datetime_field_overflow then
      raise exception 'invalid request dates or numeric values' using errcode = '22023';
  end;

  -- المدير المسؤول من الهيكل الإداري (مع منع الموافقة الذاتية + توجيه التشغيل)
  v_manager := public.resolve_request_approver(v_me, v_today);

  v_row := public.submit_request(
    p_request_type,
    null,
    v_manager,
    trim(p_title),
    trim(p_reason),
    v_payload);

  -- إنشاء صف تفصيل الإجازة (يُفعّل حجز الرصيد عبر تريغر 0026)
  if p_request_type = 'leave' then
    insert into public.leave_requests(
      request_id, employee_id, leave_type_id, start_date, end_date,
      days_count, duration_unit, handover_notes, contact_during_leave,
      attachment_url, substitute_employee_id, created_by)
    values(
      v_row.id, v_me, v_leave_type_id, v_start_date, v_end_date,
      v_days, 'day',
      nullif(v_payload->>'handoverNotes',''),
      nullif(v_payload->>'contactDuringLeave',''),
      nullif(v_payload->>'attachmentUrl',''),
      v_substitute, auth.uid());

    -- العارضة/الطارئة: تُنفَّذ مباشرة دون موافقة المدير المباشر
    if v_leave_type = 'casual' then
      update public.requests
        set status = 'approved',
            workflow_status = 'completed',
            decided_at = now(),
            decided_by = v_me,
            updated_at = now()
        where id = v_row.id
        returning * into v_row;

      update public.request_steps
        set status = 'skipped', acted_at = now(), acted_by = v_me,
            comment = 'تنفيذ مباشر للإجازة العارضة دون موافقة', updated_at = now()
        where request_id = v_row.id and status in ('active','pending');

      update public.workflow_instances
        set status = 'completed', completed_at = now(), updated_at = now()
        where request_id = v_row.id and status = 'running';

      insert into public.request_actions(
        request_id, actor_employee_id, action, from_status, to_status, comment, metadata, created_by)
      values(
        v_row.id, v_me, 'system', 'pending', 'approved',
        'تنفيذ مباشر للإجازة العارضة (لا تستوجب موافقة المدير المباشر)',
        jsonb_build_object('immediate', true, 'leaveType', 'casual'), auth.uid());

      perform public.log_audit_event(
        'leave.casual.immediate', 'workflow', 'info', 'requests', v_row.id,
        'تنفيذ فوري لإجازة عارضة',
        format('من %s إلى %s', v_start_date, v_end_date),
        jsonb_build_object('days', v_days, 'employeeId', v_me));
    end if;
  end if;

  return v_row;
end $$;

revoke execute on function public.submit_my_request(text,text,text,jsonb) from public;
grant execute on function public.submit_my_request(text,text,text,jsonb) to authenticated;

comment on function public.submit_my_request(text,text,text,jsonb) is
  'V17 §8: تقديم طلب شخصي — 6 أنواع (leave/mission/convoy/late_permit/early_permit/attendance_correction) مع توجيه تلقائي للمدير.';
