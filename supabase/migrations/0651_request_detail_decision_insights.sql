-- ============================================================================
-- 0651: «سياق القرار» في تفاصيل الطلب للمعتمِد (insights)
-- ============================================================================
-- المعتمِد يقرر بلا سياق: لا يرى رصيد الموظف ولا من غاب من زملاء إدارته في
-- الفترة نفسها ولا كثرة طلباته. تُضاف «insights» لغير صاحب الطلب (من اجتاز شرط
-- الوصول: مدير/موارد بشرية/تشغيل/إدارة):
--   • leaveBalance: المتاح والمحجوز والمستهلك من نوع الإجازة المطلوب (سنة الطلب).
--   • month: طلباته الأخرى هذا الشهر حسب النوع والحالة.
--   • teamSize / teamAway: زملاء إدارته النشطون، ومن منهم في إجازة/مأمورية/
--     قافلة/فاندي (معتمدة أو قيد المراجعة) متداخلة مع فترة الطلب.
-- تواريخ الحمولة تُحلَّل بحماية CASE + regex حتى لا يُسقط تاريخٌ تالف العرض كله.
-- بقية الدالة مطابقة حرفيًا لـ 0646 (المطبقة)؛ الاستبدال كنوني كامل.

create or replace function public.get_mobile_request_detail(p_request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_me                 uuid := public.current_employee_id();
  v_full               boolean := public.current_is_full_access();
  v_roles              text[];
  v_request            public.requests;
  v_employee           public.employees;
  v_department         text;
  v_job_title          text;
  v_flags              jsonb;
  v_current_step       uuid;
  v_steps              jsonb;
  v_history            jsonb;
  v_attachments        jsonb;
  v_context            jsonb;
  v_decided_by         text;
  v_cancelled_by       text;
  v_decision_actor     text;
  v_decision_mode      text;
  v_decision_on_behalf boolean;
  v_execution          jsonb;
  v_insights           jsonb;
  v_start              date;
  v_end                date;
begin
  select * into v_request from public.requests where id = p_request_id;
  if v_request.id is null then
    return null;
  end if;

  select coalesce(array_agg(distinct r.slug), '{}'::text[]) into v_roles
    from public.user_roles ur
    join public.roles r on r.id = ur.role_id
   where ur.user_id = auth.uid()
     and (ur.effective_from is null or ur.effective_from <= now())
     and (ur.effective_to is null or ur.effective_to > now());

  -- coalesce: حساب بلا موظف كان يمرّ لأن not (null or false) = null
  if not coalesce(
       v_request.employee_id = v_me
    or v_request.manager_employee_id = v_me
    or exists (
         select 1 from public.manager_relations mr
          where mr.employee_id = v_request.employee_id
            and mr.manager_employee_id = v_me
            and mr.relation_type = 'primary'
            and mr.effective_from <= current_date
            and (mr.effective_to is null or mr.effective_to >= current_date))
    or exists (
         select 1 from public.request_steps s
          where s.request_id = v_request.id and s.assignee_employee_id = v_me)
    or v_full
    or v_roles && array['admin', 'super-admin', 'executive', 'executive-director',
                        'general-manager', 'hr-manager', 'operations-manager-1']
    or public.can_access_employee(v_request.employee_id, 'requests.request.approve')
    or public.can_access_employee(v_request.employee_id, 'requests.request.read')
    or public.can_access_employee(v_request.employee_id, 'requests.read')
    or public.can_access_employee(v_request.employee_id, 'requests.approve'),
    false
  ) then
    raise exception 'request access denied' using errcode = '42501';
  end if;

  select * into v_employee from public.employees where id = v_request.employee_id;
  select d.name into v_department from public.departments d where d.id = v_employee.department_id;
  select jt.name into v_job_title from public.job_titles jt where jt.id = v_employee.job_title_id;

  v_flags := public.request_decision_flags(v_request, v_me, v_full, v_roles);

  if v_request.status = 'pending' then
    select s.id into v_current_step
      from public.request_steps s
     where s.request_id = v_request.id
       and s.status in ('active', 'escalated', 'pending')
     order by (s.status = 'active') desc, s.step_order
     limit 1;
  end if;

  -- المراحل: الفاعل والتعليق للخطوة التي بُتّ فيها فقط (السحب يضع فاعلًا على
  -- الخطوات المتخطاة)، والإرجاع يُسجَّل rejected على الخطوة فيُميَّز هنا.
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', s.id,
           'order', s.step_order,
           'name', s.name_ar,
           'roleSlug', s.assignee_role_slug,
           'status', s.status,
           'decision', case
               when s.status = 'approved' then 'approved'
               when s.status = 'rejected' and v_request.status = 'returned' then 'returned'
               when s.status = 'rejected' then 'rejected'
             end,
           'comment', case when s.status in ('approved', 'rejected') then nullif(trim(s.comment), '') end,
           'decidedAt', case when s.status in ('approved', 'rejected') then s.acted_at end,
           'actorName', case when s.status in ('approved', 'rejected') then actor.full_name_ar end,
           'dueAt', s.due_at,
           'escalatedAt', s.escalated_at,
           'isCurrent', s.id is not distinct from v_current_step
         ) order by s.step_order), '[]'::jsonb)
    into v_steps
    from public.request_steps s
    left join public.employees actor on actor.id = s.acted_by
   where s.request_id = p_request_id;

  -- سجل الإجراءات: التصعيد الآلي يتكرر كل دورة مهلة — يُعرض أوله في كل دورة
  -- رفع مع عدد التكرار، ونصوصه الآلية (بعضها تالف تاريخيًا) لا تُرجَع.
  with base as (
    select a.*,
           sum((a.action = 'submit')::int) over (
             order by a.created_at, a.id
             rows between unbounded preceding and current row) as cycle_no
      from public.request_actions a
     where a.request_id = p_request_id
       and a.action in ('submit', 'approve', 'reject', 'return', 'request_changes',
                        'cancel', 'withdraw', 'escalate', 'expire', 'reassign')
  ),
  ranked as (
    select b.*,
           row_number() over w as rn,
           count(*) over w as cnt
      from base b
    window w as (
      partition by b.cycle_no, b.action,
                   coalesce(b.metadata->>'targetRole', b.metadata->>'escalatedToRole', '')
      order by b.created_at, b.id
      rows between unbounded preceding and unbounded following)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'action', x.action,
           'at', x.created_at,
           'actorName', case when x.action in ('escalate', 'expire') then null else actor.full_name_ar end,
           'comment', case when x.action in ('approve', 'reject', 'return', 'request_changes',
                                             'cancel', 'withdraw', 'reassign')
                           then nullif(trim(x.comment), '') end,
           'stepOrder', st.step_order,
           'stepName', st.name_ar,
           'stepRole', st.assignee_role_slug,
           'targetRole', coalesce(x.metadata->>'targetRole', x.metadata->>'escalatedToRole'),
           'repeat', case when x.action = 'escalate' then x.cnt end,
           'isResubmit', x.action = 'submit' and x.from_status in ('rejected', 'returned')
         ) order by x.created_at, x.id), '[]'::jsonb)
    into v_history
    from ranked x
    left join public.employees actor on actor.id = x.actor_employee_id
    left join public.request_steps st on st.id = x.request_step_id
   where x.action <> 'escalate' or x.rn = 1;

  select coalesce(jsonb_agg(jsonb_build_object(
           'path', a.storage_path, 'mimeType', a.mime, 'sizeBytes', a.size_bytes
         ) order by a.created_at), '[]'::jsonb)
    into v_attachments
    from public.attachments a
   where a.entity_type = 'request' and a.entity_id = p_request_id;

  -- البديل والتعارضات (حُذفت منذ 0628). للدالة تحقق وصول أضيق؛ عند رفضها لا
  -- يسقط عرض الطلب كله.
  begin
    v_context := public.get_request_decision_context(p_request_id);
  exception when others then
    v_context := null;
  end;

  select e.full_name_ar into v_decided_by from public.employees e where e.id = v_request.decided_by;
  select e.full_name_ar into v_cancelled_by from public.employees e where e.id = v_request.cancelled_by;

  select e.full_name_ar, a.metadata->>'decisionMode',
         coalesce((a.metadata->>'onBehalfOfExecutive')::boolean, false)
    into v_decision_actor, v_decision_mode, v_decision_on_behalf
    from public.request_actions a
    left join public.employees e on e.id = a.actor_employee_id
   where a.request_id = p_request_id and a.action in ('approve', 'reject', 'return')
   order by a.created_at desc
   limit 1;

  -- سياق القرار لغير صاحب الطلب (اجتاز شرط الوصول أعلاه: مدير/موارد بشرية/
  -- تشغيل/إدارة). التواريخ تُحلَّل بحماية CASE حتى لا يُسقط تاريخ تالف العرض.
  if not coalesce(v_request.employee_id = v_me, false) then
    v_start := case
      when coalesce(v_request.payload->>'startDate', v_request.payload->>'permitDate') ~ '^\d{4}-\d{2}-\d{2}$'
      then coalesce(v_request.payload->>'startDate', v_request.payload->>'permitDate')::date
    end;
    v_end := case
      when v_request.payload->>'endDate' ~ '^\d{4}-\d{2}-\d{2}$'
      then (v_request.payload->>'endDate')::date
      else v_start
    end;

    v_insights := jsonb_build_object(
      'leaveBalance', case when v_request.request_type = 'leave' then (
        select jsonb_build_object(
                 'name', lt.name_ar,
                 'available', coalesce(a.opening_units + a.accrued_units + a.adjusted_units
                                       + a.carryover_units - a.consumed_units - a.reserved_units, 0),
                 'reserved', coalesce(a.reserved_units, 0),
                 'consumed', coalesce(a.consumed_units, 0))
          from public.leave_types lt
          left join public.leave_balance_accounts a
            on a.leave_type_id = lt.id
           and a.employee_id = v_request.employee_id
           and a.balance_year = extract(year from coalesce(v_start,
                 (now() at time zone 'Africa/Cairo')::date))::int
         where lt.code = v_request.payload->>'leaveType'
         limit 1
      ) end,
      'month', (
        select jsonb_build_object(
                 'total', count(*),
                 'missions', count(*) filter (where r.request_type in ('mission', 'convoy', 'fundraising')),
                 'leaves', count(*) filter (where r.request_type = 'leave'),
                 'permits', count(*) filter (where r.request_type in ('late_permit', 'early_permit')),
                 'rejected', count(*) filter (where r.status in ('rejected', 'returned')),
                 'pending', count(*) filter (where r.status = 'pending'))
          from public.requests r
         where r.employee_id = v_request.employee_id
           and r.id <> v_request.id
           and r.status <> 'cancelled'
           and r.created_at >= (date_trunc('month', now() at time zone 'Africa/Cairo')
                                at time zone 'Africa/Cairo')
      ),
      'teamSize', (
        select count(*) from public.employees e
         where v_employee.department_id is not null
           and e.department_id = v_employee.department_id
           and e.id <> v_request.employee_id
           and e.is_active and not e.is_deleted
      ),
      'teamAway', case when v_start is not null and v_employee.department_id is not null then (
        select coalesce(jsonb_agg(jsonb_build_object(
                 'name', t.full_name_ar, 'type', t.request_type, 'status', t.status)
                 order by t.status, t.full_name_ar), '[]'::jsonb)
          from (
            select distinct on (e.id) e.full_name_ar, r.request_type, r.status
              from public.requests r
              join public.employees e on e.id = r.employee_id
             where e.department_id = v_employee.department_id
               and e.id <> v_request.employee_id
               and e.is_active and not e.is_deleted
               and r.status in ('approved', 'pending')
               and r.request_type in ('leave', 'mission', 'convoy', 'fundraising')
               and (case when r.payload->>'startDate' ~ '^\d{4}-\d{2}-\d{2}$'
                         then (r.payload->>'startDate')::date end) <= v_end
               and (case when coalesce(r.payload->>'endDate', r.payload->>'startDate') ~ '^\d{4}-\d{2}-\d{2}$'
                         then coalesce(r.payload->>'endDate', r.payload->>'startDate')::date end) >= v_start
             order by e.id, (r.status = 'approved') desc
          ) t
      ) end
    );
  end if;

  if v_request.request_type in ('mission', 'convoy', 'fundraising') then
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
    'employeePhotoUrl', v_employee.photo_url,
    'employeeDepartment', v_department,
    'employeeJobTitle', v_job_title,
    'title', v_request.title,
    'reason', v_request.reason,
    'status', v_request.status,
    'workflowStatus', v_request.workflow_status,
    'payload', coalesce(v_request.payload, '{}'::jsonb),
    'currentStepOrder', v_request.current_step_order,
    'decisionDueAt', v_request.decision_due_at,
    'createdAt', v_request.created_at,
    'updatedAt', v_request.updated_at,
    'decidedAt', v_request.decided_at,
    'decidedByName', v_decided_by,
    'cancelledAt', v_request.cancelled_at,
    'cancelReason', v_request.cancel_reason,
    'cancelledByName', v_cancelled_by,
    'isMine', coalesce(v_request.employee_id = v_me, false),
    'canDecide', coalesce((v_flags->>'canDecide')::boolean, false),
    'awaitingMe', coalesce((v_flags->>'awaitingMe')::boolean, false),
    'canCancel', v_request.status = 'pending' and coalesce(v_request.employee_id = v_me, false),
    -- عقد 0452: المالك على طلب مرفوض/مُعاد من الأنواع القابلة لإعادة الرفع
    'canResubmit', v_request.status in ('rejected', 'returned')
                   and coalesce(v_request.employee_id = v_me, false)
                   and v_request.request_type in ('leave', 'mission', 'convoy', 'fundraising',
                                                  'late_permit', 'early_permit'),
    'steps', v_steps,
    'history', v_history,
    'attachments', v_attachments,
    'decisionContext', v_context,
    'insights', v_insights,
    'decisionActorName', v_decision_actor,
    'decisionMode', v_decision_mode,
    'decisionOnBehalfOfExecutive', v_decision_on_behalf,
    'missionExecution', v_execution
  );
end;
$$;

comment on function public.get_mobile_request_detail(uuid) is
  '0651: تفاصيل الطلب (عقد 0646) + insights للمعتمِد: رصيد الإجازة، طلبات الشهر، زملاء الإدارة خارج المقر في الفترة نفسها.';
revoke all on function public.get_mobile_request_detail(uuid) from public, anon;
grant execute on function public.get_mobile_request_detail(uuid) to authenticated;
