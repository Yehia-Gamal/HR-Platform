-- 0282: تحصين hard_delete_employee_guarded.
-- 1) عقد التأكيد المزدوج: يقبل كود الموظف أو النص الثابت «حذف» (متطابق مع واجهة الإدارة).
-- 2) منع حذف مدير/قائد فريق لديه مرؤوسون نشطون (manager_has_direct_reports).
-- 3) قائمة تحقق تاريخية شاملة + تحويل أي FK حارس إلى رسالة الأرشفة بدلاً من خطأ خام.
-- 4) تسجيل كل محاولات الحذف الفاشلة في audit_events.

create or replace function public.hard_delete_employee_guarded(p_employee_id uuid,p_confirmation_code text,p_reason text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_employee public.employees%rowtype;
begin
  -- 1) الحذف النهائي محصور على مدير النظام الأساسي فقط.
  if not public.current_is_full_access() then raise exception 'main_admin_required' using errcode='42501'; end if;
  -- 2) منع حذف الحساب الحالي.
  if p_employee_id=public.current_employee_id() then raise exception 'self_delete_not_allowed' using errcode='42501'; end if;
  -- 3) سبب الحذف مطلوب (١٠ أحرف على الأقل بعد إزالة الفراغات).
  if length(trim(coalesce(p_reason,'')))<10 then raise exception 'delete_reason_required' using errcode='22023'; end if;
  -- 4) التحقق من وجود الموظف مع قفل الصف لمنع سباقات الحذف.
  select * into v_employee from public.employees where id=p_employee_id for update;
  if v_employee.id is null then raise exception 'employee_not_found' using errcode='P0002'; end if;
  -- 5) عقد التأكيد المزدوج: كود الموظف أو «حذف».
  if p_confirmation_code is distinct from v_employee.employee_code
     and p_confirmation_code is distinct from 'حذف'
  then raise exception 'delete_confirmation_mismatch' using errcode='22023'; end if;
  -- 6) منع حذف مدير/قائد فريق لديه مرؤوسون نشطون — أعد إسنادهم أولاً.
  if exists (select 1 from public.employees d where d.manager_id=p_employee_id and d.is_active=true)
     or exists (select 1 from public.teams t where t.lead_id=p_employee_id and t.is_active=true)
  then raise exception 'manager_has_direct_reports' using errcode='55000'; end if;
  -- 7) قائمة تحقق تاريخية شاملة: أي أثر تاريخي يمنع الحذف النهائي ويوجب الأرشفة.
  --    (الشبكة الأمنية لكل السجلات الأخرى: مُعالَجة في خطوة 9 عبر تحويل FK إلى نفس الرسالة.)
  if exists (select 1 from public.profiles where employee_id=p_employee_id)
     or exists (select 1 from public.attendance_events where employee_id=p_employee_id)
     or exists (select 1 from public.attendance_daily where employee_id=p_employee_id)
     or exists (select 1 from public.requests where employee_id=p_employee_id)
     or exists (select 1 from public.leave_requests where employee_id=p_employee_id)
     or exists (select 1 from public.leave_balance_accounts where employee_id=p_employee_id)
     or exists (select 1 from public.leave_ledger_entries where employee_id=p_employee_id)
     or exists (select 1 from public.missions where employee_id=p_employee_id)
     or exists (select 1 from public.convoy_requests where employee_id=p_employee_id)
     or exists (select 1 from public.kpi_evaluations where employee_id=p_employee_id)
     or exists (select 1 from public.monthly_evaluations where employee_id=p_employee_id)
     or exists (select 1 from public.goal_objectives where employee_id=p_employee_id)
     or exists (select 1 from public.employee_competency_assessments where employee_id=p_employee_id)
     or exists (select 1 from public.improvement_plans where employee_id=p_employee_id)
     or exists (select 1 from public.one_on_ones where employee_id=p_employee_id)
     or exists (select 1 from public.documents where owner_employee_id=p_employee_id)
     or exists (select 1 from public.announcement_acknowledgements where employee_id=p_employee_id)
     or exists (select 1 from public.committee_members where employee_id=p_employee_id)
     or exists (select 1 from public.employee_devices where employee_id=p_employee_id)
     or exists (select 1 from public.passkey_credentials where employee_id=p_employee_id)
     or exists (select 1 from public.employee_locations where employee_id=p_employee_id)
     or exists (select 1 from public.audit_events where employee_id=p_employee_id)
  then raise exception 'employee_history_requires_archive' using errcode='55000'; end if;
  -- 8) تسجيل إذن الحذف قبل التنفيذ.
  perform public.log_audit_event('employee.permanent_delete_approved','security','critical','employees',p_employee_id,trim(p_reason),row_to_json(v_employee)::text,jsonb_build_object('confirmationCode',coalesce(p_confirmation_code,'')));
  -- 9) الحذف الفعلي: أي FK حارس غير مشمول بالقائمة أعلاه يُحوَّل إلى رسالة الأرشفة.
  begin
    delete from public.employees where id=p_employee_id;
  exception when foreign_key_violation then
    raise exception 'employee_history_requires_archive' using errcode='55000';
  end;
  return jsonb_build_object('ok',true,'employeeId',p_employee_id,'deleted',true);
exception when others then
  begin
    perform public.log_audit_event('employee.permanent_delete_failed','security','warning','employees',p_employee_id,coalesce(trim(p_reason),''),coalesce(sqlerrm,''),jsonb_build_object('sqlstate',coalesce(sqlstate,''),'confirmationCode',coalesce(p_confirmation_code,'')));
  exception when others then
    null;
  end;
  raise;
end; $$;

revoke all on function public.hard_delete_employee_guarded(uuid,text,text) from public,anon;
grant execute on function public.hard_delete_employee_guarded(uuid,text,text) to authenticated;

drop policy if exists employees_delete on public.employees;
revoke delete on public.employees from authenticated;
