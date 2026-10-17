-- ============================================================================
-- 0664: فترات الدوام الإداري والإدارة المشتركة لمصطفى أحمد ويوسف رسمي
-- ============================================================================
-- 1) فترات الورديات لمصطفى أحمد ويوسف رسمي:
--    - مصطفى أحمد كمال الدين ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c')
--      ويوسف رسمي شعبان ('a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6')
--      لهما الفترات المرنة الثلاث للتيم الإداري:
--      (9 ص – 5 م)، (10 ص – 6 م)، (11 ص – 7 م) وليس ورديات العيادات.
--    - تحديث get_my_work_shift_info لضمان إرجاع الورديات الإدارية الثلاث لهما.
--    - إلغاء قيد الوردية المجزأة (split shift) عن يوسف رسمي ليعامل إدارياً كباقي الفريق.
--
-- 2) الإدارة المشتركة وإدارة التيم الإداري وقبول الطلبات:
--    - يوسف رسمي مسؤول عن تيم العيادات جنباً إلى جنب مع مصطفى أحمد، ويسري عليه
--      ما يسري على مصطفى أحمد من كل شيء.
--    - منح يوسف رسمي أدوار clinics-manager و direct-manager و department-manager.
--    - استثناء مصطفى أحمد ويوسف رسمي من قيود أفراد العيادات (is_clinic_team_member).
--    - تحديث resolve_request_approver و submit_request لدعم الإشراف المشترك.
--    - تحديث decide_request لمنح مصطفى أحمد ويوسف رسمي كامل صلاحية البت والاعتماد
--      على طلبات طاقم العيادات والتيم الإداري دون تصعيد قسري.
--    - تحديث request_live_location و can_view_isolated_employee و get_employee_home
--      و get_my_access_context.
-- ============================================================================

begin;

-- ─── 1) إلغاء قيد الوردية المجزأة عن يوسف رسمي ──────────────────────────────
update public.employees
set is_split_shift = false
where id = 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6';

create or replace function public.is_employee_split_shift(p_employee_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select exists (
    select 1 from public.employees
    where id = p_employee_id and is_split_shift = true
  ) or coalesce(p_employee_id = '7d879f2d-b4d4-4da0-93d6-14e542e7fef3'::uuid, false);
$fn$;

revoke all on function public.is_employee_split_shift(uuid) from public, anon;
grant execute on function public.is_employee_split_shift(uuid) to authenticated, service_role;

-- ─── 2) منح أدوار الإدارة ليوسف رسمي (clinics-manager, direct-manager, department-manager) ───
with yr_emp as (
  select user_id from public.employees
  where id = 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6' and user_id is not null limit 1
), target_roles as (
  select id from public.roles
  where slug in ('clinics-manager', 'direct-manager', 'department-manager')
)
insert into public.user_roles (user_id, role_id, granted_by, effective_from)
select yr_emp.user_id, target_roles.id, null::uuid, now() at time zone 'Africa/Cairo'
from yr_emp, target_roles
where not exists (
  select 1 from public.user_roles ur
  where ur.user_id = yr_emp.user_id
    and ur.role_id = target_roles.id
    and (ur.effective_to is null or ur.effective_to > now())
);

-- ─── 3) فحص أفراد طاقم العيادات (الموظفون المستهدفون دون المديرين) ───────────
create or replace function public.is_clinic_team_member(p_employee_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.employees e
    left join public.departments d on d.id = e.department_id
    where e.id = p_employee_id
      -- مصطفى أحمد ويوسف رسمي مديرون للتيم، لا يسري عليهم حصر العيادات
      and e.id not in (
        '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid,
        'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid
      )
      and (
        public.is_clinic_staff_exempt(e.id)
        or public.is_employee_isolated(e.id)
        or coalesce(d.is_isolated, false) = true
        or coalesce(d.code, '') in ('MED-ADMIN', 'CLINICS')
        or coalesce(d.name, '') like '%عياد%'
        or exists (
          select 1 from public.manager_relations mr
          where mr.employee_id = e.id
            and mr.manager_employee_id in (
              '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid,
              'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid
            )
            and mr.effective_from <= now()
            and (mr.effective_to is null or mr.effective_to >= now())
        )
      )
  );
$$;

revoke all on function public.is_clinic_team_member(uuid) from public, anon;
grant execute on function public.is_clinic_team_member(uuid) to service_role, authenticated;

comment on function public.is_clinic_team_member(uuid) is
  '0664: فحص ما إذا كان الموظف يتبع طاقم العيادات (باستثناء المديرين مصطفى أحمد ويوسف رسمي)';

