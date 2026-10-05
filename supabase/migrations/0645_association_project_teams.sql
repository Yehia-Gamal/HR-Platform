-- ═══════════════════════════════════════════════════════════════
-- 0645: مشاريع الجمعية — فريق المشروع (قائد + أعضاء) وإدارات متعددة
--
-- قبلها: كل مشروع مربوط بإدارة واحدة إجبارية + «مالك» واحد.
-- المطلوب: المسؤولون عن المشروع مجموعة أشخاص، واحد منهم فقط هو القائد،
-- والإدارة ليست إجبارية — يكفي أشخاص، أو إدارة واحدة، أو عدة إدارات.
--
-- الجديد:
--   • association_project_members: (مشروع، موظف، is_leader) — قائد واحد فقط
--     لكل مشروع (فهرس فريد جزئي). owner_employee_id يبقى = القائد دائماً
--     (توافق مع النسخ القديمة من التطبيق والتقارير).
--   • association_project_departments: إدارات المشروع (0..n).
--     association_projects.department_id أصبح اختيارياً = أول إدارة مرتبطة.
--   • نطاق المشروع (من يراه ويدير خطواته وتحديثاته):
--       القائد + الأعضاء + موظفو ومديرو الإدارات المرتبطة + full-access.
--   • تعديل بيانات المشروع وفريقه: القائد، منشئ المشروع، مدير إدارة مرتبطة،
--     وfull-access. بعد الإرسال للاعتماد يُقفل الاسم والوصف لغير full-access.
--   • المكلَّف بخطوة يجب أن يكون ضمن نطاق المشروع، ويُشعَر عند تكليفه.
--   • من يُضاف للفريق يُشعَر (والقائد بصفته قائداً).
--   • save_association_project: إنشاء/تعديل كامل بالفريق والإدارات.
--   • get_association_project_pickers: قائمة الموظفين والإدارات لاختيار الفريق
--     (متاحة لكل موظف لأن المشاريع قد تجمع أكثر من إدارة).
--
-- الدوال القديمة (create/update_association_project_admin) تبقى تعمل
-- للنسخ القديمة من تطبيق الموبايل، وتكتب الفريق والإدارات الجديدة.
-- كل الدوال المستبدلة: استبدال كنوني كامل بنفس التواقيع.
-- ═══════════════════════════════════════════════════════════════

begin;

-- ═══════════════════════════════════════════════
-- 1. الجداول الجديدة + ترحيل البيانات القائمة
-- ═══════════════════════════════════════════════

