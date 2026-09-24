-- ═══════════════════════════════════════════════════════════════
-- 0553: مشاريع الجمعية — سير عمل الإدارات + لمبة التنبيه الثلاثية
--
-- الفكرة: كل إدارة ترفع مشروعها ← المدير التنفيذي يعتمده ← يظهر على
-- الشاشة الرئيسية بلمبة حالة، والإدارة صاحبة المشروع تدير خطواته/مهامه.
--
-- ما كان مكسوراً قبل هذه الـ migration:
--   (1) الصلاحية كانت «المالك الشخصي» فقط — بقية أعضاء الإدارة ومديرها
--       لا يستطيعون إضافة/تعديل مهام مشروع إدارتهم ولا حتى رؤيته.
--   (2) اللمبة: مشروع معتمد بلا تحديث = «مطفأ» رمادي بدل الأحمر، والمكتمل
--       يظهر «مطفأ» كالملغى، وتعديل الخطوات لا يُحتسب نشاطاً إطلاقاً.
--   (3) نسبة الإنجاز يدوية منفصلة عن الخطوات المكتملة.
--   (4) لا إشعار للمدير التنفيذي عند طلب اعتماد أو عند تعثّر مشروع.
--
-- الجديد:
--   • last_activity_at: يتحدّث مع كل تحديث/تعديل خطوة/اعتماد (trigger).
--   • اللمبة: active (أخضر) / halted (أحمر ثابت) / critical (أحمر يومض —
--     يحتاج تدخل المدير التنفيذي) / completed / stale (ملغى) + حالات الاعتماد.
--   • حدود الأيام قابلة للضبط: association_project_settings (افتراضي 7 / 14).
--   • نطاق الإدارة: الموظف النشط في إدارة المشروع + مدير الإدارة + المالك.
--   • progress يُشتق تلقائياً من الخطوات المكتملة متى وُجدت خطوات.
--   • إشعارات: طلب اعتماد → full-access، اعتماد/رفض → المالك، تعثّر → الكل.
--
-- كل الدوال المستبدلة: استبدال كنوني كامل (create or replace) بنفس
-- التواقيع — STABLE + SET search_path محفوظة، ORDER BY داخل jsonb_agg.
-- ═══════════════════════════════════════════════════════════════

begin;

-- ═══════════════════════════════════════════════
-- 1. أعمدة جديدة
-- ═══════════════════════════════════════════════

alter table public.association_projects
  add column if not exists last_activity_at     timestamptz,
  add column if not exists critical_notified_at timestamptz;

alter table public.association_project_steps
  add column if not exists completed_at timestamptz;

comment on column public.association_projects.last_activity_at is
  '0553: آخر نشاط فعلي (تحديث، تعديل خطوة، اعتماد) — مصدر لون اللمبة.';
comment on column public.association_projects.critical_notified_at is
  '0553: متى أُرسل تنبيه «يحتاج تدخل» — يُصفَّر مع أي نشاط جديد حتى لا يتكرر.';

-- ترميم الصفوف القائمة: أحدث علامة نشاط معروفة.
update public.association_projects p set last_activity_at = greatest(
  p.last_update_at,
  p.approved_at,
  (select max(coalesce(s.updated_at, s.created_at))
     from public.association_project_steps s where s.project_id = p.id)
)
where p.last_activity_at is null;

update public.association_project_steps
   set completed_at = coalesce(updated_at, created_at)
 where status = 'done' and completed_at is null;

create index if not exists ix_association_projects_department
  on public.association_projects (department_id);
create index if not exists ix_association_project_steps_project
  on public.association_project_steps (project_id, sort_order);
create index if not exists ix_association_project_updates_project
  on public.association_project_updates (project_id, created_at desc);

-- ═══════════════════════════════════════════════
-- 2. إعدادات حدود اللمبة (صف واحد)
-- ═══════════════════════════════════════════════

create table if not exists public.association_project_settings (
  id            boolean primary key default true check (id),
  warning_days  integer not null default 7  check (warning_days  between 1 and 365),
  critical_days integer not null default 14 check (critical_days between 2 and 730),
  updated_at    timestamptz,
  updated_by    uuid references auth.users(id),
  constraint ck_association_project_settings_order check (critical_days > warning_days)
);

insert into public.association_project_settings (id) values (true)
on conflict (id) do nothing;

