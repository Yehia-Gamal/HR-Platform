-- ============================================================================
-- 0506_fix_rls_infinite_recursion_and_attendance_overview.sql
--
-- 1) كسر الحلقة التكرارية اللانهائية (Infinite Recursion) بين requests و request_steps:
--    - إنشاء دالتين بصلاحية SECURITY DEFINER للتحقق دون تفعيل سياسات RLS متبادلة:
--      * public.is_request_assignee_or_manager(p_request_id, p_employee_id)
--      * public.is_request_participant(p_request_id, p_employee_id)
--    - تحديث سياسات requests_select و request_steps_select و leave_requests_select
--      مع تقديم فحص الأدوار القيادية والوصول الكامل في أول التعبير لسرعة الأداء.
--
-- 2) جعل get_dashboard_overview و get_attendance_today_overview بصلاحية SECURITY DEFINER:
--    - تفادي تأثر حساب مؤشرات وإحصائيات النظام بسياسات المستخدم الفردي.
--    - توسيع فحص الصلاحية في get_attendance_today_overview ليشمل الأدوار الإدارية.
--
-- 3) تحديث get_pending_devices_admin و get_all_devices_admin:
--    - السماح لأصحاب الأدوار الإدارية (admin, hr-manager, executive) بعرض وإدارة الأجهزة.
-- ============================================================================

-- ─── 1) دوال فحص الوصول لخطوات وطلبات العمل (Security Definer) ─────────────
create or replace function public.is_request_assignee_or_manager(
  p_request_id uuid,
  p_employee_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.request_steps rs
    where rs.request_id = p_request_id
      and rs.assignee_employee_id = p_employee_id
  );
$$;

comment on function public.is_request_assignee_or_manager(uuid, uuid) is
  '0506: فحص ذري عازل لسياسات RLS — يتحقق هل الموظف مسند له خطوة في الطلب دون استدعاء متبادل.';
revoke all on function public.is_request_assignee_or_manager(uuid, uuid) from public, anon;
grant execute on function public.is_request_assignee_or_manager(uuid, uuid) to authenticated;

create or replace function public.is_request_participant(
  p_request_id uuid,
  p_employee_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.requests r
    where r.id = p_request_id
      and (
        r.employee_id = p_employee_id
        or r.manager_employee_id = p_employee_id
      )
  );
$$;

comment on function public.is_request_participant(uuid, uuid) is
  '0506: فحص ذري عازل لسياسات RLS — يتحقق هل الموظف صاحب الطلب أو مديره دون استدعاء متبادل.';
revoke all on function public.is_request_participant(uuid, uuid) from public, anon;
grant execute on function public.is_request_participant(uuid, uuid) to authenticated;

-- ─── 2) تحديث سياسات RLS بدون أي حلقة تكرارية ──────────────────────────────
drop policy if exists requests_select on public.requests;
create policy requests_select on public.requests
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.current_has_active_role(array['admin','super-admin','executive','executive-director','general-manager','hr-manager','operations-manager-1'])
    or employee_id = public.current_employee_id()
    or manager_employee_id = public.current_employee_id()
    or exists (
      select 1 from public.manager_relations mr
      where mr.employee_id = requests.employee_id
        and mr.manager_employee_id = public.current_employee_id()
        and mr.relation_type = 'primary'
        and mr.effective_from <= current_date
        and (mr.effective_to is null or mr.effective_to >= current_date)
    )
    or public.is_request_assignee_or_manager(requests.id, public.current_employee_id())
    or public.can_access_employee(employee_id, 'requests.read')
    or public.can_access_employee(employee_id, 'requests.request.read')
    or public.can_access_employee(employee_id, 'requests.approve')
    or public.can_access_employee(employee_id, 'requests.request.approve')
  );

drop policy if exists request_steps_select on public.request_steps;
create policy request_steps_select on public.request_steps
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.current_has_active_role(array['admin','super-admin','executive','executive-director','general-manager','hr-manager','operations-manager-1'])
    or assignee_employee_id = public.current_employee_id()
    or public.is_request_participant(request_steps.request_id, public.current_employee_id())
  );

drop policy if exists leave_requests_select on public.leave_requests;
create policy leave_requests_select on public.leave_requests
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.current_has_active_role(array['admin','super-admin','executive','executive-director','general-manager','hr-manager'])
    or employee_id = public.current_employee_id()
    or public.is_request_participant(leave_requests.request_id, public.current_employee_id())
    or public.can_access_employee(employee_id, 'requests.read')
  );