-- ─── 4) تحديث get_my_work_shift_info: 3 فترات إدارية لمصطفى أحمد ويوسف رسمي ─
create or replace function public.get_my_work_shift_info()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me            uuid := public.current_employee_id();
  v_today         date := (now() at time zone 'Africa/Cairo')::date;
  v_assign        record;
  v_default_shift record;
  v_current_shift jsonb;
  v_available     jsonb;
  v_pending       jsonb := null;
  v_req           record;
  v_today_permit  record;
  v_permit_obj    jsonb := null;
  v_shift_start   time;
  v_shift_end     time;
  v_shift_grace   integer := 15;
  v_eff_start     time;
  v_eff_grace_end time;
  v_eff_end       time;
  v_has_permit    boolean := false;
  v_is_clinic     boolean := false;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  -- مصطفى أحمد ويوسف رسمي لهما الورديات الإدارية الثلاث كباقي التيم الإداري
  v_is_clinic := public.is_clinic_team_member(v_me)
                 and v_me not in (
                   '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid,
                   'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid
                 );

  -- 1) فحص الوردية المعتمدة المسندة حالياً للموظف
  select sa.id as assignment_id, sa.effective_from, sa.notes,
         s.id as shift_id, s.code, s.name, s.name_en, s.start_time, s.end_time,
         coalesce(s.grace_in_minutes, 15) as grace_in_minutes
    into v_assign
    from public.shift_assignments sa
    join public.shifts s on s.id = sa.shift_id
   where sa.employee_id = v_me
     and sa.is_active = true
     and sa.effective_from <= v_today
     and (sa.effective_to is null or sa.effective_to >= v_today)
   order by sa.effective_from desc
   limit 1;

  if v_assign.shift_id is not null then
    v_shift_start := coalesce(v_assign.start_time, '10:00:00'::time);
    v_shift_end := coalesce(v_assign.end_time, '18:00:00'::time);
    v_shift_grace := coalesce(v_assign.grace_in_minutes, 15);
  else
    -- الدوام الأساسي الافتراضي العام (10 ص – 6 م)
    select s.id, s.code, s.name, s.name_en, s.start_time, s.end_time,
           coalesce(s.grace_in_minutes, 15) as grace_in_minutes
      into v_default_shift
      from public.shifts s
     where s.code = 'OFFICIAL' and s.is_active
     limit 1;

    if v_default_shift.id is null then
      select s.id, s.code, s.name, s.name_en, s.start_time, s.end_time,
             coalesce(s.grace_in_minutes, 15) as grace_in_minutes
        into v_default_shift
        from public.shifts s
       where s.id = public.default_shift_id();
    end if;

    v_shift_start := coalesce(v_default_shift.start_time, '10:00:00'::time);
    v_shift_end := coalesce(v_default_shift.end_time, '18:00:00'::time);
    v_shift_grace := coalesce(v_default_shift.grace_in_minutes, 15);
  end if;

  -- 2) فحص أي إذن معتمد لليوم
  select r.id, r.request_type, r.title, r.status, r.payload,
         coalesce(
           (r.payload->>'minutes')::integer,
           (r.payload->>'duration')::integer,
           ((r.payload->>'hours')::numeric * 60)::integer,
           120
         ) as permit_minutes,
         coalesce(r.payload->>'permitKind',
                  case when r.request_type = 'early_permit' then 'early_departure' else 'late_arrival' end) as permit_kind
    into v_today_permit
    from public.requests r
   where r.employee_id = v_me
     and r.status not in ('rejected', 'cancelled')
     and r.request_type in ('late_permit', 'early_permit', 'permit', 'permission', 'errand', 'late_excuse')
     and coalesce(
       public.try_cast_date(r.payload->>'permitDate'),
       public.try_cast_date(r.payload->>'date'),
       public.try_cast_date(r.payload->>'startDate'),
       public.try_cast_date(r.payload->>'start_date'),
       public.try_cast_date(r.payload->>'workDate'),
       r.created_at::date
     ) = v_today
   order by r.created_at desc
   limit 1;

  v_eff_start := v_shift_start;
  v_eff_grace_end := (v_shift_start + (v_shift_grace || ' minutes')::interval)::time;
  v_eff_end := v_shift_end;

  if v_today_permit.id is not null then
    v_has_permit := true;
    if v_today_permit.permit_kind = 'late_arrival' then
      v_eff_start := (v_shift_start + (v_today_permit.permit_minutes || ' minutes')::interval)::time;
      v_eff_grace_end := (v_eff_start + (v_shift_grace || ' minutes')::interval)::time;
    elsif v_today_permit.permit_kind = 'early_departure' then
      v_eff_end := (v_shift_end - (v_today_permit.permit_minutes || ' minutes')::interval)::time;
    end if;

    v_permit_obj := jsonb_build_object(
      'id', v_today_permit.id,
      'requestType', v_today_permit.request_type,
      'title', coalesce(v_today_permit.title, 'إذن معتمد'),
      'permitMinutes', v_today_permit.permit_minutes,
      'permitKind', v_today_permit.permit_kind,
      'status', v_today_permit.status,
      'effectiveStartTime', to_char(v_eff_start, 'HH24:MI:SS'),
      'effectiveGraceEndTime', to_char(v_eff_grace_end, 'HH24:MI:SS'),
      'effectiveEndTime', to_char(v_eff_end, 'HH24:MI:SS')
    );
  end if;

  -- بناء كائن الوردية الحالية
  if v_assign.shift_id is not null then
    v_current_shift := jsonb_build_object(
      'id', v_assign.shift_id,
      'code', v_assign.code,
      'name', v_assign.name,
      'nameEn', v_assign.name_en,
      'startTime', to_char(v_shift_start, 'HH24:MI:SS'),
      'endTime', to_char(v_shift_end, 'HH24:MI:SS'),
      'graceInMinutes', v_shift_grace,
      'isAssigned', true,
      'assignmentId', v_assign.assignment_id,
      'effectiveFrom', v_assign.effective_from,
      'status', 'approved',
      'hasPermitToday', v_has_permit,
      'effectiveStartTime', to_char(v_eff_start, 'HH24:MI:SS'),
      'effectiveGraceEndTime', to_char(v_eff_grace_end, 'HH24:MI:SS'),
      'effectiveEndTime', to_char(v_eff_end, 'HH24:MI:SS')
    );
  else
    v_current_shift := jsonb_build_object(
      'id', v_default_shift.id,
      'code', coalesce(v_default_shift.code, 'OFFICIAL'),
      'name', coalesce(v_default_shift.name, 'الدوام الأساسي (10 ص – 6 م)'),
      'nameEn', v_default_shift.name_en,
      'startTime', to_char(v_shift_start, 'HH24:MI:SS'),
      'endTime', to_char(v_shift_end, 'HH24:MI:SS'),
      'graceInMinutes', v_shift_grace,
      'isAssigned', false,
      'assignmentId', null,
      'effectiveFrom', v_today,
      'status', 'default',
      'hasPermitToday', v_has_permit,
      'effectiveStartTime', to_char(v_eff_start, 'HH24:MI:SS'),
      'effectiveGraceEndTime', to_char(v_eff_grace_end, 'HH24:MI:SS'),
      'effectiveEndTime', to_char(v_eff_end, 'HH24:MI:SS')
    );
  end if;

  -- 3) قائمة الورديات المرنة المتاحة للاختيار
  if v_is_clinic then
    -- لطاقم العيادات فقط: ورديتان (10 ص – 6 م) و (3 ع – 11 م)
    select coalesce(jsonb_agg(
             jsonb_build_object(
               'id', s.id,
               'code', s.code,
               'name', s.name,
               'nameEn', s.name_en,
               'startTime', to_char(s.start_time, 'HH24:MI:SS'),
               'endTime', to_char(s.end_time, 'HH24:MI:SS'),
               'graceInMinutes', coalesce(s.grace_in_minutes, 15),
               'isDefault', (s.code = 'OFFICIAL'),
               'description', case s.code
                 when 'OFFICIAL' then 'فترة صباحية تبدأ 10:00 ص (سماح حتى 10:15 ص) وتنتهي 6:00 م'
                 when 'SHIFT_CLINIC_3_11' then 'فترة مسائية تبدأ 3:00 عصراً (سماح حتى 3:15 ع) وتنتهي 11:00 م'
                 else 'فترة عمل معتمدة للعيادات'
               end
             ) order by s.start_time asc
           ), '[]'::jsonb)
      into v_available
      from public.shifts s
     where s.is_active = true
       and s.code in ('OFFICIAL', 'SHIFT_CLINIC_3_11');
  else
    -- للتيم الإداري (بما في ذلك مصطفى أحمد ويوسف رسمي وباقي الموظفين): 3 فترات مرنة
    select coalesce(jsonb_agg(
             jsonb_build_object(
               'id', s.id,
               'code', s.code,
               'name', s.name,
               'nameEn', s.name_en,
               'startTime', to_char(s.start_time, 'HH24:MI:SS'),
               'endTime', to_char(s.end_time, 'HH24:MI:SS'),
               'graceInMinutes', coalesce(s.grace_in_minutes, 15),
               'isDefault', (s.code = 'OFFICIAL'),
               'description', case s.code
                 when 'SHIFT_9_5' then 'فترة صباحية تبدأ 9:00 ص (سماح حتى 9:15 ص) وتنتهي 5:00 م'
                 when 'OFFICIAL' then 'الدوام الأساسي العام يبدأ 10:00 ص (سماح حتى 10:15 ص) وينتهي 6:00 م'
                 when 'SHIFT_11_7' then 'فترة مسائية تبدأ 11:00 ص (سماح حتى 11:15 ص) وتنتهي 7:00 م'
                 else 'فترة عمل معتمدة'
               end
             ) order by s.start_time asc
           ), '[]'::jsonb)
      into v_available
      from public.shifts s
     where s.is_active = true
       and s.code in ('SHIFT_9_5', 'OFFICIAL', 'SHIFT_11_7');
  end if;

  -- 4) فحص أي طلب معلق لتغيير فترة العمل
  select r.id, r.title, r.reason, r.created_at, r.status,
         r.payload->>'shiftId' as requested_shift_id,
         r.payload->>'shiftName' as requested_shift_name
    into v_req
    from public.requests r
   where r.employee_id = v_me
     and r.request_type = 'shift_change'
     and r.status = 'pending'
   order by r.created_at desc
   limit 1;

  if v_req.id is not null then
    v_pending := jsonb_build_object(
      'requestId', v_req.id,
      'title', v_req.title,
      'reason', v_req.reason,
      'requestedShiftId', v_req.requested_shift_id,
      'requestedShiftName', v_req.requested_shift_name,
      'createdAt', v_req.created_at,
      'status', v_req.status
    );
  end if;

  return jsonb_build_object(
    'currentShift', v_current_shift,
    'availableShifts', v_available,
    'pendingRequest', v_pending,
    'todayPermit', v_permit_obj
  );
