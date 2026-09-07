-- Migration 0503: إصلاح قبول طلبات الموظفين (مأموريات، إجازات، أذونات) وتعديل المأمورية لتبدأ من وقت الإنشاء تلقائياً دون تحديد أوقات.
-- 1) decide_request: توسيع التخويل ليشمل الإدارة التنفيذية والمدير المباشر والموارد البشرية وبدء المأمورية تلقائياً من وقت الإنشاء فور الاعتماد.
-- 2) apply_leave_ledger_entry: منع رفع خطأ CONSUME_EXCEEDS_RESERVE الذي يوقف اعتماد الإجازات عند وجود فارق حجز رصيد.
-- 3) submit_my_request & resubmit_my_request: تحرير المأمورية من إلزامية تاريخ ووقت البداية والنهاية، وضبط بدايتها تلقائياً من تاريخ ولحظة الإنشاء.
-- 4) get_request_detail: تحديث can_decide ليتطابق مع صلاحيات البت الموسعة.
-- 5) create_work_assignment: ضبط توقيت المأمورية الجماعية تلقائياً من وقت الإنشاء.
-- 6) start_my_mission: إزالة قيود تاريخ انتهاء المأمورية وجعلها تبدأ من تاريخ الإنشاء.

begin;

-- ============================================================================
-- 1) تحديث decide_request — صلاحية شاملة تضمن قبول كافة طلبات الموظفين
-- ============================================================================
create or replace function public.decide_request(
  p_request_id uuid,
  p_decision   text,
  p_comment    text default null
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
  v_is_operations := public.current_has_active_role(array['operations-manager-1','operations-manager','operations-officer']);

  -- الصلاحية الشاملة لاعتماد الطلبات:
  v_authorized :=
    public.current_is_full_access()
    or v_is_exec
    or v_is_hr
    or v_is_direct_mgr
    or (v_step.id is not null and v_step.assignee_employee_id = v_me)
    or public.current_has_active_role(array['admin','super-admin'])
    or public.has_any_permission(array['requests.request.approve','requests.approve','requests.request.override'])
    or public.can_access_employee(v_req.employee_id, 'requests.approve')
    or public.can_access_employee(v_req.employee_id, 'requests.request.approve')
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

  -- تسجيل إجراء الخطوة الحالية
  if v_step.id is not null then
    update public.request_steps
      set status = case p_decision when 'approve' then 'approved' else 'rejected' end,
          acted_at = now(), acted_by = v_me,
          comment = p_comment, updated_at = now()
    where id = v_step.id;
  end if;

  -- إغلاق باقي الخطوات (موافقة واحدة تُنهي الطلب)
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

  -- 0503: إذا كانت مأمورية وتم اعتمادها، يتم تفعيل تنفيذ المأمورية تلقائياً من لحظة الإنشاء
  if v_final_status = 'approved' and v_req.request_type = 'mission' then
    insert into public.mission_executions(request_id, employee_id, status, started_at)
    values (v_req.id, v_req.employee_id, 'in_progress', coalesce(v_req.created_at, now()))
    on conflict (request_id) do update
      set status = case when public.mission_executions.status = 'completed' then 'completed' else 'in_progress' end,
          started_at = coalesce(public.mission_executions.started_at, v_req.created_at, now()),
          updated_at = now();
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

comment on function public.decide_request(uuid, text, text) is
  '0503: اعتماد/رفض الطلبات بصلاحيات شاملة تضمن عدم حظر موافقة الإدارة والمديرين المباشرين.';
revoke all on function public.decide_request(uuid, text, text) from public, anon;
grant execute on function public.decide_request(uuid, text, text) to authenticated;

-- ============================================================================
-- 2) تحديث apply_leave_ledger_entry — استهلاك آمن يمنع فشل اعتماد الإجازات
-- ============================================================================
create or replace function public.apply_leave_ledger_entry(
  p_employee_id   uuid,
  p_leave_type_id uuid,
  p_year          integer,
  p_entry_type    text,   -- opening|accrual|carryover|adjustment|reserve|release|consume|refund|expire|credit
  p_units         numeric,
  p_source_key    text,
  p_request_id    uuid default null,
  p_reason        text default null,
  p_metadata      jsonb default '{}'::jsonb
) returns public.leave_ledger_entries
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_account   public.leave_balance_accounts;
  v_entry     public.leave_ledger_entries;
  v_available numeric;
  v_lock_id   bigint;
