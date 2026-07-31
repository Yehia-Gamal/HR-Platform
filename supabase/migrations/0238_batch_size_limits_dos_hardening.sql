-- 0238: حدّ أقصى لحجم الدُفعات في دوال SECURITY DEFINER التي تكرّر مصفوفات المستدعي
-- =====================================================================
-- الهدف (أمان): منع هجمات حجب الخدمة (DoS) عبر حمولات مصفوفات ضخمة.
-- كل دالة أدناه كانت تكرّر مصفوفة يزوّدها المستدعي (FOREACH / jsonb_array_elements)
-- دون سقف أعلى، فتُجبر الخادم على إدخالات/إشعارات/أقفال غير محدودة في معاملة واحدة.
-- نُعيد تعريف الدوال الحيّة (آخر تعريف) كما هي حرفياً مع إضافة حارس واحد فقط:
--   IF <array length> > <cap> THEN RAISE EXCEPTION 'ERR_BATCH_TOO_LARGE'; END IF;
--
-- السقوف (متحفّظة بما يتجاوز الاستخدام المشروع بكثير):
--   500  — دفعات uuid[]/jsonb كبيرة مشروعة (طلبات، مشاركون، صلاحيات دور، إشعارات، أيام جدول)
--   200  — دفعات jsonb بإدراج لكل عنصر (مهام، بنود إخلاء طرف، أطراف/شهود/مشاركو جلسة)
--   100  — كيانات صغيرة بطبيعتها (لجنة، حضور، أعضاء لجنة مقابلة، قائمة صلاحيات)
--
-- ملاحظات:
--   • الأغلفة language sql (schedule_dispute_session / finalize_dispute_session)
--     تفوّض إلى نسخ v2 — تقييد v2 يغطّيها تلقائياً.
--   • submit_my_dispute_v23 (0168) غلاف يمرّر المصفوفات إلى submit_my_dispute — مغطّى.
--   • advance_kpi_stage محدود ضمنياً بعدد معايير القالب (لا يحتاج تعديلاً).
-- =====================================================================

BEGIN;