drop policy if exists missions_select on public.missions;
create policy missions_select on public.missions
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.current_has_active_role(array['admin','super-admin','executive','executive-director','general-manager','hr-manager','operations-manager-1'])
    or employee_id = public.current_employee_id()
    or exists (
      select 1 from public.manager_relations mr
      where mr.employee_id = missions.employee_id
        and mr.manager_employee_id = public.current_employee_id()
        and mr.relation_type = 'primary'
        and mr.effective_from <= current_date
        and (mr.effective_to is null or mr.effective_to >= current_date)
    )
    or public.can_access_employee(employee_id, 'requests.read')
  );

-- ─── 3) get_dashboard_overview (SECURITY DEFINER) ──────────────────────────
create or replace function public.get_dashboard_overview(p_workspace text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if p_workspace not in ('hr','main_admin') then
    raise exception 'مساحة عمل غير صالحة' using errcode = '22023';
  end if;
  return jsonb_build_object(
    'employees', (select count(*) from public.employees),
    'activeEmployees', (select count(*) from public.employees where status = 'active'),
    'pendingRequests', (select count(*) from public.requests where status = 'pending'),
    'attendancePendingReview', (select count(*) from public.attendance_events where requires_review = true),
    'pendingKpi', (select count(*) from public.kpi_evaluations where current_stage <> 'finalized'),
    'openRequisitions', (select count(*) from public.job_requisitions where status in ('pending','approved','posted')),
    'urgentActions', (
      select count(*) from public.requests
      where status = 'pending' and decision_due_at is not null and decision_due_at < now() + interval '4 hours'
    ),
    'publishedDecisions', (select count(*) from public.administrative_decisions where status = 'published'),
    'unresolvedErrors', case when p_workspace = 'main_admin'
      then (select count(*) from public.app_error_events where resolved = false)
      else 0 end,
    'lastUpdatedAt', now()
  );
end;
$$;

comment on function public.get_dashboard_overview(text) is
  '0506: ملخص لوحة التحكم — بصلاحية SECURITY DEFINER لضمان الحساب الإحصائي الدقيق دون تعارض RLS.';
revoke all on function public.get_dashboard_overview(text) from public, anon;
grant execute on function public.get_dashboard_overview(text) to authenticated;

-- ─── 4) get_attendance_today_overview (SECURITY DEFINER) ───────────────────
create or replace function public.get_attendance_today_overview(p_date date default current_date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_total_active int;
  v_expected int;
  v_present int;
  v_late int;
  v_on_leave int;
  v_on_assignment int;
  v_not_checked_in int;
  v_absent int;
  v_is_friday boolean := (extract(isodow from p_date) = 5);
begin
  if not (
    public.current_is_full_access()
    or public.current_has_active_role(array['admin','super-admin','executive','executive-director','general-manager','hr-manager'])
    or public.has_permission('attendance.record.read')
    or public.has_permission('people.employee.read')
    or current_user in ('postgres', 'service_role')
  ) then
    raise exception 'غير مصرح لك' using errcode = '42501';
  end if;

  -- إجمالي الموظفين النشطين (بدون التنفيذيين)
  select count(*) into v_total_active
  from public.employees e
  where e.status = 'active'
    and not exists (
      select 1 from public.user_roles ur
      join public.roles r on r.id = ur.role_id
      where ur.user_id = e.user_id
        and r.slug in ('executive','executive-director')
        and (ur.effective_from is null or ur.effective_from <= now())
        and (ur.effective_to is null or ur.effective_to > now())
    );

  -- الموظفون في إجازة معتمدة
  select count(distinct lr.employee_id) into v_on_leave
  from public.leave_requests lr
  join public.requests req on req.id = lr.request_id
  where req.status = 'approved'
    and p_date between lr.start_date and lr.end_date;

  -- الموظفون في تكليفات نشطة
  select count(distinct wa.responsible_employee_id) into v_on_assignment
  from public.work_assignments wa
  where wa.status in ('APPROVED','IN_PROGRESS')
    and p_date between wa.start_at::date and wa.end_at::date;

  -- الحاضرون اليوم
  select count(distinct ae.employee_id) into v_present
  from public.attendance_events ae
  where ae.event_at::date = p_date and ae.event_type = 'CHECK_IN';

  -- المتأخرون
  select count(distinct ae.employee_id) into v_late
  from public.attendance_events ae
  where ae.event_at::date = p_date
    and ae.event_type = 'CHECK_IN'
    and coalesce(ae.late_minutes, 0) > 0;

  if v_is_friday then
    -- الجمعة: عطلة أسبوعية رسمية — المتوقع من لديه تكليف فقط
    v_expected := coalesce(v_on_assignment, 0);
  else
    -- الأيام العادية
    v_expected := greatest(0, coalesce(v_total_active, 0) - coalesce(v_on_leave, 0) - coalesce(v_on_assignment, 0));
  end if;

  -- من لم يسجلوا بعد
  v_not_checked_in := greatest(0, coalesce(v_expected, 0) - coalesce(v_present, 0));
  v_absent := v_not_checked_in;

  return jsonb_build_object(
    'date', p_date,
    'totalActive', coalesce(v_total_active, 0),
    'expected', coalesce(v_expected, 0),
    'expectedToday', coalesce(v_expected, 0),
    'present', coalesce(v_present, 0),
    'late', coalesce(v_late, 0),
    'onLeave', coalesce(v_on_leave, 0),
    'onAssignment', coalesce(v_on_assignment, 0),
    'notCheckedIn', coalesce(v_not_checked_in, 0),
    'absent', coalesce(v_absent, 0),
    'isFriday', v_is_friday,
    'isWeekend', v_is_friday,
    'lastUpdatedAt', now(),
    'generatedAt', now()
  );
end;
$$;

comment on function public.get_attendance_today_overview(date) is
  '0507: ملخص الحضور اليومي — بصلاحية SECURITY DEFINER للأدوار الإدارية.';
revoke all on function public.get_attendance_today_overview(date) from public, anon;
grant execute on function public.get_attendance_today_overview(date) to authenticated;

-- ─── 5) تحديث دوال إدارة الأجهزة لتشمل الأدوار الإدارية المعتمدة ──────────
create or replace function public.get_pending_devices_admin()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', d.id,
    'employeeId', d.employee_id,
    'employeeName', coalesce(e.full_name_ar, e.full_name_en, 'موظف'),
    'employeeCode', e.employee_code,
    'employeePhotoUrl', e.photo_url,
    'deviceName', coalesce(d.device_name, d.platform),
    'platform', d.platform,
    'status', d.status,
    'registeredAt', d.registered_at,
    'lastUsedAt', d.last_used_at,
    'rejectionReason', d.rejection_reason,
    'revocationSource', d.revocation_source,
    'metadata', d.metadata
  ) order by d.registered_at desc), '[]'::jsonb)
  from public.employee_devices d
  join public.employees e on e.id = d.employee_id
  where d.status in ('pending', 'blocked')
    and (
      public.current_is_full_access()
      or public.current_has_active_role(array['admin','super-admin','executive','executive-director','general-manager','hr-manager'])
      or public.has_permission('access.role.read')
    );
