-- ============================================================================
-- 0496: إعادة بناء submit_discipline_action — استعادة رسالة العقد الإنجليزية
-- ============================================================================
-- إعادة البناء في 0478/0483 تركت رسالة الخطأ العربية «المبلغ مطلوب للخصم
-- من الراتب» بينما عقد الاختبار 0345 (test 22) يتطلب:
--     throws_ok(..., '22023', 'amount is required for salary deduction', ...)
-- هنا يُعاد بناء الدالة كنونياً مع الإبقاء على كل السلوك ماعدا عودة رسالة
-- خطأ المبلغ إلى نص العقد الإنجليزي الأصلي من 0345.
-- ============================================================================

create or replace function public.submit_discipline_action(
  p_employee_id uuid,
  p_action_type text,
  p_title text,
  p_description text,
  p_severity text default 'moderate',
  p_amount numeric default null,
  p_effective_from date default null,
  p_effective_to date default null
)
returns public.employee_discipline_actions
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_row public.employee_discipline_actions;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  if not (public.current_is_full_access() or public.has_permission('relations.discipline.create')) then
    raise exception 'FORBIDDEN: requires relations.discipline.create' using errcode = '42501';
  end if;

  if not exists (select 1 from public.employees where id = p_employee_id and is_deleted = false) then
    raise exception 'employee_not_found' using errcode = 'P0002';
  end if;

  if p_action_type not in ('verbal_warning','written_warning','salary_deduction','suspension','termination') then
    raise exception 'نوع إجراء غير صالح' using errcode = '22023';
  end if;

  if p_action_type = 'salary_deduction' and (p_amount is null or p_amount <= 0) then
    raise exception 'amount is required for salary deduction' using errcode = '22023';
  end if;

  insert into public.employee_discipline_actions(
    employee_id, action_type, title, description, severity, amount,
    effective_from, effective_to, status, created_by)
  values (
    p_employee_id, p_action_type, trim(p_title), trim(p_description), p_severity, p_amount,
    p_effective_from, p_effective_to, 'pending', auth.uid())
  returning * into v_row;

  perform public.log_audit_event(
    'discipline.submitted', 'compliance', 'warning',
    'employee_discipline_actions', v_row.id,
    'إجراء تأديبي جديد بانتظار الاعتماد', null,
    jsonb_build_object('employeeId', p_employee_id, 'actionType', p_action_type));

  perform public.notify_employee(
    p_employee_id,
    'إجراء تأديبي بانتظار المراجعة',
    'تم تسجيل إجراء (' || public.discipline_action_type_label(p_action_type) || ') على ملفك وهو بانتظار الاعتماد.',
    'general', 'normal', null, null, '{}'::jsonb
  );

  return v_row;
end;
$$;

revoke execute on function public.submit_discipline_action(uuid, text, text, text, text, numeric, date, date) from public, anon;
grant  execute on function public.submit_discipline_action(uuid, text, text, text, text, numeric, date, date) to authenticated;