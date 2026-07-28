-- 0197: إضافة تقييمات KPI للموظفين المفعّلين حديثاً (mig 0187)
-- الذين لم يُدرجوا في الدورات القائمة.
-- يستهدف الدورات بحالة open أو draft فقط — لا يمسّ المغلقة/المؤرشفة.

begin;

insert into public.kpi_evaluations (
  employee_id, cycle_id, template_id,
  stage, current_stage, workflow_status, locked
)
select
  e.id,
  c.id,
  c.template_id,
  'self',
  'self',
  case when c.status = 'open' then 'OPEN_FOR_SELF_EVALUATION' else 'DRAFT' end,
  c.status <> 'open'
from public.employees e
cross join public.kpi_cycles c
where
  -- الموظفون النشطون فقط
  e.is_active
  and not coalesce(e.is_deleted, false)
  and e.status = 'active'
  -- دورات مفتوحة أو مسودة فقط
  and c.status in ('open', 'draft')
  -- استثناء أدوار المدير التنفيذي
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

commit;