-- =====================================================================
-- 1) rpc_set_role_permissions (0002) — p_items — سقف 500
-- =====================================================================
create or replace function public.rpc_set_role_permissions(p_role_id uuid, p_items jsonb)
returns integer
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_role public.roles; v_count int := 0; v_item jsonb;
begin
  if not (public.current_is_full_access() or public.has_permission('access.role.update')) then
    raise exception 'not authorized' using errcode = '42501';
  end if;
  if jsonb_array_length(coalesce(p_items,'[]'::jsonb)) > 500 then
    raise exception 'ERR_BATCH_TOO_LARGE' using errcode = '22023';
  end if;
  select * into v_role from public.roles where id = p_role_id;
  if v_role.is_system and not public.current_is_super_admin() then
    raise exception 'system roles are protected' using errcode = '42501';
  end if;
  delete from public.role_permissions where role_id = p_role_id;
  for v_item in select * from jsonb_array_elements(p_items) loop
    insert into public.role_permissions (role_id, permission_id, scope, requires_mfa, requires_reason)
    values (p_role_id,
            (v_item->>'permission_id')::uuid,
            coalesce(v_item->>'scope','self'),
            coalesce((v_item->>'requires_mfa')::boolean,false),
            coalesce((v_item->>'requires_reason')::boolean,false));
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- =====================================================================
-- 2) batch_decide_requests (0224) — p_request_ids — سقف 500
-- =====================================================================
CREATE OR REPLACE FUNCTION public.batch_decide_requests(
  p_request_ids  uuid[],
  p_decision     text,
  p_comment      text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count       int := 0;
  v_skipped     int := 0;
  v_id          uuid;
  v_user_id     uuid := auth.uid();
  v_employee_id uuid := public.current_employee_id();
  v_total       int  := coalesce(array_length(p_request_ids, 1), 0);
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'ERR_NOT_AUTHENTICATED';
  END IF;
  IF v_employee_id IS NULL THEN
    RAISE EXCEPTION 'ERR_NO_EMPLOYEE_LINKED';
  END IF;

  IF NOT public.current_is_full_access()
     AND NOT public.has_any_permission(ARRAY[
       'requests.request.approve',
       'requests.request.override'
     ])
  THEN
    RAISE EXCEPTION 'ERR_FORBIDDEN';
  END IF;

  IF p_decision NOT IN ('approved', 'rejected') THEN
    RAISE EXCEPTION 'ERR_INVALID_DECISION: يجب أن يكون approved أو rejected';
  END IF;

  IF v_total = 0 THEN
    RETURN jsonb_build_object('processed', 0, 'skipped', 0, 'total', 0);
  END IF;

  IF v_total > 500 THEN
    RAISE EXCEPTION 'ERR_BATCH_TOO_LARGE' USING ERRCODE = '22023';
  END IF;

  IF to_regclass('public.requests') IS NULL THEN
    RAISE EXCEPTION 'ERR_TABLE_NOT_FOUND: requests';
  END IF;

  FOREACH v_id IN ARRAY p_request_ids LOOP
    IF EXISTS (
      SELECT 1 FROM public.requests
      WHERE id = v_id AND employee_id = v_employee_id
    ) THEN
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    UPDATE public.requests SET
      status       = p_decision,
      decided_by   = v_employee_id,
      decided_at   = now(),
      updated_at   = now()
    WHERE id = v_id
      AND status = 'pending';

    IF FOUND THEN
      v_count := v_count + 1;

      IF to_regclass('public.request_actions') IS NOT NULL THEN
        INSERT INTO public.request_actions (
          request_id, actor_employee_id, action,
          from_status, to_status, comment, created_by
        ) VALUES (
          v_id, v_employee_id,
          CASE p_decision WHEN 'approved' THEN 'approve' ELSE 'reject' END,
          'pending', p_decision, p_comment, v_user_id
        );
      END IF;
    ELSE
      v_skipped := v_skipped + 1;
    END IF;
  END LOOP;

  PERFORM public.log_audit_event(
    'batch_decide_requests',
    'workflow',
    'notice',
    'requests',
    NULL,
    'قرار جماعي على ' || v_count || ' طلب (' || p_decision || ')',
    'batch decision: ' || v_count || ' processed, ' || v_skipped || ' skipped',
    jsonb_build_object(
      'processed', v_count,
      'skipped', v_skipped,
      'total', v_total,
      'decision', p_decision,
      'request_ids', to_jsonb(p_request_ids)
    )
  );

  RETURN jsonb_build_object(
    'processed', v_count,
    'skipped',   v_skipped,
    'total',     v_total
  );
END;
$$;

-- =====================================================================
-- 3) batch_mark_notifications_read (0224) — p_notification_ids — سقف 500
-- =====================================================================
CREATE OR REPLACE FUNCTION public.batch_mark_notifications_read(
  p_notification_ids uuid[]
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count   int;
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'ERR_NOT_AUTHENTICATED';
  END IF;

  IF coalesce(array_length(p_notification_ids, 1), 0) = 0 THEN
    RETURN 0;
  END IF;

  IF array_length(p_notification_ids, 1) > 500 THEN
    RAISE EXCEPTION 'ERR_BATCH_TOO_LARGE' USING ERRCODE = '22023';
  END IF;

  IF to_regclass('public.notifications') IS NULL THEN
    RETURN 0;
  END IF;

  UPDATE public.notifications
  SET read_at    = now(),
      is_read    = true,
      updated_at = now()
  WHERE id = ANY(p_notification_ids)
    AND recipient_user_id = v_user_id
    AND read_at IS NULL;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- =====================================================================
-- 4) create_work_assignment (0063) — p_participant_ids — سقف 500
-- =====================================================================
create or replace function public.create_work_assignment(
  p_assignment_type text,
  p_title text,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_participant_ids uuid[],
  p_description text default null,
  p_location text default null,
  p_responsible_employee_id uuid default null,
  p_needs_report boolean default false,
  p_report_due_at timestamptz default null,
  p_payload jsonb default '{}'::jsonb
)
returns public.work_assignments
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_row public.work_assignments;
  v_emp uuid;
  v_can_manage boolean;
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
begin
  if v_me is null then raise exception 'no employee linked' using errcode = '42501'; end if;
  if p_assignment_type not in ('MISSION','CONVOY','FUNDRAISING') then
    raise exception 'invalid assignment type' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_title,''))) < 3 then
    raise exception 'title is required' using errcode = '22023';
  end if;
  if p_start_at is null or p_end_at is null or p_end_at < p_start_at then
    raise exception 'invalid assignment period' using errcode = '22023';
  end if;
  if p_participant_ids is null or array_length(p_participant_ids,1) is null then
    raise exception 'at least one participant is required' using errcode = '22023';
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
end $$;