begin
  if p_units = 0 then raise exception 'LEAVE_UNITS_ZERO'; end if;
  if p_entry_type not in (
    'opening','accrual','carryover','adjustment','reserve','release',
    'consume','refund','expire','credit'
  ) then raise exception 'INVALID_LEAVE_ENTRY_TYPE'; end if;
  if nullif(trim(coalesce(p_source_key,'')),'') is null then
    raise exception 'LEAVE_SOURCE_KEY_REQUIRED';
  end if;

  -- advisory lock: serialize per (employee, leave_type)
  v_lock_id := hashtextextended(p_employee_id::text || ':' || p_leave_type_id::text, 0);
  perform pg_advisory_xact_lock(v_lock_id);

  v_account := public.ensure_leave_account(p_employee_id, p_leave_type_id, p_year);

  -- idempotency: skip if source_key already processed
  select * into v_entry
  from public.leave_ledger_entries
  where source_key = p_source_key;
  if found then
    return v_entry;
  end if;

  if p_entry_type = 'opening' and v_account.opening_units <> 0 then
    select * into v_entry
    from public.leave_ledger_entries
    where account_id = v_account.id and entry_type = 'opening'
    order by created_at limit 1;
    if found then return v_entry; end if;
  end if;

  insert into public.leave_ledger_entries(
    account_id, employee_id, leave_type_id, request_id, entry_type, units,
    effective_date, reason, source_key, metadata, created_by
  ) values (
    v_account.id, p_employee_id, p_leave_type_id, p_request_id, p_entry_type, p_units,
    current_date, p_reason, p_source_key, coalesce(p_metadata, '{}'::jsonb), auth.uid()
  ) on conflict(source_key) do nothing returning * into v_entry;
  if not found then
    select * into strict v_entry from public.leave_ledger_entries
    where source_key = p_source_key;
    return v_entry;
  end if;

  -- تطبيق القيد حسب النوع
  if p_entry_type = 'opening' then
    update public.leave_balance_accounts set opening_units = opening_units + p_units, updated_at = now() where id = v_account.id;
  elsif p_entry_type = 'accrual' then
    update public.leave_balance_accounts set accrued_units = accrued_units + p_units, updated_at = now() where id = v_account.id;
  elsif p_entry_type = 'carryover' then
    update public.leave_balance_accounts set carryover_units = carryover_units + p_units, updated_at = now() where id = v_account.id;
  elsif p_entry_type = 'adjustment' then
    update public.leave_balance_accounts set adjusted_units = adjusted_units + p_units, updated_at = now() where id = v_account.id;
  elsif p_entry_type = 'credit' then
    update public.leave_balance_accounts set adjusted_units = adjusted_units + p_units, updated_at = now() where id = v_account.id;
  elsif p_entry_type = 'reserve' then
    select opening_units + accrued_units + adjusted_units + carryover_units - consumed_units - reserved_units
      into v_available from public.leave_balance_accounts where id = v_account.id for update;
    if v_available < p_units then
      raise exception 'INSUFFICIENT_LEAVE_BALANCE: available=% requested=%', v_available, p_units;
    end if;
    update public.leave_balance_accounts set reserved_units = reserved_units + p_units, updated_at = now() where id = v_account.id;
  elsif p_entry_type = 'release' then
    update public.leave_balance_accounts set reserved_units = greatest(0, reserved_units - abs(p_units)), updated_at = now() where id = v_account.id;
  elsif p_entry_type = 'consume' then
    -- استهلاك الرصيد بأمان دون إحباط العملية إذا لم يكن هناك حجز كافٍ
    update public.leave_balance_accounts
      set reserved_units = greatest(0, reserved_units - abs(p_units)),
          consumed_units = consumed_units + abs(p_units),
          updated_at = now()
      where id = v_account.id;
  elsif p_entry_type = 'refund' then
    update public.leave_balance_accounts set consumed_units = greatest(0, consumed_units - abs(p_units)), updated_at = now() where id = v_account.id;
  elsif p_entry_type = 'expire' then
    update public.leave_balance_accounts set adjusted_units = adjusted_units - abs(p_units), updated_at = now() where id = v_account.id;
  end if;

  return v_entry;
end;
$$;

comment on function public.apply_leave_ledger_entry(uuid, uuid, integer, text, numeric, text, uuid, text, jsonb) is
  '0503: تطبيق قيود رصيد الإجازات مع استهلاك آمن لا يعطل الاعتماد.';
