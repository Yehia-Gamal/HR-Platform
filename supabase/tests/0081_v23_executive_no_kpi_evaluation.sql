-- 0081: V23 §8.4 — Executive لا يُقيَّم في KPI.
-- يثبت أن create_kpi_cycle_admin تستثني الموظفين ذوي أدوار executive/executive-director
-- من إنشاء تقييمات KPI. المدير التنفيذي يعتمد التقييمات (executive_review)
-- لكن لا يُقيَّم هو شخصيًا.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(12);

-- =====================================================================
-- (1) الدالة create_kpi_cycle_admin موجودة
-- =====================================================================
select has_function(
  'public', 'create_kpi_cycle_admin',
  'create_kpi_cycle_admin RPC exists');

-- =====================================================================
-- (2) الدالة تستثني executive من إنشاء التقييمات
-- =====================================================================
select lives_ok(
  $live$do $t$
  declare v_src text;
  begin
    select prosrc into v_src from pg_proc
    where proname='create_kpi_cycle_admin' and pronamespace='public'::regnamespace;
    if v_src not ilike '%executive%' then
      raise exception 'create_kpi_cycle_admin لا تتعامل مع دور executive';
    end if;
  end $t$$live$,
  'create_kpi_cycle_admin تتعامل مع دور executive');

-- (3) الدالة تستثني executive-director أيضًا
select lives_ok(
  $live$do $t$
  declare v_src text;
  begin
    select prosrc into v_src from pg_proc
    where proname='create_kpi_cycle_admin' and pronamespace='public'::regnamespace;
    if v_src not ilike '%executive-director%' then
      raise exception 'create_kpi_cycle_admin لا تستثني executive-director';
    end if;
  end $t$$live$,
  'create_kpi_cycle_admin تستثني executive-director');

-- (4) الاستثناء يتم عبر NOT EXISTS (منع إنشاء صف التقييم)
select lives_ok(
  $live$do $t$
  declare v_src text;
  begin
    select prosrc into v_src from pg_proc
    where proname='create_kpi_cycle_admin' and pronamespace='public'::regnamespace;
    if v_src not ilike '%not exists%' or v_src not ilike '%executive%' then
      raise exception 'لا يوجد NOT EXISTS لاستثناء executive';
    end if;
  end $t$$live$,
  'الاستثناء يتم عبر NOT EXISTS في insert...select');

-- (5) الاستثناء يتحقق من user_roles → roles (السلسلة الصحيحة)
select lives_ok(
  $live$do $t$
  declare v_src text;
  begin
    select prosrc into v_src from pg_proc
    where proname='create_kpi_cycle_admin' and pronamespace='public'::regnamespace;
    if v_src not ilike '%user_roles%' or v_src not ilike '%roles%' or v_src not ilike '%slug%' then
      raise exception 'الاستثناء لا يتحقق من سلسلة user_roles → roles.slug';
    end if;
  end $t$$live$,
  'الاستثناء يفحص user_roles → roles.slug');

-- (6) الاستثناء يتحقق من صلاحية الفترة الزمنية (effective_from/effective_to)
select lives_ok(
  $live$do $t$
  declare v_src text;
  begin
    select prosrc into v_src from pg_proc
    where proname='create_kpi_cycle_admin' and pronamespace='public'::regnamespace;
    if v_src not ilike '%effective_from%' or v_src not ilike '%effective_to%' then
      raise exception 'لا يتحقق من فترة صلاحية الدور';
    end if;
  end $t$$live$,
  'الاستثناء يتحقق من فترة صلاحية الدور (effective_from/to)');

-- =====================================================================
-- (7-8) advance_kpi_stage: عقد المسار المبسّط 0470
-- =====================================================================

-- (7) 0470: مرحلة executive_review أُزيلت من المسار القانوني
select lives_ok(
  $live$do $t$
  declare v_src text;
  begin
    select prosrc into v_src from pg_proc
    where proname='advance_kpi_stage' and pronamespace='public'::regnamespace;
    if v_src ilike '%executive_review%' then
      raise exception '0470: executive_review يجب أن تكون قد أُزيلت من advance_kpi_stage';
    end if;
  end $t$$live$,
  '0470: advance_kpi_stage بلا مرحلة executive_review');

-- (8) الاعتماد صار خطوة مدير واحدة تنتهي بانتظار إقرار الموظف
select lives_ok(
  $live$do $t$
  declare v_src text;
  begin
    select prosrc into v_src from pg_proc
    where proname='advance_kpi_stage' and pronamespace='public'::regnamespace;
    if v_src not ilike '%manager_review%' or v_src not ilike '%EMPLOYEE_ACKNOWLEDGEMENT_PENDING%' then
      raise exception '0470: اعتماد المدير الواحد + حالة الإقرار مفقودتان';
    end if;
  end $t$$live$,
  '0470: اعتماد المدير الواحد ينتهي بـ EMPLOYEE_ACKNOWLEDGEMENT_PENDING');

-- =====================================================================
-- (9-10) التحقق السلوكي: Executive مستثنى من التقييمات
-- =====================================================================

