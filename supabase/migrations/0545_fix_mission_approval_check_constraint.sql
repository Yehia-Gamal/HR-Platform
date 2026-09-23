-- Migration 0545: إصلاح خطأ قبول واعتماد المأموريات (23514 check constraint ck_missions_period)
-- السبب الجذري:
-- في دالة tg_leave_attendance_on_approval، عند اعتماد مأمورية لا تحتوي على endTime
-- (وهو الوضع القياسي منذ التعديل 0503 حيث تبدأ المأمورية فور الإنشاء وتستمر حتى انتهاء العمل)،
-- كانت الدالة تحسب end_at كـ T00:00:00 من نفس اليوم، بينما start_at يحتوي على وقت الإنشاء (مثل 12:31:00).
-- مما يجعل end_at يسبق start_at بـ 12 ساعة، فيخرق القيد ck_missions_period (check end_at >= start_at)
-- وينتج عنه الخطأ 23514: new row for relation "missions" violates check constraint "ck_missions_period".
--
-- الحل:
-- 1) احتساب end_at الافتراضي حتى نهاية اليوم (T23:59:59) عند عدم تحديد endTime.
-- 2) ضمان أن end_at >= start_at دائماً عبر greatest(v_start_ts, v_end_ts).
-- 3) تطبيق نفس الحماية على convoy_requests لضمان عدم حدوث تعارض زمني مماثل.
-- 4) تحديث دالة decide_request بحماية إضافية لـ mission_executions.

begin;

-- ═══════════════════════════════════════════════════════════════════════
-- 1) تحديث tg_leave_attendance_on_approval
-- ═══════════════════════════════════════════════════════════════════════

create or replace function public.tg_leave_attendance_on_approval()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_lr public.leave_requests;
  v_day date; v_end date; v_start date; v_emp uuid;
  v_start_ts timestamptz; v_end_ts timestamptz;
  v_type_id uuid; v_year integer;
  v_punch timestamptz;
  v_covered boolean;
  v_dep_ts timestamptz;
  v_ret_ts timestamptz;
