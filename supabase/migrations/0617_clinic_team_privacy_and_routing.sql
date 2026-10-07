-- 0617: خصوصية وسياسة تيم العيادات (الموظفون غير المديرين)
-- =====================================================================
-- متطلبات السياسة:
--   1. حجب التقارير اليومية عن تيم العيادات (get_public_daily_reports_feed)
--   2. توجيه طلبات المواقع الخاصة بتيم العيادات مباشرة لمديرهم مصطفى أحمد (request_live_location)
--   3. حجب لوحة الشرف عن تيم العيادات (get_honor_board)
--   4. حجب صفحة القرارات والتعاميم عن تيم العيادات (get_official_feed_admin, get_employee_published_decisions_admin)
--   5. تحديث get_my_access_context و get_employee_home لتعكس الحجب والراية isClinicStaff
-- =====================================================================

begin;

-- ═══════════════════════════════════════════════════════════════════════
-- 1. تحديث طلبات المواقع: طلب موقع أي موظفة بالعيادات يذهب مباشرة لمصطفى أحمد
-- ═══════════════════════════════════════════════════════════════════════
create or replace function public.request_live_location(
  p_employee_id uuid,
  p_mode text default 'snapshot'::text,
  p_reason text default ''::text
)
returns public.live_location_requests
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_me uuid := public.current_employee_id();
  v_req public.live_location_requests;
  v_duration integer;
  v_target_user uuid;
  v_deep_link text;
  v_target_emp_id uuid := p_employee_id;
  v_orig_emp_name text;
  v_clinic_mgr_emp_id uuid := '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'; -- مصطفي أحمد كمال الدين
  v_clinic_mgr_user_id uuid := '3e950d11-b5b4-4652-9ecf-919c434222fc';
  v_is_clinic_redirect boolean := false;
begin
  if v_me is null then
    raise exception 'requester has no employee profile' using errcode='42501';
  end if;

  if not (public.current_is_full_access() or public.current_has_active_role(array['executive', 'executive-director'])) then
    raise exception 'only executive director may request employee location' using errcode='42501';
  end if;

  if p_employee_id = v_me then
    raise exception 'cannot request own location' using errcode='22023';
  end if;

  -- استبعاد المدير التنفيذي كهدف
  if public.is_employee_executive(p_employee_id) then
    raise exception 'cannot request location of executive director' using errcode='22023';
  end if;

  -- ★ إذا كان المستهدف من طاقم العيادات (وليس مديراً): طلب الموقع يوجه مباشرة للمدير مصطفى أحمد ★
  if public.is_clinic_staff_exempt(p_employee_id) or public.employee_blocks_inbound_alerts(p_employee_id) then
    select full_name_ar into v_orig_emp_name from public.employees where id = p_employee_id;
    v_target_emp_id := v_clinic_mgr_emp_id;
    v_is_clinic_redirect := true;
    p_reason := 'طلب موقع لموظفة العيادات (' || coalesce(v_orig_emp_name, 'موظفة') || ') — مرسل مباشرة للمدير مصطفى أحمد للمتابعة والتحقق' ||
                case when nullif(trim(p_reason), '') is not null then ' | سبب إضافي: ' || trim(p_reason) else '' end;
  end if;

  -- وضع snapshot فقط
  if coalesce(p_mode, '') <> 'snapshot' then
    raise exception 'LOCATION_MODE_DISABLED: V17 allows snapshot location requests only' using errcode='22023';
  end if;

  if not exists (
    select 1 from public.employees
    where id = v_target_emp_id and status = 'active' and is_active and not is_deleted and user_id is not null
  ) then
    raise exception 'employee is not active or has no linked user account' using errcode='P0002';
  end if;

  -- مهلة 30 ثانية
  if exists (
    select 1 from public.live_location_requests
    where requested_by = v_me and employee_id = v_target_emp_id
      and requested_at > now() - interval '30 seconds'
  ) then
    raise exception 'cooldown_active: please wait 30 seconds between requests' using errcode='22023';
  end if;

  v_duration := 1;

  insert into public.live_location_requests(
    employee_id, requested_by, reason, status, purpose,
    requested_at, expires_at, duration_minutes, metadata, created_by
  ) values (
    v_target_emp_id, v_me, coalesce(nullif(trim(p_reason), ''), null),
    'pending', 'verification',
    now(), now() + interval '5 minutes', v_duration,
    jsonb_build_object(
      'mode', 'snapshot', 'videoSeconds', 0,
      'needsPoint', true, 'needsVideo', false,
      'isTracking', false, 'videoRemoved', true, 'policyVersion', 'V17',
      'isClinicRedirect', v_is_clinic_redirect,
      'originalTargetEmployeeId', p_employee_id::text
    ),
    auth.uid()
  )
  returning * into v_req;

  update public.live_location_requests
     set metadata = metadata || jsonb_build_object('requestId', v_req.id)
   where id = v_req.id
  returning * into v_req;

  v_deep_link := 'https://ahla-shabab-management-os.vercel.app/action/live_location_request/' || v_req.id::text;

  select user_id into v_target_user from public.employees where id = v_target_emp_id;
  if v_target_user is not null then
    insert into public.notifications(
      recipient_user_id, recipient_employee_id, title, body, category, priority,
      action_url, entity_type, entity_id, metadata, created_by
    ) values (
      v_target_user, v_target_emp_id,
      case when v_is_clinic_redirect then 'طلب موقع عاجل (طاقم العيادات)' else 'طلب موقع عاجل' end,
      case when v_is_clinic_redirect
        then 'طلب موقع يخص موظفة بالعيادات (' || coalesce(v_orig_emp_name, '') || ') — محول إليك كمسؤول للعيادات للموافقة الفورية.'
        else 'اجتمع التنفيذ لمعرفة موقعك فوراً. يرجى الضغط للموافقة.'
      end,
      'system', 'urgent',
      v_deep_link,
      'live_location_request', v_req.id,
      jsonb_build_object(
        'fullScreen', true, 'kind', 'live_location_request', 'requestId', v_req.id,
        'entityId', v_req.id, 'channel', 'urgent_location_v6',
        'deepLink', v_deep_link
      ),
      auth.uid()
    );
  end if;

  perform public.log_audit_event(
    'live_location.requested', 'security', 'info',
    'live_location_requests', v_req.id, 'طلب موقع حي', null,
    jsonb_build_object('mode', 'snapshot', 'employeeId', v_target_emp_id, 'requestId', v_req.id, 'originalTargetEmployeeId', p_employee_id)
  );

  return v_req;
