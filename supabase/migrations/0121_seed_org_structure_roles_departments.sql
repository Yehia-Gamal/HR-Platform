-- Migration 0119: بذر الهيكل التنظيمي الفعلي لجمعية خواطر أحلى شباب
-- الأدوار الخمسة + الإدارات + المسميات الوظيفية
-- Idempotent: ON CONFLICT DO NOTHING/UPDATE — آمن للتطبيق المتكرر.

-- =========================================================
-- 1) الأدوار الخمسة الأساسية
-- =========================================================
-- admin (is_full_access) + employee موجودان من 0002.
-- direct-manager + operations-officer موجودان من 0056.
-- operations-manager-1/2 من 0059.
-- نضمن وجود: executive, executive-secretary, hr-manager

insert into public.roles (slug, name_ar, name_en, description, is_system, is_full_access)
values
  ('executive',           'المدير التنفيذي',    'Executive Director',    'المدير التنفيذي — أعلى صلاحية بعد admin', true, false),
  ('executive-secretary', 'السكرتير التنفيذي',   'Executive Secretary',   'سكرتير المدير التنفيذي — إدارة الدورات والمتابعة', true, false),
  ('hr-manager',          'مدير الموارد البشرية','HR Manager',            'مدير HR — إدارة شؤون الموظفين والحضور والتقييم', true, false)
on conflict (slug) do update set
  name_ar = excluded.name_ar,
  name_en = excluded.name_en,
  description = excluded.description;

-- =========================================================
-- 2) المسميات الوظيفية
-- =========================================================
insert into public.job_titles (code, name, name_en, is_active) values
  ('EXEC_DIR',       'مدير تنفيذي',                'Executive Director',     true),
  ('OPS_MGR',        'مدير تشغيل (أوبريشن)',       'Operations Manager',     true),
  ('MANAGER',        'مدير',                        'Manager',                true),
  ('EXEC_SEC',       'سكرتير تنفيذي',              'Executive Secretary',    true),
  ('EMPLOYEE',       'موظف',                        'Employee',               true),
  ('COMPLEX_MGR',    'مدير مجمع',                   'Complex Manager',        true),
  ('OFFICE_BOY',     'أوفيس بوي',                   'Office Boy',             true),
  ('HR_MGR',         'مدير موارد بشرية',            'HR Manager',             true),
  ('ACCOUNTANT',     'محاسب',                       'Accountant',             true),
  ('IT_SPECIALIST',  'أخصائي تكنولوجيا معلومات',   'IT Specialist',          true),
  ('LOGISTICS_MGR',  'مدير لوجستيك',               'Logistics Manager',      true),
  ('MEDIA_SPEC',     'أخصائي ميديا',               'Media Specialist',       true),
  ('FUNDRAISER',     'مسؤول فاندريزنج',            'Fundraiser',             true),
  ('LEGAL_ADMIN',    'مسؤول شؤون إدارية وقانونية', 'Legal & Admin Officer',  true),
  ('KITCHEN_MGR',    'مسؤول مطبخ',                 'Kitchen Manager',        true),
  ('MEDICAL',        'طبيب / أخصائي طبي',          'Medical Specialist',     true),
  ('PROJECT_MGR',    'مدير مشاريع',                'Project Manager',        true),
  ('DRIVER',         'سائق / مسؤول حركة',          'Driver',                 true),
  ('WAREHOUSE',      'أمين مخازن',                 'Warehouse Keeper',       true),
  ('PROCUREMENT',    'مسؤول مشتريات',              'Procurement Officer',    true)
on conflict (code) do update set
  name     = excluded.name,
  name_en  = excluded.name_en,
  is_active = true;

-- =========================================================
-- 3) الإدارات (departments) — هيكل شجري
-- =========================================================
-- نستخدم CTE لجلب legal_entity_id و branch_id
do $$
declare
  v_le  uuid;
  v_br  uuid;
  -- top-level departments
  v_logistics      uuid;
  v_accounting     uuid;
  v_it             uuid;
  v_osra_karima    uuid;
  v_exploration    uuid;
  v_medical_com    uuid;
  v_ops1           uuid;
  v_ops2           uuid;
  v_media          uuid;
  v_hr             uuid;
  v_kitchen1       uuid;
  v_kitchen2       uuid;
  v_kitchen3       uuid;
  v_legal_admin    uuid;
  v_exec_sec       uuid;
  v_fundraising    uuid;
  v_clinics        uuid;
  -- sub-departments
  v_transport      uuid;
  v_warehouse      uuid;
  v_procurement    uuid;
  v_students       uuid;
  v_projects       uuid;