revoke all on function public.apply_leave_ledger_entry(uuid, uuid, integer, text, numeric, text, uuid, text, jsonb) from public, anon;
grant execute on function public.apply_leave_ledger_entry(uuid, uuid, integer, text, numeric, text, uuid, text, jsonb) to authenticated, service_role;

-- ============================================================================
-- 3) تحديث submit_my_request — المأمورية تبدأ من وقت الإنشاء وتُلغى خيارات الوقت
-- ============================================================================
create or replace function public.submit_my_request(
  p_request_type text,
  p_title text,
  p_reason text,
  p_payload jsonb default '{}'::jsonb,
  p_idempotency_key uuid default null::uuid
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me                uuid := public.current_employee_id();
  v_manager           uuid;
  v_row               public.requests;
  v_payload           jsonb := coalesce(p_payload, '{}'::jsonb);
  v_today             date := (now() at time zone 'Africa/Cairo')::date;
  v_month_start       date := date_trunc('month', v_today)::date;
  v_day_mark          boolean := coalesce((v_payload->>'dayMark')::boolean, false);
  v_start_date        date;
  v_end_date          date;
  v_permit_date       date;
  v_minutes           integer;
  v_leave_type        text;
  v_leave_type_id     uuid;
  v_affects           boolean;
  v_days              numeric;
  v_substitute        uuid;
  v_correction_date   date;
  v_correction_type   text;
  v_corrected_time    text;
  v_permit_kind       text;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  if p_idempotency_key is not null then
    select * into v_row
    from public.requests
    where employee_id = v_me
      and payload ->> 'clientId' = p_idempotency_key::text
      and created_at > now() - interval '10 minutes';
    if found then
      return v_row;
    end if;
    v_payload := v_payload || jsonb_build_object('clientId', p_idempotency_key::text);
  end if;

  if p_request_type not in ('leave','mission','convoy','fundraising','late_permit','early_permit','attendance_correction','attendance_permit','generic') then
    raise exception 'نوع طلب غير صالح' using errcode = '22023';
  end if;

  if length(trim(coalesce(p_title,''))) < 3
     or length(trim(coalesce(p_reason,''))) < 3 then
    raise exception 'title and reason are required (min 3 chars)' using errcode = '22023';
  end if;

  if v_day_mark and p_request_type in ('leave','convoy','fundraising') then
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
        if v_leave_type = 'emergency' then v_leave_type := 'casual'; end if;
        v_start_date := nullif(v_payload->>'startDate', '')::date;
        v_end_date := nullif(v_payload->>'endDate', '')::date;
        v_substitute := nullif(v_payload->>'substituteEmployeeId', '')::uuid;
        if v_leave_type not in ('annual','casual','sick','unpaid','weekly_rest_comp') then
          raise exception 'نوع إجازة غير مدعوم' using errcode = '22023';
        end if;
        if v_start_date is null or v_end_date is null then
          raise exception 'leave start and end dates are required' using errcode = '22023';
        end if;
        if v_end_date < v_start_date then
          raise exception 'leave end date cannot precede start date' using errcode = '22023';
        end if;
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

      -- ─── مأمورية (0503: تبدأ من وقت الإنشاء فوراً ودون اختيار وقت) ───────────
      when 'mission' then
        v_start_date := coalesce(nullif(v_payload->>'startDate', '')::date, v_today);
        v_end_date   := coalesce(nullif(v_payload->>'endDate', '')::date, v_start_date);
        if length(trim(coalesce(v_payload->>'location', ''))) < 2 then
          raise exception 'assignment location is required' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'startDate', v_start_date,
          'endDate', v_end_date,
          'location', trim(v_payload->>'location'),
          'days', 1,
          'startTime', coalesce(nullif(trim(coalesce(v_payload->>'startTime','')),''), to_char(now() at time zone 'Africa/Cairo', 'HH24:MI')),
          'startedAtCreation', true);

      -- ─── قافلة / فاندي ───────────────────────────────────────────────────
      when 'convoy', 'fundraising' then
        v_start_date := nullif(v_payload->>'startDate', '')::date;
        v_end_date := nullif(v_payload->>'endDate', '')::date;
        if v_start_date is null or v_end_date is null then
          raise exception 'تاريخا بداية ونهاية التكليف مطلوبان' using errcode = '22023';
        end if;
        if v_end_date < v_start_date then
          raise exception 'تاريخ نهاية التكليف لا يسبق تاريخ البداية' using errcode = '22023';
        end if;
        if not v_day_mark and v_start_date < v_today then
          raise exception 'التكليفات بأثر رجعي غير مسموحة' using errcode = '22023';
        end if;
        if length(trim(coalesce(v_payload->>'location', ''))) < 2 then
          raise exception 'assignment location is required' using errcode = '22023';
        end if;
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

      -- ─── إذن تأخير ────────────────────────────────────────────────────────
      when 'late_permit' then
        v_permit_date := nullif(v_payload->>'permitDate', '')::date;
        v_minutes := nullif(v_payload->>'minutes', '')::integer;
        if v_permit_date is null then
          raise exception 'تاريخ الإذن مطلوب' using errcode = '22023';
        end if;
        if v_permit_date < v_today then
          raise exception 'retroactive permits are not allowed' using errcode = '22023';
        end if;
        if v_minutes is null or v_minutes < 1 or v_minutes > 240 then
          raise exception 'دقائق الإذن يجب أن تكون بين 1 و240' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'permitDate', v_permit_date,
          'permitKind', 'late_arrival',
          'minutes', v_minutes);

      -- ─── إذن انصراف مبكر ──────────────────────────────────────────────────
      when 'early_permit' then
        v_permit_date := nullif(v_payload->>'permitDate', '')::date;
        v_minutes := nullif(v_payload->>'minutes', '')::integer;
        if v_permit_date is null then
          raise exception 'تاريخ الإذن مطلوب' using errcode = '22023';
        end if;
        if v_permit_date < v_today then
          raise exception 'retroactive permits are not allowed' using errcode = '22023';
        end if;
        if v_minutes is null or v_minutes < 1 or v_minutes > 240 then
          raise exception 'دقائق الإذن يجب أن تكون بين 1 و240' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'permitDate', v_permit_date,
          'permitKind', 'early_departure',
          'minutes', v_minutes);

      -- ─── إذن حضور موحد ─────────────────────────────────────────────────────
      when 'attendance_permit' then
        v_permit_date := nullif(v_payload->>'permitDate', '')::date;
        v_permit_kind := v_payload->>'permitKind';
        v_minutes := nullif(v_payload->>'minutes', '')::integer;
        if v_permit_date is null then
          raise exception 'تاريخ الإذن مطلوب' using errcode = '22023';
        end if;
        if v_permit_date < v_today then
          raise exception 'إذن الحضور بأثر رجعي غير مسموح' using errcode = '22023';
        end if;
        if v_permit_kind not in ('late_arrival','early_departure') then
          raise exception 'نوع إذن غير مدعوم' using errcode = '22023';
        end if;
        if v_minutes is null or v_minutes < 1 or v_minutes > 240 then
          raise exception 'دقائق الإذن يجب أن تكون بين 1 و240' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'permitDate', v_permit_date,
          'permitKind', v_permit_kind,
          'minutes', v_minutes);

      -- ─── تصحيح حضور ─────────────────────────────────────────────────────
      when 'attendance_correction' then
        v_correction_date := nullif(v_payload->>'correctionDate', '')::date;
        v_correction_type := v_payload->>'correctionType';
        v_corrected_time := v_payload->>'correctedTime';
        if v_correction_date is null then
          raise exception 'تاريخ التصحيح مطلوب' using errcode = '22023';
        end if;
        if v_correction_type not in ('check_in','check_out','both') then
          raise exception 'نوع التصحيح يجب أن يكون حضور أو انصراف أو كلاهما' using errcode = '22023';
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
      raise exception 'تواريخ أو قيم رقمية غير صالحة' using errcode = '22023';
  end;

  v_manager := public.resolve_request_approver(v_me, v_today);

  v_row := public._submit_request_for(
    v_me,
    p_request_type,
    null,
    v_manager,
    trim(p_title),
    trim(p_reason),
    v_payload);

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
end;
$$;

