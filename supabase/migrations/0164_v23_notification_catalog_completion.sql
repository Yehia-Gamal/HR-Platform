-- 0160: V23 §8 — Notification catalog completion.
-- Covers: device approval/rejection/pending, official holidays broadcast,
-- dispute status changes, role assignment/revocation notifications.
-- Also adds notifications table to Supabase Realtime publication.
-- Idempotent: CREATE OR REPLACE + DROP TRIGGER IF EXISTS.

begin;

-- =====================================================================
-- 1) approve_device — إضافة إشعارات للموظف عند الموافقة أو الرفض
-- =====================================================================
create or replace function public.approve_device(
  p_device_id uuid,
  p_approved boolean,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_device public.employee_devices;
begin
  if not public.current_is_full_access() then
    raise exception 'insufficient permissions' using errcode = '42501';
  end if;

  select * into v_device
  from public.employee_devices
  where id = p_device_id;

  if v_device is null then
    raise exception 'device not found' using errcode = 'P0002';
  end if;

  if v_device.status not in ('pending', 'blocked') then
    raise exception 'device is not in a reviewable state (current: %)', v_device.status
      using errcode = '22023';
  end if;

  if p_approved then
    update public.employee_devices
    set status = 'replaced',
        revoked_at = now(),
        metadata = metadata || jsonb_build_object('replacedByApproval', p_device_id)
    where employee_id = v_device.employee_id
      and id <> p_device_id
      and status = 'active';

    update public.employee_devices
    set status = 'active',
        approved_by = auth.uid(),
        approved_at = now(),
        rejection_reason = null,
        revoked_at = null
    where id = p_device_id;

    perform public.notify_employee(
      v_device.employee_id,
      'تمت الموافقة على جهازك',
      'تمت الموافقة على تسجيل جهازك «' || coalesce(v_device.device_name, 'جهاز') || '» ويمكنك استخدامه الآن.',
      'system', 'normal',
      'employee_device', p_device_id,
      jsonb_build_object('kind', 'device_approved', 'deviceName', v_device.device_name)
    );
  else
    update public.employee_devices
    set status = 'blocked',
        approved_by = auth.uid(),
        approved_at = now(),
        rejection_reason = coalesce(p_reason, 'رفض إداري')
    where id = p_device_id;

    perform public.notify_employee(
      v_device.employee_id,
      'تم رفض تسجيل جهازك',
      'تم رفض تسجيل جهازك «' || coalesce(v_device.device_name, 'جهاز') || '». السبب: ' || coalesce(p_reason, 'رفض إداري'),
      'system', 'normal',
      'employee_device', p_device_id,
      jsonb_build_object('kind', 'device_rejected', 'deviceName', v_device.device_name, 'reason', coalesce(p_reason, 'رفض إداري'))
    );
  end if;

  perform public.log_security_event(
    case when p_approved then 'device.approved' else 'device.rejected' end,
    'medium', 'allowed',
    v_device.device_identifier_hash,
    jsonb_build_object(
      'deviceId', p_device_id,
      'employeeId', v_device.employee_id,
      'approved', p_approved,
      'reason', p_reason
    )
  );

  return jsonb_build_object('ok', true, 'status', case when p_approved then 'active' else 'blocked' end);
end;
$$;

revoke all on function public.approve_device(uuid, boolean, text) from public, anon, authenticated;
grant execute on function public.approve_device(uuid, boolean, text) to authenticated;

-- =====================================================================
-- 2) Trigger: إشعار المسؤولين عند تسجيل جهاز جديد (pending)
-- =====================================================================
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
      coalesce(NEW.user_id, '00000000-0000-0000-0000-000000000000')
    );
  end loop;

  return NEW;
end;
$$;

drop trigger if exists trg_device_pending_notify_admins on public.employee_devices;
create trigger trg_device_pending_notify_admins
  after insert on public.employee_devices
  for each row
  execute function public.trg_fn_device_pending_notify_admins();

-- =====================================================================
-- 3) Trigger: بث إشعار العطلة الرسمية لجميع الموظفين النشطين
-- =====================================================================
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
      coalesce(NEW.created_by, '00000000-0000-0000-0000-000000000000')
    );
  end loop;

  return NEW;
