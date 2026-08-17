-- migration: 0429
-- description: تحصين الوصول لحضور/إجازات الموظفين (الحالة العامة فقط للجميع + منع الكتابة خارج النطاق)
--              + المأموريات/القوافل لا تُحتسب غياباً في ملف الموظف (بلا خصم من الرصيد)
--              + بدل الراحة الأسبوعي يُمنح تلقائياً عن الجمعة في مأمورية/قافلة/تكليف عمل
--              + منح بدل راحة يدوي لأي موظف (HR/التنفيذي)
-- -----------------------------------------------------------------------------
-- القرارات:
--   * المأمورية/القافلة المعتمدة = يوم عمل معتمد (يظهر "في إجازة" في الحضور والدليل)
--     ولا يُخصم أي رصيد إجازات (قرار الإدارة).
--   * عامة الموظفين (الدليل): لا يرون سوى الحالة: present / on_leave / absent.
--   * التفاصيل الكاملة (الكشف الشهري، الجداول، الأرصدة): المدير المباشر + التنفيذي + HR
--     فقط — عبر can_access_employee(employee_id, permission) ذات النطاقات.

begin;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1) سياسات الكتابة على جداول الحضور: فرض نطاق can_access_employee بدل has_permission
--    المكشوفة (كان أي حامل صلاحية — حتى بنطاق self — يكتب على صفوف أي موظف).
-- ═══════════════════════════════════════════════════════════════════════════════

-- attendance_daily
drop policy if exists att_daily_write on public.attendance_daily;
create policy att_daily_write on public.attendance_daily
  for all to authenticated
  using (
    public.can_access_employee(employee_id,'attendance.record.process')
    or public.can_access_employee(employee_id,'attendance.record.review')
  )
  with check (
    public.can_access_employee(employee_id,'attendance.record.process')
    or public.can_access_employee(employee_id,'attendance.record.review')
  );

-- attendance_identity_checks
drop policy if exists att_idcheck_write on public.attendance_identity_checks;
create policy att_idcheck_write on public.attendance_identity_checks
  for all to authenticated
  using (public.can_access_employee(employee_id,'attendance.identity.manage'))
  with check (public.can_access_employee(employee_id,'attendance.identity.manage'));

-- attendance_risk_events
drop policy if exists att_risk_write on public.attendance_risk_events;
create policy att_risk_write on public.attendance_risk_events
  for all to authenticated
  using (public.can_access_employee(employee_id,'attendance.risk.manage'))
  with check (public.can_access_employee(employee_id,'attendance.risk.manage'));

-- attendance_exceptions
drop policy if exists att_exc_write on public.attendance_exceptions;
create policy att_exc_write on public.attendance_exceptions
  for all to authenticated
  using (
    public.can_access_employee(employee_id,'attendance.exception.manage')
    or public.can_access_employee(employee_id,'attendance.record.review')
  )
  with check (
    public.can_access_employee(employee_id,'attendance.exception.manage')
    or public.can_access_employee(employee_id,'attendance.record.review')
  );

-- attendance_permits (الموظف يبقى قادراً على طلب لنفسه وتعديل طلبه المعلّق)
drop policy if exists att_permit_insert on public.attendance_permits;
create policy att_permit_insert on public.attendance_permits
  for insert to authenticated
  with check (
    public.can_access_employee(employee_id,'attendance.permit.manage')
    or employee_id = public.current_employee_id()
  );

drop policy if exists att_permit_update on public.attendance_permits;
create policy att_permit_update on public.attendance_permits
  for update to authenticated
  using (
    public.can_access_employee(employee_id,'attendance.permit.manage')
    or (employee_id = public.current_employee_id() and status = 'pending')
  )
  with check (
    public.can_access_employee(employee_id,'attendance.permit.manage')
    or (employee_id = public.current_employee_id() and status = 'pending')
  );

drop policy if exists att_permit_delete on public.attendance_permits;
create policy att_permit_delete on public.attendance_permits
  for delete to authenticated
  using (public.can_access_employee(employee_id,'attendance.permit.manage'));