begin
  if old.status = new.status then return new; end if;

  -- ── إجازة معتمدة: on_leave (مع حماية أيام العمل المعتمدة الأخرى) ──
  if new.request_type = 'leave' and new.status = 'approved' then
    select * into v_lr from public.leave_requests where request_id = new.id;
    if not found then return new; end if;
    v_day := v_lr.start_date;
    while v_day <= v_lr.end_date loop
      -- يوم مغطّى بمأمورية/قافلة/فاندي/تكليف معتمد = يوم عمل → لا يُعلَّم إجازة
      v_covered := exists (
        select 1 from public.requests r
        where r.employee_id = v_lr.employee_id and r.status = 'approved'
          and r.request_type in ('mission','convoy','fundraising')
          and v_day between public._payload_date(r.payload, 'startDate')
                       and coalesce(public._payload_date(r.payload, 'endDate'), public._payload_date(r.payload, 'startDate'))
      ) or exists (
        select 1 from public.work_assignment_participants wp
        join public.work_assignments wa on wa.id = wp.assignment_id
        where wp.employee_id = v_lr.employee_id and wa.status = 'APPROVED'
          and v_day between (wa.start_at at time zone 'Africa/Cairo')::date
                       and (wa.end_at at time zone 'Africa/Cairo')::date
      );
      if not v_covered then
        insert into public.attendance_daily(employee_id, work_date, status)
        values(v_lr.employee_id, v_day, 'on_leave')
        on conflict on constraint attendance_daily_uq do update
          set status = 'on_leave', updated_at = now()
          where public.attendance_daily.is_finalized = false
            and public.attendance_daily.status <> 'on_leave';
      end if;
      v_day := v_day + 1;
    end loop;
    perform public.log_audit_event(
      'leave.attendance.marked', 'workflow', 'info', 'attendance_daily', v_lr.employee_id,
      'تم تعليم أيام الإجازة المعتمدة كـ on_leave في الحضور',
      format('من %s إلى %s', v_lr.start_date, v_lr.end_date),
      jsonb_build_object('requestId', new.id));
    return new;
  end if;

  -- ── مأمورية/قافلة/فاندي معتمدة: أيام عمل → present (بلا خصم من الرصيد) ──
  if new.request_type in ('mission','convoy','fundraising') and new.status = 'approved' then
    v_emp := new.employee_id;
    if v_emp is null then
      return new; -- لا بيانات مصدرية للطلب → لا تعليم
    end if;
    v_start := public._payload_date(new.payload, 'startDate');
    v_end := coalesce(public._payload_date(new.payload, 'endDate'), v_start);

    if v_start is null then
      -- بلا payload: قراءة التواريخ من الخانات الخاصة (طلبات قديمة / إنشاء مباشر)
      v_start_ts := null; v_end_ts := null;
      if new.request_type = 'mission' then
        select start_at, end_at into v_start_ts, v_end_ts
        from public.missions where request_id = new.id;
      elsif new.request_type = 'convoy' then
        select departure_at, coalesce(return_at, departure_at) into v_start_ts, v_end_ts
        from public.convoy_requests where request_id = new.id;
      end if;
      if v_start_ts is null then
        return new;
      end if;
      v_start := (v_start_ts at time zone 'Africa/Cairo')::date;
      v_end := (v_end_ts at time zone 'Africa/Cairo')::date;
    else
      -- ضبط الخانات الخاصة بالطلب من payload (متوافقة مع قراءة الكشف والتراجع)
      if new.request_type = 'mission'
         and not exists (select 1 from public.missions where request_id = new.id) then
        
        -- حساب start_at و end_at للمأمورية:
        -- المأمورية تبدأ من startTime أو T00:00:00
        -- وتنتهي في endTime أو نهاية اليوم T23:59:59 (لمنع انتهاك ck_missions_period)
        v_start_ts := (v_start::text || case when new.payload->>'startTime' is not null
                                             then 'T' || (new.payload->>'startTime') || ':00'
                                             else 'T00:00:00' end)::timestamp at time zone 'Africa/Cairo';
        v_end_ts   := (v_end::text   || case when new.payload->>'endTime' is not null
                                             then 'T' || (new.payload->>'endTime') || ':00'
                                             else 'T23:59:59' end)::timestamp at time zone 'Africa/Cairo';
        if v_end_ts < v_start_ts then
          v_end_ts := v_start_ts;
        end if;

        insert into public.missions (request_id, employee_id, destination, purpose, start_at, end_at, created_by)
        values (
          new.id, v_emp, coalesce(new.payload->>'location', ''), coalesce(new.title, ''),
          v_start_ts, v_end_ts, new.created_by
        );
      elsif new.request_type = 'convoy'
            and not exists (select 1 from public.convoy_requests where request_id = new.id) then
        v_dep_ts := (v_start::text || case when new.payload->>'startTime' is not null
                                           then 'T' || (new.payload->>'startTime') || ':00'
                                           else 'T00:00:00' end)::timestamp at time zone 'Africa/Cairo';
        v_ret_ts := case
                      when new.payload->>'endTime' is not null
                        then (v_end::text || 'T' || (new.payload->>'endTime') || ':00')::timestamp at time zone 'Africa/Cairo'
                      when v_end > v_start
                        then (v_end::text || 'T23:59:59')::timestamp at time zone 'Africa/Cairo'
                      else null
                    end;
        if v_ret_ts is not null and v_ret_ts < v_dep_ts then
          v_ret_ts := v_dep_ts;
        end if;

        insert into public.convoy_requests (request_id, employee_id, convoy_name, origin, destination, departure_at, return_at, created_by)
        values (
          new.id, v_emp,
          coalesce(coalesce(new.payload->>'convoyName', new.title), ''),
          coalesce(new.payload->>'origin', ''), coalesce(new.payload->>'location', ''),
          v_dep_ts, v_ret_ts,
          new.created_by
        );
      end if;
    end if;

    v_day := v_start;
    while v_day <= v_end loop
      -- بصمة حضور في أول يوم (من وقت بدء المأمورية إن وُجد — بدون بصمة = حضور مُسجَّل)
      v_punch := null;
      if v_day = v_start and new.payload->>'startTime' is not null then
        v_punch := (v_day::text || 'T' || (new.payload->>'startTime') || ':00')::timestamp at time zone 'Africa/Cairo';
      end if;
      insert into public.attendance_daily(employee_id, work_date, status, first_check_in)
      values(v_emp, v_day, 'present', v_punch)
      on conflict on constraint attendance_daily_uq do update
        set status = 'present',
            first_check_in = coalesce(public.attendance_daily.first_check_in, excluded.first_check_in),
            updated_at = now()
        where public.attendance_daily.is_finalized = false
          and public.attendance_daily.status not in ('holiday','weekend');

      -- بصمة انصراف في آخر يوم (وقت نهاية المأمورية إن وُجد — يُسجَّل الانصراف عند الامتداد خارج العمل)
      if v_day = v_end and new.payload->>'endTime' is not null then
        update public.attendance_daily
        set last_check_out = (v_day::text || 'T' || (new.payload->>'endTime') || ':00')::timestamp at time zone 'Africa/Cairo',
            updated_at = now()
        where employee_id = v_emp and work_date = v_day
          and last_check_out is null and is_finalized = false;
      end if;

      -- بدل الراحة الأسبوعي: الجمعة خلال مأمورية/قافلة/فاندي
      if extract(isodow from v_day) = 5 then
        select id into v_type_id from public.leave_types where code = 'weekly_rest_comp';
        if v_type_id is not null then
          v_year := extract(year from v_day)::integer;
          perform public.apply_leave_ledger_entry(
            v_emp, v_type_id, v_year, 'credit', 1,
            'weekly-rest:credit:' || v_emp::text || ':' || v_day::text,
            null,
            'بدل راحة أسبوعي عن يوم عمل في ' || new.request_type || ' بتاريخ ' || to_char(v_day, 'YYYY-MM-DD'),
            jsonb_build_object('workDate', v_day::text, 'source', new.request_type, 'requestId', new.id)
          );
        end if;
      end if;
      v_day := v_day + 1;
    end loop;
    perform public.log_audit_event(
      'leave.attendance.marked', 'workflow', 'info', 'attendance_daily', v_emp,
      'تم تعليم أيام ' || new.request_type || ' المعتمدة كحضور عمل (present) بلا خصم',
      format('من %s إلى %s', v_start, v_end),
      jsonb_build_object('requestId', new.id, 'kind', new.request_type));
    return new;
  end if;

  return new;
end $function$;

-- ═══════════════════════════════════════════════════════════════════════
-- 2) حماية إضافية على جدول missions ضد التواريخ المتعارضة
-- ═══════════════════════════════════════════════════════════════════════

update public.missions
set end_at = start_at
where end_at < start_at;

-- ═══════════════════════════════════════════════════════════════════════
-- 3) حماية إضافية في decide_request لـ mission_executions
-- ═══════════════════════════════════════════════════════════════════════

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

  -- إذا كانت مأمورية وتم اعتمادها، يتم تفعيل تنفيذ المأمورية بأمان
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

commit;