end;
$$;

drop trigger if exists trg_public_holiday_broadcast on public.public_holidays;
create trigger trg_public_holiday_broadcast
  after insert on public.public_holidays
  for each row
  execute function public.trg_fn_public_holiday_broadcast();

-- =====================================================================
-- 4) Trigger: إشعار أطراف النزاع عند تغيير حالته
-- =====================================================================
create or replace function public.trg_fn_dispute_status_notify()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_status_label text;
  v_recipients uuid[];
  v_eid uuid;
begin
  if OLD.status = NEW.status then
    return NEW;
  end if;

  v_status_label := case NEW.status
    when 'submitted'              then 'مقدّمة'
    when 'under_review'           then 'قيد المراجعة'
    when 'needs_more_information' then 'تحتاج معلومات إضافية'
    when 'accepted'               then 'مقبولة'
    when 'rejected'               then 'مرفوضة'
    when 'waiting_for_respondent' then 'بانتظار المدعى عليه'
    when 'waiting_for_witness'    then 'بانتظار الشاهد'
    when 'session_scheduled'      then 'جلسة مجدولة'
    when 'session_completed'      then 'الجلسة مكتملة'
    when 'committee_deliberation' then 'مداولة اللجنة'
    when 'settlement_pending'     then 'تسوية معلقة'
    when 'escalated_to_executive' then 'مُحالة للمدير التنفيذي'
    when 'decision_issued'        then 'صدر القرار'
    when 'action_proposed'        then 'إجراء مقترح'
    when 'pending_execution'      then 'بانتظار التنفيذ'
    when 'executed'               then 'تم التنفيذ'
    when 'closed'                 then 'مغلقة'
    when 'reopened'               then 'أُعيد فتحها'
    when 'cancelled_by_employee'  then 'ملغاة من الموظف'
    else NEW.status
  end;

  v_recipients := array[]::uuid[];
  if NEW.actor_employee_id is not null then
    v_recipients := v_recipients || NEW.actor_employee_id;
  end if;
  if NEW.respondent_employee_id is not null
     and NEW.respondent_employee_id <> all(v_recipients) then
    v_recipients := v_recipients || NEW.respondent_employee_id;
  end if;
  if NEW.assigned_to is not null
     and NEW.assigned_to <> all(v_recipients) then
    v_recipients := v_recipients || NEW.assigned_to;
  end if;

  foreach v_eid in array v_recipients loop
    perform public.notify_employee(
      v_eid,
      'تحديث حالة النزاع',
      'تم تغيير حالة القضية «' || coalesce(NEW.title, 'نزاع') || '» إلى: ' || v_status_label,
      'dispute', 'normal',
      'dispute_case', NEW.id,
      jsonb_build_object('kind', 'dispute_status_change', 'newStatus', NEW.status, 'statusLabel', v_status_label)
    );
  end loop;

  return NEW;
end;
$$;

drop trigger if exists trg_dispute_status_notify on public.dispute_cases;
create trigger trg_dispute_status_notify
  after update of status on public.dispute_cases
  for each row
  execute function public.trg_fn_dispute_status_notify();

-- =====================================================================
-- 5) Trigger: إشعار الموظف عند منح أو سحب دور
-- =====================================================================
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
    select name into v_role_name from public.roles where id = NEW.role_id;

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
        coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000')
      );
    end if;

  elsif TG_OP = 'DELETE' then
    v_user_id := OLD.user_id;
    select name into v_role_name from public.roles where id = OLD.role_id;

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
        coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000')
      );
    end if;
  end if;

  return coalesce(NEW, OLD);
end;
$$;

drop trigger if exists trg_role_assignment_notify on public.user_roles;
create trigger trg_role_assignment_notify
  after insert or delete on public.user_roles
  for each row
  execute function public.trg_fn_role_assignment_notify();

-- =====================================================================
-- 6) Supabase Realtime: نشر جدول الإشعارات
-- =====================================================================
do $realtime$
begin
  alter publication supabase_realtime add table public.notifications;
exception when duplicate_object then
  null;
end $realtime$;

commit;
