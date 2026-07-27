-- 0066: V23 — dispute committee alignment (migration 0161).
-- Tests: resolved_friendly status, submit_my_dispute_v23 RPC,
-- resolve_friendly transition, portal summary key.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(16);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. Structure — submit_my_dispute_v23 RPC exists
-- ═══════════════════════════════════════════════════════════════════════════════

select has_function(
  'public', 'submit_my_dispute_v23',
  array['text','text','text','jsonb','jsonb','boolean','boolean'],
  'submit_my_dispute_v23 RPC exists with 7 params'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2. Structure — transition_dispute_case still exists
-- ═══════════════════════════════════════════════════════════════════════════════

select has_function(
  'public', 'transition_dispute_case',
  array['uuid','text','text','jsonb'],
  'transition_dispute_case RPC exists'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 3. Structure — get_committee_dispute_portal still exists
-- ═══════════════════════════════════════════════════════════════════════════════

select has_function(
  'public', 'get_committee_dispute_portal',
  '{}',
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
-- 5. Security — submit_my_dispute_v23 is SECURITY DEFINER
-- ═══════════════════════════════════════════════════════════════════════════════

select is(
  (select prosecdef from pg_proc where proname='submit_my_dispute_v23' and pronamespace='public'::regnamespace limit 1),
  true,
  'submit_my_dispute_v23 is security definer'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 6. Security — transition_dispute_case is SECURITY DEFINER
-- ═══════════════════════════════════════════════════════════════════════════════

select is(
  (select prosecdef from pg_proc where proname='transition_dispute_case' and pronamespace='public'::regnamespace limit 1),
  true,
  'transition_dispute_case is security definer'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 7. Security — submit_my_dispute_v23 not executable by public
-- ═══════════════════════════════════════════════════════════════════════════════

select is(
  (select has_function_privilege('public', 'submit_my_dispute_v23(text,text,text,jsonb,jsonb,boolean,boolean)', 'execute')),
  false,
  'submit_my_dispute_v23 not executable by public role'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 8. Security — submit_my_dispute_v23 executable by authenticated
-- ═══════════════════════════════════════════════════════════════════════════════

select is(
  (select has_function_privilege('authenticated', 'submit_my_dispute_v23(text,text,text,jsonb,jsonb,boolean,boolean)', 'execute')),
  true,
  'submit_my_dispute_v23 executable by authenticated'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- Fixtures — lightweight: one admin user, one employee, one dispute case
-- ═══════════════════════════════════════════════════════════════════════════════

do $fixture$
declare
  v_entity uuid := 'b6600000-0000-4000-8000-000000000001';
  v_dept   uuid := 'b6600000-0000-4000-8000-000000000010';
begin
  insert into public.legal_entities(id, code, name)
  values(v_entity, 'V23-DSP-LE', 'كيان نزاعات V23')
  on conflict do nothing;
  insert into public.departments(id, legal_entity_id, code, name)
  values(v_dept, v_entity, 'V23-DSP-D', 'إدارة نزاعات V23')
  on conflict do nothing;

  -- 2 users: admin (full-access), employee
  insert into auth.users(id, email, aud, role) values
    ('b6600000-0000-4000-8000-000000000101', 'v23dsp-admin@test.local', 'authenticated', 'authenticated'),
    ('b6600000-0000-4000-8000-000000000102', 'v23dsp-emp@test.local',   'authenticated', 'authenticated')
  on conflict do nothing;

  insert into public.employees(id, user_id, employee_code, full_name_ar, department_id, status, is_active, is_deleted) values
    ('b6600000-0000-4000-8000-000000000201', 'b6600000-0000-4000-8000-000000000101', 'V23-ADM', 'مدير نزاعات V23',  v_dept, 'active', true, false),
    ('b6600000-0000-4000-8000-000000000202', 'b6600000-0000-4000-8000-000000000102', 'V23-EMP', 'موظف نزاعات V23',  v_dept, 'active', true, false)
  on conflict do nothing;

  insert into public.profiles(id, employee_id, status) values
    ('b6600000-0000-4000-8000-000000000101', 'b6600000-0000-4000-8000-000000000201', 'active'),
    ('b6600000-0000-4000-8000-000000000102', 'b6600000-0000-4000-8000-000000000202', 'active')
  on conflict do nothing;

  -- admin = full access
  insert into public.user_roles(user_id, role_id)
  select 'b6600000-0000-4000-8000-000000000101', id
  from public.roles where slug='full-access'
  on conflict do nothing;
end $fixture$;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 9. resolved_friendly is a valid status (direct INSERT)
-- ═══════════════════════════════════════════════════════════════════════════════

select lives_ok(
  $live$
    insert into public.dispute_cases(
      id, case_number, title, description, case_type, status,
      severity, actor_employee_id, is_confidential, privacy_level,
      opened_at, truth_confirmed, confidentiality_accepted,
      review_due_at, created_by
    ) values(
      'b6600000-0000-4000-8000-000000000301',
      'CASE-V23-RF-01', 'حالة حل ودي', 'وصف الحالة للاختبار', 'other',
      'resolved_friendly', 'normal',
      'b6600000-0000-4000-8000-000000000202', true, 'restricted',
      now(), true, true, now() + interval '24 hours',
      'b6600000-0000-4000-8000-000000000101'
    )
  $live$,
  'resolved_friendly is a valid status for dispute_cases'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 10. transition resolve_friendly: from under_review → resolved_friendly
-- ═══════════════════════════════════════════════════════════════════════════════

-- Set up a case in under_review status
do $setup$
begin
  insert into public.dispute_cases(
    id, case_number, title, description, case_type, status,
    severity, actor_employee_id, is_confidential, privacy_level,
    opened_at, truth_confirmed, confidentiality_accepted,
    review_due_at, created_by
  ) values(
    'b6600000-0000-4000-8000-000000000302',
    'CASE-V23-RF-02', 'قضية مراجعة V23', 'وصف تفصيلي لاختبار الانتقال', 'employee_conflict',
    'under_review', 'normal',
    'b6600000-0000-4000-8000-000000000202', true, 'restricted',
    now(), true, true, now() + interval '7 days',
    'b6600000-0000-4000-8000-000000000101'
  );
end $setup$;

-- Transition as admin
set local role authenticated;
set local request.jwt.claims = '{"sub":"b6600000-0000-4000-8000-000000000101"}';

select is(
  public.transition_dispute_case(
    'b6600000-0000-4000-8000-000000000302'::uuid,
    'resolve_friendly',
    'تم الاتفاق بين الأطراف وديًا'
  ),
  'resolved_friendly',
  'resolve_friendly transitions to resolved_friendly'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 11. Verify case status is now resolved_friendly
-- ═══════════════════════════════════════════════════════════════════════════════

reset role;

select is(
  (select status from public.dispute_cases where id='b6600000-0000-4000-8000-000000000302'),
  'resolved_friendly',
  'case status is resolved_friendly after transition'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 12. Verify resolved_at was set
-- ═══════════════════════════════════════════════════════════════════════════════

select isnt(
  (select resolved_at from public.dispute_cases where id='b6600000-0000-4000-8000-000000000302'),
  null::timestamptz,
  'resolved_at is set after resolve_friendly'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 13. Close is allowed from resolved_friendly
-- ═══════════════════════════════════════════════════════════════════════════════

set local role authenticated;
set local request.jwt.claims = '{"sub":"b6600000-0000-4000-8000-000000000101"}';

select is(
  public.transition_dispute_case(
    'b6600000-0000-4000-8000-000000000302'::uuid,
    'close',
    'تم إغلاق القضية بعد الحل الودي'
  ),
  'closed',
  'close is allowed from resolved_friendly'
);

reset role;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 14. resolve_friendly rejected from invalid state (submitted)
-- ═══════════════════════════════════════════════════════════════════════════════

do $setup2$
begin
  insert into public.dispute_cases(
    id, case_number, title, description, case_type, status,
    severity, actor_employee_id, is_confidential, privacy_level,
    opened_at, truth_confirmed, confidentiality_accepted,
    review_due_at, created_by
  ) values(
    'b6600000-0000-4000-8000-000000000303',
    'CASE-V23-RF-03', 'قضية مقدمة V23', 'لا يجوز الحل الودي من حالة مقدمة', 'other',
    'submitted', 'normal',
    'b6600000-0000-4000-8000-000000000202', true, 'restricted',
    now(), true, true, now() + interval '24 hours',
    'b6600000-0000-4000-8000-000000000101'
  );
end $setup2$;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b6600000-0000-4000-8000-000000000101"}';

select throws_ok(
  $throw$select public.transition_dispute_case(
    'b6600000-0000-4000-8000-000000000303'::uuid,
    'resolve_friendly',
    'محاولة حل ودي من حالة غير صالحة'
  )$throw$,
  'INVALID_STATE',
  'resolve_friendly rejected from submitted status'
);

reset role;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 15. resolve_friendly requires reason
-- ═══════════════════════════════════════════════════════════════════════════════

-- Use case 303 which is in submitted — but first change to under_review
update public.dispute_cases set status='under_review' where id='b6600000-0000-4000-8000-000000000303';

set local role authenticated;
set local request.jwt.claims = '{"sub":"b6600000-0000-4000-8000-000000000101"}';

select throws_ok(
  $throw$select public.transition_dispute_case(
    'b6600000-0000-4000-8000-000000000303'::uuid,
    'resolve_friendly',
    ''
  )$throw$,
  'REASON_REQUIRED',
  'resolve_friendly requires a reason'
);

reset role;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 16. Audit trail — action logged
-- ═══════════════════════════════════════════════════════════════════════════════

select is(
  (select count(*)::int from public.dispute_actions
   where case_id='b6600000-0000-4000-8000-000000000302' and action_type='resolve_friendly'),
  1,
  'resolve_friendly action is logged in dispute_actions'
);

-- ═══════════════════════════════════════════════════════════════════════════════

select * from finish();
rollback;