end;
$$;

revoke all on function public.get_my_work_shift_info() from public, anon;
grant execute on function public.get_my_work_shift_info() to authenticated;

-- ─── 5) تحديث resolve_request_approver للإدارة المشتركة ───────────────────────
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
  v_dept_mgr uuid;
  v_emp_mgr uuid;
  v_delegate uuid;
begin
  if p_employee_id is null then return null; end if;

  -- ★ طاقم العيادات (الموظفون): معتمدهم المباشر مصطفى أحمد أو يوسف رسمي ★
  if public.is_clinic_team_member(p_employee_id)
     and p_employee_id not in (
       '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid,
       'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid
     ) then
    -- فحص إذا كان للموظف علاقة مدير مباشر نشطة مع يوسف رسمي أو مصطفى أحمد
    select mr.manager_employee_id into v_mgr
    from public.manager_relations mr
    where mr.employee_id = p_employee_id
      and mr.manager_employee_id in (
        '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid,
        'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid
      )
      and mr.relation_type = 'primary'
      and mr.effective_from <= p_as_of
      and (mr.effective_to is null or mr.effective_to >= p_as_of)
    order by (mr.effective_to is null) desc, mr.created_at desc
    limit 1;

    if v_mgr is null then
      v_mgr := '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid;
    end if;
  else
    -- 1) المدير المباشر الفعلي النشط من manager_relations
    select mr.manager_employee_id into v_mgr
    from public.manager_relations mr
    where mr.employee_id = p_employee_id
      and mr.relation_type = 'primary'
      and mr.effective_from <= p_as_of
      and (mr.effective_to is null or mr.effective_to >= p_as_of)
      and mr.manager_employee_id <> p_employee_id
    order by (mr.effective_to is null) desc, mr.created_at desc
    limit 1;

    -- 2) مدير القسم من departments.manager_id
    if v_mgr is null then
      select e.department_id into v_dept_id
      from public.employees e
      where e.id = p_employee_id;

      if v_dept_id is not null then
        select d.manager_id into v_dept_mgr
        from public.departments d
        where d.id = v_dept_id and d.is_active;

        if v_dept_mgr is not null and v_dept_mgr <> p_employee_id then
          v_mgr := v_dept_mgr;
        else
          select parent_dept.manager_id into v_dept_mgr
          from public.departments child_dept
          join public.departments parent_dept on parent_dept.id = child_dept.parent_id
          where child_dept.id = v_dept_id and parent_dept.is_active
            and parent_dept.manager_id is not null
            and parent_dept.manager_id <> p_employee_id
          limit 1;

          if v_dept_mgr is not null then
            v_mgr := v_dept_mgr;
          end if;
        end if;
      end if;
    end if;

    -- 3) عمود manager_id المخزن على الموظف
    if v_mgr is null and v_emp_mgr is not null and v_emp_mgr <> p_employee_id then
      if exists (select 1 from public.employees where id = v_emp_mgr and is_active and not is_deleted) then
        v_mgr := v_emp_mgr;
      end if;
    end if;

    -- 4) مدير الموارد البشرية (hr-manager)
    if v_mgr is null then
      select e.id into v_mgr
      from public.employees e
      join public.user_roles ur on ur.user_id = e.user_id
      join public.roles r on r.id = ur.role_id
      where r.slug = 'hr-manager'
        and e.is_active and not e.is_deleted
        and e.id <> p_employee_id
        and (ur.effective_to is null or ur.effective_to > now())
      order by e.created_at
      limit 1;
    end if;

    -- 5) مسؤول الموارد البشرية (hr-specialist / hr-officer)
    if v_mgr is null then
      select e.id into v_mgr
      from public.employees e
      join public.user_roles ur on ur.user_id = e.user_id
      join public.roles r on r.id = ur.role_id
      where r.slug in ('hr-specialist', 'hr-officer')
        and e.is_active and not e.is_deleted
        and e.id <> p_employee_id
        and (ur.effective_to is null or ur.effective_to > now())
      order by e.created_at
      limit 1;
    end if;

    -- 6) المدير العام أو التنفيذي
    if v_mgr is null then
      select e.id into v_mgr
      from public.employees e
      join public.user_roles ur on ur.user_id = e.user_id
      join public.roles r on r.id = ur.role_id
      where r.slug in ('general-manager', 'executive-director', 'executive')
        and e.is_active and not e.is_deleted
        and e.id <> p_employee_id
        and (ur.effective_to is null or ur.effective_to > now())
      order by e.created_at
      limit 1;
    end if;
  end if;

  -- ★ فحص تفويض الاعتماد: إذا كان المدير v_mgr لديه بديل ساري اليوم ولا يساوي مقدم الطلب نفسه ★
  if v_mgr is not null then
    v_delegate := public.get_active_approval_delegate(v_mgr, p_as_of);
    if v_delegate is not null and v_delegate <> p_employee_id then
      return v_delegate;
    end if;
  end if;

  return v_mgr;
