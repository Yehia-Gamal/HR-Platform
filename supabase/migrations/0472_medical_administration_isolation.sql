-- =====================================================================
-- 0472: عزل الإدارة الطبية (العيادات) — إدارة منفصلة داخل التطبيق
-- ---------------------------------------------------------------------
-- المطلب: فريق العيادات تحت مسؤول العيادات «مصطفى أحمد» يسجل حضوره
-- وانصرافه في التطبيق، دون أن يراه باقي الفريق ودون أن يرى هو إلا
-- القليل. القرارات المعتمدة: بصمة موبايل، full_access يرى الجميع في
-- التقارير، خدمات الموظف القياسية كاملة (إجازات/مأموريات يعتمدها
-- مديرها المباشر).
--
-- الآلية (نمط 0444 معمَّم على مستوى القسم):
--   1) departments.is_isolated — علم عزل يُفعَّل على أي قسم مستقبلاً.
--   2) is_employee_isolated / can_view_isolated_employee /
--      can_see_directory_entry — مساعدات مركزية للرؤية.
--   3) فلترة الدليل العام (متبادلة) وقوائم ولوحة الحضور (اتجاه واحد).
--   4) submit_request: موظف قسم معزول يستخدم medical_leave_v1 —
--      خطوة واحدة لمديره المباشر بدل السلسلة العامة.
--   5) دوران جديدان بوراثة صلاحيات direct-manager و employee.
-- =====================================================================

begin;

alter table public.departments add column if not exists is_isolated boolean not null default false;

-- ─── قسم الإدارة الطبية (تحت أقدم كيان — قابل للنقل إدارياً لاحقاً) ───
do $seed$
declare
  v_entity uuid;
begin
  select id into v_entity
    from public.legal_entities
   order by created_at asc nulls last, id asc
   limit 1;
  if v_entity is null then
    raise exception 'no legal entity found for medical department';
  end if;
  insert into public.departments(id, legal_entity_id, code, name, is_isolated)
  values (gen_random_uuid(), v_entity, 'MED-ADMIN', 'الإدارة الطبية', true)
  on conflict do nothing;
end $seed$;

