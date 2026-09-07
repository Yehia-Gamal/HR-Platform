-- ═══════════════════════════════════════════════════════════════════════════
-- 0502: تفعيل الحساب فوراً عند تعيين كلمة المرور وإزالة علامة must_change_password
-- ═══════════════════════════════════════════════════════════════════════════
-- يضمن فتح الحساب مباشرة للموظف عند تعيين كلمة المرور له من الإدارة
-- وإزالة أي علامات إجبار تغيير كلمة المرور العالقة.

create or replace function public.admin_activate_employee_after_password_set(p_employee_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid;
  v_employee_status_before text;
  v_profile_status_before text;
begin
  if p_employee_id is null then
    raise exception 'employee_id_required' using errcode = '22023';
  end if;

  select e.status, e.user_id
    into v_employee_status_before, v_user_id
  from public.employees e
  where e.id = p_employee_id and e.is_deleted = false
  limit 1;

  if v_user_id is null then
    raise exception 'employee_not_found' using errcode = 'P0002';
  end if;

  select p.status into v_profile_status_before
  from public.profiles p
  where p.id = v_user_id
  limit 1;

  -- تفعيل الموظف وضمان حالة active
  if v_employee_status_before in ('invited', 'onboarding', 'draft') then
    update public.employees
    set    status     = 'active',
           is_active  = true,
           updated_at = now()
    where  id = p_employee_id
      and  is_deleted = false;
  else
    update public.employees
    set    is_active  = true,
           updated_at = now()
    where  id = p_employee_id
      and  is_deleted = false;
  end if;

  -- تفعيل الملف الشخصي وإلغاء كلمة المرور المؤقتة
  update public.profiles
  set    status             = 'active',
         temporary_password = false,
         updated_at         = now()
  where  id = v_user_id;

  -- إزالة علامة must_change_password من app_metadata لفتح الحساب فوراً للموظف
  update auth.users
  set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) - 'must_change_password'
  where id = v_user_id;

  -- نسجّل الحدث في سجل التدقيق
  perform public.log_audit_event(
    'employee.password_set_activated',
    'security',
    'info',
    'employees',
    p_employee_id,
    'تفعيل حساب بعد تعيين كلمة مرور يدوياً من الإدارة وتصفير إجبار التغيير',
    null,
    jsonb_build_object(
      'employee_status_before', v_employee_status_before,
      'profile_status_before',  v_profile_status_before,
      'employee_id', p_employee_id
    )
  );

  return jsonb_build_object(
    'activated', true,
    'employee_status_before', v_employee_status_before,
    'profile_status_before', v_profile_status_before
  );
end;
$$;

comment on function public.admin_activate_employee_after_password_set(uuid) is
  '0502: تفعيل حساب الموظف فوراً وإزالة علامة must_change_password عند تعيين كلمة المرور من الإدارة.';

revoke all on function public.admin_activate_employee_after_password_set(uuid) from public, anon;
grant execute on function public.admin_activate_employee_after_password_set(uuid) to authenticated, service_role;

-- إزالة علامة must_change_password العالقة من كافة حسابات المستخدمين في auth.users
update auth.users
set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) - 'must_change_password'
where raw_app_meta_data ? 'must_change_password';
