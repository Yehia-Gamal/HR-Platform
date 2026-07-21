-- =====================================================================
-- Demo seed for LOCAL Supabase preview (idempotent).
-- Creates: employee, executive-director, HR accounts; manager links;
-- Menyal Shiha compound work-site + 300m geofence + shift assignment;
-- one pending live-location request (executive -> employee).
-- Re-runnable: deletes prior demo rows first.
-- Passwords: Demo12345 / Exec12345 / Hr123456789
-- =====================================================================
\set ON_ERROR_STOP on
\pset pager off

create extension if not exists pgcrypto;

-- --- Clean any previous demo data (child-safe order) -----------------
do $$
declare
  v_uids uuid[];
  v_emps uuid[];
begin
  select coalesce(array_agg(id), '{}') into v_uids
    from auth.users where email in ('demo@ahla.local','exec@ahla.local','hr@ahla.local');
  select coalesce(array_agg(id), '{}') into v_emps
    from public.employees where employee_code in ('DEMO001','EXEC001','HR001');

  delete from public.live_location_requests where employee_id = any(v_emps);
  delete from public.shift_assignments      where employee_id = any(v_emps);
  delete from public.manager_relations
     where employee_id = any(v_emps) or manager_employee_id = any(v_emps);
  delete from public.user_roles where user_id = any(v_uids);
  delete from public.profiles  where id = any(v_uids);
  delete from public.employees where id = any(v_emps);
  delete from auth.users       where id = any(v_uids);
end $$;