comment on function public.submit_my_request(text, text, text, jsonb, uuid) is
  '0503: تقديم طلبات الموظفين مع ضبط المأمورية لتبدأ تلقائياً من وقت الإنشاء.';
revoke all on function public.submit_my_request(text, text, text, jsonb, uuid) from public, anon;
grant execute on function public.submit_my_request(text, text, text, jsonb, uuid) to authenticated, service_role;

-- ============================================================================
-- 4) تحديث resubmit_my_request — للمأموريات المعادة
-- ============================================================================
create or replace function public.resubmit_my_request(
  p_request_id uuid,
  p_title      text,
  p_reason     text,
  p_payload    jsonb default '{}'::jsonb
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_req      public.requests;
  v_def      public.workflow_definitions;
  v_manager  uuid;
  v_due      timestamptz;
  v_esc      timestamptz;
  v_payload  jsonb := coalesce(p_payload, '{}'::jsonb);
  v_today    date := (now() at time zone 'Africa/Cairo')::date;
begin
  select * into v_req from public.requests where id = p_request_id for update;
  if not found then
    raise exception 'REQUEST_NOT_FOUND' using errcode = 'P0002';
  end if;

  if v_req.employee_id <> public.current_employee_id() then
    raise exception 'ONLY_REQUEST_OWNER_CAN_RESUBMIT' using errcode = '42501';
  end if;

  if v_req.status not in ('rejected','returned') then
    raise exception 'ONLY_REJECTED_OR_RETURNED_CAN_RESUBMIT' using errcode = '22023';
  end if;

  if v_req.request_type not in
     ('leave','mission','convoy','fundraising','late_permit','early_permit') then
    raise exception 'TYPE_NOT_RESUBMITTABLE' using errcode = '22023';
  end if;

  if p_title is null or length(trim(p_title)) < 3 or length(trim(p_title)) > 300 then
    raise exception 'INVALID_TITLE_LENGTH' using errcode = '22023';
  end if;
  if p_reason is null or length(trim(p_reason)) < 3 or length(trim(p_reason)) > 300 then
    raise exception 'INVALID_REASON_LENGTH' using errcode = '22023';
  end if;

  if v_req.request_type = 'mission' then
    v_payload := v_payload || jsonb_build_object(
      'startDate', coalesce(nullif(v_payload->>'startDate', '')::date, v_today),
      'endDate', coalesce(nullif(v_payload->>'endDate', '')::date, v_today),
      'days', 1,
      'startTime', coalesce(nullif(trim(coalesce(v_payload->>'startTime','')),''), to_char(now() at time zone 'Africa/Cairo', 'HH24:MI')),
      'startedAtCreation', true
    );
  end if;

  v_manager := public.resolve_request_approver(v_req.employee_id);

  if v_req.workflow_definition_id is not null then
    select * into v_def from public.workflow_definitions where id = v_req.workflow_definition_id;
  end if;
  if v_def.id is null or not v_def.is_active then
    select * into v_def from public.workflow_definitions
      where request_type = v_req.request_type and is_default = true and is_active = true
      order by version desc limit 1;
  end if;
  if v_def.id is not null then
    v_due := now() + make_interval(hours => coalesce(v_def.default_due_hours, 48));
    if v_def.auto_escalate then v_esc := v_due; end if;
  else
    v_due := now() + interval '48 hours';
  end if;

  update public.requests set
    title                = trim(p_title),
    reason               = trim(p_reason),
    payload              = v_payload,
    status               = 'pending',
    workflow_status      = 'submitted',
    current_step_order   = 1,
    manager_employee_id  = coalesce(v_manager, manager_employee_id),
    decision_due_at      = v_due,
    escalation_deadline  = v_esc,
    escalated_at         = null,
    decided_at           = null,
    decided_by           = null,
    updated_at           = now()
  where id = v_req.id
  returning * into v_req;

  delete from public.request_steps where request_id = v_req.id;

  if v_def.id is not null then
    insert into public.request_steps (
      request_id, workflow_step_id, step_order, name_ar, step_type,
      assignee_employee_id, assignee_role_slug, status, sla_hours,
      due_at, escalation_deadline, created_by
    )
    select
      v_req.id, ws.id, ws.step_order, ws.name_ar, ws.step_type,
      case when ws.approver_type = 'specific_employee' then ws.approver_employee_id
           when ws.approver_type in ('direct_manager','department_manager') then v_req.manager_employee_id
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

    update public.workflow_instances set
      status = 'running', current_step_order = 1, completed_at = null, updated_at = now()
    where request_id = v_req.id;
  end if;

  insert into public.request_actions (
    request_id, actor_employee_id, action, to_status, comment, created_by
  ) values (v_req.id, public.current_employee_id(), 'resubmit', 'pending', p_reason, auth.uid());

  return v_req;
end;
$$;

comment on function public.resubmit_my_request(uuid, text, text, jsonb) is
  '0503: إعادة رفع طلب مُعاد أو مرفوض.';
revoke all on function public.resubmit_my_request(uuid, text, text, jsonb) from public, anon;
grant execute on function public.resubmit_my_request(uuid, text, text, jsonb) to authenticated;

-- ============================================================================
-- 5) تحديث get_request_detail — مزامنة صلاحية البت canDecide
-- ============================================================================
create or replace function public.get_request_detail(p_request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_me              uuid := public.current_employee_id();
  v_request         public.requests;
  v_employee        public.employees;
  v_steps           jsonb;
  v_attachments     jsonb;
  v_can_decide      boolean;
  v_can_cancel      boolean;
  v_can_resubmit    boolean;
  v_decision_actor  text;
  v_decision_mode   text;
  v_decision_on_behalf boolean;
  v_execution       jsonb;
  v_is_direct_mgr   boolean;
begin
  select * into v_request from public.requests where id = p_request_id;
  if not found then return null; end if;

  if not (public.current_is_full_access()
          or v_request.employee_id = v_me
          or v_request.manager_employee_id = v_me
          or public.can_access_employee(v_request.employee_id)
          or public.has_permission('requests.read')) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  select * into v_employee from public.employees where id = v_request.employee_id;

  v_is_direct_mgr := (v_request.manager_employee_id = v_me) or exists (
    select 1 from public.manager_relations mr
    where mr.employee_id = v_request.employee_id
      and mr.manager_employee_id = v_me
      and mr.relation_type = 'primary'
      and (mr.effective_to is null or mr.effective_to >= current_date)
  );

  v_can_cancel := v_request.status = 'pending' and v_request.employee_id = v_me;

  v_can_decide := v_request.status = 'pending' and (
    public.current_is_full_access()
    or v_is_direct_mgr
    or public.current_has_active_role(array['executive','executive-director','general-manager','admin','super-admin','hr-manager','hr-specialist','hr-officer','operations-manager-1','operations-manager','operations-officer'])
    or public.can_access_employee(v_request.employee_id, 'requests.request.approve')
    or public.can_access_employee(v_request.employee_id, 'requests.approve')
    or public.has_permission('requests.request.approve')
    or public.has_permission('requests.approve')
    or public.has_permission('requests.request.override')
  );

  v_can_resubmit := v_request.status in ('rejected','returned')
    and v_request.employee_id = v_me
    and v_request.request_type in ('leave','mission','convoy','fundraising','late_permit','early_permit');

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',s.id,'order',s.step_order,'name',s.name_ar,'status',s.status,
    'decision',case when s.status in ('approved','rejected') then s.status else null end,
    'comment',s.comment,'decidedAt',s.acted_at,'dueAt',s.due_at,
    'actorName',actor.full_name_ar
  ) order by s.step_order),'[]'::jsonb)
  into v_steps from public.request_steps s
  left join public.employees actor on actor.id = s.acted_by
  where s.request_id = p_request_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'path',a.storage_path,'mimeType',a.mime,'sizeBytes',a.size_bytes
  ) order by a.created_at),'[]'::jsonb)
  into v_attachments from public.attachments a
  where a.entity_type = 'request' and a.entity_id = p_request_id;

  select e.full_name_ar, a.metadata->>'decisionMode', coalesce((a.metadata->>'onBehalfOfExecutive')::boolean, false)
  into v_decision_actor, v_decision_mode, v_decision_on_behalf
  from public.request_actions a left join public.employees e on e.id = a.actor_employee_id
  where a.request_id = p_request_id and a.action in ('approve','reject')
  order by a.created_at desc limit 1;

  if v_request.request_type in ('mission','convoy','fundraising') then
    select to_jsonb(me) into v_execution from (
      select me.id, me.status,
             me.started_at as "startedAt",
             me.ended_at as "endedAt",
             me.actual_minutes as "actualMinutes",
             me.report, me.outcome
      from public.mission_executions me
      where me.request_id = v_request.id
    ) me;
  end if;

  return jsonb_build_object(
    'id', v_request.id,
    'requestNumber', v_request.request_number,
    'requestType', v_request.request_type,
    'employeeId', v_request.employee_id,
    'employeeName', v_employee.full_name_ar,
    'employeeCode', v_employee.employee_code,
    'title', v_request.title,
    'reason', v_request.reason,
    'status', v_request.status,
    'workflowStatus', v_request.workflow_status,
    'payload', coalesce(v_request.payload, '{}'::jsonb),
    'currentStepOrder', v_request.current_step_order,
    'decisionDueAt', v_request.decision_due_at,
    'createdAt', v_request.created_at,
    'updatedAt', v_request.updated_at,
    'canDecide', v_can_decide,
    'canCancel', v_can_cancel,
    'canResubmit', v_can_resubmit,
    'steps', v_steps,
    'attachments', v_attachments,
    'decisionContext', public.get_request_decision_context(p_request_id),
    'decisionActorName', v_decision_actor,
    'decisionMode', v_decision_mode,
    'decisionOnBehalfOfExecutive', v_decision_on_behalf,
    'missionExecution', v_execution
  );
