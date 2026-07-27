-- 0160: V23 §8 — Notification catalog completion.
-- Fills notification gaps across: devices, holidays, disputes, role changes.
-- Adds Supabase Realtime publication for the notifications table.
--
-- Components:
--   1. approve_device RPC — adds employee notification on approve/reject
--   2. trg_fn_device_pending_notify_admins — notifies admins on new pending device
--   3. trg_fn_public_holiday_broadcast — broadcasts to all employees on new holiday
--   4. trg_fn_dispute_status_notify — notifies parties on dispute status change
--   5. trg_fn_role_assignment_notify — notifies employee on role grant/revoke
--   6. Realtime publication — notifications table added to supabase_realtime
-- ============================================================================

begin;

-- ─────────────────────────────────────────────────────────────
-- 1) approve_device — إضافة إشعار للموظف عند الموافقة أو الرفض
--    CREATE OR REPLACE — idempotent. الأصل في 0145.
-- ─────────────────────────────────────────────────────────────
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
    -- قبل التفعيل: تعطيل أي جهاز active آخر لنفس الموظف
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

    -- V23: إشعار الموظف بالموافقة على جهازه
    perform public.notify_employee(
      v_device.employee_id,
      'تمت الموافقة على جهازك',
      'تم تفعيل جهازك «' || coalesce(v_device.device_name, 'جهاز') || '» بنجاح.',
      'system', 'normal',
      'employee_device', p_device_id,
      jsonb_build_object('kind', 'device_approved', 'deviceId', p_device_id)
    );
  else
    update public.employee_devices
    set status = 'blocked',
        approved_by = auth.uid(),
        approved_at = now(),
        rejection_reason = coalesce(p_reason, 'رفض إداري')
    where id = p_device_id;

    -- V23: إشعار الموظف برفض جهازه
    perform public.notify_employee(
      v_device.employee_id,
      'تم رفض تسجيل جهازك',
      'تم رفض جهازك «' || coalesce(v_device.device_name, 'جهاز') || '». السبب: ' || coalesce(p_reason, 'رفض إداري'),
      'system', 'normal',
      'employee_device', p_device_id,
      jsonb_build_object('kind', 'device_rejected', 'deviceId', p_device_id, 'reason', coalesce(p_reason, 'رفض إداري'))
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

-- ─────────────────────────────────────────────────────────────
-- 2) إشعار المسؤولين عند تسجيل جهاز جديد بحالة pending
-- ─────────────────────────────────────────────────────────────
create or replace function public.trg_fn_device_pending_notify_admins()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_emp_name text;
begin
  if new.status <> 'pending' then
    return new;
  end if;

  select e.full_name_ar into v_emp_name
  from public.employees e where e.id = new.employee_id;

  -- إشعار جميع المسؤولين (full-access) بوجود جهاز جديد بانتظار الموافقة
  insert into public.notifications(
    recipient_user_id, recipient_employee_id,
    title, body, category, priority,
    entity_type, entity_id, metadata, created_by
  )
  select
    p.id,
    e.id,
    'جهاز جديد بانتظار الموافقة',
    'الموظف «' || coalesce(v_emp_name, '') || '» سجّل جهازاً جديداً بانتظار موافقتك.',
    'system',
    'normal',
    'employee_device',
    new.id,
    jsonb_build_object(
      'kind', 'device_pending_approval',
      'deviceId', new.id,
      'deviceName', coalesce(new.device_name, 'جهاز'),
      'employeeId', new.employee_id
    ),
    coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid)
  from public.user_roles ur
  join public.roles r on r.id = ur.role_id and r.is_full_access = true
  join public.profiles p on p.id = ur.user_id and p.status = 'active'
  join public.employees e on e.id = p.employee_id and e.is_active = true
  where (ur.effective_from is null or ur.effective_from <= now())
    and (ur.effective_to is null or ur.effective_to > now());

  return new;
end;
$$;

drop trigger if exists trg_device_pending_notify_admins on public.employee_devices;
create trigger trg_device_pending_notify_admins
  after insert on public.employee_devices
  for each row
  execute function public.trg_fn_device_pending_notify_admins();

comment on function public.trg_fn_device_pending_notify_admins() is
  'V23 §8: إشعار جميع المسؤولين (full-access) عند تسجيل جهاز جديد بحالة pending.';

