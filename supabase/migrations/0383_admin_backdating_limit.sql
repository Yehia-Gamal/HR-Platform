-- migration: 0377
-- description: limit admin backdating to 90 days — prevent historical falsification
-- أُعيدت الكتابة على النسخة الفعلية المطبَّقة في DB (0266/0315/0362 + توقيع 10 وسائط
-- مع p_leave_type) بحيث يستبدلها في مكانها (نفس التوقيع) ويطبَّق حارس الـ 90 يوماً
-- فعلياً على كل المستدعين، بدل إنشاء overload ميت بتوقيع وهمي (integer,date,text,text).

begin;

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

  -- ── حارس الـ backdating (0383) — يمنع تزوير سجلات قديمة ───────────────────
  -- service_role يتجاوز الحارس للتصحيحات الرسمية/الترحيلات.
  if auth.role() <> 'service_role' then
    if p_work_date > v_today then
      raise exception 'INVALID_DATE: cannot set attendance for a future date' using errcode = '22023';
    end if;
    if p_work_date < (v_today - interval '90 days')::date then
      raise exception 'BACKDATING_LIMIT: cannot modify attendance older than 90 days (date: %, limit: %)',
        p_work_date, (v_today - interval '90 days')::date;
    end if;
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

  -- تطبيع نوع الإجازة قبل التخزين في attendance_day_overrides.leave_type.
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

  -- ─────────────────────────────────────────────────────────────────────────
  -- ترميز إداري مباشر → ينشئ طلباً معتمداً (خصم الرصيد للِإجازة/الغياب).
  -- نمنع إنشاء طلب مكرر ليومٍ به طلب معتمد مسبقاً يغطي نفس اليوم.
  -- ─────────────────────────────────────────────────────────────────────────
  if p_day_type in ('leave','absent','mission','convoy','fundraising') then
    if p_day_type in ('leave','absent') then
      -- نوع الإجازة: سبق تطبيعه أعلاه (v_leave_type) وتحققنا من صلاحيته.
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
      -- مأمورية/قافلة/فاندي: طلب تشغيلي معتمد → تريجر الإعفاء يكتب present + استثناء
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

  return jsonb_build_object(
    'ok', true,
    'id', v_id,
    'employeeId', p_employee_id,
    'workDate', p_work_date,
    'leaveType', v_leave_type
  );
end
$$;

revoke all on function public.set_employee_attendance_day_admin(
  uuid,date,text,time,time,boolean,boolean,text,text,text
) from public, anon;
grant execute on function public.set_employee_attendance_day_admin(
  uuid,date,text,time,time,boolean,boolean,text,text,text
) to authenticated, service_role;

commit;
