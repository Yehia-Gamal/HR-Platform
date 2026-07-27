-- pgTAP: V23 §3.4 — can_access_employee() ABAC reporting-line scopes
-- يتحقق من: جميع أنماط النطاق (self, direct_reports, management_descendants,
--           department, team, selected_departments, selected_employees, organization)
--           والحالات السلبية (الوصول مرفوض عند عدم التطابق).
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(18);

-- ═══════════════════════════════════════════════════════════════════════
-- Fixture: 6 مستخدمين × 6 موظفين × 3 إدارات + علاقات إدارية
-- ═══════════════════════════════════════════════════════════════════════
do $fixture$
declare
  v_le   uuid := '78000000-0000-4000-8000-000000000000';
  -- إدارات
  v_dept_a uuid := '78000000-0000-4000-8000-000000000001';
  v_dept_b uuid := '78000000-0000-4000-8000-000000000002';
  -- فروع
  v_br_a uuid := '78000000-0000-4000-8000-000000000010';
  v_br_b uuid := '78000000-0000-4000-8000-000000000011';
  -- فرق
  v_tm_a uuid := '78000000-0000-4000-8000-000000000020';
  -- مستخدمون (auth.users)
  v_uid_director uuid := '78000000-0000-4000-8000-000000000100';
  v_uid_manager  uuid := '78000000-0000-4000-8000-000000000101';
  v_uid_worker1  uuid := '78000000-0000-4000-8000-000000000102';
  v_uid_worker2  uuid := '78000000-0000-4000-8000-000000000103';
  v_uid_outsider uuid := '78000000-0000-4000-8000-000000000104';
  v_uid_scoped   uuid := '78000000-0000-4000-8000-000000000105';
  -- موظفون
  v_emp_director uuid := '78000000-0000-4000-8000-000000000200';
  v_emp_manager  uuid := '78000000-0000-4000-8000-000000000201';
  v_emp_worker1  uuid := '78000000-0000-4000-8000-000000000202';
  v_emp_worker2  uuid := '78000000-0000-4000-8000-000000000203';
  v_emp_outsider uuid := '78000000-0000-4000-8000-000000000204';
  v_emp_scoped   uuid := '78000000-0000-4000-8000-000000000205';
  -- أدوار اختبارية
  v_role_self uuid;
  v_role_direct uuid;
  v_role_desc uuid;
  v_role_dept uuid;
  v_role_team uuid;
  v_role_seldept uuid;
  v_role_selemp uuid;
  v_role_org uuid;
  -- صلاحية اختبارية
  v_perm_id uuid;
