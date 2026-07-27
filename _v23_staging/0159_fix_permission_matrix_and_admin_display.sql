-- Migration 0159: ضبط مصفوفة الصلاحيات — عرض كامل للأدمن + توزيع حكيم
--
-- المشكلة: الأدمن (full-access) يظهر بـ 0 صلاحية في الواجهة لأن RPC
-- يعرض فقط صفوف role_permissions، والأدمن يعتمد على bypass لا صفوف.
--
-- الحل:
-- 1. تعديل get_access_admin_catalog: الأدوار full-access تعرض كل الصلاحيات
-- 2. ضمان وجود جميع أكواد الصلاحيات الأساسية في الكتالوج
-- 3. منح صلاحيات شاملة للمدير التنفيذي ومدير التشغيل والمدير المباشر

begin;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. Fix get_access_admin_catalog — full-access → ALL permissions
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.get_access_admin_catalog()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not (public.current_is_full_access() or public.has_any_permission(array[
    'access.role.read','access.role.update','access.role.assign'
  ])) then
    raise exception 'access catalog denied' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'roles', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'slug', r.slug, 'name', r.name_ar, 'nameEn', r.name_en,
        'description', r.description, 'color', r.color, 'icon', r.icon,
        'system', r.is_system, 'fullAccess', r.is_full_access,
        'permissions', case
          when r.is_full_access then
            -- ── أدوار كاملة الصلاحية: عرض جميع الصلاحيات من الكتالوج ──
            coalesce((
              select jsonb_agg(jsonb_build_object(
                'permissionId', p.id, 'code', p.code,
                'name', coalesce(p.description, p.code),
                'scope', 'organization',
                'requiresMfa', false,
                'requiresReason', false
              ) order by p.module, p.code)
              from public.permissions p
            ), '[]'::jsonb)
          else
            -- ── أدوار عادية: عرض الصلاحيات الممنوحة فقط ──
            coalesce((
              select jsonb_agg(jsonb_build_object(
                'permissionId', p.id, 'code', p.code,
                'name', coalesce(p.description, p.code),
                'scope', rp.scope, 'requiresMfa', rp.requires_mfa,
                'requiresReason', rp.requires_reason
              ) order by p.module, p.code)
              from public.role_permissions rp
              join public.permissions p on p.id = rp.permission_id
              where rp.role_id = r.id
            ), '[]'::jsonb)
        end,
        'assignments', (
          select count(*)
          from public.user_roles ur
          where ur.role_id = r.id
            and ur.effective_from <= now()
            and (ur.effective_to is null or ur.effective_to > now())
        )
      ) order by r.is_full_access desc, r.name_ar)
      from public.roles r
    ), '[]'::jsonb),

    'permissions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'code', p.code, 'module', p.module, 'resource', p.resource,
        'action', p.action, 'name', coalesce(p.description, p.code),
        'description', p.description,
        'riskLevel', p.risk_level, 'sensitive', p.is_sensitive,
        'allowedScopes', array[
          'self','direct_reports','management_descendants','selected_employees',
          'team','department','selected_departments','branch','selected_branches',
          'organization','assigned_cases','workflow_inbox',
          'records_created_by_user','archive_readonly'
        ]
      ) order by p.module, p.code)
      from public.permissions p
    ), '[]'::jsonb),

    'users', coalesce((
      select jsonb_agg(jsonb_build_object(
        'userId', pr.id, 'employeeId', pr.employee_id,
        'name', coalesce(e.full_name_ar, pr.id::text),
        'employeeCode', e.employee_code,
        'status', pr.status,
        'roles', coalesce((
          select jsonb_agg(jsonb_build_object(
            'roleId', r.id, 'slug', r.slug, 'name', r.name_ar,
            'effectiveFrom', ur.effective_from, 'effectiveTo', ur.effective_to,
            'scopeOverride', ur.scope_override
          ) order by r.name_ar)
          from public.user_roles ur join public.roles r on r.id = ur.role_id
          where ur.user_id = pr.id
        ), '[]'::jsonb)
      ) order by coalesce(e.full_name_ar, pr.id::text))
      from public.profiles pr
      left join public.employees e on e.id = pr.employee_id
    ), '[]'::jsonb),

    'lastUpdatedAt', now()
  );
