-- ============================================================================
-- 0354: إصلاح احتساب الغياب للطلبات المعلّقة + سلسلة اعتماد تشغيل سليمة
--
-- الشكوى: «عند طلب مأمورية أو إجازة لا يتم اعتمادها ويُحتسب اليوم غياباً».
-- السببان الجذريان:
--   (أ) الأيام التي عليها طلب معلّق (pending) كانت تُحتسب غياباً في الكشف
--       لأن الكشف يعتمد فقط على الطلبات المعتمدة وصفوف الحضور.
--   (ب) resolve_request_approver تعيد null عند غياب المدير المباشر / التنفيذي
--       للتشغيل، فلا يملك الطلب أي معتمِد فيبقى معلّقاً.
--
-- المكونات:
--   (1) توسيع workflow_definitions.request_type ليشمل fundraising وأذون الحضور.
--   (2) التشغيل (مأمورية/قافلة/فاندي) يُعتمد بخطوة واحدة من المدير المباشر أو
--       البديل — إزالة أي تعريف افتراضي بمراجعة HR تبقيه معلّقاً.
--   (3) resolve_request_approver: معتمِد بديل عند غياب المدير المباشر
--       (executive-director → صاحب صلاحية requests.approve بنطاق تنظيمي → executive).
--   (4) كشف الشهر: أيام عليها طلب معلّق لا تُحتسب غياباً وتُعرض «بانتظار الاعتماد».
--   (5) tg_request_approved_attendance_exempt: يشمل الفاندي (fundraising).
--   (6) refresh_kpi_attendance_inputs: إعفاء معلّق (pending_exempt) لا يخصم من الحضور.
-- ============================================================================

begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- (1) توسيع أنواع سير العمل
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.workflow_definitions
  drop constraint if exists workflow_definitions_request_type_check;
alter table public.workflow_definitions
  add constraint workflow_definitions_request_type_check
  check (request_type in (
    'leave','mission','convoy','fundraising','attendance_permit',
    'late_permit','early_permit','attendance_correction','generic'
  ));

-- ─────────────────────────────────────────────────────────────────────────────
-- (2) التشغيل يُعتمد بخطوة واحدة من المدير المباشر أو البديل
--     بلا تعريف سير عمل افتراضي بمراجعة HR (حتى لا يبقى الطلب معلّقاً
--     ويُحتسب غياباً، وليتوافق مع عقد تنفيذ المأمورية/القافلة في 0108).
--     يُزال أي تعريف افتراضي سابق للتشغيل إن وُجد.
-- ─────────────────────────────────────────────────────────────────────────────
delete from public.workflow_definitions
  where request_type in ('mission','convoy','fundraising')
    and is_default;

-- ─────────────────────────────────────────────────────────────────────────────
-- (3) resolve_request_approver — معتمِد بديل عند غياب المدير المباشر
--     (إعادة تعريف نسخة 0136)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.resolve_request_approver(
  p_employee_id uuid,
  p_as_of date default (now() at time zone 'Africa/Cairo')::date
)
returns uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_mgr uuid;
  v_dept_id uuid;
  v_is_operations boolean := false;
  v_executive_employee_id uuid;
