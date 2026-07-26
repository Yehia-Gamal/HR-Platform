-- =====================================================================================
-- Seed 0001: Permissions catalog + Role templates + Role/Permission bindings (RBAC/ABAC)
-- =====================================================================================
-- الغرض: بدون بذر الصلاحيات ستُرجع public.has_permission(...) القيمة false لكل من ليس
-- full-access (admin/super-admin)، لأن الدالة تعتمد على وجود صفوف في role_permissions.
-- هذا الملف idempotent بالكامل: يمكن تشغيله أكثر من مرة دون أثر جانبي.
-- ملاحظة النطاق: صلاحيات payro.* متعمّد تجاهلها (خارج نطاق هذا الإصدار).
--
-- تشغيل: psql "$DATABASE_URL" -f supabase/seed/0001_seed_permissions_roles.sql
--        أو عبر supabase db push بعد نسخه لمجلد seed.
-- =====================================================================================

begin;

-- =====================================================================================
-- 1) كتالوج الصلاحيات: public.permissions
--    module/resource/action تُشتق من code بالتقسيم على النقاط (split_part).
--    code فريد => on conflict (code) do update لضمان الاتساق عند إعادة التشغيل.
-- =====================================================================================

with codes(code) as (
  values
  -- ================= 1) People / Employees =================
    ('people.employee.read'),
    ('people.employee.create'),
    ('people.employee.update_basic'),
    ('people.employee.update_sensitive'),
    ('people.employee.archive'),
    ('people.employee.terminate'),
    ('people.employee.restore'),
    ('people.employee.import'),
    ('people.employee.export'),
    ('people.employee.assign_manager'),
    ('people.employee.transfer'),
    ('people.employee.promote'),
    ('people.employee.change_status'),
    ('people.employee.view_identity'),
    ('people.employee.view_contact'),
    ('people.employee.view_compensation'),
    ('people.employee.view_history'),
    ('people.employee.view_audit'),
    ('people.employee.upload_avatar'),
    ('people.employee.manage_documents'),

  -- ================= 2) Organization =================
    ('organization.entity.read'),
    ('organization.entity.manage'),
    ('organization.branch.manage'),
    ('organization.department.manage'),
    ('organization.unit.manage'),
    ('organization.position.manage'),
    ('organization.job_title.manage'),
    ('organization.grade.manage'),
    ('organization.org_chart.read'),

  -- ================= 3) Access / Security control =================
    ('access.account.read'),
    ('access.account.create'),
    ('access.account.update'),
    ('access.account.clone'),
    ('access.account.assign'),
    ('access.account.remove'),
    ('access.account.approve_sensitive_change'),
    ('access.account.preview'),
    ('access.role.read'),
    ('access.role.create'),
    ('access.role.update'),
    ('access.role.clone'),
    ('access.role.assign'),
    ('access.role.remove'),
    ('access.role.approve_sensitive_change'),
    ('access.role.preview'),
    ('access.audit.read'),
    ('access.break_glass.activate'),

  -- ================= 4) Attendance =================
    ('attendance.punch.check_in'),
    ('attendance.punch.check_out'),
    ('attendance.record.read'),
    ('attendance.record.read_location'),
    ('attendance.record.read_identity_check'),
    ('attendance.record.read_risk'),
    ('attendance.record.export'),
    ('attendance.record.manual_create'),
    ('attendance.record.void'),
    ('attendance.correction.create'),
    ('attendance.correction.review'),
    ('attendance.correction.approve'),
    ('attendance.correction.reject'),
    ('attendance.risk.review'),
    ('attendance.risk.resolve'),
    ('attendance.shift.read'),
    ('attendance.shift.manage'),
    ('attendance.shift.assign'),
    ('attendance.calendar.manage'),
    ('attendance.geofence.manage'),
    ('attendance.policy.manage'),
    ('attendance.period.close'),
    ('attendance.period.unlock'),

  -- ================= 5) Live location =================
    ('live_location.request'),
    ('live_location.request_group'),
    ('live_location.cancel'),
    ('live_location.view_response'),
    ('live_location.view_history'),
    ('live_location.export'),
    ('live_location.manage_policy'),
    ('live_location.manage_retention'),
    ('live_location.read_access_log'),

  -- ================= 6) Requests / Workflow =================
    ('requests.request.read'),
    ('requests.request.create'),
    ('requests.request.update_draft'),
    ('requests.request.submit'),
    ('requests.request.withdraw'),
    ('requests.request.cancel_approved'),
    ('requests.request.return_for_correction'),
    ('requests.request.approve'),
    ('requests.request.reject'),
    ('requests.request.delegate'),
    ('requests.request.escalate'),
    ('requests.request.override'),
    ('requests.approve'),
    ('requests.read'),
    ('requests.workflow.read'),
    ('requests.workflow.manage'),
    ('requests.workflow.publish_version'),
    ('requests.workflow.view_audit'),
    ('requests.leave.balance.read'),
    ('requests.leave.balance.adjust'),
    ('requests.leave.policy.manage'),
    ('requests.leave.execute_casual'),

  -- ================= 7) Operations =================
    ('operations.task.read'),
    ('operations.task.create'),
    ('operations.task.update'),
    ('operations.task.assign'),
    ('operations.task.complete'),
    ('operations.task.cancel'),
    ('operations.incident.manage'),
    ('operations.convoy.manage'),
    ('operations.mission.manage'),
    ('operations.shift_handover.create'),
    ('operations.shift_handover.read'),
  -- تكليفات العمل الجديدة (مأمورية/قافلة/فاندي) — وحدة work_assignments (0063).
    ('assignments.mission.manage'),
    ('assignments.convoy.manage'),
    ('assignments.fundraising.manage'),
    ('assignments.report.review'),

  -- ================= 8) Performance / KPI =================
    ('performance.kpi.read'),
    ('performance.kpi.self_assess'),
    ('performance.kpi.manager_assess'),
    ('performance.kpi.hr_review'),
    ('performance.kpi.secretary_review'),
    ('performance.kpi.executive_review'),
    ('performance.kpi.finalize'),
    ('performance.kpi.reopen_amendment'),
    ('performance.kpi.view_reviewer_notes'),
    ('performance.kpi.view_sensitive_scores'),
    ('performance.kpi.export'),
    ('performance.template.manage'),
    ('performance.cycle.manage'),
    ('performance.calibration.manage'),
    ('performance.pip.manage'),
    ('performance.goal.manage_self'),
    ('performance.goal.manage_team'),

  -- ================= 9) Documents =================
    ('documents.employee.read'),
    ('documents.employee.create'),
    ('documents.employee.update'),
    ('documents.employee.delete'),
    ('documents.employee.export'),
    ('documents.contract.read'),
    ('documents.contract.create'),
    ('documents.contract.update'),
    ('documents.contract.delete'),
    ('documents.contract.export'),
    ('documents.policy.publish'),
    ('documents.policy.acknowledge'),
    ('documents.expiry.manage'),

  -- ================= 10) Employee relations / cases =================
    ('relations.case.read'),
    ('relations.case.create'),
    ('relations.case.update'),
    ('relations.case.assign'),
    ('relations.case.resolve'),
    ('relations.case.close'),
    ('relations.case.export'),
    ('relations.committee.manage_templates'),
    ('relations.committee.manage_members'),
    ('relations.discipline.create'),
    ('relations.discipline.approve'),

  -- ================= 11) Communications =================
    ('communications.announcement.create'),
    ('communications.announcement.publish'),
    ('communications.announcement.manage_targets'),
    ('communications.decision.create'),
    ('communications.decision.publish'),
    ('communications.decision.acknowledge'),
    ('communications.decision.read_receipts'),
    ('communications.notification.send'),
    ('communications.notification.send_bulk'),
    ('communications.survey.manage'),

  -- ================= 12) Reports =================
    ('reports.attendance.read'),
    ('reports.people.read'),
    ('reports.requests.read'),
    ('reports.performance.read'),
    ('reports.operations.read'),
    ('reports.report.export'),
    ('reports.report.schedule'),
    ('reports.builder.use'),
    ('reports.builder.manage_catalog'),

  -- ================= 13) System administration =================
    ('system.settings.read'),
    ('system.settings.update_general'),
    ('system.settings.update_security'),
    ('system.feature_flags.manage'),
    ('system.integrations.manage'),
    ('system.jobs.read'),
    ('system.jobs.retry'),
    ('system.audit.read'),
    ('system.security_events.read'),
    ('system.security_events.resolve'),
    ('system.backup.read_status'),
    ('system.backup.run'),
    ('system.restore.execute')
)
insert into public.permissions (code, module, resource, action, description, risk_level, is_sensitive)
select
  c.code,
  split_part(c.code, '.', 1)                                        as module,
  -- resource = كل ما بين أول نقطة وآخر نقطة (يدعم أكواد بأربعة أجزاء مثل requests.leave.balance.read)
  case
    when array_length(string_to_array(c.code, '.'), 1) <= 2
      then split_part(c.code, '.', 1)
    else array_to_string(
           (string_to_array(c.code, '.'))[2 : array_length(string_to_array(c.code, '.'), 1) - 1],
           '.')
  end                                                               as resource,
  -- action = آخر جزء بعد آخر نقطة
  reverse(split_part(reverse(c.code), '.', 1))                      as action,
  null::text                                                        as description,
  -- تصنيف المخاطر: الأكواد الحسّاسة/الحرجة
  case
    when c.code in (
      'people.employee.update_sensitive','people.employee.terminate',
      'people.employee.view_compensation','people.employee.view_identity',
      'people.employee.view_audit',
      'access.account.approve_sensitive_change','access.role.approve_sensitive_change',
      'access.role.assign','access.role.remove','access.role.create','access.role.update',
      'attendance.record.read_identity_check','attendance.period.unlock',
      'live_location.export','live_location.read_access_log',
      'requests.request.override','performance.kpi.view_sensitive_scores',
      'relations.discipline.approve','system.settings.update_security',
      'system.security_events.resolve'
    ) then 'sensitive'
    when c.code in (
      'access.break_glass.activate','system.restore.execute','system.backup.run'
    ) then 'critical'
    else 'normal'
  end                                                               as risk_level,
  case
    when c.code in (
      'people.employee.update_sensitive','people.employee.terminate',
      'people.employee.view_compensation','people.employee.view_identity',
      'people.employee.view_audit',
      'access.account.approve_sensitive_change','access.role.approve_sensitive_change',
      'access.role.assign','access.role.remove','access.role.create','access.role.update',
      'attendance.record.read_identity_check','attendance.period.unlock',
      'live_location.export','live_location.read_access_log',
      'requests.request.override','performance.kpi.view_sensitive_scores',
      'relations.discipline.approve','system.settings.update_security',
      'system.security_events.resolve',
      'access.break_glass.activate','system.restore.execute','system.backup.run'
    ) then true
    else false
  end                                                               as is_sensitive
