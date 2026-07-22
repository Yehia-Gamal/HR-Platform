-- Migration 0019: Complete mobile KPI forms and secure attendance state.
-- Keeps the canonical application flow inside server-authored RPCs.

begin;

create or replace function public.get_kpi_evaluation_form(p_evaluation_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_eval public.kpi_evaluations;
  v_employee public.employees;
  v_cycle public.kpi_cycles;
  v_visible_stages text[] := '{}'::text[];
  v_editable_stage text;
  v_allowed boolean := false;
  v_is_owner boolean := false;
  v_criteria jsonb := '[]'::jsonb;
begin
  select * into v_eval from public.kpi_evaluations where id = p_evaluation_id;
  if not found then raise exception 'KPI evaluation not found' using errcode = 'P0002'; end if;
  select * into v_employee from public.employees where id = v_eval.employee_id;
  select * into v_cycle from public.kpi_cycles where id = v_eval.cycle_id;

  v_is_owner := v_eval.employee_id = public.current_employee_id();
  v_allowed := public.current_is_full_access()
    or v_is_owner
    or public.can_access_employee(v_eval.employee_id, 'performance.kpi.manager_assess')
    or public.has_permission('performance.kpi.secretary_review')
    or public.has_permission('performance.kpi.executive_review')
    or public.has_permission('performance.kpi.finalize')
    or public.has_permission('performance.kpi.read');
  if not v_allowed then raise exception 'KPI evaluation access denied' using errcode = '42501'; end if;

  if public.current_is_full_access()
     or public.has_permission('performance.kpi.executive_review')
     or public.has_permission('performance.kpi.finalize') then
    v_visible_stages := array['self','manager','secretary','executive'];
  elsif public.has_permission('performance.kpi.secretary_review') then
    v_visible_stages := array['self','manager','secretary'];
  elsif public.can_access_employee(v_eval.employee_id, 'performance.kpi.manager_assess') then
    v_visible_stages := array['self','manager'];
  elsif v_is_owner and v_eval.current_stage = 'finalized' then
    v_visible_stages := array['self','manager','executive'];
  else
    v_visible_stages := array['self'];
  end if;

  if not v_eval.locked and v_cycle.status <> 'locked' then
    if v_eval.current_stage = 'self' and v_is_owner
       and (public.current_is_full_access() or public.has_permission('performance.kpi.self_assess')) then
      v_editable_stage := 'self';
    elsif v_eval.current_stage = 'manager'
       and (public.current_is_full_access() or public.can_access_employee(v_eval.employee_id, 'performance.kpi.manager_assess')) then
      v_editable_stage := 'manager';
    elsif v_eval.current_stage = 'secretary'
       and (public.current_is_full_access() or public.has_permission('performance.kpi.secretary_review')) then
      v_editable_stage := 'secretary';
    elsif v_eval.current_stage = 'executive'
       and (public.current_is_full_access() or public.has_any_permission(array['performance.kpi.executive_review','performance.kpi.finalize'])) then
      v_editable_stage := 'executive';
    end if;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', c.id,
    'name', c.name_ar,
    'weight', c.weight,
    'maxScore', c.max_score,
    'sortOrder', c.sort_order,
    'stageScores', coalesce((
      select jsonb_object_agg(s.reviewer_stage, jsonb_build_object('score', s.score, 'note', s.note))
      from public.kpi_scores s
      where s.evaluation_id = v_eval.id
        and s.criterion_id = c.id
        and s.reviewer_stage = any(v_visible_stages)
    ), '{}'::jsonb)
  ) order by c.sort_order, c.created_at), '[]'::jsonb)
  into v_criteria
  from public.kpi_criteria c
  where c.template_id = v_eval.template_id;

  return jsonb_build_object(
    'id', v_eval.id,
    'employeeId', v_eval.employee_id,
    'employeeName', v_employee.full_name_ar,
    'employeeCode', v_employee.employee_code,
    'periodMonth', v_cycle.period_month,
    'currentStage', v_eval.current_stage,
    'editableStage', v_editable_stage,
    'locked', v_eval.locked or v_cycle.status = 'locked',
    'finalScore', v_eval.final_score,
    'finalRating', v_eval.final_rating,
    'criteria', v_criteria,
    'lastUpdatedAt', coalesce(v_eval.updated_at, v_eval.created_at)
  );
