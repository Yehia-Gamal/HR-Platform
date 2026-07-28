-- 0197: إضافة تقييمات KPI للموظفين المفعّلين حديثاً (mig 0187)
-- الموظفون الذين كانوا invited وتحولوا لـ active لم يُدرجوا في دورات KPI القائمة.
-- هذه الـ migration تضيفهم في كل دورة open أو draft لم يُدرجوا فيها بعد.

do $$
declare
  v_cycle record;
  v_count int := 0;
begin
  for v_cycle in
    select c.id, c.template_id, c.status
    from public.kpi_cycles c
    where c.status in ('open', 'draft')
  loop
    insert into public.kpi_evaluations(
      employee_id, cycle_id, template_id,
      stage, current_stage, workflow_status, locked
    )
    select
      e.id, v_cycle.id, v_cycle.template_id,
      'self', 'self',
      case when v_cycle.status = 'open'
           then 'OPEN_FOR_SELF_EVALUATION'
           else 'DRAFT' end,
      v_cycle.status <> 'open'
    from public.employees e
    where e.is_active
      and not coalesce(e.is_deleted, false)
      and e.status = 'active'
      -- استثناء التنفيذيين (نفس منطق create_kpi_cycle_admin).
      and not exists (
        select 1
        from public.user_roles ur
        join public.roles r on r.id = ur.role_id
        where ur.user_id = e.user_id
          and r.slug in ('executive', 'executive-director')
          and (ur.effective_from is null or ur.effective_from <= now())
          and (ur.effective_to   is null or ur.effective_to   > now())
      )
    on conflict (employee_id, cycle_id, template_id) do nothing;

    get diagnostics v_count = row_count;
    raise notice 'Cycle %: inserted % new evaluations', v_cycle.id, v_count;
  end loop;
end $$;
