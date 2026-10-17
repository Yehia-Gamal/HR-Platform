-- ==============================================================================
-- Migration 0679: Order Employees by Administrative Hierarchy & Clinic Isolation
-- ==============================================================================
-- المطلوب:
-- 1) ترتيب عرض الموظفين في كافة القوائم والهيكل الإداري:
--    الرتبة 1: الشيخ محمد يوسف (على رأس الهيكل الإداري)
--    الرتبة 2: يحيى السبع (السكرتير التنفيذي)
--    الرتبة 3: أبو عمار (محمد عبدالباسط - مدير تشغيل / أوبريشن 1)
--    الرتبة 4: ياسر (ياسر فتحي نور الدين - مدير تشغيل / أوبريشن 2)
--    الرتبة 5: باقي المديرين (بما فيهم مديرا العيادات مصطفى أحمد ويوسف رسمي)
--    الرتبة 6: باقي الموظفين
--    الرتبة 7: تيم البنات بتوع الطاقم الطبي (آخر شيء خالص)
-- 2) تيم البنات بتوع الطاقم الطبي لا يظهرون لأي أحد غير مديرهم مصطفى أحمد،
--    ويوسف رسمي، ويحيى، والشيخ محمد، والإدارة العليا.
-- 3) إدراج الشيخ محمد يوسف في دليل الموظفين التنفيذي (get_mobile_executive_people)
--    على رأس القائمة دائماً وتطبيق عزل العيادات.
-- ==============================================================================

begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) دالة مساعدة مركزية لحساب رتبة الهيكل الإداري
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.get_employee_hierarchy_rank(
  p_name text,
  p_job_title text,
  p_department text
)
returns integer
language plpgsql
immutable
as $function$
declare
  n text := coalesce(trim(p_name), '');
  t text := lower(coalesce(trim(p_job_title), ''));
  d text := lower(coalesce(trim(p_department), ''));
  v_is_med_mgr boolean;
begin
  -- 1 — الشيخ محمد يوسف
  if n ilike '%الشيخ محمد%' or n ilike '%ألشيخ محمد%'
     or n = 'محمد يوسف' or n ilike 'محمد يوسف %'
     or t ilike '%مدير تنفيذي%' or (t ilike '%مدير%' and t ilike '%تنفيذي%')
     or t = 'ceo' or t ilike '%chief executive%' then
    return 1;
  end if;

  -- 2 — يحيى السبع
  if n ilike '%يحيى%' or n ilike '%يحيي%' or n ilike '%السبع%'
     or t ilike '%سكرتير%' or t ilike '%المساعد التنفيذي%'
     or t ilike '%executive secretary%' or t ilike '%executive assistant%' then
    return 2;
  end if;

  -- 3 — أبو عمار
  if n ilike '%ابو عمار%' or n ilike '%أبو عمار%'
     or n ilike 'محمد عبدالباسط%' or n ilike 'محمد عبد الباسط%'
     or ((t ilike '%أوبريشن%' or t ilike '%تشغيل%' or t ilike '%operations%') and (t ilike '%1%' or t ilike '%أول%' or t ilike '%رئيسي%')) then
    return 3;
  end if;

  -- 4 — ياسر
  if n ilike '%ياسر%'
     or ((t ilike '%أوبريشن%' or t ilike '%تشغيل%' or t ilike '%operations%') and (t ilike '%2%' or t ilike '%ثاني%' or t ilike '%مساعد%')) then
    return 4;
  end if;

  -- هل هو من مديري العيادات؟ (مصطفى أحمد كمال الدين، يوسف رسمي شعبان)
  v_is_med_mgr := n ilike '%مصطفي%أحمد%' or n ilike '%مصطفى%أحمد%' or n ilike '%يوسف%رسمي%'
                  or t ilike '%مدير مجمع%' or (d ilike '%عياد%' and t ilike '%مدير%');

  -- 7 — تيم البنات بتوع الطاقم الطبي (آخر شيء خالص)
  if not v_is_med_mgr then
    if d ilike '%عياد%'
       or t ilike '%تمريض%' or t ilike '%معمل%' or t ilike '%دكتورة المعمل%' or t ilike '%استقبال%'
       or n ilike '%رحاب مجدي%' or n ilike '%ساميه%' or n ilike '%سامية%' or n ilike '%سمر احمد%' or n ilike '%سمر أحمد%'
       or n ilike '%سميرة سعيد%' or n ilike '%سميره سعيد%' or n ilike '%شروق عبد العليم%' or n ilike '%شروق عبدالعليم%' then
      return 7;
    end if;
  end if;

  -- 5 — باقي المديرين
  if t ilike '%مدير%' or t ilike '%manager%' or t ilike '%head%' or t ilike '%lead%'
     or t ilike '%director%' or t ilike '%رئيس%' or t ilike '%نائب%' or t ilike '%وكيل%'
     or v_is_med_mgr then
    return 5;
  end if;

  -- 6 — باقي الموظفين
  return 6;