end;
$$;

revoke all on function public.resolve_request_approver(uuid, date) from public, anon;
grant execute on function public.resolve_request_approver(uuid, date) to authenticated, service_role;

-- ─── 6) تحديث decide_request لتمكين مصطفى أحمد ويوسف رسمي من اعتماد الطلبات ───
create or replace function public.decide_request(
  p_request_id uuid,
  p_decision text,
  p_comment text default null
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me              uuid := public.current_employee_id();
  v_req             public.requests;
  v_step            public.request_steps;
  v_authorized      boolean := false;
  v_is_direct_mgr   boolean;
  v_is_operations   boolean;
  v_is_hr           boolean;
  v_is_exec         boolean;
  v_is_clinic_mgr   boolean;
  v_current_step    integer;
  v_final_status    text;
  v_actor_role      text;
  v_exec_emp        uuid;
  v_correction_id   uuid;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;
  if p_decision not in ('approve','reject','return') then
    raise exception 'invalid decision: %', p_decision using errcode = '22023';
  end if;
  if p_decision = 'return'
     and nullif(trim(coalesce(p_comment, '')), '') is null then
    raise exception 'return_requires_comment' using errcode = '22023';
  end if;

  select * into v_req from public.requests where id = p_request_id for update;
  if not found then
    raise exception 'request not found: %', p_request_id using errcode = 'P0002';
  end if;
  if v_req.status <> 'pending' then
    raise exception 'request is not pending (current: %)', v_req.status using errcode = '22023';
  end if;

  v_is_exec := public.current_has_active_role(array['executive','executive-director','general-manager']);
  v_is_hr   := public.current_has_active_role(array['hr-manager','hr-specialist','hr-officer']);

  -- حظر الاعتماد الذاتي للجميع باستثناء من يملك صلاحية إدارية عليا
  if v_req.employee_id = v_me
     and not (public.current_is_full_access() or v_is_hr or v_is_exec or public.current_has_active_role(array['admin','super-admin'])) then
    raise exception 'الاعتماد الذاتي غير مسموح' using errcode = '42501';
  end if;

  -- الخطوة الحالية: نفضّل الخطوة النشطة (active)، وإن لم توجد نأخذ أول escalated/pending
  select * into v_step
  from public.request_steps
  where request_id = p_request_id
    and status in ('active','escalated','pending')
  order by (status = 'active') desc, step_order
  limit 1
  for update;

  v_current_step  := coalesce(v_step.step_order, 0);

  -- التحقق من كون المعتمِد مدير العيادات (مصطفى أحمد أو يوسف رسمي أو دور clinics-manager)
  v_is_clinic_mgr := (
    v_me in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid)
    or public.current_has_active_role(array['clinics-manager'])
  );

  -- التحقق من صفة المدير المباشر:
  -- أ) المدير المباشر المسجل في الطلب.
  -- ب) إدارة العيادات المشتركة: مصطفى أحمد أو يوسف رسمي يحق لأي منهما اعتماد طلبات العيادات.
  -- ج) علاقة إشراف رئيسية في manager_relations.
  v_is_direct_mgr := (v_req.manager_employee_id = v_me)
    or (
      v_is_clinic_mgr and (
        public.is_clinic_team_member(v_req.employee_id)
        or v_req.manager_employee_id in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid)
        or exists (
          select 1 from public.workflow_definitions wd
          where wd.id = v_req.workflow_definition_id and wd.code like 'medical_%'
        )
      )
    )
    or exists (
      select 1 from public.manager_relations mr
      where mr.employee_id = v_req.employee_id
        and mr.manager_employee_id = v_me
        and mr.relation_type = 'primary'
        and (mr.effective_to is null or mr.effective_to >= current_date)
    );

  v_is_operations := public.current_has_active_role(array['operations-manager-1']);

  -- الصلاحية الشاملة لاعتماد الطلبات:
  v_authorized :=
    public.current_is_full_access()
    or v_is_exec
    or v_is_hr
    or v_is_direct_mgr
    or (v_step.id is not null and (
      v_step.assignee_employee_id = v_me
      or (v_is_clinic_mgr and v_step.assignee_employee_id in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid))
    ))
    or public.current_has_active_role(array['admin','super-admin'])
    or (v_is_operations
        and (
          v_current_step >= 2
          or (v_step.escalation_deadline is not null and v_step.escalation_deadline < now())
          or public.employee_on_leave(coalesce(v_step.assignee_employee_id, v_req.manager_employee_id), (now() at time zone 'Africa/Cairo')::date)
        )
    );

  if not v_authorized then
    raise exception 'غير مصرح لك باتخاذ قرار بشأن هذا الطلب' using errcode = '42501';
  end if;

  -- تحديد الدور الفعلي للمتخذ القرار
  if public.current_is_full_access() or public.current_has_active_role(array['admin','super-admin']) then
    v_actor_role := 'admin';
  elsif v_is_exec then
    v_actor_role := 'executive';
  elsif v_is_hr then
    v_actor_role := 'hr';
  elsif v_is_direct_mgr then
    v_actor_role := 'direct_manager';
  elsif v_is_operations then
    v_actor_role := 'operations';
  else
    v_actor_role := 'manager';
  end if;

  -- 1) إذا كان القرار هو الرفض أو الإرجاع: يُغلق الطلب مباشرة
  if p_decision in ('reject', 'return') then
    v_final_status := case when p_decision = 'reject' then 'rejected' else 'returned' end;

    update public.requests
    set status = v_final_status,
        workflow_status = case when p_decision = 'reject' then 'rejected' else 'returned' end,
        decided_at = now(),
        decided_by = v_me,
        updated_at = now()
    where id = p_request_id
    returning * into v_req;

    if v_step.id is not null then
      update public.request_steps
      set status = v_final_status,
          decided_at = now(),
          decided_by = v_me,
          action_notes = p_comment,
          updated_at = now()
      where id = v_step.id;
    end if;

    insert into public.request_actions (
      request_id, actor_employee_id, action, from_status, to_status, comment, created_by
    ) values (
      p_request_id, v_me, p_decision, 'pending', v_final_status, p_comment, auth.uid()
    );

    perform public.notify_employee(
      v_req.employee_id,
      case when p_decision = 'reject' then 'تم رفض طلبك' else 'تمت إعادة طلبك للمراجعة' end,
      coalesce(v_req.title, '') || case when p_comment is not null then ' — ' || p_comment else '' end,
      'request', 'normal', 'request', v_req.id,
      jsonb_build_object('status', v_final_status, 'decision', p_decision, 'requestId', v_req.id)
    );

    return v_req;
  end if;

  -- 2) إذا كان القرار هو الموافقة (approve):
  if v_step.id is not null then
    update public.request_steps
    set status = 'approved',
        decided_at = now(),
        decided_by = v_me,
        action_notes = p_comment,
        updated_at = now()
    where id = v_step.id;
  end if;

  insert into public.request_actions (
    request_id, actor_employee_id, action, from_status, to_status, comment, created_by
  ) values (
    p_request_id, v_me, 'approve', 'pending', 'approved', p_comment, auth.uid()
  );

  -- فحص ما إذا كانت هناك خطوات لاحقة تحتاج اعتماداً أعلى
  if exists (
    select 1 from public.request_steps
    where request_id = p_request_id
      and step_order > v_current_step
      and status = 'pending'
  ) and not (public.current_is_full_access() or v_is_exec) then
    -- تنشيط الخطوة التالية
    update public.request_steps
    set status = 'active',
        updated_at = now()
    where request_id = p_request_id
      and step_order = (
        select min(step_order) from public.request_steps
        where request_id = p_request_id and step_order > v_current_step and status = 'pending'
      );

    select * into v_req from public.requests where id = p_request_id;
    return v_req;
  end if;

  -- اعتماد نهائي للطلب:
  update public.requests
  set status = 'approved',
      workflow_status = 'approved',
      decided_at = now(),
      decided_by = v_me,
      updated_at = now()
  where id = p_request_id
  returning * into v_req;

  -- تطبيق الآثار التلقائية للطلب المعتمد:
  -- أ) تغيير الوردية (shift_change):
  if v_req.request_type = 'shift_change' and v_req.payload->>'shiftId' is not null then
    insert into public.shift_assignments (
      employee_id, shift_id, effective_from, is_active, notes, created_by
    ) values (
      v_req.employee_id,
      (v_req.payload->>'shiftId')::uuid,
      coalesce((v_req.payload->>'effectiveFrom')::date, (now() at time zone 'Africa/Cairo')::date),
      true,
      'معتمد بطلب تغيير وردية: ' || coalesce(v_req.title, ''),
      auth.uid()
    );
  end if;

  -- ب) تصحيح البصمة (attendance_correction):
  if v_req.request_type = 'attendance_correction' then
    v_correction_id := nullif(v_req.payload->>'correctionId', '')::uuid;
    if v_correction_id is not null then
      update public.attendance_corrections
      set status = 'approved',
          reviewed_by = auth.uid(),
          reviewed_at = now(),
          review_notes = coalesce(p_comment, 'معتمد تلقائياً مع الطلب')
      where id = v_correction_id;
    end if;
  end if;

  perform public.notify_employee(
    v_req.employee_id,
    'تمت الموافقة على طلبك بنجاح',
    coalesce(v_req.title, '') || case when p_comment is not null then ' — ' || p_comment else '' end,
    'request', 'normal', 'request', v_req.id,
    jsonb_build_object('status', 'approved', 'decision', 'approve', 'requestId', v_req.id)
  );

  return v_req;