-- إعداد البيانات التجريبية
do $fixture$
declare
  v_entity uuid := 'b8400000-0000-4000-8000-000000000001';
  v_dept   uuid := 'b8400000-0000-4000-8000-000000000010';
  v_exec_role_id uuid;
begin
  -- كيان وإدارة
  insert into public.legal_entities(id, code, name)
  values(v_entity, 'V23-EXEC-LE', 'كيان اختبار Executive')
  on conflict(id) do nothing;
  insert into public.departments(id, legal_entity_id, code, name)
  values(v_dept, v_entity, 'V23-EXEC-D', 'إدارة اختبار')
  on conflict(id) do nothing;

  -- مستخدمون: واحد عادي + واحد executive
  insert into auth.users(id, email, aud, role) values
    ('b8400000-0000-4000-8000-000000000101', 'v23-exec-normal@test.local', 'authenticated', 'authenticated'),
    ('b8400000-0000-4000-8000-000000000102', 'v23-exec-director@test.local', 'authenticated', 'authenticated')
  on conflict(id) do nothing;

  insert into public.employees(id, user_id, employee_code, full_name_ar, department_id, status, is_active, is_deleted) values
    ('b8400000-0000-4000-8000-000000000201', 'b8400000-0000-4000-8000-000000000101', 'EXEC-NRM', 'موظف عادي', v_dept, 'active', true, false),
    ('b8400000-0000-4000-8000-000000000202', 'b8400000-0000-4000-8000-000000000102', 'EXEC-DIR', 'مدير تنفيذي', v_dept, 'active', true, false)
  on conflict(id) do nothing;

  insert into public.profiles(id, employee_id, status) values
    ('b8400000-0000-4000-8000-000000000101', 'b8400000-0000-4000-8000-000000000201', 'active'),
    ('b8400000-0000-4000-8000-000000000102', 'b8400000-0000-4000-8000-000000000202', 'active')
  on conflict(id) do nothing;

  -- إسناد دور executive للمدير التنفيذي
  select id into v_exec_role_id from public.roles where slug = 'executive' limit 1;
  if v_exec_role_id is not null then
    insert into public.user_roles(user_id, role_id)
    values('b8400000-0000-4000-8000-000000000102', v_exec_role_id)
    on conflict do nothing;
  end if;
end
$fixture$;

-- (9) الموظف العادي ليس executive (تحقق أساسي)
select ok(
  not exists(
    select 1 from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where ur.user_id = 'b8400000-0000-4000-8000-000000000102'
      and r.slug in ('executive','executive-director')
      and (ur.effective_from is null or ur.effective_from <= now())
      and (ur.effective_to is null or ur.effective_to > now())
  ) is false,
  'المدير التنفيذي لديه دور executive مُسنَد');

-- (10) فحص أن منطق create_kpi_cycle_admin يستثني الموظف ذو دور executive
-- نُحاكي الاستعلام الداخلي للدالة (SELECT مع NOT EXISTS)
select ok(
  (select count(*) from public.employees e
   where e.is_active and not coalesce(e.is_deleted, false) and e.status = 'active'
     and e.id in ('b8400000-0000-4000-8000-000000000201', 'b8400000-0000-4000-8000-000000000202')
     and not exists(
       select 1 from public.user_roles ur
       join public.roles r on r.id = ur.role_id
       where ur.user_id = e.user_id
         and r.slug in ('executive','executive-director')
         and (ur.effective_from is null or ur.effective_from <= now())
         and (ur.effective_to is null or ur.effective_to > now())
     )
  ) = 1,
  'الاستعلام يُرجع الموظف العادي فقط — Executive مستثنى');

-- =====================================================================
-- (11) فقط الموظف العادي يمر عبر فلتر الاستثناء
-- =====================================================================
select ok(
  exists(
    select 1 from public.employees e
    where e.id = 'b8400000-0000-4000-8000-000000000201'
      and e.is_active and not coalesce(e.is_deleted, false) and e.status = 'active'
      and not exists(
        select 1 from public.user_roles ur
        join public.roles r on r.id = ur.role_id
        where ur.user_id = e.user_id
          and r.slug in ('executive','executive-director')
          and (ur.effective_from is null or ur.effective_from <= now())
          and (ur.effective_to is null or ur.effective_to > now())
      )
  ),
  'الموظف العادي يمر عبر فلتر الاستثناء');

-- (12) المدير التنفيذي لا يمر عبر فلتر الاستثناء
select ok(
  not exists(
    select 1 from public.employees e
    where e.id = 'b8400000-0000-4000-8000-000000000202'
      and e.is_active and not coalesce(e.is_deleted, false) and e.status = 'active'
      and not exists(
        select 1 from public.user_roles ur
        join public.roles r on r.id = ur.role_id
        where ur.user_id = e.user_id
          and r.slug in ('executive','executive-director')
          and (ur.effective_from is null or ur.effective_from <= now())
          and (ur.effective_to is null or ur.effective_to > now())
      )
  ),
  'المدير التنفيذي مستثنى من فلتر التقييمات');

select * from finish();
rollback;
