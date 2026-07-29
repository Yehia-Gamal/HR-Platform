-- ─────────────────────────────────────────────────────────────────────────────
-- 0204 — إصلاح get_kpi_inbox: المدير يرى فقط فريقه وليس الجميع
--
-- المشكلة: migration 0166 استبدلت النسخة scope-aware من 0101 بنسخة مبسّطة
--   تستخدم has_any_permission('performance.kpi.read') بدون فحص scope.
--   دور direct-manager يملك performance.kpi.read بنطاق 'direct_reports'
--   لكن has_any_permission لا تفحص scope → المدير يرى KPI الجميع.
--
-- الحل: إعادة الفحص scope-aware مع الحفاظ على حقول V23.
-- ─────────────────────────────────────────────────────────────────────────────
begin;

create or replace function public.get_kpi_inbox(p_limit integer default 100)
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_me        uuid;
  v_is_full   boolean;
  v_limit     int := greatest(1, least(coalesce(p_limit, 100), 500));
begin
  v_me      := public.current_employee_id();
  v_is_full := public.current_is_full_access();

  return coalesce((
    select jsonb_agg(item order by (item->>'periodMonth') desc, (item->>'employeeName'))
    from (
      select jsonb_build_object(
        'id',               e.id,
        'employeeId',       e.employee_id,
        'employeeName',     emp.full_name_ar,
        'employeeCode',     emp.employee_code,
        'employeePhotoUrl', emp.photo_url,
        'periodMonth',      c.period_month,
        'currentStage',     e.current_stage,
        'workflowStatus',   e.workflow_status,
        'finalScore',       e.final_score,
        'finalRating',      e.final_rating,
        'hrCompleted',      e.hr_completed,
        'managerCompleted', e.manager_completed,
        'parallelFlow',     coalesce(c.use_parallel_flow, false),
        'version',          e.version
      ) item
      from public.kpi_evaluations e
      join public.employees       emp on emp.id = e.employee_id
      join public.kpi_cycles      c   on c.id  = e.cycle_id
      where c.status in ('open','locked')
        and (
          ---------------------------------------------------------------
          -- 1. Full-access (admin): see everything
          ---------------------------------------------------------------
          v_is_full

          ---------------------------------------------------------------
          -- 2. Self: own evaluations
          ---------------------------------------------------------------
          or e.employee_id = v_me

          ---------------------------------------------------------------
          -- 3. HR reviewer (hr-manager / hr-specialist): see everything
          ---------------------------------------------------------------
          or public.current_is_hr_reviewer()

          ---------------------------------------------------------------
          -- 4. Executive secretary: see everything
          ---------------------------------------------------------------
          or public.current_is_executive_secretary()

          ---------------------------------------------------------------
          -- 5. Executive / executive-director: see everything
          ---------------------------------------------------------------
          or public.current_has_active_role(array['executive','executive-director'])

          ---------------------------------------------------------------
          -- 6. Organization-scope permission: see everything
          ---------------------------------------------------------------
          or exists (
            select 1
            from public.user_roles ur
            join public.role_permissions rp on rp.role_id = ur.role_id
            join public.permissions      p  on p.id       = rp.permission_id
            where ur.user_id = auth.uid()
              and p.code in ('performance.kpi.read','performance.kpi.report.read',
                             'performance.kpi.manager_assess','performance.kpi.hr_review')
              and rp.scope = 'organization'
              and (ur.effective_from is null or ur.effective_from <= now())
              and (ur.effective_to   is null or ur.effective_to   > now())
          )

          ---------------------------------------------------------------
          -- 7. Direct-reports scope: see only direct reports
          ---------------------------------------------------------------
          or (
            exists (
              select 1
              from public.user_roles ur
              join public.role_permissions rp on rp.role_id = ur.role_id
              join public.permissions      p  on p.id       = rp.permission_id
              where ur.user_id = auth.uid()
                and p.code in ('performance.kpi.read','performance.kpi.manager_assess')
                and rp.scope = 'direct_reports'
                and (ur.effective_from is null or ur.effective_from <= now())
                and (ur.effective_to   is null or ur.effective_to   > now())
            )
            and exists (
              select 1 from public.manager_relations mr
              where mr.manager_employee_id = v_me
                and mr.employee_id         = e.employee_id
                and mr.effective_from     <= now()
                and (mr.effective_to is null or mr.effective_to >= now())
            )
          )

          ---------------------------------------------------------------
          -- 8. Management-descendants scope: see subtree
          ---------------------------------------------------------------
          or (
            exists (
              select 1
              from public.user_roles ur
              join public.role_permissions rp on rp.role_id = ur.role_id
              join public.permissions      p  on p.id       = rp.permission_id
              where ur.user_id = auth.uid()
                and p.code in ('performance.kpi.read','performance.kpi.manager_assess')
                and rp.scope = 'management_descendants'
                and (ur.effective_from is null or ur.effective_from <= now())
                and (ur.effective_to   is null or ur.effective_to   > now())
            )
            and public.is_management_descendant(v_me, e.employee_id)
          )

          ---------------------------------------------------------------
          -- 9. Department scope: see same department
          ---------------------------------------------------------------
          or (
            exists (
              select 1
              from public.user_roles ur
              join public.role_permissions rp on rp.role_id = ur.role_id
              join public.permissions      p  on p.id       = rp.permission_id
              where ur.user_id = auth.uid()
                and p.code in ('performance.kpi.read','performance.kpi.manager_assess')
                and rp.scope = 'department'
                and (ur.effective_from is null or ur.effective_from <= now())
                and (ur.effective_to   is null or ur.effective_to   > now())
            )
            and emp.department_id = (
              select e2.department_id from public.employees e2 where e2.id = v_me
            )
          )
        )
      order by c.period_month desc, emp.full_name_ar
      limit v_limit
    ) q
  ), '[]'::jsonb);
end;
$$;

-- تأكد من الصلاحيات
revoke execute on function public.get_kpi_inbox(integer) from public, anon;
grant  execute on function public.get_kpi_inbox(integer) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- إصلاح kpi_can_read_evaluation — نفس المشكلة
--
-- has_any_permission(...'performance.kpi.read'...) لا تفحص scope
-- المدير يملك performance.kpi.read بنطاق direct_reports لكن has_any_permission
-- تعيد true بدون فحص → يستطيع فتح أي تقييم KPI.
--
-- الحل: استبدال performance.kpi.read في has_any_permission
--        بـ can_access_employee التي تفحص scope
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.kpi_can_read_evaluation(p_evaluation_id uuid)
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
 select exists(
  select 1 from public.kpi_evaluations e where e.id=p_evaluation_id and (
   public.current_is_full_access()
   or e.employee_id=public.current_employee_id()
   or public.can_access_employee(e.employee_id,'performance.kpi.manager_assess')
   or public.can_access_employee(e.employee_id,'performance.kpi.read')
   or public.has_any_permission(array[
       'performance.kpi.hr_review','performance.kpi.hr_assess',
       'performance.kpi.secretary_review','performance.kpi.executive_review',
       'performance.kpi.finalize'
     ])
  )
 );
$$;

revoke execute on function public.kpi_can_read_evaluation(uuid) from public, anon;
grant  execute on function public.kpi_can_read_evaluation(uuid) to authenticated, service_role;

commit;
