-- 0438: أدوات الإجازات والتكليفات — إنشاء إجازة بدل الموظف + منح بدل راحة جماعي
--
-- الخلفية: صفحة الويب الجديدة «أدوات الإجازات والتكليفات» تحتاج ثلاثة أسطح RPC:
--   1) get_leave_types_admin()          — سرد أنواع الإجازات النشطة لملء النماذج.
--   2) admin_create_leave_request(...)  — إنشاء طلب إجازة نيابةً عن موظف (HR/التنفيذي)
--        بدون تسجيل الدخول كالموظف: يسير في مسار الموافقة المعتاد (مدير مباشر ثم
--        عمليات 1 أبو عمار) عبر _submit_request_for، مع إنشاء صف leave_requests
--        لتفعيل حجز الرصيد (نفس سلوك submit_my_request) وتنفيذ العارضة فورياً.
--   3) grant_weekly_rest_credit_bulk(...) — منح رصيد بدل الراحة الأسبوعي لعدة
--        موظفين دفعة واحدة (نفس قواعد/بوابة النسخة الفردية 0429، idempotent
--        عبر source_key لكل يوم).
--
-- البوابة: full access أو requests.leave.balance.adjust — مطابقة لـ
-- grant_weekly_rest_credit (0429) وadjust_leave_balance (0026).

begin;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1) get_leave_types_admin — كتالوج أنواع الإجازات النشطة للويب
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function public.get_leave_types_admin()
returns table (
  id                 uuid,
  code               text,
  name_ar            text,
  is_paid            boolean,
  requires_attachment boolean,
  max_days_per_year  integer,
  affects_balance    boolean,
  color              text
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select lt.id, lt.code, lt.name_ar, lt.is_paid, lt.requires_attachment,
         lt.max_days_per_year, lt.affects_balance, lt.color
  from public.leave_types lt
  where lt.is_active = true
  order by lt.sort_order, lt.code;
$$;

comment on function public.get_leave_types_admin() is
  'سرد أنواع الإجازات النشطة (كتالوج) لأدوات الإجازات في الويب.';

revoke all on function public.get_leave_types_admin() from public, anon;
grant execute on function public.get_leave_types_admin() to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2) admin_create_leave_request — إنشاء طلب إجازة بدل الموظف
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function public.admin_create_leave_request(
  p_employee_id      uuid,
  p_leave_type       text,
  p_start_date       date,
  p_end_date         date,
  p_reason           text default null,
  p_title            text default null,
  p_handover_notes   text default null,
  p_substitute_employee_id uuid default null
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me                uuid := public.current_employee_id();
  v_manager           uuid;
  v_leave_type_id     uuid;
  v_days              numeric;
  v_payload           jsonb;
  v_row               public.requests;
  v_today             date := (now() at time zone 'Africa/Cairo')::date;
begin
  if v_me is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;

  -- البوابة: full access أو صلاحية ضبط أرصدة الإجازات (مطابقة 0429/0026).
  if not (public.current_is_full_access() or public.has_permission('requests.leave.balance.adjust')) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if p_employee_id is null then
    raise exception 'EMPLOYEE_REQUIRED' using errcode = '22023';
  end if;
  if not exists(
    select 1 from public.employees
    where id = p_employee_id and is_active and not is_deleted
  ) then
    raise exception 'EMPLOYEE_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- توافق خلفي: emergency → casual (نفس submit_my_request 0401).
  if p_leave_type = 'emergency' then p_leave_type := 'casual'; end if;
  if p_leave_type not in ('annual','casual','sick','unpaid','weekly_rest_comp') then
    raise exception 'unsupported leave type' using errcode = '22023';
  end if;

  if p_start_date is null or p_end_date is null then
    raise exception 'leave start and end dates are required' using errcode = '22023';
  end if;
  if p_end_date < p_start_date then
    raise exception 'leave end date cannot precede start date' using errcode = '22023';
  end if;
  if p_start_date < v_today then
    raise exception 'retroactive leave requests are not allowed' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_reason,''))) < 3 then
    raise exception 'reason is required (min 3 chars)' using errcode = '22023';
  end if;

  select id into v_leave_type_id
  from public.leave_types
  where code = p_leave_type and is_active = true;
  if v_leave_type_id is null then
    raise exception 'leave type is inactive or unknown: %', p_leave_type using errcode = '22023';
  end if;

  v_days := (p_end_date - p_start_date) + 1;
  v_payload := jsonb_build_object(
    'leaveType', p_leave_type,
    'startDate', p_start_date,
    'endDate', p_end_date,
    'days', v_days,
    'immediate', (p_leave_type = 'casual'),
    'adminCreated', true,
    'handoverNotes', nullif(p_handover_notes,''),
    'substituteEmployeeId', p_substitute_employee_id);

  -- المدير المسؤول من الهيكل الإداري (مع منع الموافقة الذاتية + توجيه التشغيل).
  v_manager := public.resolve_request_approver(p_employee_id, v_today);

  -- إنشاء الطلب في مسار الموافقة المعتاد (مدير مباشر ثم عمليات 1 أبو عمار).
  v_row := public._submit_request_for(
    p_employee_id,
    'leave',
    null,
    v_manager,
    coalesce(nullif(trim(p_title),''), 'إجازة ' || p_leave_type),
    trim(p_reason),
    v_payload);

  -- إنشاء صف تفصيل الإجازة (يُفعّل حجز الرصيد عبر تريغر 0026).
  insert into public.leave_requests(
    request_id, employee_id, leave_type_id, start_date, end_date,
    days_count, duration_unit, handover_notes, substitute_employee_id, created_by)
  values(
    v_row.id, p_employee_id, v_leave_type_id, p_start_date, p_end_date,
    v_days, 'day',
    nullif(p_handover_notes,''),
    p_substitute_employee_id, auth.uid());

  -- العارضة: تُنفَّذ مباشرة دون موافقة (نفس submit_my_request 0401).
  if p_leave_type = 'casual' then
    update public.requests
      set status = 'approved',
          workflow_status = 'completed',
          decided_at = now(),
          decided_by = v_me,
          updated_at = now()
      where id = v_row.id
      returning * into v_row;

    update public.request_steps
      set status = 'skipped', acted_at = now(), acted_by = v_me,
          comment = 'تنفيذ مباشر للإجازة العارضة دون موافقة', updated_at = now()
      where request_id = v_row.id and status in ('active','pending');

    update public.workflow_instances
      set status = 'completed', completed_at = now(), updated_at = now()
      where request_id = v_row.id and status = 'running';

    insert into public.request_actions(
      request_id, actor_employee_id, action, from_status, to_status, comment, metadata, created_by)
    values(
      v_row.id, v_me, 'system', 'pending', 'approved',
      'تنفيذ مباشر للإجازة العارضة (أنشأها HR بدل الموظف)',
      jsonb_build_object('immediate', true, 'leaveType', 'casual', 'adminCreated', true),
      auth.uid());

    perform public.log_audit_event(
      'leave.casual.immediate', 'workflow', 'info', 'requests', v_row.id,
      'تنفيذ فوري لإجازة عارضة (إنشاء إداري)',
      format('من %s إلى %s', p_start_date, p_end_date),
      jsonb_build_object('days', v_days, 'employeeId', p_employee_id));
  end if;

  perform public.log_audit_event(
    'leave.request.admin_created', 'hr', 'info', 'requests', v_row.id,
    'إنشاء طلب إجازة بدل الموظف',
    coalesce(v_row.title, ''),
    jsonb_build_object(
      'employeeId', p_employee_id,
      'leaveType', p_leave_type,
      'days', v_days,
      'startDate', p_start_date,
      'endDate', p_end_date));

  return v_row;
