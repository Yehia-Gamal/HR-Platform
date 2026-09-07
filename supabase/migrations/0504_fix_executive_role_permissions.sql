-- 0504: توحيد صلاحيات المدير التنفيذي (executive + executive-director)
--
-- المشكلة الجذرية:
-- 1. دور `executive` (من 0121) يملك KPI والحضور لكن ينقصه الخلافات والنشر والاعتمادات.
-- 2. دور `executive-director` (من 0059) يملك الخلافات لكن ينقصه KPI والحضور والنشر.
-- 3. كلا الدورين ينقصه `comms.announcement.manage` → يحجب صفحة الإعلانات بالكامل.
-- 4. كلا الدورين ينقصه `disputes.case.transition` → يخفي جميع إجراءات الخلافات.
-- 5. كلا الدورين ينقصه `disputes.admin_action.decide` → يمنع اتخاذ القرار التنفيذي.
--
-- الحل: منح كلتا الدورين الصلاحيات الكاملة اللازمة لتطبيق الموبايل.
-- آمن للتطبيق المتكرر (ON CONFLICT DO NOTHING).

begin;

do $$
declare
  v_exec_role uuid;
  v_exec_dir_role uuid;
  v_perm_id uuid;
  v_code text;
  v_codes text[] := array[
    -- ─── الحضور والتقارير ──────────────────────────────────
    'attendance.record.read',
    'reports.people.read',
    'reports.schedule.manage',
    'reports.executive.read',
    -- ─── KPI ────────────────────────────────────────────────
    'performance.kpi.read',
    'performance.kpi.executive_review',
    'performance.kpi.finalize',
    'performance.kpi.report.read',
    'performance.cycle.manage',
    -- ─── النشر والتواصل ────────────────────────────────────
    'comms.announcement.read',
    'comms.announcement.manage',
    'comms.decision.approve',
    'comms.decision.manage',
    'posts.publish',
    -- ─── الخلافات ──────────────────────────────────────────
    'disputes.portal.access',
    'disputes.case.read_all',
    'disputes.case.transition',
    'disputes.case.escalate',
    'disputes.executive.manage',
    'disputes.admin_action.decide',
    'disputes.appeal.review',
    -- ─── التنبيهات ──────────────────────────────────────────
    'alerts.broadcast.send',
    -- ─── طلبات الموقع ──────────────────────────────────────
    'live_location.request',
    -- ─── الموظفين والتنظيم ─────────────────────────────────
    'people.employee.read',
    'organization.org_chart.read',
    'organization.entity.read',
    -- ─── الطلبات والاعتمادات ───────────────────────────────
    'requests.request.read',
    'requests.request.approve',
    'requests.leave.balance.adjust',
    -- ─── المهام والعمليات ──────────────────────────────────
    'tasks.write',
    'operations.mission.manage',
    'operations.convoy.manage',
    -- ─── مراقبة النظام ──────────────────────────────────────
    'system.release.read'
  ];
begin
  select id into v_exec_role     from public.roles where slug = 'executive';
  select id into v_exec_dir_role from public.roles where slug = 'executive-director';

  -- ─── منح صلاحيات دور `executive` ──────────────────────────
  if v_exec_role is not null then
    foreach v_code in array v_codes loop
      select id into v_perm_id from public.permissions where code = v_code;
      if v_perm_id is not null then
        insert into public.role_permissions (role_id, permission_id, scope)
        values (v_exec_role, v_perm_id, 'organization')
        on conflict (role_id, permission_id, scope) do nothing;
      end if;
    end loop;
  end if;

  -- ─── منح صلاحيات دور `executive-director` ──────────────────
  if v_exec_dir_role is not null then
    foreach v_code in array v_codes loop
      select id into v_perm_id from public.permissions where code = v_code;
      if v_perm_id is not null then
        insert into public.role_permissions (role_id, permission_id, scope)
        values (v_exec_dir_role, v_perm_id, 'organization')
        on conflict (role_id, permission_id, scope) do nothing;
      end if;
    end loop;
  end if;

  raise notice '0504: executive permissions patched (exec=%, exec_dir=%)',
    v_exec_role is not null, v_exec_dir_role is not null;
end;
$$;

commit;
