-- =====================================================================
-- 0511: نظام الغرامات الفورية للتأخير (Instant Attendance Penalties)
-- =====================================================================
-- نظام متكامل لفرض غرامات فورية على تأخر الموظفين مع تصعيد تلقائي:
--
--   القواعد:
--     • تأخير ≤ 30 دقيقة  → 20 ج.م
--     • تأخير ≤ 60 دقيقة  → 50 ج.م
--     • تأخير ≤ 120 دقيقة → 150 ج.م
--     • عدم الدفع في نفس اليوم → مضاعفة إلى 500 ج.م
--     • عدم الدفع بعد المضاعفة → تعليق الموظف عن العمل
--
--   المكوّنات:
--     1) جدول instant_attendance_penalties
--     2) generate_instant_penalty — إنشاء غرامة (يدوي أو تلقائي)
--     3) confirm_instant_penalty_payment — HR يؤكد الدفع
--     4) get_instant_penalties — استعلام مع فلاتر
--     5) get_employees_with_pending_instant_penalties — المطالبين بالدفع
--     6) auto_escalate_instant_penalties — كرون: مضاعفة + تعليق
--     7) auto_generate_instant_penalties — كرون: إنشاء تلقائي من الحضور
--     8) lift_instant_penalty_suspension — رفع التعليق يدوياً
--
--   الإشعارات: عند كل حدث يُبلَّغ الموظف + المدير + المدير التنفيذي + HR + الفريق.
--
-- Idempotent: CREATE TABLE IF NOT EXISTS + CREATE OR REPLACE FUNCTION.
-- =====================================================================

begin;

-- ═══════════════════════════════════════════════════════════════════════
-- 1) جدول الغرامات الفورية
-- ═══════════════════════════════════════════════════════════════════════

create table if not exists public.instant_attendance_penalties (
  id                  uuid primary key default gen_random_uuid(),
  employee_id         uuid not null references public.employees(id) on delete cascade,
  work_date           date not null,
  late_minutes        integer not null check (late_minutes > 0),
  original_amount     numeric(12,2) not null check (original_amount > 0),
  current_amount      numeric(12,2) not null check (current_amount > 0),
  currency            text not null default 'EGP',
  status              text not null default 'pending_payment'
                        check (status in ('pending_payment','paid','doubled','suspended')),
  escalation_level    text not null default 'initial'
                        check (escalation_level in ('initial','doubled','suspended')),
  -- الدفع
  paid_at             timestamptz,
  confirmed_by        uuid references public.employees(id),
  -- التعليق
  suspended_at        timestamptz,
  suspension_lifted_at timestamptz,
  suspension_lifted_by uuid references public.employees(id),
  -- تتبع
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  created_by          uuid references auth.users(id),
  notes               text,
  -- منع تكرار: غرامة واحدة لكل موظف/يوم
  constraint uq_instant_penalty_employee_date unique (employee_id, work_date)
);

comment on table public.instant_attendance_penalties is
  'الغرامات الفورية للتأخير: تُنشأ تلقائياً أو يدوياً، مع تصعيد (مضاعفة → تعليق) حتى السداد.';

create index if not exists ix_instant_penalties_employee
  on public.instant_attendance_penalties (employee_id);
create index if not exists ix_instant_penalties_status
  on public.instant_attendance_penalties (status);
create index if not exists ix_instant_penalties_date
  on public.instant_attendance_penalties (work_date desc);
create index if not exists ix_instant_penalties_escalation
  on public.instant_attendance_penalties (escalation_level)
  where status not in ('paid');

alter table public.instant_attendance_penalties enable row level security;

-- updated_at trigger
drop trigger if exists trg_instant_penalties_updated_at on public.instant_attendance_penalties;
create trigger trg_instant_penalties_updated_at before update on public.instant_attendance_penalties
  for each row execute function public.tg_set_updated_at();

-- ═══════════════════════════════════════════════════════════════════════
-- 2) RLS — HR + full-access يديرون؛ الموظف يقرأ سجله فقط
-- ═══════════════════════════════════════════════════════════════════════

drop policy if exists instant_penalties_select on public.instant_attendance_penalties;
create policy instant_penalties_select on public.instant_attendance_penalties
  for select to authenticated
  using (
    employee_id = public.current_employee_id()
    or public.current_is_full_access()
    or public.has_any_permission(array[
      'payroll.run.manage', 'payroll.run.approve', 'people.employee.read'
    ])
  );