-- =====================================================================
-- 5) publish_roster_admin (0032) — p_days — سقف 500
-- =====================================================================
create or replace function public.publish_roster_admin(
  p_name text,
  p_period_start date,
  p_period_end date,
  p_department_id uuid,
  p_team_id uuid,
  p_branch_id uuid,
  p_days jsonb,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_id uuid;
  v_item jsonb;
  v_employee uuid;
  v_date date;
  v_shift uuid;
  v_status text;
  v_code text;
begin
  if not(public.current_is_full_access() or public.has_permission('attendance.roster.manage')) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  if p_period_end < p_period_start or jsonb_typeof(p_days) <> 'array' or jsonb_array_length(p_days)=0 then
    raise exception 'INVALID_ROSTER';
  end if;
  if jsonb_array_length(p_days) > 500 then
    raise exception 'ERR_BATCH_TOO_LARGE' using errcode='22023';
  end if;

  v_code := 'RST-' || to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS');
  insert into public.work_rosters(
    code,name,period_start,period_end,department_id,team_id,branch_id,status,
    published_at,published_by,notes,created_by
  ) values (
    v_code,trim(p_name),p_period_start,p_period_end,p_department_id,p_team_id,p_branch_id,
    'published',now(),public.current_employee_id(),p_notes,auth.uid()
  ) returning id into v_id;

  for v_item in select * from jsonb_array_elements(p_days) loop
    v_employee := (v_item->>'employeeId')::uuid;
    v_date := (v_item->>'workDate')::date;
    v_shift := nullif(v_item->>'shiftId','')::uuid;
    v_status := coalesce(v_item->>'dayStatus','scheduled');

    if v_date < p_period_start or v_date > p_period_end
       or not public.can_access_employee(v_employee,'attendance.roster.manage') then
      raise exception 'ROSTER_SCOPE_OR_DATE_INVALID';
    end if;

    update public.roster_days
       set day_status='cancelled', updated_at=now()
     where employee_id=v_employee and work_date=v_date and day_status<>'cancelled';

    update public.work_rosters r
       set status='superseded', updated_at=now()
     where r.status='published'
       and r.id<>v_id
       and exists(
         select 1 from public.roster_days d
          where d.roster_id=r.id and d.employee_id=v_employee and d.work_date=v_date
       );

    insert into public.roster_days(
      roster_id,employee_id,work_date,shift_id,work_site_id,geofence_id,day_status,
      start_override,end_override,notes,created_by
    ) values (
      v_id,v_employee,v_date,v_shift,nullif(v_item->>'workSiteId','')::uuid,
      nullif(v_item->>'geofenceId','')::uuid,v_status,
      nullif(v_item->>'startOverride','')::time,nullif(v_item->>'endOverride','')::time,
      v_item->>'notes',auth.uid()
    );
  end loop;

  perform public.log_audit_event(
    'attendance.roster.published','workflow','notice','work_rosters',v_id,
    'نشر جدول ورديات',null,jsonb_build_object('start',p_period_start,'end',p_period_end)
  );
  return v_id;
end $$;

-- =====================================================================
-- 6) create_onboarding_journey_admin (0025) — p_tasks — سقف 200
-- =====================================================================
create or replace function public.create_onboarding_journey_admin(
  p_employee_id uuid,
  p_started_at timestamptz default now(),
  p_probation_end date default null,
  p_tasks jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
  v_task jsonb;
begin
  if not (public.current_is_full_access() or public.has_permission('onboarding.journey.manage')) then
    raise exception 'onboarding management denied' using errcode = '42501';
  end if;
  if jsonb_array_length(coalesce(p_tasks, '[]'::jsonb)) > 200 then
    raise exception 'ERR_BATCH_TOO_LARGE' using errcode = '22023';
  end if;
  if not exists(select 1 from public.employees e where e.id = p_employee_id and e.is_deleted = false) then
    raise exception 'employee not found' using errcode = 'P0002';
  end if;
  if exists(select 1 from public.onboarding_journeys j where j.employee_id = p_employee_id and j.status in ('not_started','in_progress')) then
    raise exception 'employee already has an active onboarding journey' using errcode = '23505';
  end if;

  insert into public.onboarding_journeys(employee_id, started_at, probation_end, status, created_by)
  values (p_employee_id, coalesce(p_started_at, now()), p_probation_end, 'in_progress', auth.uid())
  returning id into v_id;

  for v_task in select * from jsonb_array_elements(coalesce(p_tasks, '[]'::jsonb)) loop
    if nullif(trim(v_task->>'title'), '') is not null then
      insert into public.onboarding_tasks(journey_id, title, owner_role, assignee_id, due_offset_days, status, created_by)
      values (
        v_id,
        trim(v_task->>'title'),
        nullif(trim(v_task->>'ownerRole'), ''),
        nullif(v_task->>'assigneeId', '')::uuid,
        coalesce(nullif(v_task->>'dueOffsetDays', '')::integer, 0),
        'pending', auth.uid()
      );
    end if;
  end loop;

  update public.employees set status = 'onboarding', updated_at = now()
  where id = p_employee_id and status in ('draft','invited');
  return v_id;
end;
$$;

-- =====================================================================
-- 7) start_offboarding_case (0031) — p_clearance_items — سقف 200
-- =====================================================================
create or replace function public.start_offboarding_case(p_employee_id uuid,p_reason_type text,p_reason text,p_notice_date date,p_last_working_date date,p_handover_employee_id uuid default null,p_clearance_items jsonb default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid; v_number text; v_item jsonb;
begin
 if not(public.current_is_full_access() or public.has_permission('offboarding.case.manage')) then raise exception 'FORBIDDEN'; end if;
 if p_employee_id=public.current_employee_id() or p_last_working_date<coalesce(p_notice_date,p_last_working_date) then raise exception 'INVALID_OFFBOARDING'; end if;
 if exists(select 1 from public.offboarding_cases where employee_id=p_employee_id and status not in ('completed','cancelled')) then raise exception 'ACTIVE_OFFBOARDING_EXISTS'; end if;
 v_number:='OFF-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS');
 insert into public.offboarding_cases(employee_id,case_number,reason_type,reason,notice_date,last_working_date,status,handover_employee_id,created_by)
 values(p_employee_id,v_number,p_reason_type,p_reason,p_notice_date,p_last_working_date,'in_clearance',p_handover_employee_id,auth.uid()) returning id into v_id;
 update public.employees set status='notice_period',is_active=true,updated_at=now() where id=p_employee_id;
 if p_clearance_items is null then p_clearance_items:='[{"category":"manager","title":"تسليم المهام والمعرفة"},{"category":"assets","title":"إعادة جميع العهد"},{"category":"it","title":"إلغاء الوصول التقني"},{"category":"hr","title":"مراجعة الملف والمستندات"},{"category":"finance","title":"التسوية المالية النهائية"}]'::jsonb; end if;
 if jsonb_array_length(p_clearance_items) > 200 then raise exception 'ERR_BATCH_TOO_LARGE' using errcode='22023'; end if;
 for v_item in select * from jsonb_array_elements(p_clearance_items) loop
  insert into public.offboarding_clearance_items(offboarding_case_id,category,title,owner_role,due_at,created_by) values(v_id,v_item->>'category',v_item->>'title',v_item->>'ownerRole',p_last_working_date::timestamptz,auth.uid());
 end loop;
 insert into public.offboarding_actions(offboarding_case_id,action_type,to_status,note,actor_employee_id,actor_user_id) values(v_id,'start','in_clearance',p_reason,public.current_employee_id(),auth.uid()); return v_id;