create table if not exists public.association_project_members (
  project_id  uuid not null references public.association_projects(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  is_leader   boolean not null default false,
  added_at    timestamptz not null default now(),
  added_by    uuid references auth.users(id),
  primary key (project_id, employee_id)
);

create unique index if not exists ux_association_project_members_leader
  on public.association_project_members (project_id) where is_leader;
create index if not exists ix_association_project_members_employee
  on public.association_project_members (employee_id);

create table if not exists public.association_project_departments (
  project_id    uuid not null references public.association_projects(id) on delete cascade,
  department_id uuid not null references public.departments(id) on delete cascade,
  primary key (project_id, department_id)
);

create index if not exists ix_association_project_departments_department
  on public.association_project_departments (department_id);

comment on table public.association_project_members is
  '0645: فريق المشروع — قائد واحد (is_leader) + أعضاء. owner_employee_id = القائد.';
comment on table public.association_project_departments is
  '0645: الإدارات المسؤولة عن المشروع (اختيارية، قد تكون أكثر من إدارة).';

-- الوصول عبر الدوال فقط.
alter table public.association_project_members     enable row level security;
alter table public.association_project_departments enable row level security;
revoke all on public.association_project_members     from public, anon, authenticated;
revoke all on public.association_project_departments from public, anon, authenticated;
grant all on public.association_project_members     to service_role;
grant all on public.association_project_departments to service_role;

-- كل مشروع قائم: مالكه قائده، وإدارته إدارته.
insert into public.association_project_members (project_id, employee_id, is_leader, added_at)
select p.id, p.owner_employee_id, true, p.created_at
from public.association_projects p
where p.owner_employee_id is not null
on conflict (project_id, employee_id) do update set is_leader = true;

insert into public.association_project_departments (project_id, department_id)
select p.id, p.department_id
from public.association_projects p
where p.department_id is not null
on conflict do nothing;

alter table public.association_projects alter column department_id drop not null;

comment on column public.association_projects.department_id is
  '0645: أول إدارة مرتبطة (للتوافق) — المصدر الكامل association_project_departments.';
comment on column public.association_projects.owner_employee_id is
  '0645: قائد المشروع — متزامن دائماً مع association_project_members.is_leader.';

-- ═══════════════════════════════════════════════
-- 2. دوال النطاق والصلاحية (داخلية)
-- ═══════════════════════════════════════════════

-- صفة موظف في مشروع: leader / member / dept_manager / dept_staff / creator / null
create or replace function public._association_project_role_of(
  p_project_id  uuid,
  p_employee_id uuid
)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case
    when p_employee_id is null then null
    when exists (select 1 from public.association_project_members m
                  where m.project_id = p_project_id and m.employee_id = p_employee_id and m.is_leader)
      then 'leader'
    when exists (select 1 from public.association_project_members m
                  where m.project_id = p_project_id and m.employee_id = p_employee_id)
      then 'member'
    when exists (select 1 from public.association_project_departments pd
                   join public.departments d on d.id = pd.department_id
                  where pd.project_id = p_project_id and d.manager_id = p_employee_id)
      then 'dept_manager'
    when exists (select 1 from public.association_project_departments pd
                   join public.employees e on e.department_id = pd.department_id
                  where pd.project_id = p_project_id and e.id = p_employee_id and e.is_active)
      then 'dept_staff'
    -- منشئ المشروع يبقى يراه حتى لو أخرجه القائد من الفريق.
    when exists (select 1 from public.association_projects p
                   join public.employees e on e.user_id = p.created_by
                  where p.id = p_project_id and e.id = p_employee_id)
      then 'creator'
  end;
$$;

-- صفة المستخدم الحالي
create or replace function public._association_project_role(p_project_id uuid)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public._association_project_role_of(p_project_id, public.current_employee_id());
$$;

-- يرى المشروع ويدير خطواته وتحديثاته: full-access أو أي صفة في المشروع
create or replace function public._association_project_can_manage(p_project_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.current_is_full_access()
      or (exists (select 1 from public.association_projects where id = p_project_id)
          and public._association_project_role(p_project_id) is not null);
$$;

-- يعدّل بيانات المشروع وفريقه: full-access، القائد، مدير إدارة مرتبطة، المنشئ
create or replace function public._association_project_can_edit(p_project_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.current_is_full_access()
      or public._association_project_role(p_project_id) in ('leader', 'dept_manager')
      or exists (select 1 from public.association_projects p
                  where p.id = p_project_id and p.created_by = auth.uid());
$$;

-- ═══════════════════════════════════════════════
-- 3. الإشعارات
-- ═══════════════════════════════════════════════

-- 'admins' = full-access ، 'department' / 'team' = القائد + الأعضاء + مديرو الإدارات المرتبطة
create or replace function public._association_project_notify(
  p_project_id uuid,
  p_audience   text,
  p_title      text,
  p_body       text,
  p_kind       text,
  p_priority   text default 'normal'
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_owner uuid;
begin
  select owner_employee_id into v_owner
  from public.association_projects where id = p_project_id;
  if not found then return; end if;

  insert into public.notifications (
    recipient_user_id, recipient_employee_id, title, body,
    category, priority, entity_type, entity_id, metadata, created_by
  )
  select distinct on (r.user_id)
         r.user_id, r.employee_id, p_title, p_body,
         'workflow', p_priority, 'association_project', p_project_id,
         jsonb_build_object('kind', p_kind, 'projectId', p_project_id),
         auth.uid()
  from (
    select pr.id as user_id, e.id as employee_id
    from public.user_roles ur
    join public.roles r     on r.id = ur.role_id and r.is_full_access
    join public.profiles pr on pr.id = ur.user_id and pr.status = 'active'
    join public.employees e on e.id = pr.employee_id and e.is_active
    where p_audience = 'admins'
      and (ur.effective_to is null or ur.effective_to > now())
    union all
    select e.user_id, e.id
    from public.employees e
    where p_audience in ('department', 'team')
      and e.is_active and e.user_id is not null
      and (e.id = v_owner
           or exists (select 1 from public.association_project_members m
                       where m.project_id = p_project_id and m.employee_id = e.id)
           or exists (select 1 from public.association_project_departments pd
                        join public.departments d on d.id = pd.department_id
                       where pd.project_id = p_project_id and d.manager_id = e.id))
  ) r
  -- لا نُشعر الفاعل نفسه بما فعله.
  where r.user_id is distinct from auth.uid();
end;
$$;

-- إشعار موظف بعينه (إضافة للفريق، تكليف بخطوة)
create or replace function public._association_project_notify_employee(
  p_project_id  uuid,
  p_employee_id uuid,
  p_title       text,
  p_body        text,
  p_kind        text,
  p_priority    text default 'normal'
)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  insert into public.notifications (
    recipient_user_id, recipient_employee_id, title, body,
    category, priority, entity_type, entity_id, metadata, created_by
  )
  select e.user_id, e.id, p_title, p_body,
         'workflow', p_priority, 'association_project', p_project_id,
         jsonb_build_object('kind', p_kind, 'projectId', p_project_id),
         auth.uid()
  from public.employees e
  where e.id = p_employee_id
    and e.is_active and e.user_id is not null
    and e.user_id is distinct from auth.uid();
$$;

-- ═══════════════════════════════════════════════
-- 4. مزامنة الفريق والإدارات (داخلية — تُستدعى بعد فحص الصلاحية)
-- ═══════════════════════════════════════════════

create or replace function public._association_project_set_team(
  p_project_id  uuid,
  p_leader_id   uuid,
  p_member_ids  uuid[],
  p_department_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_name       text;
  v_team       uuid[] := array(select distinct x from unnest(coalesce(p_member_ids, '{}') || p_leader_id) x where x is not null);
  v_depts      uuid[] := array(select distinct x from unnest(coalesce(p_department_ids, '{}')) x where x is not null);
  v_old        uuid[];
  v_old_leader uuid;
  r            record;
begin
  select name into v_name from public.association_projects where id = p_project_id;
  select coalesce(array_agg(employee_id), '{}') into v_old
    from public.association_project_members where project_id = p_project_id;
  select employee_id into v_old_leader
    from public.association_project_members where project_id = p_project_id and is_leader;

  delete from public.association_project_members
   where project_id = p_project_id and not (employee_id = any(v_team));

  -- إنزال القائد القديم أولاً حتى لا يتعارض الفهرس الفريد للقائد.
  update public.association_project_members set is_leader = false
   where project_id = p_project_id and is_leader and employee_id <> p_leader_id;

  insert into public.association_project_members (project_id, employee_id, is_leader, added_by)
  select p_project_id, x, x = p_leader_id, auth.uid() from unnest(v_team) x
  on conflict (project_id, employee_id) do update set is_leader = excluded.is_leader;

  delete from public.association_project_departments
   where project_id = p_project_id and not (department_id = any(v_depts));
  insert into public.association_project_departments (project_id, department_id)
  select p_project_id, x from unnest(v_depts) x
  on conflict do nothing;

  update public.association_projects set
    owner_employee_id = p_leader_id,
    department_id     = (select d.id from public.departments d
                          where d.id = any(v_depts) order by d.name, d.id limit 1)
  where id = p_project_id;

  -- من خرج من نطاق المشروع تُفك مهامه غير المنجزة.
  update public.association_project_steps s set assignee_employee_id = null
   where s.project_id = p_project_id and s.status <> 'done'
     and s.assignee_employee_id is not null
     and public._association_project_role_of(p_project_id, s.assignee_employee_id) is null;

  -- إشعار من أُضيف للفريق أو أصبح قائداً.
  for r in
    select x as emp, x = p_leader_id as is_leader
    from unnest(v_team) x
    where not (x = any(v_old))
       or (x = p_leader_id and v_old_leader is distinct from p_leader_id)
  loop
    perform public._association_project_notify_employee(
      p_project_id, r.emp,
      case when r.is_leader then 'أصبحت قائد مشروع' else 'أُضفت إلى فريق مشروع' end,
      case when r.is_leader
           then 'أنت الآن قائد مشروع «' || v_name || '». تابع خطواته وفريقه من شاشة مشاريع الجمعية.'
           else 'أُضفت إلى فريق مشروع «' || v_name || '». تابع خطواته ومهامك من شاشة مشاريع الجمعية.' end,
      'project_team_added');
  end loop;
end;
$$;

-- ═══════════════════════════════════════════════
-- 5. كائن JSON موحّد للمشروع — استبدال كنوني (إدارة اختيارية + الفريق)
-- ═══════════════════════════════════════════════

create or replace function public._association_project_json(
  p_project_id    uuid,
  p_warning_days  integer,
  p_critical_days integer
)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'id',                p.id,
    'code',              p.code,
    'name',              p.name,
    'description',       p.description,
    'departmentId',      p.department_id,
    -- أسماء كل الإدارات المرتبطة (أو null لمشروع أفراد فقط)
    'departmentName',    (select string_agg(d.name, '، ' order by d.name)
                            from public.association_project_departments pd
                            join public.departments d on d.id = pd.department_id
                           where pd.project_id = p.id),
    'departments',       coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'name', d.name) order by d.name)
                                     from public.association_project_departments pd
                                     join public.departments d on d.id = pd.department_id
                                    where pd.project_id = p.id), '[]'::jsonb),
    'ownerId',           p.owner_employee_id,
    'ownerName',         e.full_name_ar,
    'leaderId',          p.owner_employee_id,
    'leaderName',        e.full_name_ar,
    'members',           coalesce((select jsonb_agg(jsonb_build_object(
                                       'employeeId',     m.employee_id,
                                       'name',           me.full_name_ar,
                                       'jobTitle',       jt.name,
                                       'departmentName', md.name,
                                       'isLeader',       m.is_leader)
                                     order by m.is_leader desc, me.full_name_ar)
                                     from public.association_project_members m
                                     join public.employees me on me.id = m.employee_id
                                     left join public.job_titles jt on jt.id = me.job_title_id
                                     left join public.departments md on md.id = me.department_id
                                    where m.project_id = p.id), '[]'::jsonb),
    'createdBy',         p.created_by,
    'status',            p.status,
    'approvalStatus',    p.approval_status,
    'priority',          p.priority,
    'progress',          p.progress,
    'startDate',         p.start_date,
    'targetEndDate',     p.target_end_date,
    'lastUpdateAt',      p.last_update_at,
    'lastUpdateNote',    p.last_update_note,
    'lastActivityAt',    p.last_activity_at,
    'daysSinceActivity', case when p.last_activity_at is null then null
                              else floor(extract(epoch from now() - p.last_activity_at) / 86400)::int end,
    'approvedBy',        p.approved_by,
    'approvedAt',        p.approved_at,
    'rejectionReason',   p.rejection_reason,
    'createdAt',         p.created_at,
    'totalSteps',        st.total,
    'completedSteps',    st.done,
    'inProgressSteps',   st.in_progress,
    'remainingSteps',    st.total - st.done,
    'blockedSteps',      st.blocked,
    'overdueSteps',      st.overdue,
    'currentStepTitle',  (select s.title from public.association_project_steps s
                           where s.project_id = p.id and s.status <> 'done'
                           order by s.sort_order, s.created_at limit 1),
    'isOverdue',         p.target_end_date is not null
                         and p.status not in ('completed','cancelled')
                         and p.target_end_date < (now() at time zone 'Africa/Cairo')::date,
    'myRole',            coalesce(public._association_project_role(p.id),
                                  case when public.current_is_full_access() then 'admin' end),
    'canManage',         public._association_project_can_manage(p.id),
    'canEdit',           public._association_project_can_edit(p.id),
    'ledStatus',         public._association_project_led(
                           p.status, p.approval_status, p.last_activity_at,
                           p_warning_days, p_critical_days)
  )
  from public.association_projects p
  left join public.employees e on e.id = p.owner_employee_id
  cross join lateral (
    select count(*)::int                                          as total,
           count(*) filter (where s.status = 'done')::int         as done,
           count(*) filter (where s.status = 'in_progress')::int  as in_progress,
           count(*) filter (where s.status = 'blocked')::int      as blocked,
           count(*) filter (where s.status <> 'done' and s.due_date is not null
                              and s.due_date < (now() at time zone 'Africa/Cairo')::date)::int as overdue
    from public.association_project_steps s
    where s.project_id = p.id
  ) st
  where p.id = p_project_id;