drop policy if exists instant_penalties_insert on public.instant_attendance_penalties;
create policy instant_penalties_insert on public.instant_attendance_penalties
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or public.has_any_permission(array['payroll.run.manage', 'payroll.run.approve'])
  );

drop policy if exists instant_penalties_update on public.instant_attendance_penalties;
create policy instant_penalties_update on public.instant_attendance_penalties
  for update to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array['payroll.run.manage', 'payroll.run.approve'])
  )
  with check (
    public.current_is_full_access()
    or public.has_any_permission(array['payroll.run.manage', 'payroll.run.approve'])
  );

-- ═══════════════════════════════════════════════════════════════════════
-- 3) Helper: حساب مبلغ الغرامة من دقائق التأخير
-- ═══════════════════════════════════════════════════════════════════════

create or replace function public.calc_instant_penalty_amount(p_late_minutes integer)
returns numeric(12,2)
language sql immutable strict
as $$
  select case
    when p_late_minutes <= 15  then 0.00   -- فترة سماح 15 دقيقة (10:00 - 10:15) بدون أي خصم
    when p_late_minutes <= 30  then 20.00  -- حتى 10:30 (16-30 دقيقة) = 20 ج.م
    when p_late_minutes <= 60  then 50.00  -- حتى 11:00 (31-60 دقيقة) = 50 ج.م
    when p_late_minutes <= 120 then 150.00 -- حتى 12:00 (61-120 دقيقة) = 150 ج.م
    else 150.00  -- الحد الأقصى الأولي
  end;
$$;

-- ═══════════════════════════════════════════════════════════════════════
-- 4) Helper: إشعار كل المعنيين بحدث غرامة فورية
-- ═══════════════════════════════════════════════════════════════════════

create or replace function public._notify_instant_penalty_stakeholders(
  p_employee_id uuid,
  p_title text,
  p_body text,
  p_entity_type text,
  p_entity_id uuid,
  p_metadata jsonb default '{}'::jsonb
)
returns void
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_mgr_id uuid;
begin
  -- 1) إشعار الموظف نفسه
  perform public.notify_employee(
    p_employee_id, p_title, p_body,
    'system', 'urgent', p_entity_type, p_entity_id, p_metadata
  );

  -- 2) إشعار المدير المباشر
  select mr.manager_employee_id into v_mgr_id
    from public.manager_relations mr
    join public.employees m on m.id = mr.manager_employee_id
   where mr.employee_id = p_employee_id
     and mr.effective_from <= current_date
     and (mr.effective_to is null or mr.effective_to >= current_date)
     and m.is_active = true
   order by case mr.relation_type
              when 'primary' then 1 when 'functional' then 2 else 3
            end
   limit 1;

  if v_mgr_id is not null then
    perform public.notify_employee(
      v_mgr_id, p_title, p_body,
      'system', 'urgent', p_entity_type, p_entity_id, p_metadata
    );
  end if;

  -- 3) إشعار HR + كل المختصين (payroll.run.manage)
  perform public.notify_employees_with_permission(
    'payroll.run.manage', p_title, p_body,
    'system', 'urgent', p_entity_type, p_entity_id, p_metadata,
    p_employee_id  -- استبعاد الموظف نفسه (أُشعر أعلاه)
  );

  -- 4) إشعار المدير التنفيذي (alerts.broadcast.send)
  perform public.notify_employees_with_permission(
    'alerts.broadcast.send', p_title, p_body,
    'system', 'urgent', p_entity_type, p_entity_id, p_metadata,
    p_employee_id
  );
end;
$$;

-- ═══════════════════════════════════════════════════════════════════════
-- 5) RPC: إنشاء غرامة فورية
-- ═══════════════════════════════════════════════════════════════════════

create or replace function public.generate_instant_penalty(
  p_employee_id uuid,
  p_work_date date,
  p_late_minutes integer
)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_amount numeric(12,2);
  v_row public.instant_attendance_penalties;
  v_emp_name text;