alter table public.association_project_settings enable row level security;

-- جدول إعداد مرجعي للقراءة فقط؛ الكتابة عبر set_association_project_settings.
drop policy if exists association_project_settings_read on public.association_project_settings;
create policy association_project_settings_read on public.association_project_settings
  for select to authenticated using (true);

-- ═══════════════════════════════════════════════
-- 3. دوال مساعدة داخلية (غير مكشوفة للعميل)
-- ═══════════════════════════════════════════════

-- هل الموظف الحالي من «إدارة المشروع»؟ (المالك، أو عضو نشط في الإدارة، أو مديرها)
create or replace function public._association_project_is_member(
  p_department_id uuid,
  p_owner_id      uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce((
    select v.emp = p_owner_id
        or exists (select 1 from public.employees e
                    where e.id = v.emp and e.is_active and e.department_id = p_department_id)
        or exists (select 1 from public.departments d
                    where d.id = p_department_id and d.manager_id = v.emp)
    from (select public.current_employee_id() as emp) v
    where v.emp is not null
  ), false);
$$;

-- full-access أو عضو في إدارة المشروع
create or replace function public._association_project_can_manage(p_project_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.current_is_full_access()
      or exists (select 1 from public.association_projects p
                  where p.id = p_project_id
                    and public._association_project_is_member(p.department_id, p.owner_employee_id));
$$;

-- لون اللمبة — المصدر الوحيد للقاعدة (القائمة والتفاصيل والكرون)
create or replace function public._association_project_led(
  p_status        text,
  p_approval      text,
  p_last_activity timestamptz,
  p_warning_days  integer,
  p_critical_days integer
)
returns text
language sql
stable
set search_path = public, pg_temp
as $$
  select case
    when p_approval = 'pending_approval' then 'pending'
    when p_approval = 'rejected'         then 'rejected'
    when p_approval = 'draft'            then 'draft'
    when p_status   = 'completed'        then 'completed'
    when p_status   = 'cancelled'        then 'stale'
    when p_last_activity is null
      or p_last_activity < now() - make_interval(days => p_critical_days) then 'critical'
    when p_status = 'on_hold'
      or p_last_activity < now() - make_interval(days => p_warning_days)  then 'halted'
    else 'active'
  end;
$$;

-- كائن JSON موحّد لمشروع واحد (يُستخدم في القائمة والتفاصيل)
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
    'departmentName',    d.name,
    'ownerId',           p.owner_employee_id,
    'ownerName',         e.full_name_ar,
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
    'canManage',         public.current_is_full_access()
                         or public._association_project_is_member(p.department_id, p.owner_employee_id),
    'ledStatus',         public._association_project_led(
                           p.status, p.approval_status, p.last_activity_at,
                           p_warning_days, p_critical_days)
  )
  from public.association_projects p
  join public.departments d on d.id = p.department_id
  join public.employees   e on e.id = p.owner_employee_id
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

-- إرسال إشعار لمجموعة مستلمين: 'admins' (full-access) أو 'department' (المالك + مدير الإدارة)
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
  v_dept  uuid;
begin
  select owner_employee_id, department_id into v_owner, v_dept
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
    where p_audience = 'department'
      and e.is_active and e.user_id is not null
      and (e.id = v_owner
           or e.id = (select d.manager_id from public.departments d where d.id = v_dept))
  ) r
  -- لا نُشعر الفاعل نفسه بما فعله.
  where r.user_id is distinct from auth.uid();
end;
$$;

-- ═══════════════════════════════════════════════
-- 4. Triggers: completed_at + نشاط/تقدم المشروع من الخطوات
-- ═══════════════════════════════════════════════

create or replace function public.tg_association_step_completed_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.status = 'done' then
    if tg_op = 'INSERT' then
      new.completed_at := now();
    elsif old.status is distinct from 'done' then
      new.completed_at := now();
    end if;
  else
    new.completed_at := null;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_association_step_completed_at on public.association_project_steps;
create trigger trg_association_step_completed_at
  before insert or update of status on public.association_project_steps
  for each row execute function public.tg_association_step_completed_at();

create or replace function public.tg_association_step_touch_project()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_project uuid := coalesce(new.project_id, old.project_id);
  v_total   int;
  v_done    int;
  v_started boolean;