-- attendance_events (النسخ الحالية من 0012 — إدخال/تحديث/حذف بلا نطاق)
drop policy if exists att_events_insert on public.attendance_events;
create policy att_events_insert on public.attendance_events
  for insert to authenticated
  with check (public.can_access_employee(employee_id,'attendance.record.manual_create'));

drop policy if exists att_events_update on public.attendance_events;
create policy att_events_update on public.attendance_events
  for update to authenticated
  using (
    public.can_access_employee(employee_id,'attendance.record.manual_create')
    or public.can_access_employee(employee_id,'attendance.record.review')
  )
  with check (
    public.can_access_employee(employee_id,'attendance.record.manual_create')
    or public.can_access_employee(employee_id,'attendance.record.review')
  );

drop policy if exists att_events_delete on public.attendance_events;
create policy att_events_delete on public.attendance_events
  for delete to authenticated
  using (public.can_access_employee(employee_id,'attendance.record.review'));

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2) تحصين RPCs المكشوفة: قراءة كشف/ملخص موظف تتطلب نطاقاً فعلياً على الموظف
--    المستهدف (كان حامل الصلاحية بنطاق self يقرأ كشف أي موظف آخر).
-- ═══════════════════════════════════════════════════════════════════════════════

-- 2a) الكشف الشهري لأي موظف: يتطلب الوصول النطاقي على p_employee_id
create or replace function public.get_employee_monthly_attendance_statement(
  p_employee_id uuid,
  p_year integer default extract(year from (now() at time zone 'Africa/Cairo'))::integer,
  p_month integer default extract(month from (now() at time zone 'Africa/Cairo'))::integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if p_month < 1 or p_month > 12 then raise exception 'INVALID_MONTH' using errcode = '22023'; end if;
  -- الصلاحية: full-access أو وصول نطاقي فعلي (المدير المباشر/الإدارة/HR/التنفيذي)
  -- بصلاحية قراءة الحضور أو التقارير — بنطاق self لا يمر (لا يُرى سوى الموظف نفسه).
  if not (
    public.current_is_full_access()
    or public.can_access_employee(p_employee_id, 'attendance.record.read')
    or public.can_access_employee(p_employee_id, 'reports.attendance.read')
  ) then
    raise exception 'FORBIDDEN: لا تملك صلاحية رؤية كشف هذا الموظف' using errcode = '42501';
  end if;
  return public._build_attendance_statement(p_employee_id, p_year, p_month);
end $$;

-- 2b) قائمة الموظفين التنفيذية: فلتر per-row على نطاق المستدعي
create or replace function public.get_mobile_executive_people(
  p_search text default null,
  p_limit integer default 60
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_allowed boolean;
  v_search text := nullif(trim(coalesce(p_search, '')), '');
  v_today date := (now() at time zone 'Africa/Cairo')::date;
begin
  v_allowed := public.current_is_full_access() or public.has_any_permission(array[
    'performance.kpi.executive_review',
    'reports.executive.read',
    'live_location.request',
    'people.employee.read'
  ]);
  if not v_allowed then
    raise exception 'executive people access denied' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', x.id,
      'employeeCode', x.employee_code,
      'name', x.full_name_ar,
      'photoUrl', x.photo_url,
      'jobTitle', x.job_title,
      'department', x.department,
      'team', x.team,
      'attendanceStatus', x.attendance_status,
      'pendingRequests', x.pending_requests,
      'openTasks', x.open_tasks,
      'latestKpiScore', x.latest_kpi_score
    ) order by x.full_name_ar)
    from (
      select e.id, e.employee_code, e.full_name_ar, e.photo_url,
        jt.name job_title, d.name department, tm.name team,
        ad.status attendance_status,
        (select count(*) from public.requests r where r.employee_id = e.id and r.status = 'pending') pending_requests,
        (select count(*) from public.tasks t where t.assignee_employee_id = e.id and t.status in ('pending','in_progress')) open_tasks,
        (select ke.final_score from public.kpi_evaluations ke join public.kpi_cycles kc on kc.id = ke.cycle_id where ke.employee_id = e.id order by kc.period_month desc, ke.created_at desc limit 1) latest_kpi_score
      from public.employees e
      left join public.job_titles jt on jt.id = e.job_title_id
      left join public.departments d on d.id = e.department_id
      left join public.teams tm on tm.id = e.team_id
      left join public.attendance_daily ad on ad.employee_id = e.id and ad.work_date = v_today
      where e.is_active = true and e.is_deleted = false
        and public.can_access_employee(e.id,'people.employee.read')
        and (v_search is null or e.full_name_ar ilike '%' || public.escape_ilike(v_search) || '%' or e.employee_code ilike '%' || public.escape_ilike(v_search) || '%')
      order by e.full_name_ar
      limit greatest(1, least(coalesce(p_limit, 60), 100))
    ) x
  ), '[]'::jsonb);