begin
  -- التحقق من الصلاحيات (الكرون auth.uid() is null مسموح)
  if auth.uid() is not null
     and not (public.current_is_full_access()
              or public.has_any_permission(array['payroll.run.manage', 'payroll.run.approve', 'attendance.record.manage'])) then
    raise exception 'غير مسموح: تحتاج صلاحية إدارة الغرامات' using errcode = '42501';
  end if;

  -- التحقق من الموظف
  select full_name_ar into v_emp_name
    from public.employees
   where id = p_employee_id and is_deleted = false and is_active = true;

  if v_emp_name is null then
    raise exception 'الموظف غير موجود أو غير نشط' using errcode = 'P0002';
  end if;

  if p_late_minutes is null or p_late_minutes <= 0 then
    raise exception 'دقائق التأخير يجب أن تكون أكبر من صفر' using errcode = '22023';
  end if;

  -- حساب المبلغ
  v_amount := public.calc_instant_penalty_amount(p_late_minutes);

  -- إذا كان التأخير ضمن فترة السماح (15 دقيقة الأولى: 10:00 - 10:15 = 0 ج.م)
  if v_amount <= 0.00 then
    return jsonb_build_object(
      'id', null,
      'alreadyExists', false,
      'isGracePeriod', true,
      'amount', 0,
      'message', 'التأخير ضمن فترة السماح الرسمية (15 دقيقة الأولى: 10:00 - 10:15) — لا توجد غرامة مستحقة'
    );
  end if;

  -- إنشاء الغرامة (مع تجاهل التكرار)
  insert into public.instant_attendance_penalties(
    employee_id, work_date, late_minutes,
    original_amount, current_amount, currency,
    status, escalation_level, created_by
  ) values (
    p_employee_id, p_work_date, p_late_minutes,
    v_amount, v_amount, 'EGP',
    'pending_payment', 'initial', auth.uid()
  )
  on conflict (employee_id, work_date) do nothing
  returning * into v_row;

  -- إذا كانت موجودة مسبقاً
  if v_row.id is null then
    select * into v_row
      from public.instant_attendance_penalties
     where employee_id = p_employee_id and work_date = p_work_date;

    return jsonb_build_object(
      'id', v_row.id,
      'alreadyExists', true,
      'status', v_row.status,
      'currentAmount', v_row.current_amount
    );
  end if;

  -- سجل التدقيق
  perform public.log_audit_event(
    'instant_penalty.issued', 'financial', 'warning',
    'instant_attendance_penalties', v_row.id,
    'غرامة فورية: ' || v_emp_name || ' تأخر ' || p_late_minutes || ' دقيقة — ' || v_amount || ' ج.م',
    null,
    jsonb_build_object(
      'employeeId', p_employee_id,
      'workDate', p_work_date,
      'lateMinutes', p_late_minutes,
      'amount', v_amount
    )
  );

  -- إشعار كل المعنيين
  perform public._notify_instant_penalty_stakeholders(
    p_employee_id,
    '⚠️ غرامة تأخير فورية',
    v_emp_name || ' تأخر ' || p_late_minutes || ' دقيقة يوم ' ||
      to_char(p_work_date, 'YYYY-MM-DD') || ' — غرامة ' || v_amount || ' ج.م مطلوب سدادها اليوم.',
    'instant_penalty',
    v_row.id,
    jsonb_build_object(
      'employeeId', p_employee_id::text,
      'workDate', p_work_date::text,
      'lateMinutes', p_late_minutes,
      'amount', v_amount,
      'channel', 'instant_penalty',
      'deepLink', 'ahlashabab://action/finance?tab=instant-penalties'
    )
  );

  return jsonb_build_object(
    'id', v_row.id,
    'employeeId', v_row.employee_id,
    'workDate', v_row.work_date,
    'lateMinutes', v_row.late_minutes,
    'originalAmount', v_row.original_amount,
    'currentAmount', v_row.current_amount,
    'status', v_row.status,
    'alreadyExists', false
  );
end;
$$;

-- ═══════════════════════════════════════════════════════════════════════
-- 6) RPC: تأكيد الدفع (HR)
-- ═══════════════════════════════════════════════════════════════════════

create or replace function public.confirm_instant_penalty_payment(
  p_penalty_id uuid,
  p_notes text default null
)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_row public.instant_attendance_penalties;
  v_emp_name text;
  v_was_suspended boolean;
