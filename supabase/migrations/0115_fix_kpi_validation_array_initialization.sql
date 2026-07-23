-- Keep KPI validation errors as a typed array.  The previous text literal
-- relied on an assignment cast and is flagged by plpgsql_check on production.

create or replace function public.get_kpi_validation_errors(p_evaluation_id uuid)
returns text[]
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_eval public.kpi_evaluations;
  v_errors text[] := array[]::text[];
  v_total numeric;
begin
  select *
  into strict v_eval
  from public.kpi_evaluations
  where id = p_evaluation_id;

  if exists(
    select 1
    from public.kpi_criteria c
    where c.template_id = v_eval.template_id
      and public.kpi_effective_score(v_eval.id, c.id) is null
  ) then
    v_errors := array_append(v_errors, 'لم تكتمل درجات البنود السبعة.');
  end if;

  if not exists(
    select 1
    from public.kpi_scores s
    join public.kpi_criteria c on c.id = s.criterion_id
    where s.evaluation_id = v_eval.id
      and s.reviewer_stage = 'self'
    group by s.evaluation_id
    having count(distinct s.criterion_id) = 7
  ) then
    v_errors := array_append(v_errors, 'التقييم الذاتي للبنود السبعة غير مكتمل.');
  end if;

  if not exists(
    select 1
    from public.kpi_attendance_snapshots a
    where a.evaluation_id = p_evaluation_id
  ) or exists(
    select 1
    from public.kpi_attendance_snapshots a
    where a.evaluation_id = p_evaluation_id
      and a.has_pending_items
  ) then
    v_errors := array_append(v_errors, 'بيانات الحضور غير محسوبة أو ما زالت معلقة.');
  end if;

  if (
    select count(*)
    from public.kpi_compliance_records
    where evaluation_id = p_evaluation_id
      and metric in ('PRAYER', 'HALAQA')
  ) <> 2 then
    v_errors := array_append(v_errors, 'يجب على HR استكمال الصلاة والحلقة.');
  end if;

  if nullif(trim(coalesce(v_eval.manager_comment, '')), '') is null then
    v_errors := array_append(v_errors, 'ملاحظة المدير مطلوبة قبل الاعتماد النهائي.');
  end if;

  v_total := public.kpi_total_score(p_evaluation_id);
  if v_total < 0 or v_total > 100 then
    v_errors := array_append(v_errors, 'المجموع النهائي يجب أن يكون بين صفر و100.');
  end if;

  return v_errors;
end;
$$;

revoke execute on function public.get_kpi_validation_errors(uuid) from public;
grant execute on function public.get_kpi_validation_errors(uuid) to authenticated;