end;
$$;

-- 2c) الملخص التنفيذي لموظف محدد: نطاق على المعامل
create or replace function public.get_mobile_executive_employee_summary(
  p_employee_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_allowed boolean;
  v_result jsonb;
begin
  v_allowed := public.current_is_full_access() or public.has_any_permission(array[
    'performance.kpi.executive_review',
    'reports.executive.read',
    'live_location.request',
    'people.employee.read'
  ]);
  if not v_allowed then
    raise exception 'executive employee summary access denied' using errcode = '42501';
  end if;
  -- نطاق فعلي على الموظف المستهدف — المدير المباشر لا يقرأ خارج فريقه.
  if not (public.current_is_full_access() or public.can_access_employee(p_employee_id,'people.employee.read')) then
    raise exception 'FORBIDDEN: لا تملك صلاحية رؤية ملف هذا الموظف' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'id', e.id,
    'employeeCode', e.employee_code,
    'name', e.full_name_ar,
    'photoUrl', e.photo_url,
    'status', e.status,
    'jobTitle', jt.name,
    'position', p.name,
    'department', d.name,
    'team', tm.name,
    'branch', b.name,
    'workSite', ws.name,
    'managerName', manager.full_name_ar,
    'hireDate', e.hire_date,
    'pendingRequests', (select count(*) from public.requests r where r.employee_id = e.id and r.status = 'pending'),
    'openTasks', (select count(*) from public.tasks t where t.assignee_employee_id = e.id and t.status in ('pending','in_progress')),
    'expiringDocuments', (select count(*) from public.documents doc where doc.owner_employee_id = e.id and doc.status <> 'archived' and doc.expiry_date <= current_date + 60),
    'latestKpi', (
      select jsonb_build_object('score', ke.final_score, 'rating', ke.final_rating, 'stage', ke.current_stage, 'periodMonth', kc.period_month)
      from public.kpi_evaluations ke
      join public.kpi_cycles kc on kc.id = ke.cycle_id
      where ke.employee_id = e.id
      order by kc.period_month desc, ke.created_at desc
      limit 1
    ),
    'recentAttendance', coalesce((
      select jsonb_agg(jsonb_build_object(
        'workDate', a.work_date,
        'status', a.status,
        'lateMinutes', a.late_minutes,
        'workMinutes', a.work_minutes,
        'firstCheckIn', a.first_check_in,
        'lastCheckOut', a.last_check_out
      ) order by a.work_date desc)
      from (
        select * from public.attendance_daily
        where employee_id = e.id
        order by work_date desc
        limit 14
      ) a
    ), '[]'::jsonb),
    'lastUpdatedAt', now()
  ) into v_result
  from public.employees e
  left join public.job_titles jt on jt.id = e.job_title_id
  left join public.positions p on p.id = e.position_id
  left join public.departments d on d.id = e.department_id
  left join public.teams tm on tm.id = e.team_id
  left join public.branches b on b.id = e.branch_id
  left join public.work_sites ws on ws.id = e.work_site_id
  left join lateral (
    select me.full_name_ar
    from public.manager_relations mr
    join public.employees me on me.id = mr.manager_employee_id
    where mr.employee_id = e.id
      and mr.relation_type = 'primary'
      and mr.effective_from <= (now() at time zone 'Africa/Cairo')::date
      and (mr.effective_to is null or mr.effective_to >= (now() at time zone 'Africa/Cairo')::date)
    order by mr.effective_from desc
    limit 1
  ) manager on true
  where e.id = p_employee_id;

  return v_result;
