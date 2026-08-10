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
--   2) حفظه في set_employee_attendance_day_admin (INSERT/UPDATE) — نسخ جسم
--      0355 كاملاً مع إضافة leave_type فقط لتفادي انتكاس المنطق.
--   3) إرجاعه في adminOverride من _build_attendance_statement.
--   4) backfill من leave_requests المرتبطة بالأيام المرمزة إدارياً.

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
-- نسخ جسم 0355 كاملاً مع إضافة leave_type إلى INSERT/UPDATE فقط.
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
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
  v_previous jsonb;
  v_month date := date_trunc('month', p_work_date)::date;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_manager uuid;
  v_req public.requests;
  v_leave_type_id uuid;
  v_affects boolean;
  v_leave_type text;
  v_payload jsonb;
begin
  if p_employee_id is null or p_work_date is null then
    raise exception 'EMPLOYEE_AND_DATE_REQUIRED' using errcode = '22023';
  end if;
  if p_day_type not in ('work','leave','mission','convoy','fundraising','holiday','rest','absent') then
    raise exception 'INVALID_DAY_TYPE' using errcode = '22023';
  end if;
  if length(btrim(coalesce(p_reason, ''))) < 5 then
    raise exception 'REASON_REQUIRED' using errcode = '22023';
  end if;
  if p_clear_check_in and p_check_in is not null then
    raise exception 'CHECK_IN_CLEAR_CONFLICT' using errcode = '22023';
  end if;
  if p_clear_check_out and p_check_out is not null then
    raise exception 'CHECK_OUT_CLEAR_CONFLICT' using errcode = '22023';
  end if;
  if not (
    public.current_is_full_access()
    or public.can_access_employee(p_employee_id, 'attendance.correction.review')
    or public.can_access_employee(p_employee_id, 'attendance.record.manual_create')
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if exists (
    select 1
    from public.attendance_periods ap
    join public.employees e on e.id = p_employee_id
    left join public.branches b on b.id = e.branch_id
    where ap.period_month = v_month
      and ap.status = 'closed'
      and (ap.branch_id is null or ap.branch_id = e.branch_id)
      and (ap.legal_entity_id is null or ap.legal_entity_id = b.legal_entity_id)
  ) then
    raise exception 'ATTENDANCE_PERIOD_CLOSED' using errcode = '55000';
  end if;

  -- تطبيع leave_type قبل INSERT لحفظه في العمود الجديد
  if p_day_type in ('leave','absent') then
    v_leave_type := coalesce(nullif(trim(coalesce(p_leave_type, '')), ''), case when p_day_type = 'absent' then 'unpaid' else 'annual' end);
    if v_leave_type = 'emergency' then v_leave_type := 'casual'; end if;
    if v_leave_type not in ('annual','casual','sick','unpaid','weekly_rest_comp') then
      raise exception 'unsupported leave type: %', v_leave_type using errcode = '22023';
    end if;
  end if;

  select to_jsonb(o) into v_previous
  from public.attendance_day_overrides o
  where o.employee_id = p_employee_id and o.work_date = p_work_date;

  -- الإضافة الوحيدة عن 0355: حفظ leave_type في عمود الجدول
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

  -- ─────────────────────────────────────────────────────────────────────────
  -- منطق إنشاء الطلبات — مطابق لـ 0355 بالكامل (لا تغيير هنا)
  -- ─────────────────────────────────────────────────────────────────────────
  if p_day_type in ('leave','absent','mission','convoy','fundraising') then
    if p_day_type in ('leave','absent') then
      select id, affects_balance into v_leave_type_id, v_affects
      from public.leave_types where code = v_leave_type and is_active = true;
      if v_leave_type_id is null then
        raise exception 'leave type is inactive or unknown: %', v_leave_type using errcode = '22023';
      end if;

      if not exists (
        select 1
          from public.leave_requests lr
          join public.requests r on r.id = lr.request_id and r.status = 'approved'
         where lr.employee_id = p_employee_id
           and p_work_date between lr.start_date and lr.end_date
      ) then
        v_manager := public.resolve_request_approver(p_employee_id, p_work_date);
        v_payload := jsonb_build_object(
          'leaveType', v_leave_type,
          'startDate', p_work_date,
          'endDate', p_work_date,
          'days', 1,
          'dayMark', true);

        v_req := public._submit_request_for(
          p_employee_id,
          'leave',
          null,
          v_manager,
          'تحديد يوم إداري — ' || (case when p_day_type = 'absent' then 'غياب' else 'إجازة' end),
          btrim(p_reason),
          v_payload);

        insert into public.leave_requests(
          request_id, employee_id, leave_type_id, start_date, end_date,
          days_count, duration_unit, created_by)
        values(
          v_req.id, p_employee_id, v_leave_type_id, p_work_date, p_work_date,
          1, 'day', auth.uid());

        v_req := public._admin_approve_request_immediately(v_req.id);
      end if;
    else
      if not exists (
        select 1
          from public.requests r
         where r.employee_id = p_employee_id
           and r.request_type = p_day_type
           and r.status = 'approved'
           and p_work_date between (r.payload->>'startDate')::date
                               and coalesce((r.payload->>'endDate')::date, (r.payload->>'startDate')::date)
      ) then
        v_manager := public.resolve_request_approver(p_employee_id, p_work_date);
        v_payload := jsonb_build_object(
          'startDate', p_work_date,
          'endDate', p_work_date,
          'days', 1,
          'dayMark', true,
          'location', coalesce(nullif(trim(coalesce(p_notes, '')), ''), 'تحديد إداري'));

        v_req := public._submit_request_for(
          p_employee_id,
          p_day_type,
          null,
          v_manager,
          'تحديد يوم إداري — ' || public.request_type_label(p_day_type),
          btrim(p_reason),
          v_payload);

        v_req := public._admin_approve_request_immediately(v_req.id);
      end if;
    end if;
  end if;

  perform public.log_audit_event(
    'attendance.day.override.saved', 'workflow', 'warning',
    'attendance_day_overrides', v_id,
    'تعديل إداري ليوم حضور', p_reason,
    jsonb_build_object(
      'employeeId', p_employee_id,
      'workDate', p_work_date,
      'previous', v_previous,
      'dayType', p_day_type,
      'leaveType', v_leave_type,
      'requestId', case when v_req.id is null then null else v_req.id end,
      'checkIn', p_check_in,
      'checkOut', p_check_out,
      'clearCheckIn', coalesce(p_clear_check_in, false),
      'clearCheckOut', coalesce(p_clear_check_out, false)
    )
  );

  return jsonb_build_object('ok', true, 'id', v_id, 'employeeId', p_employee_id, 'workDate', p_work_date);
end
$$;

revoke all on function public.set_employee_attendance_day_admin(uuid,date,text,time,time,boolean,boolean,text,text,text)
  from public, anon;
grant execute on function public.set_employee_attendance_day_admin(uuid,date,text,time,time,boolean,boolean,text,text,text)
  to authenticated, service_role;

-- ─── 3) _build_attendance_statement: إرجاع leaveType في adminOverride ─────────
create or replace function public._build_attendance_statement(
  p_employee_id uuid,
  p_year integer,
  p_month integer
)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_days jsonb;
  v_month_start date := make_date(p_year, p_month, 1);
  v_month_end date := (make_date(p_year, p_month, 1) + interval '1 month - 1 day')::date;
  v_today date := current_date;
  v_emp jsonb;