end $function$;

comment on function public.get_request_detail(uuid) is
  '0503: جلب تفاصيل الطلب مع canDecide محدثة.';
revoke all on function public.get_request_detail(uuid) from public, anon;
grant execute on function public.get_request_detail(uuid) to authenticated;

-- ============================================================================
-- 5) تحديث create_work_assignment — ضبط بداية المأمورية تلقائياً من وقت الإنشاء
-- ============================================================================
create or replace function public.create_work_assignment(
  p_assignment_type          text,
  p_title                    text,
  p_start_at                 timestamp with time zone,
  p_end_at                   timestamp with time zone,
  p_participant_ids          uuid[],
  p_description              text default null::text,
  p_location                 text default null::text,
  p_responsible_employee_id  uuid default null::uuid,
  p_needs_report             boolean default false,
  p_report_due_at            timestamp with time zone default null::timestamp with time zone,
  p_payload                  jsonb default '{}'::jsonb
)
returns public.work_assignments
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_me         uuid := public.current_employee_id();
  v_row        public.work_assignments;
  v_emp        uuid;
  v_can_manage boolean;
  v_payload    jsonb := coalesce(p_payload, '{}'::jsonb);
begin
  if v_me is null then raise exception 'لا يوجد موظف مرتبط' using errcode = '42501'; end if;
  if p_assignment_type not in ('MISSION','CONVOY','FUNDRAISING') then
    raise exception 'نوع تكليف غير صالح' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_title,''))) < 3 then
    raise exception 'العنوان مطلوب' using errcode = '22023';
  end if;

  if p_assignment_type = 'MISSION' then
    if p_start_at is null then
      p_start_at := now();
    end if;
    if p_end_at is null or p_end_at < p_start_at then
      p_end_at := p_start_at;
    end if;
  else
    if p_start_at is null or p_end_at is null or p_end_at < p_start_at then
      raise exception 'فترة تكليف غير صالحة' using errcode = '22023';
    end if;
  end if;

  if p_participant_ids is null or array_length(p_participant_ids,1) is null then
    raise exception 'مشارك واحد على الأقل مطلوب' using errcode = '22023';
  end if;
  if array_length(p_participant_ids,1) > 500 then
    raise exception 'ERR_BATCH_TOO_LARGE' using errcode = '22023';
  end if;

  v_can_manage := public.can_manage_assignment_type_org_wide(p_assignment_type);

  foreach v_emp in array p_participant_ids loop
    if not (v_can_manage or public.can_access_employee(v_emp)) then
      raise exception 'cannot assign employee outside your team without permission: %', v_emp
        using errcode = '42501';
    end if;
  end loop;

  insert into public.work_assignments(
    assignment_type, subtype, title, description, status,
    created_by_employee_id, responsible_employee_id, start_at, end_at,
    is_full_day, location, transport_mode, instructions, project_id, campaign_name,
    target_amount, needs_report, report_due_at, metadata, created_by)
  values(
    p_assignment_type, nullif(v_payload->>'subtype',''), trim(p_title), p_description,
    'APPROVED',
    v_me, coalesce(p_responsible_employee_id, v_me), p_start_at, p_end_at,
    coalesce((v_payload->>'isFullDay')::boolean, true),
    p_location, nullif(v_payload->>'transportMode',''),
    nullif(v_payload->>'instructions',''),
    nullif(v_payload->>'projectId','')::uuid, nullif(v_payload->>'campaignName',''),
    nullif(v_payload->>'targetAmount','')::numeric,
    coalesce(p_needs_report,false), p_report_due_at, v_payload, auth.uid())
  returning * into v_row;

  foreach v_emp in array p_participant_ids loop
    insert into public.work_assignment_participants(
      assignment_id, employee_id, role_in_assignment, created_by)
    values(v_row.id, v_emp, nullif(v_payload->>'roleInAssignment',''), auth.uid())
    on conflict(assignment_id, employee_id) do nothing;

    perform public.notify_employee(
      v_emp, 'تكليف عمل جديد',
      format('%s: %s', case v_row.assignment_type
                         when 'MISSION' then 'مأمورية'
                         when 'CONVOY' then 'قافلة'
                         else 'فاندي' end, v_row.title),
      'general', 'normal', 'work_assignments', v_row.id,
      jsonb_build_object('assignmentType', v_row.assignment_type,
                         'startAt', v_row.start_at, 'endAt', v_row.end_at));
  end loop;

  perform public.log_audit_event(
    'assignment.created', 'workflow', 'info', 'work_assignments', v_row.id,
    'إنشاء تكليف عمل', v_row.title,
    jsonb_build_object('type', v_row.assignment_type,
                       'participants', array_length(p_participant_ids,1)));
  return v_row;