end;
$$;

revoke all on function public.decide_request(uuid, text, text) from public, anon;
grant execute on function public.decide_request(uuid, text, text) to authenticated;

-- ─── 7) تحديث submit_request و _submit_request_for ──────────────────────────
create or replace function public._submit_request_for(
  p_employee_id uuid,
  p_request_type text,
  p_workflow_definition_id uuid default null::uuid,
  p_manager_employee_id uuid default null::uuid,
  p_title text default null::text,
  p_reason text default null::text,
  p_payload jsonb default '{}'::jsonb
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me             uuid := public.current_employee_id();
  v_def            public.workflow_definitions;
  v_due            timestamptz;
  v_esc            timestamptz;
  v_row            public.requests;
  v_first_approver uuid;
  v_label          text;
  v_is_clinic      boolean := false;
begin
  if p_employee_id is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  if p_request_type not in (
    'leave','mission','convoy','fundraising',
    'late_permit','early_permit','attendance_correction',
    'attendance_permit','shift_change','generic'
  ) then
    raise exception 'invalid request_type: %', p_request_type using errcode = '22023';
  end if;

  -- فحص طاقم العيادات (الموظفون غير المديرين)
  v_is_clinic := public.is_clinic_team_member(p_employee_id)
                 and p_employee_id not in (
                   '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid,
                   'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid
                 );

  -- تحديد المدير المعتمد
  if v_is_clinic then
    if p_manager_employee_id is null or p_manager_employee_id not in (
         '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid,
         'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid
       ) then
      p_manager_employee_id := coalesce(
        public.resolve_request_approver(p_employee_id),
        '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid
      );
    end if;
  elsif p_manager_employee_id is null or p_manager_employee_id = p_employee_id then
    p_manager_employee_id := public.resolve_request_approver(p_employee_id);
  end if;

  -- التعرف التلقائي لتعريف سير العمل
  if p_workflow_definition_id is not null then
    select * into v_def from public.workflow_definitions where id = p_workflow_definition_id;
  else
    if v_is_clinic then
      select * into v_def from public.workflow_definitions
        where code like 'medical_%' and request_type = p_request_type and is_active = true
        order by version desc limit 1;
    end if;

    if v_def.id is null and public.is_employee_isolated(p_employee_id) then
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
    if v_def.auto_escalate and not v_is_clinic then
      v_esc := v_due;
    end if;
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

  if v_def.id is not null then
    insert into public.request_steps (
      request_id, workflow_step_id, step_order, name_ar, step_type,
      assignee_employee_id, assignee_role_slug, status, sla_hours,
      due_at, escalation_deadline, created_by
    )
    select
      v_row.id, ws.id, ws.step_order, ws.name_ar, ws.step_type,
      case
        when ws.approver_type = 'specific_employee' then ws.approver_employee_id
        when ws.approver_type in ('direct_manager','department_manager') then p_manager_employee_id
        else null
      end,
      ws.approver_role_slug,
      case when ws.step_order = 1 then 'active' else 'pending' end,
      ws.sla_hours,
      case when ws.step_order = 1
           then now() + make_interval(hours => coalesce(ws.sla_hours, 48)) end,
      case when ws.step_order = 1 and ws.escalate_after_hours is not null and not v_is_clinic
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
  ) values (v_row.id, coalesce(v_me, p_employee_id), 'submit', 'pending', p_reason, auth.uid());

  v_label := format('%s — %s',
    public.request_type_label(v_row.request_type),
    coalesce(v_row.title, ''));

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
      'طلب جديد بانتظار مراجعتك',
      v_label,
      'request', 'high', 'request', v_row.id,
      jsonb_build_object(
        'requestType', v_row.request_type,
        'requestId', v_row.id,
        'employeeId', v_row.employee_id
      )
    );
  end if;

  return v_row;