end;
$$;


-- ═══════════════════════════════════════════════════════════════════════════
-- 2. Ensure core permission codes exist in the catalog
-- ═══════════════════════════════════════════════════════════════════════════
-- بعض الأكواد موجودة فقط في ملفات seed — نضمن وجودها هنا للنشر

insert into public.permissions (code, module, resource, action) values
  -- People / Employees
  ('people.employee.read',              'people','employee','read'),
  ('people.employee.create',            'people','employee','create'),
  ('people.employee.update_basic',      'people','employee','update_basic'),
  ('people.employee.update_sensitive',  'people','employee','update_sensitive'),
  ('people.employee.archive',           'people','employee','archive'),
  ('people.employee.terminate',         'people','employee','terminate'),
  ('people.employee.restore',           'people','employee','restore'),
  ('people.employee.import',            'people','employee','import'),
  ('people.employee.export',            'people','employee','export'),
  ('people.employee.assign_manager',    'people','employee','assign_manager'),
  ('people.employee.transfer',          'people','employee','transfer'),
  ('people.employee.promote',           'people','employee','promote'),
  ('people.employee.change_status',     'people','employee','change_status'),
  ('people.employee.view_identity',     'people','employee','view_identity'),
  ('people.employee.view_contact',      'people','employee','view_contact'),
  ('people.employee.view_compensation', 'people','employee','view_compensation'),
  ('people.employee.view_history',      'people','employee','view_history'),
  ('people.employee.view_audit',        'people','employee','view_audit'),
  ('people.employee.upload_avatar',     'people','employee','upload_avatar'),
  ('people.employee.manage_documents',  'people','employee','manage_documents'),
  -- Organization
  ('organization.entity.read',       'organization','entity','read'),
  ('organization.entity.manage',     'organization','entity','manage'),
  ('organization.branch.manage',     'organization','branch','manage'),
  ('organization.department.manage', 'organization','department','manage'),
  ('organization.unit.manage',       'organization','unit','manage'),
  ('organization.position.manage',   'organization','position','manage'),
  ('organization.job_title.manage',  'organization','job_title','manage'),
  ('organization.grade.manage',      'organization','grade','manage'),
  ('organization.org_chart.read',    'organization','org_chart','read'),
  -- Access
  ('access.account.read',   'access','account','read'),
  ('access.account.create', 'access','account','create'),
  ('access.account.update', 'access','account','update'),
  ('access.role.read',      'access','role','read'),
  ('access.role.create',    'access','role','create'),
  ('access.role.update',    'access','role','update'),
  ('access.role.assign',    'access','role','assign'),
  ('access.role.remove',    'access','role','remove'),
  ('access.audit.read',     'access','audit','read'),
  -- Attendance
  ('attendance.punch.check_in',            'attendance','punch','check_in'),
  ('attendance.punch.check_out',           'attendance','punch','check_out'),
  ('attendance.record.read',               'attendance','record','read'),
  ('attendance.record.read_location',      'attendance','record','read_location'),
  ('attendance.record.read_identity_check','attendance','record','read_identity_check'),
  ('attendance.record.read_risk',          'attendance','record','read_risk'),
  ('attendance.record.export',             'attendance','record','export'),
  ('attendance.record.manual_create',      'attendance','record','manual_create'),
  ('attendance.record.void',               'attendance','record','void'),
  ('attendance.correction.create',         'attendance','correction','create'),
  ('attendance.correction.review',         'attendance','correction','review'),
  ('attendance.correction.approve',        'attendance','correction','approve'),
  ('attendance.correction.reject',         'attendance','correction','reject'),
  ('attendance.risk.review',               'attendance','risk','review'),
  ('attendance.risk.resolve',              'attendance','risk','resolve'),
  ('attendance.shift.read',                'attendance','shift','read'),
  ('attendance.shift.manage',              'attendance','shift','manage'),
  ('attendance.shift.assign',              'attendance','shift','assign'),
  ('attendance.calendar.manage',           'attendance','calendar','manage'),
  ('attendance.geofence.manage',           'attendance','geofence','manage'),
  ('attendance.policy.manage',             'attendance','policy','manage'),
  ('attendance.period.close',              'attendance','period','close'),
  ('attendance.period.unlock',             'attendance','period','unlock'),
  -- Live Location
  ('live_location.request',          'live_location','request','request'),
  ('live_location.request_group',    'live_location','request','request_group'),
  ('live_location.cancel',           'live_location','request','cancel'),
  ('live_location.view_response',    'live_location','response','view_response'),
  ('live_location.view_history',     'live_location','history','view_history'),
  ('live_location.export',           'live_location','history','export'),
  ('live_location.manage_policy',    'live_location','policy','manage_policy'),
  ('live_location.manage_retention', 'live_location','retention','manage_retention'),
  ('live_location.read_access_log',  'live_location','audit','read_access_log'),
  -- Requests / Workflow
  ('requests.request.read',                  'requests','request','read'),
  ('requests.request.create',                'requests','request','create'),
  ('requests.request.update_draft',          'requests','request','update_draft'),
  ('requests.request.submit',                'requests','request','submit'),
  ('requests.request.withdraw',              'requests','request','withdraw'),
  ('requests.request.cancel_approved',       'requests','request','cancel_approved'),
  ('requests.request.return_for_correction', 'requests','request','return_for_correction'),
  ('requests.request.approve',               'requests','request','approve'),
  ('requests.request.reject',                'requests','request','reject'),
  ('requests.request.delegate',              'requests','request','delegate'),
  ('requests.request.escalate',              'requests','request','escalate'),
  ('requests.request.override',              'requests','request','override'),
  ('requests.approve',                       'requests','approve','approve'),
  ('requests.read',                          'requests','read','read'),
  ('requests.workflow.read',                 'requests','workflow','read'),
  ('requests.workflow.manage',               'requests','workflow','manage'),
  ('requests.leave.balance.read',            'requests','leave','balance_read'),
  ('requests.leave.balance.adjust',          'requests','leave','balance_adjust'),
  ('requests.leave.policy.manage',           'requests','leave','policy_manage'),
  ('requests.leave.execute_casual',          'requests','leave','execute_casual'),
  -- Operations
  ('operations.task.read',             'operations','task','read'),
  ('operations.task.create',           'operations','task','create'),
  ('operations.task.update',           'operations','task','update'),
  ('operations.task.assign',           'operations','task','assign'),
  ('operations.task.complete',         'operations','task','complete'),
  ('operations.task.cancel',           'operations','task','cancel'),
  ('operations.incident.manage',       'operations','incident','manage'),
  ('operations.convoy.manage',         'operations','convoy','manage'),
  ('operations.mission.manage',        'operations','mission','manage'),
  ('operations.shift_handover.create', 'operations','shift_handover','create'),
  ('operations.shift_handover.read',   'operations','shift_handover','read'),
  -- Assignments
  ('assignments.mission.manage',     'assignments','mission','manage'),
  ('assignments.convoy.manage',      'assignments','convoy','manage'),
  ('assignments.fundraising.manage', 'assignments','fundraising','manage'),
  ('assignments.report.review',      'assignments','report','review'),
  -- Performance
  ('performance.kpi.read',                  'performance','kpi','read'),
  ('performance.kpi.self_assess',           'performance','kpi','self_assess'),
  ('performance.kpi.manager_assess',        'performance','kpi','manager_assess'),
  ('performance.kpi.hr_review',             'performance','kpi','hr_review'),
  ('performance.kpi.secretary_review',      'performance','kpi','secretary_review'),
  ('performance.kpi.executive_review',      'performance','kpi','executive_review'),
  ('performance.kpi.finalize',              'performance','kpi','finalize'),
  ('performance.kpi.reopen_amendment',      'performance','kpi','reopen_amendment'),
  ('performance.kpi.view_reviewer_notes',   'performance','kpi','view_reviewer_notes'),
  ('performance.kpi.view_sensitive_scores', 'performance','kpi','view_sensitive_scores'),
  ('performance.kpi.export',                'performance','kpi','export'),
  ('performance.template.manage',           'performance','template','manage'),
  ('performance.cycle.manage',              'performance','cycle','manage'),
  ('performance.calibration.manage',        'performance','calibration','manage'),
  ('performance.pip.manage',                'performance','pip','manage'),
  ('performance.goal.manage_self',          'performance','goal','manage_self'),
  ('performance.goal.manage_team',          'performance','goal','manage_team'),
  -- Documents
  ('documents.employee.read',     'documents','employee','read'),
  ('documents.employee.create',   'documents','employee','create'),
  ('documents.employee.update',   'documents','employee','update'),
  ('documents.employee.delete',   'documents','employee','delete'),
  ('documents.employee.export',   'documents','employee','export'),
  ('documents.contract.read',     'documents','contract','read'),
  ('documents.contract.create',   'documents','contract','create'),
  ('documents.contract.update',   'documents','contract','update'),
  ('documents.contract.delete',   'documents','contract','delete'),
  ('documents.contract.export',   'documents','contract','export'),
  ('documents.policy.publish',    'documents','policy','publish'),
  ('documents.policy.acknowledge','documents','policy','acknowledge'),
  ('documents.expiry.manage',     'documents','expiry','manage'),
  -- Relations
  ('relations.case.read',                 'relations','case','read'),
  ('relations.case.create',               'relations','case','create'),
  ('relations.case.update',               'relations','case','update'),
  ('relations.case.assign',               'relations','case','assign'),
  ('relations.case.resolve',              'relations','case','resolve'),
  ('relations.case.close',                'relations','case','close'),
  ('relations.case.export',               'relations','case','export'),
  ('relations.committee.manage_templates','relations','committee','manage_templates'),
  ('relations.committee.manage_members',  'relations','committee','manage_members'),
  ('relations.discipline.create',         'relations','discipline','create'),
  ('relations.discipline.approve',        'relations','discipline','approve'),
  -- Communications
  ('communications.announcement.create',       'communications','announcement','create'),
  ('communications.announcement.publish',      'communications','announcement','publish'),
  ('communications.announcement.manage_targets','communications','announcement','manage_targets'),
  ('communications.decision.create',           'communications','decision','create'),
  ('communications.decision.publish',          'communications','decision','publish'),
  ('communications.decision.acknowledge',      'communications','decision','acknowledge'),
  ('communications.decision.read_receipts',    'communications','decision','read_receipts'),
  ('communications.notification.send',         'communications','notification','send'),
  ('communications.notification.send_bulk',    'communications','notification','send_bulk'),
  ('communications.survey.manage',             'communications','survey','manage'),
  -- Reports
  ('reports.attendance.read',       'reports','attendance','read'),
  ('reports.people.read',           'reports','people','read'),
  ('reports.requests.read',         'reports','requests','read'),
  ('reports.performance.read',      'reports','performance','read'),
  ('reports.operations.read',       'reports','operations','read'),
  ('reports.report.export',         'reports','report','export'),
  ('reports.report.schedule',       'reports','report','schedule'),
  ('reports.builder.use',           'reports','builder','use'),
  ('reports.builder.manage_catalog','reports','builder','manage_catalog'),
  -- System
  ('system.settings.read',           'system','settings','read'),
  ('system.settings.update_general', 'system','settings','update_general'),
  ('system.settings.update_security','system','settings','update_security'),
  ('system.feature_flags.manage',    'system','feature_flags','manage'),
  ('system.integrations.manage',     'system','integrations','manage'),
  ('system.jobs.read',               'system','jobs','read'),
  ('system.jobs.retry',              'system','jobs','retry'),
  ('system.audit.read',              'system','audit','read'),
  ('system.security_events.read',    'system','security_events','read'),
  ('system.security_events.resolve', 'system','security_events','resolve'),
  ('system.backup.read_status',      'system','backup','read_status'),
  ('system.backup.run',              'system','backup','run'),
  ('system.restore.execute',         'system','restore','execute')