end;
$$;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 3) دليل الموظفين العام: إضافة الحالة العامة اليومية (present/on_leave/absent)
--    — ما يظهر لكل الموظفين هو الحالة فقط، بلا أي تفاصيل حضور/إجازات.
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.get_mobile_employee_directory(
  p_search text default null,
  p_limit  integer default 40
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_search text := nullif(trim(coalesce(p_search, '')), '');
  v_today date := (now() at time zone 'Africa/Cairo')::date;
begin
  -- متاح لأي موظف مفعّل في المنظمة (يعرض الحالة العامة فقط — لا تفاصيل)
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',           e.id,
      'name',         e.full_name_ar,
      'employeeCode', e.employee_code,
      'photoUrl',     e.photo_url,
      'jobTitle',     jt.name,
      'department',   d.name,
      'statusToday',  case
        -- الحالة المباشرة من جدول الحضور (present/on_leave/absent)
        when ad.status in ('present','late','partial') then 'present'
        when ad.status = 'on_leave' then 'on_leave'
        when ad.status is not null and ad.status <> 'absent' then ad.status
        -- مأمورية/قافلة/تكليف معتمد يغطي اليوم (بيانات قديمة قبل 0429)
        when exists (
          select 1 from public.missions m join public.requests r on r.id = m.request_id
          where m.employee_id = e.id and r.status = 'approved'
            and v_today between (m.start_at at time zone 'Africa/Cairo')::date and (m.end_at at time zone 'Africa/Cairo')::date
        ) then 'on_leave'
        when exists (
          select 1 from public.convoy_requests c join public.requests r on r.id = c.request_id
          where c.employee_id = e.id and r.status = 'approved'
            and v_today between (c.departure_at at time zone 'Africa/Cairo')::date and (coalesce(c.return_at,c.departure_at) at time zone 'Africa/Cairo')::date
        ) then 'on_leave'
        when exists (
          select 1 from public.work_assignment_participants wp join public.work_assignments wa on wa.id = wp.assignment_id
          where wp.employee_id = e.id and wa.status = 'APPROVED' and coalesce(wa.counts_as_work_day,true)
            and v_today between (wa.start_at at time zone 'Africa/Cairo')::date and (wa.end_at at time zone 'Africa/Cairo')::date
        ) then 'on_leave'
        -- إجازة معتمدة تغطي اليوم (بيانات قديمة)
        when exists (
          select 1 from public.leave_requests lr join public.requests r on r.id = lr.request_id
          where lr.employee_id = e.id and r.status = 'approved'
            and v_today between lr.start_date and lr.end_date
        ) then 'on_leave'
        else 'absent'
      end
    ) order by e.full_name_ar)
    from public.employees e
    left join public.job_titles  jt on jt.id = e.job_title_id
    left join public.departments d  on d.id  = e.department_id
    left join public.attendance_daily ad on ad.employee_id = e.id and ad.work_date = v_today
    where e.is_active  = true
      and e.is_deleted = false
      and (
        v_search is null
        or e.full_name_ar  ilike '%' || v_search || '%'
        or e.employee_code ilike '%' || v_search || '%'
        or jt.name         ilike '%' || v_search || '%'
        or d.name          ilike '%' || v_search || '%'
      )
    limit greatest(1, least(coalesce(p_limit, 40), 100))
  ), '[]'::jsonb);
end;
$$;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 4) المأمورية/القافلة المعتمدة: تسجيل أيامها كأيام عمل معتمدة (on_leave — لا غياب)
--    + منح بدل الراحة الأسبوعي عن أي جمعة ضمن الفترة (بدون خصم من الرصيد)
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.tg_leave_attendance_on_approval()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_lr public.leave_requests; v_day date; v_end date; v_start date; v_emp uuid;
  v_start_ts timestamptz; v_end_ts timestamptz;
  v_type_id uuid; v_year integer;
