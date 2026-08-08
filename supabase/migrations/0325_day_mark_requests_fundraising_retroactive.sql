-- ============================================================================
-- 0325 — تحديد اليوم (مأمورية/قافلة/فاندي/إجازة) بأثر رجعي + نوع طلب fundraising
-- ============================================================================
-- الميزة: من جدول الأيام الشهرية (موبايل/ويب) يضغط المستخدم على يوم ماضٍ أو
-- اليوم الحالي ويعيّنه:
--   • مأمورية (mission)
--   • قافلة (convoy)
--   • فاندي (fundraising — نشاط تشغيلي جديد)
--   • إجازة اعتيادية (annual) / عارضة (casual، تنفيذ فوري) / بدون راتب (unpaid)
-- ويعتمدها المدير المباشر؛ عند الاعتماد يُزال اليوم من الغياب:
--   • mission/convoy/fundraising → present (تريجر إعفاء الحضور)
--   • leave                          → on_leave (تريجر 0065)
-- القيود: فقط أيام ماضية من نفس الشهر + اليوم الحالي (لا أيام مستقبلية، لا أيام
-- قبل الشهر الحالي، ولا تحديد متعدد الأيام).
--
-- التغييرات:
--   1) نوع طلب جديد 'fundraising' (فاندي) في CHECKs + التسمية العربية.
--   2) استخراج جوهر submit_request إلى _submit_request_for(p_employee_id,...)
--      ليستخدمه الإداري للنيابة، مع إشعار المدير المباشر عند غياب خطوات سير عمل.
--   3) submit_my_request يدعم 'fundraising' + dayMark=true (أثر رجعي بنفس الشهر).
--   4) submit_employee_day_mark: RPC للإداري ينشئ طلب تحديد يوم نيابةً عن موظف.
--   5) تريجر جديد trg_fundraising_attendance_exempt يعفى حضور فاندي كالمأمورية.
-- ============================================================================

begin;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1) توسيع CHECK أنواع الطلبات ليشمل fundraising
-- ═══════════════════════════════════════════════════════════════════════════

alter table public.requests drop constraint if exists requests_request_type_check;
alter table public.requests
  add constraint requests_request_type_check
    check(request_type in ('leave','mission','convoy','fundraising','late_permit','early_permit','attendance_correction'));

alter table public.workflow_definitions drop constraint if exists workflow_definitions_request_type_check;
alter table public.workflow_definitions
  add constraint workflow_definitions_request_type_check
    check(request_type in ('leave','mission','convoy','fundraising','late_permit','early_permit','attendance_correction'))
  not valid;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2) request_type_label — تسمية فاندي
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.request_type_label(p_type text)
returns text
language sql immutable strict
as $$
  select case p_type
    when 'leave' then 'إجازة'
    when 'mission' then 'مأمورية'
    when 'convoy' then 'قافلة'
    when 'fundraising' then 'فاندي'
    when 'late_permit' then 'إذن تأخير'
    when 'early_permit' then 'إذن انصراف مبكر'
    when 'attendance_correction' then 'تصحيح حضور'
    else coalesce(p_type, '')
  end;