begin
  select count(*), count(*) filter (where status = 'done'),
         bool_or(status in ('in_progress','done'))
    into v_total, v_done, v_started
  from public.association_project_steps where project_id = v_project;

  update public.association_projects set
    last_activity_at     = now(),
    critical_notified_at = null,
    progress = case when v_total > 0 then round(100.0 * v_done / v_total, 2) else progress end,
    -- بدء أول خطوة في مشروع معتمد «مخطط» = المشروع بدأ فعلياً.
    status   = case when status = 'planned' and approval_status = 'approved' and coalesce(v_started, false)
                    then 'active' else status end
  where id = v_project;

  return null;
end;
$$;

drop trigger if exists trg_association_step_touch_project on public.association_project_steps;
create trigger trg_association_step_touch_project
  after insert or update or delete on public.association_project_steps
  for each row execute function public.tg_association_step_touch_project();

-- ═══════════════════════════════════════════════
-- 5. get_association_projects — استبدال كنوني
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
      where v_full or public._association_project_is_member(p.department_id, p.owner_employee_id)
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
        where v_full or public._association_project_is_member(p.department_id, p.owner_employee_id)
        order by u.created_at desc
        limit 30
      ) x
    ), '[]'::jsonb),
    'lastUpdatedAt',  now(),
    'isFullAccess',   v_full,
    'canCreate',      v_full or v_dept is not null,
    'myDepartmentId', v_dept,
    'settings',       jsonb_build_object('warningDays', v_warning, 'criticalDays', v_critical)
  );
end;
$$;

-- ═══════════════════════════════════════════════
-- 6. get_association_project_detail — استبدال كنوني
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
  v_manage   boolean;
  v_approval text;
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

  v_manage := public._association_project_can_manage(p_project_id);
  if not v_manage then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

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
      'canManage',  true,
      'canApprove', v_full and v_approval = 'pending_approval',
      'canEdit',    v_full or v_approval in ('draft','rejected'),
      'canSubmit',  v_approval in ('draft','rejected'),
      'canUpdate',  v_approval = 'approved',
      'canDelete',  v_full or v_approval in ('draft','rejected')
    )
  );
end;
$$;

-- ═══════════════════════════════════════════════
-- 7. create_association_project_admin — استبدال كنوني
--    full-access: أي إدارة، ويُعتمد مباشرة.
--    غيره: إدارته فقط (أو إدارة يديرها)، يملكه بنفسه، ويبدأ draft.
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
  v_id    uuid;
  v_emp   uuid := public.current_employee_id();
  v_full  boolean := public.current_is_full_access();
  v_owner uuid;
  v_code  text := nullif(btrim(coalesce(p_code, '')), '');
  v_n     int;
begin
  if not v_full and v_emp is null then
    raise exception 'EMPLOYEE_CONTEXT_REQUIRED' using errcode = '42501';
  end if;
  if nullif(btrim(coalesce(p_name, '')), '') is null then
    raise exception 'اسم المشروع مطلوب' using errcode = '22023';
  end if;
  if p_department_id is null or not exists (select 1 from public.departments where id = p_department_id) then
    raise exception 'الإدارة غير صحيحة' using errcode = '22023';
  end if;
  if coalesce(p_priority, 'medium') not in ('low','medium','high','critical') then
    raise exception 'أولوية غير صحيحة' using errcode = '22023';
  end if;
  if p_start_date is not null and p_target_end_date is not null and p_target_end_date < p_start_date then
    raise exception 'الموعد النهائي قبل تاريخ البدء' using errcode = '22023';
  end if;

  if v_full then
    v_owner := coalesce(p_owner_employee_id, v_emp);
    if v_owner is null then
      raise exception 'مسؤول المشروع مطلوب' using errcode = '22023';
    end if;
  else
    if p_owner_employee_id is not null and p_owner_employee_id <> v_emp then
      raise exception 'FORBIDDEN' using errcode = '42501';
    end if;
    if not public._association_project_is_member(p_department_id, null) then
      raise exception 'لا يمكنك إنشاء مشروع إلا لإدارتك' using errcode = '42501';
    end if;
    v_owner := v_emp;
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
    v_code, btrim(p_name), nullif(btrim(coalesce(p_description, '')), ''), p_department_id, v_owner,
    'planned',
    case when v_full then 'approved' else 'draft' end,
    case when v_full then auth.uid() end,
    case when v_full then now() end,
    case when v_full then now() end,
    coalesce(p_priority, 'medium'), p_start_date, p_target_end_date, auth.uid()
  ) returning id into v_id;

  return v_id;