-- ─────────────────────────────────────────────────────────────
-- 3) إشعار جماعي عند إضافة عطلة رسمية جديدة
-- ─────────────────────────────────────────────────────────────
create or replace function public.trg_fn_public_holiday_broadcast()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- فقط للعطل الفعّالة
  if new.is_active is distinct from true then
    return new;
  end if;

  insert into public.notifications(
    recipient_user_id, recipient_employee_id,
    title, body, category, priority,
    entity_type, entity_id, metadata, created_by
  )
  select
    p.id,
    e.id,
    'عطلة رسمية جديدة',
    coalesce(new.name, 'عطلة') || ' — ' || to_char(new.holiday_date, 'YYYY-MM-DD'),
    'announcement',
    'normal',
    'public_holiday',
    new.id,
    jsonb_build_object(
      'kind', 'official_holiday',
      'holidayId', new.id,
      'holidayName', coalesce(new.name, ''),
      'holidayDate', new.holiday_date::text
    ),
    coalesce(new.created_by, '00000000-0000-0000-0000-000000000000'::uuid)
  from public.employees e
  join public.profiles p on p.employee_id = e.id
  where e.is_active = true
    and e.is_deleted = false
    and e.status = 'active'
    and e.user_id is not null;

  return new;
end;
$$;

drop trigger if exists trg_public_holiday_broadcast on public.public_holidays;
create trigger trg_public_holiday_broadcast
  after insert on public.public_holidays
  for each row
  execute function public.trg_fn_public_holiday_broadcast();

comment on function public.trg_fn_public_holiday_broadcast() is
  'V23 §8: إشعار جماعي لكل الموظفين النشطين عند إضافة عطلة رسمية جديدة.';

-- ─────────────────────────────────────────────────────────────
-- 4) إشعار أطراف النزاع عند تغيّر الحالة
-- ─────────────────────────────────────────────────────────────
create or replace function public.trg_fn_dispute_status_notify()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_status_label text;
begin
  -- فقط عند تغيّر الحالة
  if old.status is not distinct from new.status then
    return new;
  end if;

  v_status_label := case new.status
    when 'submitted' then 'تم التقديم'
    when 'accepted' then 'مقبولة'
    when 'rejected' then 'مرفوضة'
    when 'under_review' then 'قيد المراجعة'
    when 'session_scheduled' then 'تم جدولة جلسة'
    when 'session_completed' then 'انتهت الجلسة'
    when 'committee_deliberation' then 'قيد المداولة'
    when 'decision_issued' then 'صدر القرار'
    when 'action_proposed' then 'اقتراح إجراء'
    when 'pending_execution' then 'بانتظار التنفيذ'
    when 'executed' then 'تم التنفيذ'
    when 'closed' then 'مغلقة'
    when 'escalated_to_executive' then 'تم التصعيد للمدير التنفيذي'
    when 'reopened' then 'أعيد فتحها'
    when 'cancelled_by_employee' then 'ألغاها الموظف'
    else new.status
  end;

  -- إشعار المدّعي (actor)
  if new.actor_employee_id is not null then
    insert into public.notifications(
      recipient_user_id, recipient_employee_id,
      title, body, category, priority,
      entity_type, entity_id, metadata, created_by
    )
    select p.id, new.actor_employee_id,
      'تحديث حالة النزاع',
      'تم تحديث حالة النزاع «' || coalesce(left(new.title, 60), '') || '» إلى: ' || v_status_label,
      'dispute', 'normal',
      'dispute_case', new.id,
      jsonb_build_object('kind', 'dispute_status_change', 'disputeId', new.id, 'newStatus', new.status),
      coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid)
    from public.profiles p where p.employee_id = new.actor_employee_id;
  end if;

  -- إشعار المدّعى عليه (respondent) — بشرط اختلافه عن المدّعي
  if new.respondent_employee_id is not null
     and new.respondent_employee_id is distinct from new.actor_employee_id then
    insert into public.notifications(
      recipient_user_id, recipient_employee_id,
      title, body, category, priority,
      entity_type, entity_id, metadata, created_by
    )
    select p.id, new.respondent_employee_id,
      'تحديث حالة النزاع',
      'تم تحديث حالة النزاع «' || coalesce(left(new.title, 60), '') || '» إلى: ' || v_status_label,
      'dispute', 'normal',
      'dispute_case', new.id,
      jsonb_build_object('kind', 'dispute_status_change', 'disputeId', new.id, 'newStatus', new.status),
      coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid)
    from public.profiles p where p.employee_id = new.respondent_employee_id;
  end if;

  -- إشعار المكلّف بالتحقيق (assigned_to) — بشرط اختلافه عن الطرفين
  if new.assigned_to is not null
     and new.assigned_to is distinct from new.actor_employee_id
     and new.assigned_to is distinct from new.respondent_employee_id then
    insert into public.notifications(
      recipient_user_id, recipient_employee_id,
      title, body, category, priority,
      entity_type, entity_id, metadata, created_by
    )
    select p.id, new.assigned_to,
      'تحديث حالة النزاع',
      'تم تحديث حالة النزاع «' || coalesce(left(new.title, 60), '') || '» إلى: ' || v_status_label,
      'dispute', 'normal',
      'dispute_case', new.id,
      jsonb_build_object('kind', 'dispute_status_change', 'disputeId', new.id, 'newStatus', new.status),
      coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid)
    from public.profiles p where p.employee_id = new.assigned_to;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_dispute_status_notify on public.dispute_cases;
