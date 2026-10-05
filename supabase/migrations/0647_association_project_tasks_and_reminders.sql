-- ═══════════════════════════════════════════════════════════════
-- 0647: مشاريع الجمعية — «مهامي» + تذكير مواعيد المهام + ترتيب الخطوات
--
--   • get_my_project_tasks: كل المهام المفتوحة المكلَّف بها المستخدم عبر كل
--     المشاريع (لتبويب «مهامي» في الويب والموبايل).
--   • notify_project_step_deadlines (كرون يومي 06:15 UTC ≈ 09:15 القاهرة):
--       - مهمة موعدها غداً → تذكير للمكلَّف.
--       - مهمة متأخرة → تذكير للمكلَّف كل 3 أيام، وإشعار قائد المشروع أول مرة.
--     reminded_on يمنع التكرار في نفس اليوم.
--   • move_project_step: تحريك خطوة لأعلى/لأسفل (يُطبّع sort_order أولاً).
-- ═══════════════════════════════════════════════════════════════

begin;

alter table public.association_project_steps
  add column if not exists reminded_on date;

comment on column public.association_project_steps.reminded_on is
  '0647: آخر يوم (بتوقيت القاهرة) أُرسل فيه تذكير موعد هذه المهمة.';

create index if not exists ix_association_project_steps_assignee_open
  on public.association_project_steps (assignee_employee_id)
  where status <> 'done' and assignee_employee_id is not null;

-- ═══════════════════════════════════════════════
-- 1. get_my_project_tasks — مهامي المفتوحة عبر كل المشاريع
-- ═══════════════════════════════════════════════

create or replace function public.get_my_project_tasks()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_emp   uuid := public.current_employee_id();
  v_today date := (now() at time zone 'Africa/Cairo')::date;
begin
  if v_emp is null then
    raise exception 'EMPLOYEE_CONTEXT_REQUIRED' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'stepId',        s.id,
      'title',         s.title,
      'description',   s.description,
      'status',        s.status,
      'dueDate',       s.due_date,
      'isOverdue',     s.due_date is not null and s.due_date < v_today,
      'isDueSoon',     s.due_date is not null and s.due_date between v_today and v_today + 2,
      'projectId',     p.id,
      'projectName',   p.name,
      'projectStatus', p.status,
      'approvalStatus', p.approval_status,
      'leaderName',    le.full_name_ar
    ) order by (s.due_date is null), s.due_date, p.name, s.sort_order)
    from public.association_project_steps s
    join public.association_projects p on p.id = s.project_id
    left join public.employees le on le.id = p.owner_employee_id
    where s.assignee_employee_id = v_emp
      and s.status <> 'done'
      and p.status not in ('completed', 'cancelled')
      -- المكلَّف خارج نطاق المشروع (أُخرج منه) لا تظهر له المهمة.
      and public._association_project_role_of(p.id, v_emp) is not null
  ), '[]'::jsonb);
end;
$$;

-- ═══════════════════════════════════════════════
-- 2. move_project_step — تحريك خطوة لأعلى/لأسفل
-- ═══════════════════════════════════════════════

