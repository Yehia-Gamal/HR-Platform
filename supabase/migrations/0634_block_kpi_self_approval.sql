-- ═══════════════════════════════════════════════════════════════════════════
-- 0634: منع اعتماد الذات في تقييم الأداء — حتى لأصحاب full-access
-- ═══════════════════════════════════════════════════════════════════════════
-- المشكلة: kpi_can_approve (0476) كانت =
--   current_is_full_access() OR current_employee_id = kpi_resolve_approver(...)
-- أي أن صاحب الصلاحية الكاملة يعتمد تقييمه بنفسه بتجاوز سلسلة
--   مدير مباشر ← HR ← السكرتير التنفيذي.
-- القرار (المستخدم، 2026-10): غير مقصود → يُمنع، ويُحَال تلقائياً لموافق
-- السلسلة. إن لم يوجد موافق بديل فالتقييم يبقى بانتظار إضافة موافق —
-- الممتنع عن اعتماد ذاته خيار مقصود لا يُدارَع.
--
-- يؤثر في: advance_kpi_stage (خطوة المدير) + return_kpi_stage +
-- editableStage في get_kpi_evaluation_form — كلها عبر الدالة نفسها،
-- فالحماية مركزية للويب والموبايل معاً.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create or replace function public.kpi_can_approve(p_evaluation public.kpi_evaluations)
returns boolean
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  -- 0634: لا يعتمد الموظف تقييمه بنفسه — مهما كانت صلاحياته.
  if public.current_employee_id() is not null
     and public.current_employee_id() = p_evaluation.employee_id then
    return false;
  end if;
  return coalesce(
    public.current_is_full_access()
    or public.current_employee_id() =
       public.kpi_resolve_approver_for_employee(p_evaluation.employee_id),
    false
  );
end;
$$;

comment on function public.kpi_can_approve(public.kpi_evaluations) is
  '0634: اعتماد الذات ممنوع للجميع (بما فيهم full-access)؛ الموافق يُحسم عبر سلسلة kpi_resolve_approver_for_employee (مدير ← HR ← سكرتير).';

commit;