on conflict (code) do nothing;


-- ═══════════════════════════════════════════════════════════════════════════
-- 3. توزيع الصلاحيات بحكمة — كل دور يحصل على ما يحتاجه
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── دالة مساعدة مؤقتة لمنح مجموعة صلاحيات لدور ───
create or replace function pg_temp.grant_perms(
  p_role_slug text,
  p_codes     text[],
  p_scope     text default 'organization'
) returns void language plpgsql as $$
declare
  v_role_id uuid;
  v_code    text;
  v_perm_id uuid;
begin
  select id into v_role_id from public.roles where slug = p_role_slug;
  if v_role_id is null then return; end if;

  foreach v_code in array p_codes loop
    select id into v_perm_id from public.permissions where code = v_code;
    if v_perm_id is not null then
      insert into public.role_permissions (role_id, permission_id, scope)
      values (v_role_id, v_perm_id, p_scope)
      on conflict (role_id, permission_id, scope) do nothing;
    end if;
  end loop;
end;
$$;


-- ── المدير التنفيذي (executive) — رؤية استراتيجية + اعتماد نهائي ──
-- يرى كل شيء، يعتمد القرارات الحساسة، لا يدير العمليات اليومية
select pg_temp.grant_perms('executive', array[
  -- شؤون الموظفين (قراءة + ترقية)
  'people.employee.read', 'people.employee.view_compensation',
  'people.employee.view_history', 'people.employee.view_audit',
  'people.employee.promote', 'people.employee.change_status',
  -- الهيكل التنظيمي
  'organization.entity.read', 'organization.org_chart.read',
  -- الحضور (قراءة ملخصات)
  'attendance.record.read', 'attendance.record.read_location',
  'attendance.record.export',
  -- الموقع المباشر (طلب ومتابعة)
  'live_location.request', 'live_location.request_group',
  'live_location.cancel', 'live_location.view_response',
  'live_location.view_history', 'live_location.read_access_log',
  'live_location.export',
  -- الطلبات (قراءة + اعتماد نهائي + تجاوز)
  'requests.request.read', 'requests.request.approve',
  'requests.request.reject', 'requests.request.override',
  'requests.request.delegate', 'requests.approve', 'requests.read',
  -- الأداء (مراجعة تنفيذية + اعتماد نهائي)
  'performance.kpi.read', 'performance.kpi.executive_review',
  'performance.kpi.finalize', 'performance.kpi.view_reviewer_notes',
  'performance.kpi.view_sensitive_scores', 'performance.kpi.export',
  'performance.calibration.manage',
  -- الاتصالات (نشر رسمي)
  'communications.announcement.create', 'communications.announcement.publish',
  'communications.decision.create', 'communications.decision.publish',
  'communications.decision.read_receipts',
  -- علاقات الموظفين (اعتماد التأديب)
  'relations.discipline.approve', 'relations.case.read',
  -- التقارير (كل التقارير)
  'reports.people.read', 'reports.attendance.read',
  'reports.requests.read', 'reports.performance.read',
  'reports.operations.read', 'reports.report.export',
  'reports.report.schedule'
], 'organization');