begin
  if v_me is null then
    raise exception 'لا يوجد ملف موظف مرتبط بالمستخدم الحالي' using errcode = '42501';
  end if;

  if not (public.current_is_full_access()
          or public.has_any_permission(array['payroll.run.manage', 'payroll.run.approve'])) then
    raise exception 'غير مسموح: تحتاج صلاحية إدارة الرواتب' using errcode = '42501';
  end if;

  select * into v_row
    from public.instant_attendance_penalties
   where id = p_penalty_id;

  if not found then
    raise exception 'الغرامة غير موجودة' using errcode = 'P0002';
  end if;

  if v_row.status = 'paid' then
    raise exception 'الغرامة مدفوعة بالفعل' using errcode = '22023';
  end if;

  v_was_suspended := (v_row.status = 'suspended');

  -- تحديث الحالة
  update public.instant_attendance_penalties
     set status = 'paid',
         paid_at = now(),
         confirmed_by = v_me,
         suspension_lifted_at = case when v_was_suspended then now() else suspension_lifted_at end,
         suspension_lifted_by = case when v_was_suspended then v_me else suspension_lifted_by end,
         notes = coalesce(p_notes, notes),
         updated_at = now()
   where id = p_penalty_id
  returning * into v_row;

  select full_name_ar into v_emp_name
    from public.employees where id = v_row.employee_id;

  -- إذا كان الموظف معلّقاً: فتح السيستم فوراً وإعادته لمباشرة العمل
  if v_was_suspended then
    update public.employees
       set status = 'active',
           is_active = true,
           updated_at = now()
     where id = v_row.employee_id;

    update public.profiles
       set status = 'active',
           updated_at = now()
     where employee_id = v_row.employee_id;
  end if;

  -- سجل التدقيق
  perform public.log_audit_event(
    'instant_penalty.paid', 'financial', 'info',
    'instant_attendance_penalties', v_row.id,
    'تم سداد غرامة فورية وإزالة الخصم: ' || coalesce(v_emp_name, 'موظف') || ' — ' || v_row.current_amount || ' ج.م' ||
      case when v_was_suspended then ' (تم رفع التعليق وفتح السيستم وعودته للعمل)' else '' end,
    null,
    jsonb_build_object(
      'employeeId', v_row.employee_id,
      'amount', v_row.current_amount,
      'wasSuspended', v_was_suspended
    )
  );

  -- إشعار المعنيين بالسداد
  perform public._notify_instant_penalty_stakeholders(
    v_row.employee_id,
    '✅ تم سداد غرامة التأخير وإزالة الخصم',
    coalesce(v_emp_name, 'الموظف') || ' سدد غرامة التأخير بقيمة ' || v_row.current_amount || ' ج.م للـ HR وتمت إزالة الخصم' ||
      case when v_was_suspended then ' — تم فتح السيستم ورفع التعليق وعودته لمباشرة العمل.' else '.' end,
    'instant_penalty',
    v_row.id,
    jsonb_build_object(
      'employeeId', v_row.employee_id::text,
      'amount', v_row.current_amount,
      'wasSuspended', v_was_suspended,
      'channel', 'instant_penalty_paid',
      'deepLink', 'ahlashabab://action/finance?tab=instant-penalties'
    )
  );

  -- إذا كان معلّقاً: إشعار كامل الفريق برفع التعليق وعودته لمباشرة العمل
  if v_was_suspended then
    perform public.notify_employee(
      e.id,
      '✅ عودة زميل لمباشرة العمل',
      'إشعار للفريق: قام ' || coalesce(v_emp_name, 'الموظف') || ' بسداد الغرامة المستحقة للـ HR، وتم رفع التعليق وإعادة فتح حسابه على السيستم وعودته لمباشرة العمل.',
      'system',
      'normal',
      'instant_penalty_reinstated',
      v_row.id,
      jsonb_build_object(
        'employeeId', v_row.employee_id::text,
        'amount', v_row.current_amount,
        'channel', 'team_reinstatement_broadcast'
      )
    )
      from public.employees e
     where e.is_active = true
       and coalesce(e.is_deleted, false) = false
       and e.id <> v_row.employee_id;
  end if;

  return jsonb_build_object(
    'id', v_row.id,
    'status', v_row.status,
    'paidAt', v_row.paid_at,
    'currentAmount', v_row.current_amount,
    'wasSuspended', v_was_suspended
  );
end;
$$;

-- ═══════════════════════════════════════════════════════════════════════
-- 7) RPC: استعلام الغرامات الفورية
-- ═══════════════════════════════════════════════════════════════════════