end;
$$;

revoke execute on function public._submit_request_for(uuid, text, uuid, uuid, text, text, jsonb) from public, anon, authenticated;
grant execute on function public._submit_request_for(uuid, text, uuid, uuid, text, text, jsonb) to service_role;

-- ─── 8) تحديث request_live_location: تمكين الإدارة المشتركة ─────────────────
create or replace function public.request_live_location(
  p_employee_id uuid,
  p_mode text default 'snapshot',
  p_reason text default ''
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
  v_is_clinic_redirect boolean := false;
  v_is_clinic_direct_from_mgr boolean := false;
begin
  if v_me is null then
    raise exception 'requester has no employee profile' using errcode='42501';
  end if;

  -- الصلاحية: المدير التنفيذي، أو مصطفى أحمد / يوسف رسمي لطلب موقع أفراد طاقم العيادات
  if not (
    public.current_is_full_access()
    or public.current_has_active_role(array['executive', 'executive-director'])
    or (v_me in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid)
        and public.is_clinic_team_member(p_employee_id))
    or (public.current_has_active_role(array['clinics-manager']) and public.is_clinic_team_member(p_employee_id))
  ) then
    raise exception 'only executive director or clinics manager may request employee location' using errcode='42501';
  end if;

  if p_employee_id = v_me then
    raise exception 'cannot request own location' using errcode='22023';
  end if;

  -- استبعاد المدير التنفيذي كهدف
  if public.is_employee_executive(p_employee_id) then
    raise exception 'cannot request location of executive director' using errcode='22023';
  end if;

  -- ★ توجيه طلبات المواقع الخاصة بالعيادات:
  -- أ) إذا كان الطالب مصطفى أحمد أو يوسف رسمي أو يحمل دور clinics-manager: يصل للموظف مباشرة.
  -- ب) إذا كان الطالب هو المدير التنفيذي: يتحول لمدير العيادات للتحقق.
  if public.is_clinic_team_member(p_employee_id)
     and p_employee_id not in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid) then
    if v_me in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid)
       or public.current_has_active_role(array['clinics-manager']) then
      v_target_emp_id := p_employee_id;
      v_is_clinic_direct_from_mgr := true;
    else
      select full_name_ar into v_orig_emp_name from public.employees where id = p_employee_id;
      v_target_emp_id := '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid;
      v_is_clinic_redirect := true;
      p_reason := 'طلب موقع لموظفة العيادات (' || coalesce(v_orig_emp_name, 'موظفة') || ') — مرسل مباشرة لإدارة العيادات (مصطفى أحمد / يوسف رسمي) للمتابعة والتحقق' ||
                  case when nullif(trim(p_reason), '') is not null then ' | سبب إضافي: ' || trim(p_reason) else '' end;
    end if;
  end if;

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
      'isClinicDirectFromMgr', v_is_clinic_direct_from_mgr,
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
      case
        when v_is_clinic_redirect then 'طلب موقع عاجل (إدارة العيادات)'
        when v_is_clinic_direct_from_mgr then 'طلب موقع فوري من مدير العيادات'
        else 'طلب موقع عاجل'
      end,
      case
        when v_is_clinic_redirect
          then 'طلب موقع يخص موظفة بالعيادات (' || coalesce(v_orig_emp_name, '') || ') — محول لإدارة العيادات للمتابعة.'
        when v_is_clinic_direct_from_mgr
          then 'طلب موقع صادر من إدارة العيادات (مصطفى أحمد / يوسف رسمي) — يرجى الموافقة الفورية.'
        else 'طلب موقع عاجل لمتابعة مسار العمل. يرجى الضغط للموافقة.'
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