end;
$function$;

revoke execute on function public.get_employee_hierarchy_rank(text, text, text) from public, anon;
grant execute on function public.get_employee_hierarchy_rank(text, text, text) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) تحديث can_view_isolated_employee لضمان رؤية المصرح لهم فقط
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.can_view_isolated_employee(p_target uuid)
returns boolean
language plpgsql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_me uuid := public.current_employee_id();
  v_me_name text;
begin
  if not public.is_employee_isolated(p_target) then return true; end if;
  if public.current_can_view_all_employees() then return true; end if;
  if v_me is null then return false; end if;

  -- 1) الشيخ محمد يوسف
  if v_me = '7b0740fa-66ba-4616-8674-3dbd8e14109e'::uuid then
    return true;
  end if;

  -- 2) مديرا العيادات: مصطفى أحمد ويوسف رسمي
  if v_me in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid) then
    return true;
  end if;

  -- 3) فحص بالاسم (الشيخ محمد، يحيى، مصطفى أحمد، يوسف رسمي)
  select full_name_ar into v_me_name from public.employees where id = v_me;
  if v_me_name ilike '%محمد يوسف%' or v_me_name ilike '%يحيى%' or v_me_name ilike '%مصطفي%أحمد%' or v_me_name ilike '%مصطفى%أحمد%' or v_me_name ilike '%يوسف%رسمي%' then
    return true;
  end if;

  -- 4) زميل القسم (عزل إداري فقط)
  if exists (
    select 1
      from public.employees t
      join public.departments d on d.id = t.department_id
     where t.id = p_target
       and d.is_isolated
       and t.department_id = (select e.department_id from public.employees e where e.id = v_me)
  ) then return true; end if;

  -- 5) المدير المباشر (علاقة إشراف سارية)
  if exists (
    select 1 from public.manager_relations mr
     where mr.employee_id = p_target
       and mr.manager_employee_id = v_me
       and mr.effective_from <= now()
       and (mr.effective_to is null or mr.effective_to > now())
  ) then return true; end if;

  return false;
end $function$;