from codes c
on conflict (code) do update set
  module       = excluded.module,
  resource     = excluded.resource,
  action       = excluded.action,
  risk_level   = excluded.risk_level,
  is_sensitive = excluded.is_sensitive,
  updated_at   = now();

-- =====================================================================================
-- 2) قوالب الأدوار: public.roles
--    slug فريد => on conflict (slug) do update. is_system=true للقوالب المحمية.
--    is_full_access=true لـ admin والسكرتير التنفيذي بصفته الأدمن الرئيسي.
-- =====================================================================================

insert into public.roles (slug, name_ar, name_en, description, is_system, is_full_access)
values
  ('admin',               'مدير النظام (كامل الصلاحية)', 'System Administrator (Full Access)', 'وصول كامل — super/full admin', true,  true),
  ('employee',            'موظف',                        'Employee',                           'صلاحيات الموظف على بياناته فقط', true, false),
  ('operations-officer',  'ضابط عمليات',                 'Operations Officer',                 'تنفيذ المهام والعمليات الميدانية', true, false),
  ('operations-manager',  'مدير العمليات',               'Operations Manager',                 'إدارة العمليات والمهام والحوادث والقوافل', true, false),
  ('direct-manager',      'مدير مباشر',                  'Direct Manager',                     'إدارة المرؤوسين المباشرين والموافقات وتقييم الأداء', true, false),
  ('department-manager',  'مدير إدارة',                  'Department Manager',                 'إدارة على مستوى الإدارة', true, false),
  ('hr-specialist',       'أخصائي موارد بشرية',          'HR Specialist',                      'تنفيذ عمليات الموارد البشرية', true, false),
  ('hr-manager',          'مدير الموارد البشرية',        'HR Manager',                         'إدارة الموارد البشرية على مستوى المنظمة', true, false),
  ('executive-secretary', 'السكرتير التنفيذي (الأدمن الرئيسي)', 'Executive Secretary (Main Administrator)', 'إدارة النظام بالكامل ومراجعة الأداء والتحكم في دوراته', true, true),
  ('executive-director',  'المدير التنفيذي',             'Executive Director',                 'الاعتماد النهائي والقرارات والتقارير التنفيذية', true, false),
  ('committee-member',    'عضو لجنة',                    'Committee Member',                   'مراجعة الحالات المسندة للجنة', true, false),
  ('committee-chair',     'رئيس لجنة',                   'Committee Chair',                    'قيادة اللجان واعتماد الإجراءات التأديبية', true, false),
  ('system-admin',        'مسؤول تقني',                  'System Admin (Technical)',           'إدارة إعدادات النظام والتكامل والمهام والنسخ الاحتياطي', true, false)
