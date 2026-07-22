-- =====================================================================
-- 0062: تصعيد حقيقي للطلبات + قرار بالإنابة + صلاحيات السكرتير التنفيذي
-- =====================================================================
-- المرجع: المواصفة الرسمية (البنود 4،5،6،18).
-- المشكلة (من الفحص العميق): process_request_sla (0026) كان يقلب علم
--   workflow_status='escalated' فقط — بلا إعادة توجيه لمعتمد أعلى وبلا إشعار،
--   ولا مسار «بالإنابة» لمسؤول العمليات عند تأخر المدير التنفيذي (الشيخ محمد).
-- الحل:
--   1) دوال مساعدة: قراءة إعداد + إيجاد موظف نشط لدور معيّن + إشعار مستخدم.
--   2) إعادة كتابة process_request_sla لإعادة توجيه الطلب فعليًا + إشعار
--      المُصعَّد إليه + إشعار السكرتير + تسجيل action='escalate'، مع مسار
--      «بالإنابة» عندما يكون المدير المباشر هو المدير التنفيذي.
--   3) صلاحيات السكرتير: reassign_request / extend_request_deadline /
--      withdraw_escalation — full-access/executive-secretary + Audit.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1a) قراءة إعداد نظام كنص.
-- ---------------------------------------------------------------------
create or replace function public.get_system_setting_text(p_key text, p_default text default null)
returns text
language sql stable security definer set search_path = public, pg_temp
as $$
  select coalesce((select value #>> '{}' from public.system_settings where key = p_key), p_default);
$$;
revoke execute on function public.get_system_setting_text(text, text) from public;
grant execute on function public.get_system_setting_text(text, text) to authenticated, service_role;

-- 1b) قراءة إعداد نظام كرقم.
create or replace function public.get_system_setting_int(p_key text, p_default integer default null)
returns integer
language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_txt text;
begin
  v_txt := public.get_system_setting_text(p_key, null);
  if v_txt is null then return p_default; end if;
  begin return v_txt::integer; exception when others then return p_default; end;
end $$;
revoke execute on function public.get_system_setting_int(text, integer) from public;
grant execute on function public.get_system_setting_int(text, integer) to authenticated, service_role;

-- 1c) إيجاد موظف نشط يحمل دورًا معيّنًا (slug). يُرجع أقدم إسناد فعّال.
create or replace function public.first_active_employee_for_role(p_role_slug text)
returns uuid
language sql stable security definer set search_path = public, pg_temp
as $$
  select e.id
  from public.roles r
  join public.user_roles ur on ur.role_id = r.id
    and (ur.effective_from is null or ur.effective_from <= now())
    and (ur.effective_to   is null or ur.effective_to   >  now())
  join public.profiles p on p.id = ur.user_id
  join public.employees e on e.id = p.employee_id
    and e.is_active = true and e.status = 'active'
  where r.slug = p_role_slug
  order by ur.effective_from asc nulls first
  limit 1;
$$;
revoke execute on function public.first_active_employee_for_role(text) from public;
grant execute on function public.first_active_employee_for_role(text) to authenticated, service_role;

-- 1d) هل يحمل الموظف دورًا معيّنًا (slug)؟
create or replace function public.employee_has_role(p_employee_id uuid, p_role_slug text)
returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.employees e
    join public.profiles p on p.employee_id = e.id
    join public.user_roles ur on ur.user_id = p.id
      and (ur.effective_from is null or ur.effective_from <= now())
      and (ur.effective_to   is null or ur.effective_to   >  now())
    join public.roles r on r.id = ur.role_id
    where e.id = p_employee_id and r.slug = p_role_slug
  );
$$;
revoke execute on function public.employee_has_role(uuid, text) from public;
grant execute on function public.employee_has_role(uuid, text) to authenticated, service_role;