$$;

-- ═══════════════════════════════════════════════
-- 6. get_association_projects — استبدال كنوني (نطاق الفريق والإدارات)
-- ═══════════════════════════════════════════════

create or replace function public.get_association_projects()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_emp      uuid;
  v_full     boolean;
  v_dept     uuid;
  v_warning  int;
  v_critical int;
begin
  v_emp  := public.current_employee_id();
  v_full := public.current_is_full_access();

  if not v_full and v_emp is null then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  select warning_days, critical_days into v_warning, v_critical
  from public.association_project_settings where id;
  v_warning  := coalesce(v_warning, 7);
  v_critical := coalesce(v_critical, 14);

  select department_id into v_dept from public.employees where id = v_emp;

  return jsonb_build_object(
    'projects', coalesce((
      select jsonb_agg(
        public._association_project_json(p.id, v_warning, v_critical)
        order by
          case p.approval_status when 'pending_approval' then 0 when 'draft' then 1 else 2 end,
          case p.priority when 'critical' then 1 when 'high' then 2 when 'medium' then 3 else 4 end,
          coalesce(p.updated_at, p.created_at) desc)
      from public.association_projects p
      where v_full or public._association_project_role_of(p.id, v_emp) is not null
    ), '[]'::jsonb),
    -- آخر 30 تحديثاً فعلياً عبر المشاريع المرئية (تبويب «آخر النشاطات»)
    'recentUpdates', coalesce((
      select jsonb_agg(x.obj order by x.created_at desc)
      from (
        select u.created_at,
               jsonb_build_object(
                 'id',           u.id,
                 'projectId',    p.id,
                 'projectName',  p.name,
                 'projectCode',  p.code,
                 'note',         u.note,
                 'progress',     u.progress,
                 'statusChange', u.status_change,
                 'authorName',   ue.full_name_ar,
                 'createdAt',    u.created_at) as obj
        from public.association_project_updates u
        join public.association_projects p on p.id = u.project_id
        join public.employees ue on ue.id = u.author_employee_id
        where v_full or public._association_project_role_of(p.id, v_emp) is not null
        order by u.created_at desc
        limit 30
      ) x
    ), '[]'::jsonb),
    'lastUpdatedAt',  now(),
    'isFullAccess',   v_full,
    -- أي موظف يستطيع اقتراح مشروع (يعتمده المدير التنفيذي).
    'canCreate',      v_full or v_emp is not null,
    'myDepartmentId', v_dept,
    'myEmployeeId',   v_emp,
    'settings',       jsonb_build_object('warningDays', v_warning, 'criticalDays', v_critical)
  );