revoke execute on function public.can_view_isolated_employee(uuid) from public, anon;
grant execute on function public.can_view_isolated_employee(uuid) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) تحديث get_mobile_executive_people (إدراج التنفيذي + عزل العيادات + ترتيب الهيكل)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.get_mobile_executive_people(
  p_search text default null::text,
  p_limit integer default 80
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
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
    raise exception 'وصول الموظفين التنفيذي مرفوض' using errcode = '42501';
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
    ) order by x.rank, x.full_name_ar)
    from (
      select e.id, e.employee_code, e.full_name_ar, e.photo_url,
        jt.name job_title, d.name department, tm.name team,
        ad.status attendance_status,
        public.get_employee_hierarchy_rank(e.full_name_ar, jt.name, d.name) as rank,
        (select count(*) from public.requests r where r.employee_id = e.id and r.status = 'pending') pending_requests,
        (select count(*) from public.tasks t where t.assignee_employee_id = e.id and t.status in ('pending','in_progress')) open_tasks,
        (select ke.final_score from public.kpi_evaluations ke join public.kpi_cycles kc on kc.id = ke.cycle_id where ke.employee_id = e.id order by kc.period_month desc, ke.created_at desc limit 1) latest_kpi_score
      from public.employees e
      left join public.job_titles jt on jt.id = e.job_title_id
      left join public.departments d on d.id = e.department_id
      left join public.teams tm on tm.id = e.team_id
      left join public.attendance_daily ad on ad.employee_id = e.id and ad.work_date = v_today
      where e.is_active = true and e.is_deleted = false
        and (
          not public.is_employee_isolated(e.id)
          or public.can_view_isolated_employee(e.id)
        )
        and public.can_access_employee(e.id, 'people.employee.read')
        and (v_search is null or e.full_name_ar ilike '%' || public.escape_ilike(v_search) || '%' or e.employee_code ilike '%' || public.escape_ilike(v_search) || '%')
      order by public.get_employee_hierarchy_rank(e.full_name_ar, jt.name, d.name), e.full_name_ar
      limit greatest(1, least(coalesce(p_limit, 80), 120))
    ) x
  ), '[]'::jsonb);
end;
$function$;

