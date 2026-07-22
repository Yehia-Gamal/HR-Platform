-- Migration 0032: mobile self-service catalogs and runtime hardening
begin;

-- Treat NULL organization/branch values as equal when closing a period.
alter table public.attendance_periods
  drop constraint if exists attendance_periods_period_month_legal_entity_id_branch_id_key;
create unique index if not exists ux_attendance_period_scope
  on public.attendance_periods(period_month, legal_entity_id, branch_id) nulls not distinct;

-- A replacement published roster supersedes previous assignments for the same employee/day.
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

create or replace function public.get_my_attendance_services(
  p_from date default current_date - 31,
  p_to date default current_date + 45
)
returns jsonb
language plpgsql
stable
security definer
set search_path=public,pg_temp
as $$
declare
  v_emp uuid := public.current_employee_id();
begin
  if v_emp is null then raise exception 'NO_EMPLOYEE'; end if;
  if p_to < p_from or p_to-p_from > 370 then raise exception 'INVALID_RANGE'; end if;

  return jsonb_build_object(
    'schedule', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',d.id,
        'workDate',d.work_date,
        'dayStatus',d.day_status,
        'shiftId',d.shift_id,
        'shiftName',s.name,
        'startTime',coalesce(d.start_override,s.start_time),
        'endTime',coalesce(d.end_override,s.end_time),
        'workSiteId',d.work_site_id,
        'notes',d.notes
      ) order by d.work_date)
      from public.roster_days d
      left join public.shifts s on s.id=d.shift_id
      join public.work_rosters r on r.id=d.roster_id
      where d.employee_id=v_emp and d.work_date between p_from and p_to
        and d.day_status<>'cancelled' and r.status='published'
    ),'[]'::jsonb),
    'corrections', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',c.id,
        'workDate',c.work_date,
        'type',c.correction_type,
        'reason',c.reason,
        'status',c.status,
        'requestedCheckIn',c.requested_check_in,
        'requestedCheckOut',c.requested_check_out,
        'requestedStatus',c.requested_status,
        'reviewNote',c.review_note,
        'createdAt',c.created_at
      ) order by c.created_at desc)
      from public.attendance_corrections c
      where c.employee_id=v_emp and c.work_date between p_from and p_to
    ),'[]'::jsonb),
    'periods', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',p.id,'periodMonth',p.period_month,'status',p.status,'closedAt',p.closed_at
      ) order by p.period_month desc)
      from public.attendance_periods p
      join public.employees e on e.id=v_emp
      where p.period_month between date_trunc('month',p_from)::date and date_trunc('month',p_to)::date
        and (p.branch_id is null or p.branch_id=e.branch_id)
        and (p.legal_entity_id is null or p.legal_entity_id=e.legal_entity_id)
    ),'[]'::jsonb),
    'lastUpdatedAt',now()
  );
end $$;

create or replace function public.get_my_dispute_portal()
returns jsonb
language plpgsql
stable
security definer
set search_path=public,pg_temp
as $$
declare v_emp uuid:=public.current_employee_id();
begin
  if v_emp is null then raise exception 'NO_EMPLOYEE'; end if;
  return jsonb_build_object(
    'cases',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',c.id,'caseNumber',c.case_number,'title',c.title,'description',c.description,
        'caseType',c.case_type,'status',c.status,'severity',c.severity,
        'respondentEmployeeId',c.respondent_employee_id,
        'respondentName',respondent.full_name_ar,
        'isConfidential',c.is_confidential,'openedAt',c.opened_at,
        'acceptedAt',c.accepted_at,'decisionDueAt',c.decision_due_at,
        'canCancel',(c.actor_employee_id=v_emp and c.status='submitted' and c.accepted_at is null),
        'isCommitteeMember',exists(select 1 from public.committee_members m where m.case_id=c.id and m.employee_id=v_emp and m.is_active)
      ) order by c.opened_at desc)
      from public.dispute_cases c
      left join public.employees respondent on respondent.id=c.respondent_employee_id
      where public.can_access_dispute(c.id)
    ),'[]'::jsonb),
    'decisions',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',d.id,'caseId',d.case_id,'decisionNumber',d.decision_number,
        'decisionText',d.decision_text,'rationale',d.rationale,
        'outcomeType',d.outcome_type,'status',d.status,'issuedAt',d.issued_at,
        'canAppeal',exists(
          select 1 from public.dispute_cases c
          where c.id=d.case_id and v_emp in (c.actor_employee_id,c.respondent_employee_id)
            and (c.appeal_deadline is null or c.appeal_deadline>=now())
            and not exists(select 1 from public.dispute_appeals a where a.decision_id=d.id and a.appellant_employee_id=v_emp)
        )
      ) order by d.created_at desc)
      from public.dispute_decisions d where public.can_access_dispute(d.case_id) and d.status in ('approved','issued','implemented')
    ),'[]'::jsonb),
    'appeals',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',a.id,'caseId',a.case_id,'decisionId',a.decision_id,'reason',a.reason,
        'status',a.status,'submittedAt',a.submitted_at,'resolution',a.resolution,'reviewedAt',a.reviewed_at
      ) order by a.submitted_at desc)
      from public.dispute_appeals a where a.appellant_employee_id=v_emp
    ),'[]'::jsonb),
    'lastUpdatedAt',now()
  );
