-- Seed 0002: ضمان تسجيل كل أكواد الصلاحيات المستخدمة فعلياً في سياسات RLS/RPCs
-- عبر كل migrations، وربطها بالأدوار. يعالج تباين مساحات الأسماء الناتج عن توليد
-- الملفات بالتوازي (employees.* / documents.* / comms.* / recruitment.* ...).
-- بدون هذا الـseed سترجع has_permission=false لغير full-access فتُحجب البيانات.
-- idempotent: on conflict do nothing/update.

begin;

-- =========================================================
-- 1) إدراج كل الأكواد المستخدمة فعلياً (module/resource/action مشتقة من الكود)
-- =========================================================
with used(code) as (
  select unnest(array[
    -- access / profiles
    'access.role.assign','access.role.create','access.role.remove','access.role.update',
    'profiles.manage','profiles.read',
    -- employees (مساحة الأسماء المستخدمة في 0004 وغيره)
    'employees.read','employees.create','employees.update','employees.delete',
    'people.employee.update_basic','people.employee.update_sensitive',
    -- documents / attachments / assets
    'documents.read','documents.write','documents.manage','documents.policy.publish',
    'attachments.read','attachments.write','assets.read','assets.write',
    -- attendance
    'attendance.record.read','attendance.record.review','attendance.record.process','attendance.record.manual_create',
    'attendance.shift.read','attendance.shift.manage','attendance.shift.assign',
    'attendance.geofence.manage','attendance.identity.read','attendance.identity.manage',
    'attendance.risk.read','attendance.risk.manage','attendance.permit.read','attendance.permit.manage',
    'attendance.exception.read','attendance.exception.manage',
    -- location
    'location.request.manage',
    -- requests
    'requests.read','requests.approve','requests.workflow.manage','requests.leave_type.manage','requests.settings.manage',
    -- performance / kpi
    'performance.kpi.self_assess','performance.kpi.manager_assess','performance.kpi.hr_review',
    'performance.kpi.secretary_review','performance.kpi.executive_review','performance.kpi.finalize',
    'performance.cycle.manage','performance.calibration.manage','performance.calibration.view',
    'performance.competency.assess','performance.competency.manage','performance.competency.self_assess',
    'performance.feedback.manage','performance.goals.manage','performance.goals.own','performance.goals.view',
    'performance.improvement.manage','performance.oneonone.manage',
    -- communications
    'comms.announcement.read','comms.announcement.manage','comms.decision.read','comms.decision.manage',
    'comms.notification.send','comms.notification.admin','comms.recognition.read','comms.recognition.manage',
    'comms.suggestion.read','comms.suggestion.manage','comms.survey.read','comms.survey.manage','comms.survey.results',
    'decisions.read','decisions.write',
    -- disputes
    'disputes.case.manage',
    -- operations / tasks / projects / meetings / risks / incidents / knowledge / tickets
    'tasks.read','tasks.write','projects.read','projects.write','meetings.read','meetings.write',
    'risks.read','risks.write','incidents.read','incidents.write','knowledge.write',
    'tickets.read','tickets.write',
    -- recruitment / onboarding
    'recruitment.requisition.read','recruitment.requisition.manage','recruitment.posting.read','recruitment.posting.manage',
    'recruitment.candidate.read','recruitment.candidate.manage','recruitment.application.read','recruitment.application.manage',
    'recruitment.interview.read','recruitment.interview.manage','recruitment.offer.read','recruitment.offer.manage',
    'recruitment.contract.read','recruitment.contract.manage','recruitment.pipeline.manage',
    'onboarding.journey.read','onboarding.journey.manage','onboarding.provisioning.read','onboarding.provisioning.manage',
    -- reports
    'reports.read','reports.write',
    -- audit / security / system
    'audit.view','audit.log.view','audit.event.view','security.event.view','security.event.manage',
    'settings.read','settings.manage','system.manage','system.feature.manage',
    'system.integration.view','system.integration.manage','system.backup.view','system.backup.manage',
    'system.error.view','system.error.manage',
    -- release / access governance / privacy / integration outbox
    'system.release.read','system.release.manage',
    'access.review.read','access.review.manage',
    'access.break_glass.request','access.break_glass.approve',
    'privacy.request.manage',
    'system.integration.outbox.read','system.integration.outbox.manage',
    -- leave/assignments (مستخدمة في RLS/RPCs بالترحيلات 0026/0060-0066)
    'requests.leave.balance.read','requests.leave.balance.adjust','requests.leave.policy.manage',
    'requests.leave.execute_casual',
    'requests.request.delegate','requests.request.override','requests.request.escalate',
    'assignments.mission.manage','assignments.convoy.manage','assignments.fundraising.manage',
    'assignments.report.review',
    'operations.mission.manage','operations.convoy.manage',
    'performance.kpi.attendance.refresh','performance.kpi.hr_assess','performance.kpi.read'
  ])
)
insert into public.permissions (code, module, resource, action, description)
select
  u.code,
  split_part(u.code, '.', 1) as module,
  case
    when array_length(string_to_array(u.code,'.'),1) >= 3
      then array_to_string((string_to_array(u.code,'.'))[2:array_length(string_to_array(u.code,'.'),1)-1], '.')
    else split_part(u.code,'.',2)
  end as resource,
  reverse(split_part(reverse(u.code), '.', 1)) as action,
  'auto-seeded (used in RLS/RPC)' as description