on conflict (slug) do update set
  name_ar        = excluded.name_ar,
  name_en        = excluded.name_en,
  description    = excluded.description,
  is_system      = excluded.is_system,
  is_full_access = excluded.is_full_access,
  updated_at     = now();

-- =====================================================================================
-- 3) ربط الصلاحيات بالأدوار: public.role_permissions
--    نستخدم CTE يبني (role_slug, permission_code, scope) ثم نربط عبر الـid.
--    unique(role_id, permission_id, scope) => on conflict do nothing => idempotent.
--    ملاحظة: دور admin full_access لا يحتاج صفوفاً؛ has_permission يمر عبر current_is_full_access.
-- =====================================================================================

with mapping(role_slug, permission_code, scope) as (
  values
  -- ============================================================
  -- employee: نطاق self فقط
  -- ============================================================
    ('employee','attendance.punch.check_in','self'),
    ('employee','attendance.punch.check_out','self'),
    ('employee','attendance.record.read','self'),
    ('employee','requests.request.read','self'),
    ('employee','requests.request.create','self'),
    ('employee','requests.request.update_draft','self'),
    ('employee','requests.request.submit','self'),
    ('employee','requests.request.withdraw','self'),
    ('employee','requests.leave.balance.read','self'),
    ('employee','performance.kpi.read','self'),
    ('employee','performance.kpi.self_assess','self'),
    ('employee','performance.goal.manage_self','self'),
    ('employee','documents.employee.read','self'),
    ('employee','documents.policy.acknowledge','self'),
    ('employee','communications.decision.acknowledge','self'),
    ('employee','people.employee.view_contact','self'),
    ('employee','people.employee.upload_avatar','self'),

  -- ============================================================
  -- direct-manager: نطاق direct_reports (قراءة/موافقات/تقييم مدير)
  --   يرث ضمنياً قدرات الموظف على نفسه عبر إسناد دور employee له في التطبيق.
  -- ============================================================
    ('direct-manager','people.employee.read','direct_reports'),
    ('direct-manager','people.employee.view_contact','direct_reports'),
    ('direct-manager','people.employee.view_history','direct_reports'),
    ('direct-manager','attendance.record.read','direct_reports'),
    ('direct-manager','attendance.record.read_location','direct_reports'),
    ('direct-manager','attendance.correction.review','direct_reports'),
    ('direct-manager','attendance.correction.approve','direct_reports'),
    ('direct-manager','attendance.correction.reject','direct_reports'),
    ('direct-manager','attendance.shift.read','direct_reports'),
    ('direct-manager','requests.request.read','direct_reports'),
    ('direct-manager','requests.request.approve','direct_reports'),
    ('direct-manager','requests.request.reject','direct_reports'),
    ('direct-manager','requests.request.return_for_correction','direct_reports'),
    ('direct-manager','requests.approve','direct_reports'),
    ('direct-manager','requests.read','direct_reports'),
    ('direct-manager','performance.kpi.read','direct_reports'),
    ('direct-manager','performance.kpi.manager_assess','direct_reports'),
    ('direct-manager','performance.kpi.view_reviewer_notes','direct_reports'),
    ('direct-manager','performance.goal.manage_team','direct_reports'),
    ('direct-manager','operations.task.read','direct_reports'),
    ('direct-manager','operations.task.assign','direct_reports'),
    -- تكليفات العمل: المدير المباشر ينشئ لتابعيه (direct_reports).
    ('direct-manager','assignments.mission.manage','direct_reports'),
    ('direct-manager','assignments.convoy.manage','direct_reports'),
    ('direct-manager','assignments.fundraising.manage','direct_reports'),
    ('direct-manager','assignments.report.review','direct_reports'),
    -- طلب الموقع الحي: المدير المباشر يطلب موقع مرؤوسيه المباشرين فقط.
    ('direct-manager','live_location.request','direct_reports'),
    ('direct-manager','live_location.view_response','direct_reports'),
    ('direct-manager','live_location.view_history','direct_reports'),

  -- ============================================================
  -- department-manager: نطاق department (توسعة صلاحيات المدير المباشر)
  -- ============================================================
    ('department-manager','people.employee.read','department'),
    ('department-manager','people.employee.view_contact','department'),
    ('department-manager','people.employee.view_history','department'),
    ('department-manager','people.employee.assign_manager','department'),
    ('department-manager','attendance.record.read','department'),
    ('department-manager','attendance.record.read_location','department'),
    ('department-manager','attendance.record.export','department'),
    ('department-manager','attendance.correction.review','department'),
    ('department-manager','attendance.correction.approve','department'),
    ('department-manager','attendance.correction.reject','department'),
    ('department-manager','attendance.shift.read','department'),
    ('department-manager','attendance.shift.assign','department'),
    ('department-manager','requests.request.read','department'),
    ('department-manager','requests.request.approve','department'),
    ('department-manager','requests.request.reject','department'),
    ('department-manager','requests.request.return_for_correction','department'),
    ('department-manager','requests.request.escalate','department'),
    ('department-manager','requests.approve','department'),
    ('department-manager','requests.read','department'),
    ('department-manager','performance.kpi.read','department'),
    ('department-manager','performance.kpi.manager_assess','department'),
    ('department-manager','performance.kpi.view_reviewer_notes','department'),
    ('department-manager','performance.goal.manage_team','department'),
    ('department-manager','operations.task.read','department'),
    ('department-manager','operations.task.assign','department'),
    ('department-manager','reports.attendance.read','department'),
    ('department-manager','reports.people.read','department'),
    ('department-manager','reports.requests.read','department'),

  -- ============================================================
  -- hr-manager: نطاق organization لوحدات people/attendance/requests/documents/reports
  -- ============================================================
    ('hr-manager','people.employee.read','organization'),
    ('hr-manager','people.employee.create','organization'),
    ('hr-manager','people.employee.update_basic','organization'),
    ('hr-manager','people.employee.update_sensitive','organization'),
    ('hr-manager','people.employee.archive','organization'),
    ('hr-manager','people.employee.terminate','organization'),
    ('hr-manager','people.employee.restore','organization'),
    ('hr-manager','people.employee.import','organization'),
    ('hr-manager','people.employee.export','organization'),
    ('hr-manager','people.employee.assign_manager','organization'),
    ('hr-manager','people.employee.transfer','organization'),
    ('hr-manager','people.employee.promote','organization'),
    ('hr-manager','people.employee.change_status','organization'),
    ('hr-manager','people.employee.view_identity','organization'),
    ('hr-manager','people.employee.view_contact','organization'),
    ('hr-manager','people.employee.view_compensation','organization'),
    ('hr-manager','people.employee.view_history','organization'),
    ('hr-manager','people.employee.view_audit','organization'),
    ('hr-manager','people.employee.manage_documents','organization'),
    ('hr-manager','attendance.record.read','organization'),
    ('hr-manager','attendance.record.read_location','organization'),
    ('hr-manager','attendance.record.read_risk','organization'),
    ('hr-manager','attendance.record.export','organization'),
    ('hr-manager','attendance.record.manual_create','organization'),
    ('hr-manager','attendance.record.void','organization'),
    ('hr-manager','attendance.correction.review','organization'),
    ('hr-manager','attendance.correction.approve','organization'),
    ('hr-manager','attendance.correction.reject','organization'),
    ('hr-manager','attendance.risk.review','organization'),
    ('hr-manager','attendance.risk.resolve','organization'),
    ('hr-manager','attendance.shift.read','organization'),
    ('hr-manager','attendance.shift.manage','organization'),
    ('hr-manager','attendance.shift.assign','organization'),
    ('hr-manager','attendance.calendar.manage','organization'),
    ('hr-manager','attendance.policy.manage','organization'),
    ('hr-manager','attendance.period.close','organization'),
    ('hr-manager','requests.request.read','organization'),
    ('hr-manager','requests.request.approve','organization'),
    ('hr-manager','requests.request.reject','organization'),
    ('hr-manager','requests.request.return_for_correction','organization'),
    ('hr-manager','requests.request.delegate','organization'),
    ('hr-manager','requests.request.escalate','organization'),
    ('hr-manager','requests.approve','organization'),
    ('hr-manager','requests.read','organization'),
    ('hr-manager','requests.workflow.read','organization'),
    ('hr-manager','requests.workflow.manage','organization'),
    ('hr-manager','requests.leave.balance.read','organization'),
    ('hr-manager','requests.leave.balance.adjust','organization'),
    ('hr-manager','requests.leave.policy.manage','organization'),
    ('hr-manager','documents.employee.read','organization'),
    ('hr-manager','documents.employee.create','organization'),
    ('hr-manager','documents.employee.update','organization'),
    ('hr-manager','documents.employee.delete','organization'),
    ('hr-manager','documents.employee.export','organization'),
    ('hr-manager','documents.contract.read','organization'),
    ('hr-manager','documents.contract.create','organization'),
    ('hr-manager','documents.contract.update','organization'),
    ('hr-manager','documents.contract.delete','organization'),
    ('hr-manager','documents.contract.export','organization'),
    ('hr-manager','documents.policy.publish','organization'),
    ('hr-manager','documents.expiry.manage','organization'),
    ('hr-manager','reports.attendance.read','organization'),
    ('hr-manager','reports.people.read','organization'),
    ('hr-manager','reports.requests.read','organization'),
    ('hr-manager','reports.performance.read','organization'),
    ('hr-manager','reports.report.export','organization'),
    ('hr-manager','reports.report.schedule','organization'),
    ('hr-manager','reports.builder.use','organization'),

  -- ============================================================
  -- hr-specialist: تنفيذي على مستوى organization لكن بدون العمليات الحسّاسة/الاعتماد
  -- ============================================================
    ('hr-specialist','people.employee.read','organization'),
    ('hr-specialist','people.employee.create','organization'),
    ('hr-specialist','people.employee.update_basic','organization'),
    ('hr-specialist','people.employee.import','organization'),
    ('hr-specialist','people.employee.export','organization'),
    ('hr-specialist','people.employee.view_contact','organization'),
    ('hr-specialist','people.employee.view_history','organization'),
    ('hr-specialist','people.employee.manage_documents','organization'),
    ('hr-specialist','attendance.record.read','organization'),
    ('hr-specialist','attendance.record.export','organization'),
    ('hr-specialist','attendance.correction.review','organization'),
    ('hr-specialist','requests.request.read','organization'),
    ('hr-specialist','requests.read','organization'),
    ('hr-specialist','requests.leave.balance.read','organization'),
    ('hr-specialist','documents.employee.read','organization'),
    ('hr-specialist','documents.employee.create','organization'),
    ('hr-specialist','documents.employee.update','organization'),
    ('hr-specialist','documents.contract.read','organization'),
    ('hr-specialist','documents.expiry.manage','organization'),
    ('hr-specialist','reports.people.read','organization'),
    ('hr-specialist','reports.attendance.read','organization'),
    ('hr-specialist','performance.kpi.read','organization'),
    ('hr-specialist','performance.kpi.hr_review','organization'),

  -- ============================================================
  -- executive-secretary: دعم المكتب التنفيذي ومراجعة السكرتير للأداء
  -- ============================================================
    ('executive-secretary','people.employee.read','organization'),
    ('executive-secretary','requests.request.read','organization'),
    ('executive-secretary','requests.read','organization'),
    ('executive-secretary','requests.workflow.read','organization'),
    ('executive-secretary','performance.kpi.read','organization'),
    ('executive-secretary','performance.kpi.secretary_review','organization'),
    ('executive-secretary','performance.cycle.manage','organization'),
    ('executive-secretary','performance.kpi.view_reviewer_notes','organization'),
    ('executive-secretary','communications.announcement.create','organization'),
    ('executive-secretary','communications.decision.create','organization'),
    ('executive-secretary','communications.notification.send','organization'),
    ('executive-secretary','reports.people.read','organization'),
    ('executive-secretary','reports.requests.read','organization'),
    ('executive-secretary','reports.performance.read','organization'),
    -- السكرتير التنفيذي (Main Admin): صلاحية كاملة على الإجازات والتكليفات (البند 18).
    ('executive-secretary','requests.request.approve','organization'),
    ('executive-secretary','requests.request.reject','organization'),
    ('executive-secretary','requests.request.override','organization'),
    ('executive-secretary','requests.request.delegate','organization'),
    ('executive-secretary','requests.request.escalate','organization'),
    ('executive-secretary','requests.approve','organization'),
    ('executive-secretary','requests.leave.balance.adjust','organization'),
    ('executive-secretary','requests.leave.policy.manage','organization'),
    ('executive-secretary','requests.leave.execute_casual','organization'),
    ('executive-secretary','assignments.mission.manage','organization'),
    ('executive-secretary','assignments.convoy.manage','organization'),
    ('executive-secretary','assignments.fundraising.manage','organization'),
    ('executive-secretary','assignments.report.review','organization'),

  -- ============================================================
  -- executive-director: نطاق organization للتقارير والقرارات والاعتماد النهائي
  -- ============================================================
    ('executive-director','people.employee.read','organization'),
    ('executive-director','people.employee.view_compensation','organization'),
    ('executive-director','people.employee.promote','organization'),
    ('executive-director','requests.request.read','organization'),
    ('executive-director','requests.request.approve','organization'),
    ('executive-director','requests.request.reject','organization'),
    ('executive-director','requests.request.override','organization'),
    ('executive-director','requests.approve','organization'),
    ('executive-director','requests.read','organization'),
    ('executive-director','performance.kpi.read','organization'),
    ('executive-director','performance.kpi.executive_review','organization'),
    ('executive-director','performance.kpi.finalize','organization'),
    ('executive-director','performance.kpi.view_reviewer_notes','organization'),
    ('executive-director','performance.kpi.view_sensitive_scores','organization'),
    ('executive-director','performance.calibration.manage','organization'),
    ('executive-director','communications.announcement.create','organization'),
    ('executive-director','communications.announcement.publish','organization'),
    ('executive-director','communications.decision.create','organization'),
    ('executive-director','communications.decision.publish','organization'),
    ('executive-director','communications.decision.read_receipts','organization'),
    ('executive-director','relations.discipline.approve','organization'),
    ('executive-director','reports.people.read','organization'),
    ('executive-director','reports.attendance.read','organization'),
    ('executive-director','reports.requests.read','organization'),
    ('executive-director','reports.performance.read','organization'),
    ('executive-director','reports.operations.read','organization'),
    ('executive-director','reports.report.export','organization'),
    -- طلب الموقع الحي: المدير التنفيذي يتابع كل موظفي الجمعية ويطلب موقعهم على مستوى المؤسسة
    ('executive-director','live_location.request','organization'),
    ('executive-director','live_location.request_group','organization'),
    ('executive-director','live_location.cancel','organization'),
    ('executive-director','live_location.view_response','organization'),
    ('executive-director','live_location.view_history','organization'),
    ('executive-director','live_location.read_access_log','organization'),
    ('executive-director','live_location.export','organization'),

  -- ============================================================
  -- committee-member: نطاق assigned_cases
  -- ============================================================
    ('committee-member','relations.case.read','assigned_cases'),
    ('committee-member','relations.case.update','assigned_cases'),
    ('committee-member','relations.case.resolve','assigned_cases'),
    ('committee-member','relations.discipline.create','assigned_cases'),
    ('committee-member','documents.employee.read','assigned_cases'),
    ('committee-member','people.employee.read','assigned_cases'),

  -- ============================================================
  -- committee-chair: قيادة اللجان + اعتماد التأديب (assigned_cases)
  -- ============================================================
    ('committee-chair','relations.case.read','assigned_cases'),
    ('committee-chair','relations.case.create','assigned_cases'),
    ('committee-chair','relations.case.update','assigned_cases'),
    ('committee-chair','relations.case.assign','assigned_cases'),
    ('committee-chair','relations.case.resolve','assigned_cases'),
    ('committee-chair','relations.case.close','assigned_cases'),
    ('committee-chair','relations.case.export','assigned_cases'),
    ('committee-chair','relations.committee.manage_members','assigned_cases'),
    ('committee-chair','relations.discipline.create','assigned_cases'),
    ('committee-chair','relations.discipline.approve','assigned_cases'),
    ('committee-chair','documents.employee.read','assigned_cases'),
    ('committee-chair','people.employee.read','assigned_cases'),

  -- ============================================================
  -- operations-officer: تنفيذ المهام (self على تسجيله + قراءة/تحديث مهامه)
  -- ============================================================
    ('operations-officer','operations.task.read','self'),
    ('operations-officer','operations.task.update','self'),
    ('operations-officer','operations.task.complete','self'),
    ('operations-officer','operations.shift_handover.create','self'),
    ('operations-officer','operations.shift_handover.read','self'),
    ('operations-officer','attendance.punch.check_in','self'),
    ('operations-officer','attendance.punch.check_out','self'),
    ('operations-officer','live_location.view_response','self'),
    -- تكليفات العمل: ضابط العمليات ينشئ لأي موظف (البند 17) — نطاق organization.
    ('operations-officer','assignments.mission.manage','organization'),
    ('operations-officer','assignments.convoy.manage','organization'),
    ('operations-officer','assignments.fundraising.manage','organization'),
    ('operations-officer','assignments.report.review','organization'),

  -- ============================================================
  -- operations-manager: إدارة العمليات على مستوى department
  -- ============================================================
    ('operations-manager','operations.task.read','department'),
    ('operations-manager','operations.task.create','department'),
    ('operations-manager','operations.task.update','department'),
    ('operations-manager','operations.task.assign','department'),
    ('operations-manager','operations.task.complete','department'),
    ('operations-manager','operations.task.cancel','department'),
    ('operations-manager','operations.incident.manage','department'),
    ('operations-manager','operations.convoy.manage','department'),
    ('operations-manager','operations.mission.manage','department'),
    ('operations-manager','operations.shift_handover.create','department'),
    ('operations-manager','operations.shift_handover.read','department'),
    ('operations-manager','live_location.request','department'),
    ('operations-manager','live_location.request_group','department'),
    ('operations-manager','live_location.cancel','department'),
    ('operations-manager','live_location.view_response','department'),
    ('operations-manager','live_location.view_history','department'),
    ('operations-manager','attendance.record.read','department'),
    ('operations-manager','attendance.record.read_location','department'),
    ('operations-manager','reports.operations.read','department'),
    -- تكليفات العمل: مدير العمليات ينشئ ويدير على مستوى الإدارة.
    ('operations-manager','assignments.mission.manage','department'),
    ('operations-manager','assignments.convoy.manage','department'),
    ('operations-manager','assignments.fundraising.manage','department'),
    ('operations-manager','assignments.report.review','department'),

  -- ============================================================
  -- system-admin: إدارة النظام (نطاق organization)
  -- ============================================================
    ('system-admin','system.settings.read','organization'),
    ('system-admin','system.settings.update_general','organization'),
    ('system-admin','system.settings.update_security','organization'),
    ('system-admin','system.feature_flags.manage','organization'),
    ('system-admin','system.integrations.manage','organization'),
    ('system-admin','system.jobs.read','organization'),
    ('system-admin','system.jobs.retry','organization'),
    ('system-admin','system.audit.read','organization'),
    ('system-admin','system.security_events.read','organization'),
    ('system-admin','system.security_events.resolve','organization'),
    ('system-admin','system.backup.read_status','organization'),
    ('system-admin','system.backup.run','organization'),
    ('system-admin','access.audit.read','organization'),
    ('system-admin','access.account.read','organization')
)
insert into public.role_permissions (role_id, permission_id, scope)
select r.id, p.id, m.scope
from mapping m
join public.roles r        on r.slug = m.role_slug
join public.permissions p  on p.code = m.permission_code
on conflict (role_id, permission_id, scope) do nothing;