end;
$$;

-- ═══════════════════════════════════════════════
-- 8. update_association_project_admin — استبدال كنوني (تحديث جزئي)
--    full-access: أي حقل وأي وقت. الإدارة: الحقول الأساسية وهو draft/rejected.
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
  v_full  boolean := public.current_is_full_access();
  v_row   public.association_projects%rowtype;
  v_steps int;
begin
  select * into v_row from public.association_projects where id = p_project_id;
  if not found or not public._association_project_can_manage(p_project_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if not v_full then
    if v_row.approval_status not in ('draft','rejected') then
      raise exception 'لا يمكن تعديل بيانات مشروع بعد إرساله للاعتماد' using errcode = '42501';
    end if;
    -- الإدارة لا تنقل المشروع لإدارة/مالك آخر ولا تغيّر الحالة التشغيلية هنا.
    if (p_department_id is not null and p_department_id <> v_row.department_id)
       or (p_owner_employee_id is not null and p_owner_employee_id <> v_row.owner_employee_id)
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

  select count(*) into v_steps from public.association_project_steps where project_id = p_project_id;

  update public.association_projects set
    name              = coalesce(nullif(btrim(p_name), ''), name),
    description       = coalesce(p_description, description),
    department_id     = coalesce(p_department_id, department_id),
    owner_employee_id = coalesce(p_owner_employee_id, owner_employee_id),
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
end;
$$;

-- ═══════════════════════════════════════════════
-- 9. add_project_update_admin — استبدال كنوني
--    تحديث دوري من الإدارة على مشروع معتمد (يُطفئ الأحمر).
-- ═══════════════════════════════════════════════

create or replace function public.add_project_update_admin(
  p_project_id     uuid,
  p_note           text,
  p_progress       numeric,
  p_status_change  text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_emp    uuid := public.current_employee_id();
  v_row    public.association_projects%rowtype;
  v_steps  int;
  v_status text;
begin
  select * into v_row from public.association_projects where id = p_project_id;
  if not found or not public._association_project_can_manage(p_project_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if v_emp is null then
    raise exception 'EMPLOYEE_CONTEXT_REQUIRED' using errcode = '42501';
  end if;
  if v_row.approval_status <> 'approved' then
    raise exception 'لا يمكن إضافة تحديث قبل اعتماد المشروع' using errcode = '42501';
  end if;
  if nullif(btrim(coalesce(p_note, '')), '') is null then
    raise exception 'نص التحديث مطلوب' using errcode = '22023';
  end if;
  if p_status_change is not null and p_status_change not in ('planned','active','on_hold','completed','cancelled') then
    raise exception 'حالة غير صحيحة' using errcode = '22023';
  end if;
  if p_progress is not null and (p_progress < 0 or p_progress > 100) then
    raise exception 'نسبة الإنجاز يجب أن تكون بين 0 و100' using errcode = '22023';
  end if;

  select count(*) into v_steps from public.association_project_steps where project_id = p_project_id;

  -- أي تحديث على مشروع «مخطط» بلا تغيير صريح = بدأ التنفيذ.
  v_status := coalesce(p_status_change, case when v_row.status = 'planned' then 'active' else v_row.status end);

  insert into public.association_project_updates (project_id, author_employee_id, note, progress, status_change)
  values (p_project_id, v_emp, btrim(p_note),
          case when v_steps > 0 then v_row.progress else p_progress end,
          nullif(v_status, v_row.status));

  update public.association_projects set
    last_update_at       = now(),
    last_update_note     = btrim(p_note),
    last_activity_at     = now(),
    critical_notified_at = null,
    status               = v_status,
    progress             = case when v_steps > 0 then progress
                                when v_status = 'completed' then 100
                                else coalesce(p_progress, progress) end
  where id = p_project_id;
end;
$$;

-- ═══════════════════════════════════════════════
-- 10. upsert_project_step_admin — استبدال كنوني
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
  v_id uuid;
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
  if p_assignee_employee_id is not null
     and not exists (select 1 from public.employees where id = p_assignee_employee_id and is_active) then
    raise exception 'الموظف المكلَّف غير موجود أو غير نشط' using errcode = '22023';
  end if;

  if p_step_id is not null then
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

  return v_id;
end;
$$;

-- ═══════════════════════════════════════════════
-- 11. set_project_step_status — تغيير سريع لحالة خطوة (علامة ✓)
-- ═══════════════════════════════════════════════

create or replace function public.set_project_step_status(p_step_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_project uuid;
begin
  select project_id into v_project from public.association_project_steps where id = p_step_id;
  if v_project is null or not public._association_project_can_manage(v_project) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if p_status not in ('pending','in_progress','done','blocked') then
    raise exception 'حالة خطوة غير صحيحة' using errcode = '22023';
  end if;

  update public.association_project_steps set status = p_status where id = p_step_id;
end;
$$;

-- ═══════════════════════════════════════════════
-- 12. delete_project_step_admin — استبدال كنوني
-- ═══════════════════════════════════════════════

create or replace function public.delete_project_step_admin(p_step_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_project uuid;
begin
  select project_id into v_project from public.association_project_steps where id = p_step_id;
  if v_project is null or not public._association_project_can_manage(v_project) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  delete from public.association_project_steps where id = p_step_id;
end;
$$;

-- ═══════════════════════════════════════════════
-- 13. submit_project_for_approval — أي عضو في الإدارة
-- ═══════════════════════════════════════════════

create or replace function public.submit_project_for_approval(p_project_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row  public.association_projects%rowtype;
  v_dept text;
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

  select name into v_dept from public.departments where id = v_row.department_id;
  perform public._association_project_notify(
    p_project_id, 'admins',
    'مشروع جديد بانتظار اعتمادك',
    'أرسلت ' || coalesce(v_dept, 'إحدى الإدارات') || ' مشروع «' || v_row.name || '» للاعتماد.',
    'project_submitted', 'high');
end;
$$;

-- ═══════════════════════════════════════════════
-- 14. approve_project / reject_project — استبدال كنوني + إشعار الإدارة
-- ═══════════════════════════════════════════════

create or replace function public.approve_project(p_project_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_name text;
begin
  if not public.current_is_full_access() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  update public.association_projects set
    approval_status      = 'approved',
    approved_by          = auth.uid(),
    approved_at          = now(),
    rejection_reason     = null,
    last_activity_at     = now(),
    critical_notified_at = null
  where id = p_project_id and approval_status = 'pending_approval'
  returning name into v_name;

  if v_name is null then
    raise exception 'PROJECT_NOT_PENDING' using errcode = 'P0002';
  end if;

  perform public._association_project_notify(
    p_project_id, 'department',
    'تم اعتماد المشروع',
    'اعتُمد مشروع «' || v_name || '» وأصبح ظاهراً على لوحة مشاريع الجمعية. ابدأ بإضافة خطوات التنفيذ.',
    'project_approved');
end;
$$;

create or replace function public.reject_project(
  p_project_id uuid,
  p_reason     text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_name text;
begin
  if not public.current_is_full_access() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  update public.association_projects set
    approval_status  = 'rejected',
    rejection_reason = nullif(btrim(coalesce(p_reason, '')), '')
  where id = p_project_id and approval_status = 'pending_approval'
  returning name into v_name;

  if v_name is null then
    raise exception 'PROJECT_NOT_PENDING' using errcode = 'P0002';
  end if;

  perform public._association_project_notify(
    p_project_id, 'department',
    'لم يُعتمد المشروع',
    'أُعيد مشروع «' || v_name || '» للتعديل'
      || coalesce(': ' || nullif(btrim(coalesce(p_reason, '')), ''), '.'),
    'project_rejected', 'high');
end;
$$;

-- ═══════════════════════════════════════════════
-- 15. delete_association_project — المسودات للإدارة، وأي مشروع لـ full-access
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
  if v_approval is null or not public._association_project_can_manage(p_project_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if not public.current_is_full_access() and v_approval not in ('draft','rejected') then
    raise exception 'لا يمكن حذف مشروع مُرسل للاعتماد أو معتمد' using errcode = '42501';
  end if;

  delete from public.association_projects where id = p_project_id;
end;
$$;

-- ═══════════════════════════════════════════════
-- 16. set_association_project_settings — حدود أيام اللمبة (full-access)
-- ═══════════════════════════════════════════════

create or replace function public.set_association_project_settings(
  p_warning_days  integer,
  p_critical_days integer
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.current_is_full_access() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if p_warning_days is null or p_critical_days is null
     or p_warning_days < 1 or p_critical_days <= p_warning_days or p_critical_days > 730 then
    raise exception 'أيام التنبيه يجب أن تكون أقل من أيام التدخل' using errcode = '22023';
  end if;

  insert into public.association_project_settings (id, warning_days, critical_days, updated_at, updated_by)
  values (true, p_warning_days, p_critical_days, now(), auth.uid())
  on conflict (id) do update set
    warning_days  = excluded.warning_days,
    critical_days = excluded.critical_days,
    updated_at    = excluded.updated_at,
    updated_by    = excluded.updated_by;
end;
$$;

-- ═══════════════════════════════════════════════
-- 17. notify_stalled_association_projects — كرون يومي
--     مشروع وصل «يحتاج تدخل» → إشعار واحد للمدير التنفيذي والإدارة.
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
    select p.id, p.name, d.name as dept_name,
           floor(extract(epoch from now() - coalesce(p.last_activity_at, p.approved_at, p.created_at)) / 86400)::int as days
    from public.association_projects p
    join public.departments d on d.id = p.department_id
    where p.critical_notified_at is null
      and public._association_project_led(p.status, p.approval_status, p.last_activity_at,
                                           coalesce(v_warning, 7), coalesce(v_critical, 14)) = 'critical'
    for update of p skip locked
  loop
    perform public._association_project_notify(
      r.id, 'admins',
      'مشروع متعثّر يحتاج تدخلك',
      'مشروع «' || r.name || '» (' || r.dept_name || ') بلا أي تحديث منذ ' || r.days || ' يوماً.',
      'project_stalled', 'high');
    perform public._association_project_notify(
      r.id, 'department',
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
-- 18. الصلاحيات
--     الدوال المساعدة (_*) والكرون والتريجرات: خادمية فقط.
-- ═══════════════════════════════════════════════

do $grants$
declare
  v_sig text;
begin
  foreach v_sig in array array[
    'public._association_project_is_member(uuid,uuid)',
    'public._association_project_can_manage(uuid)',
    'public._association_project_led(text,text,timestamptz,integer,integer)',
    'public._association_project_json(uuid,integer,integer)',
    'public._association_project_notify(uuid,text,text,text,text,text)',
    'public.tg_association_step_completed_at()',
    'public.tg_association_step_touch_project()',
    'public.notify_stalled_association_projects()'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', v_sig);
    execute format('grant execute on function %s to service_role', v_sig);
  end loop;

  foreach v_sig in array array[
    'public.get_association_projects()',
    'public.get_association_project_detail(uuid)',
    'public.create_association_project_admin(text,text,text,uuid,uuid,text,date,date)',
    'public.update_association_project_admin(uuid,text,text,uuid,uuid,text,text,numeric,date,date)',
    'public.add_project_update_admin(uuid,text,numeric,text)',
    'public.upsert_project_step_admin(uuid,uuid,text,text,integer,text,date,uuid)',
    'public.set_project_step_status(uuid,text)',
    'public.delete_project_step_admin(uuid)',
    'public.submit_project_for_approval(uuid)',
    'public.approve_project(uuid)',
    'public.reject_project(uuid,text)',
    'public.delete_association_project(uuid)',
    'public.set_association_project_settings(integer,integer)'
  ] loop
    execute format('revoke all on function %s from public, anon', v_sig);
    execute format('grant execute on function %s to authenticated, service_role', v_sig);
  end loop;
end
$grants$;

revoke insert, update, delete on public.association_project_settings from anon, authenticated;
grant select on public.association_project_settings to authenticated;

-- ═══════════════════════════════════════════════
-- 19. جدولة الكرون: يومياً 06:00 UTC ≈ 09:00 ص بتوقيت القاهرة
-- ═══════════════════════════════════════════════

do $cron$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron غير مفعّل — تنبيه المشاريع المتعثّرة لن يُجدول.';
    return;
  end if;

  perform cron.unschedule(jobname) from cron.job
   where jobname = 'association_projects_stalled_alert';

  perform cron.schedule(
    'association_projects_stalled_alert', '0 6 * * *',
    $job$ select public.notify_stalled_association_projects() $job$
  );
end
$cron$;

notify pgrst, 'reload schema';

commit;