end;
$function$;


-- ═══════════════════════════════════════════════════════════════════════
-- 2. حجب التقارير اليومية عن تيم العيادات (get_public_daily_reports_feed)
-- ═══════════════════════════════════════════════════════════════════════
create or replace function public.get_public_daily_reports_feed(
  p_limit integer default 50,
  p_before date default null::date
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_me uuid := public.current_employee_id();
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'يلزم تسجيل الدخول أولاً' using errcode = '42501';
  end if;

  -- ★ تيم العيادات (غير المديرين) لا يرى التقارير اليومية إطلاقاً ★
  if public.is_clinic_staff_exempt(v_me) then
    return '[]'::jsonb;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', dr.id,
    'employeeId', e.id,
    'employeeName', e.full_name_ar,
    'employeeCode', e.employee_code,
    'photoUrl', e.photo_url,
    'jobTitle', jt.name,
    'department', d.name,
    'managerName', mgr.full_name_ar,
    'reportDate', dr.report_date,
    'achievements', dr.achievements,
    'blockers', dr.blockers,
    'tomorrowPlan', dr.tomorrow_plan,
    'managerComment', dr.manager_comment,
    'reviewedByName', rv.full_name_ar,
    'reviewedAt', dr.reviewed_at,
    'createdAt', dr.created_at,
    'likesCount', (select count(*) from public.daily_report_likes l where l.report_id = dr.id),
    'isLikedByMe', exists(
      select 1 from public.daily_report_likes l
      where l.report_id = dr.id and l.employee_id = v_me
    ),
    'viewersCount', (select count(*) from public.daily_report_views v where v.report_id = dr.id),
    'viewers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'employeeId', ve.id,
        'name', ve.full_name_ar,
        'photoUrl', ve.photo_url,
        'at', v.last_viewed_at
      ) order by v.last_viewed_at desc)
      from (
        select v2.employee_id, v2.last_viewed_at
        from public.daily_report_views v2
        where v2.report_id = dr.id
        order by v2.last_viewed_at desc
        limit 3
      ) v
      join public.employees ve on ve.id = v.employee_id
    ), '[]'::jsonb)
  ) order by dr.report_date desc, dr.created_at desc), '[]'::jsonb)
  into v_result
  from public.daily_reports dr
  join public.employees e on e.id = dr.employee_id
  left join public.job_titles jt on jt.id = e.job_title_id
  left join public.departments d on d.id = e.department_id
  left join public.departments dm on dm.id = e.department_id
  left join public.employees mgr on mgr.id = dm.manager_id
  left join public.employees rv on rv.id = dr.reviewed_by
  where not e.is_deleted
    and (p_before is null or dr.report_date < p_before)
  limit coalesce(p_limit, 50);

  return v_result;