begin
  -- جلب الكيان القانوني والفرع
  select id into v_le from public.legal_entities where code = 'AHLA';
  if v_le is null then
    raise notice 'Legal entity AHLA not found — skipping department seed';
    return;
  end if;
  select id into v_br from public.branches where legal_entity_id = v_le and code = 'MAIN';

  -- ──────── إدارات المستوى الأول ────────

  insert into public.departments (legal_entity_id, branch_id, parent_id, code, name, name_en, is_active)
  values (v_le, v_br, null, 'LOGISTICS', 'إدارة اللوجستيك', 'Logistics', true)
  on conflict (legal_entity_id, code) do update set name = excluded.name, name_en = excluded.name_en
  returning id into v_logistics;

  insert into public.departments (legal_entity_id, branch_id, parent_id, code, name, name_en, is_active)
  values (v_le, v_br, null, 'ACCOUNTING', 'إدارة الحسابات', 'Accounting', true)
  on conflict (legal_entity_id, code) do update set name = excluded.name, name_en = excluded.name_en
  returning id into v_accounting;

  insert into public.departments (legal_entity_id, branch_id, parent_id, code, name, name_en, is_active)
  values (v_le, v_br, null, 'IT', 'إدارة تكنولوجيا المعلومات', 'IT', true)
  on conflict (legal_entity_id, code) do update set name = excluded.name, name_en = excluded.name_en
  returning id into v_it;

  insert into public.departments (legal_entity_id, branch_id, parent_id, code, name, name_en, is_active)
  values (v_le, v_br, null, 'OSRA_KARIMA', 'لجنة أسرة كريمة', 'Osra Karima Committee', true)
  on conflict (legal_entity_id, code) do update set name = excluded.name, name_en = excluded.name_en
  returning id into v_osra_karima;

  insert into public.departments (legal_entity_id, branch_id, parent_id, code, name, name_en, is_active)
  values (v_le, v_br, null, 'EXPLORATION', 'لجنة الاستكشاف', 'Exploration Committee', true)
  on conflict (legal_entity_id, code) do update set name = excluded.name, name_en = excluded.name_en
  returning id into v_exploration;

  insert into public.departments (legal_entity_id, branch_id, parent_id, code, name, name_en, is_active)
  values (v_le, v_br, null, 'MEDICAL_COM', 'اللجنة الطبية', 'Medical Committee', true)
  on conflict (legal_entity_id, code) do update set name = excluded.name, name_en = excluded.name_en
  returning id into v_medical_com;

  insert into public.departments (legal_entity_id, branch_id, parent_id, code, name, name_en, is_active)
  values (v_le, v_br, null, 'OPS1', 'إدارة تشغيل 1', 'Operations 1', true)
  on conflict (legal_entity_id, code) do update set name = excluded.name, name_en = excluded.name_en
  returning id into v_ops1;

  insert into public.departments (legal_entity_id, branch_id, parent_id, code, name, name_en, is_active)
  values (v_le, v_br, null, 'OPS2', 'إدارة تشغيل 2', 'Operations 2', true)
  on conflict (legal_entity_id, code) do update set name = excluded.name, name_en = excluded.name_en
  returning id into v_ops2;

  insert into public.departments (legal_entity_id, branch_id, parent_id, code, name, name_en, is_active)
  values (v_le, v_br, null, 'MEDIA', 'إدارة الميديا', 'Media', true)
  on conflict (legal_entity_id, code) do update set name = excluded.name, name_en = excluded.name_en
  returning id into v_media;

  insert into public.departments (legal_entity_id, branch_id, parent_id, code, name, name_en, is_active)
  values (v_le, v_br, null, 'HR', 'إدارة الموارد البشرية', 'Human Resources', true)
  on conflict (legal_entity_id, code) do update set name = excluded.name, name_en = excluded.name_en
  returning id into v_hr;

  insert into public.departments (legal_entity_id, branch_id, parent_id, code, name, name_en, is_active)
  values (v_le, v_br, null, 'KITCHEN1', 'مطبخ المتعففين 1', 'Kitchen 1', true)
  on conflict (legal_entity_id, code) do update set name = excluded.name, name_en = excluded.name_en
  returning id into v_kitchen1;

  insert into public.departments (legal_entity_id, branch_id, parent_id, code, name, name_en, is_active)
  values (v_le, v_br, null, 'KITCHEN2', 'مطبخ المتعففين 2', 'Kitchen 2', true)
  on conflict (legal_entity_id, code) do update set name = excluded.name, name_en = excluded.name_en
  returning id into v_kitchen2;

  insert into public.departments (legal_entity_id, branch_id, parent_id, code, name, name_en, is_active)
  values (v_le, v_br, null, 'KITCHEN3', 'مطبخ المتعففين 3', 'Kitchen 3', true)
  on conflict (legal_entity_id, code) do update set name = excluded.name, name_en = excluded.name_en
  returning id into v_kitchen3;

  insert into public.departments (legal_entity_id, branch_id, parent_id, code, name, name_en, is_active)
  values (v_le, v_br, null, 'LEGAL_ADMIN', 'إدارة الشؤون الإدارية والقانونية', 'Admin & Legal Affairs', true)
  on conflict (legal_entity_id, code) do update set name = excluded.name, name_en = excluded.name_en
  returning id into v_legal_admin;

  insert into public.departments (legal_entity_id, branch_id, parent_id, code, name, name_en, is_active)
  values (v_le, v_br, null, 'EXEC_SEC', 'السكرتير التنفيذي', 'Executive Secretary Office', true)
  on conflict (legal_entity_id, code) do update set name = excluded.name, name_en = excluded.name_en
  returning id into v_exec_sec;

  insert into public.departments (legal_entity_id, branch_id, parent_id, code, name, name_en, is_active)
  values (v_le, v_br, null, 'FUNDRAISING', 'إدارة الفاندريزنج', 'Fundraising', true)
  on conflict (legal_entity_id, code) do update set name = excluded.name, name_en = excluded.name_en
  returning id into v_fundraising;

  insert into public.departments (legal_entity_id, branch_id, parent_id, code, name, name_en, is_active)
  values (v_le, v_br, null, 'CLINICS', 'إدارة العيادات الطبية', 'Medical Clinics', true)
  on conflict (legal_entity_id, code) do update set name = excluded.name, name_en = excluded.name_en
  returning id into v_clinics;

  -- ──────── إدارات فرعية تحت اللوجستيك ────────

  insert into public.departments (legal_entity_id, branch_id, parent_id, code, name, name_en, is_active)
  values (v_le, v_br, v_logistics, 'TRANSPORT', 'إدارة الحركة', 'Transportation', true)
  on conflict (legal_entity_id, code) do update set name = excluded.name, name_en = excluded.name_en, parent_id = excluded.parent_id
  returning id into v_transport;

  insert into public.departments (legal_entity_id, branch_id, parent_id, code, name, name_en, is_active)
  values (v_le, v_br, v_logistics, 'WAREHOUSE', 'إدارة المخازن', 'Warehouses', true)
  on conflict (legal_entity_id, code) do update set name = excluded.name, name_en = excluded.name_en, parent_id = excluded.parent_id
  returning id into v_warehouse;

  insert into public.departments (legal_entity_id, branch_id, parent_id, code, name, name_en, is_active)
  values (v_le, v_br, v_logistics, 'PROCUREMENT', 'إدارة المشتريات', 'Procurement', true)
  on conflict (legal_entity_id, code) do update set name = excluded.name, name_en = excluded.name_en, parent_id = excluded.parent_id
  returning id into v_procurement;

  -- ──────── إدارات فرعية تحت أسرة كريمة ────────

  insert into public.departments (legal_entity_id, branch_id, parent_id, code, name, name_en, is_active)
  values (v_le, v_br, v_osra_karima, 'STUDENTS', 'طلاب العلم', 'Students of Knowledge', true)
  on conflict (legal_entity_id, code) do update set name = excluded.name, name_en = excluded.name_en, parent_id = excluded.parent_id
  returning id into v_students;

  insert into public.departments (legal_entity_id, branch_id, parent_id, code, name, name_en, is_active)
  values (v_le, v_br, v_osra_karima, 'PROJECTS', 'إدارة المشاريع', 'Projects Management', true)
  on conflict (legal_entity_id, code) do update set name = excluded.name, name_en = excluded.name_en, parent_id = excluded.parent_id
  returning id into v_projects;

  raise notice 'Seeded % top-level + % sub departments, % job titles',
    17, 5, 20;