-- 1e) إشعار موظف (يحلّ recipient_user_id من profiles). آمن إن لم يكن للموظف مستخدم.
create or replace function public.notify_employee(
  p_employee_id uuid,
  p_title text,
  p_body text,
  p_category text default 'request',
  p_priority text default 'normal',
  p_entity_type text default null,
  p_entity_id uuid default null,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_user uuid; v_id uuid;
begin
  if p_employee_id is null then return null; end if;
  select p.id into v_user from public.profiles p where p.employee_id = p_employee_id;
  if v_user is null then return null; end if;
  insert into public.notifications(
    recipient_user_id, recipient_employee_id, title, body, category, priority,
    entity_type, entity_id, metadata, created_by)
  values(
    v_user, p_employee_id, p_title, p_body, p_category, p_priority,
    p_entity_type, p_entity_id, coalesce(p_metadata,'{}'::jsonb), auth.uid())
  returning id into v_id;
  return v_id;
end $$;
revoke execute on function public.notify_employee(uuid,text,text,text,text,text,uuid,jsonb) from public;
grant execute on function public.notify_employee(uuid,text,text,text,text,text,uuid,jsonb) to authenticated, service_role;

-- ---------------------------------------------------------------------
-- 2) إعادة كتابة process_request_sla: تصعيد حقيقي + إعادة توجيه + إشعار.
--    لكل طلب pending تجاوز مهلة القرار ولم يُصعَّد بعد:
--      * يحدد المُصعَّد إليه (دور من إعداد leave_escalation_target_role).
--      * إن كان المدير المباشر هو المدير التنفيذي → وسم القرار «بالإنابة».
--      * يحدّث manager_employee_id للطلب وassignee للخطوة النشطة.
--      * يضبط workflow_status='escalated' + escalated_at.
--      * يُشعر المُصعَّد إليه + السكرتير التنفيذي.
--      * يسجّل request_action='escalate' + Audit.
-- ---------------------------------------------------------------------
create or replace function public.process_request_sla(p_limit integer default 500)
returns integer
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_count integer := 0;
  v_row record;
  v_target_role text;
  v_notify_role text;
  v_exec_role text;
  v_target_emp uuid;
  v_notify_emp uuid;
  v_on_behalf boolean;
  v_mode text;