revoke all on function public.get_mobile_executive_people(text, integer) from public, anon;
grant execute on function public.get_mobile_executive_people(text, integer) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4) تحديث get_mobile_employee_directory (ترتيب الهيكل + عزل العيادات)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.get_mobile_employee_directory(
  p_search text default null::text,
  p_limit  integer default 40
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_search text := nullif(trim(coalesce(p_search, '')), '');
  v_norm_search text := null;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
begin
  if auth.uid() is null then
    raise exception 'غير مسجل الدخول' using errcode = '42501';
  end if;

  if v_search is not null then
    v_norm_search := translate(lower(v_search), 'أإآ', 'ااا');
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',               e.id,
      'name',             e.full_name_ar,
      'employeeCode',     e.employee_code,
      'photoUrl',         e.photo_url,
      'jobTitle',         jt.name,
      'department',       d.name,
      'statusToday',      case
        when public.is_employee_attendance_exempt(e.id) then 'exempt'
        when req.request_type = 'convoy' then 'convoy'
        when req.request_type = 'fundraising' then 'fundraising'
        when req.request_type = 'mission' then 'mission'
        when req.request_type = 'leave' then 'on_leave'
        when ad.status = 'on_leave' then 'on_leave'
        when ad.status in ('weekend','holiday') then ad.status
        when coalesce(ad.first_check_in, ae.event_at) is not null then
          case
            when ad.status = 'present'
              or coalesce(ad.work_minutes, 0) >= 480
              or (
                ad.first_check_in is not null and ad.last_check_out is not null
                and extract(epoch from (ad.last_check_out - ad.first_check_in)) >= 28800
              )
              or (
                ad.last_check_out is null
                and extract(epoch from ((now() at time zone 'Africa/Cairo') - coalesce(ad.first_check_in, ae.event_at))) >= 28800
              )
            then 'present'
            when ad.status = 'late' or coalesce(ad.late_minutes, 0) > 0 then 'late'
            else 'present'
          end
        when ad.status = 'absent' then 'absent'
        else 'not_recorded'
      end,
      'statusTodayLabel', case
        when public.is_employee_attendance_exempt(e.id) then 'معفى من البصمة'
        when req.request_type = 'convoy' then 'في قافلة'
        when req.request_type = 'fundraising' then 'في فاندي'
        when req.request_type = 'mission' then 'في مأمورية'
        when req.request_type = 'leave' then 'في إجازة'
        when ad.status = 'on_leave' then 'في إجازة'
        when ad.status = 'weekend' then 'إجازة أسبوعية'
        when ad.status = 'holiday' then 'عطلة رسمية'
        when coalesce(ad.first_check_in, ae.event_at) is not null then
          case
            when ad.status = 'present'
              or coalesce(ad.work_minutes, 0) >= 480
              or (
                ad.first_check_in is not null and ad.last_check_out is not null
                and extract(epoch from (ad.last_check_out - ad.first_check_in)) >= 28800
              )
              or (
                ad.last_check_out is null
                and extract(epoch from ((now() at time zone 'Africa/Cairo') - coalesce(ad.first_check_in, ae.event_at))) >= 28800
              )
            then
              case
                when coalesce(ad.work_minutes, 0) > 480 or coalesce(ad.overtime_minutes, 0) > 0 then 'حاضر (إضافي)'
                else 'حاضر'
              end
            when ad.status = 'late' or coalesce(ad.late_minutes, 0) > 0 then 'متأخر'
            else 'حاضر'
          end
        when ad.status = 'absent' then 'غائب'
        else 'لم يسجل'
      end,
      'activityTitle',    req.activity_title
    ) order by public.get_employee_hierarchy_rank(e.full_name_ar, jt.name, d.name), e.full_name_ar)
    from public.employees e
    left join public.job_titles  jt on jt.id = e.job_title_id
    left join public.departments d  on d.id  = e.department_id
    left join lateral (
      select 
        r.request_type,
        coalesce(nullif(r.payload->>'location',''), nullif(r.payload->>'destination',''), nullif(r.title,'')) as activity_title
      from public.requests r
      where r.employee_id = e.id
        and r.status in ('approved', 'pending')
        and r.request_type in ('convoy', 'fundraising', 'mission', 'leave')
        and v_today between 
            coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date, r.created_at::date)
        and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date, r.created_at::date)
      order by case when r.status = 'approved' then 1 else 2 end,
               case r.request_type 
                 when 'convoy' then 1
                 when 'fundraising' then 2
                 when 'mission' then 3
                 when 'leave' then 4
                 else 5
               end,
               r.created_at desc
      limit 1
    ) req on true
    left join public.attendance_daily ad on ad.employee_id = e.id and ad.work_date = v_today
    left join lateral (
      select min(event_at) as event_at
      from public.attendance_events
      where employee_id = e.id and event_type = 'CHECK_IN'
        and (event_at at time zone 'Africa/Cairo')::date = v_today
        and status in ('accepted', 'adjusted')
    ) ae on true
    where e.is_active = true
      and e.is_deleted = false
      and (
        not public.is_employee_isolated(e.id)
        or public.can_view_isolated_employee(e.id)
      )
      and (
        v_search is null
        or lower(e.full_name_ar) like '%' || lower(v_search) || '%'
        or (v_norm_search is not null and translate(lower(e.full_name_ar), 'أإآ', 'ااا') like '%' || v_norm_search || '%')
        or lower(coalesce(e.full_name_en, '')) like '%' || lower(v_search) || '%'
        or lower(e.employee_code) like '%' || lower(v_search) || '%'
        or lower(coalesce(d.name, '')) like '%' || lower(v_search) || '%'
        or lower(coalesce(jt.name, '')) like '%' || lower(v_search) || '%'
      )
    limit greatest(1, least(coalesce(p_limit, 40), 100))
  ), '[]'::jsonb);
end;
$function$;