-- كرر نفس المنح لـ executive-director (نفس المفهوم، slug مختلف من الـ seed)
select pg_temp.grant_perms('executive-director', array[
  'people.employee.read', 'people.employee.view_compensation',
  'people.employee.view_history', 'people.employee.view_audit',
  'people.employee.promote', 'people.employee.change_status',
  'organization.entity.read', 'organization.org_chart.read',
  'attendance.record.read', 'attendance.record.read_location',
  'attendance.record.export',
  'live_location.request', 'live_location.request_group',
  'live_location.cancel', 'live_location.view_response',
  'live_location.view_history', 'live_location.read_access_log',
  'live_location.export',
  'requests.request.read', 'requests.request.approve',
  'requests.request.reject', 'requests.request.override',
  'requests.request.delegate', 'requests.approve', 'requests.read',
  'performance.kpi.read', 'performance.kpi.executive_review',
  'performance.kpi.finalize', 'performance.kpi.view_reviewer_notes',
  'performance.kpi.view_sensitive_scores', 'performance.kpi.export',
  'performance.calibration.manage',
  'communications.announcement.create', 'communications.announcement.publish',
  'communications.decision.create', 'communications.decision.publish',
  'communications.decision.read_receipts',
  'relations.discipline.approve', 'relations.case.read',
  'reports.people.read', 'reports.attendance.read',
  'reports.requests.read', 'reports.performance.read',
  'reports.operations.read', 'reports.report.export',
  'reports.report.schedule'
], 'organization');