revoke execute on function public.request_live_location(uuid, text, text) from public, anon;
grant execute on function public.request_live_location(uuid, text, text) to authenticated;

-- ─── 9) تحديث get_employee_home: إظهار القرارات الإدارية للمديرين ────────────
create or replace function public.get_employee_home()
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_me uuid;
  v_is_clinic_staff boolean := false;
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

  -- الحجب يقتصر فقط على أفراد طاقم العيادات التابعين وليس المديرين
  v_is_clinic_staff := public.is_clinic_team_member(v_me)
                       and v_me not in (
                         '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid,
                         'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid
                       );

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
    -- حجب القرارات الإدارية يقتصر فقط على طاقم العيادات
    'unreadOfficial', case when v_is_clinic_staff then 0 else (
      select count(*) from public.decision_recipients dr
      join public.administrative_decisions d on d.id = dr.decision_id
      left join public.decision_reads rr on rr.decision_id = d.id
        and rr.employee_id = dr.employee_id
      where dr.employee_id = v_me
        and d.status = 'published'
        and rr.id is null
    ) end,
    'pendingLocationRequests', (
      select count(*) from public.live_location_requests
      where employee_id = v_me
        and status = 'pending'
        and expires_at > now()
    ),
    'lastUpdatedAt', now()
  );