begin
  if old.status = new.status then return new; end if;

  -- الإجازة المعتمدة → on_leave لكل أيامها (كما كان قبل 0429)
  if new.request_type = 'leave' and new.status = 'approved' then
    select * into v_lr from public.leave_requests where request_id = new.id;
    if not found then return new; end if;
    v_day := v_lr.start_date;
    while v_day <= v_lr.end_date loop
      insert into public.attendance_daily(employee_id, work_date, status)
      values(v_lr.employee_id, v_day, 'on_leave')
      on conflict on constraint attendance_daily_uq do update
        set status = 'on_leave', updated_at = now()
        where public.attendance_daily.is_finalized = false
          and public.attendance_daily.status <> 'on_leave';
      v_day := v_day + 1;
    end loop;
    perform public.log_audit_event(
      'leave.attendance.marked', 'workflow', 'info', 'attendance_daily', v_lr.employee_id,
      'وسم أيام الإجازة المعتمدة في الحضور',
      format('من %s إلى %s', v_lr.start_date, v_lr.end_date),
      jsonb_build_object('requestId', new.id));
    return new;
  end if;

  -- المأمورية/القافلة المعتمدة: أيام عمل معتمدة (لا غياب) + بدل الجمعة — بلا خصم رصيد
  if new.request_type in ('mission','convoy') and new.status = 'approved' then
    if new.request_type = 'mission' then
      select employee_id, start_at, end_at into v_emp, v_start_ts, v_end_ts
      from public.missions where request_id = new.id;
    else
      select employee_id, departure_at, coalesce(return_at, departure_at) into v_emp, v_start_ts, v_end_ts
      from public.convoy_requests where request_id = new.id;
    end if;
    if v_emp is null then return new; end if; -- لا تفاصيل فترة — نخرج بلا تسجيل
    v_start := (v_start_ts at time zone 'Africa/Cairo')::date;
    v_end := (v_end_ts at time zone 'Africa/Cairo')::date;
    v_day := v_start;
    while v_day <= v_end loop
      insert into public.attendance_daily(employee_id, work_date, status)
      values(v_emp, v_day, 'on_leave')
      on conflict on constraint attendance_daily_uq do update
        set status = 'on_leave', updated_at = now()
        where public.attendance_daily.is_finalized = false
          and public.attendance_daily.status <> 'on_leave';
      -- بدل الراحة الأسبوعي: الجمعة ضمن مأمورية/قافلة معتمدة
      if extract(isodow from v_day) = 5 then
        select id into v_type_id from public.leave_types where code = 'weekly_rest_comp';
        if v_type_id is not null then
          v_year := extract(year from v_day)::integer;
          perform public.apply_leave_ledger_entry(
            v_emp, v_type_id, v_year, 'credit', 1,
            'weekly-rest:credit:' || v_emp::text || ':' || v_day::text,
            null,
            'رصيد بدل راحة أسبوعي عن ' || new.request_type || ' يوم الجمعة ' || to_char(v_day, 'YYYY-MM-DD'),
            jsonb_build_object('workDate', v_day::text, 'source', new.request_type, 'requestId', new.id)
          );
        end if;
      end if;
      v_day := v_day + 1;
    end loop;
    perform public.log_audit_event(
      'leave.attendance.marked', 'workflow', 'info', 'attendance_daily', v_emp,
      'وسم أيام ' || new.request_type || ' المعتمدة في الحضور (لا غياب)',
      format('من %s إلى %s', v_start, v_end),
      jsonb_build_object('requestId', new.id, 'kind', new.request_type));
    return new;
  end if;

  return new;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 5) تكليفات العمل (work_assignments — مأمورية/قافلة/فاندي): المشاركون أيام معتمدة