begin
  -- المدير المباشر (primary) من الهيكل الإداري
  select manager_employee_id into v_mgr
  from public.manager_relations
  where employee_id = p_employee_id
    and relation_type = 'primary'
    and effective_from <= p_as_of
    and (effective_to is null or effective_to >= p_as_of)
  order by effective_from desc
  limit 1;

  -- منع الموافقة الذاتية: لو صار المدير هو المُقدِّم نفسه، اصعد لمديره
  if v_mgr is not null and v_mgr = p_employee_id then
    select manager_employee_id into v_mgr
    from public.manager_relations
    where employee_id = p_employee_id
      and relation_type = 'primary'
      and manager_employee_id <> p_employee_id
      and effective_from <= p_as_of
      and (effective_to is null or effective_to >= p_as_of)
    order by effective_from desc
    limit 1;
  end if;

  -- V17 §1.2: توجيه طلبات التشغيل للمدير التنفيذي
  select e.department_id into v_dept_id
  from public.employees e
  where e.id = p_employee_id and e.is_active and not e.is_deleted;

  if v_dept_id is not null then
    select exists(
      with recursive dept_tree as (
        select d.id, d.slug, d.parent_id
        from public.departments d where d.id = v_dept_id
        union all
        select p.id, p.slug, p.parent_id
        from public.departments p
        join dept_tree dt on dt.parent_id = p.id
      )
      select 1 from dept_tree where slug like 'operations%'
    ) into v_is_operations;
  end if;

  if v_is_operations then
    select e.id into v_executive_employee_id
    from public.employees e
    join public.user_roles ur on ur.user_id = e.user_id
    join public.roles r on r.id = ur.role_id
    where r.slug = 'executive'
      and e.is_active and not e.is_deleted
      and e.id <> p_employee_id
    limit 1;

    if v_executive_employee_id is not null then
      v_mgr := v_executive_employee_id;
    end if;
  end if;

  -- 0353: معتمِد بديل (fallback) عند غياب المدير المباشر والتنفيذي
  -- حتى لا يبقى الطلب بلا معتمِد ويُحتسب اليوم غياباً.
  if v_mgr is null then
    -- (أ) المدير التنفيذي الأول/الأعلى نشط
    select e.id into v_mgr
    from public.employees e
    join public.user_roles ur on ur.user_id = e.user_id
    join public.roles r on r.id = ur.role_id
    where r.slug = 'executive-director'
      and e.is_active and not e.is_deleted
      and e.id <> p_employee_id
    order by e.hire_date
    limit 1;
  end if;

  if v_mgr is null then
    -- (ب) أي موظف نشط بدور يملك صلاحية requests.approve بنطاق تنظيمي
    --     (يستطيع فعلياً تنفيذ decide_request في المسار الاحتياطي)
    select e.id into v_mgr
    from public.employees e
    join public.user_roles ur on ur.user_id = e.user_id
    join public.role_permissions rp on rp.role_id = ur.role_id
    join public.permissions perm on perm.id = rp.permission_id
    where perm.code = 'requests.approve'
      and rp.scope in ('organization', 'global')
      and e.is_active and not e.is_deleted
      and e.id <> p_employee_id
      and (ur.effective_from is null or ur.effective_from <= now())
      and (ur.effective_to   is null or ur.effective_to   >  now())
      and (rp.effective_from is null or rp.effective_from <= now())
      and (rp.effective_to   is null or rp.effective_to   >  now())
    order by e.hire_date
    limit 1;
  end if;

  if v_mgr is null then
    -- (ج) المدير التنفيذي النشط (غير المقدِّم)
    select e.id into v_mgr
    from public.employees e
    join public.user_roles ur on ur.user_id = e.user_id
    join public.roles r on r.id = ur.role_id
    where r.slug = 'executive'
      and e.is_active and not e.is_deleted
      and e.id <> p_employee_id
    order by e.hire_date
    limit 1;
  end if;

  return v_mgr;
end $$;

comment on function public.resolve_request_approver(uuid, date) is
  'V17 §1.2+§8 (0353): المدير المسؤول عن الطلب — التشغيل للتنفيذي، ومعتمِد بديل (executive-director ← requests.approve تنظيمي ← executive) عند غياب المدير المباشر.';