-- --- Helper: insert an auth user with all token cols pre-filled ------
-- (avoids GoTrue "Database error querying schema" from NULL token cols)
create or replace function pg_temp.mk_user(p_email text, p_password text)
returns uuid language plpgsql as $$
declare v_uid uuid := gen_random_uuid();
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change,
    email_change_token_current, phone_change, phone_change_token, reauthentication_token
  ) values (
    '00000000-0000-0000-0000-000000000000', v_uid, 'authenticated', 'authenticated',
    p_email, crypt(p_password, gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(),
    '', '', '', '', '', '', '', ''
  );
  return v_uid;
end $$;

-- --- Build everything in one transaction ----------------------------
do $$
declare
  u_emp uuid; u_exec uuid; u_hr uuid;
  e_emp uuid := gen_random_uuid();
  e_exec uuid := gen_random_uuid();
  e_hr uuid := gen_random_uuid();
  r_exec uuid; r_hr uuid;
  le uuid := gen_random_uuid();
  br uuid := gen_random_uuid();
  ws uuid := gen_random_uuid();
  gf uuid := gen_random_uuid();
  sh uuid := gen_random_uuid();
  -- Menyal Shiha compound
  c_lat double precision := 29.950608064639997;
  c_lng double precision := 31.238103680290173;
begin
  select id into r_exec from public.roles where slug = 'executive-director';
  select id into r_hr   from public.roles where slug = 'hr-manager';

  -- 1) Auth users
  u_emp  := pg_temp.mk_user('demo@ahla.local', 'Demo12345');
  u_exec := pg_temp.mk_user('exec@ahla.local', 'Exec12345');
  u_hr   := pg_temp.mk_user('hr@ahla.local',   'Hr123456789');

  -- 2) Employees
  insert into public.employees (id, user_id, employee_code, full_name_ar, status, is_active) values
    (e_emp,  u_emp,  'DEMO001', 'موظف تجريبي',            'active', true),
    (e_exec, u_exec, 'EXEC001', 'المدير التنفيذي التجريبي','active', true),
    (e_hr,   u_hr,   'HR001',   'مسؤول الموارد البشرية',   'active', true);

  -- 3) Profiles (active), primary_role for display
  insert into public.profiles (id, employee_id, primary_role_id, status) values
    (u_emp,  e_emp,  null,   'active'),
    (u_exec, e_exec, r_exec, 'active'),
    (u_hr,   e_hr,   r_hr,   'active');

  -- 4) Roles
  insert into public.user_roles (user_id, role_id, effective_from) values
    (u_exec, r_exec, now()),
    (u_hr,   r_hr,   now());

  -- 5) Manager relations: employee -> executive (primary), employee -> HR (functional)
  insert into public.manager_relations (employee_id, manager_employee_id, relation_type, effective_from) values
    (e_emp, e_exec, 'primary',    current_date),
    (e_emp, e_hr,   'functional', current_date);

  -- 6) Org chain: legal_entity -> branch -> work_site (compound)
  insert into public.legal_entities (id, code, name) values (le, 'AHLA', 'أحلى شباب');
  insert into public.branches (id, legal_entity_id, code, name) values (br, le, 'MENYAL', 'فرع منيل شيحة');
  insert into public.work_sites (id, branch_id, code, name, address, latitude, longitude)
    values (ws, br, 'MENYAL-HQ', 'مجمع أحلى شباب منيل شيحة',
            'شارع مزلقان العرب, Manil Shihah, Abu El Numrus, Giza Governorate 12912',
            c_lat, c_lng);

  -- 7) Geofence: 300m radius at compound, max GPS accuracy 100m
  insert into public.geofences (id, work_site_id, code, name, latitude, longitude, radius_meters, max_accuracy)
    values (gf, ws, 'MENYAL-GF', 'نطاق مجمع منيل شيحة', c_lat, c_lng, 300, 100);

  -- 8) Shift + assignment linking employee to the geofence (enables 300m punch check)
  insert into public.shifts (id, code, name, start_time, end_time)
    values (sh, 'DAY', 'الوردية الصباحية', '09:00', '17:00');
  insert into public.shift_assignments (employee_id, shift_id, work_site_id, geofence_id, effective_from)
    values (e_emp, sh, ws, gf, current_date);

  -- 9) Pending live-location request: executive -> employee, 5s video mode
  insert into public.live_location_requests
    (employee_id, requested_by, reason, status, purpose, requested_at, expires_at, duration_minutes, metadata)
  values
    (e_emp, e_exec, 'التحقق من الموقع الحالي (تجريبي)', 'pending', 'verification',
     now(), now() + interval '30 minutes', 1,
     jsonb_build_object('mode','video_5s','videoSeconds',5));

  raise notice 'SEED OK: emp=% exec=% hr=% geofence=% (300m @ %,%)', e_emp, e_exec, e_hr, gf, c_lat, c_lng;
end $$;

-- --- Verify ----------------------------------------------------------
\echo '=== accounts ==='
select u.email, e.employee_code, e.full_name_ar,
       coalesce(array_agg(r.slug) filter (where r.slug is not null), '{}') as roles
from auth.users u
join public.profiles p on p.id = u.id
join public.employees e on e.id = p.employee_id
left join public.user_roles ur on ur.user_id = u.id
left join public.roles r on r.id = ur.role_id
where u.email in ('demo@ahla.local','exec@ahla.local','hr@ahla.local')
group by u.email, e.employee_code, e.full_name_ar order by e.employee_code;

\echo '=== manager relations for DEMO001 ==='
select me.employee_code as employee, mm.employee_code as manager, mr.relation_type
from public.manager_relations mr
join public.employees me on me.id = mr.employee_id
join public.employees mm on mm.id = mr.manager_employee_id
where me.employee_code = 'DEMO001';

\echo '=== geofence + assignment ==='
select g.name, g.latitude, g.longitude, g.radius_meters, g.max_accuracy
from public.geofences g where g.code = 'MENYAL-GF';

\echo '=== pending location request ==='
select llr.status, llr.metadata->>'mode' as mode, llr.metadata->>'videoSeconds' as secs, llr.expires_at
from public.live_location_requests llr
join public.employees e on e.id = llr.employee_id
where e.employee_code = 'DEMO001';