--    + بدل الجمعة + تراجع عند الإلغاء/الرفض بعد الاعتماد (للأيام غير المثبتة فقط)
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.tg_work_assignment_attendance_link()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_p record; v_day date; v_end date; v_type_id uuid; v_year integer; v_emp uuid;
begin
  if old is not null and old.status = new.status then return new; end if;

  -- اعتماد (بما فيه الإنشاء بحالة APPROVED من create_work_assignment)
  if new.status = 'APPROVED' then
    for v_p in
      select employee_id from public.work_assignment_participants where assignment_id = new.id
      union select new.responsible_employee_id where new.responsible_employee_id is not null
    loop
      v_emp := v_p.employee_id;
      v_day := (new.start_at at time zone 'Africa/Cairo')::date;
      v_end := (new.end_at at time zone 'Africa/Cairo')::date;
      while v_day <= v_end loop
        if coalesce(new.counts_as_work_day, true) then
          insert into public.attendance_daily(employee_id, work_date, status)
          values(v_emp, v_day, 'on_leave')
          on conflict on constraint attendance_daily_uq do update
            set status = 'on_leave', updated_at = now()
            where public.attendance_daily.is_finalized = false
              and public.attendance_daily.status <> 'on_leave';
        end if;
        -- بدل الراحة الأسبوعي عن الجمعة ضمن التكليف
        if extract(isodow from v_day) = 5 then
          select id into v_type_id from public.leave_types where code = 'weekly_rest_comp';
          if v_type_id is not null then
            v_year := extract(year from v_day)::integer;
            perform public.apply_leave_ledger_entry(
              v_emp, v_type_id, v_year, 'credit', 1,
              'weekly-rest:credit:' || v_emp::text || ':' || v_day::text,
              null,
              'رصيد بدل راحة أسبوعي عن تكليف عمل يوم الجمعة ' || to_char(v_day, 'YYYY-MM-DD'),
              jsonb_build_object('workDate', v_day::text, 'source', 'work-assignment', 'assignmentId', new.id)
            );
          end if;
        end if;
        v_day := v_day + 1;
      end loop;
    end loop;
    return new;
  end if;

  -- إلغاء/رفض بعد اعتماد: تراجع عن الأيام غير المثبتة ما لم يغطّها اعتماد آخر
  if old.status = 'APPROVED' and new.status in ('REJECTED','CANCELLED') then
    for v_p in
      select employee_id from public.work_assignment_participants where assignment_id = new.id
      union select new.responsible_employee_id where new.responsible_employee_id is not null
    loop
      v_emp := v_p.employee_id;
      v_day := (new.start_at at time zone 'Africa/Cairo')::date;
      v_end := (new.end_at at time zone 'Africa/Cairo')::date;
      while v_day <= v_end loop
        update public.attendance_daily ad
        set status = 'absent', updated_at = now()
        where ad.employee_id = v_emp and ad.work_date = v_day
          and ad.is_finalized = false and ad.status = 'on_leave'
          and not exists (
            select 1 from public.leave_requests lr join public.requests r on r.id = lr.request_id
            where lr.employee_id = v_emp and r.status = 'approved'
              and v_day between lr.start_date and lr.end_date)
          and not exists (
            select 1 from public.missions m join public.requests r on r.id = m.request_id
            where m.employee_id = v_emp and r.status = 'approved'
              and v_day between (m.start_at at time zone 'Africa/Cairo')::date and (m.end_at at time zone 'Africa/Cairo')::date)
          and not exists (
            select 1 from public.convoy_requests c join public.requests r on r.id = c.request_id
            where c.employee_id = v_emp and r.status = 'approved'
              and v_day between (c.departure_at at time zone 'Africa/Cairo')::date and (coalesce(c.return_at,c.departure_at) at time zone 'Africa/Cairo')::date)
          and not exists (
            select 1 from public.work_assignment_participants wp2 join public.work_assignments wa2 on wa2.id = wp2.assignment_id
            where wp2.employee_id = v_emp and wa2.status = 'APPROVED' and wa2.id <> new.id
              and v_day between (wa2.start_at at time zone 'Africa/Cairo')::date and (wa2.end_at at time zone 'Africa/Cairo')::date);
        v_day := v_day + 1;
      end loop;
    end loop;
  end if;
  return new;
end $$;

drop trigger if exists trg_work_assignment_attendance_link on public.work_assignments;
create trigger trg_work_assignment_attendance_link
  after insert or update of status on public.work_assignments
  for each row execute function public.tg_work_assignment_attendance_link();

