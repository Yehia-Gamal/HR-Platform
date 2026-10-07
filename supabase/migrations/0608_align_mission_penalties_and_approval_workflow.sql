-- ============================================================================
-- 0608: محاذاة شاملة ومحكمة لمنظومة المأموريات والغرامات والاعتماد
-- ============================================================================
-- الأهداف:
-- 1) حماية المأموريات (سواء كانت معلقة pending أو جارية in_progress أو معتمدة approved)
--    من أي احتساب لدقائق التأخير أو توقيع غرامات تلقائية، عبر تحديث:
--    - public.is_lateness_excused
--    - public.is_employee_exempt_from_instant_penalty
-- 2) عند تقديم الموظف لمأمورية لليوم الحالي عبر submit_my_request:
--    - إلغاء فوري لأي غرامات حضور معلقة لذلك اليوم (pending_payment, doubled).
--    - تصفير دقائق التأخير (late_minutes = 0) في attendance_daily و attendance_events.
--    - تثبيت حالة الحضور كـ present وتوثيق بدء المأمورية.
-- 3) تحديث decide_request:
--    - دعم المأموريات والقوافل وفعاليات الفاندي (mission, convoy, fundraising).
--    - عند الاعتماد: الحفاظ على سجل المأمورية إن كان مكتملاً أو جارياً دون إعادة تصفيره.
--    - عند الرفض: تحديث حالة تنفيذ المأمورية إلى cancelled إن كانت قيد التنفيذ لمنع بقائها معلقة.
-- ============================================================================

begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) تحديث is_lateness_excused: شمول المأموريات المعلقة والجارية والمكتملة
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.is_lateness_excused(p_employee_id uuid, p_work_date date)
returns boolean
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select public.is_employee_attendance_exempt(p_employee_id)
    or public.is_employee_penalty_exempt(p_employee_id)
    or extract(isodow from p_work_date) = 5
    -- عطلة رسمية
    or exists (
      select 1 from public.public_holidays h
      where coalesce(h.is_active, true)
        and p_work_date between h.holiday_date and coalesce(h.end_date, h.holiday_date))
    -- تعديل إداري معتمد
    or exists (
      select 1 from public.attendance_day_overrides o
      where o.employee_id = p_employee_id and o.work_date = p_work_date and o.is_active
        and o.day_type in ('leave', 'mission', 'convoy', 'fundraising', 'holiday', 'rest'))
    -- حالة الحضور اليومي
    or exists (
      select 1 from public.attendance_daily ad
      where ad.employee_id = p_employee_id and ad.work_date = p_work_date and ad.status in ('on_leave', 'mission'))
    -- طلب إجازة غير ملغي وغير مرفوض
    or exists (
      select 1 from public.leave_requests lr
      join public.requests r on r.id = lr.request_id
      where lr.employee_id = p_employee_id and r.status not in ('rejected', 'cancelled')
        and p_work_date between lr.start_date and lr.end_date)
    -- إذن حضور أو تأخير مسجل
    or exists (
      select 1 from public.requests r
      where r.employee_id = p_employee_id and r.status not in ('rejected', 'cancelled')
        and r.request_type in ('late_permit', 'early_permit', 'permit', 'permission', 'errand', 'late_excuse')
        and coalesce(public.try_cast_date(r.payload->>'permitDate'), public.try_cast_date(r.payload->>'date'),
                     public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'),
                     public.try_cast_date(r.payload->>'workDate'), r.created_at::date) = p_work_date)
    -- مأمورية أو قافلة أو فاندي (سواء كانت معتمدة أو قيد المراجعة أو جارية)
    or exists (
      select 1 from public.requests r
      where r.employee_id = p_employee_id and r.status in ('approved', 'in_progress', 'pending')
        and (
          r.request_type in ('mission', 'external_mission', 'administrative_mission', 'convoy', 'field_convoy', 'fundraising', 'fandy', 'fundi')
          or coalesce(r.payload->>'missionType', r.payload->>'type') in ('mission', 'convoy', 'fundraising', 'fandy')
        )
        and p_work_date between coalesce(public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'), r.created_at::date)
                            and coalesce(public.try_cast_date(r.payload->>'endDate'), public.try_cast_date(r.payload->>'end_date'),
                                         public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'), r.created_at::date))
    -- سجل تنفيذ مأمورية جارٍ أو مكتمل لهذا اليوم
    or exists (
      select 1 from public.mission_executions me
      where me.employee_id = p_employee_id
        and me.status in ('in_progress', 'completed')
        and (me.started_at at time zone 'Africa/Cairo')::date = p_work_date);
$fn$;

comment on function public.is_lateness_excused(uuid, date) is
  '0608: استثناء التأخير لمن لديه إعفاء أو إجازة أو إذن أو مأمورية (معلقة أو جارية أو معتمدة) أو تنفيذ مأمورية.';

revoke execute on function public.is_lateness_excused(uuid, date) from public, anon, authenticated;
grant execute on function public.is_lateness_excused(uuid, date) to service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) تحديث is_employee_exempt_from_instant_penalty: فحص mission_executions
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.is_employee_exempt_from_instant_penalty(
  p_employee_id uuid,
  p_work_date date
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
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

  -- 4) فحص الإجازات في جدول leave_requests (معتمدة أو قيد المراجعة / طلب مقدم)
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

  -- 5) فحص أذونات الحضور والتأخير (late_permit, early_permit, permit, permission)
  for v_req in
    select r.id, r.request_type, r.status, r.payload
      from public.requests r
     where r.employee_id = p_employee_id
       and r.status not in ('rejected', 'cancelled')
       and r.request_type in ('late_permit', 'early_permit', 'permit', 'permission', 'errand', 'late_excuse')
       and coalesce(
         (r.payload->>'permitDate')::date,
         (r.payload->>'date')::date,
         (r.payload->>'startDate')::date,
         (r.payload->>'start_date')::date,
         (r.payload->>'workDate')::date,
         r.created_at::date
       ) = p_work_date
     order by r.created_at desc
     limit 1
  loop
    return jsonb_build_object(
      'isExempt', true,
      'category', 'permit',
      'reason', 'إذن حضور/تأخير رسمي مسجل' || case when v_req.status = 'pending' then ' (قيد المراجعة)' else ' (معتمد)' end
    );
  end loop;

  -- 6) فحص سجل تنفيذ المأموريات المباشر (in_progress أو completed لليوم)
  if exists (
    select 1 from public.mission_executions me
    where me.employee_id = p_employee_id
      and me.status in ('in_progress', 'completed')
      and (me.started_at at time zone 'Africa/Cairo')::date = p_work_date
  ) then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'mission',
      'reason', 'مأمورية عمل جارية أو مكتملة اليوم'
    );
  end if;

  -- 7) فحص طلبات المأموريات، القوافل، الفاندي، والإجازات في جدول requests
  for v_req in
    select r.id, r.request_type, r.status, r.payload
      from public.requests r
     where r.employee_id = p_employee_id
       and r.status not in ('rejected', 'cancelled')
       and (
         -- طلب إجازة
         (r.request_type in ('leave', 'casual_leave', 'annual_leave', 'sick_leave', 'unpaid_leave')
          and p_work_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                              and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
         -- مأمورية عمل
         or (r.request_type in ('mission', 'external_mission', 'administrative_mission')
             and p_work_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                                 and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
         -- قافلة ميدانية
         or (r.request_type in ('convoy', 'field_convoy')
             and p_work_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                                 and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
         -- فاندي / جمع تبرعات
         or (r.request_type in ('fundraising', 'fandy', 'fundi')
             and p_work_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                                 and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
         -- فحص داخل payload للأنواع المدمجة
         or (coalesce(r.payload->>'missionType', r.payload->>'type') in ('convoy', 'fundraising', 'fandy', 'mission')
             and p_work_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                                 and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
         -- عمل عن بعد أو تعويض
         or (r.request_type in ('remote_work', 'compensation')
             and p_work_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                                 and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
       )
     order by r.created_at desc
     limit 1
  loop
    v_loc := case
      when v_req.request_type in ('convoy', 'field_convoy') or coalesce(v_req.payload->>'missionType', '') = 'convoy' then 'قافلة ميدانية'
      when v_req.request_type in ('fundraising', 'fandy', 'fundi') or coalesce(v_req.payload->>'missionType', '') = 'fundraising' then 'فاندي (جمع تبرعات)'
      when v_req.request_type in ('mission', 'external_mission', 'administrative_mission') then 'مأمورية عمل'
      when v_req.request_type = 'remote_work' then 'عمل عن بعد'
      when v_req.request_type = 'compensation' then 'يوم راحة تعويضي'
      else 'إجازة رسمية'
    end;

    return jsonb_build_object(
      'isExempt', true,
      'category', v_req.request_type,
      'reason', v_loc || case when v_req.status = 'pending' then ' (طلب مسجل قيد المراجعة)' else ' (معتمدة)' end
    );
  end loop;

  -- 8) فحص جدول مهام العمل والمأموريات والقوافل work_assignments
  select wa.assignment_type, wa.title into v_wa
    from public.work_assignments wa
   where wa.responsible_employee_id = p_employee_id
     and wa.status in ('APPROVED', 'IN_PROGRESS', 'PENDING')
     and p_work_date between wa.start_at::date and wa.end_at::date
   limit 1;

  if v_wa.assignment_type is not null then
    v_loc := case
      when upper(v_wa.assignment_type) in ('CONVOY', 'FIELD_CONVOY') then 'قافلة ميدانية'
      when upper(v_wa.assignment_type) in ('FUNDRAISING', 'FANDY') then 'فاندي (جمع تبرعات)'
      when upper(v_wa.assignment_type) in ('MISSION', 'EXTERNAL') then 'مأمورية عمل'
      else 'مهمة عمل رسمية (' || coalesce(v_wa.title, v_wa.assignment_type) || ')'
    end;

    return jsonb_build_object(
      'isExempt', true,
      'category', 'assignment',
      'reason', v_loc || ' مكلف بها رسمياً'
    );
  end if;

  -- 9) فحص حالة الحضور اليومي في attendance_daily
  select ad.status into v_att
    from public.attendance_daily ad
   where ad.employee_id = p_employee_id
     and ad.work_date = p_work_date
   limit 1;

  if v_att.status in ('on_leave', 'mission', 'excused', 'holiday', 'weekend') then
    return jsonb_build_object(
      'isExempt', true,
      'category', v_att.status,
      'reason', case v_att.status
        when 'on_leave' then 'مسجل في عطلة/إجازة رسمية'
        when 'mission'  then 'مسجل في مأمورية عمل'
        when 'excused'  then 'معذور رسمياً في سجل الحضور'
        when 'holiday'  then 'عطلة رسمية'
        when 'weekend'  then 'راحة أسبوعية'
        else v_att.status
      end
    );
  end if;

  -- الموظف غير معفى
  return jsonb_build_object(
    'isExempt', false,
    'category', 'none',
    'reason', null
  );
end;
$$;

grant execute on function public.is_employee_exempt_from_instant_penalty(uuid, date) to authenticated, anon, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) تحديث submit_my_request: إلغاء فوري للغرامات وتصفير دقائق التأخير
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.submit_my_request(
  p_request_type text,
  p_title text,
  p_reason text,
  p_payload jsonb default '{}'::jsonb,
  p_idempotency_key uuid default null
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me                  uuid := public.current_employee_id();
  v_today               date := (now() at time zone 'Africa/Cairo')::date;
  v_row                 public.requests;
  v_def                 public.workflow_definitions;
  v_prev_id             uuid;
  v_step_id             uuid;
  v_manager             uuid;
  v_first_approver      uuid;
  v_dep_manager         uuid;
  v_label               text;
  v_leave_type_code     text;
  v_day_mark            boolean;
  v_start_date          date;
  v_end_date            date;
  v_work_date           date;
  v_existing_req_status text;
  v_existing_req_id     uuid;
  v_geofence_id         uuid;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك الحالي' using errcode = '42501';
  end if;

  if p_request_type is null or length(trim(p_request_type)) = 0 then
    raise exception 'نوع الطلب مطلوب' using errcode = '22023';
  end if;
  if p_title is null or length(trim(p_title)) < 3 then
    raise exception 'عنوان الطلب يجب أن لا يقل عن 3 أحرف' using errcode = '22023';
  end if;
  if p_reason is null or length(trim(p_reason)) < 3 then
    raise exception 'سبب الطلب يجب أن لا يقل عن 3 أحرف' using errcode = '22023';
  end if;

  -- استخراج التواريخ
  v_day_mark := coalesce((p_payload->>'dayMark')::boolean, false);
  v_start_date := coalesce(nullif(p_payload->>'startDate', '')::date, nullif(p_payload->>'permitDate', '')::date);
  v_end_date := coalesce(nullif(p_payload->>'endDate', '')::date, v_start_date);
  v_work_date := coalesce(v_start_date, v_today);

  -- التحقق من التعارض للطلبات اليومية
  if v_day_mark and v_start_date is not null then
    select r.id, r.status into v_existing_req_id, v_existing_req_status
      from public.requests r
     where r.employee_id = v_me
       and r.status in ('pending', 'approved')
       and (
         (r.payload->>'startDate')::date = v_start_date
         or (r.payload->>'permitDate')::date = v_start_date
         or r.id in (
           select lr.request_id from public.leave_requests lr
            where lr.employee_id = v_me and v_start_date between lr.start_date and lr.end_date
         )
       )
     limit 1;

    if v_existing_req_id is not null then
      raise exception 'يوجد طلب سابق (%) مسجل بالفعل لهذا اليوم (حالة الطلب: %)',
        v_existing_req_id,
        case v_existing_req_status when 'pending' then 'قيد المراجعة' else 'معتمد' end
        using errcode = '23505';
    end if;
  end if;

  -- فحص مفتاح عدم التكرار (Idempotency)
  if p_idempotency_key is not null then
    select id into v_prev_id from public.requests
     where idempotency_key = p_idempotency_key and employee_id = v_me
     limit 1;
    if v_prev_id is not null then
      select * into v_row from public.requests where id = v_prev_id;
      return v_row;
    end if;
  end if;

  -- تحديد المدير المباشر
  select mr.manager_employee_id into v_manager
    from public.manager_relations mr
   where mr.employee_id = v_me
     and mr.relation_type = 'primary'
     and (mr.effective_to is null or mr.effective_to >= current_date)
   order by mr.effective_from desc nulls last
   limit 1;

  if v_manager is null then
    select e.direct_manager_id into v_manager
      from public.employees e where e.id = v_me;
  end if;

  -- تعريف سير العمل
  select * into v_def from public.workflow_definitions
   where entity_type = 'request' and is_active = true
   order by (code = p_request_type) desc, is_default desc
   limit 1;

  -- إدراج الطلب
  insert into public.requests (
    employee_id, manager_employee_id, request_type, title, reason,
    payload, status, workflow_status, current_step_order,
    idempotency_key, created_by
  ) values (
    v_me, v_manager, p_request_type, trim(p_title), trim(p_reason),
    coalesce(p_payload, '{}'::jsonb), 'pending', 'submitted', 1,
    p_idempotency_key, auth.uid()
  ) returning * into v_row;

  -- خطوات سير العمل
  if v_def.id is not null then
    insert into public.request_steps (
      request_id, workflow_step_id, step_order, name_ar, step_type,
      assignee_employee_id, assignee_role_slug, status, sla_hours,
      due_at, escalation_deadline, created_by
    )
    select
      v_row.id, ws.id, ws.step_order, ws.name_ar, ws.step_type,
      case
        when ws.approver_type = 'specific_employee' then ws.approver_employee_id
        when ws.approver_type = 'direct_manager' then v_manager
        when ws.approver_type = 'department_manager' then coalesce(v_dep_manager, v_manager)
        else null
      end,
      ws.approver_role_slug,
      case when ws.step_order = 1 then 'active' else 'pending' end,
      ws.sla_hours,
      case when ws.step_order = 1 then now() + make_interval(hours => coalesce(ws.sla_hours, 48)) else null end,
      case when ws.step_order = 1 and ws.escalate_after_hours is not null
           then now() + make_interval(hours => ws.escalate_after_hours) else null end,
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

  -- توثيق الإجراء في request_actions
  insert into public.request_actions (
    request_id, actor_employee_id, action, from_status, to_status, comment, created_by
  ) values (
    v_row.id, v_me, 'submit', null, 'pending', trim(p_reason), auth.uid()
  );

  -- إشعار صاحب الاعتماد
  v_label := format('%s — %s', public.request_type_label(p_request_type), p_title);
  select s.assignee_employee_id into v_first_approver
    from public.request_steps s
   where s.request_id = v_row.id and s.status = 'active'
   order by s.step_order limit 1;

  if v_first_approver is null then
    v_first_approver := v_manager;
  end if;

  if v_first_approver is not null and v_first_approver <> v_me then
    perform public.notify_employee(
      v_first_approver,
      'طلب جديد بانتظار مراجعتك',
      v_label,
      'request', 'high', 'request', v_row.id,
      jsonb_build_object('request_id', v_row.id, 'request_type', p_request_type, 'deepLink', '/requests/' || v_row.id)
    );
  end if;

  -- التنفيذ الفوري للإجازة العارضة المستوفية للشروط
  if p_request_type = 'leave' and not v_day_mark then
    v_leave_type_code := p_payload->>'leaveType';
    if v_leave_type_code = 'casual' then
      update public.requests
         set status = 'approved',
             workflow_status = 'completed',
             decided_at = now(),
             decided_by = v_me,
             updated_at = now()
       where id = v_row.id
       returning * into v_row;

      update public.request_steps
         set status = 'approved', acted_at = now(), acted_by = v_me, updated_at = now()
       where request_id = v_row.id;

      update public.workflow_instances
         set status = 'completed', completed_at = now(), updated_at = now()
       where request_id = v_row.id;

      insert into public.request_actions (
        request_id, actor_employee_id, action, from_status, to_status, comment, metadata, created_by
      ) values (
        v_row.id, v_me, 'approve', 'pending', 'approved',
        'تنفيذ مباشر للإجازة العارضة (لا تستوجب موافقة المدير المباشر)',
        jsonb_build_object('immediate', true, 'leaveType', 'casual'), auth.uid());
    end if;
  end if;

  -- ── 0608: بدء المأمورية فور طلبها لليوم الحالي وتسجيل الحضور وإلغاء الغرامات ──
  if p_request_type in ('mission', 'convoy', 'fundraising') and not v_day_mark and v_start_date = v_today then
    -- 1. تسجيل بدء المأمورية في mission_executions
    insert into public.mission_executions(
      request_id, employee_id, status, started_at
    ) values (
      v_row.id, v_me, 'in_progress', coalesce(v_row.created_at, now())
    ) on conflict (request_id) do update
      set status = 'in_progress',
          started_at = coalesce(public.mission_executions.started_at, v_row.created_at, now()),
          updated_at = now();

    -- 2. تثبيت الحضور اليومي كـ present وتصفير أي تأخير
    insert into public.attendance_daily (
      employee_id, work_date, status, first_check_in, late_minutes, updated_at
    ) values (
      v_me, v_today, 'present', coalesce(v_row.created_at, now()), 0, now()
    ) on conflict (employee_id, work_date) do update
      set first_check_in = coalesce(public.attendance_daily.first_check_in, excluded.first_check_in),
          status = 'present',
          late_minutes = 0,
          updated_at = now();

    -- 3. تصفير دقائق التأخير في أحداث البصمة لليوم
    update public.attendance_events
       set late_minutes = 0
     where employee_id = v_me
       and (event_at at time zone 'Africa/Cairo')::date = v_today;

    -- 4. إلغاء فوري لأي غرامات حضور معلقة لليوم
    update public.instant_attendance_penalties
       set status = 'cancelled',
           cancelled_reason = 'إلغاء تلقائي: بدء مأمورية عمل لليوم',
           notes = coalesce(notes || ' | ', '') || 'إلغاء تلقائي: بدء مأمورية عمل لليوم',
           updated_at = now()
     where employee_id = v_me
       and work_date = v_today
       and status in ('pending_payment', 'doubled');

    -- 5. إدراج حدث بصمة دخول آلي من المأمورية إن لم يكن موجوداً
    if not exists (
      select 1 from public.attendance_events
       where employee_id = v_me
         and (event_at at time zone 'Africa/Cairo')::date = v_today
         and event_type = 'CHECK_IN'
         and status in ('accepted', 'adjusted')
    ) then
      select id into v_geofence_id
        from public.geofences where is_active = true
        order by created_at limit 1;

      insert into public.attendance_events (
        employee_id, geofence_id, event_type, event_at, status,
        requires_review, verification_status, server_verified,
        is_mock_location, source, notes, late_minutes
      ) values (
        v_me, v_geofence_id, 'CHECK_IN', coalesce(v_row.created_at, now()), 'adjusted',
        true, 'server_verified', true,
        false, 'mission_auto', 'auto_check_in_from_mission_creation', 0
      );
    end if;
  end if;

  return v_row;
end;
$$;

revoke all on function public.submit_my_request(text, text, text, jsonb, uuid) from public, anon;
grant execute on function public.submit_my_request(text, text, text, jsonb, uuid) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4) تحديث decide_request: إحكام التعامل مع المأموريات والقوافل والفاندي
-- ─────────────────────────────────────────────────────────────────────────────
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

  -- 0608: إذا كانت مأمورية أو قافلة أو فاندي وتم اعتمادها → تثبيت تنفيذ المأمورية بأمان
  if v_final_status = 'approved' and v_req.request_type in ('mission', 'convoy', 'fundraising') then
    insert into public.mission_executions(request_id, employee_id, status, started_at)
    values (v_req.id, v_req.employee_id, 'in_progress', coalesce(v_req.created_at, now()))
    on conflict (request_id) do update
      set status = case when public.mission_executions.status = 'completed' then 'completed' else 'in_progress' end,
          started_at = coalesce(public.mission_executions.started_at, v_req.created_at, now()),
          updated_at = now();
  end if;

  -- 0608: إذا تم رفض مأمورية وكانت جارية → إلغاء تنفيذها
  if v_final_status = 'rejected' and v_req.request_type in ('mission', 'convoy', 'fundraising') then
    update public.mission_executions
       set status = 'cancelled',
           updated_at = now()
     where request_id = p_request_id
       and status = 'in_progress';
  end if;

  -- إذا كان تصحيح حضور وتم اعتماده → تطبيق التصحيح
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

  -- إذا كان تصحيح حضور وتم رفضه → رفض التصحيح
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
comment on function public.decide_request(uuid, text, text) is
  '0608: قرار على طلب — مع دعم مأموريات وقوافل وفاندي وتصحيحات الحضور وإلغاء التنفيذ عند الرفض';

commit;
