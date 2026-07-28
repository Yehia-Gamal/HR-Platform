-- 0170: Fix notification triggers from 0160 — three bugs:
-- 1) trg_fn_role_assignment_notify: column is name_ar, not name
-- 2) All three triggers: created_by fallback '00000000-...' violates FK
--    Fix: use the row's own user reference instead of a nonexistent sentinel

-- ── 1. Device pending trigger ──────────────────────────────────────────
create or replace function public.trg_fn_device_pending_notify_admins()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_admin record;
  v_emp_name text;
begin
  if NEW.status <> 'pending' then
    return NEW;
  end if;

  select full_name_ar into v_emp_name
  from public.employees where id = NEW.employee_id;

  for v_admin in
    select e.id as employee_id, p.id as user_id
    from public.user_roles ur
    join public.roles r on r.id = ur.role_id and r.is_full_access = true
    join public.profiles p on p.id = ur.user_id and p.status = 'active'
    join public.employees e on e.id = p.employee_id and e.is_active = true
  loop
    insert into public.notifications(
      recipient_user_id, recipient_employee_id, title, body,
      category, priority, entity_type, entity_id, metadata, created_by
    ) values (
      v_admin.user_id, v_admin.employee_id,
      'جهاز جديد بانتظار الموافقة',
      'الموظف ' || coalesce(v_emp_name, 'غير معروف') || ' سجّل جهازاً جديداً (' || coalesce(NEW.device_name, 'جهاز') || ') وينتظر موافقتك.',
      'system', 'normal',
      'employee_device', NEW.id,
      jsonb_build_object('kind', 'device_pending_approval', 'employeeId', NEW.employee_id, 'deviceName', NEW.device_name),
      NEW.user_id
    );
  end loop;

  return NEW;
end;
$$;

-- ── 2. Holiday broadcast trigger ───────────────────────────────────────
create or replace function public.trg_fn_public_holiday_broadcast()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_emp record;
begin
  if NEW.is_active is not true then
    return NEW;
  end if;

  for v_emp in
    select e.id as employee_id, p.id as user_id
    from public.employees e
    join public.profiles p on p.employee_id = e.id and p.status = 'active'
    where e.is_active = true and e.status = 'active'
  loop
    insert into public.notifications(
      recipient_user_id, recipient_employee_id, title, body,
      category, priority, entity_type, entity_id, metadata, created_by
    ) values (
      v_emp.user_id, v_emp.employee_id,
      'عطلة رسمية: ' || NEW.name,
      'تم الإعلان عن عطلة رسمية «' || NEW.name || '» بتاريخ ' || NEW.holiday_date::text || '.',
      'announcement', 'normal',
      'public_holiday', NEW.id,
      jsonb_build_object('kind', 'public_holiday_announced', 'holidayName', NEW.name, 'holidayDate', NEW.holiday_date),
      coalesce(NEW.created_by, v_emp.user_id)
    );
  end loop;

  return NEW;
end;
$$;

-- ── 3. Role assignment trigger (name→name_ar + FK fix) ─────────────────
create or replace function public.trg_fn_role_assignment_notify()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_employee_id uuid;
  v_role_name text;
  v_user_id uuid;
begin
  if TG_OP = 'INSERT' then
    v_user_id := NEW.user_id;
    select name_ar into v_role_name from public.roles where id = NEW.role_id;

    select p.employee_id into v_employee_id
    from public.profiles p where p.id = v_user_id and p.status = 'active';

    if v_employee_id is not null then
      insert into public.notifications(
        recipient_user_id, recipient_employee_id, title, body,
        category, priority, entity_type, entity_id, metadata, created_by
      ) values (
        v_user_id, v_employee_id,
        'تم منحك دوراً جديداً',
        'تم منحك دور «' || coalesce(v_role_name, 'غير معروف') || '» في النظام.',
        'system', 'normal',
        'role', NEW.role_id,
        jsonb_build_object('kind', 'role_granted', 'roleName', v_role_name, 'roleId', NEW.role_id),
        coalesce(auth.uid(), v_user_id)
      );
    end if;

  elsif TG_OP = 'DELETE' then
    v_user_id := OLD.user_id;
    select name_ar into v_role_name from public.roles where id = OLD.role_id;

    select p.employee_id into v_employee_id
    from public.profiles p where p.id = v_user_id and p.status = 'active';

    if v_employee_id is not null then
      insert into public.notifications(
        recipient_user_id, recipient_employee_id, title, body,
        category, priority, entity_type, entity_id, metadata, created_by
      ) values (
        v_user_id, v_employee_id,
        'تم سحب دور منك',
        'تم سحب دور «' || coalesce(v_role_name, 'غير معروف') || '» من حسابك.',
        'system', 'normal',
        'role', OLD.role_id,
        jsonb_build_object('kind', 'role_revoked', 'roleName', v_role_name, 'roleId', OLD.role_id),
        coalesce(auth.uid(), v_user_id)
      );
    end if;
  end if;

  return coalesce(NEW, OLD);
end;
$$;