$$;

comment on function public.get_pending_devices_admin() is
  '0506: جلب الأجهزة المعلّقة والمحظورة للأدوار الإدارية والـ HR.';
revoke all on function public.get_pending_devices_admin() from public, anon;
grant execute on function public.get_pending_devices_admin() to authenticated;

create or replace function public.get_all_devices_admin(
  p_status_filter text default null::text,
  p_include_terminated boolean default false
)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case
    when not (
      public.current_is_full_access()
      or public.current_has_active_role(array['admin','super-admin','executive','executive-director','general-manager','hr-manager'])
      or public.has_permission('access.role.read')
    ) then '[]'::jsonb
    else coalesce(jsonb_agg(jsonb_build_object(
      'id', d.id,
      'employeeId', d.employee_id,
      'employeeName', coalesce(e.full_name_ar, e.full_name_en, 'موظف'),
      'employeeCode', e.employee_code,
      'employeePhotoUrl', e.photo_url,
      'deviceName', coalesce(d.device_name, d.platform),
      'platform', d.platform,
      'status', d.status,
      'registeredAt', d.registered_at,
      'lastUsedAt', d.last_used_at,
      'revokedAt', d.revoked_at,
      'revocationSource', d.revocation_source,
      'approvedBy', d.approved_by,
      'rejectionReason', d.rejection_reason,
      'metadata', d.metadata
    ) order by d.registered_at desc), '[]'::jsonb)
  end
  from public.employee_devices d
  join public.employees e on e.id = d.employee_id
  where (p_status_filter is null or d.status = p_status_filter)
    and (
      p_include_terminated = true
      or d.status in ('pending', 'active', 'blocked')
    );
$$;

comment on function public.get_all_devices_admin(text, boolean) is
  '0506: جلب كافة أجهزة الموظفين للأدوار الإدارية والـ HR.';
revoke all on function public.get_all_devices_admin(text, boolean) from public, anon;
grant execute on function public.get_all_devices_admin(text, boolean) to authenticated;