-- =====================================================================================
-- 4) مستخدم Super Admin الأولي — لا يُنشأ هنا.
-- =====================================================================================
-- تعمّدنا عدم إنشاء أي مستخدم أو كلمة مرور في هذا الـSQL.
-- يُنشأ مستخدم Super Admin الأولي عبر سكربت admin آمن يستخدم Supabase Admin API
-- (auth.admin.createUser عبر service_role key، خارج الـSQL، في بيئة موثوقة فقط)،
-- ثم يُسند له دور 'admin' (is_full_access=true) عبر استدعاء public.rpc_assign_role
-- من سياق service_role/super-admin. لا تُخزَّن أي كلمة مرور أو سر داخل هذا الملف.
--
-- مثال (Node/TS، ليس SQL):
--   const { data: { user } } = await admin.auth.admin.createUser({ email, password, email_confirm: true });
--   const { data: role } = await admin.from('roles').select('id').eq('slug','admin').single();
--   await admin.rpc('rpc_assign_role', { p_user_id: user.id, p_role_id: role.id });
-- =====================================================================================

commit;

-- =====================================================================================
-- تحقق سريع (اختياري، للتشغيل اليدوي):
--   select count(*) as permissions_count from public.permissions;
--   select count(*) as roles_count       from public.roles;
--   select r.slug, count(*) from public.role_permissions rp
--     join public.roles r on r.id = rp.role_id group by r.slug order by r.slug;
-- =====================================================================================
