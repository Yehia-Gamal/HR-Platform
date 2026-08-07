-- =====================================================================
-- 0303_fix_kpi_inbox_relation_field.sql
-- =====================================================================
-- المشكلة: get_kpi_inbox على الإنتاج لا يحتوي على حقل 'relation' (self/team/review).
-- migration 0204 كان يجب أن يضيفه لكنه لم يُطبَّق على الإنتاج.
-- الموبايل يقسّم التقييمات حسب relation في 3 تبويبات:
--   selfItems = items.where((e) => e.relation == 'self')
--   teamItems = items.where((e) => e.relation == 'team')
--   reviewItems = items.where((e) => e.relation == 'review')
-- بدون الحقل = لا تظهر أي تقييمات في أي تبويب.
--
-- الحل: إعادة تعريف get_kpi_inbox مع حقل relation + order by relation.
-- =====================================================================

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
    select jsonb_agg(item order by (item->>'relation'), (item->>'periodMonth') desc, (item->>'employeeName'))
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
        'version',          e.version,
        'relation',         case
                              when e.employee_id = v_me then 'self'
                              when exists(
                                select 1 from public.manager_relations mr
                                where mr.manager_employee_id = v_me
                                  and mr.employee_id = e.employee_id
                                  and mr.effective_from <= now()
                                  and (mr.effective_to is null or mr.effective_to >= now())
                              ) then 'team'
                              else 'review'
                            end
      ) item
      from public.kpi_evaluations e
      join public.employees       emp on emp.id = e.employee_id
      join public.kpi_cycles      c   on c.id  = e.cycle_id
      where c.status in ('open','locked')
        and (
          v_is_full
          or e.employee_id = v_me
          or public.current_is_hr_reviewer()
          or public.current_is_executive_secretary()
          or public.current_has_active_role(array['executive','executive-director'])
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

revoke execute on function public.get_kpi_inbox(integer) from public, anon;
grant  execute on function public.get_kpi_inbox(integer) to authenticated, service_role;

notify pgrst, 'reload schema';

commit;