create or replace function public.get_instant_penalties(
  p_employee_id uuid default null,
  p_status text default null,
  p_date_from date default null,
  p_date_to date default null,
  p_limit integer default 200,
  p_offset integer default 0
)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if not (public.current_is_full_access()
          or public.has_any_permission(array[
            'payroll.run.manage', 'payroll.run.approve', 'people.employee.read'
          ])) then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', p.id,
      'employeeId', p.employee_id,
      'employeeName', e.full_name_ar,
      'employeeCode', e.employee_code,
      'departmentName', d.name,
      'workDate', p.work_date,
      'lateMinutes', p.late_minutes,
      'originalAmount', p.original_amount,
      'currentAmount', p.current_amount,
      'currency', p.currency,
      'status', p.status,
      'escalationLevel', p.escalation_level,
      'paidAt', p.paid_at,
      'confirmedBy', p.confirmed_by,
      'suspendedAt', p.suspended_at,
      'suspensionLiftedAt', p.suspension_lifted_at,
      'notes', p.notes,
      'createdAt', p.created_at
    ) order by p.work_date desc, p.created_at desc)
    from public.instant_attendance_penalties p
    join public.employees e on e.id = p.employee_id
    left join public.departments d on d.id = e.department_id
    where (p_employee_id is null or p.employee_id = p_employee_id)
      and (p_status is null or p.status = p_status)
      and (p_date_from is null or p.work_date >= p_date_from)
      and (p_date_to is null or p.work_date <= p_date_to)
    limit greatest(1, p_limit) offset greatest(0, p_offset)
  ), '[]'::jsonb);
end;
$$;

-- ═══════════════════════════════════════════════════════════════════════
-- 8) RPC: الموظفين المطالبين بالدفع (للشارة البصرية)
-- ═══════════════════════════════════════════════════════════════════════

create or replace function public.get_employees_with_pending_instant_penalties()
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if not (public.current_is_full_access()
          or public.has_any_permission(array[
            'payroll.run.manage', 'payroll.run.approve', 'people.employee.read'
          ])) then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'employeeId', p.employee_id,
      'employeeName', e.full_name_ar,
      'employeeCode', e.employee_code,
      'departmentName', d.name,
      'pendingCount', count(*),
      'totalAmount', sum(p.current_amount),
      'isSuspended', bool_or(p.status = 'suspended'),
      'latestDate', max(p.work_date)
    ) order by bool_or(p.status = 'suspended') desc, sum(p.current_amount) desc)
    from public.instant_attendance_penalties p
    join public.employees e on e.id = p.employee_id
    left join public.departments d on d.id = e.department_id
    where p.status in ('pending_payment', 'doubled', 'suspended')
    group by p.employee_id, e.full_name_ar, e.employee_code, d.name
  ), '[]'::jsonb);
end;
$$;

-- ═══════════════════════════════════════════════════════════════════════
-- 9) RPC: التصعيد التلقائي (كرون يومي)
-- ═══════════════════════════════════════════════════════════════════════

create or replace function public.auto_escalate_instant_penalties()
returns integer
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_today date := ((now() at time zone 'Africa/Cairo')::date);
  v_rec record;
  v_escalated integer := 0;
  v_emp_name text;
