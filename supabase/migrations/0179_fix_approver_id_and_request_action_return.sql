-- 0177: إصلاح ثلاث مشاكل تمنع اختبارات pgTAP من النجاح:
--   1) tg_adjust_escalation_deadline يشير إلى approver_id غير موجود → assignee_employee_id
--   2) request_actions_action_check لا يشمل 'return' → إضافته
--   3) إشعار اعتماد/رفض الجهاز مفقود → trigger جديد على employee_devices

begin;

-- ═══════════════════════════════════════════════════════════════════════
-- 1. إصلاح tg_adjust_escalation_deadline: approver_id → assignee_employee_id
-- ═══════════════════════════════════════════════════════════════════════

create or replace function public.tg_adjust_escalation_deadline()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_hours int;
  v_manager_id uuid;
begin
  -- فقط لطلبات الإجازة التي لها خطوة موافقة (step_order >= 1)
  if new.request_type = 'leave' and new.current_step_order >= 1 then
    -- جلب المدير المسؤول عن الخطوة الحالية
    select assignee_employee_id into v_manager_id
    from public.request_steps
    where request_id = new.id
      and step_order = new.current_step_order
    limit 1;

    if v_manager_id is not null then
      v_hours := public.get_escalation_hours(v_manager_id);
      new.decision_due_at := now() + (v_hours || ' hours')::interval;
    end if;
  end if;

  return new;
end;
$$;

-- ═══════════════════════════════════════════════════════════════════════
-- 2. إضافة 'return' إلى request_actions_action_check
-- ═══════════════════════════════════════════════════════════════════════

alter table public.request_actions
  drop constraint if exists request_actions_action_check;

alter table public.request_actions
  add constraint request_actions_action_check
  check (action in (
    'submit','approve','reject','return',
    'request_changes','comment','escalate',
    'reassign','cancel','withdraw','expire','system'
  ));

-- ═══════════════════════════════════════════════════════════════════════
-- 3. إشعار الموظف عند اعتماد/رفض الجهاز (trigger على employee_devices)
-- ═══════════════════════════════════════════════════════════════════════

create or replace function public.tg_device_approval_notify()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- فقط عند تغيير الحالة من pending/blocked إلى active أو blocked
  if old.status in ('pending','blocked')
     and new.status in ('active','blocked')
     and old.status is distinct from new.status then

    perform public.notify_employee(
      new.employee_id,
      case new.status
        when 'active'  then 'تم اعتماد جهازك'
        else 'تم رفض جهازك'
      end,
      case new.status
        when 'active'  then 'تم اعتماد جهاز ' || coalesce(new.device_name, 'غير معروف')
        else 'تم رفض جهاز ' || coalesce(new.device_name, 'غير معروف') ||
             coalesce(': ' || new.rejection_reason, '')
      end,
      'device',
      case new.status when 'active' then 'normal' else 'high' end,
      'device',
      new.id,
      jsonb_build_object(
        'kind', case new.status when 'active' then 'device_approved' else 'device_rejected' end,
        'deviceId', new.id,
        'deviceName', new.device_name
      )
    );
  end if;

  return new;
end;
$$;

-- إنشاء الـ trigger فقط إذا لم يكن موجوداً
do $$
begin
  if not exists (
    select 1 from pg_trigger
    where tgname = 'trg_device_approval_notify'
      and tgrelid = 'public.employee_devices'::regclass
  ) then
    create trigger trg_device_approval_notify
      after update on public.employee_devices
      for each row
      execute function public.tg_device_approval_notify();
  end if;
end $$;

commit;