-- ── مدير التشغيل (operations-manager) — إدارة ميدانية كاملة ──
-- مهام، حوادث، قوافل، مأموريات، حضور ميداني، تقارير تشغيلية

-- نطبق على كل الأدوار التي تبدأ بـ operations-manager
do $$
declare
  v_slug text;
  v_codes text[] := array[
    -- العمليات (كل شيء)
    'operations.task.read', 'operations.task.create', 'operations.task.update',
    'operations.task.assign', 'operations.task.complete', 'operations.task.cancel',
    'operations.incident.manage', 'operations.convoy.manage', 'operations.mission.manage',
    'operations.shift_handover.create', 'operations.shift_handover.read',
    -- التكليفات
    'assignments.mission.manage', 'assignments.convoy.manage',
    'assignments.fundraising.manage', 'assignments.report.review',
    -- الحضور (قراءة ميدانية)
    'attendance.record.read', 'attendance.record.read_location',
    'attendance.record.export', 'attendance.shift.read',
    -- الموقع المباشر
    'live_location.request', 'live_location.request_group',
    'live_location.cancel', 'live_location.view_response',
    'live_location.view_history',
    -- الطلبات (موافقة عند غياب المدير المباشر)
    'requests.request.read', 'requests.request.approve',
    'requests.request.reject', 'requests.request.return_for_correction',
    'requests.approve', 'requests.read',
    -- شؤون الموظفين (قراءة)
    'people.employee.read', 'people.employee.view_contact',
    -- الأداء (قراءة)
    'performance.kpi.read',
    -- التقارير (تشغيلية)
    'reports.operations.read', 'reports.attendance.read',
    -- الهيكل
    'organization.org_chart.read'
  ];