begin
  if auth.role() <> 'service_role' and not public.current_is_full_access() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  v_target_role := public.get_system_setting_text('leave_escalation_target_role', 'operations-officer');
  v_notify_role := public.get_system_setting_text('leave_escalation_notify_role', 'executive-secretary');
  v_exec_role   := public.get_system_setting_text('executive_director_role', 'executive-director');
  v_target_emp  := public.first_active_employee_for_role(v_target_role);
  v_notify_emp  := public.first_active_employee_for_role(v_notify_role);

  for v_row in
    select id, employee_id, manager_employee_id, request_type, title
    from public.requests
    where status = 'pending'
      and workflow_status in ('submitted','in_review','awaiting_manager','awaiting_operator')
      and decision_due_at is not null
      and decision_due_at < now()
      and escalated_at is null
    order by decision_due_at
    limit greatest(1, least(p_limit, 2000))
    for update skip locked
  loop
    -- مسار «بالإنابة»: المدير المباشر هو المدير التنفيذي (الشيخ محمد).
    v_on_behalf := (v_row.manager_employee_id is not null
                    and public.employee_has_role(v_row.manager_employee_id, v_exec_role));
    v_mode := case when v_on_behalf
                   then 'ESCALATED_TO_OPERATIONS_ON_BEHALF_OF_EXECUTIVE_DIRECTOR'
                   else 'ESCALATED_MANAGER_TIMEOUT' end;

    update public.requests
      set workflow_status = 'escalated',
          escalated_at = now(),
          -- المُصعَّد إليه يصبح المسؤول عن القرار (لا نمسح الأصلي — نحفظه بالـmetadata).
          manager_employee_id = coalesce(v_target_emp, manager_employee_id),
          payload = payload || jsonb_build_object(
            'escalation', jsonb_build_object(
              'mode', v_mode,
              'previousManagerId', v_row.manager_employee_id,
              'escalatedToRole', v_target_role,
              'escalatedToEmployeeId', v_target_emp,
              'onBehalfOfExecutive', v_on_behalf)),
          updated_at = now()
      where id = v_row.id;

    -- أعِد توجيه الخطوة النشطة للمُصعَّد إليه.
    update public.request_steps
      set assignee_employee_id = coalesce(v_target_emp, assignee_employee_id),
          status = 'escalated', escalated_at = now(), updated_at = now()
      where request_id = v_row.id and status in ('active','pending');

    -- سجل الإجراء.
    insert into public.request_actions(
      request_id, actor_employee_id, action, from_status, to_status, comment, metadata)
    values(
      v_row.id, null, 'escalate', 'pending', 'pending',
      case when v_on_behalf
           then 'تصعيد بالإنابة عن المدير التنفيذي بعد انتهاء المهلة'
           else 'تصعيد تلقائي بعد انتهاء مهلة المدير المباشر' end,
      jsonb_build_object('mode', v_mode, 'escalatedToRole', v_target_role,
                         'previousManagerId', v_row.manager_employee_id));

    -- إشعارات: المُصعَّد إليه + السكرتير التنفيذي (إن اختلف).
    perform public.notify_employee(
      v_target_emp, 'طلب مُصعَّد للقرار',
      format('طلب #%s بحاجة إلى قرارك بعد انتهاء مهلة المدير المباشر.', v_row.id),
      'request', 'high', 'requests', v_row.id,
      jsonb_build_object('mode', v_mode, 'onBehalfOfExecutive', v_on_behalf));

    if v_notify_emp is not null and v_notify_emp is distinct from v_target_emp then
      perform public.notify_employee(
        v_notify_emp, 'إشعار تصعيد طلب',
        format('تم تصعيد الطلب #%s بعد تأخر المدير المباشر عن اتخاذ القرار.', v_row.id),
        'request', 'normal', 'requests', v_row.id,
        jsonb_build_object('mode', v_mode, 'previousManagerId', v_row.manager_employee_id));
    end if;

    perform public.log_audit_event(
      'request.escalated', 'workflow', 'warning', 'requests', v_row.id,
      'تصعيد طلب بعد انتهاء المهلة',
      case when v_on_behalf then 'بالإنابة عن المدير التنفيذي' else 'تأخر المدير المباشر' end,
      jsonb_build_object('mode', v_mode, 'escalatedToRole', v_target_role,
                         'previousManagerId', v_row.manager_employee_id,
                         'escalatedToEmployeeId', v_target_emp));
    v_count := v_count + 1;
  end loop;

  return v_count;
end $$;

comment on function public.process_request_sla(integer) is
  'تصعيد حقيقي للطلبات المتأخرة: إعادة توجيه للمُصعَّد إليه + إشعار + قرار بالإنابة عن المدير التنفيذي + Audit.';

revoke execute on function public.process_request_sla(integer) from public, authenticated;
grant execute on function public.process_request_sla(integer) to service_role;

-- ---------------------------------------------------------------------
-- 3a) نقل الطلب من مدير إلى مدير (السكرتير التنفيذي) مع تسجيل القديم/الجديد.
-- ---------------------------------------------------------------------
create or replace function public.reassign_request(
  p_request_id uuid,
  p_new_manager_id uuid,
  p_reason text
)
returns public.requests
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_req public.requests; v_old uuid;
begin
  if not (public.current_is_full_access()
          or public.has_any_permission(array['requests.request.delegate','requests.request.override'])) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if length(trim(coalesce(p_reason,''))) < 3 then
    raise exception 'REASON_REQUIRED' using errcode = '22023';
  end if;

  select * into v_req from public.requests where id = p_request_id for update;
  if not found then raise exception 'request not found' using errcode = 'P0002'; end if;
  if v_req.status <> 'pending' then
    raise exception 'only pending requests can be reassigned' using errcode = '22023';
  end if;
  if p_new_manager_id = v_req.employee_id then
    raise exception 'cannot assign requester as approver' using errcode = '42501';
  end if;
  v_old := v_req.manager_employee_id;

  update public.requests
    set manager_employee_id = p_new_manager_id, updated_at = now(),
        payload = payload || jsonb_build_object('reassignment',
          jsonb_build_object('previousManagerId', v_old, 'newManagerId', p_new_manager_id, 'reason', p_reason))
    where id = p_request_id returning * into v_req;

  update public.request_steps
    set assignee_employee_id = p_new_manager_id, updated_at = now()
    where request_id = p_request_id and status in ('active','pending','escalated');

  insert into public.request_actions(
    request_id, actor_employee_id, action, comment, metadata)
  values(p_request_id, public.current_employee_id(), 'reassign', p_reason,
    jsonb_build_object('previousManagerId', v_old, 'newManagerId', p_new_manager_id));

  perform public.notify_employee(p_new_manager_id, 'أُسند إليك طلب للقرار',
    format('تم نقل الطلب #%s إليك.', p_request_id), 'request', 'high', 'requests', p_request_id);

  perform public.log_audit_event('request.reassigned', 'workflow', 'warning',
    'requests', p_request_id, 'نقل طلب من مدير إلى آخر', p_reason,
    jsonb_build_object('previousManagerId', v_old, 'newManagerId', p_new_manager_id));
  return v_req;