$$;
revoke execute on function public.request_type_label(text) from public;
grant execute on function public.request_type_label(text) to authenticated, service_role;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3) جوهر إنشاء الطلب لموظف محدد — _submit_request_for
--    (إعادة بناء submit_request من 0316 مع تمرير employee_id + إشعار المدير
--    المباشر عند غياب خطوات سير عمل — كان mission/convoy بدون تعريف دورة عمل
--    لا تُشعر المدير عند الإنشاء)
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public._submit_request_for(
  p_employee_id           uuid,
  p_request_type          text,
  p_workflow_definition_id uuid default null,
  p_manager_employee_id   uuid default null,
  p_title                 text default null,
  p_reason                text default null,
  p_payload               jsonb default '{}'::jsonb
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
  v_first_approver uuid;
begin
  if p_employee_id is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;

  -- V17 §8 + 0325: 7 أنواع رسمية
  if p_request_type not in ('leave','mission','convoy','fundraising','late_permit','early_permit','attendance_correction') then
    raise exception 'invalid request_type: %', p_request_type using errcode = '22023';
  end if;

  if p_manager_employee_id is not null and p_manager_employee_id = p_employee_id then
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
    p_request_type, p_employee_id, p_manager_employee_id, v_def.id,
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

  -- إشعار أول معتمِد (خطوة نشطة) بوصول طلب جديد؛ وعند غياب تعريف سير عمل
  -- (mission/convoy/fundraising) يُشعَر المدير المباشر مباشرة.
  select s.assignee_employee_id into v_first_approver
  from public.request_steps s
  where s.request_id = v_row.id and s.status = 'active'
  order by s.step_order
  limit 1;

  if v_first_approver is null then
    v_first_approver := v_row.manager_employee_id;
  end if;

  if v_first_approver is not null and v_first_approver <> v_row.employee_id then
    perform public.notify_employee(
      v_first_approver,
      'طلب جديد بانتظار مراجعتك',
      format('%s — %s', public.request_type_label(v_row.request_type), coalesce(v_row.title, '')),
      'request', 'normal', 'request', v_row.id,
      jsonb_build_object('requestType', v_row.request_type, 'workflowStatus', 'submitted'));
  end if;

  return v_row;
end;
$$;
comment on function public._submit_request_for(uuid, text, uuid, uuid, text, text, jsonb) is
  'جوهر إنشاء طلب موحّد لموظف محدد (داخلي — يُستدعى من submit_request و submit_employee_day_mark).';
revoke execute on function public._submit_request_for(uuid, text, uuid, uuid, text, text, jsonb) from public, anon;
grant execute on function public._submit_request_for(uuid, text, uuid, uuid, text, text, jsonb) to service_role;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4) submit_request — غلاف V17 §8 (نفس التوقيع) مع دعم fundraising
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.submit_request(
  p_request_type          text,
  p_workflow_definition_id uuid    default null,
  p_manager_employee_id    uuid    default null,
  p_title                  text    default null,
  p_reason                 text    default null,
  p_payload                jsonb   default '{}'::jsonb
)
returns public.requests
language sql
security definer
set search_path = public, pg_temp
as $$
  select public._submit_request_for(
    public.current_employee_id(),
    p_request_type,
    p_workflow_definition_id,
    p_manager_employee_id,
    p_title,
    p_reason,
    p_payload
  );
$$;
comment on function public.submit_request(text, uuid, uuid, text, text, jsonb) is
  'V17 §8: إنشاء طلب موحّد — 7 أنواع رسمية (مع fundraising)، سير عمل وخطوات وإشعار أول معتمِد.';