end;
$$;

-- ═══════════════════════════════════════════════
-- 7. get_association_project_detail — استبدال كنوني
-- ═══════════════════════════════════════════════

create or replace function public.get_association_project_detail(p_project_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_full     boolean := public.current_is_full_access();
  v_approval text;
  v_edit     boolean;
  v_warning  int;
  v_critical int;
begin
  select approval_status into v_approval
  from public.association_projects where id = p_project_id;
  if not found then
    -- لا نفرّق بين «غير موجود» و«ليس لك» لغير full-access حتى لا نكشف الوجود.
    if v_full then
      raise exception 'PROJECT_NOT_FOUND' using errcode = 'P0002';
    end if;
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if not public._association_project_can_manage(p_project_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  v_edit := public._association_project_can_edit(p_project_id);

  select warning_days, critical_days into v_warning, v_critical
  from public.association_project_settings where id;

  return jsonb_build_object(
    'project', public._association_project_json(p_project_id, coalesce(v_warning, 7), coalesce(v_critical, 14)),
    'steps', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',           s.id,
        'title',        s.title,
        'description',  s.description,
        'sortOrder',    s.sort_order,
        'status',       s.status,
        'dueDate',      s.due_date,
        'assigneeId',   s.assignee_employee_id,
        'assigneeName', ae.full_name_ar,
        'completedAt',  s.completed_at,
        'updatedAt',    coalesce(s.updated_at, s.created_at)
      ) order by s.sort_order, s.created_at)
      from public.association_project_steps s
      left join public.employees ae on ae.id = s.assignee_employee_id
      where s.project_id = p_project_id
    ), '[]'::jsonb),
    'updates', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',           u.id,
        'note',         u.note,
        'progress',     u.progress,
        'statusChange', u.status_change,
        'authorName',   ue.full_name_ar,
        'createdAt',    u.created_at
      ) order by u.created_at desc)
      from public.association_project_updates u
      join public.employees ue on ue.id = u.author_employee_id
      where u.project_id = p_project_id
    ), '[]'::jsonb),
    'permissions', jsonb_build_object(
      'canManage',   true,
      'canApprove',  v_full and v_approval = 'pending_approval',
      -- تعديل البيانات كاملة (الاسم والوصف مقفلان بعد الإرسال لغير full-access)
      'canEdit',     v_edit,
      'canEditCore', v_full or (v_edit and v_approval in ('draft','rejected')),
      'canEditTeam', v_edit,
      'canSubmit',   v_approval in ('draft','rejected'),
      'canUpdate',   v_approval = 'approved',
      'canDelete',   v_full or (v_edit and v_approval in ('draft','rejected'))
    )
  );
