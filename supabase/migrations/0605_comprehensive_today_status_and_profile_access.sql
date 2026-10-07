-- ═══════════════════════════════════════════════════════════════════
-- Migration 0605: إتاحة ملف الموظف لجميع منسوبي الجمعية مع الحالة اليومية
-- الشاملة (حاضر / غائب / في مأمورية / في قافلة / في فاندي / في إجازة)
-- ═══════════════════════════════════════════════════════════════════

-- 1) get_employee_360: إتاحة العرض لأي فرد مسجل في الجمعية + الحالة اليومية التشغيلية التفصيلية
create or replace function public.get_employee_360(p_employee_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;

  if p_employee_id is null then
    raise exception 'employee_not_found' using errcode = 'P0002';
  end if;

  -- الحفاظ على عزل الإدارة الطبية / فتيات العيادات للمصرح لهم فقط
  if public.is_employee_isolated(p_employee_id) and not public.can_view_isolated_employee(p_employee_id) then
    raise exception 'employee scope denied' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'id', e.id,
    'employeeCode', e.employee_code,
    'fullNameAr', e.full_name_ar,
    'fullNameEn', e.full_name_en,
    'email', au.email,
    'phoneE164', e.phone_e164,
    'photoUrl', e.photo_url,
    'status', e.status,
    'isActive', e.is_active,
    'hireDate', e.hire_date,
    'contractEnd', e.contract_end,
    'probationEnd', e.probation_end,
    'jobTitle', jt.name,
    'position', pos.name,
    'grade', grade.name,
    'department', dept.name,
    'team', team.name,
    'branch', branch.name,
    'workSite', site.name,
    'managerName', manager_rel.full_name_ar,
    'accountStatus', profile.status,
    'departmentId', e.department_id,
    'teamId', e.team_id,
    'branchId', e.branch_id,
    'workSiteId', e.work_site_id,
    'jobTitleId', e.job_title_id,
    'positionId', e.position_id,
    'gradeId', e.grade_id,
    'employmentTypeId', e.employment_type_id,
    'managerId', (
      select mr.manager_employee_id
      from public.manager_relations mr
      where mr.employee_id = e.id
        and mr.relation_type = 'primary'
        and mr.effective_from <= (now() at time zone 'Africa/Cairo')::date
        and (mr.effective_to is null or mr.effective_to >= (now() at time zone 'Africa/Cairo')::date)
      order by (mr.effective_to is null) desc, mr.created_at desc
      limit 1
    ),
    'roles', coalesce((
      select jsonb_agg(jsonb_build_object('slug', r.slug, 'name', r.name_ar) order by r.name_ar)
      from public.user_roles ur
      join public.roles r on r.id = ur.role_id
      where ur.user_id = e.user_id
        and ur.effective_from <= now()
        and (ur.effective_to is null or ur.effective_to > now())
    ), '[]'::jsonb),
    'directReports', (
      select count(*)
      from public.manager_relations mr
      where mr.manager_employee_id = e.id
        and mr.relation_type = 'primary'
        and mr.effective_from <= (now() at time zone 'Africa/Cairo')::date
        and (mr.effective_to is null or mr.effective_to >= (now() at time zone 'Africa/Cairo')::date)
    ),
    'todayStatus', (
      with req as (
        select
          r.request_type,
          r.status as req_status,
          coalesce(
            nullif(r.payload->>'location',''),
            nullif(r.payload->>'destination',''),
            nullif(r.title,''),
            case when r.request_type = 'leave' then 
              case coalesce(r.payload->>'leaveType', '')
                when 'annual' then 'إجازة اعتيادية'
                when 'casual' then 'إجازة عارضة'
                when 'sick' then 'إجازة مرضية'
                when 'weekly_rest_comp' then 'بدل راحة أسبوعية'
                else 'إجازة رسمية'
              end
            else null end
          ) as activity_title
        from public.requests r
        where r.employee_id = e.id
          and r.status in ('approved', 'pending')
          and r.request_type in ('convoy', 'fundraising', 'mission', 'leave')
          and (now() at time zone 'Africa/Cairo')::date between 
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
      ),
      punch as (
        select 
          ad.status as ad_status,
          ad.late_minutes,
          ad.work_minutes,
          coalesce(ad.first_check_in, (
            select min(ae.event_at) from public.attendance_events ae 
            where ae.employee_id = e.id 
              and ae.event_type = 'CHECK_IN' 
              and (ae.event_at at time zone 'Africa/Cairo')::date = (now() at time zone 'Africa/Cairo')::date
              and ae.status in ('accepted', 'adjusted')
          )) as check_in,
          coalesce(ad.last_check_out, (
            select max(ae.event_at) from public.attendance_events ae 
            where ae.employee_id = e.id 
              and ae.event_type = 'CHECK_OUT' 
              and (ae.event_at at time zone 'Africa/Cairo')::date = (now() at time zone 'Africa/Cairo')::date
              and ae.status in ('accepted', 'adjusted')
          )) as check_out
        from (select 1) _
        left join public.attendance_daily ad on ad.employee_id = e.id 
          and ad.work_date = (now() at time zone 'Africa/Cairo')::date
      )
      select jsonb_build_object(
        'status', case 
          when (select request_type from req) = 'convoy' then 'convoy'
          when (select request_type from req) = 'fundraising' then 'fundraising'
          when (select request_type from req) = 'mission' then 'mission'
          when (select request_type from req) = 'leave' then 'on_leave'
          when (select ad_status from punch) = 'on_leave' then 'on_leave'
          when (select ad_status from punch) in ('weekend', 'holiday') then (select ad_status from punch)
          when (select check_in from punch) is not null then
            case when coalesce((select late_minutes from punch), 0) > 0 or (select ad_status from punch) = 'late' then 'late' else 'present' end
          when (select ad_status from punch) = 'absent' then 'absent'
          else 'not_recorded'
        end,
        'statusLabel', case 
          when (select request_type from req) = 'convoy' then 'في قافلة'
          when (select request_type from req) = 'fundraising' then 'في فاندي'
          when (select request_type from req) = 'mission' then 'في مأمورية'
          when (select request_type from req) = 'leave' then 'في إجازة'
          when (select ad_status from punch) = 'on_leave' then 'في إجازة'
          when (select ad_status from punch) = 'weekend' then 'إجازة أسبوعية'
          when (select ad_status from punch) = 'holiday' then 'عطلة رسمية'
          when (select check_in from punch) is not null then
            case when coalesce((select late_minutes from punch), 0) > 0 or (select ad_status from punch) = 'late' then 'متأخر' else 'حاضر' end
          when (select ad_status from punch) = 'absent' then 'غائب'
          else 'لم يسجل بعد'
        end,
        'activityTitle', (select activity_title from req),
        'lateMinutes', coalesce((select late_minutes from punch), 0),
        'checkInAt', (select check_in from punch),
        'checkOutAt', (select check_out from punch),
        'workMinutes', coalesce((select work_minutes from punch), 0)
      )
    ),
    'attendance30', jsonb_build_object(
      'present', (select count(*) from public.attendance_daily a where a.employee_id=e.id and a.work_date >= (now() at time zone 'Africa/Cairo')::date - 29 and a.status in ('present','late')),
      'lateDays', (select count(*) from public.attendance_daily a where a.employee_id=e.id and a.work_date >= (now() at time zone 'Africa/Cairo')::date - 29 and a.late_minutes > 0),
      'absent', (select count(*) from public.attendance_daily a where a.employee_id=e.id and a.work_date >= (now() at time zone 'Africa/Cairo')::date - 29 and a.status='absent'),
      'workMinutes', (select coalesce(sum(a.work_minutes),0) from public.attendance_daily a where a.employee_id=e.id and a.work_date >= (now() at time zone 'Africa/Cairo')::date - 29)
    ),
    'requestCounts', jsonb_build_object(
      'pending', (select count(*) from public.requests r where r.employee_id=e.id and r.status='pending'),
      'approved', (select count(*) from public.requests r where r.employee_id=e.id and r.status='approved'),
      'rejected', (select count(*) from public.requests r where r.employee_id=e.id and r.status='rejected')
    ),
    'documents', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', doc.id, 'type', doc.doc_type, 'title', doc.title,
        'expiryDate', doc.expiry_date,
        'status', case when doc.expiry_date is not null and doc.expiry_date < (now() at time zone 'Africa/Cairo')::date then 'expired' else doc.status end
      ) order by doc.created_at desc)
      from public.documents doc
      where doc.owner_employee_id=e.id and doc.status <> 'archived'
    ), '[]'::jsonb),
    'assets', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', aa.id, 'assetName', ai.name_ar, 'assetType', ai.asset_type,
        'serial', ai.serial, 'handedOverAt', aa.handed_over_at, 'returnedAt', aa.returned_at
      ) order by aa.handed_over_at desc nulls last)
      from public.asset_assignments aa
      join public.asset_inventory ai on ai.id=aa.asset_id
      where aa.employee_id=e.id
    ), '[]'::jsonb),
    'recentRequests', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'requestNumber', r.request_number, 'requestType', r.request_type,
        'title', r.title, 'status', r.status, 'createdAt', r.created_at
      ) order by r.created_at desc)
      from (
        select * from public.requests where employee_id=e.id order by created_at desc limit 10
      ) r
    ), '[]'::jsonb),
    'recentTasks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'title', t.title, 'status', t.status,
        'priority', t.priority, 'dueDate', t.due_date
      ) order by t.created_at desc)
      from (
        select * from public.tasks where assignee_employee_id=e.id order by created_at desc limit 10
      ) t
    ), '[]'::jsonb),
    'departments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', ed.id, 'departmentId', ed.department_id, 'departmentName', d.name,
        'jobTitle', ed.job_title, 'isPrimary', ed.is_primary, 'assignedAt', ed.assigned_at
      ) order by ed.is_primary desc, ed.assigned_at desc)
      from public.employee_departments ed
      join public.departments d on d.id=ed.department_id
      where ed.employee_id=e.id
        and (ed.start_date is null or ed.start_date <= (now() at time zone 'Africa/Cairo')::date)
        and (ed.end_date is null or ed.end_date >= (now() at time zone 'Africa/Cairo')::date)
    ), '[]'::jsonb),
    'lastUpdatedAt', coalesce(e.updated_at, e.created_at, now())
  )
  into v_result
  from public.employees e
  left join public.job_titles jt on jt.id=e.job_title_id
  left join public.positions pos on pos.id=e.position_id
  left join public.job_grades grade on grade.id=e.grade_id
  left join public.departments dept on dept.id=e.department_id
  left join public.teams team on team.id=e.team_id
  left join public.branches branch on branch.id=e.branch_id
  left join public.work_sites site on site.id=e.work_site_id
  left join public.employees manager_rel on manager_rel.id = (
    select mr.manager_employee_id
    from public.manager_relations mr
    where mr.employee_id=e.id and mr.relation_type='primary'
      and mr.effective_from <= (now() at time zone 'Africa/Cairo')::date
      and (mr.effective_to is null or mr.effective_to >= (now() at time zone 'Africa/Cairo')::date)
    order by (mr.effective_to is null) desc, mr.created_at desc
    limit 1
  )
  left join public.profiles profile on profile.employee_id=e.id
  left join auth.users au on au.id=profile.id
  where e.id=p_employee_id;

  if v_result is null then
    raise exception 'employee_not_found' using errcode = 'P0002';
  end if;

  return v_result;