create trigger trg_dispute_status_notify
  after update of status on public.dispute_cases
  for each row
  execute function public.trg_fn_dispute_status_notify();

comment on function public.trg_fn_dispute_status_notify() is
  'V23 §8: إشعار أطراف النزاع (مدّعي، مدّعى عليه، محقق) عند تغيّر حالة القضية.';

-- ─────────────────────────────────────────────────────────────
-- 5) إشعار الموظف عند منح أو سحب صلاحية
-- ─────────────────────────────────────────────────────────────
create or replace function public.trg_fn_role_assignment_notify()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role_name text;
  v_employee_id uuid;
  v_user_id uuid;
begin
  if tg_op = 'INSERT' then
    select r.name into v_role_name from public.roles r where r.id = new.role_id;
    select p.employee_id into v_employee_id from public.profiles p where p.id = new.user_id;
    v_user_id := new.user_id;

    if v_employee_id is not null then
      insert into public.notifications(
        recipient_user_id, recipient_employee_id,
        title, body, category, priority,
        entity_type, entity_id, metadata, created_by
      ) values (
        v_user_id, v_employee_id,
        'تم منحك صلاحية جديدة',
        'تم منحك دور «' || coalesce(v_role_name, 'غير محدد') || '».',
        'system', 'normal',
        'user_role', new.id,
        jsonb_build_object('kind', 'role_granted', 'roleId', new.role_id, 'roleName', coalesce(v_role_name, '')),
        coalesce(auth.uid(), coalesce(new.granted_by, '00000000-0000-0000-0000-000000000000'::uuid))
      );
    end if;
    return new;

  elsif tg_op = 'DELETE' then
    select r.name into v_role_name from public.roles r where r.id = old.role_id;
    select p.employee_id into v_employee_id from public.profiles p where p.id = old.user_id;
    v_user_id := old.user_id;

    if v_employee_id is not null then
      insert into public.notifications(
        recipient_user_id, recipient_employee_id,
        title, body, category, priority,
        entity_type, entity_id, metadata, created_by
      ) values (
        v_user_id, v_employee_id,
        'تم سحب صلاحية',
        'تم سحب دور «' || coalesce(v_role_name, 'غير محدد') || '» من حسابك.',
        'system', 'normal',
        'user_role', null,
        jsonb_build_object('kind', 'role_revoked', 'roleId', old.role_id, 'roleName', coalesce(v_role_name, '')),
        coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid)
      );
    end if;
    return old;
  end if;

  return null;
end;
$$;

drop trigger if exists trg_role_assignment_notify on public.user_roles;
create trigger trg_role_assignment_notify
  after insert or delete on public.user_roles
  for each row
  execute function public.trg_fn_role_assignment_notify();

comment on function public.trg_fn_role_assignment_notify() is
  'V23 §8: إشعار الموظف عند منح أو سحب دور (صلاحية) من حسابه.';

-- ─────────────────────────────────────────────────────────────
-- 6) إضافة جدول notifications إلى Supabase Realtime
--    آمن: يتجاهل الخطأ إن كان الجدول مضافاً مسبقاً.
-- ─────────────────────────────────────────────────────────────
do $$ begin
  alter publication supabase_realtime add table public.notifications;
exception when duplicate_object then null;
end $$;

commit;
