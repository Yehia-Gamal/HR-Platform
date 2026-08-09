-- 0351: إصلاح مراجع أعمدة خاطئة كشفتها أداة فحص المراجع (check-function-refs).
--
-- الأخطاء المكتشفة (كلها مرّت لأن PL/pgSQL لا يتحقق من الأعمدة عند الإنشاء، وتفشل عند الاستدعاء):
--   1) get_mobile_action_target (0277): `public.attendance_punches` جدول غير موجود إطلاقاً.
--      البديل الصحيح: attendance_punch_attempts عبر attendance_event_id (بصمة مرتبطة بحدث حضور).
--   2) get_mobile_action_target (0277): `dc.complainant_employee_id` — لا يوجد في dispute_cases.
--      الصحيح: actor_employee_id (مقدّم الشكوى).
--   3) get_mobile_action_target (0277): `r.given_by_employee_id` — لا يوجد في recognitions.
--      الصحيح: nominated_by (مُرسل التقدير).
--   4) hard_delete_employee_guarded (0282): `employees.manager_id` — العمود غير موجود.
--      الصحيح: فحص المرؤوسين عبر manager_relations (relation_type='primary') بنمط 0321/0022.

begin;

-- ---------------------------------------------------------------
-- 1) get_mobile_action_target — تصحيح أعمدة attendance/dispute/recognition
-- ---------------------------------------------------------------
create or replace function public.get_mobile_action_target(p_action_id text, p_kind text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uuid uuid;
  v_prefix text := lower(trim(coalesce(p_kind, '')))||'-';
  v_raw_id text;
  v_allowed boolean := false;
  v_emp uuid;
begin
  if p_action_id is null or p_kind is null or position(v_prefix in lower(p_action_id)) <> 1 then
    raise exception 'invalid action identifier' using errcode = '22023';
  end if;
  v_raw_id := substring(p_action_id from length(v_prefix) + 1);
  begin
    v_uuid := v_raw_id::uuid;
  exception when others then
    raise exception 'invalid action identifier' using errcode = '22023';
  end;

  case lower(p_kind)
    when 'request' then
      select exists(
        select 1 from public.requests r
        where r.id = v_uuid
          and (
            r.employee_id = public.current_employee_id()
            or public.current_is_full_access()
            or public.can_access_employee(r.employee_id, 'requests.request.approve')
            or public.can_access_employee(r.employee_id, 'requests.request.read')
          )
      ) into v_allowed;
      if not v_allowed then raise exception 'action target access denied' using errcode='42501'; end if;
      return jsonb_build_object('kind','request','recordId',v_uuid,'mobileRoute','request_detail');

    when 'kpi' then
      select exists(
        select 1 from public.kpi_evaluations k
        where k.id = v_uuid
          and (
            k.employee_id = public.current_employee_id()
            or public.current_is_full_access()
            or public.can_access_employee(k.employee_id,'performance.kpi.manager_assess')
            or public.has_any_permission(array[
              'performance.kpi.read','performance.kpi.secretary_review',
              'performance.kpi.executive_review','performance.kpi.finalize'
            ])
          )
      ) into v_allowed;
      if not v_allowed then raise exception 'action target access denied' using errcode='42501'; end if;
      return jsonb_build_object('kind','kpi','recordId',v_uuid,'mobileRoute','kpi_form');

    when 'decision' then
      select exists(
        select 1 from public.administrative_decisions d
        where d.id = v_uuid and d.status = 'published'
          and (
            public.current_is_full_access()
            or public.has_any_permission(array['comms.decision.read','comms.decision.manage'])
            or exists (
              select 1 from public.decision_recipients dr
              where dr.decision_id=d.id and dr.employee_id=public.current_employee_id()
            )
          )
      ) into v_allowed;
      if not v_allowed then raise exception 'action target access denied' using errcode='42501'; end if;
      return jsonb_build_object('kind','decision','recordId',v_uuid,'mobileRoute','feed_detail');

    -- حضور/بصمة: أي حدث/تصحيح/طلب يخصني أو أملك صلاحية مراجعته
    when 'attendance' then
      select (
        exists(select 1 from public.attendance_events e
               where e.id = v_uuid and e.employee_id = public.current_employee_id())
        or exists(select 1 from public.attendance_corrections c
                  where c.id = v_uuid and c.employee_id = public.current_employee_id())
        or exists(select 1 from public.attendance_punch_attempts pa
                  where pa.attendance_event_id = v_uuid and pa.employee_id = public.current_employee_id())
        or public.current_is_full_access()
        or public.has_any_permission(array[
          'attendance.review','attendance.manage','attendance.admin',
          'attendance.attendance.review','attendance.attendance.manage'
        ])
      ) into v_allowed;
      if not v_allowed then
        -- fallback: إن لم يوجد سجل أصلاً، اسمح بالفتح لعرض صفحة الحضور العامة
        -- (الهوية مؤكدة عبر كونها UUID صالح — لا تسريب بيانات).
        return jsonb_build_object('kind','attendance','recordId',v_uuid,'mobileRoute','attendance_detail');
      end if;
      return jsonb_build_object('kind','attendance','recordId',v_uuid,'mobileRoute','attendance_detail');

    -- نزاع: أحد الأطراف أو عضو لجنة أو مدير نزاعات
    when 'dispute' then
      select exists(
        select 1 from public.dispute_cases dc
        where dc.id = v_uuid and (
          dc.actor_employee_id = public.current_employee_id()
          or dc.respondent_employee_id = public.current_employee_id()
          or public.current_is_full_access()
          or public.can_access_dispute(dc.id)
          or public.has_any_permission(array['disputes.case.read','disputes.case.manage'])
        )
      ) into v_allowed;
    if not v_allowed then raise exception 'action target access denied' using errcode='42501'; end if;
      return jsonb_build_object('kind','dispute','recordId',v_uuid,'mobileRoute','dispute_detail');

    -- مهمة: المكلّف أو المُسنِد أو مدير المهام
    when 'task' then
      select exists(
        select 1 from public.tasks t
        where t.id = v_uuid and (
          t.assignee_employee_id = public.current_employee_id()
          or t.created_by_employee_id = public.current_employee_id()
          or public.current_is_full_access()
          or public.has_any_permission(array['tasks.task.read','tasks.task.manage'])
        )
      ) into v_allowed;
      if not v_allowed then raise exception 'action target access denied' using errcode='42501'; end if;
      return jsonb_build_object('kind','task','recordId',v_uuid,'mobileRoute','task_detail');

    -- إعلان: منشور أو موجّه إليّ
    when 'announcement' then
      select exists(
        select 1 from public.announcements a
        where a.id = v_uuid and (
          a.status = 'published'
          or public.current_is_full_access()
          or public.has_any_permission(array['comms.announcement.read','comms.announcement.manage'])
        )
      ) into v_allowed;
      if not v_allowed then raise exception 'action target access denied' using errcode='42501'; end if;
      return jsonb_build_object('kind','announcement','recordId',v_uuid,'mobileRoute','feed_detail');

    -- تقدير: المستلم أو المُرسل أو الإدارة
    when 'recognition' then
      select (
        exists(select 1 from public.recognitions r
               where r.id = v_uuid and (
                 r.recipient_employee_id = public.current_employee_id()
                 or r.nominated_by = public.current_employee_id()
               ))
        or public.current_is_full_access()
        or public.has_any_permission(array['recognition.read','recognition.manage'])
      ) into v_allowed;
    if not v_allowed then
        -- التقدير العام يظهر في feed حتى لو لم أكن طرفاً مباشراً
        return jsonb_build_object('kind','recognition','recordId',v_uuid,'mobileRoute','feed_detail');
      end if;
      return jsonb_build_object('kind','recognition','recordId',v_uuid,'mobileRoute','feed_detail');

    else
      raise exception 'unsupported action kind' using errcode='22023';
  end case;
end;
$$;

comment on function public.get_mobile_action_target(text,text) is
  'توجيه الروابط العميقة للتطبيق — request/kpi/decision/attendance/dispute/task/announcement/recognition مع مراجعة الصلاحيات. (0351)';

grant execute on function public.get_mobile_action_target(text, text) to authenticated;

-- ---------------------------------------------------------------
-- 2) hard_delete_employee_guarded — تصحيح فحص "لديه مرؤوسون"
--    (employees.manager_id غير موجود؛ الصحيح عبر manager_relations)
-- ---------------------------------------------------------------
create or replace function public.hard_delete_employee_guarded(p_employee_id uuid,p_confirmation_code text,p_reason text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_employee public.employees%rowtype;
begin
  -- 1) الحذف الدائم مقصور على المدير الرئيسي للوصول الكامل.
  if not public.current_is_full_access() then raise exception 'main_admin_required' using errcode='42501'; end if;
  -- 2) منع حذف الموظف لنفسه.
  if p_employee_id=public.current_employee_id() then raise exception 'self_delete_not_allowed' using errcode='42501'; end if;
  -- 3) سجل سبب الحذف (لا يمكن أن يكون فارغاً/قصيراً).
  if length(trim(coalesce(p_reason,'')))<10 then raise exception 'delete_reason_required' using errcode='22023'; end if;
  -- 4) تحميل سجل الموظف ثم قفله لضمان الحذف الآمن.
  select * into v_employee from public.employees where id=p_employee_id for update;
  if v_employee.id is null then raise exception 'employee_not_found' using errcode='P0002'; end if;
  -- 5) التحقق من رمز التأكيد: إما رمز الموظف أو إداري.
  if p_confirmation_code is distinct from v_employee.employee_code
     and p_confirmation_code is distinct from 'hard-delete-confirm'
  then raise exception 'delete_confirmation_mismatch' using errcode='22023'; end if;
  -- 6) منع حذف مدير/قائد فريق لديه مرؤوسون نشطون (مدير مباشر أو قائد فريق).
  if exists (
       select 1 from public.manager_relations mr
       join public.employees sub on sub.id = mr.employee_id
       where mr.manager_employee_id = p_employee_id
         and mr.relation_type = 'primary'
         and mr.effective_from <= (now() at time zone 'Africa/Cairo')::date
         and (mr.effective_to is null or mr.effective_to >= (now() at time zone 'Africa/Cairo')::date)
         and sub.is_active = true
         and sub.is_deleted = false
     )
     or exists (select 1 from public.teams t where t.lead_id=p_employee_id and t.is_active=true)
  then raise exception 'manager_has_direct_reports' using errcode='55000'; end if;
  -- 7) منع الحذف الدائم عند وجود سجل تاريخي (المعتمد: الحذف عبر أرشيف).
  --    (إبقاء الترحيل محافظاً: سرد 9+ جداول FK لمنع الحذف المباشر.)
  if exists (select 1 from public.profiles where employee_id=p_employee_id)
     or exists (select 1 from public.attendance_events where employee_id=p_employee_id)
     or exists (select 1 from public.attendance_daily where employee_id=p_employee_id)
     or exists (select 1 from public.requests where employee_id=p_employee_id)
     or exists (select 1 from public.leave_requests where employee_id=p_employee_id)
     or exists (select 1 from public.leave_balance_accounts where employee_id=p_employee_id)
     or exists (select 1 from public.leave_ledger_entries where employee_id=p_employee_id)
     or exists (select 1 from public.missions where employee_id=p_employee_id)
     or exists (select 1 from public.convoy_requests where employee_id=p_employee_id)
     or exists (select 1 from public.kpi_evaluations where employee_id=p_employee_id)
     or exists (select 1 from public.monthly_evaluations where employee_id=p_employee_id)
     or exists (select 1 from public.goal_objectives where employee_id=p_employee_id)
     or exists (select 1 from public.employee_competency_assessments where employee_id=p_employee_id)
     or exists (select 1 from public.improvement_plans where employee_id=p_employee_id)
     or exists (select 1 from public.one_on_ones where employee_id=p_employee_id)
     or exists (select 1 from public.documents where owner_employee_id=p_employee_id)
     or exists (select 1 from public.announcement_acknowledgements where employee_id=p_employee_id)
     or exists (select 1 from public.committee_members where employee_id=p_employee_id)
     or exists (select 1 from public.employee_devices where employee_id=p_employee_id)
     or exists (select 1 from public.passkey_credentials where employee_id=p_employee_id)
     or exists (select 1 from public.employee_locations where employee_id=p_employee_id)
     or exists (select 1 from public.audit_events where employee_id=p_employee_id)
  then raise exception 'employee_history_requires_archive' using errcode='55000'; end if;
  -- 8) تسجيل عملية الحذف الدائم المعتمدة.
  perform public.log_audit_event('employee.permanent_delete_approved','security','critical','employees',p_employee_id,trim(p_reason),row_to_json(v_employee)::text,jsonb_build_object('confirmationCode',coalesce(p_confirmation_code,'')));
  -- 9) حذف الموظف: FK معرّفة تحمي البيانات التاريخية عند تفعيل الأرشفة.
  begin
    delete from public.employees where id=p_employee_id;
  exception when foreign_key_violation then
    raise exception 'employee_history_requires_archive' using errcode='55000';
  end;
  return jsonb_build_object('ok',true,'employeeId',p_employee_id,'deleted',true);
exception when others then
  begin
    perform public.log_audit_event('employee.permanent_delete_failed','security','warning','employees',p_employee_id,coalesce(trim(p_reason),''),coalesce(sqlerrm,''),jsonb_build_object('sqlstate',coalesce(sqlstate,''),'confirmationCode',coalesce(p_confirmation_code,'')));
  exception when others then
    null;
  end;
  raise;
end; $$;

notify pgrst, 'reload schema';

commit;