from used u
on conflict (code) do nothing;

-- =========================================================
-- 2) ربط الصلاحيات بالأدوار حسب البادئة (module) — نطاق منطقي
--    admin مستثنى (full-access). القاعدة:
--    * hr-manager / system-admin / executive-director: نطاق organization لأغلب الوحدات الإدارية.
--    * department-manager: department ، direct-manager: direct_reports.
--    * employee: self لعدد محدود.
-- =========================================================

-- ربط الصلاحيات بالأدوار حسب البادئة داخل كتلة DO ذرية واحدة.
-- ملاحظة: نستخدم DO $$ بدلاً من create function مؤقتة + select، لأن مُشغّل seed في
-- Supabase CLI قد يُنفّذ DDL (create function) وDML (select) في دفعات منفصلة داخل
-- الجلسة نفسها، فلا يرى المُخطِّطُ الدالةَ عند التخطيط ويظهر الخطأ:
--   function public._seed_grant(unknown, text[], unknown) does not exist
-- الكتلة الواحدة idempotent عبر on conflict do nothing.
do $$
declare
  r record;
  v_role uuid;
begin
  for r in
    select * from (values
      -- hr-manager: كل وحدات HR على مستوى المؤسسة
      ('hr-manager', array[
        'employees.','people.employee.','profiles.','documents.','attachments.','attendance.',
        'requests.','performance.','comms.','disputes.','tasks.','reports.','onboarding.',
        'recruitment.','location.','audit.view','privacy.request.manage'], 'organization'),
      -- hr-specialist: تشغيلي على مستوى المؤسسة لكن دون إدارة الأدوار/النظام
      ('hr-specialist', array[
        'employees.read','people.employee.update_basic','documents.read','attendance.record.read',
        'requests.read','requests.approve','onboarding.','recruitment.'], 'organization'),
      -- department-manager: نطاق الإدارة
      ('department-manager', array[
        'employees.read','attendance.record.read','attendance.record.review','requests.read','requests.approve',
        'performance.kpi.manager_assess','performance.goals.view','tasks.','reports.read','comms.decision.read'], 'department'),
      -- direct-manager: التقارير المباشرة
      ('direct-manager', array[
        'employees.read','attendance.record.read','requests.read','requests.approve',
        'performance.kpi.manager_assess','performance.goals.view','tasks.read','tasks.write'], 'direct_reports'),
      -- operations-manager: تشغيل + مهام على مستوى الفريق/الإدارة
      ('operations-manager', array[
        'tasks.','projects.','meetings.','incidents.','risks.','attendance.record.read','requests.approve',
        'location.request.manage'], 'department'),
      -- operations-officer: تشغيل ذاتي محدود
      ('operations-officer', array[
        'tasks.read','tasks.write','projects.read','meetings.read','attendance.record.read'], 'team'),
      -- executive-secretary: متابعة تنفيذية + KPI السكرتير + قرارات/تقارير
      ('executive-secretary', array[
        'performance.kpi.secretary_review','performance.calibration.view','comms.','decisions.',
        'reports.read','requests.read','attendance.record.read','system.release.read','access.review.read'], 'organization'),
      -- executive-director: اعتماد نهائي + تقارير + قرارات على مستوى المؤسسة
      ('executive-director', array[
        'performance.kpi.executive_review','performance.kpi.finalize','comms.decision.manage','decisions.',
        'reports.','requests.approve','location.request.manage','audit.view'], 'organization'),
      -- committee-member / chair: القضايا المسندة
      ('committee-member', array['disputes.case.manage'], 'assigned_cases'),
      ('committee-chair',  array['disputes.case.manage','comms.decision.manage'], 'assigned_cases'),
      -- system-admin: النظام والأمان والتكاملات (لا اعتماد HR/KPI تلقائياً)
      ('system-admin', array[
        'settings.','system.','security.','audit.','access.role.read','access.review.',
        'access.break_glass.request','privacy.request.manage'], 'organization'),
      -- employee: ذاتي فقط
      ('employee', array[
        'attendance.record.read','attendance.permit.read','requests.read',
        'performance.kpi.self_assess','performance.goals.own','performance.competency.self_assess',
        'documents.read','comms.announcement.read','comms.decision.read','tasks.read','tickets.read','tickets.write'], 'self')
    ) as t(role_slug, prefixes, scope)
  loop
    select id into v_role from public.roles where slug = r.role_slug;
    if v_role is null then continue; end if;
    insert into public.role_permissions (role_id, permission_id, scope)
    select v_role, p.id, r.scope
    from public.permissions p
    where exists (select 1 from unnest(r.prefixes) pre where p.code like pre || '%')
    on conflict (role_id, permission_id, scope) do nothing;
  end loop;
end $$;

commit;

-- ملاحظة: هذا الـseed مكمّل لـ0001. شغّلهما بالترتيب بعد db push.
-- Super Admin الأولي يُنشأ عبر auth.admin (service_role) ثم rpc_assign_role إلى دور admin.