end $function$;

comment on function public.create_work_assignment(text, text, timestamp with time zone, timestamp with time zone, uuid[], text, text, uuid, boolean, timestamp with time zone, jsonb) is
  '0503: إنشاء تكليف عمل مع ضبط وقت المأمورية تلقائياً من لحظة الإنشاء دون إلزامية أوقات مسبقة.';
revoke all on function public.create_work_assignment(text, text, timestamp with time zone, timestamp with time zone, uuid[], text, text, uuid, boolean, timestamp with time zone, jsonb) from public, anon;
grant execute on function public.create_work_assignment(text, text, timestamp with time zone, timestamp with time zone, uuid[], text, text, uuid, boolean, timestamp with time zone, jsonb) to authenticated;

-- ============================================================================
-- 6) تحديث start_my_mission — عدم اشتراط تاريخ نهاية للمأمورية واستمراريتها
-- ============================================================================
create or replace function public.start_my_mission(p_request_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me    uuid := public.current_employee_id();
  v_req   public.requests;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_id    uuid;
  v_end   date;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط' using errcode = '42501';
  end if;

  select * into v_req from public.requests where id = p_request_id;
  if not found then
    raise exception 'لم يتم العثور على طلب المأمورية' using errcode = 'P0002';
  end if;
  if v_req.employee_id <> v_me then
    raise exception 'هذه المأمورية ليست مسندة إليك' using errcode = '42501';
  end if;
  if v_req.request_type not in ('mission','convoy','fundraising') then
    raise exception 'هذا الطلب ليس مأمورية أو تكليفاً' using errcode = '22023';
  end if;
  if v_req.status <> 'approved' then
    raise exception 'يجب اعتماد المأمورية قبل بدئها — راجع الإدارة' using errcode = '22023';
  end if;

  -- إذا كانت مسجلة مسبقاً، نعيد المعرف بسلاسة
  select id into v_id from public.mission_executions
   where request_id = p_request_id
     and status in ('in_progress','completed');
  if v_id is not null then
    return v_id;
  end if;

  if v_req.request_type <> 'mission' then
    begin
      v_end := (nullif(v_req.payload->>'endDate', ''))::date;
    exception when others then
      v_end := null;
    end;
    if v_end is not null and v_today > v_end then
      raise exception 'لا يمكن بدء التكليف بعد انتهاء مدته' using errcode = '22023';
    end if;
  end if;

  insert into public.mission_executions(request_id, employee_id, status, started_at)
  values (p_request_id, v_me, 'in_progress', coalesce(v_req.created_at, now()))
  on conflict (request_id) do update
    set status = 'in_progress',
        started_at = coalesce(public.mission_executions.started_at, v_req.created_at, now()),
        updated_at = now()
  returning id into v_id;

  return v_id;
end $$;

comment on function public.start_my_mission(uuid) is
  '0503: بدء المأمورية بدون قيود تاريخ انتهاء ومع ربط وقت البدء بلحظة الإنشاء.';
revoke all on function public.start_my_mission(uuid) from public, anon;
grant execute on function public.start_my_mission(uuid) to authenticated;

commit;