end;
$function$;

revoke execute on function public.get_employee_home() from public, anon;
grant execute on function public.get_employee_home() to authenticated;

-- ─── 10) تحديث get_my_access_context: إتاحة مساحة العمل الإدارية لمصطفى ويوسف ──
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
  v_roles text[] := '{}';
  v_permissions text[] := '{}';
  v_workspaces text[] := '{}';
  v_default_workspace text := 'employee';
  v_is_full boolean := false;
  v_is_immune_admin boolean := false;
  v_is_executive boolean := false;
  v_is_operations boolean := false;
  v_is_manager boolean := false;
  v_is_hr boolean := false;
  v_is_main_admin boolean := false;
  v_is_committee boolean := false;
  v_is_clinic_staff boolean := false;
begin
  if v_user_id is null then
    raise exception 'غير مسجل الدخول' using errcode = '42501';
  end if;

  select e.id, e.full_name_ar, e.employee_code, e.photo_url
    into v_employee_id, v_display_name, v_employee_code, v_photo_url
  from public.employees e
  where e.user_id = v_user_id and e.is_active and not e.is_deleted
  limit 1;

  select coalesce(array_agg(r.slug order by r.slug), '{}'::text[]),
         bool_or(coalesce(r.is_full_access, false))
    into v_roles, v_is_full
  from public.user_roles ur
  join public.roles r on r.id = ur.role_id
  where ur.user_id = v_user_id and ur.effective_from <= now() and (ur.effective_to is null or ur.effective_to > now());

  v_is_immune_admin := exists (
    select 1 from public.employees e
    where e.user_id = v_user_id
      and e.is_active and not e.is_deleted
      and e.id in ('d0000000-0000-4000-8000-000000000001'::uuid, 'd0000000-0000-4000-8000-000000000002'::uuid)
  );

  if v_is_full or v_is_immune_admin then
    select coalesce(array_agg(p.code order by p.code), '{}'::text[])
      into v_permissions
    from public.permissions p;
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
  v_is_manager := v_is_operations
                  or v_roles && array['direct-manager','department-manager','branch-manager','clinics-manager']::text[]
                  or (v_employee_id is not null and v_employee_id in (
                        '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid,
                        'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid
                      ));

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

  -- طاقم العيادات يقتصر على الموظفين فقط دون المديرين مصطفى أحمد ويوسف رسمي
  if v_employee_id is not null then
    v_is_clinic_staff := public.is_clinic_team_member(v_employee_id)
                         and v_employee_id not in (
                           '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid,
                           'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid
                         );
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
      'liveLocationResponseEnabled', not v_is_executive and not public.is_employee_attendance_exempt(v_employee_id) and v_employee_id is not null
    )
  );
end;
$function$;

revoke execute on function public.get_my_access_context() from public, anon;
grant execute on function public.get_my_access_context() to authenticated;

-- ─── 11) تحديث can_view_isolated_employee لدعم يوسف رسمي ومصطفى أحمد ─────────
create or replace function public.can_view_isolated_employee(p_target uuid)
returns boolean
language plpgsql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_me uuid := public.current_employee_id();
begin
  if not public.is_employee_isolated(p_target) then return true; end if;
  if public.current_can_view_all_employees() then return true; end if;
  if v_me is null then return false; end if;

  -- مصطفى أحمد ويوسف رسمي مديران للعيادات ويمكنهما رؤية جميع أفراد طاقم العيادات
  if v_me in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid) then
    return true;
  end if;

  -- زميل القسم (عزل إداري فقط)
  if exists (
    select 1
      from public.employees t
      join public.departments d on d.id = t.department_id
     where t.id = p_target
       and d.is_isolated
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
end $function$;

revoke execute on function public.can_view_isolated_employee(uuid) from public, anon;
grant execute on function public.can_view_isolated_employee(uuid) to authenticated, service_role;

-- ─── 12) تحديث خطوات سير عمل العيادات لتظهر إدارة العيادات المشتركة ──────────
update public.workflow_steps
set name_ar = 'إدارة العيادات الطبية (مصطفى أحمد / يوسف رسمي)'
where definition_id in (
  select id from public.workflow_definitions where code like 'medical_%'
);

notify pgrst, 'reload schema';

commit;