end $$;

create or replace function public.get_my_offboarding_portal()
returns jsonb
language plpgsql
stable
security definer
set search_path=public,pg_temp
as $$
declare v_emp uuid:=public.current_employee_id(); v_case uuid;
begin
  if v_emp is null then raise exception 'NO_EMPLOYEE'; end if;
  select id into v_case from public.offboarding_cases
   where employee_id=v_emp and status not in ('completed','cancelled')
   order by created_at desc limit 1;

  return jsonb_build_object(
    'case',case when v_case is null then null else (
      select jsonb_build_object(
        'id',o.id,'caseNumber',o.case_number,'reasonType',o.reason_type,'reason',o.reason,
        'noticeDate',o.notice_date,'lastWorkingDate',o.last_working_date,'status',o.status,
        'handoverEmployeeId',o.handover_employee_id,'approvedAt',o.approved_at
      ) from public.offboarding_cases o where o.id=v_case
    ) end,
    'clearance',coalesce((select jsonb_agg(jsonb_build_object(
      'id',i.id,'category',i.category,'title',i.title,'status',i.status,'dueAt',i.due_at,
      'completionNote',i.completion_note,'completedAt',i.completed_at
    ) order by i.created_at) from public.offboarding_clearance_items i where i.offboarding_case_id=v_case),'[]'::jsonb),
    'knowledgeTransfer',coalesce((select jsonb_agg(jsonb_build_object(
      'id',k.id,'title',k.title,'description',k.description,'status',k.status,
      'destinationEmployeeId',k.destination_employee_id,'acknowledgedAt',k.acknowledged_at
    ) order by k.created_at) from public.knowledge_transfer_items k where k.offboarding_case_id=v_case),'[]'::jsonb),
    'assignedAssets',coalesce((select jsonb_agg(jsonb_build_object(
      'assignmentId',aa.id,'assetId',a.id,'assetCode',a.asset_code,'assetName',a.name,
      'assignedAt',aa.assigned_at,'status',aa.status
    ) order by aa.assigned_at desc) from public.asset_assignments aa join public.asset_inventory a on a.id=aa.asset_id
      where aa.employee_id=v_emp and aa.status='assigned'),'[]'::jsonb),
    'lastUpdatedAt',now()
  );
end $$;

revoke execute on function public.publish_roster_admin(text,date,date,uuid,uuid,uuid,jsonb,text) from public;
grant execute on function public.publish_roster_admin(text,date,date,uuid,uuid,uuid,jsonb,text) to authenticated;
revoke execute on function public.get_my_attendance_services(date,date) from public;
grant execute on function public.get_my_attendance_services(date,date) to authenticated;
revoke execute on function public.get_my_dispute_portal() from public;
grant execute on function public.get_my_dispute_portal() to authenticated;
revoke execute on function public.get_my_offboarding_portal() from public;
grant execute on function public.get_my_offboarding_portal() to authenticated;

commit;