end $$;

-- =====================================================================
-- 8) submit_my_dispute (0059) — p_parties / p_witnesses — سقف 200 لكل مصفوفة
--    يغطّي أيضاً submit_my_dispute_v23 (0168) الذي يفوّض إليها.
-- =====================================================================
create or replace function public.submit_my_dispute(
 p_title text,p_description text,p_case_type text,p_priority text default 'normal',
 p_incident_at timestamptz default null,p_incident_location text default null,
 p_parties jsonb default '[]'::jsonb,p_witnesses jsonb default '[]'::jsonb,
 p_direct_manager_contacted boolean default null,p_amicable_attempted boolean default null,
 p_amicable_result text default null,p_requested_action text default null,
 p_confidential boolean default true,p_truth_confirmed boolean default false,
 p_confidentiality_accepted boolean default false
)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_emp uuid:=public.current_employee_id(); v_id uuid; v_number text; v_item jsonb; v_party uuid; v_first_respondent uuid;
begin
 if v_emp is null then raise exception 'EMPLOYEE_CONTEXT_REQUIRED' using errcode='42501'; end if;
 if length(trim(coalesce(p_title,'')))<5 or length(trim(coalesce(p_description,'')))<20 then raise exception 'INVALID_CASE' using errcode='22023'; end if;
 if not p_truth_confirmed or not p_confidentiality_accepted then raise exception 'REQUIRED_CONFIRMATIONS_MISSING' using errcode='22023'; end if;
 if p_case_type not in ('employee_conflict','inappropriate_conduct','verbal_abuse','management_chain','direct_manager','department_conflict','misunderstanding','work_environment','donor_beneficiary','administrative_violation','agreement_breach','other') then raise exception 'INVALID_CASE_TYPE' using errcode='22023'; end if;
 if p_priority not in ('normal','urgent') then raise exception 'EMPLOYEE_PRIORITY_NOT_ALLOWED' using errcode='22023'; end if;
 if jsonb_typeof(coalesce(p_parties,'[]'::jsonb))<>'array' or jsonb_typeof(coalesce(p_witnesses,'[]'::jsonb))<>'array' then raise exception 'INVALID_PARTIES' using errcode='22023'; end if;
 if jsonb_array_length(coalesce(p_parties,'[]'::jsonb))=0 then raise exception 'AT_LEAST_ONE_PARTY_REQUIRED' using errcode='22023'; end if;
 if jsonb_array_length(coalesce(p_parties,'[]'::jsonb))>200 or jsonb_array_length(coalesce(p_witnesses,'[]'::jsonb))>200 then raise exception 'ERR_BATCH_TOO_LARGE' using errcode='22023'; end if;

 v_number:='CASE-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS');
 insert into public.dispute_cases(case_number,title,description,case_type,status,severity,actor_employee_id,is_confidential,privacy_level,opened_at,
  incident_at,incident_location,requested_action,witnesses_present,direct_manager_contacted,amicable_resolution_attempted,amicable_resolution_result,
  truth_confirmed,confidentiality_accepted,review_due_at,created_by)
 values(v_number,trim(p_title),trim(p_description),p_case_type,'submitted',p_priority,v_emp,p_confidential,'restricted',now(),
  p_incident_at,nullif(trim(p_incident_location),''),nullif(trim(p_requested_action),''),jsonb_array_length(coalesce(p_witnesses,'[]'::jsonb))>0,
  p_direct_manager_contacted,p_amicable_attempted,nullif(trim(p_amicable_result),''),true,true,now()+interval '24 hours',auth.uid()) returning id into v_id;

 insert into public.dispute_parties(case_id,employee_id,party_type,notification_status,notified_at,created_by)
 values(v_id,v_emp,'complainant','read',now(),auth.uid());

 for v_item in select * from jsonb_array_elements(coalesce(p_parties,'[]'::jsonb)) loop
  v_party=(v_item->>'employeeId')::uuid;
  if v_party=v_emp or not exists(select 1 from public.employees where id=v_party and status='active' and is_active and not is_deleted) then raise exception 'INVALID_PARTY' using errcode='22023'; end if;
  insert into public.dispute_parties(case_id,employee_id,party_type,notification_status,created_by)
  values(v_id,v_party,case when coalesce(v_item->>'type','respondent') in ('respondent','related') then coalesce(v_item->>'type','respondent') else 'respondent' end,'withheld',auth.uid())
  on conflict(case_id,employee_id,party_type) do nothing;
  if v_first_respondent is null and coalesce(v_item->>'type','respondent')='respondent' then v_first_respondent=v_party; end if;
 end loop;
 for v_item in select * from jsonb_array_elements(coalesce(p_witnesses,'[]'::jsonb)) loop
  v_party=(v_item->>'employeeId')::uuid;
  if v_party=v_emp or not exists(select 1 from public.employees where id=v_party and status='active' and is_active and not is_deleted) then raise exception 'INVALID_WITNESS' using errcode='22023'; end if;
  insert into public.dispute_parties(case_id,employee_id,party_type,notification_status,created_by)
  values(v_id,v_party,'witness','withheld',auth.uid()) on conflict(case_id,employee_id,party_type) do nothing;
 end loop;
 update public.dispute_cases set respondent_employee_id=v_first_respondent where id=v_id;
 insert into public.dispute_actions(case_id,action_type,to_status,note,actor_employee_id,actor_user_id,metadata)
 values(v_id,'submit','submitted','تم تقديم المشكلة',v_emp,auth.uid(),jsonb_build_object('priority',p_priority));
 perform public.log_audit_event('dispute.submitted','workflow','notice','dispute_cases',v_id,'تقديم مشكلة جديدة',null,jsonb_build_object('caseNumber',v_number,'priority',p_priority));
 perform public.notify_dispute_admins(v_id,'submitted','مشكلة جديدة تنتظر المراجعة',v_number||' — '||trim(p_title),case when p_priority='urgent' then 'urgent' else 'high' end);
 return v_id;
