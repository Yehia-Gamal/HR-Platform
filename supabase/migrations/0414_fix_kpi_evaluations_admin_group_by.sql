-- ============================================================================
-- 0414: إصلاح get_employee_kpi_evaluations_admin — خطأ GROUP BY و LIMIT
-- ============================================================================
-- المشكلة: استعلام الدالة يضع ORDER BY kc.period_month / LIMIT على مستوى
-- الاستعلام الرئيسي، بينما قائمة SELECT عبارة عن تجميع jsonb_agg بدون
-- GROUP BY (مجموعة واحدة ضمنية). ونتيجةً لذلك يرفع PostgreSQL:
--   ERROR: column "kc.period_month" must appear in the GROUP BY clause
--          or be used in an aggregate function  (SQLSTATE 42803)
-- عند تنفيذ الدالة (تخطيط الاستعلام الداخلي)، فيُجهض المعاملة (transaction)
-- ويُسقط باقي اختبارات الـ pgTAP في ملف 0412. كما أن LIMIT على مستوى
-- الاستعلام يقصّ صف المخرج الواحد (عديم الأثر) بدلاً من قصّ صفوف الدخل.
--
-- الحل: نقل ترتيب period_month desc + LIMIT إلى استعلام فرعي يغذّي
-- jsonb_agg — وهو النموذج المعتمد في get_employee_published_decisions_admin
-- (migration 0412 نفسه، الأسطر 202-214). تُطبّق الدالة الترتيب/التحديد على
-- صفوف الدخل، ثم تجمّعها في jsonb واحد — دون أي GROUP BY ظاهر.
-- الناتج (أسماء المفاتيح وقيمها) مطابق تماماً للسلوك الأصلي والمتوقع في
-- اختبارات 0412 (periodMonth / currentStage / workflowStatus / cycleStatus
-- / finalScore / finalRating / managerComment / hrComment / locked / updatedAt).
-- حارس الصلاحية (raise 'ERR_FORBIDDEN' errcode '42501') دون تغيير.
-- ============================================================================

create or replace function public.get_employee_kpi_evaluations_admin(
  p_employee_id uuid,
  p_limit integer default 60
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  if not (
    public.has_permission('people.employee.read')
    or public.can_access_employee(p_employee_id)
  ) then
    raise exception 'ERR_FORBIDDEN' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id,
    'periodMonth', s.period_month,
    'currentStage', s.current_stage,
    'workflowStatus', s.workflow_status,
    'cycleStatus', s.cycle_status,
    'finalScore', s.final_score,
    'finalRating', s.final_rating,
    'managerComment', s.manager_comment,
    'hrComment', s.hr_comment,
    'locked', s.locked,
    'updatedAt', s.updated_at
  ) order by s.period_month desc), '[]'::jsonb)
  into v_result
  from (
    select ke.id,
           kc.period_month,
           ke.current_stage,
           ke.workflow_status,
           kc.status as cycle_status,
           ke.final_score,
           ke.final_rating,
           ke.manager_comment,
           ke.hr_comment,
           ke.locked,
           ke.updated_at
    from public.kpi_evaluations ke
    join public.kpi_cycles kc on kc.id = ke.cycle_id
    where ke.employee_id = p_employee_id
    order by kc.period_month desc
    limit greatest(1, least(coalesce(p_limit, 60), 240))
  ) s;

  return v_result;
end;
$$;

-- إعادة تأكيد الأذونات (لا تغيير عن الأصل: anon ممنوع، authenticated مسموح)
revoke execute on function public.get_employee_kpi_evaluations_admin(uuid, integer) from public, anon;
grant execute on function public.get_employee_kpi_evaluations_admin(uuid, integer) to authenticated;