end;
$function$;


-- ═══════════════════════════════════════════════════════════════════════
-- 3. حجب لوحة الشرف عن تيم العيادات (get_honor_board)
-- ═══════════════════════════════════════════════════════════════════════
create or replace function public.get_honor_board(
  p_period text default 'month'::text,
  p_category text default 'attendance'::text
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_today  date := (now() at time zone 'Africa/Cairo')::date;
  v_start  date;
  v_result jsonb;
  v_me uuid := public.current_employee_id();
begin
  if auth.uid() is null then
    raise exception 'يلزم تسجيل الدخول أولاً' using errcode = '42501';
  end if;

  -- ★ تيم العيادات (غير المديرين) لا تظهر لهم لوحة الشرف ★
  if public.is_clinic_staff_exempt(v_me) then
    return '[]'::jsonb;
  end if;

  if p_period = 'week' then
    v_start := v_today - ((extract(dow from v_today)::int + 1) % 7);
  else
    v_start := date_trunc('month', v_today)::date;
  end if;

  if p_category = 'attendance' then
    with days as (
      select d::date as day,
             (extract(dow from d) <> 5
              and not exists (
                select 1 from public.public_holidays h
                where h.is_active
                  and d::date between h.holiday_date and coalesce(h.end_date, h.holiday_date)
              )) as is_workday
      from generate_series(v_start, v_today, interval '1 day') d
    ),
    staff as (
      select e.id, e.full_name_ar, e.photo_url, e.hire_date,
             coalesce(dp.name, 'الإدارة العامة') as department
      from public.employees e
      left join public.departments dp on dp.id = e.department_id
      where e.is_active and not e.is_deleted
        and not coalesce(e.is_attendance_exempt, false)
        and not public.is_employee_attendance_exempt(e.id)
        and not public.is_clinic_staff_exempt(e.id)
    ),
    emp_stats as (
      select
        s.id, s.full_name_ar, s.photo_url, s.department, s.hire_date,
        count(distinct d.day) filter (
          where d.day >= coalesce(s.hire_date, '2000-01-01'::date)
        ) as work_days,
        count(distinct ad.work_date) filter (
          where ad.status = 'present'
        ) as present_days,
        coalesce(sum(least(ad.late_minutes, 120)) filter (
          where ad.status = 'present' and ad.late_minutes > 15
        ), 0)::integer as late_minutes,
        count(distinct ad.work_date) filter (
          where ad.status = 'absent'
        ) as absent_days
      from staff s
      cross join days d
      left join public.attendance_daily ad
        on ad.employee_id = s.id and ad.work_date = d.day
      where d.is_workday
      group by s.id, s.full_name_ar, s.photo_url, s.department, s.hire_date
    ),
    scored as (
      select
        id, full_name_ar, photo_url, department,
        work_days, present_days, absent_days, late_minutes,
        case
          when work_days = 0 then 0
          else round(
            greatest(0,
              (present_days::numeric / work_days::numeric * 70.0)
              + greatest(0, 20.0 - (late_minutes::numeric / 6.0))
              - (absent_days::numeric * 5.0)
            ), 1
          )
        end as score,
        dense_rank() over (
          order by
            case
              when work_days = 0 then 0
              else round(
                greatest(0,
                  (present_days::numeric / work_days::numeric * 70.0)
                  + greatest(0, 20.0 - (late_minutes::numeric / 6.0))
                  - (absent_days::numeric * 5.0)
                ), 1
              )
            end desc,
            present_days desc,
            late_minutes asc
        ) as rank
      from emp_stats
      where work_days > 0
    )
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'rank', rank,
        'employee_id', id,
        'full_name_ar', full_name_ar,
        'photo_url', photo_url,
        'department', department,
        'score', score,
        'present_days', present_days,
        'work_days', work_days,
        'late_minutes', late_minutes,
        'absent_days', absent_days,
        'period', p_period,
        'category', p_category
      ) order by rank, score desc
    ), '[]'::jsonb)
    into v_result
    from scored
    where rank <= 10;

  elsif p_category = 'missions' then
    with staff as (
      select e.id, e.full_name_ar, e.photo_url,
             coalesce(dp.name, 'الإدارة العامة') as department
      from public.employees e
      left join public.departments dp on dp.id = e.department_id
      where e.is_active and not e.is_deleted
        and not public.is_clinic_staff_exempt(e.id)
    ),
    mission_counts as (
      select
        s.id, s.full_name_ar, s.photo_url, s.department,
        count(distinct r.id) as completed_missions
      from staff s
      join public.requests r on r.employee_id = s.id
      where r.request_type = 'mission'
        and r.status = 'approved'
        and r.created_at::date between v_start and v_today
      group by s.id, s.full_name_ar, s.photo_url, s.department
    ),
    ranked as (
      select *,
        dense_rank() over (order by completed_missions desc) as rank
      from mission_counts
      where completed_missions > 0
    )
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'rank', rank,
        'employee_id', id,
        'full_name_ar', full_name_ar,
        'photo_url', photo_url,
        'department', department,
        'score', completed_missions * 10,
        'completed_missions', completed_missions,
        'period', p_period,
        'category', p_category
      ) order by rank
    ), '[]'::jsonb)
    into v_result
    from ranked
    where rank <= 10;

  elsif p_category = 'reports' then
    with staff as (
      select e.id, e.full_name_ar, e.photo_url,
             coalesce(dp.name, 'الإدارة العامة') as department
      from public.employees e
      left join public.departments dp on dp.id = e.department_id
      where e.is_active and not e.is_deleted
        and not public.is_clinic_staff_exempt(e.id)
    ),
    report_counts as (
      select
        s.id, s.full_name_ar, s.photo_url, s.department,
        count(distinct dr.id) as reports_count
      from staff s
      join public.daily_reports dr on dr.employee_id = s.id
      where dr.report_date between v_start and v_today
      group by s.id, s.full_name_ar, s.photo_url, s.department
    ),
    ranked as (
      select *,
        dense_rank() over (order by reports_count desc) as rank
      from report_counts
      where reports_count > 0
    )
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'rank', rank,
        'employee_id', id,
        'full_name_ar', full_name_ar,
        'photo_url', photo_url,
        'department', department,
        'score', reports_count * 5,
        'reports_count', reports_count,
        'period', p_period,
        'category', p_category
      ) order by rank
    ), '[]'::jsonb)
    into v_result
    from ranked
    where rank <= 10;

  else
    v_result := '[]'::jsonb;
  end if;

  return coalesce(v_result, '[]'::jsonb);
