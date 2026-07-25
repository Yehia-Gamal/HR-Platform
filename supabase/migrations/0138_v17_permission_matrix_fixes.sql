-- 0138: V17 §2.2.1 — إصلاح مصفوفة الصلاحيات بناءً على تدقيق Wave 3.
-- يعالج 4 مشاكل:
--   1) CRITICAL: دور hr-specialist غير موجود في أي migration (فقط في seed).
--   2) CRITICAL: disputes.admin_action.decide ممنوحة لـ executive-secretary بدلاً من executive (0131).
--   3) MODERATE: performance.cycle.manage ممنوحة للمدير التنفيذي — يجب أن تكون للسكرتير فقط.
--   4) INFO: أكواد صلاحيات وهمية (comms.decision.approve, people.employee.manage, tasks.assign)
--           تُدرج بصمت دون أثر — لا ضرر لكن نوثق.
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) ضمان وجود دور hr-specialist في migrations (مستقل عن seed)
--    الكود يعتمد عليه في: 0013, 0053, 0104, 0109, 0111, 0131, 0132, 0133
-- ─────────────────────────────────────────────────────────────────────────────

insert into public.roles (slug, name_ar, name_en, description, is_system, is_full_access)
values (
  'hr-specialist',
  'أخصائي موارد بشرية',
  'HR Specialist',
  'تنفيذ عمليات الموارد البشرية — الرتبة الثانية بعد مدير HR',
  true,
  false
)
on conflict (slug) do update set
  name_ar     = excluded.name_ar,
  name_en     = excluded.name_en,
  description = excluded.description;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) نقل disputes.admin_action.decide من executive-secretary إلى executive
--    المدير التنفيذي هو صاحب القرار النهائي في الإجراءات الإدارية.
--    الخطأ الأصلي في 0131 سطر 80.
-- ─────────────────────────────────────────────────────────────────────────────

-- حذف المنحة الخاطئة (executive-secretary)
delete from public.role_permissions
where role_id = (select id from public.roles where slug = 'executive-secretary')
  and permission_id = (select id from public.permissions where code = 'disputes.admin_action.decide');

-- منح الصلاحية للمدير التنفيذي
insert into public.role_permissions (role_id, permission_id, scope, requires_reason)
select r.id, p.id, 'organization', true
from public.roles r
join public.permissions p on p.code = 'disputes.admin_action.decide'
where r.slug = 'executive'
on conflict (role_id, permission_id, scope) do nothing;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) سحب performance.cycle.manage من executive
--    إدارة دورات الأداء مسؤولية السكرتير التنفيذي (executive-secretary)،
--    وهي ممنوحة له بالفعل في 0121. المدير التنفيذي يراجع ويعتمد فقط.
-- ─────────────────────────────────────────────────────────────────────────────

delete from public.role_permissions
where role_id = (select id from public.roles where slug = 'executive')
  and permission_id = (select id from public.permissions where code = 'performance.cycle.manage');

-- ─────────────────────────────────────────────────────────────────────────────
-- 4) ربط صلاحيات hr-specialist الأساسية (المُبذورة في seed لكن غير مضمونة)
--    نكرر مجموعة فرعية آمنة — ON CONFLICT DO NOTHING لعدم التكرار.
-- ─────────────────────────────────────────────────────────────────────────────

do $$
declare
  v_role_id uuid;
  v_perm_id uuid;
  v_code text;
  v_codes text[] := array[
    'people.employee.read',
    'people.employee.create',
    'people.employee.update_basic',
    'people.employee.view_contact',
    'people.employee.view_history',
    'people.employee.manage_documents',
    'attendance.record.read',
    'attendance.record.export',
    'attendance.correction.review',
    'requests.request.read',
    'requests.read',
    'requests.leave.balance.read',
    'documents.employee.read',
    'documents.employee.create',
    'documents.employee.update',
    'performance.kpi.read',
    'performance.kpi.hr_review',
    'comms.announcement.read',
    'reports.people.read',
    'organization.org_chart.read'
  ];
begin
  select id into v_role_id from public.roles where slug = 'hr-specialist';
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

-- ─────────────────────────────────────────────────────────────────────────────
-- ملاحظة: أكواد الصلاحيات الوهمية
-- ─────────────────────────────────────────────────────────────────────────────
-- الأكواد التالية مُستخدمة في 0121 لكنها غير موجودة في جدول permissions:
--   • comms.decision.approve (executive) — لا يوجد. الكود الصحيح: comms.decision.manage
--   • people.employee.manage (hr-manager) — لا يوجد. يُغطى بـ create+update_basic+manage_documents
--   • tasks.assign (direct-manager) — لا يوجد. نظام المهام لم يُنفَّذ بعد.
-- هذه الأكواد تُدرج بصمت (الـ loop يتخطى perm_id = null) — لا ضرر فعلي.
-- عند تنفيذ نظام المهام مستقبلاً، يجب إنشاء صلاحية tasks.assign.