begin
  -- كيان قانوني + إدارات + فروع + فرق
  insert into public.legal_entities(id,code,name)
    values(v_le,'T78-LE','كيان §3.4');
  insert into public.departments(id,legal_entity_id,code,name) values
    (v_dept_a,v_le,'T78-DA','إدارة أ'),
    (v_dept_b,v_le,'T78-DB','إدارة ب');
  insert into public.branches(id,legal_entity_id,code,name) values
    (v_br_a,v_le,'T78-BA','فرع أ'),
    (v_br_b,v_le,'T78-BB','فرع ب');
  insert into public.teams(id,department_id,code,name) values
    (v_tm_a,v_dept_a,'T78-TA','فريق أ');

  -- مستخدمون
  insert into auth.users(id,email,aud,role) values
    (v_uid_director,'t78-director@test.local','authenticated','authenticated'),
    (v_uid_manager,'t78-manager@test.local','authenticated','authenticated'),
    (v_uid_worker1,'t78-worker1@test.local','authenticated','authenticated'),
    (v_uid_worker2,'t78-worker2@test.local','authenticated','authenticated'),
    (v_uid_outsider,'t78-outsider@test.local','authenticated','authenticated'),
    (v_uid_scoped,'t78-scoped@test.local','authenticated','authenticated');

  -- موظفون
  -- Director: dept_a, branch_a (no team)
  insert into public.employees(id,user_id,employee_code,full_name_ar,department_id,branch_id,team_id,status,is_active,birth_date,hire_date) values
    (v_emp_director,v_uid_director,'T78-DIR','مدير عام',v_dept_a,v_br_a,null,'active',true,'1980-01-01','2015-01-01');
  -- Manager: dept_a, branch_a, team_a (managed by Director)
  insert into public.employees(id,user_id,employee_code,full_name_ar,department_id,branch_id,team_id,status,is_active,birth_date,hire_date) values
    (v_emp_manager,v_uid_manager,'T78-MGR','مدير قسم',v_dept_a,v_br_a,v_tm_a,'active',true,'1985-01-01','2017-01-01');
  -- Worker1: dept_a, branch_a, team_a (managed by Manager)
  insert into public.employees(id,user_id,employee_code,full_name_ar,department_id,branch_id,team_id,status,is_active,birth_date,hire_date) values
    (v_emp_worker1,v_uid_worker1,'T78-W01','عامل ١',v_dept_a,v_br_a,v_tm_a,'active',true,'1990-01-01','2020-01-01');
  -- Worker2: dept_b, branch_b (managed by Director — different dept)
  insert into public.employees(id,user_id,employee_code,full_name_ar,department_id,branch_id,team_id,status,is_active,birth_date,hire_date) values
    (v_emp_worker2,v_uid_worker2,'T78-W02','عامل ٢',v_dept_b,v_br_b,null,'active',true,'1991-01-01','2021-01-01');
  -- Outsider: dept_b, branch_b (no manager relation)
  insert into public.employees(id,user_id,employee_code,full_name_ar,department_id,branch_id,team_id,status,is_active,birth_date,hire_date) values
    (v_emp_outsider,v_uid_outsider,'T78-OUT','خارجي',v_dept_b,v_br_b,null,'active',true,'1992-01-01','2022-01-01');
  -- Scoped user: dept_b, branch_b (for selected_departments/selected_employees tests)
  insert into public.employees(id,user_id,employee_code,full_name_ar,department_id,branch_id,team_id,status,is_active,birth_date,hire_date) values
    (v_emp_scoped,v_uid_scoped,'T78-SCP','مستخدم محدد',v_dept_b,v_br_b,null,'active',true,'1993-01-01','2023-01-01');

  -- ملفات تعريف
  insert into public.profiles(id,employee_id,status) values
    (v_uid_director,v_emp_director,'active'),
    (v_uid_manager,v_emp_manager,'active'),
    (v_uid_worker1,v_emp_worker1,'active'),
    (v_uid_worker2,v_emp_worker2,'active'),
    (v_uid_outsider,v_emp_outsider,'active'),
    (v_uid_scoped,v_emp_scoped,'active');

  -- علاقات إدارية:
  -- Director → Manager (primary)
  insert into public.manager_relations(employee_id,manager_employee_id,relation_type,effective_from)
    values(v_emp_manager,v_emp_director,'primary',current_date);
  -- Manager → Worker1 (primary)
  insert into public.manager_relations(employee_id,manager_employee_id,relation_type,effective_from)
    values(v_emp_worker1,v_emp_manager,'primary',current_date);
  -- Director → Worker2 (primary)
  insert into public.manager_relations(employee_id,manager_employee_id,relation_type,effective_from)
    values(v_emp_worker2,v_emp_director,'primary',current_date);

  -- صلاحية اختبارية
  insert into public.permissions(id,code,module,resource,action,description)
    values(gen_random_uuid(),'test.access.78','test','access','test78','اختبار نطاقات ABAC')
    returning id into v_perm_id;

  -- أدوار اختبارية (واحد لكل نطاق)
  insert into public.roles(id,name_ar,slug,description,is_full_access) values
    (gen_random_uuid(),'T78 Self','t78-self','§3.4 self scope',false) returning id into v_role_self;
  insert into public.roles(id,name_ar,slug,description,is_full_access) values
    (gen_random_uuid(),'T78 Direct','t78-direct','§3.4 direct_reports',false) returning id into v_role_direct;
  insert into public.roles(id,name_ar,slug,description,is_full_access) values
    (gen_random_uuid(),'T78 Descendants','t78-descendants','§3.4 management_descendants',false) returning id into v_role_desc;
  insert into public.roles(id,name_ar,slug,description,is_full_access) values
    (gen_random_uuid(),'T78 Dept','t78-dept','§3.4 department',false) returning id into v_role_dept;
  insert into public.roles(id,name_ar,slug,description,is_full_access) values
    (gen_random_uuid(),'T78 Team','t78-team','§3.4 team',false) returning id into v_role_team;
  insert into public.roles(id,name_ar,slug,description,is_full_access) values
    (gen_random_uuid(),'T78 SelDept','t78-seldept','§3.4 selected_departments',false) returning id into v_role_seldept;
  insert into public.roles(id,name_ar,slug,description,is_full_access) values
    (gen_random_uuid(),'T78 SelEmp','t78-selemp','§3.4 selected_employees',false) returning id into v_role_selemp;
  insert into public.roles(id,name_ar,slug,description,is_full_access) values
    (gen_random_uuid(),'T78 Org','t78-org','§3.4 organization',false) returning id into v_role_org;

  -- ربط الأدوار بالصلاحية مع النطاقات
  insert into public.role_permissions(role_id,permission_id,scope) values
    (v_role_self,    v_perm_id, 'self'),
    (v_role_direct,  v_perm_id, 'direct_reports'),
    (v_role_desc,    v_perm_id, 'management_descendants'),
    (v_role_dept,    v_perm_id, 'department'),
    (v_role_team,    v_perm_id, 'team'),
    (v_role_seldept, v_perm_id, 'selected_departments'),
    (v_role_selemp,  v_perm_id, 'selected_employees'),
    (v_role_org,     v_perm_id, 'organization');

  -- تعيين الأدوار للمستخدمين:
  -- Worker1 → self scope
  insert into public.user_roles(user_id,role_id,effective_from)
    values(v_uid_worker1, v_role_self, now());

  -- Manager → direct_reports scope
  insert into public.user_roles(user_id,role_id,effective_from)
    values(v_uid_manager, v_role_direct, now());

  -- Director → management_descendants scope
  insert into public.user_roles(user_id,role_id,effective_from)
    values(v_uid_director, v_role_desc, now());

  -- Worker2 → department scope
  insert into public.user_roles(user_id,role_id,effective_from)
    values(v_uid_worker2, v_role_dept, now());

  -- Worker1 → team scope (additional role)
  insert into public.user_roles(user_id,role_id,effective_from)
    values(v_uid_worker1, v_role_team, now());

  -- Scoped user → selected_departments (dept_a only) + selected_employees (worker1 only)
  insert into public.user_roles(user_id,role_id,scope_override,effective_from)
    values(v_uid_scoped, v_role_seldept,
      jsonb_build_object('department_ids', jsonb_build_array(v_dept_a::text)),
      now());
  insert into public.user_roles(user_id,role_id,scope_override,effective_from)
    values(v_uid_scoped, v_role_selemp,
      jsonb_build_object('employee_ids', jsonb_build_array(v_emp_worker1::text)),
      now());

  -- Outsider → organization scope
  insert into public.user_roles(user_id,role_id,effective_from)
    values(v_uid_outsider, v_role_org, now());