end;
$function$;


-- ═══════════════════════════════════════════════════════════════════════
-- 4. حجب القرارات والتعاميم عن تيم العيادات
-- ═══════════════════════════════════════════════════════════════════════
create or replace function public.get_official_feed_admin(p_limit integer default 100)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_me uuid := public.current_employee_id();
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;

  -- ★ تيم العيادات (غير المديرين) لا تظهر لهم صفحة القرارات والتعاميم ★
  if public.is_clinic_staff_exempt(v_me) then
    return '[]'::jsonb;
  end if;

  select coalesce(jsonb_agg(item order by sort_at desc), '[]'::jsonb)
  into v_result
  from (
    select item, sort_at
    from (
      select jsonb_build_object(
        'id', a.id, 'kind', 'announcement', 'title', a.title, 'body', a.body,
        'category', a.category, 'priority', a.priority, 'status', a.status,
        'postType', coalesce(a.post_type, 'announcement'),
        'requiresAcknowledgement', a.requires_acknowledgement,
        'publishedAt', a.published_at, 'expiresAt', a.expires_at,
        'imageUrl', a.banner_url,
        'authorName', e_a.full_name_ar,
        'authorPhotoUrl', e_a.photo_url,
        'acknowledgedCount', (select count(*)::integer from public.announcement_acknowledgements x where x.announcement_id = a.id),
        'viewCount', (select count(*)::integer from public.announcement_acknowledgements x where x.announcement_id = a.id)
      ) as item, a.published_at as sort_at
      from public.announcements a
      left join public.employees e_a on e_a.id = a.created_by_employee_id
      where a.status = 'published'

      union all

      select jsonb_build_object(
        'id', d.id, 'kind', 'decision', 'title', d.title, 'body', coalesce(d.content, ''),
        'category', d.category, 'priority', 'normal', 'status', d.status,
        'postType', 'decision',
        'requiresAcknowledgement', false,
        'publishedAt', d.published_at, 'expiresAt', null,
        'imageUrl', null,
        'authorName', e_d.full_name_ar,
        'authorPhotoUrl', e_d.photo_url,
        'acknowledgedCount', 0,
        'viewCount', (select count(*)::integer from public.decision_reads r where r.decision_id = d.id)
      ) as item, d.published_at as sort_at
      from public.administrative_decisions d
      left join public.employees e_d on e_d.id = d.issued_by
      where d.status = 'published'
    ) combined
    order by sort_at desc
    limit coalesce(p_limit, 100)
  ) sub;

  return v_result;