end;
$$;
revoke execute on function public.get_kpi_evaluation_form(uuid) from public;
grant execute on function public.get_kpi_evaluation_form(uuid) to authenticated;

create or replace function public.advance_kpi_stage(
  p_evaluation_id uuid,
  p_action text,
  p_scores jsonb default null,
  p_note text default null
)
returns public.kpi_evaluations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_eval public.kpi_evaluations;
  v_cycle public.kpi_cycles;
  v_expected text;
  v_next text;
  v_perm text;
  v_row jsonb;
  v_score numeric;
  v_max_score numeric;
  v_criterion_count integer;
  v_submitted_count integer;
  v_final_score numeric(6,2);
begin
  case p_action
    when 'self' then v_expected := 'self'; v_next := 'manager'; v_perm := 'performance.kpi.self_assess';
    when 'manager' then v_expected := 'manager'; v_next := 'secretary'; v_perm := 'performance.kpi.manager_assess';
    when 'secretary' then v_expected := 'secretary'; v_next := 'executive'; v_perm := 'performance.kpi.secretary_review';
    when 'executive' then v_expected := 'executive'; v_next := 'finalized'; v_perm := 'performance.kpi.executive_review';
    when 'finalize' then v_expected := 'executive'; v_next := 'finalized'; v_perm := 'performance.kpi.finalize';
    else raise exception 'invalid KPI action: %', p_action using errcode = '22023';
  end case;

  if p_note is not null and length(p_note) > 5000 then
    raise exception 'KPI note exceeds 5000 characters' using errcode = '22023';
  end if;

  select * into v_eval from public.kpi_evaluations where id = p_evaluation_id for update;
  if not found then raise exception 'KPI evaluation not found' using errcode = 'P0002'; end if;
  select * into v_cycle from public.kpi_cycles where id = v_eval.cycle_id;
  if v_eval.locked or v_cycle.status = 'locked' then raise exception 'KPI evaluation is locked' using errcode = '55000'; end if;
  if v_eval.current_stage is distinct from v_expected then
    raise exception 'stage_out_of_order: expected %, found %', v_expected, v_eval.current_stage using errcode = '55000';
  end if;
  if not (public.current_is_full_access() or public.has_permission(v_perm)) then
    raise exception 'insufficient privilege: % required', v_perm using errcode = '42501';
  end if;
  if p_action = 'self' and not public.current_is_full_access()
     and v_eval.employee_id is distinct from public.current_employee_id() then
    raise exception 'self assessment is restricted to the evaluated employee' using errcode = '42501';
  end if;
  if p_action = 'manager' and not public.current_is_full_access()
     and not public.can_access_employee(v_eval.employee_id, 'performance.kpi.manager_assess') then
    raise exception 'employee is outside manager scope' using errcode = '42501';
  end if;

  select count(*) into v_criterion_count
  from public.kpi_criteria where template_id = v_eval.template_id;

  if p_scores is not null and jsonb_typeof(p_scores) <> 'array' then
    raise exception 'p_scores must be a JSON array' using errcode = '22023';
  end if;
  v_submitted_count := case when p_scores is null then 0 else jsonb_array_length(p_scores) end;
  if p_action in ('self','manager') and v_criterion_count > 0 and v_submitted_count <> v_criterion_count then
    raise exception 'all KPI criteria require a score: expected %, received %', v_criterion_count, v_submitted_count using errcode = '22023';
  end if;
  if p_scores is not null and (
    select count(*) <> count(distinct (x->>'criterion_id'))
    from jsonb_array_elements(p_scores) x
  ) then
    raise exception 'duplicate KPI criterion in submitted scores' using errcode = '22023';
  end if;

  if p_scores is not null then
    for v_row in select * from jsonb_array_elements(p_scores)
    loop
      begin
        v_score := (v_row->>'score')::numeric;
      exception when others then
        raise exception 'invalid KPI score' using errcode = '22023';
      end;
      select c.max_score into v_max_score
      from public.kpi_criteria c
      where c.id = (v_row->>'criterion_id')::uuid
        and c.template_id = v_eval.template_id;
      if not found then raise exception 'criterion does not belong to evaluation template' using errcode = '22023'; end if;
      if v_score < 0 or v_score > v_max_score then
        raise exception 'KPI score must be between 0 and %', v_max_score using errcode = '22023';
      end if;
      insert into public.kpi_scores(evaluation_id, criterion_id, score, reviewer_stage, note, created_by)
      values (p_evaluation_id, (v_row->>'criterion_id')::uuid, v_score, v_expected,
              nullif(coalesce(v_row->>'note', p_note), ''), auth.uid())
      on conflict (evaluation_id, criterion_id, reviewer_stage)
      do update set score = excluded.score, note = excluded.note, updated_at = now();
    end loop;
  end if;

  if v_next = 'finalized' then
    select round(
      sum(coalesce(executive_score.score, manager_score.score, self_score.score, 0) * c.weight / c.max_score)
      / nullif(sum(c.weight), 0) * 100,
      2
    ) into v_final_score
    from public.kpi_criteria c
    left join public.kpi_scores executive_score on executive_score.evaluation_id=v_eval.id and executive_score.criterion_id=c.id and executive_score.reviewer_stage='executive'
    left join public.kpi_scores manager_score on manager_score.evaluation_id=v_eval.id and manager_score.criterion_id=c.id and manager_score.reviewer_stage='manager'
    left join public.kpi_scores self_score on self_score.evaluation_id=v_eval.id and self_score.criterion_id=c.id and self_score.reviewer_stage='self'
    where c.template_id = v_eval.template_id;
  end if;

  update public.kpi_evaluations
  set stage = v_next,
      current_stage = v_next,
      locked = (v_next = 'finalized'),
      final_score = case when v_next = 'finalized' then coalesce(v_final_score, final_score) else final_score end,
      final_rating = case
        when v_next <> 'finalized' then final_rating
        when coalesce(v_final_score, final_score) >= 90 then 'ممتاز'
        when coalesce(v_final_score, final_score) >= 80 then 'جيد جدًا'
        when coalesce(v_final_score, final_score) >= 70 then 'جيد'
        when coalesce(v_final_score, final_score) >= 60 then 'مقبول'
        else 'يحتاج تحسين'
      end,
      updated_at = now()
  where id = p_evaluation_id
  returning * into v_eval;

  perform public.log_audit_event(
    'kpi.stage_advanced', 'workflow', 'info', 'kpi_evaluations', p_evaluation_id,
    'انتقال مرحلة تقييم الأداء', null,
    jsonb_build_object('action', p_action, 'from', v_expected, 'to', v_next, 'note', p_note, 'scoreCount', v_submitted_count)
  );
  return v_eval;
