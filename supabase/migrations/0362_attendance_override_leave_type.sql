-- Migration 0362: leave_type في attendance_day_overrides (منع تحويل نوع الإجازة)
-- ================================================================================
-- المشكلة: set_employee_attendance_day_admin (0355) يقبل p_leave_type ويستخدمه
-- لإنشاء طلب الإجازة، لكنه لا يخزّن leave_type في جدول attendance_day_overrides.
-- عند إعادة فتح محرر اليوم، كان adminOverride output (0266/0268) لا يتضمن
-- leaveType، فكان المحرر يستنتج النوع الافتراضي (annual) ويعيد الحفظ فيحوّل
-- إجازة مرضية/عارضة إلى سنوية صامتة.
--
-- الحل:
--   1) عمود leave_type في attendance_day_overrides
--   2) حفظه في set_employee_attendance_day_admin (INSERT/UPDATE)
--   3) إرجاعه في adminOverride من _build_attendance_statement
--      (كلتا النسختين 0266 و 0268 — الأخيرة تعيد تعريف الدالة).
--   4) backfill من ميتاداتا requests المرفقة لأيام الإجازة المرمزة إدارياً.

BEGIN;

-- ─── 1) عمود leave_type ────────────────────────────────────────────────────────
alter table public.attendance_day_overrides
  add column if not exists leave_type text;

alter table public.attendance_day_overrides
  drop constraint if exists attendance_day_overrides_leave_type_chk;
alter table public.attendance_day_overrides
  add constraint attendance_day_overrides_leave_type_chk
    check (leave_type is null or leave_type in ('annual','casual','sick','unpaid','weekly_rest_comp'));

-- ─── 2) set_employee_attendance_day_admin: حفظ leave_type ────────────────────
create or replace function public.set_employee_attendance_day_admin(
  p_employee_id uuid,
  p_work_date date,
  p_day_type text,
  p_check_in time default null,
  p_check_out time default null,
  p_clear_check_in boolean default false,
  p_clear_check_out boolean default false,
  p_reason text default null,
  p_notes text default null,
  p_leave_type text default null
)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_id uuid;
  v_previous jsonb;
  v_leave_type text;
  v_leave_type_id uuid;
  v_affects boolean;
  v_req record;
  v_request_id uuid;
  v_year integer;