end $$;

-- =====================================================================
-- 9) set_dispute_committee (0059) — p_members — سقف 100
-- =====================================================================
create or replace function public.set_dispute_committee(p_case_id uuid,p_members jsonb)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_item jsonb; v_emp uuid; v_role text; v_status text; v_voters integer;
begin
 if not(public.current_is_full_access() or public.has_permission('disputes.committee.manage')) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if jsonb_typeof(p_members)<>'array' or jsonb_array_length(p_members)<2 then raise exception 'COMMITTEE_TOO_SMALL'; end if;
 if jsonb_array_length(p_members)>100 then raise exception 'ERR_BATCH_TOO_LARGE' using errcode='22023'; end if;
 select status into strict v_status from public.dispute_cases where id=p_case_id for update;
 if v_status not in ('accepted','under_review','returned_to_committee','reopened') then raise exception 'INVALID_STATE'; end if;
 delete from public.committee_members where case_id=p_case_id;
 for v_item in select * from jsonb_array_elements(p_members) loop
  v_emp=(v_item->>'employeeId')::uuid; v_role=coalesce(v_item->>'role','member');
  if v_role not in ('chair','secretary','member','observer','advisor') then raise exception 'INVALID_COMMITTEE_ROLE'; end if;
  if not exists(select 1 from public.employees where id=v_emp and status='active' and is_active and not is_deleted) then raise exception 'INVALID_COMMITTEE_MEMBER'; end if;
  if exists(select 1 from public.dispute_parties where case_id=p_case_id and employee_id=v_emp) then raise exception 'PARTY_CANNOT_JOIN_COMMITTEE'; end if;
  insert into public.committee_members(case_id,committee_name,employee_id,role_in_committee,created_by)
  values(p_case_id,'لجنة حل المشكلات والخلافات',v_emp,v_role,auth.uid());
 end loop;
 if not exists(select 1 from public.committee_members where case_id=p_case_id and role_in_committee='chair') then raise exception 'CHAIR_REQUIRED'; end if;
 select count(*) into v_voters from public.committee_members where case_id=p_case_id and role_in_committee in ('chair','secretary','member') and is_active;
 if (select committee_quorum from public.dispute_cases where id=p_case_id)>v_voters then raise exception 'QUORUM_EXCEEDS_VOTERS'; end if;
 update public.dispute_cases set status='under_review',updated_at=now() where id=p_case_id;
 insert into public.dispute_actions(case_id,action_type,from_status,to_status,actor_employee_id,actor_user_id,metadata)
 values(p_case_id,'committee_assigned',v_status,'under_review',public.current_employee_id(),auth.uid(),jsonb_build_object('members',jsonb_array_length(p_members)));
 perform public.log_audit_event('dispute.committee_assigned','workflow','notice','dispute_cases',p_case_id,'تشكيل لجنة المشكلة',null,jsonb_build_object('members',jsonb_array_length(p_members)));
