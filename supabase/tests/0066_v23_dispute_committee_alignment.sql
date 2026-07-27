-- 0066: V23 — dispute committee alignment (migration 0164).
-- resolved_friendly status, resolve_friendly transition, submit_my_dispute_v23 RPC,
-- updated portal summary.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(16);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. Structure: submit_my_dispute_v23 RPC exists
-- ═══════════════════════════════════════════════════════════════════════════════

select has_function(
  'public', 'submit_my_dispute_v23',
  array['text','text','text','jsonb','jsonb','boolean','boolean'],
  'submit_my_dispute_v23 RPC exists with 7 params'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2. Structure: transition_dispute_case still exists
-- ═══════════════════════════════════════════════════════════════════════════════

select has_function(
  'public', 'transition_dispute_case',
  array['uuid','text','text','jsonb'],
  'transition_dispute_case RPC exists'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 3. Structure: get_committee_dispute_portal still exists
-- ═══════════════════════════════════════════════════════════════════════════════

select has_function(
  'public', 'get_committee_dispute_portal',
  'get_committee_dispute_portal RPC exists'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 4. Status CHECK includes resolved_friendly
-- ═══════════════════════════════════════════════════════════════════════════════

select lives_ok(
  $live$do $t$
  declare v_chk text;
  begin
    select pg_get_constraintdef(c.oid) into v_chk
    from pg_constraint c join pg_class r on c.conrelid=r.oid
    where r.relname='dispute_cases' and c.conname='dispute_cases_status_check';
    if v_chk not ilike '%resolved_friendly%' then
      raise exception 'resolved_friendly not in status CHECK';
    end if;
  end $t$$live$,
  'status CHECK includes resolved_friendly'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 5. Grants: submit_my_dispute_v23 accessible to authenticated
-- ═══════════════════════════════════════════════════════════════════════════════

select lives_ok(
  $live$do $t$
  begin
    if not has_function_privilege('authenticated',
      'public.submit_my_dispute_v23(text,text,text,jsonb,jsonb,boolean,boolean)',
      'execute') then
      raise exception 'authenticated cannot execute submit_my_dispute_v23';
    end if;
  end $t$$live$,
  'authenticated can execute submit_my_dispute_v23'
);

select lives_ok(
  $live$do $t$
  begin
    if has_function_privilege('public',
      'public.submit_my_dispute_v23(text,text,text,jsonb,jsonb,boolean,boolean)',
      'execute') then
      raise exception 'public should NOT execute submit_my_dispute_v23';
    end if;
  end $t$$live$,
  'public cannot execute submit_my_dispute_v23'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- Fixtures — reuse V17 dispute test entity IDs with different UUIDs
-- ═══════════════════════════════════════════════════════════════════════════════

do $fixture$
declare
  v_entity uuid := 'a6600000-0000-4000-8000-000000000001';
  v_dept   uuid := 'a6600000-0000-4000-8000-000000000010';
begin
  insert into public.legal_entities(id, code, name)
  values(v_entity, 'V23-DSP-LE', 'كيان نزاعات V23')
  on conflict do nothing;
  insert into public.departments(id, legal_entity_id, code, name)
  values(v_dept, v_entity, 'V23-DSP-D', 'إدارة نزاعات V23')
  on conflict do nothing;

  -- 3 users: admin (full-access), complainant, respondent
  insert into auth.users(id, email, aud, role) values
    ('a6600000-0000-4000-8000-000000000101', 'v23dsp-admin@test.local', 'authenticated', 'authenticated'),
    ('a6600000-0000-4000-8000-000000000102', 'v23dsp-comp@test.local',  'authenticated', 'authenticated'),
    ('a6600000-0000-4000-8000-000000000103', 'v23dsp-resp@test.local',  'authenticated', 'authenticated')
  on conflict do nothing;

  insert into public.employees(id, user_id, employee_code, full_name_ar, department_id, status, is_active, is_deleted) values
    ('a6600000-0000-4000-8000-000000000201', 'a6600000-0000-4000-8000-000000000101', 'V23-ADM', 'مدير V23',     v_dept, 'active', true, false),
    ('a6600000-0000-4000-8000-000000000202', 'a6600000-0000-4000-8000-000000000102', 'V23-CMP', 'مشتكي V23',    v_dept, 'active', true, false),
    ('a6600000-0000-4000-8000-000000000203', 'a6600000-0000-4000-8000-000000000103', 'V23-RSP', 'مشتكى عليه V23', v_dept, 'active', true, false)
  on conflict do nothing;

  insert into public.profiles(id, employee_id, status) values
    ('a6600000-0000-4000-8000-000000000101', 'a6600000-0000-4000-8000-000000000201', 'active'),
    ('a6600000-0000-4000-8000-000000000102', 'a6600000-0000-4000-8000-000000000202', 'active'),
    ('a6600000-0000-4000-8000-000000000103', 'a6600000-0000-4000-8000-000000000203', 'active')
  on conflict do nothing;

  -- admin = full access
  insert into public.user_roles(user_id, role_id)
  select 'a6600000-0000-4000-8000-000000000101', r.id
  from public.roles r where r.slug='full-access'
  on conflict do nothing;
end $fixture$;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 6. resolve_friendly transition: happy path
-- ═══════════════════════════════════════════════════════════════════════════════

-- Insert a dispute case directly in under_review status, then resolve friendly
select lives_ok(
  $live$do $t$
  declare v_case uuid; v_next text;
  begin
    set local role to 'authenticated';
    set local request.jwt.claim.sub to 'a6600000-0000-4000-8000-000000000101';

    insert into public.dispute_cases(
      id, case_number, title, description, case_type, status, severity,
      actor_employee_id, is_confidential, privacy_level, opened_at,
      truth_confirmed, confidentiality_accepted, review_due_at, created_by
    ) values(
      'a6600000-0000-4000-8000-000000000301',
      'CASE-V23-RF-001', 'قضية حل ودي', 'وصف تجريبي لقضية الحل الودي',
      'employee_conflict', 'under_review', 'normal',
      'a6600000-0000-4000-8000-000000000202', true, 'restricted', now(),
      true, true, now() + interval '24 hours', 'a6600000-0000-4000-8000-000000000101'
    );

    -- Add complainant party
    insert into public.dispute_parties(case_id, employee_id, party_type, notification_status, created_by)
    values('a6600000-0000-4000-8000-000000000301', 'a6600000-0000-4000-8000-000000000202', 'complainant', 'read', 'a6600000-0000-4000-8000-000000000101');

    -- Add respondent party
    insert into public.dispute_parties(case_id, employee_id, party_type, notification_status, created_by)
    values('a6600000-0000-4000-8000-000000000301', 'a6600000-0000-4000-8000-000000000203', 'respondent', 'withheld', 'a6600000-0000-4000-8000-000000000101');

    v_next := public.transition_dispute_case(
      'a6600000-0000-4000-8000-000000000301',
      'resolve_friendly',
      'تم الاتفاق بين الطرفين على حل ودي'
    );

    if v_next <> 'resolved_friendly' then
      raise exception 'Expected resolved_friendly but got %', v_next;
    end if;
  end $t$$live$,
  'resolve_friendly transitions to resolved_friendly from under_review'
);

-- Verify status persisted
select is(
  (select status from public.dispute_cases where id = 'a6600000-0000-4000-8000-000000000301'),
  'resolved_friendly',
  'dispute case status is resolved_friendly after transition'
);

-- Verify resolved_at is set
select isnt(
  (select resolved_at from public.dispute_cases where id = 'a6600000-0000-4000-8000-000000000301'),
  null,
  'resolved_at is set after resolve_friendly'
);

-- Verify resolution_summary is set
select is(
  (select resolution_summary from public.dispute_cases where id = 'a6600000-0000-4000-8000-000000000301'),
  'تم الاتفاق بين الطرفين على حل ودي',
  'resolution_summary is set after resolve_friendly'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 7. close from resolved_friendly is allowed
-- ═══════════════════════════════════════════════════════════════════════════════

select lives_ok(
  $live$do $t$
  declare v_next text;
  begin
    set local role to 'authenticated';
    set local request.jwt.claim.sub to 'a6600000-0000-4000-8000-000000000101';

    v_next := public.transition_dispute_case(
      'a6600000-0000-4000-8000-000000000301',
      'close',
      'تم إغلاق القضية بعد الحل الودي'
    );

    if v_next <> 'closed' then
      raise exception 'Expected closed but got %', v_next;
    end if;
  end $t$$live$,
  'close allowed from resolved_friendly status'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 8. resolve_friendly from invalid state is rejected
-- ═══════════════════════════════════════════════════════════════════════════════

select lives_ok(
  $live$do $t$
  declare v_case uuid;
  begin
    set local role to 'authenticated';
    set local request.jwt.claim.sub to 'a6600000-0000-4000-8000-000000000101';

    insert into public.dispute_cases(
      id, case_number, title, description, case_type, status, severity,
      actor_employee_id, is_confidential, privacy_level, opened_at,
      truth_confirmed, confidentiality_accepted, review_due_at, created_by
    ) values(
      'a6600000-0000-4000-8000-000000000302',
      'CASE-V23-RF-002', 'قضية رفض حل ودي', 'وصف تجريبي لرفض الحل الودي',
      'employee_conflict', 'submitted', 'normal',
      'a6600000-0000-4000-8000-000000000202', true, 'restricted', now(),
      true, true, now() + interval '24 hours', 'a6600000-0000-4000-8000-000000000101'
    );

    begin
      perform public.transition_dispute_case(
        'a6600000-0000-4000-8000-000000000302',
        'resolve_friendly',
        'محاولة حل ودي من حالة غير مسموحة'
      );
      raise exception 'should have raised INVALID_STATE';
    exception when others then
      if sqlerrm not like '%INVALID_STATE%' then
        raise exception 'unexpected error: %', sqlerrm;
      end if;
    end;
  end $t$$live$,
  'resolve_friendly rejected from submitted status (INVALID_STATE)'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 9. resolve_friendly requires reason (min 5 chars)
-- ═══════════════════════════════════════════════════════════════════════════════

select lives_ok(
  $live$do $t$
  begin
    set local role to 'authenticated';
    set local request.jwt.claim.sub to 'a6600000-0000-4000-8000-000000000101';

    -- Set case 302 to under_review first
    update public.dispute_cases set status='under_review' where id='a6600000-0000-4000-8000-000000000302';

    begin
      perform public.transition_dispute_case(
        'a6600000-0000-4000-8000-000000000302',
        'resolve_friendly',
        'قص'
      );
      raise exception 'should have raised REASON_REQUIRED';
    exception when others then
      if sqlerrm not like '%REASON_REQUIRED%' then
        raise exception 'unexpected error: %', sqlerrm;
      end if;
    end;
  end $t$$live$,
  'resolve_friendly requires reason >= 5 chars'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 10. Audit trail: dispute action logged for resolve_friendly
-- ═══════════════════════════════════════════════════════════════════════════════

select is(
  (select count(*)::int from public.dispute_actions
   where case_id = 'a6600000-0000-4000-8000-000000000301'
     and action_type = 'resolve_friendly'),
  1,
  'resolve_friendly action logged in dispute_actions'
);

select * from finish();
rollback;