end;
$$;
revoke execute on function public.advance_kpi_stage(uuid,text,jsonb,text) from public;
grant execute on function public.advance_kpi_stage(uuid,text,jsonb,text) to authenticated;


create or replace function public.return_kpi_stage(
  p_evaluation_id uuid,
  p_target_stage text,
  p_note text
)
returns public.kpi_evaluations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_eval public.kpi_evaluations;
  v_allowed_target text;
  v_perm text;
begin
  if length(trim(coalesce(p_note,''))) < 5 then
    raise exception 'return note is required' using errcode = '22023';
  end if;
  select * into v_eval from public.kpi_evaluations where id=p_evaluation_id for update;
  if not found then raise exception 'KPI evaluation not found' using errcode='P0002'; end if;
  if v_eval.locked then raise exception 'KPI evaluation is locked' using errcode='55000'; end if;

  case v_eval.current_stage
    when 'manager' then v_allowed_target := 'self'; v_perm := 'performance.kpi.manager_assess';
    when 'secretary' then v_allowed_target := 'manager'; v_perm := 'performance.kpi.secretary_review';
    when 'executive' then v_allowed_target := 'secretary'; v_perm := 'performance.kpi.executive_review';
    else raise exception 'current KPI stage cannot be returned' using errcode='55000';
  end case;
  if p_target_stage is distinct from v_allowed_target then
    raise exception 'invalid return target: expected %', v_allowed_target using errcode='22023';
  end if;
  if not (public.current_is_full_access() or public.has_permission(v_perm)) then
    raise exception 'insufficient privilege: % required', v_perm using errcode='42501';
  end if;
  if v_eval.current_stage='manager' and not public.current_is_full_access()
     and not public.can_access_employee(v_eval.employee_id,'performance.kpi.manager_assess') then
    raise exception 'employee is outside manager scope' using errcode='42501';
  end if;

  update public.kpi_evaluations
  set stage=p_target_stage,current_stage=p_target_stage,updated_at=now()
  where id=p_evaluation_id returning * into v_eval;
  perform public.log_audit_event(
    'kpi.stage_returned','workflow','warning','kpi_evaluations',p_evaluation_id,
    'إعادة تقييم الأداء للمرحلة السابقة',null,
    jsonb_build_object('from',case p_target_stage when 'self' then 'manager' when 'manager' then 'secretary' else 'executive' end,'to',p_target_stage,'note',trim(p_note))
  );
  return v_eval;