revoke execute on function public.submit_request(text, uuid, uuid, text, text, jsonb) from public;
grant  execute on function public.submit_request(text, uuid, uuid, text, text, jsonb) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 5) submit_my_request — إعادة بناء 0318 مع:
--      • نوع fundraising (فرع mission/convoy)
--      • dayMark=true: تحديد يوم ماضٍ من نفس الشهر أو اليوم (لا مستقبل، يوم واحد)
--    يستدعي _submit_request_for(v_me, ...)
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.submit_my_request(
  p_request_type text,
  p_title text,
  p_reason text,
  p_payload jsonb default '{}'::jsonb
)
returns requests
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_me uuid := public.current_employee_id();
  v_manager uuid;
  v_row public.requests;
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_month_start date := date_trunc('month', v_today)::date;
  v_day_mark boolean := coalesce((v_payload->>'dayMark')::boolean, false);
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

  -- V17 §8 + 0325: 7 أنواع رسمية بالضبط
  if p_request_type not in ('leave','mission','convoy','fundraising','late_permit','early_permit','attendance_correction') then
    raise exception 'invalid request type' using errcode = '22023';
  end if;

  if length(trim(coalesce(p_title,''))) < 3
     or length(trim(coalesce(p_reason,''))) < 3 then
    raise exception 'title and reason are required (min 3 chars)' using errcode = '22023';
  end if;

  -- قواعد تحديد اليوم (dayMark): يوم ماضٍ من نفس الشهر أو اليوم الحالي فقط.
  -- تُطبَّق على الإجازات والتوجيهات التشغيلية (مأمورية/قافلة/فاندي).
  if v_day_mark and p_request_type in ('leave','mission','convoy','fundraising') then
    v_start_date := nullif(v_payload->>'startDate', '')::date;
    v_end_date := nullif(v_payload->>'endDate', '')::date;
    if v_start_date is null or v_end_date is null then
      raise exception 'day mark requires a date' using errcode = '22023';
    end if;
    if v_end_date <> v_start_date then
      raise exception 'day marks are single-day only' using errcode = '22023';
    end if;
    if v_start_date < v_month_start then
      raise exception 'day marks are allowed within the current month only' using errcode = '22023';
    end if;
    if v_start_date > v_today then
      raise exception 'future days cannot be marked' using errcode = '22023';
    end if;
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
        -- أثر رجعي: مسموح فقط عبر dayMark (نفس الشهر) — وإلا منع كالمعتاد
        if not v_day_mark and v_start_date < v_today then
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

      -- ─── مأمورية / قافلة / فاندي ───────────────────────────────────────────
      when 'mission', 'convoy', 'fundraising' then
        v_start_date := nullif(v_payload->>'startDate', '')::date;
        v_end_date := nullif(v_payload->>'endDate', '')::date;
        if v_start_date is null or v_end_date is null then
          raise exception 'assignment start and end dates are required' using errcode = '22023';
        end if;
        if v_end_date < v_start_date then
          raise exception 'assignment end date cannot precede start date' using errcode = '22023';
        end if;
        -- أثر رجعي: مسموح فقط عبر dayMark — وإلا منع كالمعتاد
        if not v_day_mark and v_start_date < v_today then
          raise exception 'retroactive assignments are not allowed' using errcode = '22023';
        end if;
        if length(trim(coalesce(v_payload->>'location', ''))) < 2 then
          raise exception 'assignment location is required' using errcode = '22023';
        end if;
        -- وقت مخطط اختياري بصيغة HH:MM — يرفض "9:00"
        if nullif(trim(coalesce(v_payload->>'startTime','')),'') is not null
           and v_payload->>'startTime' !~ '^\d{2}:\d{2}$' then
          raise exception 'startTime must be in HH:MM format' using errcode = '22023';
        end if;
        if nullif(trim(coalesce(v_payload->>'endTime','')),'') is not null
           and v_payload->>'endTime' !~ '^\d{2}:\d{2}$' then
          raise exception 'endTime must be in HH:MM format' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'startDate', v_start_date,
          'endDate', v_end_date,
          'location', trim(v_payload->>'location'),
          'days', (v_end_date - v_start_date) + 1,
          'startTime', nullif(trim(coalesce(v_payload->>'startTime','')),''),
          'endTime', nullif(trim(coalesce(v_payload->>'endTime','')),''));

      -- ─── إذن تأخير (V17 §8) ────────────────────────────────────────────────
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

      -- ─── إذن انصراف مبكر (V17 §8) ──────────────────────────────────────────
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

      -- ─── تصحيح حضور (V17 §8) ─────────────────────────────────────────────
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

  v_row := public._submit_request_for(
    v_me,
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
end $function$;
comment on function public.submit_my_request(text, text, text, jsonb) is
  'V17 §8 + 0325: تقديم طلب ذاتي — 7 أنواع، مع تحديد يوم (dayMark) بأثر رجعي بنفس الشهر وتنفيذ فوري للعارضة.';
revoke execute on function public.submit_my_request(text,text,text,jsonb) from public;
grant execute on function public.submit_my_request(text,text,text,jsonb) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 6) submit_employee_day_mark — RPC إداري: ينشئ طلب تحديد يوم نيابةً عن موظف
--    (يستخدمه الويب — لوحة الإدارة). نفس قواعد dayMark + نفس صلاحية
--    التعديل الإداري لليوم (0266) + منع شهر مغلق.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.submit_employee_day_mark(
  p_employee_id uuid,
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
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_month_start date := date_trunc('month', v_today)::date;
  v_start_date date;
  v_end_date date;
  v_manager uuid;
  v_leave_type text;
  v_leave_type_id uuid;
  v_days numeric := 1;
  v_substitute uuid;
  v_row public.requests;
begin
  if v_me is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;
  if p_employee_id is null then
    raise exception 'employee is required' using errcode = '22023';
  end if;

  -- الصلاحية: نفس صلاحية التعديل الإداري لليوم (0266)
  if not (
    public.current_is_full_access()
    or public.can_access_employee(p_employee_id, 'attendance.correction.review')
    or public.can_access_employee(p_employee_id, 'attendance.record.manual_create')
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  -- منع التعديل على شهر مغلق
  if exists (
    select 1
    from public.attendance_periods ap
    join public.employees e on e.id = p_employee_id
    left join public.branches b on b.id = e.branch_id
    where ap.period_month = v_month_start
      and ap.status = 'closed'
      and (ap.branch_id is null or ap.branch_id = e.branch_id)
      and (ap.legal_entity_id is null or ap.legal_entity_id = b.legal_entity_id)
  ) then
    raise exception 'ATTENDANCE_PERIOD_CLOSED' using errcode = '55000';
  end if;

  -- النوع: إجازة أو توجيه تشغيلي فقط
  if p_request_type not in ('leave','mission','convoy','fundraising') then
    raise exception 'day mark supports leave, mission, convoy, fundraising only' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_title,''))) < 3
     or length(trim(coalesce(p_reason,''))) < 3 then
    raise exception 'title and reason are required (min 3 chars)' using errcode = '22023';
  end if;

  v_start_date := nullif(v_payload->>'startDate', '')::date;
  v_end_date := nullif(v_payload->>'endDate', '')::date;
  if v_start_date is null or v_end_date is null then
    raise exception 'day mark requires a date' using errcode = '22023';
  end if;
  if v_end_date <> v_start_date then
    raise exception 'day marks are single-day only' using errcode = '22023';
  end if;
  if v_start_date < v_month_start then
    raise exception 'day marks are allowed within the current month only' using errcode = '22023';
  end if;
  if v_start_date > v_today then
    raise exception 'future days cannot be marked' using errcode = '22023';
  end if;

  v_manager := public.resolve_request_approver(p_employee_id, v_today);

  if p_request_type = 'leave' then
    v_leave_type := v_payload->>'leaveType';
    if v_leave_type = 'emergency' then v_leave_type := 'casual'; end if;
    if v_leave_type not in ('annual','casual','sick','unpaid') then
      raise exception 'unsupported leave type' using errcode = '22023';
    end if;
    select id into v_leave_type_id
    from public.leave_types where code = v_leave_type and is_active = true;
    if v_leave_type_id is null then
      raise exception 'leave type is inactive or unknown: %', v_leave_type using errcode = '22023';
    end if;
    v_substitute := nullif(v_payload->>'substituteEmployeeId', '')::uuid;
    v_payload := v_payload || jsonb_build_object(
      'leaveType', v_leave_type,
      'startDate', v_start_date,
      'endDate', v_end_date,
      'days', v_days,
      'immediate', (v_leave_type = 'casual'),
      'dayMark', true);
  else
    if length(trim(coalesce(v_payload->>'location', ''))) < 2 then
      raise exception 'assignment location is required' using errcode = '22023';
    end if;
    v_payload := v_payload || jsonb_build_object(
      'startDate', v_start_date,
      'endDate', v_end_date,
      'location', trim(v_payload->>'location'),
      'days', v_days,
      'dayMark', true);
  end if;

  v_row := public._submit_request_for(
    p_employee_id,
    p_request_type,
    null,
    v_manager,
    trim(p_title),
    trim(p_reason),
    v_payload);

  -- صف تفصيل الإجازة + تنفيذ فوري للعارضة (نفس مسار submit_my_request)
  if p_request_type = 'leave' then
    insert into public.leave_requests(
      request_id, employee_id, leave_type_id, start_date, end_date,
      days_count, duration_unit, handover_notes, contact_during_leave,
      attachment_url, substitute_employee_id, created_by)
    values(
      v_row.id, p_employee_id, v_leave_type_id, v_start_date, v_end_date,
      v_days, 'day',
      nullif(v_payload->>'handoverNotes',''),
      nullif(v_payload->>'contactDuringLeave',''),
      nullif(v_payload->>'attachmentUrl',''),
      v_substitute, auth.uid());

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
        jsonb_build_object('days', v_days, 'employeeId', p_employee_id));
    end if;
  end if;

  return v_row;