begin
  -- الكرون (auth.uid() is null) مسموح. استدعاء يدوي يتطلب صلاحية.
  if auth.uid() is not null
     and not (public.current_is_full_access()
              or public.has_permission('payroll.run.manage')) then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;

  -- ═══ المرحلة 1: مضاعفة الغرامات المتأخرة (pending_payment من أمس فأقدم) ═══
  for v_rec in
    select p.*
      from public.instant_attendance_penalties p
     where p.status = 'pending_payment'
       and p.escalation_level = 'initial'
       and p.work_date < v_today
  loop
    update public.instant_attendance_penalties
       set status = 'doubled',
           escalation_level = 'doubled',
           current_amount = 500.00,
           updated_at = now()
     where id = v_rec.id;

    select full_name_ar into v_emp_name
      from public.employees where id = v_rec.employee_id;

    perform public.log_audit_event(
      'instant_penalty.doubled', 'financial', 'high',
      'instant_attendance_penalties', v_rec.id,
      'مضاعفة غرامة فورية: ' || coalesce(v_emp_name, 'موظف') || ' — 500 ج.م',
      null,
      jsonb_build_object('employeeId', v_rec.employee_id, 'originalAmount', v_rec.original_amount)
    );

    perform public._notify_instant_penalty_stakeholders(
      v_rec.employee_id,
      '🔴 مضاعفة غرامة تأخير — 500 ج.م',
      coalesce(v_emp_name, 'الموظف') || ' لم يسدد غرامة التأخير في الموعد. تمت مضاعفة الغرامة إلى 500 ج.م. يجب السداد فوراً وإلا سيتم تعليقه عن العمل.',
      'instant_penalty_doubled',
      v_rec.id,
      jsonb_build_object(
        'employeeId', v_rec.employee_id::text,
        'originalAmount', v_rec.original_amount,
        'newAmount', 500,
        'channel', 'instant_penalty_doubled',
        'deepLink', 'ahlashabab://action/finance?tab=instant-penalties'
      )
    );

    v_escalated := v_escalated + 1;
  end loop;

  -- ═══ المرحلة 2: اليوم الثالث — غلق السيستم وإيقاف الموظف عن العمل وإشعار كامل الفريق ═══
  for v_rec in
    select p.*
      from public.instant_attendance_penalties p
     where p.status = 'doubled'
       and p.escalation_level = 'doubled'
       and p.work_date < v_today - 1
  loop
    -- 1) تحديث سجل الغرامة
    update public.instant_attendance_penalties
       set status = 'suspended',
           escalation_level = 'suspended',
           suspended_at = now(),
           updated_at = now()
     where id = v_rec.id;

    -- 2) غلق السيستم على الموظف وإيقافه عن العمل
    update public.employees
       set status = 'suspended',
           is_active = false,
           updated_at = now()
     where id = v_rec.employee_id;

    update public.profiles
       set status = 'suspended',
           updated_at = now()
     where employee_id = v_rec.employee_id;

    select full_name_ar into v_emp_name
      from public.employees where id = v_rec.employee_id;

    perform public.log_audit_event(
      'instant_penalty.suspended', 'security', 'critical',
      'instant_attendance_penalties', v_rec.id,
      'غلق السيستم وتعليق موظف عن العمل: ' || coalesce(v_emp_name, 'موظف') || ' — لعدم سداد غرامة 500 ج.م في اليوم الثاني',
      null,
      jsonb_build_object('employeeId', v_rec.employee_id, 'amount', v_rec.current_amount)
    );

    -- 3) إشعار الموظف والمديرين
    perform public._notify_instant_penalty_stakeholders(
      v_rec.employee_id,
      '🚫 إيقاف عن العمل وغلق الحساب',
      'تم إيقافك عن العمل وغلق حسابك على السيستم لعدم سداد غرامة الـ 500 ج.م. يجب التوجه للـ HR وسداد المبلغ لإعادة فتح الحساب ومباشرة العمل.',
      'instant_penalty_suspended',
      v_rec.id,
      jsonb_build_object(
        'employeeId', v_rec.employee_id::text,
        'amount', v_rec.current_amount,
        'channel', 'instant_penalty_suspended',
        'deepLink', 'ahlashabab://action/finance?tab=instant-penalties'
      )
    );

    -- 4) إرسال إشعار فوري لكامل الفريق (كل الموظفين النشطين بالشركة)
    perform public.notify_employee(
      e.id,
      '🚫 إشعار إيقاف موظف عن العمل',
      'إشعار للفريق: تم إيقاف ' || coalesce(v_emp_name, 'أحد الموظفين') || ' عن العمل مؤقتاً وغلق حسابه على السيستم لعدم سداد غرامة التأخير (500 ج.م) حتى يتم السداد للـ HR وإزالة الغرامة وعودته لمباشرة العمل.',
      'system',
      'urgent',
      'instant_penalty_suspended',
      v_rec.id,
      jsonb_build_object(
        'employeeId', v_rec.employee_id::text,
        'suspendedEmployeeName', v_emp_name,
        'amount', 500,
        'channel', 'team_suspension_broadcast'
      )
    )
      from public.employees e
     where e.is_active = true
       and coalesce(e.is_deleted, false) = false
       and e.id <> v_rec.employee_id;

    v_escalated := v_escalated + 1;
  end loop;

  return v_escalated;
exception
  when others then
    perform public.log_audit_event(
      'instant_penalty.escalation_failed', 'operations', 'error',
      'instant_attendance_penalties', null,
      'فشل التصعيد التلقائي للغرامات الفورية', null,
      jsonb_build_object('error', sqlerrm)
    );
    return 0;