end;
$$;

-- =========================================================
-- 4) ربط الصلاحيات بالأدوار الخمسة
-- =========================================================
-- لا نحذف الصلاحيات الحالية — نضيف فقط ما ينقص.
-- executive: كل ما يبدأ بـ executive + attendance.record.read + reports + kpi
-- executive-secretary: kpi cycle + comms + reports + attendance
-- hr-manager: people + attendance + requests + performance + onboarding + recruitment + documents + comms
-- direct-manager: attendance.record.read + requests.request.read/approve + performance.kpi.manager_assess
-- employee: (الصلاحيات الذاتية — self scope — مبذورة بالفعل في 0013)

-- Executive role permissions
do $$
declare
  v_role_id uuid;
  v_perm_id uuid;
  v_code text;
  v_codes text[] := array[
    'attendance.record.read',
    'performance.kpi.read', 'performance.kpi.executive_review', 'performance.kpi.finalize',
    'performance.cycle.manage',
    'reports.people.read', 'reports.schedule.manage',
    'comms.announcement.read', 'comms.decision.approve',
    'live_location.request',
    'people.employee.read',
    'organization.org_chart.read', 'organization.entity.read'
  ];
begin
  select id into v_role_id from public.roles where slug = 'executive';
  if v_role_id is null then return; end if;
  foreach v_code in array v_codes loop
    select id into v_perm_id from public.permissions where code = v_code;
    if v_perm_id is not null then
      insert into public.role_permissions (role_id, permission_id, scope)
      values (v_role_id, v_perm_id, 'organization')
      on conflict (role_id, permission_id, scope) do nothing;
    end if;
  end loop;