begin
  for v_slug in (select slug from public.roles where slug like 'operations-manager%') loop
    perform pg_temp.grant_perms(v_slug, v_codes, 'department');
  end loop;
end $$;


-- ── المدير المباشر (direct-manager) — إدارة الفريق المباشر ──
select pg_temp.grant_perms('direct-manager', array[
  -- شؤون الموظفين (قراءة المرؤوسين)
  'people.employee.read', 'people.employee.view_contact',
  'people.employee.view_history',
  -- الحضور (متابعة + تصحيحات)
  'attendance.record.read', 'attendance.record.read_location',
  'attendance.correction.review', 'attendance.correction.approve',
  'attendance.correction.reject', 'attendance.shift.read',
  -- الطلبات (موافقة/رفض)
  'requests.request.read', 'requests.request.approve',
  'requests.request.reject', 'requests.request.return_for_correction',
  'requests.approve', 'requests.read',
  -- الأداء (تقييم المرؤوسين)
  'performance.kpi.read', 'performance.kpi.manager_assess',
  'performance.kpi.view_reviewer_notes', 'performance.goal.manage_team',
  -- المهام
  'operations.task.read', 'operations.task.assign',
  -- التكليفات
  'assignments.mission.manage', 'assignments.convoy.manage',
  'assignments.fundraising.manage', 'assignments.report.review',
  -- الموقع المباشر
  'live_location.request', 'live_location.view_response',
  'live_location.view_history'
], 'direct_reports');


-- ── مدير الإدارة (department-manager) — كل الإدارة ──
select pg_temp.grant_perms('department-manager', array[
  -- شؤون الموظفين
  'people.employee.read', 'people.employee.view_contact',
  'people.employee.view_history', 'people.employee.assign_manager',
  -- الحضور
  'attendance.record.read', 'attendance.record.read_location',
  'attendance.record.export', 'attendance.correction.review',
  'attendance.correction.approve', 'attendance.correction.reject',
  'attendance.shift.read', 'attendance.shift.assign',
  -- الطلبات
  'requests.request.read', 'requests.request.approve',
  'requests.request.reject', 'requests.request.return_for_correction',
  'requests.request.escalate', 'requests.approve', 'requests.read',
  -- الأداء
  'performance.kpi.read', 'performance.kpi.manager_assess',
  'performance.kpi.view_reviewer_notes', 'performance.goal.manage_team',
  -- المهام
  'operations.task.read', 'operations.task.assign',
  -- التكليفات
  'assignments.mission.manage', 'assignments.convoy.manage',
  'assignments.fundraising.manage', 'assignments.report.review',
  -- الموقع المباشر
  'live_location.request', 'live_location.view_response',
  'live_location.view_history',
  -- التقارير
  'reports.attendance.read', 'reports.people.read', 'reports.requests.read',
  -- الهيكل
  'organization.org_chart.read'
], 'department');