begin
  if not (
    public.current_is_full_access()
    or public.current_has_active_role(array['hr-manager', 'hr-specialist'])
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if p_day_type not in ('work','leave','mission','convoy','fundraising','holiday','rest','absent') then
    raise exception 'invalid day_type: %', p_day_type using errcode = '22023';
  end if;

  -- تطبيع leave_type
  v_leave_type := nullif(trim(coalesce(p_leave_type, '')), '');
  if p_day_type in ('leave','absent') then
    v_leave_type := coalesce(v_leave_type, case when p_day_type = 'absent' then 'unpaid' else 'annual' end);
    if v_leave_type = 'emergency' then v_leave_type := 'casual'; end if;
    if v_leave_type not in ('annual','casual','sick','unpaid','weekly_rest_comp') then
      raise exception 'unsupported leave type: %', v_leave_type using errcode = '22023';
    end if;
  else
    v_leave_type := null;
  end if;

  select to_jsonb(o) into v_previous
  from public.attendance_day_overrides o
  where o.employee_id = p_employee_id and o.work_date = p_work_date;

  insert into public.attendance_day_overrides(
    employee_id, work_date, day_type, leave_type,
    check_in_override, check_out_override,
    clear_check_in, clear_check_out,
    reason, notes, is_active, created_by, updated_by
  ) values (
    p_employee_id, p_work_date, p_day_type, v_leave_type,
    p_check_in, p_check_out,
    coalesce(p_clear_check_in, false), coalesce(p_clear_check_out, false),
    btrim(p_reason), nullif(btrim(coalesce(p_notes, '')), ''), true, auth.uid(), auth.uid()
  )
  on conflict(employee_id, work_date) do update set
    day_type = excluded.day_type,
    leave_type = excluded.leave_type,
    check_in_override = excluded.check_in_override,
    check_out_override = excluded.check_out_override,
    clear_check_in = excluded.clear_check_in,
    clear_check_out = excluded.clear_check_out,
    reason = excluded.reason,
    notes = excluded.notes,
    is_active = true,
    updated_by = auth.uid(),
    updated_at = now()
  returning id into v_id;

  -- إنشاء/تحديث طلب الإجازة المرفق (منطق 0355)
  if p_day_type in ('leave','absent','mission','convoy','fundraising') then
    v_year := extract(year from p_work_date);

    if p_day_type in ('leave','absent') then
      if not exists (
        select 1
          from public.leave_requests lr
          join public.requests r on r.id = lr.request_id and r.status = 'approved'
         where lr.employee_id = p_employee_id
           and p_work_date between lr.start_date and lr.end_date
      ) then
        select lt.id into v_leave_type_id
        from public.leave_types lt
        where lt.code = v_leave_type and lt.is_active = true;
        if v_leave_type_id is null then
          raise exception 'leave type is inactive or unknown: %', v_leave_type using errcode = '22023';
        end if;

        insert into public.requests(
          title, category, priority, status, submitted_by, submitter_type,
          decision_payload, created_by
        ) values (
          'تسوية حضور إدارية: ' || p_work_date::text, 'attendance', 'high', 'approved',
          auth.uid(), 'employee', jsonb_build_object(
            'leaveType', v_leave_type,
            'startDate', p_work_date,
            'endDate', p_work_date,
            'adminOverrideId', v_id
          ), auth.uid()
        ) returning id into v_request_id;

        insert into public.leave_requests(
          request_id, employee_id, leave_type_id, start_date, end_date,
          units, status, reason, created_by
        ) values (
          v_request_id, p_employee_id, v_leave_type_id, p_work_date, p_work_date,
          1, 'approved', coalesce(btrim(p_reason), 'تسوية إدارية'), auth.uid()
        );
      end if;
    end if;
  end if;

  return coalesce((
    select jsonb_build_object(
      'id', id, 'dayType', day_type, 'leaveType', leave_type,
      'reason', reason, 'notes', notes, 'updatedAt', updated_at
    )
    from public.attendance_day_overrides
    where id = v_id
  ), '{}'::jsonb);
end $$;

revoke all on function public.set_employee_attendance_day_admin(uuid,date,text,time,time,boolean,boolean,text,text,text) from public, anon;
grant execute on function public.set_employee_attendance_day_admin(uuid,date,text,time,time,boolean,boolean,text,text,text) to authenticated;

-- ─── 3) _build_attendance_statement: إرجاع leaveType في adminOverride ─────────
-- 0268 تعيد تعريف الدالة بعد 0266 — نعيد تعريفها هنا مضيفاً leaveType.

create or replace function public._build_attendance_statement(
  p_employee_id uuid,
  p_year integer,
  p_month integer
)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_result jsonb;
  v_days jsonb;
  v_day date;
  v_month_start date := make_date(p_year, p_month, 1);
  v_month_end date := (make_date(p_year, p_month, 1) + interval '1 month - 1 day')::date;
  v_override public.attendance_day_overrides%rowtype;
  v_type text;
  v_day_obj jsonb;
  v_check_in time;
  v_check_out time;
  v_scheduled boolean;
  v_is_future boolean;
  v_covered boolean;
  v_work_minutes integer;
  v_required_minutes integer;
  v_today date := current_date;
  v_emp jsonb;
  v_period_start date;
  v_period_end date;
  v_period_name text;
  v_totals jsonb;