revoke all on function public.get_mobile_employee_directory(text, integer) from public, anon;
grant execute on function public.get_mobile_employee_directory(text, integer) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5) تحديث get_employees_enriched (ترتيب الهيكل الإداري)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.get_employees_enriched(
  p_search text default null::text,
  p_status text default null::text,
  p_limit integer default 200
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_search text := nullif(trim(lower(coalesce(p_search, ''))), '');
  v_norm_search text := null;
  v_is_org_admin boolean := false;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
begin
  if auth.uid() is null then
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  if v_search is not null then
    v_norm_search := translate(v_search, 'أإآ', 'ااا');
  end if;

  v_is_org_admin := public.current_is_full_access()
    or public.has_permission('organization.org_chart.read');

  return coalesce((
    select jsonb_agg(row_data order by (row_data->>'hierarchyRank')::integer, row_data->>'fullNameAr')
    from (
      select jsonb_build_object(
        'id', e.id,
        'employeeCode', e.employee_code,
        'fullNameAr', e.full_name_ar,
        'fullNameEn', e.full_name_en,
        'hierarchyRank', public.get_employee_hierarchy_rank(e.full_name_ar, jt.name, d.name),
        'phoneE164', e.phone_e164,
        'status', e.status,
        'isActive', e.is_active,
        'photoUrl', e.photo_url,
        'departmentId', e.department_id,
        'department', coalesce(
          (
            select string_agg(d_sub.name, ' / ' order by ed_sub.is_primary desc, d_sub.name)
            from public.employee_departments ed_sub
            join public.departments d_sub on d_sub.id = ed_sub.department_id
            where ed_sub.employee_id = e.id
          ),
          d.name
        ),
        'teamId', e.team_id,
        'team', t.name,
        'branchId', e.branch_id,
        'branch', b.name,
        'jobTitle', jt.name,
        'createdAt', e.created_at,
        'statusToday', case
          when public.is_employee_attendance_exempt(e.id) then 'exempt'
          when req.request_type = 'convoy' then 'convoy'
          when req.request_type = 'fundraising' then 'fundraising'
          when req.request_type = 'mission' then 'mission'
          when req.request_type = 'leave' then 'on_leave'
          when ad.status = 'on_leave' then 'on_leave'
          when ad.status in ('weekend','holiday') then ad.status
          when coalesce(ad.first_check_in, ae.event_at) is not null then
            case
              when ad.status = 'present'
                or coalesce(ad.work_minutes, 0) >= 480
                or (
                  ad.first_check_in is not null and ad.last_check_out is not null
                  and extract(epoch from (ad.last_check_out - ad.first_check_in)) >= 28800
                )
                or (
                  ad.last_check_out is null
                  and extract(epoch from ((now() at time zone 'Africa/Cairo') - coalesce(ad.first_check_in, ae.event_at))) >= 28800
                )
              then 'present'
              when ad.status = 'late' or coalesce(ad.late_minutes, 0) > 0 then 'late'
              else 'present'
            end
          when ad.status = 'absent' then 'absent'
          else 'not_recorded'
        end,
        'statusTodayLabel', case
          when public.is_employee_attendance_exempt(e.id) then 'معفى من البصمة'
          when req.request_type = 'convoy' then 'في قافلة'
          when req.request_type = 'fundraising' then 'في فاندي'
          when req.request_type = 'mission' then 'في مأمورية'
          when req.request_type = 'leave' then 'في إجازة'
          when ad.status = 'on_leave' then 'في إجازة'
          when ad.status = 'weekend' then 'إجازة أسبوعية'
          when ad.status = 'holiday' then 'عطلة رسمية'
          when coalesce(ad.first_check_in, ae.event_at) is not null then
            case
              when ad.status = 'present'
                or coalesce(ad.work_minutes, 0) >= 480
                or (
                  ad.first_check_in is not null and ad.last_check_out is not null
                  and extract(epoch from (ad.last_check_out - ad.first_check_in)) >= 28800
                )
                or (
                  ad.last_check_out is null
                  and extract(epoch from ((now() at time zone 'Africa/Cairo') - coalesce(ad.first_check_in, ae.event_at))) >= 28800
                )
              then
                case
                  when coalesce(ad.work_minutes, 0) > 480 or coalesce(ad.overtime_minutes, 0) > 0 then 'حاضر (إضافي)'
                  else 'حاضر'
                end
              when ad.status = 'late' or coalesce(ad.late_minutes, 0) > 0 then 'متأخر'
              else 'حاضر'
            end
          when ad.status = 'absent' then 'غائب'
          else 'لم يسجل بعد'
        end,
        'activityTitle', req.activity_title,
        'workMinutes', coalesce(ad.work_minutes, 0),
        'overtimeMinutes', coalesce(ad.overtime_minutes, case when coalesce(ad.work_minutes, 0) > 480 then coalesce(ad.work_minutes, 0) - 480 else 0 end),
        'lateMinutes', case
          when public.is_employee_attendance_exempt(e.id) then 0
          when ad.status = 'present' or coalesce(ad.work_minutes, 0) >= 480 then 0
          else coalesce(ad.late_minutes, 0)
        end,
        'firstCheckIn', coalesce(ad.first_check_in, ae.event_at),
        'lastCheckOut', ad.last_check_out
      ) as row_data
      from public.employees e
      left join public.departments d on d.id = e.department_id
      left join public.teams t on t.id = e.team_id
      left join public.branches b on b.id = e.branch_id
      left join public.job_titles jt on jt.id = e.job_title_id
      left join lateral (
        select 
          r.request_type,
          coalesce(nullif(r.payload->>'location',''), nullif(r.payload->>'destination',''), nullif(r.title,'')) as activity_title
        from public.requests r
        where r.employee_id = e.id
          and r.status in ('approved', 'pending')
          and r.request_type in ('convoy', 'fundraising', 'mission', 'leave')
          and v_today between 
              coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date, r.created_at::date)
          and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date, r.created_at::date)
        order by case when r.status = 'approved' then 1 else 2 end,
                 case r.request_type 
                   when 'convoy' then 1
                   when 'fundraising' then 2
                   when 'mission' then 3
                   when 'leave' then 4
                   else 5
                 end,
                 r.created_at desc
        limit 1
      ) req on true
      left join public.attendance_daily ad on ad.employee_id = e.id and ad.work_date = v_today
      left join lateral (
        select min(event_at) as event_at
        from public.attendance_events
        where employee_id = e.id and event_type = 'CHECK_IN'
          and (event_at at time zone 'Africa/Cairo')::date = v_today
          and status in ('accepted', 'adjusted')
      ) ae on true
      where e.is_deleted = false
        and (
          not public.is_employee_isolated(e.id)
          or public.can_view_isolated_employee(e.id)
        )
        and (p_status is null or e.status = p_status)
        and (
          v_search is null
          or lower(e.full_name_ar) like '%' || v_search || '%'
          or (v_norm_search is not null and translate(lower(e.full_name_ar), 'أإآ', 'ااا') like '%' || v_norm_search || '%')
          or lower(coalesce(e.full_name_en, '')) like '%' || v_search || '%'
          or lower(e.employee_code) like '%' || v_search || '%'
          or e.phone_e164 like '%' || v_search || '%'
          or lower(coalesce(d.name, '')) like '%' || v_search || '%'
          or exists (
            select 1 from public.employee_departments ed_srch
            join public.departments d_srch on d_srch.id = ed_srch.department_id
            where ed_srch.employee_id = e.id and lower(d_srch.name) like '%' || v_search || '%'
          )
        )
        and (
          v_is_org_admin
          or public.can_access_employee(e.id, 'people.employee.read')
        )
      order by public.get_employee_hierarchy_rank(e.full_name_ar, jt.name, d.name), e.full_name_ar
      limit greatest(1, least(coalesce(p_limit, 200), 500))
    ) q
  ), '[]'::jsonb);