end;
$$;

-- ═══════════════════════════════════════════════════════════════════════
-- 10) RPC: إنشاء تلقائي من الحضور اليومي (كرون)
-- ═══════════════════════════════════════════════════════════════════════

create or replace function public.auto_generate_instant_penalties()
returns integer
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_today date := ((now() at time zone 'Africa/Cairo')::date);
  v_isodow integer := extract(isodow from (now() at time zone 'Africa/Cairo'))::integer;
  v_rec record;
  v_generated integer := 0;
begin
  -- الكرون مسموح. استدعاء يدوي يتطلب صلاحية.
  if auth.uid() is not null
     and not (public.current_is_full_access()
              or public.has_permission('attendance.record.manage')) then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;

  -- عطلة الجمعة(5) والسبت(6)
  if v_isodow in (5, 6) then return 0; end if;

  for v_rec in
    select ad.employee_id, ad.late_minutes
      from public.attendance_daily ad
      join public.employees e on e.id = ad.employee_id
     where ad.work_date = v_today
       and ad.status = 'late'
       and coalesce(ad.late_minutes, 0) > 15 -- تجاوز فترة السماح (أكثر من 15 دقيقة تأخير)
       and e.is_active = true
       and e.is_deleted = false
       -- لم تُنشأ له غرامة بعد
       and not exists (
         select 1 from public.instant_attendance_penalties ip
          where ip.employee_id = ad.employee_id
            and ip.work_date = v_today
       )
  loop
    perform public.generate_instant_penalty(
      v_rec.employee_id, v_today, v_rec.late_minutes
    );
    v_generated := v_generated + 1;
  end loop;

  return v_generated;
exception
  when others then
    perform public.log_audit_event(
      'instant_penalty.auto_generate_failed', 'operations', 'error',
      'instant_attendance_penalties', null,
      'فشل الإنشاء التلقائي للغرامات الفورية', null,
      jsonb_build_object('error', sqlerrm, 'workDate', v_today)
    );
    return 0;
end;
$$;

-- ═══════════════════════════════════════════════════════════════════════
-- 11) RPC: رفع التعليق يدوياً (بدون دفع — حالة استثنائية)
-- ═══════════════════════════════════════════════════════════════════════

create or replace function public.lift_instant_penalty_suspension(
  p_penalty_id uuid,
  p_notes text default null
)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_row public.instant_attendance_penalties;
  v_emp_name text;
begin
  if v_me is null then
    raise exception 'لا يوجد ملف موظف مرتبط بالمستخدم الحالي' using errcode = '42501';
  end if;

  if not public.current_is_full_access() then
    raise exception 'غير مسموح: يحتاج صلاحية full-access فقط' using errcode = '42501';
  end if;

  select * into v_row
    from public.instant_attendance_penalties
   where id = p_penalty_id and status = 'suspended';

  if not found then
    raise exception 'الغرامة غير موجودة أو ليست في حالة تعليق' using errcode = 'P0002';
  end if;

  update public.instant_attendance_penalties
     set suspension_lifted_at = now(),
         suspension_lifted_by = v_me,
         notes = coalesce(p_notes, notes),
         updated_at = now()
   where id = p_penalty_id
  returning * into v_row;

  -- إعادة تفعيل الحساب في employees و profiles
  update public.employees
     set status = 'active',
         is_active = true,
         updated_at = now()
   where id = v_row.employee_id;

  update public.profiles
     set status = 'active',
         updated_at = now()
   where employee_id = v_row.employee_id;

  select full_name_ar into v_emp_name
    from public.employees where id = v_row.employee_id;

  perform public.log_audit_event(
    'instant_penalty.suspension_lifted', 'security', 'high',
    'instant_attendance_penalties', v_row.id,
    'رفع تعليق عن موظف وفتح حسابه: ' || coalesce(v_emp_name, 'موظف') || ' (بدون سداد)',
    null,
    jsonb_build_object('employeeId', v_row.employee_id, 'notes', p_notes)
  );

  perform public._notify_instant_penalty_stakeholders(
    v_row.employee_id,
    'تم رفع التعليق وفتح السيستم',
    coalesce(v_emp_name, 'الموظف') || ' تم رفع التعليق عنه وإعادة فتح حسابه لمباشرة العمل.' ||
      case when p_notes is not null then ' (' || p_notes || ')' else '' end,
    'instant_penalty_lifted',
    v_row.id,
    jsonb_build_object(
      'employeeId', v_row.employee_id::text,
      'channel', 'instant_penalty_lifted'
    )
  );

  -- إشعار الفريق
  perform public.notify_employee(
    e.id,
    '✅ عودة زميل لمباشرة العمل',
    'إشعار للفريق: تم رفع التعليق عن ' || coalesce(v_emp_name, 'الموظف') || ' وإعادة فتح حسابه على السيستم وعودته لمباشرة العمل.',
    'system',
    'normal',
    'instant_penalty_reinstated',
    v_row.id,
    jsonb_build_object('employeeId', v_row.employee_id::text, 'channel', 'team_reinstatement_broadcast')
  )
    from public.employees e
   where e.is_active = true
     and coalesce(e.is_deleted, false) = false
     and e.id <> v_row.employee_id;

  return jsonb_build_object(
    'id', v_row.id,
    'status', v_row.status,
    'suspensionLiftedAt', v_row.suspension_lifted_at
  );