end $$;

comment on function public.admin_create_leave_request(uuid,text,date,date,text,text,text,uuid) is
  'إنشاء طلب إجازة نيابة عن موظف (HR/التنفيذي): مسار الموافقة المعتاد، العارضة تُنفَّذ فوراً، المرضية بلا حجز رصيد.';

revoke all on function public.admin_create_leave_request(uuid,text,date,date,text,text,text,uuid) from public, anon;
grant execute on function public.admin_create_leave_request(uuid,text,date,date,text,text,text,uuid) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3) grant_weekly_rest_credit_bulk — منح بدل راحة جماعي (عدة موظفين دفعة)
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function public.grant_weekly_rest_credit_bulk(
  p_employee_ids uuid[],
  p_work_date    date,
  p_days         integer default 1
) returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_type_id uuid;
  v_emp     uuid;
  v_year    integer;
  v_day     date;
  v_granted integer := 0;
  v_per_emp integer;
begin
  if not (public.current_is_full_access() or public.has_permission('requests.leave.balance.adjust')) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if p_days < 1 or p_days > 365 then
    raise exception 'INVALID_DAYS' using errcode = '22023';
  end if;
  if p_employee_ids is null or array_length(p_employee_ids, 1) is null then
    raise exception 'at least one employee is required' using errcode = '22023';
  end if;
  if array_length(p_employee_ids, 1) > 500 then
    raise exception 'too many employees (max 500)' using errcode = '22023';
  end if;

  select id into v_type_id
  from public.leave_types
  where code = 'weekly_rest_comp';
  if v_type_id is null then
    raise exception 'LEAVE_TYPE_NOT_FOUND' using errcode = 'P0002';
  end if;

  foreach v_emp in array p_employee_ids loop
    -- نتجاوز الموظفين غير النشطين/المحذوفين بدل فشل الدفعة كاملة.
    if not exists(
      select 1 from public.employees
      where id = v_emp and is_active and not is_deleted
    ) then
      continue;
    end if;

    v_day := p_work_date;
    v_per_emp := 0;
    while v_per_emp < p_days loop
      v_year := extract(year from v_day)::integer;
      perform public.apply_leave_ledger_entry(
        v_emp, v_type_id, v_year, 'credit', 1,
        'weekly-rest:manual:' || v_emp::text || ':' || v_day::text,
        null,
        'منح بدل راحة يدوي عن يوم ' || to_char(v_day, 'YYYY-MM-DD'),
        jsonb_build_object('workDate', v_day::text, 'source', 'manual-grant-bulk'));
      v_per_emp := v_per_emp + 1;
      v_day := v_day + 1;
    end loop;
    v_granted := v_granted + 1;
  end loop;

  return v_granted;
end $$;

comment on function public.grant_weekly_rest_credit_bulk(uuid[],date,integer) is
  'منح رصيد بدل الراحة الأسبوعي لعدة موظفين دفعة واحدة (HR/التنفيذي) — idempotent عبر source_key لكل يوم.';

revoke all on function public.grant_weekly_rest_credit_bulk(uuid[],date,integer) from public, anon;
grant execute on function public.grant_weekly_rest_credit_bulk(uuid[],date,integer) to authenticated;

commit;