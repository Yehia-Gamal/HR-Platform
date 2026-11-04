-- 0722_funday_entertainment_day_refinement.sql
-- تهيئة وضبط طلبات الفاندي (اليوم الترفيهي للموظفين):
-- 1. الفاندي هو يوم ترفيهي للموظفين لقضاء عطلة على حساب العمل يبدأ تلقائياً من بداية اليوم ولا يحتاج تنفيذاً ميدانياً.
-- 2. إزالة mission_executions للفاندي تماماً (حصر التنفيذ في المأموريات والقوافل فقط).
-- 3. جعل سبب الطلب اختيارياً للفاندي مع تعيين نص افتراضي «يوم ترفيهي للموظفين لقضاء عطلة على حساب العمل» في حال تركه فارغاً.
-- 4. تنظيف أي سجلات mission_executions قديمة مرتبطة بطلبات فاندي.

-- ─── 0. تنظيف سجلات التنفيذ القديمة المرتبطة بالفاندي ──────────────────────────
delete from public.mission_executions
 where request_id in (
   select id from public.requests where request_type in ('fundraising', 'fandy', 'fundi')
 );

-- ─── 1. تحديث submit_my_request ─────────────────────────────────────────────
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
  v_me                    uuid := public.current_employee_id();
  v_manager               uuid;
  v_row                   public.requests;
  v_payload               jsonb := coalesce(p_payload, '{}'::jsonb);
  v_today                 date := (now() at time zone 'Africa/Cairo')::date;
  v_min_allowed_date      date := (v_today - interval '365 days')::date;
  v_day_mark              boolean := coalesce((v_payload->>'dayMark')::boolean, false);
  v_start_date            date;
  v_end_date              date;
  v_permit_date           date;
  v_minutes               integer;
  v_leave_type            text;
  v_leave_type_id         uuid;
  v_affects               boolean;
  v_days                  numeric;
  v_substitute            uuid;
  v_correction_date       date;
  v_correction_type       text;
  v_corrected_time        text;
  v_permit_kind           text;
  v_is_clinic             boolean := false;
  v_effective_reason      text;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  v_is_clinic := public.is_clinic_team_member(v_me) and v_me <> '4120ce3a-8999-453e-8d9d-acd8f3b5f04c';

  -- حظر المأموريات والقوافل والأنشطة الميدانية على طاقم العيادات
  if v_is_clinic and p_request_type in ('mission', 'convoy', 'fundraising') then
    raise exception 'طلبات المأموريات والقوافل والأنشطة الميدانية غير متاحة لطاقم العيادات' using errcode = '22023';
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

  if p_request_type not in (
    'leave','mission','convoy','fundraising',
    'late_permit','early_permit','attendance_correction',
    'attendance_permit','shift_change','generic'
  ) then
    raise exception 'نوع طلب غير صالح' using errcode = '22023';
  end if;

  -- معالجة سبب الطلب: الفاندي لا يشترط سبباً وله قيمة افتراضية
  v_effective_reason := trim(coalesce(p_reason, ''));
  if p_request_type = 'fundraising' and (v_effective_reason = '' or length(v_effective_reason) < 3) then
    v_effective_reason := 'يوم ترفيهي للموظفين لقضاء عطلة على حساب العمل';
  end if;

  if length(trim(coalesce(p_title,''))) < 3
     or length(v_effective_reason) < 3 then
    raise exception 'العنوان وسبب الطلب مطلوبان (3 أحرف على الأقل)' using errcode = '22023';
  end if;

  if v_day_mark and p_request_type in ('leave','mission','convoy','fundraising') then
    v_start_date := nullif(v_payload->>'startDate', '')::date;
    v_end_date := nullif(v_payload->>'endDate', '')::date;
    if v_start_date is null or v_end_date is null then
      raise exception 'تعديل حالة اليوم يتطلب تاريخاً صالحاً' using errcode = '22023';
    end if;
    if v_end_date <> v_start_date then
      raise exception 'تعديل حالة اليوم يكون ليوم واحد فقط' using errcode = '22023';
    end if;
    if v_start_date < v_min_allowed_date then
      raise exception 'تعديل حالة اليوم متاح للأيام خلال آخر 365 يوماً فقط' using errcode = '22023';
    end if;
    if v_start_date > v_today then
      raise exception 'لا يمكن تعديل حالة الأيام المستقبلية' using errcode = '22023';
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
        if v_leave_type = 'unpaid' then
          raise exception 'لا يمكن للموظف طلب إجازة بدون راتب ذاتياً؛ تُمنح فقط بقرار من إدارة الموارد البشرية' using errcode = '22023';
        end if;
        if v_leave_type not in ('annual','casual','sick','weekly_rest_comp') then
          raise exception 'نوع إجازة غير مدعوم' using errcode = '22023';
        end if;
        if v_start_date is null or v_end_date is null then
          raise exception 'تاريخا بداية ونهاية الإجازة مطلوبان' using errcode = '22023';
        end if;
        if v_end_date < v_start_date then
          raise exception 'تاريخ النهاية يجب ألا يسبق البداية' using errcode = '22023';
        end if;
        if not v_day_mark and v_start_date < v_min_allowed_date then
          raise exception 'لا يمكن تقديم إجازة تسبق أكثر من سنة' using errcode = '22023';
        end if;

        select id, affects_balance into v_leave_type_id, v_affects
        from public.leave_types where code = v_leave_type and is_active = true;
        if v_leave_type_id is null then
          raise exception 'نوع الإجازة غير نشط أو غير معروف: %', v_leave_type using errcode = '22023';
        end if;
        v_days := (v_end_date - v_start_date) + 1;
        v_payload := v_payload || jsonb_build_object(
          'leaveType', v_leave_type,
          'startDate', v_start_date,
          'endDate', v_end_date,
          'days', v_days,
          'immediate', (v_leave_type = 'casual' and v_start_date >= v_today));

      -- ─── مأمورية ───────────────────────────────────────────────────────────
      when 'mission' then
        v_start_date := coalesce(nullif(v_payload->>'startDate', '')::date, v_today);
        v_end_date   := coalesce(nullif(v_payload->>'endDate', '')::date, v_start_date);
        if v_start_date < v_min_allowed_date then
          raise exception 'لا يمكن تقديم مأمورية تسبق أكثر من سنة' using errcode = '22023';
        end if;
        if v_end_date < v_start_date then
          raise exception 'تاريخ نهاية المأمورية يجب ألا يسبق البداية' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'startDate', v_start_date,
          'endDate', v_end_date,
          'location', coalesce(nullif(trim(coalesce(v_payload->>'location', '')), ''), 'مأمورية عمل خارجية'),
          'days', ((v_end_date - v_start_date) + 1),
          'startTime', coalesce(nullif(trim(coalesce(v_payload->>'startTime','')),''), to_char(now() at time zone 'Africa/Cairo', 'HH24:MI')),
          'startedAtCreation', case when v_day_mark then false else true end);

      -- ─── قافلة / فاندي ───────────────────────────────────────────────────
      when 'convoy', 'fundraising' then
        v_start_date := nullif(v_payload->>'startDate', '')::date;
        v_end_date := nullif(v_payload->>'endDate', '')::date;
        if v_start_date is null or v_end_date is null then
          raise exception 'تاريخا بداية ونهاية التكليف مطلوبان' using errcode = '22023';
        end if;
        if v_end_date < v_start_date then
          raise exception 'تاريخ النهاية يجب ألا يسبق البداية' using errcode = '22023';
        end if;
        if v_start_date < v_min_allowed_date then
          raise exception 'لا يمكن تقديم تكليف يسبق أكثر من سنة' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'startDate', v_start_date,
          'endDate', v_end_date,
          'location', coalesce(
            nullif(trim(coalesce(v_payload->>'location', '')), ''),
            case when p_request_type = 'convoy' then 'قافلة ميدانية' else 'يوم ترفيهي للموظفين' end
          ),
          'days', ((v_end_date - v_start_date) + 1));

      -- ─── إذن تأخير صباحي ──────────────────────────────────────────────────
      when 'late_permit' then
        v_permit_date := nullif(v_payload->>'permitDate', '')::date;
        v_minutes := nullif(v_payload->>'minutes', '')::integer;
        if v_permit_date is null then
          raise exception 'تاريخ الإذن مطلوب' using errcode = '22023';
        end if;
        if v_permit_date < v_min_allowed_date then
          raise exception 'تاريخ الإذن يسبق أكثر من سنة' using errcode = '22023';
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
        if v_permit_date < v_min_allowed_date then
          raise exception 'تاريخ الإذن يسبق أكثر من سنة' using errcode = '22023';
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
        if v_permit_date < v_min_allowed_date then
          raise exception 'تاريخ الإذن يسبق أكثر من سنة' using errcode = '22023';
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
        if v_correction_date < v_min_allowed_date then
          raise exception 'تاريخ التصحيح يسبق أكثر من سنة' using errcode = '22023';
        end if;
        if v_correction_type not in ('check_in','check_out','both','missing_check_in','missing_check_out') then
          raise exception 'نوع التصحيح يجب أن يكون حضور أو انصراف أو كلاهما' using errcode = '22023';
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
    v_effective_reason,
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

    if v_leave_type = 'casual' and v_start_date >= v_today then
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

  -- إنشاء صف mission_executions للمأمورية والقافلة فقط إذا بدأت اليوم
  -- الفاندي لا يحتاج إلى mission_executions لأنه يوم ترفيهي يبدأ تلقائياً
  if p_request_type in ('mission', 'convoy') and not v_day_mark and v_start_date = v_today then
    insert into public.mission_executions(
      request_id, employee_id, status, started_at, created_by)
    values(
      v_row.id, v_me, 'IN_PROGRESS', now(), auth.uid())
    on conflict (request_id) do nothing;
  end if;

  return v_row;