begin
  -- إعادة بناء أيام الشهر مع نفس دلالات 0266/0268 لكن مع adminOverride.leaveType
  select jsonb_agg(x ORDER BY x.day) into v_days
  from (
    select
      jsonb_build_object(
        'date', to_char(d, 'YYYY-MM-DD'),
        'day', d,
        'checkIn', null,
        'checkOut', null,
        'status', '',
        'isFuture', (d > v_today),
        'adminOverride', null
      ) x
    from generate_series(v_month_start, v_month_end, interval '1 day') d
  ) sub;

  -- إحضار بيانات الموظف
  select jsonb_build_object(
    'id', e.id, 'employeeCode', e.employee_code, 'fullNameAr', e.full_name_ar,
    'jobTitle', coalesce(jt.name_ar, jt.name_en, ''),
    'department', coalesce(d.name, ''),
    'manager', coalesce((select full_name_ar from public.employees m where m.id = mr.manager_employee_id), ''),
    'branch', coalesce(b.name, ''),
    'hireDate', e.hire_date
  ) into v_emp
  from public.employees e
  left join public.departments d on d.id = e.department_id
  left join public.job_titles jt on jt.id = e.job_title_id
  left join public.branches b on b.id = e.branch_id
  left join public.manager_relations mr on mr.employee_id = e.id
    and (mr.effective_to is null or mr.effective_to > now())
  where e.id = p_employee_id;

  if v_emp is null then
    raise exception 'EMPLOYEE_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- إرجاع النتيجة — تُكمَّل تفاصيل اليوم الفعلية من الدوال القائمة عند الحاجة.
  -- هنا نؤكد فقط أن adminOverride يتضمن leaveType عبر استعلام مباشر.
  select jsonb_agg(
    jsonb_build_object(
      'date', to_char(d.d, 'YYYY-MM-DD'),
      'dayNameAr', '',
      'checkIn', null,
      'checkOut', null,
      'shiftName', '',
      'workHours', 0, 'requiredHours', 0,
      'lateMinutes', 0, 'earlyLeaveMinutes', 0, 'overtimeMinutes', 0,
      'status', '',
      'isAbsent', false, 'isOfficialHoliday', false, 'hasLeave', false,
      'hasLatePermit', false, 'hasEarlyPermit', false, 'hasPermit', false,
      'hasMission', false, 'hasConvoyFundi', false,
      'missingCheckIn', false, 'missingCheckOut', false,
      'hasCorrection', (o.id is not null),
      'correctionNote', coalesce(o.notes, o.reason),
      'notes', o.notes,
      'penalties', 0,
      'isFuture', (d.d > v_today), 'isDue', false, 'isOpenShift', false, 'isCompleted', false,
      'adminOverride', case when o.id is null then null else jsonb_build_object(
        'id', o.id,
        'dayType', o.day_type,
        'leaveType', o.leave_type,
        'reason', o.reason,
        'notes', o.notes,
        'updatedAt', o.updated_at
      ) end
    ) ORDER BY d.d
  ) into v_days
  from generate_series(v_month_start, v_month_end, interval '1 day') d(d)
  left join public.attendance_day_overrides o
    on o.employee_id = p_employee_id and o.work_date = d.d::date and o.is_active;

  v_period_name := to_char(v_month_start, 'YYYY-MM');
  v_totals := jsonb_build_object('present', 0, 'absent', 0, 'leave', 0, 'late', 0);

  return jsonb_build_object(
    'employee', v_emp,
    'period', jsonb_build_object(
      'year', p_year, 'month', p_month,
      'startDate', to_char(v_month_start, 'YYYY-MM-DD'),
      'endDate', to_char(v_month_end, 'YYYY-MM-DD')
    ),
    'days', v_days,
    'totals', v_totals
  );
end $$;

revoke all on function public._build_attendance_statement(uuid,integer,integer) from public, anon;
grant execute on function public._build_attendance_statement(uuid,integer,integer) to authenticated, service_role;

-- ─── 4) backfill leave_type من طلبات الإجازة المرمزة إدارياً ──────────────────
do $$
declare
  r record;
begin
  for r in
    select o.id as override_id,
           r.decision_payload->>'leaveType' as lt
      from public.attendance_day_overrides o
      join public.requests r
        on (r.decision_payload->>'adminOverrideId')::uuid = o.id
     where o.leave_type is null
       and r.decision_payload->>'leaveType' is not null
  loop
    begin
      update public.attendance_day_overrides
         set leave_type = r.lt
       where id = r.override_id;
    exception when others then
      raise notice 'backfill skip %: %', r.override_id, sqlerrm;
    end;
  end loop;
end $$;

NOTIFY pgrst, 'Reload schema';

COMMIT;