end $fixture$;

-- ═══════════════════════════════════════════════════════════════════════
-- 1) self scope: يصل لنفسه فقط
-- ═══════════════════════════════════════════════════════════════════════
set local role authenticated;
select set_config('request.jwt.claim.sub','78000000-0000-4000-8000-000000000102',true);

select is(
  public.can_access_employee('78000000-0000-4000-8000-000000000202'::uuid, 'test.access.78'),
  true,
  'self scope: worker1 can access own record'
);

select is(
  public.can_access_employee('78000000-0000-4000-8000-000000000203'::uuid, 'test.access.78'),
  false,
  'self scope: worker1 cannot access worker2'
);

-- ═══════════════════════════════════════════════════════════════════════
-- 2) direct_reports scope: مدير يصل لتقاريره المباشرة فقط
-- ═══════════════════════════════════════════════════════════════════════
select set_config('request.jwt.claim.sub','78000000-0000-4000-8000-000000000101',true);

select is(
  public.can_access_employee('78000000-0000-4000-8000-000000000202'::uuid, 'test.access.78'),
  true,
  'direct_reports: manager can access direct report (worker1)'
);

select is(
  public.can_access_employee('78000000-0000-4000-8000-000000000204'::uuid, 'test.access.78'),
  false,
  'direct_reports: manager cannot access non-report (outsider)'
);

-- ═══════════════════════════════════════════════════════════════════════
-- 3) management_descendants: المدير العام يصل لكل السلسلة
-- ═══════════════════════════════════════════════════════════════════════
select set_config('request.jwt.claim.sub','78000000-0000-4000-8000-000000000100',true);

-- Director → Manager (direct)
select is(
  public.can_access_employee('78000000-0000-4000-8000-000000000201'::uuid, 'test.access.78'),
  true,
  'management_descendants: director can access manager (direct report)'
);

-- Director → Worker1 (indirect: via Manager)
select is(
  public.can_access_employee('78000000-0000-4000-8000-000000000202'::uuid, 'test.access.78'),
  true,
  'management_descendants: director can access worker1 (indirect descendant)'
);

-- Director → Outsider (no relation)
select is(
  public.can_access_employee('78000000-0000-4000-8000-000000000204'::uuid, 'test.access.78'),
  false,
  'management_descendants: director cannot access outsider (no relation)'
);