create or replace function public.move_project_step(p_step_id uuid, p_direction text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_project uuid;
  v_order   int;
  v_other   uuid;
  v_other_order int;
begin
  select project_id into v_project from public.association_project_steps where id = p_step_id;
  if v_project is null or not public._association_project_can_manage(v_project) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if p_direction not in ('up', 'down') then
    raise exception 'اتجاه غير صحيح' using errcode = '22023';
  end if;

  -- تطبيع الترتيب (1..n) حتى لا تتساوى قيم sort_order.
  update public.association_project_steps s set sort_order = x.rn
  from (select id, row_number() over (order by sort_order, created_at, id)::int as rn
          from public.association_project_steps where project_id = v_project) x
  where s.id = x.id and s.sort_order is distinct from x.rn;

  select sort_order into v_order from public.association_project_steps where id = p_step_id;

  select id, sort_order into v_other, v_other_order
  from public.association_project_steps
  where project_id = v_project
    and sort_order = case when p_direction = 'up' then v_order - 1 else v_order + 1 end;

  if v_other is null then
    return; -- الخطوة في الطرف بالفعل
  end if;

  update public.association_project_steps set sort_order = v_other_order where id = p_step_id;
  update public.association_project_steps set sort_order = v_order       where id = v_other;
end;
$$;

-- ═══════════════════════════════════════════════
-- 3. notify_project_step_deadlines — كرون يومي
-- ═══════════════════════════════════════════════

create or replace function public.notify_project_step_deadlines()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  r       record;
  v_count int := 0;
begin
  for r in
    select s.id, s.title, s.due_date, s.reminded_on, s.assignee_employee_id,
           p.id as project_id, p.name as project_name, p.owner_employee_id as leader_id
    from public.association_project_steps s
    join public.association_projects p on p.id = s.project_id
    where s.status <> 'done'
      and s.assignee_employee_id is not null
      and s.due_date is not null
      and p.approval_status = 'approved'
      and p.status not in ('completed', 'cancelled')
      and (
        -- موعدها غداً ولم يُذكَّر اليوم
        (s.due_date = v_today + 1 and s.reminded_on is distinct from v_today)
        -- متأخرة: أول مرة، ثم كل 3 أيام
        or (s.due_date < v_today and (s.reminded_on is null or s.reminded_on < s.due_date or s.reminded_on <= v_today - 3))
      )
    for update of s skip locked
  loop
    if r.due_date = v_today + 1 then
      perform public._association_project_notify_employee(
        r.project_id, r.assignee_employee_id,
        'موعد مهمة غداً',
        'مهمة «' || r.title || '» في مشروع «' || r.project_name || '» موعدها غداً.',
        'project_step_due');
    else
      perform public._association_project_notify_employee(
        r.project_id, r.assignee_employee_id,
        'مهمة متأخرة عن موعدها',
        'مهمة «' || r.title || '» في مشروع «' || r.project_name || '» متأخرة منذ '
          || (v_today - r.due_date) || ' يوم. حدّث حالتها أو أنجزها.',
        'project_step_overdue', 'high');
      -- القائد يُشعَر أول مرة فقط تتأخر فيها المهمة.
      if r.leader_id is distinct from r.assignee_employee_id
         and (r.reminded_on is null or r.reminded_on < r.due_date) then
        perform public._association_project_notify_employee(
          r.project_id, r.leader_id,
          'مهمة متأخرة في مشروعك',
          'مهمة «' || r.title || '» في مشروع «' || r.project_name || '» تجاوزت موعدها.',
          'project_step_overdue');
      end if;
    end if;

    -- التذكير ليس نشاطاً على المشروع: trigger النشاط (القسم 4) لا يتفاعل مع reminded_on.
    update public.association_project_steps set reminded_on = v_today where id = r.id;
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

-- ═══════════════════════════════════════════════
-- 4. نشاط المشروع: تحديث reminded_on وحده ليس نشاطاً
--    (trigger 0553 كان يعتبر أي UPDATE على خطوة نشاطاً فيطفئ الأحمر).
-- ═══════════════════════════════════════════════

drop trigger if exists trg_association_step_touch_project on public.association_project_steps;
create trigger trg_association_step_touch_project
  after insert or delete or update of title, description, status, due_date, assignee_employee_id
  on public.association_project_steps
  for each row execute function public.tg_association_step_touch_project();

-- ═══════════════════════════════════════════════
-- 5. الصلاحيات + الكرون
-- ═══════════════════════════════════════════════

revoke all on function public.notify_project_step_deadlines() from public, anon, authenticated;
grant execute on function public.notify_project_step_deadlines() to service_role;

revoke all on function public.get_my_project_tasks() from public, anon;
grant execute on function public.get_my_project_tasks() to authenticated, service_role;
revoke all on function public.move_project_step(uuid, text) from public, anon;
grant execute on function public.move_project_step(uuid, text) to authenticated, service_role;

do $cron$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron غير مفعّل — تذكير مواعيد المهام لن يُجدول.';
    return;
  end if;

  perform cron.unschedule(jobname) from cron.job
   where jobname = 'association_project_step_deadlines';

  perform cron.schedule(
    'association_project_step_deadlines', '15 6 * * *',
    $job$ select public.notify_project_step_deadlines() $job$
  );
end
$cron$;

notify pgrst, 'reload schema';

commit;