end;
$$;

revoke all on function public.submit_my_request(text, text, text, jsonb, uuid) from public, anon;
grant execute on function public.submit_my_request(text, text, text, jsonb, uuid) to authenticated, service_role;

-- ─── 2. تحديث get_mobile_request_detail ─────────────────────────────────────
create or replace function public.get_mobile_request_detail(p_request_id uuid)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $$
declare
  v_me                 uuid := public.current_employee_id();
  v_full               boolean := public.current_is_full_access();
  v_roles              text[];
  v_is_admin_or_hr     boolean := false;
  v_request            public.requests;
  v_employee           public.employees;
  v_department         text;
  v_job_title          text;
  v_flags              jsonb;
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

  v_is_admin_or_hr := coalesce(v_full, false)
    or v_roles && array['admin', 'super-admin', 'executive', 'executive-director',
                        'general-manager', 'hr-manager', 'hr-specialist', 'hr-officer', 'operations-manager-1']
    or public.has_any_permission(array['requests.approve', 'requests.request.approve', 'requests.decide',
                                       'leave.request.manage', 'attendance.record.manage']);

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
    or v_is_admin_or_hr
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
           'escalatedAt', s.escalated_at
         ) order by s.step_order), '[]'::jsonb)
    into v_steps
    from public.request_steps s
    left join public.employees actor on actor.id = s.acted_by
   where s.request_id = v_request.id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'action', x.action,
           'at', x.created_at,
           'actorName', case when x.action in ('escalate', 'expire') then null else actor.full_name_ar end,
           'comment', case when x.action in ('approve', 'reject', 'return', 'request_changes',
                                             'cancel', 'withdraw', 'reassign')
                           then nullif(trim(x.comment), '') end,
           'stepOrder', st.step_order,
           'stepName', case
             when x.metadata->>'roleName' is not null then x.metadata->>'roleName'
             when x.metadata->>'role' in ('hr', 'hr-manager', 'hr-specialist', 'hr-officer') then 'الموارد البشرية'
             when x.metadata->>'role' in ('executive', 'executive-director', 'general-manager') then 'المدير التنفيذي'
             when x.metadata->>'role' in ('operations', 'operations-manager-1', 'operations-manager') then 'مدير العمليات 1'
             when x.metadata->>'role' = 'direct_manager' then 'المدير المباشر'
             else st.name_ar
           end
         ) order by x.created_at asc), '[]'::jsonb)
    into v_history
    from public.request_actions x
    left join public.employees actor on actor.id = x.actor_employee_id
    left join public.request_steps st on st.id = x.request_step_id
   where x.request_id = v_request.id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'path', a.storage_path, 'mimeType', a.mime, 'sizeBytes', a.size_bytes
         ) order by a.created_at), '[]'::jsonb)
    into v_attachments
    from public.attachments a
   where a.entity_type = 'request' and a.entity_id = p_request_id;

  begin
    v_context := public.get_request_decision_context(p_request_id);
  exception when others then
    v_context := null;
  end;

  select e.full_name_ar into v_decided_by from public.employees e where e.id = v_request.decided_by;
  select e.full_name_ar into v_cancelled_by from public.employees e where e.id = v_request.cancelled_by;

  select ea.full_name_ar,
         coalesce(act.metadata->>'roleName', ''),
         coalesce((act.metadata->>'onBehalfOfExecutive')::boolean, false)
    into v_decision_actor, v_decision_mode, v_decision_on_behalf
    from public.request_actions act
    left join public.employees ea on ea.id = act.actor_employee_id
   where act.request_id = v_request.id
     and act.action in ('approve', 'reject', 'return', 'cancel')
   order by act.created_at desc
   limit 1;

  -- insights: سياق قرار المعتمد
  v_insights := jsonb_build_object(
    'monthRequestsCount', (
      select count(*) from public.requests r
       where r.employee_id = v_request.employee_id
         and r.id <> v_request.id
         and r.created_at >= date_trunc('month', current_date)
    ),
    'teamSize', (
      select count(*) from public.employees e
       where v_employee.department_id is not null
         and e.department_id = v_employee.department_id
         and e.id <> v_request.employee_id
         and e.is_active and not coalesce(e.is_deleted, false)
    )
  );

  -- إرفاق سجل التنفيذ للمأموريات والقوافل فقط (الفاندي لا يحتاج تنفيذاً)
  if v_request.request_type in ('mission', 'convoy') then
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
    'canDecide', coalesce((v_flags->>'canDecide')::boolean, false),
    'canCancel', coalesce(
      (v_request.status = 'pending' and v_request.employee_id = v_me)
      or (
        v_is_admin_or_hr
        and v_request.status in ('pending', 'approved')
      )
      or (
        v_request.employee_id = v_me
        and v_request.request_type in ('mission', 'convoy', 'fundraising')
        and v_request.status in ('pending', 'approved')
      ),
      false
    ),
    'canResubmit', coalesce(v_request.status in ('rejected', 'returned')
                            and v_request.employee_id = v_me
                            and v_request.request_type in ('leave', 'mission', 'convoy', 'fundraising',
                                                           'late_permit', 'early_permit', 'attendance_permit', 'attendance_correction'), false),
    'awaitingMe', coalesce((v_flags->>'awaitingMe')::boolean, false),
    'isMine', coalesce(v_request.employee_id = v_me, false),
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

revoke all on function public.get_mobile_request_detail(uuid) from public, anon;
grant execute on function public.get_mobile_request_detail(uuid) to authenticated, service_role;