end;
$function$;

create or replace function public.get_employee_published_decisions_admin(
  p_employee_id uuid,
  p_limit integer default 100
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_result jsonb;
  v_me uuid := public.current_employee_id();
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;

  -- ★ تيم العيادات لا تظهر لهم القرارات الإدارية ★
  if public.is_clinic_staff_exempt(p_employee_id) or public.is_clinic_staff_exempt(v_me) then
    return '[]'::jsonb;
  end if;

  if not (
    public.has_permission('people.employee.read')
    or public.can_access_employee(p_employee_id)
  ) then
    raise exception 'ERR_FORBIDDEN' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', d.id,
    'decisionNumber', d.decision_number,
    'title', d.title,
    'category', d.category,
    'effectiveDate', d.effective_date,
    'expiryDate', d.expiry_date,
    'publishedAt', d.published_at,
    'isRead', exists(
      select 1 from public.decision_reads dr
      where dr.decision_id = d.id and dr.employee_id = p_employee_id
    ),
    'acknowledged', coalesce((
      select dr.acknowledged from public.decision_reads dr
      where dr.decision_id = d.id and dr.employee_id = p_employee_id
    ), false),
    'acknowledgedAt', (
      select dr.acknowledged_at from public.decision_reads dr
      where dr.decision_id = d.id and dr.employee_id = p_employee_id
    ),
    'issuedByName', e.full_name_ar
  ) order by d.published_at desc), '[]'::jsonb)
  into v_result
  from public.administrative_decisions d
  left join public.employees e on e.id = d.issued_by
  where d.status = 'published'
    and (
      d.visibility = 'all'
      or exists (
        select 1 from public.decision_recipients dr
        where dr.decision_id = d.id and dr.employee_id = p_employee_id
      )
    )
  limit coalesce(p_limit, 100);

  return v_result;
end;
$function$;


-- ═══════════════════════════════════════════════════════════════════════
-- 5. تحديث get_employee_home لعدم احتساب إشعارات القرارات أو طلبات المواقع لطاقم العيادات
-- ═══════════════════════════════════════════════════════════════════════
create or replace function public.get_employee_home()
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_me uuid;
  v_is_clinic boolean := false;
begin
  v_me := public.current_employee_id();

  if v_me is null then
    return jsonb_build_object(
      'pendingRequests', 0,
      'activeTasks', 0,
      'kpiStage', null,
      'unreadNotifications', (select count(*) from public.notifications
        where recipient_user_id = auth.uid() and is_read = false),
      'unreadOfficial', 0,
      'pendingLocationRequests', 0,
      'lastUpdatedAt', now()
    );
  end if;

  v_is_clinic := public.is_clinic_staff_exempt(v_me);

  return jsonb_build_object(
    'pendingRequests', (select count(*) from public.requests
      where employee_id = v_me and status = 'pending'),
    'activeTasks', (select count(*) from public.tasks
      where assignee_employee_id = v_me
        and status not in ('done', 'cancelled')),
    'kpiStage', (select current_stage from public.kpi_evaluations
      where employee_id = v_me order by created_at desc limit 1),
    'unreadNotifications', (select count(*) from public.notifications
      where recipient_user_id = auth.uid() and is_read = false),
    'unreadOfficial', case when v_is_clinic then 0 else (
      select count(*) from public.decision_recipients dr
      join public.administrative_decisions d on d.id = dr.decision_id
      left join public.decision_reads rr on rr.decision_id = d.id
        and rr.employee_id = dr.employee_id
      where dr.employee_id = v_me
        and d.status = 'published'
        and rr.id is null
    ) end,
    'pendingLocationRequests', case when v_is_clinic then 0 else (
      select count(*) from public.live_location_requests
      where employee_id = v_me
        and status = 'pending'
        and expires_at > now()
    ) end,
    'lastUpdatedAt', now()
  );