end;
$$;

-- ═══════════════════════════════════════════════════════════════════════
-- 12) الصلاحيات والمنح
-- ═══════════════════════════════════════════════════════════════════════

revoke all on function public.calc_instant_penalty_amount(integer) from public, anon;
grant execute on function public.calc_instant_penalty_amount(integer) to authenticated, service_role;

revoke all on function public._notify_instant_penalty_stakeholders(uuid, text, text, text, uuid, jsonb) from public, anon;
grant execute on function public._notify_instant_penalty_stakeholders(uuid, text, text, text, uuid, jsonb) to authenticated, service_role;

revoke all on function public.generate_instant_penalty(uuid, date, integer) from public, anon;
grant execute on function public.generate_instant_penalty(uuid, date, integer) to authenticated, service_role;

revoke all on function public.confirm_instant_penalty_payment(uuid, text) from public, anon;
grant execute on function public.confirm_instant_penalty_payment(uuid, text) to authenticated;

revoke all on function public.get_instant_penalties(uuid, text, date, date, integer, integer) from public, anon;
grant execute on function public.get_instant_penalties(uuid, text, date, date, integer, integer) to authenticated;

revoke all on function public.get_employees_with_pending_instant_penalties() from public, anon;
grant execute on function public.get_employees_with_pending_instant_penalties() to authenticated;

revoke all on function public.auto_escalate_instant_penalties() from public, anon;
grant execute on function public.auto_escalate_instant_penalties() to authenticated, service_role;

revoke all on function public.auto_generate_instant_penalties() from public, anon;
grant execute on function public.auto_generate_instant_penalties() to authenticated, service_role;

revoke all on function public.lift_instant_penalty_suspension(uuid, text) from public, anon;
grant execute on function public.lift_instant_penalty_suspension(uuid, text) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- 13) جدولة الكرون
-- ═══════════════════════════════════════════════════════════════════════

do $cron$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron غير مفعّل — شغّل auto_escalate_instant_penalties و auto_generate_instant_penalties عبر مشغّل خارجي.';
    return;
  end if;

  -- التصعيد التلقائي: يومياً 05:00 UTC ≈ 08:00 القاهرة (بداية اليوم)
  perform cron.unschedule(jobname)
    from cron.job
   where jobname = 'hr_auto_escalate_instant_penalties';

  perform cron.schedule(
    'hr_auto_escalate_instant_penalties', '0 5 * * *',
    $job$ select public.auto_escalate_instant_penalties() $job$
  );

  -- الإنشاء التلقائي: كل 30 دقيقة خلال نافذة الحضور (08:30 إلى 12:00 UTC ≈ 10:30 إلى 14:00 القاهرة)
  perform cron.unschedule(jobname)
    from cron.job
   where jobname = 'hr_auto_generate_instant_penalties';

  perform cron.schedule(
    'hr_auto_generate_instant_penalties', '*/30 8-11 * * *',
    $job$ select public.auto_generate_instant_penalties() $job$
  );

  raise notice 'تمت جدولة كرون الغرامات الفورية: التصعيد 08:00 صباحاً + الإنشاء كل نصف ساعة من 10:30 حتى 14:00 توقيت القاهرة.';
end
$cron$;

notify pgrst, 'reload schema';

commit;