end;
$$;
revoke execute on function public.return_kpi_stage(uuid,text,text) from public;
grant execute on function public.return_kpi_stage(uuid,text,text) to authenticated;

create or replace function public.get_my_attendance_state()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_is_executive boolean;
  v_active boolean;
  v_passkeys integer := 0;
  v_last public.attendance_events;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_today_status text;
  v_suggested text := 'CHECK_IN';
begin
  if v_me is null then raise exception 'no employee linked to current user' using errcode = '42501'; end if;
  select e.is_active and not coalesce(e.is_deleted,false), exists(
    select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
    where ur.user_id=auth.uid() and r.slug in ('executive','executive-director')
      and ur.effective_from<=now() and (ur.effective_to is null or ur.effective_to>now())
  ) into v_active, v_is_executive from public.employees e where e.id=v_me;

  select count(*) into v_passkeys from public.passkey_credentials
  where employee_id=v_me and user_id=auth.uid() and status='active';
  select * into v_last from public.attendance_events
  where employee_id=v_me and (event_at at time zone 'Africa/Cairo')::date=v_today
  order by event_at desc limit 1;
  select status into v_today_status from public.attendance_daily
  where employee_id=v_me and work_date=v_today;
  if v_last.id is not null and v_last.event_type='CHECK_IN' then v_suggested := 'CHECK_OUT'; end if;

  return jsonb_build_object(
    'employeeId',v_me,
    'attendanceRequired',v_active and not v_is_executive,
    'selfPunchEnabled',v_active and not v_is_executive,
    'activePasskeys',v_passkeys,
    'hasActivePasskey',v_passkeys>0,
    'canPunch',v_active and not v_is_executive and v_passkeys>0,
    'suggestedAction',v_suggested,
    'lastEventType',v_last.event_type,
    'lastEventAt',v_last.event_at,
    'lastEventStatus',v_last.status,
    'todayStatus',v_today_status,
    'lastUpdatedAt',now()
  );
end;
$$;
revoke execute on function public.get_my_attendance_state() from public;
grant execute on function public.get_my_attendance_state() to authenticated;

commit;