end;
$function$;


-- ═══════════════════════════════════════════════════════════════════════
-- 6. تحديث get_my_access_context لإرجاع isClinicStaff
-- ═══════════════════════════════════════════════════════════════════════
create or replace function public.get_my_access_context()
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'auth', 'pg_temp'
as $function$
declare
  v_user_id uuid := auth.uid();
  v_employee_id uuid;
  v_display_name text;
  v_employee_code text;
  v_photo_url text;
  v_profile_status text;
  v_employee_status text;
  v_roles text[] := '{}'::text[];
  v_permissions text[] := '{}'::text[];
  v_workspaces text[] := '{}'::text[];
  v_default_workspace text := 'employee';
  v_is_full boolean := false;
  v_is_executive boolean := false;
  v_is_manager boolean := false;
  v_is_operations boolean := false;
  v_is_hr boolean := false;
  v_is_main_admin boolean := false;
  v_is_committee boolean := false;
  v_is_suspended boolean := false;
  v_suspension_reason text := null;
  v_suspension_message text := null;
  v_suspension_amount numeric := null;
  v_is_immune_admin boolean := false;
  v_is_clinic_staff boolean := false;
begin
  if v_user_id is null then
    raise exception 'يلزم تسجيل الدخول أولاً' using errcode = '28000';
  end if;

  select p.employee_id, coalesce(e.full_name_ar,'مستخدم النظام'), e.employee_code, e.photo_url, p.status, e.status
    into v_employee_id, v_display_name, v_employee_code, v_photo_url, v_profile_status, v_employee_status
  from public.profiles p
  left join public.employees e on e.id = p.employee_id
  where p.id = v_user_id;

  if not found then
    raise exception 'لا يوجد ملف موظف نشط' using errcode = '42501';
  end if;

  if v_user_id = '6f347a78-bb30-4ae5-8b07-2ecfc623f960'
     or v_employee_code in ('+201154869616','01154869616')
     or exists (select 1 from public.employees e where e.id = v_employee_id and (e.phone_e164 in ('+201154869616','01154869616') or e.user_id = '6f347a78-bb30-4ae5-8b07-2ecfc623f960')) then
    v_is_immune_admin := true;
    v_profile_status := 'active';
    v_employee_status := 'active';
  end if;

  if not v_is_immune_admin and (coalesce(v_profile_status,'')='suspended' or coalesce(v_employee_status,'')='suspended') then
    v_is_suspended := true;
    select p.current_amount into v_suspension_amount
    from public.instant_attendance_penalties p
    where p.employee_id = v_employee_id and p.status = 'suspended'
    order by p.created_at desc limit 1;
    if found then
      v_suspension_reason := 'penalty_unpaid';
      v_suspension_amount := coalesce(v_suspension_amount,500.00);
      v_suspension_message := 'تم وقفك عن العمل لعدم سداد قيمة الخصم 500جنيه توجه الي قسم ال HR لسداد المبلغ';
    else
      v_suspension_reason := 'administrative';
      v_suspension_message := 'تم إيقاف حسابك عن العمل مؤقتاً. يرجى مراجعة إدارة الموارد البشرية (HR).';
    end if;
    return jsonb_build_object(
      'userId', v_user_id, 'employeeId', v_employee_id, 'displayName', v_display_name,
      'employeeCode', v_employee_code, 'photoUrl', v_photo_url,
      'roles', '[]'::jsonb, 'permissions', '[]'::jsonb, 'workspaces', '[]'::jsonb,
      'defaultWorkspace', 'employee', 'isSuspended', true,
      'suspensionReason', v_suspension_reason, 'suspensionMessage', v_suspension_message,
      'suspensionAmount', v_suspension_amount,
      'isClinicStaff', false,
      'attendancePolicy', jsonb_build_object('attendanceRequired',false,'selfPunchEnabled',false,'liveLocationResponseEnabled',false)
    );
  end if;

  if v_profile_status not in ('active','pending') then
    raise exception 'حساب المستخدم غير نشط' using errcode = '42501';
  end if;

  select coalesce(array_agg(distinct r.slug order by r.slug), '{}'::text[])
    into v_roles
  from public.user_roles ur
  join public.roles r on r.id = ur.role_id
  where ur.user_id = v_user_id and ur.effective_from <= now() and (ur.effective_to is null or ur.effective_to > now());

  v_is_full := public.current_is_full_access() or v_is_immune_admin;
  if v_is_full then
    v_permissions := array['*']::text[];
  else
    select coalesce(array_agg(distinct p.code order by p.code), '{}'::text[])
      into v_permissions
    from public.user_roles ur
    join public.role_permissions rp on rp.role_id = ur.role_id
    join public.permissions p on p.id = rp.permission_id
    where ur.user_id = v_user_id and ur.effective_from <= now() and (ur.effective_to is null or ur.effective_to > now())
      and (rp.effective_from is null or rp.effective_from <= now()) and (rp.effective_to is null or rp.effective_to > now());
  end if;

  v_is_executive := v_roles && array['executive-director','executive']::text[];
  v_is_operations := v_roles && array['operations-officer','operations-manager','operations-manager-1','operations-manager-2']::text[];
  v_is_manager := v_is_operations or v_roles && array['direct-manager','department-manager','branch-manager','clinics-manager']::text[];
  if not v_is_manager and v_employee_id is not null then
    if exists (select 1 from public.departments d where d.manager_id = v_employee_id) or exists (
      select 1 from public.manager_relations mr
      where mr.manager_employee_id = v_employee_id and mr.relation_type='primary'
        and mr.effective_from <= now() and (mr.effective_to is null or mr.effective_to > now())
    ) then
      v_is_manager := true;
    end if;
  end if;

  v_is_hr := v_roles && array['hr-manager','hr-specialist']::text[];
  v_is_main_admin := v_is_full or v_is_immune_admin or v_roles && array['admin','super-admin','super_admin','system-admin','technical-lead','executive-secretary']::text[];
  v_is_committee := v_roles && array['committee-member','committee-chair','committee-secretary']::text[];

  -- فحص طاقم العيادات (الموظفون غير المديرين)
  if v_employee_id is not null then
    v_is_clinic_staff := public.is_clinic_staff_exempt(v_employee_id);
  end if;

  if v_employee_id is not null and not v_is_executive then v_workspaces := array_append(v_workspaces,'employee'); end if;
  if v_is_manager and not v_is_executive then v_workspaces := array_append(v_workspaces,'manager'); end if;
  if v_is_operations and not v_is_executive then v_workspaces := array_append(v_workspaces,'field_operations'); end if;
  if v_is_executive then v_workspaces := array_append(v_workspaces,'executive'); end if;
  if v_is_hr or v_is_main_admin then v_workspaces := array_append(v_workspaces,'hr'); end if;
  if v_is_main_admin then v_workspaces := array_append(v_workspaces,'main_admin'); end if;
  if v_is_committee and not v_is_hr and not v_is_main_admin then v_workspaces := array_append(v_workspaces,'committee'); end if;

  if v_is_main_admin then v_default_workspace := 'main_admin';
  elsif v_is_executive then v_default_workspace := 'executive';
  elsif v_is_hr then v_default_workspace := 'hr';
  elsif v_is_operations then v_default_workspace := 'field_operations';
  elsif v_is_manager then v_default_workspace := 'manager';
  elsif v_employee_id is not null then v_default_workspace := 'employee';
  else raise exception 'لا توجد مساحة عمل معينة' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'userId', v_user_id,
    'employeeId', v_employee_id,
    'displayName', v_display_name,
    'employeeCode', v_employee_code,
    'photoUrl', v_photo_url,
    'roles', to_jsonb(v_roles),
    'permissions', to_jsonb(v_permissions),
    'workspaces', to_jsonb(v_workspaces),
    'defaultWorkspace', v_default_workspace,
    'isSuspended', false,
    'suspensionReason', null,
    'suspensionMessage', null,
    'suspensionAmount', null,
    'isClinicStaff', v_is_clinic_staff,
    'attendancePolicy', jsonb_build_object(
      'attendanceRequired', not v_is_executive and not public.is_employee_attendance_exempt(v_employee_id) and v_employee_id is not null,
      'selfPunchEnabled', true,
      'liveLocationResponseEnabled', not v_is_executive and not public.is_employee_attendance_exempt(v_employee_id) and not v_is_clinic_staff and v_employee_id is not null
    )
  );
end;
$function$;

notify pgrst, 'reload schema';

commit;