end $$;

-- =====================================================================
-- 10) schedule_dispute_session_v2 (0059) — p_participants — سقف 200
--     يغطّي غلاف schedule_dispute_session (language sql) المفوِّض إليها.
-- =====================================================================
create or replace function public.schedule_dispute_session_v2(p_case_id uuid,p_type text,p_scheduled_at timestamptz,p_ends_at timestamptz default null,p_location text default null,p_modality text default 'in_person',p_participants jsonb default '[]'::jsonb)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid; v_item jsonb; v_emp uuid; v_role text; v_status text;
begin
 if not(public.current_is_full_access() or public.has_permission('disputes.session.manage') or exists(select 1 from public.committee_members where case_id=p_case_id and employee_id=public.current_employee_id() and role_in_committee in ('chair','secretary') and is_active)) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if p_scheduled_at<=now() or (p_ends_at is not null and p_ends_at<=p_scheduled_at) or p_modality not in ('in_person','remote','hybrid') then raise exception 'INVALID_SESSION'; end if;
 if jsonb_array_length(coalesce(p_participants,'[]'::jsonb))>200 then raise exception 'ERR_BATCH_TOO_LARGE' using errcode='22023'; end if;
 select status into strict v_status from public.dispute_cases where id=p_case_id for update;
 insert into public.dispute_sessions(case_id,session_type,scheduled_at,ends_at,location,modality,status,created_by)
 values(p_case_id,p_type,p_scheduled_at,p_ends_at,nullif(trim(p_location),''),p_modality,'scheduled',auth.uid()) returning id into v_id;
 for v_item in select * from jsonb_array_elements(coalesce(p_participants,'[]'::jsonb)) loop
  v_emp=(v_item->>'employeeId')::uuid; v_role=coalesce(v_item->>'role','guest');
  if not exists(select 1 from public.employees where id=v_emp and status='active' and is_active and not is_deleted) then raise exception 'INVALID_SESSION_PARTICIPANT'; end if;
  insert into public.dispute_session_participants(session_id,employee_id,participant_role,created_by) values(v_id,v_emp,v_role,auth.uid()) on conflict do nothing;
  perform public.enqueue_dispute_notification(p_case_id,v_emp,'session:'||v_id::text,'تم تحديد جلسة للمشكلة','موعد الجلسة: '||to_char(p_scheduled_at at time zone 'Africa/Cairo','YYYY-MM-DD HH24:MI'),'high');
 end loop;
 update public.dispute_cases set status='session_scheduled',updated_at=now() where id=p_case_id;
 insert into public.dispute_actions(case_id,action_type,from_status,to_status,actor_employee_id,actor_user_id,metadata)
 values(p_case_id,'session_scheduled',v_status,'session_scheduled',public.current_employee_id(),auth.uid(),jsonb_build_object('sessionId',v_id,'scheduledAt',p_scheduled_at));
 perform public.log_audit_event('dispute.session_scheduled','workflow','notice','dispute_sessions',v_id,'تحديد جلسة للمشكلة',null,jsonb_build_object('caseId',p_case_id));
 return v_id;
