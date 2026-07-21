-- Migration 0097: Activate employee after first login / password change
-- The employee starts with status 'invited' and profile status 'pending'.
-- After changing their password, they should become 'active'.

-- RPC: activate_employee_after_first_login
-- Called from the mobile app after the user successfully changes their password
-- for the first time (via SetPasswordPage).
create or replace function public.activate_employee_after_first_login()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_employee_id uuid;
  v_old_status text;
  v_profile_old_status text;
begin
  if v_user_id is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  -- Find the employee record for this user
  select id, status into v_employee_id, v_old_status
  from public.employees
  where user_id = v_user_id and is_active = true and is_deleted = false;

  if v_employee_id is null then
    -- No employee record — might be a web-only user or already active
    return jsonb_build_object('activated', false, 'reason', 'no_employee_record');
  end if;

  -- If already active, nothing to do
  if v_old_status = 'active' then
    return jsonb_build_object('activated', false, 'reason', 'already_active');
  end if;

  -- Activate employee
  update public.employees
  set status = 'active', updated_at = now()
  where id = v_employee_id;

  -- Activate profile
  update public.profiles
  set status = 'active', updated_at = now()
  where id = v_user_id;

  -- Log the activation
  perform public.log_audit_event(
    'employee.activated',
    'onboarding',
    'info',
    'employees',
    v_employee_id,
    'تفعيل الموظف بعد أول دخول وتغيير كلمة المرور',
    null,
    jsonb_build_object('old_status', v_old_status, 'new_status', 'active')
  );

  return jsonb_build_object(
    'activated', true,
    'employeeId', v_employee_id,
    'oldStatus', v_old_status
  );
end;
$$;

revoke all on function public.activate_employee_after_first_login() from public;
grant execute on function public.activate_employee_after_first_login() to authenticated;

comment on function public.activate_employee_after_first_login() is
  'Activates employee and profile after first login/password change. Safe to call multiple times (idempotent).';