end;
$$;
comment on function public.submit_employee_day_mark(uuid, text, text, text, jsonb) is
  '0325: إداري يُنشئ طلب تحديد يوم (مأمورية/قافلة/فاندي/إجازة) نيابةً عن موظف — بموافقة المدير المباشر.';
revoke execute on function public.submit_employee_day_mark(uuid, text, text, text, jsonb) from public, anon;
grant execute on function public.submit_employee_day_mark(uuid, text, text, text, jsonb) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 7) إعفاء حضور الفاندي عند الاعتماد — كالمأمورية (present + استثناء)
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.tg_fundraising_attendance_exempt()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_start_date date;
  v_end_date date;
  v_day date;
  v_employee_id uuid;
  v_employee_name text;
begin
  -- فقط عند الموافقة على طلب فاندي
  if new.status <> 'approved' or (old.status = new.status) then
    return new;
  end if;
  if new.request_type <> 'fundraising' then
    return new;
  end if;

  v_employee_id := new.employee_id;
  v_start_date := (new.payload->>'startDate')::date;
  v_end_date := coalesce((new.payload->>'endDate')::date, v_start_date);
  if v_start_date is null then
    return new;
  end if;

  select full_name_ar into v_employee_name from public.employees where id = v_employee_id;

  v_day := v_start_date;
  while v_day <= v_end_date loop
    insert into public.attendance_daily (employee_id, work_date, status)
    values (v_employee_id, v_day, 'present')
    on conflict on constraint attendance_daily_uq do update
      set status = 'present',
          updated_at = now()
      where public.attendance_daily.is_finalized = false
        and public.attendance_daily.status not in ('on_leave', 'holiday', 'weekend');

    insert into public.attendance_exceptions (
      employee_id, attendance_daily_id, work_date, kind, description, status, created_by
    )
    select v_employee_id, ad.id, v_day, 'manual_adjustment',
           'فاندي معتمد — إعفاء من التأخير/الغياب',
           'approved', auth.uid()
    from public.attendance_daily ad
    where ad.employee_id = v_employee_id and ad.work_date = v_day
    on conflict do nothing;

    v_day := v_day + 1;
  end loop;

  perform public.log_audit_event(
    'request.attendance_exempted', 'workflow', 'info',
    'attendance_daily', v_employee_id,
    'إعفاء حضور بعد اعتماد فاندي',
    format('من %s إلى %s', v_start_date, v_end_date),
    jsonb_build_object('requestId', new.id, 'requestType', new.request_type,
                       'startDate', v_start_date, 'endDate', v_end_date)
  );

  return new;
end;
$$;

comment on function public.tg_fundraising_attendance_exempt() is
  'يُعفي الموظف من الغياب عند اعتماد طلب فاندي (يقرأ التواريخ من payload).';

drop trigger if exists trg_fundraising_attendance_exempt on public.requests;
create trigger trg_fundraising_attendance_exempt
  after update of status on public.requests
  for each row execute function public.tg_fundraising_attendance_exempt();

notify pgrst, 'reload schema';

commit;