end $$;

-- =====================================================================
-- 11) finalize_dispute_session_v2 (0059) — p_attendance — سقف 100
--     يغطّي غلاف finalize_dispute_session (language sql) المفوِّض إليها.
-- =====================================================================
create or replace function public.finalize_dispute_session_v2(p_session_id uuid,p_minutes text,p_attendance jsonb,p_outcome text default null,p_minutes_data jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_session public.dispute_sessions; v_case public.dispute_cases; v_item jsonb; v_member uuid; v_present integer:=0;
begin
 select * into strict v_session from public.dispute_sessions where id=p_session_id for update;
 select * into strict v_case from public.dispute_cases where id=v_session.case_id for update;
 if not(public.current_is_full_access() or public.has_permission('disputes.session.manage') or exists(select 1 from public.committee_members where case_id=v_case.id and employee_id=public.current_employee_id() and role_in_committee in ('chair','secretary') and is_active)) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if v_session.status<>'scheduled' or length(trim(coalesce(p_minutes,'')))<20 or jsonb_typeof(p_attendance)<>'array' then raise exception 'INVALID_MINUTES'; end if;
 if jsonb_array_length(p_attendance)>100 then raise exception 'ERR_BATCH_TOO_LARGE' using errcode='22023'; end if;
 delete from public.dispute_session_attendance where session_id=p_session_id;
 for v_item in select * from jsonb_array_elements(p_attendance) loop
  v_member=(v_item->>'committeeMemberId')::uuid;
  if not exists(select 1 from public.committee_members cm where cm.id=v_member and cm.case_id=v_case.id and cm.is_active) then raise exception 'INVALID_COMMITTEE_MEMBER' using errcode='22023'; end if;
  insert into public.dispute_session_attendance(session_id,committee_member_id,attendance_status,signed_at,signature_method,created_by)
  values(p_session_id,v_member,coalesce(v_item->>'status','present'),case when coalesce(v_item->>'status','present') in ('present','remote') then now() end,case when coalesce(v_item->>'status','present') in ('present','remote') then 'manual_verified' end,auth.uid());
  if coalesce(v_item->>'status','present') in ('present','remote') then v_present=v_present+1; end if;
 end loop;
 if v_present<v_case.committee_quorum then raise exception 'QUORUM_NOT_MET'; end if;
 update public.dispute_sessions set status='held',held_at=now(),minutes=trim(p_minutes),outcome=nullif(trim(p_outcome),''),minutes_data=coalesce(p_minutes_data,'{}'::jsonb),recommendation=nullif(trim(p_minutes_data->>'recommendation'),''),follow_up_at=nullif(p_minutes_data->>'followUpAt','')::timestamptz,internal_notes=nullif(trim(p_minutes_data->>'internalNotes'),''),updated_at=now() where id=p_session_id;
 update public.dispute_cases set status='committee_deliberation',updated_at=now() where id=v_case.id;
 insert into public.dispute_actions(case_id,action_type,from_status,to_status,actor_employee_id,actor_user_id,metadata)
 values(v_case.id,'session_completed',v_case.status,'committee_deliberation',public.current_employee_id(),auth.uid(),jsonb_build_object('sessionId',p_session_id,'present',v_present));
 perform public.log_audit_event('dispute.session_completed','workflow','notice','dispute_sessions',p_session_id,'حفظ محضر جلسة المشكلة',null,jsonb_build_object('caseId',v_case.id,'present',v_present));
end $$;

-- =====================================================================
-- 12) schedule_interview_admin (0044) — p_panelists — سقف 100
-- =====================================================================
create or replace function public.schedule_interview_admin(
  p_application_id uuid,
  p_mode text,
  p_scheduled_at timestamptz,
  p_location_or_link text default null,
  p_panelists uuid[] default null,
  p_interview_id uuid default null
)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare v_id uuid; v_panelist uuid;
begin
  if not (public.current_is_full_access() or public.has_permission('recruitment.interview.manage')) then raise exception 'FORBIDDEN'; end if;
  if not exists (select 1 from public.applications where id = p_application_id) then raise exception 'APPLICATION_NOT_FOUND'; end if;
  if coalesce(p_mode,'') not in ('onsite','remote') then raise exception 'INVALID_MODE'; end if;
  if array_length(p_panelists, 1) > 100 then raise exception 'ERR_BATCH_TOO_LARGE'; end if;

  if p_interview_id is null then
    insert into public.interviews(application_id, mode, scheduled_at, location_or_link, status, created_by)
    values (p_application_id, p_mode, p_scheduled_at, nullif(trim(p_location_or_link),''), 'scheduled', auth.uid())
    returning id into v_id;
  else
    update public.interviews
      set mode = p_mode, scheduled_at = p_scheduled_at, location_or_link = nullif(trim(p_location_or_link),''), updated_at = now()
      where id = p_interview_id and application_id = p_application_id
      returning id into v_id;
    if v_id is null then raise exception 'INTERVIEW_NOT_FOUND'; end if;
  end if;

  if p_panelists is not null then
    foreach v_panelist in array p_panelists loop
      insert into public.interview_panel(interview_id, panelist_id, created_by)
      values (v_id, v_panelist, auth.uid())
      on conflict (interview_id, panelist_id) do nothing;
    end loop;
  end if;

  perform public.log_audit_event('recruitment.interview_scheduled','workflow','info','interviews',v_id,
    'جدولة/تحديث مقابلة توظيف', null, jsonb_build_object('applicationId',p_application_id,'mode',p_mode));
  return jsonb_build_object('interviewId', v_id, 'scheduledAt', p_scheduled_at);
end $$;

-- =====================================================================
-- 13) has_any_scoped_permission (0174) — p_permission_slugs — سقف 100
--     كانت language sql؛ نحوّلها إلى plpgsql لاستضافة الحارس (نفس السلوك).
-- =====================================================================
create or replace function public.has_any_scoped_permission(
  p_permission_slugs text[],
  p_scope_type text default null,
  p_scope_id uuid default null
)
returns boolean
language plpgsql stable security definer set search_path = public, pg_temp
as $$
begin
  if array_length(p_permission_slugs, 1) > 100 then
    raise exception 'ERR_BATCH_TOO_LARGE' using errcode = '22023';
  end if;
  return exists (
    select 1 from unnest(p_permission_slugs) s(slug)
    where public.has_scoped_permission(s.slug, p_scope_type, p_scope_id)
  );
end;
$$;

COMMIT;