-- ─────────────────────────────────────────────────────────────────────────────
-- (4) كشف الشهر: الطلبات المعلّقة تُغيّي الغياب وتُعرض «بانتظار الاعتماد»
--     (الطبقة الخارجية نسخة 0291 فوق v286 + طبقة الطلبات المعلّقة 0354)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public._build_attendance_statement(
  p_employee_id uuid,
  p_year integer,
  p_month integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_result jsonb;
  v_days jsonb := '[]'::jsonb;
  v_day_obj jsonb;
  v_day date;
  v_ci text;
  v_co text;
  v_status text;
  v_is_absent boolean;
  v_pending_days integer := 0;
  v_absent_days integer;
  v_pending_leave boolean;
  v_pending_mission boolean;
  v_pending_convoy boolean;
begin
  v_result := public._build_attendance_statement_v286(p_employee_id, p_year, p_month);

  -- طبقة 0354: أعلام الطلبات المعلّقة + إلغاء الغياب + «بانتظار الاعتماد» +
  -- حقول العرض المنسّقة (فوق days من v286).
  for v_day_obj in select value from jsonb_array_elements(v_result->'days')
  loop
    v_day := (v_day_obj->>'date')::date;
    v_ci := v_day_obj->>'checkIn';
    v_co := v_day_obj->>'checkOut';

    v_pending_leave := exists (
      select 1 from public.requests r
      join public.leave_requests lr on lr.request_id = r.id
      where lr.employee_id = p_employee_id
        and r.status = 'pending'
        and v_day between lr.start_date and lr.end_date
    );
    v_pending_mission := exists (
      select 1 from public.requests r
      where r.employee_id = p_employee_id
        and r.request_type = 'mission'
        and r.status = 'pending'
        and v_day between (r.payload->>'startDate')::date
                      and coalesce((r.payload->>'endDate')::date, (r.payload->>'startDate')::date)
    );
    v_pending_convoy := exists (
      select 1 from public.requests r
      where r.employee_id = p_employee_id
        and r.request_type in ('convoy','fundraising')
        and r.status = 'pending'
        and v_day between (r.payload->>'startDate')::date
                      and coalesce((r.payload->>'endDate')::date, (r.payload->>'startDate')::date)
    );

    v_status := v_day_obj->>'status';
    v_is_absent := coalesce((v_day_obj->>'isAbsent')::boolean, false);

    -- يوم عليه طلب معلّق ولا تغطيه قاعدة أخرى (حضور فعلي/طلب معتمد/عطلة) → «بانتظار الاعتماد»
    if (v_pending_leave or v_pending_mission or v_pending_convoy)
       and v_is_absent
       and v_ci is null then
      v_status := case
        when v_pending_leave then 'بانتظار اعتماد إجازة'
        when v_pending_mission then 'بانتظار اعتماد مأمورية'
        else 'بانتظار اعتماد تكليف'
      end;
      v_is_absent := false;
      v_pending_days := v_pending_days + 1;
    end if;

    v_day_obj := v_day_obj || jsonb_strip_nulls(jsonb_build_object(
      'checkIn12',  case when v_ci is not null and v_ci <> '' then public._fmt_time_12h(v_ci::time) else null end,
      'checkOut12', case when v_co is not null and v_co <> '' then public._fmt_time_12h(v_co::time) else null end,
      'workHoursFormatted', public._fmt_minutes_ar(
        greatest(0, round(coalesce((v_day_obj->>'workHours')::numeric, 0) * 60))::integer
      ),
      'status', v_status,
      'isAbsent', v_is_absent,
      'hasPendingLeave', v_pending_leave,
      'hasPendingMission', v_pending_mission,
      'hasPendingConvoyFundi', v_pending_convoy
    ));

    v_days := v_days || jsonb_build_array(v_day_obj);
  end loop;

  v_absent_days := (select count(*)::int
    from jsonb_array_elements(v_days) d
    where coalesce((d->>'isAbsent')::boolean, false));

  v_result := v_result || jsonb_build_object(
    'days', v_days,
    'summary', (v_result->'summary') || jsonb_build_object(
      'absentDays', v_absent_days,
      'pendingDays', v_pending_days,
      'totalWorkHoursFormatted', public._fmt_minutes_ar(
        greatest(0, round(coalesce((v_result->'summary'->>'totalWorkHours')::numeric, 0) * 60))::integer
      ),
      'totalRequiredHoursFormatted', public._fmt_minutes_ar(
        greatest(0, round(coalesce((v_result->'summary'->>'totalRequiredHours')::numeric, 0) * 60))::integer
      ),
      'totalDeficitFormatted', public._fmt_minutes_ar(
        greatest(0, coalesce((v_result->'summary'->>'totalDeficitMinutes')::integer, 0))
      ),
      'totalOvertimeFormatted', public._fmt_minutes_ar(
        greatest(0, coalesce((v_result->'summary'->>'totalOvertimeMinutes')::integer, 0))
      ),
      'totalLateFormatted', public._fmt_minutes_ar(
        greatest(0, coalesce((v_result->'summary'->>'totalLateMinutes')::integer, 0))
      ),
      'totalEarlyLeaveFormatted', public._fmt_minutes_ar(
        greatest(0, coalesce((v_result->'summary'->>'totalEarlyLeaveMinutes')::integer, 0))
      )
    )
  );

  return v_result;
end
$$;

revoke execute on function public._build_attendance_statement(uuid, integer, integer)
  from public, anon, authenticated;
grant execute on function public._build_attendance_statement(uuid, integer, integer)
  to service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- (5) tg_request_approved_attendance_exempt — يشمل الفاندي (fundraising)
--     (إعادة تعريف نسخة 0317)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.tg_request_approved_attendance_exempt()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_work_date date;
  v_start_date date;
  v_end_date date;
  v_day date;
  v_employee_id uuid;
  v_employee_name text;
begin
  -- فقط عند الموافقة على الطلب
  if new.status <> 'approved' or (old.status = new.status) then
    return new;
  end if;

  v_employee_id := new.employee_id;

  -- تجاهل الإجازات — لها تريجر خاص (tg_leave_attendance_on_approval)
  if new.request_type = 'leave' then
    return new;
  end if;

  -- اسم الموظف للإشعار
  select full_name_ar into v_employee_name from public.employees where id = v_employee_id;

  -- ─── المأمورية/القافلة/الفاندي: قراءة التواريخ من payload الطلب ──────────
  if new.request_type in ('mission', 'convoy', 'fundraising') then
    v_start_date := (new.payload->>'startDate')::date;
    v_end_date   := coalesce((new.payload->>'endDate')::date, v_start_date);
    if v_start_date is null then return new; end if;

    v_day := v_start_date;
    while v_day <= v_end_date loop
      insert into public.attendance_daily (employee_id, work_date, status)
      values (v_employee_id, v_day, 'present')
      on conflict on constraint attendance_daily_uq do update
        set status = 'present',
            updated_at = now()
        where public.attendance_daily.is_finalized = false
          and public.attendance_daily.status not in ('on_leave', 'holiday', 'weekend');

      -- سجل استثناء: مأمورية معتمدة
      insert into public.attendance_exceptions (
        employee_id, attendance_daily_id, work_date, kind, description, status, created_by
      )
      select v_employee_id, ad.id, v_day, 'manual_adjustment',
             'مأمورية معتمدة — إعفاء من التأخير/الغياب',
             'approved', auth.uid()
      from public.attendance_daily ad
      where ad.employee_id = v_employee_id and ad.work_date = v_day
      on conflict do nothing;

      v_day := v_day + 1;
    end loop;

    perform public.log_audit_event(
      'request.attendance_exempted', 'workflow', 'info',
      'attendance_daily', v_employee_id,
      'إعفاء حضور بعد اعتماد مأمورية',
      format('من %s إلى %s', v_start_date, v_end_date),
      jsonb_build_object('requestId', new.id, 'requestType', new.request_type,
                         'startDate', v_start_date, 'endDate', v_end_date)
    );
    return new;
  end if;

  -- ─── إذن تأخير/انصراف: قراءة permitDate من payload ──────────────────
  if new.request_type in ('late_permit', 'early_permit') then
    v_work_date := (new.payload->>'permitDate')::date;
    if v_work_date is null then
      v_work_date := (new.payload->>'date')::date;
    end if;
    if v_work_date is null then return new; end if;

    if new.request_type = 'late_permit' then
      insert into public.attendance_daily (employee_id, work_date, status, late_minutes)
      values (v_employee_id, v_work_date, 'present', 0)
      on conflict on constraint attendance_daily_uq do update
        set late_minutes = 0,
            status = case when public.attendance_daily.status in ('on_leave','holiday','weekend')
                         then public.attendance_daily.status else 'present' end,
            updated_at = now()
        where public.attendance_daily.is_finalized = false;

      insert into public.attendance_exceptions (
        employee_id, work_date, kind, description, minutes_adjustment, status, created_by
      )
      values (v_employee_id, v_work_date, 'late',
              'إذن تأخير معتمد — إعفاء من دقائق التأخير',
              0, 'approved', auth.uid())
      on conflict do nothing;
    else
      -- إذن انصراف مبكر: سجل استثناء
      insert into public.attendance_exceptions (
        employee_id, work_date, kind, description, minutes_adjustment, status, created_by
      )
      values (v_employee_id, v_work_date, 'early_leave',
              'إذن انصراف مبكر معتمد',
              0, 'approved', auth.uid())
      on conflict do nothing;
    end if;

    perform public.log_audit_event(
      'request.attendance_exempted', 'workflow', 'info',
      'attendance_daily', v_employee_id,
      'إعفاء حضور بعد اعتماد طلب',
      format('النوع: %s، التاريخ: %s', new.request_type, v_work_date),
      jsonb_build_object('requestId', new.id, 'requestType', new.request_type, 'workDate', v_work_date)
    );
    return new;
  end if;

  -- أنواع أخرى (attendance_correction) — لا نعالجها
  return new;
end;
$$;

comment on function public.tg_request_approved_attendance_exempt() is
  'يُعفي الموظف من التأخير/الغياب عند اعتماد مأمورية/قافلة/فاندي (من payload startDate/endDate) أو إذن تأخير/انصراف مبكر (permitDate).';

drop trigger if exists trg_request_approved_attendance_exempt on public.requests;
create trigger trg_request_approved_attendance_exempt
  after update of status on public.requests
  for each row execute function public.tg_request_approved_attendance_exempt();

-- ─────────────────────────────────────────────────────────────────────────────
-- (6) refresh_kpi_attendance_inputs — الطلبات المعلّقة لا تُخصم من درجة الحضور
--     (إعادة تعريف نسخة 0065)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.refresh_kpi_attendance_inputs(p_cycle_id uuid)
returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare
 v_cycle public.kpi_cycles; v_eval record; v_rules jsonb; v_count integer:=0;
 v_start date; v_end date; v_late integer; v_early integer; v_absent integer;
 v_missing integer; v_shortage numeric; v_pending boolean; v_score numeric; v_old numeric;
begin
 if not(public.current_is_full_access() or public.has_any_permission(array['performance.cycle.manage','performance.kpi.attendance.refresh','performance.kpi.hr_assess','performance.kpi.hr_review'])) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 select * into strict v_cycle from public.kpi_cycles where id=p_cycle_id;
 select attendance_rules into strict v_rules from public.kpi_policy_versions where id=v_cycle.policy_version_id;
 v_start:=date_trunc('month',v_cycle.period_month)::date;
 v_end:=least((v_start+interval '1 month'-interval '1 day')::date,(public.kpi_effective_deadline(v_cycle) at time zone 'Africa/Cairo')::date);

 for v_eval in
  select e.id,e.employee_id,c.id criterion_id from public.kpi_evaluations e
  join public.kpi_criteria c on c.template_id=e.template_id and c.code='ATTENDANCE'
  where e.cycle_id=p_cycle_id
 loop
  with daily as (
   select a.*,
    exists(select 1 from public.attendance_permits p where p.employee_id=a.employee_id and p.permit_date=a.work_date and p.kind='arrival' and p.status='approved') arrival_permit,
    exists(select 1 from public.attendance_permits p where p.employee_id=a.employee_id and p.permit_date=a.work_date and p.kind='departure' and p.status='approved') departure_permit,
    exists(select 1 from public.attendance_exceptions x where x.employee_id=a.employee_id and coalesce(x.work_date,a.work_date)=a.work_date and x.status in ('approved','resolved')) exception_settled,
    exists(select 1 from public.attendance_corrections x where x.employee_id=a.employee_id and x.work_date=a.work_date and x.status='approved') correction_settled,
    exists(select 1 from public.roster_days rd where rd.employee_id=a.employee_id and rd.work_date=a.work_date and rd.day_status in ('rest','holiday','leave','mission','cancelled')) roster_exempt,
    exists(select 1 from public.leave_requests lr join public.requests r on r.id=lr.request_id where lr.employee_id=a.employee_id and r.status in ('approved','pending') and a.work_date between lr.start_date and lr.end_date) leave_exempt,
    exists(select 1 from public.missions m join public.requests r on r.id=m.request_id where m.employee_id=a.employee_id and r.status='approved' and a.work_date between (m.start_at at time zone 'Africa/Cairo')::date and (m.end_at at time zone 'Africa/Cairo')::date) mission_exempt,
    exists(select 1 from public.work_assignment_participants wp join public.work_assignments wa on wa.id=wp.assignment_id where wp.employee_id=a.employee_id and wa.status='APPROVED' and coalesce(wa.counts_as_work_day,true) and a.work_date between (wa.start_at at time zone 'Africa/Cairo')::date and (wa.end_at at time zone 'Africa/Cairo')::date) assignment_exempt,
    exists(select 1 from public.requests r where r.employee_id=a.employee_id and r.request_type in ('mission','convoy','fundraising') and r.status='pending' and a.work_date between (r.payload->>'startDate')::date and coalesce((r.payload->>'endDate')::date,(r.payload->>'startDate')::date)) request_pending_exempt,
    greatest(0,
      case when s.crosses_midnight then extract(epoch from ((s.end_time+interval '24 hours')-s.start_time))/60
           else extract(epoch from (s.end_time-s.start_time))/60 end-coalesce(s.break_minutes,0)
    )::integer scheduled_minutes
   from public.attendance_daily a left join public.shifts s on s.id=a.shift_id
   where a.employee_id=v_eval.employee_id and a.work_date between v_start and v_end
  ), scored as (
   select *, (status in ('on_leave','holiday','weekend') or roster_exempt or leave_exempt or mission_exempt or assignment_exempt or request_pending_exempt) exempt
   from daily
  )
  select
   count(*) filter(where not exempt and late_minutes>0 and not arrival_permit and not exception_settled and not correction_settled),
   count(*) filter(where not exempt and early_leave_minutes>0 and not departure_permit and not exception_settled and not correction_settled),
   count(*) filter(where not exempt and status='absent' and not exception_settled and not correction_settled),
   count(*) filter(where not exempt and status<>'absent' and (status in ('partial','pending') or first_check_in is null or last_check_out is null) and not exception_settled and not correction_settled),
   coalesce(sum(case when not exempt and status<>'absent' and not exception_settled and not correction_settled and scheduled_minutes>work_minutes
     then least((v_rules->>'maxShortagePerDay')::numeric,ceil((scheduled_minutes-work_minutes)::numeric/60)*(v_rules->>'shortagePerHour')::numeric) else 0 end),0)
  into v_late,v_early,v_absent,v_missing,v_shortage from scored;

  select exists(
   select 1 from public.attendance_daily a where a.employee_id=v_eval.employee_id and a.work_date between v_start and v_end and a.status='pending'
   union all select 1 from public.attendance_events a where a.employee_id=v_eval.employee_id and (a.event_at at time zone 'Africa/Cairo')::date between v_start and v_end and a.requires_review
   union all select 1 from public.attendance_exceptions a where a.employee_id=v_eval.employee_id and coalesce(a.work_date,v_start) between v_start and v_end and a.status='open'
   union all select 1 from public.attendance_corrections a where a.employee_id=v_eval.employee_id and a.work_date between v_start and v_end and a.status='pending'
  ) into v_pending;

  v_score:=greatest(0,round(20-
   v_late*(v_rules->>'late')::numeric-v_early*(v_rules->>'earlyLeave')::numeric-
   v_absent*(v_rules->>'unexcusedAbsence')::numeric-v_missing*(v_rules->>'missingPunch')::numeric-v_shortage,2));
  select score into v_old from public.kpi_scores where evaluation_id=v_eval.id and criterion_id=v_eval.criterion_id and reviewer_stage='hr';
  insert into public.kpi_attendance_snapshots(evaluation_id,period_start,period_end,late_count,early_leave_count,unexcused_absence_count,shortage_penalty,missing_punch_count,score,has_pending_items,details,calculated_by)
  values(v_eval.id,v_start,v_end,v_late,v_early,v_absent,v_shortage,v_missing,v_score,v_pending,jsonb_build_object('rules',v_rules),auth.uid())
  on conflict(evaluation_id) do update set period_start=excluded.period_start,period_end=excluded.period_end,late_count=excluded.late_count,early_leave_count=excluded.early_leave_count,unexcused_absence_count=excluded.unexcused_absence_count,shortage_penalty=excluded.shortage_penalty,missing_punch_count=excluded.missing_punch_count,score=excluded.score,has_pending_items=excluded.has_pending_items,details=excluded.details,calculated_at=now(),calculated_by=auth.uid(),updated_at=now();
  insert into public.kpi_scores(evaluation_id,criterion_id,score,reviewer_stage,note,created_by)
  values(v_eval.id,v_eval.criterion_id,v_score,'hr','محسوب آليًا من الحضور والانصراف والاستثناءات والتكليفات المعتمدة',auth.uid())
  on conflict(evaluation_id,criterion_id,reviewer_stage) do update set score=excluded.score,note=excluded.note,updated_at=now();
  if v_old is distinct from v_score then
   perform public.log_audit_event('kpi.attendance.recalculated','workflow','notice','kpi_evaluations',v_eval.id,'إعادة حساب درجة الحضور',null,jsonb_build_object('oldScore',v_old,'newScore',v_score,'late',v_late,'earlyLeave',v_early,'absence',v_absent,'missingPunch',v_missing,'shortagePenalty',v_shortage,'pending',v_pending));
  end if;
  v_count:=v_count+1;
 end loop;
 return v_count;
end $$;

comment on function public.refresh_kpi_attendance_inputs(uuid) is
  '0353: يعيد حساب درجة الحضور لمرحلة KPI — أيام الطلبات المعلّقة (إجازة/مأمورية/قافلة/فاندي) تُعامل كإعفاء (request_pending_exempt) ولا تُخصم من الدرجة.';

-- ---------------------------------------------------------------------------
notify pgrst, 'reload schema';

commit;