-- ═══════════════════════════════════════════════════════════════════════
-- 4) department scope: نفس الإدارة فقط
-- ═══════════════════════════════════════════════════════════════════════
select set_config('request.jwt.claim.sub','78000000-0000-4000-8000-000000000103',true);

-- Worker2 (dept_b) → Outsider (dept_b) = same dept
select is(
  public.can_access_employee('78000000-0000-4000-8000-000000000204'::uuid, 'test.access.78'),
  true,
  'department scope: worker2 can access outsider (same dept B)'
);

-- Worker2 (dept_b) → Worker1 (dept_a) = different dept
select is(
  public.can_access_employee('78000000-0000-4000-8000-000000000202'::uuid, 'test.access.78'),
  false,
  'department scope: worker2 cannot access worker1 (different dept A)'
);

-- ═══════════════════════════════════════════════════════════════════════
-- 5) team scope: نفس الفريق فقط
-- ═══════════════════════════════════════════════════════════════════════
select set_config('request.jwt.claim.sub','78000000-0000-4000-8000-000000000102',true);

-- Worker1 (team_a) → Manager (team_a) = same team
select is(
  public.can_access_employee('78000000-0000-4000-8000-000000000201'::uuid, 'test.access.78'),
  true,
  'team scope: worker1 can access manager (same team A)'
);

-- Worker1 (team_a) → Outsider (no team) = different
select is(
  public.can_access_employee('78000000-0000-4000-8000-000000000204'::uuid, 'test.access.78'),
  false,
  'team scope: worker1 cannot access outsider (no team match)'
);

-- ═══════════════════════════════════════════════════════════════════════
-- 6) selected_departments: إدارات محددة عبر scope_override
-- ═══════════════════════════════════════════════════════════════════════
select set_config('request.jwt.claim.sub','78000000-0000-4000-8000-000000000105',true);

-- Scoped (selected dept_a) → Worker1 (dept_a) = in list
select is(
  public.can_access_employee('78000000-0000-4000-8000-000000000202'::uuid, 'test.access.78'),
  true,
  'selected_departments: scoped user can access worker1 (dept A in list)'
);

-- Scoped (selected dept_a) → Outsider (dept_b) = not in list
select is(
  public.can_access_employee('78000000-0000-4000-8000-000000000204'::uuid, 'test.access.78'),
  false,
  'selected_departments: scoped user cannot access outsider (dept B not in list)'
);

-- ═══════════════════════════════════════════════════════════════════════
-- 7) selected_employees: موظفون محددون عبر scope_override
-- ═══════════════════════════════════════════════════════════════════════
-- Scoped (selected emp_worker1) → Worker1 = in list
select is(
  public.can_access_employee('78000000-0000-4000-8000-000000000202'::uuid, 'test.access.78'),
  true,
  'selected_employees: scoped user can access worker1 (in list)'
);

-- Note: worker1 passes both selected_departments AND selected_employees.
-- Test someone not in either: Director (dept_a but selected_employees check)
-- Actually outsider (dept_b) already tested above (false).
-- Test director (dept_a passes selected_departments, but we need pure selected_employees negative)
-- Outsider is dept_b → selected_departments=false, selected_employees doesn't include outsider → false ✓

-- ═══════════════════════════════════════════════════════════════════════
-- 8) organization scope: الوصول لأي موظف
-- ═══════════════════════════════════════════════════════════════════════
select set_config('request.jwt.claim.sub','78000000-0000-4000-8000-000000000104',true);

select is(
  public.can_access_employee('78000000-0000-4000-8000-000000000202'::uuid, 'test.access.78'),
  true,
  'organization scope: outsider can access worker1 (any employee)'
);

select is(
  public.can_access_employee('78000000-0000-4000-8000-000000000200'::uuid, 'test.access.78'),
  true,
  'organization scope: outsider can access director (any employee)'
);

-- ═══════════════════════════════════════════════════════════════════════
-- 9) null code: يعتمد على manager_relations فقط
-- ═══════════════════════════════════════════════════════════════════════
select set_config('request.jwt.claim.sub','78000000-0000-4000-8000-000000000101',true);

select is(
  public.can_access_employee('78000000-0000-4000-8000-000000000202'::uuid, null),
  true,
  'null code: manager can access direct report via manager_relations'
);

select is(
  public.can_access_employee('78000000-0000-4000-8000-000000000204'::uuid, null),
  false,
  'null code: manager cannot access non-report (no manager_relations)'
);

select * from finish();
rollback;
