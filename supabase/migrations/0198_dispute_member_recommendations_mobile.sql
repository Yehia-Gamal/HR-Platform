-- 0198: السماح لأعضاء اللجنة بإبداء رأيهم على القضايا من الموبايل
--
-- المشكلة: submit_dispute_statement تتطلب عضوية committee_members لكل قضية.
-- الأوبريشنز والسكرتير لديهم صلاحية disputes.portal.access لكنهم ليسوا بالضرورة
-- مُعيّنين في committee_members لكل قضية.
--
-- الإصلاح:
--   1) توسيع submit_dispute_statement لتقبل recommendation/committee_note
--      من أي مستخدم لديه full_access أو disputes.portal.access أو disputes.case.read_all
--   2) RPC جديد get_dispute_case_recommendations لجلب الآراء والتوصيات لقضية محددة

begin;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1) تحديث submit_dispute_statement — توسيع الصلاحية
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.submit_dispute_statement(
  p_case_id uuid,
  p_statement_type text,
  p_statement_text text,
  p_visibility text default 'committee_only'
)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_emp uuid := public.current_employee_id();
  v_case public.dispute_cases;
  v_party public.dispute_parties;
  v_id uuid;
  v_committee boolean;
  v_authorized boolean;
begin
  if v_emp is null or length(trim(coalesce(p_statement_text,''))) < 10 then
    raise exception 'INVALID_STATEMENT';
  end if;

  select * into strict v_case from public.dispute_cases where id = p_case_id for update;

  v_committee := exists(
    select 1 from public.committee_members
    where case_id = p_case_id and employee_id = v_emp and is_active
  );

  -- 0198: السماح لأصحاب صلاحيات اللجنة بتقديم توصيات حتى بدون عضوية لكل قضية
  v_authorized := v_committee
    or public.current_is_full_access()
    or public.has_permission('disputes.portal.access')
    or public.has_permission('disputes.case.read_all');

  select * into v_party from public.dispute_parties
  where case_id = p_case_id and employee_id = v_emp
  order by case when party_type = 'complainant' then 0 else 1 end
  limit 1;

  -- إذا ليس عضو لجنة ولا صاحب صلاحية ولا طرف → ممنوع
  if not v_authorized and v_party.id is null then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if not v_authorized and v_party.party_type <> 'complainant'
     and v_party.notified_at is null then
    raise exception 'NOT_NOTIFIED' using errcode = '42501';
  end if;

  if not v_authorized and v_party.party_type = 'complainant'
     and v_case.status <> 'needs_more_information'
     and p_statement_type = 'clarification' then
    raise exception 'CLARIFICATION_NOT_REQUESTED';
  end if;

  if p_statement_type not in (
    'complainant','respondent','witness','clarification',
    'committee_note','recommendation','executive_note'
  ) or p_visibility not in (
    'committee_only','submitter_and_committee','parties','complainant','respondent'
  ) then
    raise exception 'INVALID_STATEMENT_TYPE';
  end if;

  -- committee_note/recommendation/executive_note تتطلب عضوية أو صلاحية
  if not v_authorized and p_statement_type in (
    'committee_note','recommendation','executive_note'
  ) then
    raise exception 'FORBIDDEN';
  end if;

  insert into public.dispute_statements(
    case_id, party_id, submitted_by, statement_type,
    statement_text, visibility, created_by
  ) values (
    p_case_id, v_party.id, v_emp, p_statement_type,
    trim(p_statement_text), p_visibility, auth.uid()
  ) returning id into v_id;

  if v_party.id is not null then
    update public.dispute_parties
    set statement_submitted_at = now(), updated_at = now()
    where id = v_party.id;
  end if;

  insert into public.dispute_actions(
    case_id, action_type, from_status, to_status,
    note, actor_employee_id, actor_user_id, metadata
  ) values (
    p_case_id, 'statement_added', v_case.status, v_case.status,
    'تمت إضافة إفادة', v_emp, auth.uid(),
    jsonb_build_object('statementId', v_id, 'type', p_statement_type)
  );

  perform public.log_audit_event(
    'dispute.statement_added','data','notice',
    'dispute_statements', v_id,
    'إضافة إفادة للمشكلة', null,
    jsonb_build_object('caseId', p_case_id, 'type', p_statement_type)
  );

  perform public.notify_dispute_admins(
    p_case_id, 'statement:' || v_id::text,
    'إفادة جديدة في مشكلة',
    coalesce(v_case.case_number,'') || ' — تمت إضافة إفادة جديدة',
    'normal'
  );

  return v_id;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2) RPC لجلب آراء وتوصيات أعضاء اللجنة لقضية محددة
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.get_dispute_case_recommendations(p_case_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare
  v_emp uuid := public.current_employee_id();
begin
  -- نفس بوابة الصلاحية المستخدمة في get_committee_dispute_portal
  if not(
    public.current_is_full_access()
    or public.has_permission('disputes.portal.access')
    or public.has_permission('disputes.case.read_all')
    or exists(select 1 from public.committee_members
              where employee_id = v_emp and is_active)
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  -- التحقق من وجود القضية
  if not exists(select 1 from public.dispute_cases where id = p_case_id) then
    raise exception 'CASE_NOT_FOUND' using errcode = '42P01';
  end if;

  return jsonb_build_object(
    'recommendations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', s.id,
        'submittedByName', e.full_name_ar,
        'submittedById', s.submitted_by,
        'statementType', s.statement_type,
        'statementText', s.statement_text,
        'submittedAt', s.submitted_at,
        'visibility', s.visibility,
        'isOwn', (s.submitted_by = v_emp)
      ) order by s.submitted_at desc)
      from public.dispute_statements s
      join public.employees e on e.id = s.submitted_by
      where s.case_id = p_case_id
        and s.statement_type in ('committee_note','recommendation')
    ), '[]'::jsonb),
    'myRecommendationExists', exists(
      select 1 from public.dispute_statements
      where case_id = p_case_id
        and submitted_by = v_emp
        and statement_type = 'recommendation'
    ),
    'totalCount', (
      select count(*) from public.dispute_statements
      where case_id = p_case_id
        and statement_type in ('committee_note','recommendation')
    )
  );
end $$;

revoke execute on function public.get_dispute_case_recommendations(uuid) from public;
grant execute on function public.get_dispute_case_recommendations(uuid) to authenticated;

commit;