end;
$$;

comment on function public.get_employee_360(uuid) is
  '0605: إتاحة ملف الموظف 360 لمنسوبي المنظومة مع تفصيل الحالة اليومية (حاضر، غائب، مأمورية، قافلة، فاندي، إجازة).';

revoke all on function public.get_employee_360(uuid) from public;
grant execute on function public.get_employee_360(uuid) to authenticated;


-- 2) get_mobile_employee_directory: تحديث الحالات اليومية في دليل الموظفين لتشمل (قافلة، فاندي، مأمورية، إجازة، حاضر، متأخر، غائب)
create or replace function public.get_mobile_employee_directory(p_search text default null::text, p_limit integer default 40)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_search text := nullif(trim(coalesce(p_search, '')), '');
  v_today date := (now() at time zone 'Africa/Cairo')::date;
begin
  if auth.uid() is null then
    raise exception 'غير مسجل الدخول' using errcode = '42501';
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
        when req.request_type = 'convoy' then 'convoy'
        when req.request_type = 'fundraising' then 'fundraising'
        when req.request_type = 'mission' then 'mission'
        when req.request_type = 'leave' then 'on_leave'
        when ad.status = 'on_leave' then 'on_leave'
        when ad.status in ('weekend','holiday') then ad.status
        when coalesce(ad.first_check_in, ae.event_at) is not null then
          case when coalesce(ad.late_minutes, 0) > 0 or ad.status = 'late' then 'late' else 'present' end
        when ad.status = 'absent' then 'absent'
        else 'not_recorded'
      end,
      'statusTodayLabel', case
        when req.request_type = 'convoy' then 'في قافلة'
        when req.request_type = 'fundraising' then 'في فاندي'
        when req.request_type = 'mission' then 'في مأمورية'
        when req.request_type = 'leave' then 'في إجازة'
        when ad.status = 'on_leave' then 'في إجازة'
        when ad.status = 'weekend' then 'إجازة أسبوعية'
        when ad.status = 'holiday' then 'عطلة رسمية'
        when coalesce(ad.first_check_in, ae.event_at) is not null then
          case when coalesce(ad.late_minutes, 0) > 0 or ad.status = 'late' then 'متأخر' else 'حاضر' end
        when ad.status = 'absent' then 'غائب'
        else 'لم يسجل'
      end,
      'activityTitle',    req.activity_title
    ) order by e.full_name_ar)
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
    where e.is_active  = true
      and e.is_deleted = false
      and not public.is_employee_executive(e.id)
      and public.can_see_directory_entry(public.current_employee_id(), e.id)
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

comment on function public.get_mobile_employee_directory(text, integer) is
  '0605: دليل الموظفين مع الحالات التشغيلية الدقيقة اليوم (مأمورية، قافلة، فاندي، إجازة، حضور).';

revoke all on function public.get_mobile_employee_directory(text, integer) from public;
grant execute on function public.get_mobile_employee_directory(text, integer) to authenticated;