begin
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

  return jsonb_build_object(
    'employee', v_emp,
    'period', jsonb_build_object(
      'year', p_year, 'month', p_month,
      'startDate', to_char(v_month_start, 'YYYY-MM-DD'),
      'endDate', to_char(v_month_end, 'YYYY-MM-DD')
    ),
    'days', v_days,
    'totals', jsonb_build_object('present', 0, 'absent', 0, 'leave', 0, 'late', 0)
  );
end $$;

revoke all on function public._build_attendance_statement(uuid,integer,integer) from public, anon;
grant execute on function public._build_attendance_statement(uuid,integer,integer) to authenticated, service_role;

-- ─── 4) backfill leave_type من leave_requests المرتبطة ───────────────────────
-- يملأ leave_type للأيام المرمزة إدارياً (leave/absent) التي لم تُحفظ فيها
-- قبل هذا الإصلاح — يستمد نوع الإجازة من leave_requests الموافقة المرتبطة.
update public.attendance_day_overrides ado
set    leave_type = lt.code
from   public.leave_requests lr
join   public.requests req on req.id = lr.request_id and req.status = 'approved'
join   public.leave_types lt on lt.id = lr.leave_type_id
where  lr.employee_id = ado.employee_id
  and  ado.work_date between lr.start_date and lr.end_date
  and  ado.leave_type is null
  and  ado.day_type in ('leave','absent');

NOTIFY pgrst, 'Reload schema';

COMMIT;