end;
$$;

-- Executive Secretary role permissions
do $$
declare
  v_role_id uuid;
  v_perm_id uuid;
  v_code text;
  v_codes text[] := array[
    'attendance.record.read',
    'performance.kpi.read', 'performance.kpi.secretary_review',
    'performance.cycle.manage',
    'reports.people.read',
    'comms.announcement.read', 'comms.announcement.manage', 'comms.decision.manage',
    'people.employee.read',
    'requests.request.read',
    'organization.org_chart.read'
  ];
begin
  select id into v_role_id from public.roles where slug = 'executive-secretary';
  if v_role_id is null then return; end if;
  foreach v_code in array v_codes loop
    select id into v_perm_id from public.permissions where code = v_code;
    if v_perm_id is not null then
      insert into public.role_permissions (role_id, permission_id, scope)
      values (v_role_id, v_perm_id, 'organization')
      on conflict (role_id, permission_id, scope) do nothing;
    end if;
  end loop;
end;
$$;

-- HR Manager role permissions
do $$
declare
  v_role_id uuid;
  v_perm_id uuid;
  v_code text;
  v_codes text[] := array[
    'people.employee.read', 'people.employee.manage', 'people.employee.create',
    'attendance.record.read', 'attendance.record.review', 'attendance.roster.read', 'attendance.roster.manage',
    'attendance.shift.read', 'attendance.shift.manage', 'attendance.correction.review',
    'requests.request.read', 'requests.request.approve',
    'performance.kpi.read', 'performance.kpi.hr_assess', 'performance.kpi.hr_review',
    'recruitment.requisition.read', 'recruitment.requisition.manage',
    'onboarding.journey.read', 'onboarding.journey.manage',
    'documents.employee.read', 'documents.template.manage',
    'comms.announcement.read', 'comms.announcement.manage',
    'reports.people.read',
    'organization.org_chart.read', 'organization.department.manage'
  ];
begin
  select id into v_role_id from public.roles where slug = 'hr-manager';
  if v_role_id is null then return; end if;
  foreach v_code in array v_codes loop
    select id into v_perm_id from public.permissions where code = v_code;
    if v_perm_id is not null then
      insert into public.role_permissions (role_id, permission_id, scope)
      values (v_role_id, v_perm_id, 'organization')
      on conflict (role_id, permission_id, scope) do nothing;
    end if;
  end loop;
end;
$$;

-- Direct Manager role permissions (scope = direct_reports)
do $$
declare
  v_role_id uuid;
  v_perm_id uuid;
  v_code text;
  v_codes text[] := array[
    'attendance.record.read',
    'requests.request.read', 'requests.request.approve',
    'performance.kpi.read', 'performance.kpi.manager_assess',
    'people.employee.read',
    'tasks.read', 'tasks.assign'
  ];
begin
  select id into v_role_id from public.roles where slug = 'direct-manager';
  if v_role_id is null then return; end if;
  foreach v_code in array v_codes loop
    select id into v_perm_id from public.permissions where code = v_code;
    if v_perm_id is not null then
      insert into public.role_permissions (role_id, permission_id, scope)
      values (v_role_id, v_perm_id, 'direct_reports')
      on conflict (role_id, permission_id, scope) do nothing;
    end if;
  end loop;
end;
$$;