end $$;
revoke execute on function public.reassign_request(uuid,uuid,text) from public;
grant execute on function public.reassign_request(uuid,uuid,text) to authenticated;

-- 3b) تمديد مهلة القرار للمدير الحالي.
create or replace function public.extend_request_deadline(
  p_request_id uuid,
  p_hours integer,
  p_reason text
)
returns public.requests
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_req public.requests;
begin
  if not (public.current_is_full_access()
          or public.has_any_permission(array['requests.request.override','requests.request.escalate'])) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if p_hours is null or p_hours < 1 or p_hours > 720 then
    raise exception 'INVALID_HOURS' using errcode = '22023';
  end if;
  update public.requests
    set decision_due_at = coalesce(decision_due_at, now()) + make_interval(hours => p_hours),
        escalation_deadline = coalesce(decision_due_at, now()) + make_interval(hours => p_hours),
        updated_at = now()
    where id = p_request_id and status = 'pending'
    returning * into v_req;
  if not found then raise exception 'request not found or not pending' using errcode = 'P0002'; end if;

  insert into public.request_actions(request_id, actor_employee_id, action, comment, metadata)
  values(p_request_id, public.current_employee_id(), 'comment',
    coalesce(p_reason, 'تمديد مهلة القرار'),
    jsonb_build_object('extendedHours', p_hours));

  perform public.log_audit_event('request.deadline.extended', 'workflow', 'info',
    'requests', p_request_id, 'تمديد مهلة قرار الطلب', p_reason,
    jsonb_build_object('hours', p_hours));
  return v_req;
end $$;
revoke execute on function public.extend_request_deadline(uuid,integer,text) from public;
grant execute on function public.extend_request_deadline(uuid,integer,text) to authenticated;

-- 3c) سحب التصعيد وإعادة الطلب لمساره الطبيعي (السكرتير التنفيذي).
create or replace function public.withdraw_escalation(
  p_request_id uuid,
  p_reason text
)
returns public.requests
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_req public.requests;
begin
  if not (public.current_is_full_access()
          or public.has_permission('requests.request.override')) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  update public.requests
    set workflow_status = 'awaiting_manager', escalated_at = null, updated_at = now(),
        payload = payload || jsonb_build_object('escalationWithdrawn',
          jsonb_build_object('reason', p_reason, 'at', now()))
    where id = p_request_id and status = 'pending'
    returning * into v_req;
  if not found then raise exception 'request not found or not pending' using errcode = 'P0002'; end if;

  insert into public.request_actions(request_id, actor_employee_id, action, comment)
  values(p_request_id, public.current_employee_id(), 'comment',
    coalesce(p_reason, 'سحب التصعيد'));

  perform public.log_audit_event('request.escalation.withdrawn', 'workflow', 'info',
    'requests', p_request_id, 'سحب تصعيد الطلب', p_reason, '{}'::jsonb);
  return v_req;
end $$;
revoke execute on function public.withdraw_escalation(uuid,text) from public;
grant execute on function public.withdraw_escalation(uuid,text) to authenticated;

-- =====================================================================
-- نهاية Migration 0062
-- =====================================================================