-- ─── المساعدات المركزية ───
create or replace function public.is_employee_isolated(p_employee_id uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select coalesce((
    select d.is_isolated
      from public.employees e
      join public.departments d on d.id = e.department_id
     where e.id = p_employee_id
  ), false);
$$;

create or replace function public.can_view_isolated_employee(p_target uuid)
returns boolean
language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
begin
  if not public.is_employee_isolated(p_target) then return true; end if;
  if public.current_is_full_access() then return true; end if;
  if v_me is null then return false; end if;
  -- نفس القسم المعزول (زميل في الإدارة الطبية)
  if exists (
    select 1
      from public.employees t
     where t.id = p_target
       and t.department_id = (select e.department_id from public.employees e where e.id = v_me)
  ) then return true; end if;
  -- المدير المباشر (علاقة إشراف سارية)
  if exists (
    select 1 from public.manager_relations mr
     where mr.employee_id = p_target
       and mr.manager_employee_id = v_me
       and mr.effective_from <= now()
       and (mr.effective_to is null or mr.effective_to > now())
  ) then return true; end if;
  return false;
end $$;

-- رؤية الدليل متبادلة: المعزول لا يرى عام الفريق، والعام لا يرى المعزول.
create or replace function public.can_see_directory_entry(p_viewer uuid, p_target uuid)
returns boolean
language plpgsql stable security definer set search_path = public, pg_temp
as $$
begin
  if p_target = p_viewer then return true; end if;
  if public.current_is_full_access() then return true; end if;
  if p_viewer is null or p_target is null then return false; end if;
  -- المعزول لا يظهر لمن خارج نطاقه
  if public.is_employee_isolated(p_target)
     and not public.can_view_isolated_employee(p_target) then
    return false;
  end if;
  -- مشاهد معزول لا يرى عام الفريق (يرى قسمه ومديره فقط)
  if public.is_employee_isolated(p_viewer)
     and not public.is_employee_isolated(p_target) then
    -- يُسمح برؤية مديره المباشر فقط
    return exists (
      select 1 from public.manager_relations mr
       where mr.employee_id = p_viewer
         and mr.manager_employee_id = p_target
         and mr.effective_from <= now()
         and (mr.effective_to is null or mr.effective_to > now())
    );
  end if;
  return true;
end $$;

-- ─── الأدوار (وراثة صلاحيات الأدوار القياسية) ───
insert into public.roles (slug, name_ar, name_en, description, is_system, is_full_access)
values
  ('clinics-manager', 'مسؤول العيادات', 'Clinics Manager',
   'مدير الإدارة الطبية — يرى فريق عياداته ويقرر طلباتهم ضمن مسارهم الطبيعي', true, false),
  ('clinic-staff', 'موظف عيادات', 'Clinic Staff',
   'موظف الإدارة الطبية — حضور وانصراف وطلبات ذاتية فقط', true, false)
on conflict (slug) do nothing;

insert into public.role_permissions (role_id, permission_id, scope)
select new_role.id, tp.permission_id, tp.scope
  from public.roles new_role
  join public.roles template_role on template_role.slug = 'direct-manager'
  join public.role_permissions tp on tp.role_id = template_role.id
 where new_role.slug = 'clinics-manager'
on conflict (role_id, permission_id, scope) do nothing;

insert into public.role_permissions (role_id, permission_id, scope)
select new_role.id, tp.permission_id, tp.scope
  from public.roles new_role
  join public.roles template_role on template_role.slug = 'employee'
  join public.role_permissions tp on tp.role_id = template_role.id
 where new_role.slug = 'clinic-staff'
on conflict (role_id, permission_id, scope) do nothing;

-- ─── تعريف سير العمل الطبي: خطوة واحدة للمدير المباشر ───
insert into public.workflow_definitions (code, name_ar, description, request_type, version, is_active, is_default, auto_escalate, default_due_hours)
select 'medical_leave_v1', 'اعتماد الإدارة الطبية',
       'مسار الإدارة الطبية: اعتماد المدير المباشر (مسؤول العيادات) ثم اكتمال',
       'leave', 1, true, false, false, 48
where not exists (select 1 from public.workflow_definitions where code = 'medical_leave_v1');

insert into public.workflow_steps (definition_id, step_order, name_ar, step_type, approver_type, sla_hours)
select d.id, 1, 'مدير الإدارة الطبية', 'approval', 'direct_manager', 48
  from public.workflow_definitions d
 where d.code = 'medical_leave_v1'
   and not exists (
     select 1 from public.workflow_steps ws where ws.definition_id = d.id
   );

-- ═══ التعريفات المرقّعة (مولّدة من pg_get_functiondef للحالة الحية) ═══

CREATE OR REPLACE FUNCTION public.get_mobile_employee_directory(p_search text DEFAULT NULL::text, p_limit integer DEFAULT 40)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_search text := nullif(trim(coalesce(p_search, '')), '');
  v_today date := (now() at time zone 'Africa/Cairo')::date;
begin
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
        when ad.status in ('present','late','partial') then 'present'
        when ad.status = 'on_leave' then 'on_leave'
        when ad.status is not null and ad.status <> 'absent' then ad.status
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
      and not public.is_employee_executive(e.id)
     and public.can_see_directory_entry(public.current_employee_id(), e.id)  -- 0444: ╪º╪│╪¬╪¿╪╣╪º╪» ╪º┘ä┘à╪»┘è╪▒ ╪º┘ä╪¬┘å┘ü┘è╪░┘è
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
$function$;

CREATE OR REPLACE FUNCTION public.get_attendance_dashboard(p_date date DEFAULT NULL::date, p_department_id uuid DEFAULT NULL::uuid, p_branch_id uuid DEFAULT NULL::uuid, p_manager_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with params as (
    select coalesce(p_date, (now() at time zone 'Africa/Cairo')::date) as work_date
  ), visible_employees as (
    select e.id, e.department_id, e.branch_id
      from public.employees e
     where e.is_active = true
       and coalesce(e.is_deleted, false) = false
       and not public.is_employee_executive(e.id)  -- 0444: ╪º╪│╪¬╪¿╪╣╪º╪» ╪º┘ä┘à╪»┘è╪▒ ╪º┘ä╪¬┘å┘ü┘è╪░┘è
       and not (public.is_employee_isolated(e.id) and not public.can_view_isolated_employee(e.id))
       and (p_department_id is null or e.department_id = p_department_id)
       and (p_branch_id is null or e.branch_id = p_branch_id)
       and (
         p_manager_id is null or exists (
           select 1
             from public.manager_relations mr
            where mr.employee_id = e.id
              and mr.manager_employee_id = p_manager_id
              and mr.effective_from <= now()
              and (mr.effective_to is null or mr.effective_to > now())
         )
       )
  ), daily as (
    select d.*
      from public.attendance_daily d
      join params p on p.work_date = d.work_date
      join visible_employees ve on ve.id = d.employee_id
  ), visible_events as (
    select e.*
      from public.attendance_events e
      join params p on (e.event_at at time zone 'Africa/Cairo')::date = p.work_date
      join visible_employees ve on ve.id = e.employee_id
  ), approved_leaves as (
    select lr.employee_id, lt.is_paid, lt.code as leave_code
      from public.leave_requests lr
      join public.requests r on r.id = lr.request_id and r.status = 'approved'
      join public.leave_types lt on lt.id = lr.leave_type_id
      join params p on p.work_date between lr.start_date and lr.end_date
      join visible_employees ve on ve.id = lr.employee_id
  ), active_missions as (
    select distinct p.employee_id
      from public.work_assignment_participants p
      join public.work_assignments wa on wa.id = p.assignment_id
      join params prm on prm.work_date between wa.start_at::date and wa.end_at::date
     where wa.status in ('APPROVED','IN_PROGRESS')
  ), derived as (
    select
      ve.id as employee_id,
      d.id as daily_id,
      d.status as daily_status,
      d.first_check_in,
      d.last_check_out,
      coalesce(d.late_minutes, 0) as late_minutes,
      d.is_finalized,
      (al.employee_id is not null) as has_approved_leave,
      (am.employee_id is not null) as has_mission,
      case
        when d.id is not null and d.status in ('present','late')
             and d.first_check_in is not null and d.last_check_out is null
             and not d.is_finalized
          then 'missing_checkout'
        when am.employee_id is not null then 'on_mission'
        when d.id is not null then d.status
        when al.employee_id is not null then 'on_leave'
        when public.is_official_holiday((select work_date from params), ve.id) then 'holiday'
        when extract(isodow from (select work_date from params)) = 5 then 'weekend'
        else 'absent'
      end as derived_status
    from visible_employees ve
    left join daily d on d.employee_id = ve.id
    left join approved_leaves al on al.employee_id = ve.id
    left join active_missions am on am.employee_id = ve.id
  ), excused_absent as (
    select dv.employee_id
      from derived dv
      join visible_events e on e.employee_id = dv.employee_id
     where dv.derived_status = 'absent'
     group by dv.employee_id
    having count(e.id) > 0
  ), location_requests_day as (
    select llr.employee_id, llr.status, llr.requested_at, llr.responded_at,
           (llr.responded_at is not null or llr.status in ('accepted','active','completed')) as responded
      from public.live_location_requests llr
      join params p on (llr.requested_at at time zone 'Africa/Cairo')::date = p.work_date
         or (llr.responded_at is not null and (llr.responded_at at time zone 'Africa/Cairo')::date = p.work_date)
      join visible_employees ve on ve.id = llr.employee_id
  )
  select jsonb_build_object(
    'scheduled',
      case when extract(isodow from (select work_date from params)) = 5
           then (select count(distinct employee_id) from daily)
           else (select count(*) from visible_employees)
      end,
    'present', (select count(*) from derived where derived_status in ('present','late','partial','missing_checkout')),
    'late', (select count(*) from derived where derived_status = 'late' or late_minutes > 0),
    'absent', (select count(*) from derived where derived_status = 'absent'),
    'unexcusedAbsent', (select count(*) from derived where derived_status = 'absent' and employee_id not in (select employee_id from excused_absent)),
    'onLeave', (select count(*) from derived where derived_status = 'on_leave'),
    'onMission', (select count(*) from derived where derived_status = 'on_mission'),
    'missingCheckout', (select count(*) from derived where derived_status = 'missing_checkout'),
    'locationRequestsToday', (select count(*) from location_requests_day),
    'locationRespondedToday', (select count(*) from location_requests_day where responded),
    -- ┘à┘ü╪º╪¬┘è╪¡ 0444 ╪¬╪¿┘é┘ë ┘ä┘ä╪¬┘ê╪º┘ü┘é ┘à╪╣ ╪º┘ä┘ê╪º╪¼┘ç╪⌐ ╪º┘ä╪ú╪¡╪»╪½:
    'locationRequestsResponded', (select count(*) from location_requests_day where responded),
    'incomplete', (select count(*) from derived where derived_status in ('partial','pending')),
    'pendingReview', (select count(*) from visible_events where requires_review = true),
    'isWeekend', (extract(isodow from (select work_date from params)) = 5),
    'date', (select work_date from params),
    'lastUpdatedAt', now()
  );
$function$;

CREATE OR REPLACE FUNCTION public.get_attendance_day_roster(p_date date DEFAULT NULL::date, p_category text DEFAULT 'scheduled'::text, p_search text DEFAULT NULL::text, p_department_id uuid DEFAULT NULL::uuid, p_branch_id uuid DEFAULT NULL::uuid, p_manager_id uuid DEFAULT NULL::uuid, p_sort text DEFAULT 'name'::text, p_direction text DEFAULT 'asc'::text, p_limit integer DEFAULT 100, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_work_date date := coalesce(p_date, (now() at time zone 'Africa/Cairo')::date);
  v_search    text := nullif(trim(coalesce(p_search, '')), '');
  v_limit     int  := greatest(1, least(coalesce(p_limit, 100), 500));
  v_offset    int  := greatest(0, coalesce(p_offset, 0));
  v_result    jsonb;
begin
  if p_category not in (
    'scheduled','present','late','absent','unexcused_absent',
    'incomplete','pending_review','location_requests','location_responded',
    'on_leave','on_mission','missing_checkout'
  ) then
    raise exception 'invalid attendance roster category: %', p_category
      using errcode = '22023';
  end if;
  if p_limit is not null and p_limit <= 0 then
    raise exception 'invalid roster limit: %', p_limit using errcode = '22023';
  end if;
  if p_offset is not null and p_offset < 0 then
    raise exception 'invalid roster offset: %', p_offset using errcode = '22023';
  end if;
  if p_sort not in ('name','check_in','late','status') then
    raise exception 'invalid roster sort: %', p_sort using errcode = '22023';
  end if;
  if p_direction not in ('asc','desc') then
    raise exception 'invalid roster direction: %', p_direction using errcode = '22023';
  end if;

  with visible_employees as (
      select e.id, e.employee_code, e.full_name_ar, e.photo_url,
             e.department_id, e.branch_id,
             d.name as department_name,
             b.name as branch_name,
             jt.name as job_title,
             mr.manager_employee_id,
             me.full_name_ar as manager_name
      from public.employees e
      left join public.departments d on d.id = e.department_id
      left join public.branches b on b.id = e.branch_id
      left join public.job_titles jt on jt.id = e.job_title_id
      left join lateral (
        select mr.manager_employee_id
          from public.manager_relations mr
         where mr.employee_id = e.id
           and mr.relation_type = 'primary'
           and mr.effective_to is null
         order by mr.effective_from desc
         limit 1
      ) mr on true
      left join public.employees me on me.id = mr.manager_employee_id
     where e.is_active = true and coalesce(e.is_deleted, false) = false
       and (p_department_id is null or e.department_id = p_department_id)
       and (p_branch_id is null or e.branch_id = p_branch_id)
       and (p_manager_id is null or mr.manager_employee_id = p_manager_id)
       and not (public.is_employee_isolated(e.id) and not public.can_view_isolated_employee(e.id))
       and (v_search is null
         or lower(e.full_name_ar) like '%' || v_search || '%'
         or lower(e.employee_code) like '%' || v_search || '%')
  ), daily as (
    select d.* from public.attendance_daily d where d.work_date = v_work_date
  ), events_day as (
    select e.* from public.attendance_events e
     where (e.event_at at time zone 'Africa/Cairo')::date = v_work_date
  ), approved_leaves as (
    select distinct on (lr.employee_id)
           lr.employee_id, lt.is_paid, lt.code as leave_code
      from public.leave_requests lr
      join public.requests r on r.id = lr.request_id and r.status = 'approved'
      join public.leave_types lt on lt.id = lr.leave_type_id
     where v_work_date between lr.start_date and lr.end_date
     order by lr.employee_id, lr.start_date desc
  ), active_missions as (
    select distinct p.employee_id
      from public.work_assignment_participants p
      join public.work_assignments wa on wa.id = p.assignment_id
     where wa.status in ('APPROVED','IN_PROGRESS')
       and v_work_date between wa.start_at::date and wa.end_at::date
  ), excused_absent as (
    select dv.employee_id
      from (
        select ve.id as employee_id,
               d.status as daily_status,
               (al.employee_id is not null) as has_approved_leave,
               (am.employee_id is not null) as has_mission
          from visible_employees ve
          left join daily d on d.employee_id = ve.id
          left join approved_leaves al on al.employee_id = ve.id
          left join active_missions am on am.employee_id = ve.id
      ) dv
      left join approved_leaves al on al.employee_id = dv.employee_id
      left join events_day e on e.employee_id = dv.employee_id
     where dv.daily_status = 'absent'
     group by dv.employee_id
    having count(al.employee_id) filter (
             where al.is_paid or coalesce(al.leave_code, '') <> 'sick'
           ) > 0
      or count(e.id) > 0
  ), location_requests_day as (
    select distinct on (llr.employee_id)
           llr.employee_id, llr.status as llr_status, llr.requested_at, llr.responded_at,
           (llr.responded_at is not null or llr.status in ('accepted','active','completed')) as responded
      from public.live_location_requests llr
     where (llr.requested_at at time zone 'Africa/Cairo')::date = v_work_date
        or (llr.responded_at is not null and (llr.responded_at at time zone 'Africa/Cairo')::date = v_work_date)
     order by llr.employee_id, llr.requested_at desc
  ), review_reasons as (
    select distinct on (e.employee_id) e.employee_id,
           case
             when e.verification_status = 'failed' then '┘ü╪┤┘ä ╪º┘ä╪¬╪¡┘é┘é ┘à┘å ╪º┘ä┘ç┘ê┘è╪⌐'
             when e.latitude is null or e.longitude is null then '┘ä╪º ┘è┘ê╪¼╪» ┘à┘ê┘é╪╣ ┘à╪ñ┘â╪»'
             when e.accuracy_meters is not null and e.accuracy_meters > 100 then '╪»┘é╪⌐ GPS ┘à┘å╪«┘ü╪╢╪⌐'
             when e.distance_meters is not null and e.distance_meters > 0 then '╪«╪º╪▒╪¼ ╪º┘ä┘å╪╖╪º┘é ╪º┘ä┘à╪╣╪¬┘à╪»'
             when e.status = 'flagged' then '╪ú┘Å╪┤╪╣┘É╪▒ ╪¬┘ä┘é╪º╪ª┘è┘ï╪º ┘ä┘ä┘à╪▒╪º╪¼╪╣╪⌐'
             else '┘è╪¡╪¬╪º╪¼ ┘à╪▒╪º╪¼╪╣╪⌐ ╪¿╪┤╪▒┘è╪⌐'
           end as reason
      from events_day e
     where e.requires_review = true
     order by e.employee_id, e.created_at desc
  ), base as (
    select
      ve.id            as employee_id,
      ve.employee_code,
      ve.full_name_ar,
      ve.photo_url,
      ve.department_id,
      ve.department_name,
      ve.branch_id,
      ve.branch_name,
      ve.job_title,
      ve.manager_employee_id,
      ve.manager_name,
      d.id             as daily_id,
      d.status         as daily_status,
      d.first_check_in,
      d.last_check_out,
      coalesce(d.late_minutes, 0) as late_minutes,
      coalesce(d.is_finalized, false) as is_finalized,
      s.name           as shift_name,
      s.start_time     as shift_start,
      s.end_time       as shift_end,
      coalesce((select bool_or(e.requires_review) from events_day e where e.employee_id = ve.id), false) as requires_review,
      rr.reason        as review_reason,
      (al.employee_id is not null) as has_approved_leave,
      al.leave_code,
      al.is_paid       as leave_is_paid,
      (am.employee_id is not null) as has_mission,
      lrd.llr_status   as location_request_status,
      lrd.requested_at as location_requested_at,
      lrd.responded_at as location_responded_at,
      coalesce(lrd.responded, false) as location_responded_today,
      case
        when d.id is not null and d.status in ('present','late')
             and d.first_check_in is not null and d.last_check_out is null
             and not d.is_finalized
          then 'missing_checkout'
        when am.employee_id is not null then 'on_mission'
        when d.id is not null then d.status
        when al.employee_id is not null then 'on_leave'
        when public.is_official_holiday(v_work_date, ve.id) then 'holiday'
        when extract(isodow from v_work_date) = 5 then 'weekend'
        else 'absent'
      end as derived_status
    from visible_employees ve
    left join daily d on d.employee_id = ve.id
    left join public.shifts s on s.id = d.shift_id
    left join review_reasons rr on rr.employee_id = ve.id
    left join approved_leaves al on al.employee_id = ve.id
    left join active_missions am on am.employee_id = ve.id
    left join location_requests_day lrd on lrd.employee_id = ve.id
  ), categorized as (
    select b.*,
           case p_sort
             when 'check_in' then coalesce(to_char(b.first_check_in, 'YYYY-MM-DD HH24:MI:SS'), '9999-99-99 99:99:99')
             when 'late'     then lpad(coalesce(b.late_minutes::text, '0'), 12, '0')
             when 'status'   then coalesce(b.derived_status, '')
             else coalesce(b.full_name_ar, '')
           end as sort_key
      from base b
     where case p_category
        when 'scheduled'          then true
        when 'present'            then b.derived_status in ('present','late','partial','missing_checkout')
        when 'late'               then b.derived_status = 'late' or b.late_minutes > 0
        when 'absent'             then b.derived_status = 'absent'
        when 'unexcused_absent'   then b.derived_status = 'absent'
                                     and b.employee_id not in (select employee_id from excused_absent)
        when 'incomplete'         then b.derived_status in ('partial','pending')
        when 'on_leave'           then b.derived_status = 'on_leave'
        when 'on_mission'         then b.derived_status = 'on_mission'
        when 'missing_checkout'   then b.derived_status = 'missing_checkout'
        when 'pending_review'     then b.requires_review = true
        when 'location_requests'  then b.location_requested_at is not null
                                    or b.location_responded_at is not null
        when 'location_responded' then b.location_responded_today = true
        else false
      end
  )
  select jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(item)
        from (
          select jsonb_build_object(
            'employeeId', c.employee_id,
            'employeeCode', c.employee_code,
            'employeeName', c.full_name_ar,
            'photoUrl', c.photo_url,
            'departmentId', c.department_id,
            'departmentName', c.department_name,
            'branchId', c.branch_id,
            'branchName', c.branch_name,
            'jobTitle', c.job_title,
            'managerId', c.manager_employee_id,
            'managerName', c.manager_name,
            'status', c.derived_status,
            'lateMinutes', c.late_minutes,
            'firstCheckIn', c.first_check_in,
            'lastCheckOut', c.last_check_out,
            'shiftName', c.shift_name,
            'shiftStartAt', c.shift_start,
            'shiftEndAt', c.shift_end,
            'requiresReview', c.requires_review,
            'reviewReason', c.review_reason,
            'hasApprovedLeave', c.has_approved_leave,
            'leaveCode', c.leave_code,
            'leaveIsPaid', c.leave_is_paid,
            'hasMission', c.has_mission,
            'locationRequestStatus', c.location_request_status,
            'locationRequestedAt', c.location_requested_at,
            'locationRespondedAt', c.location_responded_at
          ) as item
          from categorized c
          order by
            case when p_direction = 'desc' then c.sort_key end desc,
            case when p_direction = 'asc'  then c.sort_key end asc,
            c.full_name_ar asc
          limit v_limit offset v_offset
        ) t
    ), '[]'::jsonb),
    'total', (select count(*) from categorized),
    'limit', v_limit,
    'offset', v_offset
  ) into v_result;

  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public._submit_request_for(p_employee_id uuid, p_request_type text, p_workflow_definition_id uuid DEFAULT NULL::uuid, p_manager_employee_id uuid DEFAULT NULL::uuid, p_title text DEFAULT NULL::text, p_reason text DEFAULT NULL::text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me             uuid := public.current_employee_id();
  v_def            public.workflow_definitions;
  v_due            timestamptz;
  v_esc            timestamptz;
  v_row            public.requests;
  v_first_approver uuid;
  v_exec_emp       uuid;
  v_label          text;
begin
  if p_employee_id is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;

  if p_request_type not in ('leave','mission','convoy','fundraising','late_permit','early_permit','attendance_correction') then
    raise exception 'invalid request_type: %', p_request_type using errcode = '22023';
  end if;

  if p_manager_employee_id is not null and p_manager_employee_id = p_employee_id then
    raise exception 'self-approval is not allowed (manager cannot be requester)' using errcode = '42501';
  end if;

  -- ╪º┘ä╪¬╪╣╪▒┘è┘ü ╪º┘ä╪º┘ü╪¬╪▒╪º╪╢┘è ┘ä╪│┘è╪▒ ╪º┘ä╪╣┘à┘ä
  if p_workflow_definition_id is not null then
    select * into v_def from public.workflow_definitions where id = p_workflow_definition_id;
  else
    -- 0472: موظف قسم معزول (الإدارة الطبية) يستخدم تعريفه أحادي الخطوة
    if public.is_employee_isolated(p_employee_id) then
      select * into v_def from public.workflow_definitions
        where code = 'medical_leave_v1' and request_type = p_request_type and is_active = true
        order by version desc limit 1;
    end if;
    if v_def.id is null then
      select * into v_def from public.workflow_definitions
        where request_type = p_request_type and is_default = true and is_active = true
        order by version desc limit 1;
    end if;
  end if;

  if v_def.id is not null then
    v_due := now() + make_interval(hours => coalesce(v_def.default_due_hours, 48));
    if v_def.auto_escalate then v_esc := v_due; end if;
  else
    v_due := now() + interval '48 hours';
  end if;

  insert into public.requests (
    request_type, employee_id, manager_employee_id, workflow_definition_id,
    status, workflow_status, title, reason, decision_due_at, escalation_deadline,
    payload, created_by
  ) values (
    p_request_type, p_employee_id, p_manager_employee_id, v_def.id,
    'pending', 'submitted', p_title, p_reason, v_due, v_esc,
    coalesce(p_payload, '{}'::jsonb), auth.uid()
  )
  returning * into v_row;

  -- ╪Ñ┘å╪┤╪º╪í ╪«╪╖┘ê╪º╪¬ ╪º┘ä╪¼╪º╪▒┘è╪⌐
  if v_def.id is not null then
    insert into public.request_steps (
      request_id, workflow_step_id, step_order, name_ar, step_type,
      assignee_employee_id, assignee_role_slug, status, sla_hours,
      due_at, escalation_deadline, created_by
    )
    select
      v_row.id, ws.id, ws.step_order, ws.name_ar, ws.step_type,
      case when ws.approver_type = 'specific_employee' then ws.approver_employee_id
           when ws.approver_type in ('direct_manager','department_manager') then p_manager_employee_id
           else null end,
      ws.approver_role_slug,
      case when ws.step_order = 1 then 'active' else 'pending' end,
      ws.sla_hours,
      case when ws.step_order = 1
           then now() + make_interval(hours => coalesce(ws.sla_hours, 48)) end,
      case when ws.step_order = 1 and ws.escalate_after_hours is not null
           then now() + make_interval(hours => ws.escalate_after_hours) end,
      auth.uid()
    from public.workflow_steps ws
    where ws.definition_id = v_def.id and ws.is_active = true
    order by ws.step_order;

    insert into public.workflow_instances (
      definition_id, request_id, definition_version, status, current_step_order, created_by
    ) values (
      v_def.id, v_row.id, coalesce(v_def.version, 1), 'running', 1, auth.uid()
    );
  end if;

  insert into public.request_actions (
    request_id, actor_employee_id, action, to_status, comment, created_by
  ) values (v_row.id, v_me, 'submit', 'pending', p_reason, auth.uid());

  v_label := format('%s ΓÇö %s',
    public.request_type_label(v_row.request_type),
    coalesce(v_row.title, ''));

  -- ╪Ñ╪┤╪╣╪º╪▒ ╪º┘ä┘à╪»┘è╪▒ ╪º┘ä┘à╪¿╪º╪┤╪▒ (╪ú┘ê┘ä ╪«╪╖┘ê╪⌐ ┘å╪┤╪╖╪⌐)
  select s.assignee_employee_id into v_first_approver
  from public.request_steps s
  where s.request_id = v_row.id and s.status = 'active'
  order by s.step_order limit 1;

  if v_first_approver is null then
    v_first_approver := v_row.manager_employee_id;
  end if;

  if v_first_approver is not null and v_first_approver <> v_row.employee_id then
    perform public.notify_employee(
      v_first_approver,
      '╪╖┘ä╪¿ ╪¼╪»┘è╪» ╪¿╪º┘å╪¬╪╕╪º╪▒ ┘à╪▒╪º╪¼╪╣╪¬┘â',
      v_label,
      'request', 'high', 'request', v_row.id,
      jsonb_build_object(
        'requestType', v_row.request_type,
        'workflowStatus', 'submitted',
        'deepLink', '/requests/' || v_row.id
      )
    );
  end if;

  -- ╪Ñ╪┤╪╣╪º╪▒ ╪º┘ä┘à╪»┘è╪▒ ╪º┘ä╪¬┘å┘ü┘è╪░┘è ΓÇö ╪Ñ┘å╪¿╪º┘ç ┘â╪º┘à┘ä ╪º┘ä╪┤╪º╪┤╪⌐ ╪╣┘ä┘ë ┘â┘ä ╪╖┘ä╪¿ ╪¼╪»┘è╪»
  v_exec_emp := public.first_active_employee_for_role('executive-director');
  if v_exec_emp is not null
     and v_exec_emp <> v_row.employee_id
     and v_exec_emp is distinct from v_first_approver then
    perform public.notify_executive_fullscreen(
      '╪╖┘ä╪¿ ╪¼╪»┘è╪» ΓÇö ┘ä┘ä┘à╪▒╪º╪¼╪╣╪⌐',
      v_label,
      'request',
      'request', v_row.id,
      '/requests/' || v_row.id,
      jsonb_build_object(
        'requestType', v_row.request_type,
        'infoOnly', false
      )
    );
  end if;

  return v_row;
end;
$function$;

commit;

notify pgrst, 'reload schema';