-- ملاحظة ترتيب: create_work_assignment يُدرج التكليف ثم المشاركين بعده، فإذا أُنشئ
-- التكليف بحالة APPROVED مباشرة، trigger التكليف يشتغل قبل وجود المشاركين — لذا
-- trigger على إدراج المشارك يوسم أيامه (بما فيه بدل الجمعة — source_key يمنع التكرار).
create or replace function public.tg_work_assignment_participant_link()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_wa public.work_assignments;
  v_day date; v_end date; v_type_id uuid; v_year integer;
begin
  select * into v_wa from public.work_assignments where id = new.assignment_id;
  if not found or v_wa.status <> 'APPROVED' then return new; end if;
  v_day := (v_wa.start_at at time zone 'Africa/Cairo')::date;
  v_end := (v_wa.end_at at time zone 'Africa/Cairo')::date;
  while v_day <= v_end loop
    if coalesce(v_wa.counts_as_work_day, true) then
      insert into public.attendance_daily(employee_id, work_date, status)
      values(new.employee_id, v_day, 'on_leave')
      on conflict on constraint attendance_daily_uq do update
        set status = 'on_leave', updated_at = now()
        where public.attendance_daily.is_finalized = false
          and public.attendance_daily.status <> 'on_leave';
    end if;
    if extract(isodow from v_day) = 5 then
      select id into v_type_id from public.leave_types where code = 'weekly_rest_comp';
      if v_type_id is not null then
        v_year := extract(year from v_day)::integer;
        perform public.apply_leave_ledger_entry(
          new.employee_id, v_type_id, v_year, 'credit', 1,
          'weekly-rest:credit:' || new.employee_id::text || ':' || v_day::text,
          null,
          'رصيد بدل راحة أسبوعي عن تكليف عمل يوم الجمعة ' || to_char(v_day, 'YYYY-MM-DD'),
          jsonb_build_object('workDate', v_day::text, 'source', 'work-assignment', 'assignmentId', v_wa.id)
        );
      end if;
    end if;
    v_day := v_day + 1;
  end loop;
  return new;
end $$;

drop trigger if exists trg_work_assignment_participant_link on public.work_assignment_participants;
create trigger trg_work_assignment_participant_link
  after insert on public.work_assignment_participants
  for each row execute function public.tg_work_assignment_participant_link();

-- ═══════════════════════════════════════════════════════════════════════════════
-- 6) منح بدل راحة يدوي لأي موظف (HR/التنفيذي فقط) — يُضاف رصيد بدل عن أيام محددة
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.grant_weekly_rest_credit(
  p_employee_id uuid,
  p_work_date   date,
  p_days        integer default 1
) returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_type_id uuid;
  v_year    integer;
  v_day     date;
  v_count   integer := 0;
begin
  if not (public.current_is_full_access() or public.has_permission('requests.leave.balance.adjust')) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if p_days < 1 or p_days > 365 then
    raise exception 'INVALID_DAYS' using errcode = '22023';
  end if;
  if not exists(select 1 from public.employees where id = p_employee_id and is_active and not is_deleted) then
    raise exception 'EMPLOYEE_NOT_FOUND' using errcode = 'P0002';
  end if;
  select id into v_type_id from public.leave_types where code = 'weekly_rest_comp';
  if v_type_id is null then
    raise exception 'LEAVE_TYPE_NOT_FOUND' using errcode = 'P0002';
  end if;

  v_day := p_work_date;
  while v_count < p_days loop
    v_year := extract(year from v_day)::integer;
    perform public.apply_leave_ledger_entry(
      p_employee_id, v_type_id, v_year, 'credit', 1,
      'weekly-rest:manual:' || p_employee_id::text || ':' || v_day::text,
      null,
      'منح بدل راحة يدوي عن يوم ' || to_char(v_day, 'YYYY-MM-DD'),
      jsonb_build_object('workDate', v_day::text, 'source', 'manual-grant')
    );
    v_count := v_count + 1;
    v_day := v_day + 1;
  end loop;
  return v_count;
end $$;

revoke all on function public.grant_weekly_rest_credit(uuid, date, integer) from public, anon;
grant execute on function public.grant_weekly_rest_credit(uuid, date, integer) to authenticated;

commit;