end;
$$;

-- ═══════════════════════════════════════════════
-- 8. save_association_project — إنشاء/تعديل كامل بالفريق والإدارات
--    p_project_id = null → إنشاء. full-access يُعتمد مباشرة، غيره مسودة.
-- ═══════════════════════════════════════════════

create or replace function public.save_association_project(
  p_project_id      uuid,
  p_name            text,
  p_description     text,
  p_priority        text,
  p_start_date      date,
  p_target_end_date date,
  p_leader_id       uuid,
  p_member_ids      uuid[] default '{}',
  p_department_ids  uuid[] default '{}',
  p_code            text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_emp     uuid := public.current_employee_id();
  v_full    boolean := public.current_is_full_access();
  v_row     public.association_projects%rowtype;
  v_id      uuid;
  v_leader  uuid;
  v_members uuid[];
  v_depts   uuid[];
  v_code    text := nullif(btrim(coalesce(p_code, '')), '');
  v_name    text := nullif(btrim(coalesce(p_name, '')), '');
  v_desc    text := nullif(btrim(coalesce(p_description, '')), '');
  v_n       int;
begin
  if not v_full and v_emp is null then
    raise exception 'EMPLOYEE_CONTEXT_REQUIRED' using errcode = '42501';
  end if;
  if v_name is null then
    raise exception 'اسم المشروع مطلوب' using errcode = '22023';
  end if;
  if coalesce(p_priority, 'medium') not in ('low','medium','high','critical') then
    raise exception 'أولوية غير صحيحة' using errcode = '22023';
  end if;
  if p_start_date is not null and p_target_end_date is not null and p_target_end_date < p_start_date then
    raise exception 'الموعد النهائي قبل تاريخ البدء' using errcode = '22023';
  end if;

  v_leader := coalesce(p_leader_id, case when p_project_id is null then v_emp end);
  if v_leader is null then
    raise exception 'اختر قائد المشروع' using errcode = '22023';
  end if;
  if not exists (select 1 from public.employees where id = v_leader and is_active and not coalesce(is_deleted, false)) then
    raise exception 'قائد المشروع غير موجود أو غير نشط' using errcode = '22023';
  end if;

  v_members := array(select distinct x from unnest(coalesce(p_member_ids, '{}')) x
                      where x is not null and x <> v_leader);
  v_depts   := array(select distinct x from unnest(coalesce(p_department_ids, '{}')) x where x is not null);

  if cardinality(v_members) > 60 then
    raise exception 'الحد الأقصى لفريق المشروع 60 عضواً' using errcode = '22023';
  end if;
  if cardinality(v_depts) > 30 then
    raise exception 'الحد الأقصى 30 إدارة للمشروع' using errcode = '22023';
  end if;
  if exists (select 1 from unnest(v_members) x
              where not exists (select 1 from public.employees e
                                 where e.id = x and e.is_active and not coalesce(e.is_deleted, false))) then
    raise exception 'أحد أعضاء الفريق غير موجود أو غير نشط' using errcode = '22023';
  end if;
  if exists (select 1 from unnest(v_depts) x
              where not exists (select 1 from public.departments d where d.id = x)) then
    raise exception 'إحدى الإدارات غير صحيحة' using errcode = '22023';
  end if;

  if p_project_id is null then
    -- المنشئ (غير المدير التنفيذي) ينضم للفريق تلقائياً ليتابع ما أنشأه.
    if not v_full and v_emp <> v_leader and not (v_emp = any(v_members)) then
      v_members := v_members || v_emp;
    end if;

    -- كود تلقائي عند تركه فارغاً: PRJ-YYYY-NNN
    if v_code is null then
      select count(*) + 1 into v_n from public.association_projects;
      loop
        v_code := 'PRJ-' || to_char(now() at time zone 'Africa/Cairo', 'YYYY') || '-' || lpad(v_n::text, 3, '0');
        exit when not exists (select 1 from public.association_projects where code = v_code);
        v_n := v_n + 1;
      end loop;
    elsif exists (select 1 from public.association_projects where code = v_code) then
      raise exception 'كود المشروع مستخدم من قبل' using errcode = '23505';
    end if;

    insert into public.association_projects (
      code, name, description, department_id, owner_employee_id,
      status, approval_status, approved_by, approved_at, last_activity_at,
      priority, start_date, target_end_date, created_by
    ) values (
      v_code, v_name, v_desc, null, v_leader,
      'planned',
      case when v_full then 'approved' else 'draft' end,
      case when v_full then auth.uid() end,
      case when v_full then now() end,
      case when v_full then now() end,
      coalesce(p_priority, 'medium'), p_start_date, p_target_end_date, auth.uid()
    ) returning id into v_id;
  else
    select * into v_row from public.association_projects where id = p_project_id for update;
    if not found or not public._association_project_can_edit(p_project_id) then
      raise exception 'FORBIDDEN' using errcode = '42501';
    end if;

    -- بعد الإرسال للاعتماد: الاسم والوصف هما ما اعتُمد — لا يغيّرهما إلا المدير التنفيذي.
    if not v_full and v_row.approval_status not in ('draft','rejected')
       and (v_name <> v_row.name or v_desc is distinct from v_row.description) then
      raise exception 'لا يمكن تغيير اسم المشروع أو وصفه بعد إرساله للاعتماد' using errcode = '42501';
    end if;

    update public.association_projects set
      name            = v_name,
      description     = v_desc,
      priority        = coalesce(p_priority, priority),
      start_date      = p_start_date,
      target_end_date = p_target_end_date
    where id = p_project_id;
    v_id := p_project_id;
  end if;

  perform public._association_project_set_team(v_id, v_leader, v_members, v_depts);
  return v_id;
end;
$$;

-- ═══════════════════════════════════════════════
-- 9. create_association_project_admin — للنسخ القديمة (إدارة واحدة)
-- ═══════════════════════════════════════════════

create or replace function public.create_association_project_admin(
  p_code              text,
  p_name              text,
  p_description       text,
  p_department_id     uuid,
  p_owner_employee_id uuid,
  p_priority          text default 'medium',
  p_start_date        date default null,
  p_target_end_date   date default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_emp  uuid := public.current_employee_id();
  v_full boolean := public.current_is_full_access();
begin
  if not v_full and v_emp is null then
    raise exception 'EMPLOYEE_CONTEXT_REQUIRED' using errcode = '42501';
  end if;
  if p_department_id is null or not exists (select 1 from public.departments where id = p_department_id) then
    raise exception 'الإدارة غير صحيحة' using errcode = '22023';
  end if;
  if not v_full then
    if p_owner_employee_id is not null and p_owner_employee_id <> v_emp then
      raise exception 'FORBIDDEN' using errcode = '42501';
    end if;
    if not public._association_project_is_member(p_department_id, null) then
      raise exception 'لا يمكنك إنشاء مشروع إلا لإدارتك' using errcode = '42501';
    end if;
  end if;

  return public.save_association_project(
    null, p_name, p_description, coalesce(p_priority, 'medium'), p_start_date, p_target_end_date,
    case when v_full then coalesce(p_owner_employee_id, v_emp) else v_emp end,
    '{}'::uuid[], array[p_department_id], p_code);
end;
$$;

-- ═══════════════════════════════════════════════
-- 10. update_association_project_admin — للنسخ القديمة (تحديث جزئي)
-- ═══════════════════════════════════════════════

create or replace function public.update_association_project_admin(
  p_project_id        uuid,
  p_name              text default null,
  p_description       text default null,
  p_department_id     uuid default null,
  p_owner_employee_id uuid default null,
  p_status            text default null,
  p_priority          text default null,
  p_progress          numeric default null,
  p_start_date        date default null,
  p_target_end_date   date default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_full    boolean := public.current_is_full_access();
  v_row     public.association_projects%rowtype;
  v_steps   int;
  v_members uuid[];
  v_depts   uuid[];
begin
  select * into v_row from public.association_projects where id = p_project_id for update;
  if not found or not public._association_project_can_edit(p_project_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if not v_full then
    if v_row.approval_status not in ('draft','rejected') then
      raise exception 'لا يمكن تعديل بيانات مشروع بعد إرساله للاعتماد' using errcode = '42501';
    end if;
    if p_department_id is not null or p_owner_employee_id is not null
       or (p_status is not null and p_status <> v_row.status) then
      raise exception 'FORBIDDEN' using errcode = '42501';
    end if;
  end if;

  if p_status is not null and p_status not in ('planned','active','on_hold','completed','cancelled') then
    raise exception 'حالة غير صحيحة' using errcode = '22023';
  end if;
  if p_priority is not null and p_priority not in ('low','medium','high','critical') then
    raise exception 'أولوية غير صحيحة' using errcode = '22023';
  end if;
  if coalesce(p_target_end_date, v_row.target_end_date) < coalesce(p_start_date, v_row.start_date) then
    raise exception 'الموعد النهائي قبل تاريخ البدء' using errcode = '22023';
  end if;
  if p_owner_employee_id is not null
     and not exists (select 1 from public.employees where id = p_owner_employee_id and is_active) then
    raise exception 'قائد المشروع غير موجود أو غير نشط' using errcode = '22023';
  end if;
  if p_department_id is not null and not exists (select 1 from public.departments where id = p_department_id) then
    raise exception 'الإدارة غير صحيحة' using errcode = '22023';
  end if;

  select count(*) into v_steps from public.association_project_steps where project_id = p_project_id;

  update public.association_projects set
    name              = coalesce(nullif(btrim(p_name), ''), name),
    description       = coalesce(p_description, description),
    status            = coalesce(p_status, status),
    priority          = coalesce(p_priority, priority),
    -- عند وجود خطوات تُشتق النسبة منها (trigger) ولا تُكتب يدوياً.
    progress          = case when v_steps > 0 then progress
                             when p_status = 'completed' then 100
                             else coalesce(p_progress, progress) end,
    start_date        = coalesce(p_start_date, start_date),
    target_end_date   = coalesce(p_target_end_date, target_end_date),
    last_activity_at  = case when p_status is not null and p_status <> status then now() else last_activity_at end,
    critical_notified_at = case when p_status is not null and p_status <> status then null else critical_notified_at end
  where id = p_project_id;

  -- تغيير الإدارة أو المالك (full-access) يُترجم للفريق والإدارات الجديدة.
  if p_department_id is not null or p_owner_employee_id is not null then
    select coalesce(array_agg(employee_id) filter (where not is_leader), '{}') into v_members
      from public.association_project_members where project_id = p_project_id;
    if p_department_id is not null then
      v_depts := array[p_department_id];
    else
      select coalesce(array_agg(department_id), '{}') into v_depts
        from public.association_project_departments where project_id = p_project_id;
    end if;
    perform public._association_project_set_team(
      p_project_id, coalesce(p_owner_employee_id, v_row.owner_employee_id), v_members, v_depts);
  end if;
end;
$$;

-- ═══════════════════════════════════════════════
-- 11. upsert_project_step_admin — المكلَّف من نطاق المشروع + إشعاره
-- ═══════════════════════════════════════════════

create or replace function public.upsert_project_step_admin(
  p_project_id           uuid,
  p_step_id              uuid,
  p_title                text,
  p_description          text,
  p_sort_order           integer,
  p_status               text default 'pending',
  p_due_date             date default null,
  p_assignee_employee_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id       uuid;
  v_previous uuid;
  v_project  text;
begin
  if not exists (select 1 from public.association_projects where id = p_project_id)
     or not public._association_project_can_manage(p_project_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if nullif(btrim(coalesce(p_title, '')), '') is null then
    raise exception 'عنوان الخطوة مطلوب' using errcode = '22023';
  end if;
  if coalesce(p_status, 'pending') not in ('pending','in_progress','done','blocked') then
    raise exception 'حالة خطوة غير صحيحة' using errcode = '22023';
  end if;
  if p_assignee_employee_id is not null then
    if not exists (select 1 from public.employees where id = p_assignee_employee_id and is_active) then
      raise exception 'الموظف المكلَّف غير موجود أو غير نشط' using errcode = '22023';
    end if;
    if public._association_project_role_of(p_project_id, p_assignee_employee_id) is null then
      raise exception 'المكلَّف يجب أن يكون من فريق المشروع أو من إداراته — أضفه للفريق أولاً' using errcode = '22023';
    end if;
  end if;

  if p_step_id is not null then
    select assignee_employee_id into v_previous
      from public.association_project_steps where id = p_step_id and project_id = p_project_id;

    update public.association_project_steps set
      title                = btrim(p_title),
      description          = nullif(btrim(coalesce(p_description, '')), ''),
      sort_order           = coalesce(p_sort_order, sort_order),
      status               = coalesce(p_status, 'pending'),
      due_date             = p_due_date,
      assignee_employee_id = p_assignee_employee_id
    where id = p_step_id and project_id = p_project_id
    returning id into v_id;
    if v_id is null then
      raise exception 'STEP_NOT_FOUND' using errcode = 'P0002';
    end if;
  else
    insert into public.association_project_steps (
      project_id, title, description, sort_order, status, due_date, assignee_employee_id
    ) values (
      p_project_id, btrim(p_title), nullif(btrim(coalesce(p_description, '')), ''),
      coalesce(p_sort_order, (select coalesce(max(sort_order), 0) + 1
                                from public.association_project_steps where project_id = p_project_id)),
      coalesce(p_status, 'pending'), p_due_date, p_assignee_employee_id
    ) returning id into v_id;
  end if;

  if p_assignee_employee_id is not null and p_assignee_employee_id is distinct from v_previous
     and coalesce(p_status, 'pending') <> 'done' then
    select name into v_project from public.association_projects where id = p_project_id;
    perform public._association_project_notify_employee(
      p_project_id, p_assignee_employee_id,
      'مهمة جديدة في مشروع',
      'كُلّفت بـ«' || btrim(p_title) || '» في مشروع «' || v_project || '»'
        || coalesce(' — الموعد ' || to_char(p_due_date, 'YYYY/MM/DD'), '') || '.',
      'project_step_assigned');
  end if;

  return v_id;
end;
$$;

-- ═══════════════════════════════════════════════
-- 12. submit_project_for_approval — نص الإشعار بلا افتراض إدارة واحدة
-- ═══════════════════════════════════════════════

create or replace function public.submit_project_for_approval(p_project_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row    public.association_projects%rowtype;
  v_by     text;
begin
  select * into v_row from public.association_projects where id = p_project_id;
  if not found or not public._association_project_can_manage(p_project_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if v_row.approval_status not in ('draft','rejected') then
    raise exception 'المشروع مُرسل للاعتماد أو معتمد بالفعل' using errcode = '42501';
  end if;

  update public.association_projects set
    approval_status  = 'pending_approval',
    rejection_reason = null
  where id = p_project_id;

  select coalesce(
           (select string_agg(d.name, '، ' order by d.name)
              from public.association_project_departments pd
              join public.departments d on d.id = pd.department_id
             where pd.project_id = p_project_id),
           (select full_name_ar from public.employees where id = v_row.owner_employee_id))
    into v_by;

  perform public._association_project_notify(
    p_project_id, 'admins',
    'مشروع جديد بانتظار اعتمادك',
    'أُرسل مشروع «' || v_row.name || '»' || coalesce(' (' || v_by || ')', '') || ' للاعتماد.',
    'project_submitted', 'high');
end;
$$;

-- ═══════════════════════════════════════════════
-- 13. delete_association_project — من يعدّل المشروع يحذف مسودته
-- ═══════════════════════════════════════════════

create or replace function public.delete_association_project(p_project_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_approval text;
begin
  select approval_status into v_approval from public.association_projects where id = p_project_id;
  if v_approval is null or not public._association_project_can_edit(p_project_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if not public.current_is_full_access() and v_approval not in ('draft','rejected') then
    raise exception 'لا يمكن حذف مشروع مُرسل للاعتماد أو معتمد' using errcode = '42501';
  end if;

  delete from public.association_projects where id = p_project_id;
end;
$$;

-- ═══════════════════════════════════════════════
-- 14. notify_stalled_association_projects — يشمل مشاريع بلا إدارة
-- ═══════════════════════════════════════════════

create or replace function public.notify_stalled_association_projects()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_warning  int;
  v_critical int;
  r          record;
  v_count    int := 0;
begin
  select warning_days, critical_days into v_warning, v_critical
  from public.association_project_settings where id;

  for r in
    select p.id, p.name,
           coalesce((select string_agg(d.name, '، ' order by d.name)
                       from public.association_project_departments pd
                       join public.departments d on d.id = pd.department_id
                      where pd.project_id = p.id),
                    (select e.full_name_ar from public.employees e where e.id = p.owner_employee_id)) as who,
           floor(extract(epoch from now() - coalesce(p.last_activity_at, p.approved_at, p.created_at)) / 86400)::int as days
    from public.association_projects p
    where p.critical_notified_at is null
      and public._association_project_led(p.status, p.approval_status, p.last_activity_at,
                                           coalesce(v_warning, 7), coalesce(v_critical, 14)) = 'critical'
    for update of p skip locked
  loop
    perform public._association_project_notify(
      r.id, 'admins',
      'مشروع متعثّر يحتاج تدخلك',
      'مشروع «' || r.name || '»' || coalesce(' (' || r.who || ')', '') || ' بلا أي تحديث منذ ' || r.days || ' يوماً.',
      'project_stalled', 'high');
    perform public._association_project_notify(
      r.id, 'team',
      'مشروعكم متوقف منذ ' || r.days || ' يوماً',
      'لم يُسجَّل أي تحديث على مشروع «' || r.name || '». حدّث الخطوات أو أضف تحديثاً.',
      'project_stalled', 'high');
    update public.association_projects set critical_notified_at = now() where id = r.id;
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

-- ═══════════════════════════════════════════════
-- 15. get_association_project_pickers — الموظفون والإدارات لاختيار الفريق
--     (الاسم والوظيفة والإدارة فقط — لا بيانات تواصل)
-- ═══════════════════════════════════════════════

create or replace function public.get_association_project_pickers()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if public.current_employee_id() is null and not public.current_is_full_access() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'employees', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',             e.id,
        'name',           e.full_name_ar,
        'jobTitle',       jt.name,
        'departmentId',   e.department_id,
        'departmentName', d.name
      ) order by e.full_name_ar)
      from public.employees e
      left join public.job_titles  jt on jt.id = e.job_title_id
      left join public.departments d  on d.id  = e.department_id
      where e.is_active and not coalesce(e.is_deleted, false)
    ), '[]'::jsonb),
    'departments', coalesce((
      select jsonb_agg(jsonb_build_object('id', d.id, 'name', d.name) order by d.name)
      from public.departments d
      where coalesce(d.is_active, true)
    ), '[]'::jsonb)
  );
end;
$$;

-- ═══════════════════════════════════════════════
-- 16. الصلاحيات
-- ═══════════════════════════════════════════════

do $grants$
declare
  v_sig text;
begin
  foreach v_sig in array array[
    'public._association_project_role_of(uuid,uuid)',
    'public._association_project_role(uuid)',
    'public._association_project_can_manage(uuid)',
    'public._association_project_can_edit(uuid)',
    'public._association_project_notify(uuid,text,text,text,text,text)',
    'public._association_project_notify_employee(uuid,uuid,text,text,text,text)',
    'public._association_project_set_team(uuid,uuid,uuid[],uuid[])',
    'public._association_project_json(uuid,integer,integer)',
    'public.notify_stalled_association_projects()'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', v_sig);
    execute format('grant execute on function %s to service_role', v_sig);
  end loop;

  foreach v_sig in array array[
    'public.get_association_projects()',
    'public.get_association_project_detail(uuid)',
    'public.save_association_project(uuid,text,text,text,date,date,uuid,uuid[],uuid[],text)',
    'public.create_association_project_admin(text,text,text,uuid,uuid,text,date,date)',
    'public.update_association_project_admin(uuid,text,text,uuid,uuid,text,text,numeric,date,date)',
    'public.upsert_project_step_admin(uuid,uuid,text,text,integer,text,date,uuid)',
    'public.submit_project_for_approval(uuid)',
    'public.delete_association_project(uuid)',
    'public.get_association_project_pickers()'
  ] loop
    execute format('revoke all on function %s from public, anon', v_sig);
    execute format('grant execute on function %s to authenticated, service_role', v_sig);
  end loop;
end
$grants$;

notify pgrst, 'reload schema';

commit;