-- ── الموظف (employee) — خدمة ذاتية ──
select pg_temp.grant_perms('employee', array[
  -- الحضور (تسجيل + عرض)
  'attendance.punch.check_in', 'attendance.punch.check_out',
  'attendance.record.read', 'attendance.correction.create',
  -- الطلبات (إنشاء + متابعة)
  'requests.request.read', 'requests.request.create',
  'requests.request.update_draft', 'requests.request.submit',
  'requests.request.withdraw', 'requests.leave.balance.read',
  -- الأداء (تقييم ذاتي)
  'performance.kpi.read', 'performance.kpi.self_assess',
  'performance.goal.manage_self',
  -- المستندات (عرض)
  'documents.employee.read', 'documents.policy.acknowledge',
  -- الاتصالات (إقرار)
  'communications.decision.acknowledge',
  -- بيانات شخصية
  'people.employee.view_contact', 'people.employee.upload_avatar'
], 'self');


-- ── رئيس اللجنة (committee-chair) — إدارة قضايا + تأديب ──
select pg_temp.grant_perms('committee-chair', array[
  'relations.case.read', 'relations.case.create', 'relations.case.update',
  'relations.case.assign', 'relations.case.resolve', 'relations.case.close',
  'relations.case.export', 'relations.committee.manage_members',
  'relations.discipline.create', 'relations.discipline.approve',
  'documents.employee.read', 'people.employee.read'
], 'assigned_cases');


-- ── عضو اللجنة (committee-member) — اطلاع + تحديث ──
select pg_temp.grant_perms('committee-member', array[
  'relations.case.read', 'relations.case.update', 'relations.case.resolve',
  'relations.discipline.create',
  'documents.employee.read', 'people.employee.read'
], 'assigned_cases');


-- ── مسؤول تقني (system-admin) — إدارة النظام فقط ──
select pg_temp.grant_perms('system-admin', array[
  'system.settings.read', 'system.settings.update_general',
  'system.settings.update_security',
  'system.feature_flags.manage', 'system.integrations.manage',
  'system.jobs.read', 'system.jobs.retry',
  'system.audit.read',
  'system.security_events.read', 'system.security_events.resolve',
  'system.backup.read_status', 'system.backup.run',
  'access.audit.read', 'access.account.read'
], 'organization');


-- ── ضابط عمليات (operations-officer) — تنفيذ ميداني ──
select pg_temp.grant_perms('operations-officer', array[
  'operations.task.read', 'operations.task.update', 'operations.task.complete',
  'operations.shift_handover.create', 'operations.shift_handover.read',
  'attendance.punch.check_in', 'attendance.punch.check_out',
  'live_location.view_response'
], 'self');

select pg_temp.grant_perms('operations-officer', array[
  'assignments.mission.manage', 'assignments.convoy.manage',
  'assignments.fundraising.manage', 'assignments.report.review'
], 'organization');


-- ── أخصائي موارد بشرية (hr-specialist) — عمليات HR أساسية ──
select pg_temp.grant_perms('hr-specialist', array[
  'people.employee.read', 'people.employee.create', 'people.employee.update_basic',
  'people.employee.import', 'people.employee.export',
  'people.employee.view_contact', 'people.employee.view_history',
  'people.employee.manage_documents',
  'attendance.record.read', 'attendance.record.export',
  'attendance.correction.review',
  'requests.request.read', 'requests.read', 'requests.leave.balance.read',
  'documents.employee.read', 'documents.employee.create', 'documents.employee.update',
  'documents.contract.read', 'documents.expiry.manage',
  'performance.kpi.read', 'performance.kpi.hr_review',
  'reports.people.read', 'reports.attendance.read',
  'organization.org_chart.read'
], 'organization');


-- حذف الدالة المساعدة المؤقتة (pg_temp تنتهي مع الجلسة تلقائياً)

commit;