end;
$function$;

revoke all on function public.get_employees_enriched(text, text, integer) from public, anon;
grant execute on function public.get_employees_enriched(text, text, integer) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6) تحديث get_admin_org_chart (ترتيب أبناء الشجرة بالهيكل الإداري)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.get_admin_org_chart()
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_uid uuid := auth.uid();
  v_me uuid;
  v_result jsonb;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  begin
    v_me := public.current_employee_id();
  exception when others then
    v_me := null;
  end;

  if not (
    public.current_is_full_access()
    or public.has_permission('organization.org_chart.read')
    or (v_me is not null and not public.employee_blocks_inbound_alerts(v_me))
  ) then
    raise exception 'ERR_FORBIDDEN' using errcode = '42501';
  end if;

  with recursive
  emp_base as (
    select
      e.id,
      e.full_name_ar,
      e.full_name_en,
      e.photo_url,
      coalesce(jt.name, jt.name_en, '') as job_title,
      coalesce(d.name, '') as department_name,
      e.employee_code,
      e.department_id,
      e.status,
      e.is_active,
      e.is_deleted,
      public.get_employee_hierarchy_rank(e.full_name_ar, jt.name, d.name) as hierarchy_rank
    from public.employees e
    left join public.job_titles jt on jt.id = e.job_title_id
    left join public.departments d on d.id = e.department_id
    where e.is_deleted = false
      and e.status not in ('terminated', 'draft')
      and not (
        public.is_employee_isolated(e.id)
        and not public.can_view_isolated_employee(e.id)
      )
  ),
  active_primary_managers as (
    select
      mr.employee_id,
      mr.manager_employee_id
    from public.manager_relations mr
    where mr.relation_type = 'primary'
      and mr.effective_to is null
      and mr.employee_id in (select id from emp_base)
      and mr.manager_employee_id in (select id from emp_base)
  ),
  org_tree as (
    select
      eb.id,
      eb.full_name_ar,
      eb.full_name_en,
      eb.photo_url,
      eb.job_title,
      eb.department_name,
      eb.employee_code,
      eb.department_id,
      eb.status,
      eb.is_active,
      eb.hierarchy_rank,
      null::uuid as manager_employee_id,
      0 as depth,
      array[eb.id]::uuid[] as path
    from emp_base eb
    left join active_primary_managers apm on apm.employee_id = eb.id
    where apm.employee_id is null

    union all

    select
      eb.id,
      eb.full_name_ar,
      eb.full_name_en,
      eb.photo_url,
      eb.job_title,
      eb.department_name,
      eb.employee_code,
      eb.department_id,
      eb.status,
      eb.is_active,
      eb.hierarchy_rank,
      apm.manager_employee_id,
      ot.depth + 1,
      ot.path || eb.id
    from emp_base eb
    join active_primary_managers apm on apm.employee_id = eb.id
    join org_tree ot on ot.id = apm.manager_employee_id
    where not eb.id = any(ot.path)
  ),
  direct_counts as (
    select
      manager_employee_id as emp_id,
      count(*) as direct_reports_count
    from active_primary_managers
    group by manager_employee_id
  )
  select jsonb_build_object(
    'employees', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id,
        'fullNameAr', t.full_name_ar,
        'fullNameEn', t.full_name_en,
        'photoUrl', t.photo_url,
        'jobTitle', t.job_title,
        'departmentName', t.department_name,
        'employeeCode', t.employee_code,
        'departmentId', t.department_id,
        'status', t.status,
        'isActive', t.is_active,
        'hierarchyRank', t.hierarchy_rank,
        'managerEmployeeId', t.manager_employee_id,
        'directReportsCount', coalesce(dc.direct_reports_count, 0),
        'depth', t.depth,
        'path', t.path
      ) order by t.path, t.hierarchy_rank, t.full_name_ar)
      from org_tree t
      left join direct_counts dc on dc.emp_id = t.id
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$function$;

revoke all on function public.get_admin_org_chart() from public, anon;
grant execute on function public.get_admin_org_chart() to authenticated, service_role;

commit;
