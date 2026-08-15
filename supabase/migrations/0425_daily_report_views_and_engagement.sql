-- 0425: مشاهدات التقارير اليومية + "من شاهد ومن تفاعل" للجميع.
--
-- المتطلبات (من طلب المستخدم):
--   • بوكس التقارير اليومية في الواجهة الأولى للموبايل لكل المستخدمين.
--   • كل تقرير يومي يُظهر من شاهده ومن تفاعل معه (إعجاب/تعليق).
--   • صفحة الإعلانات الداخلية تُظهر أيضاً من شاهد ومن تفاعل لكل الموظفين
--     (تخفيف حارس get_announcement_engagement — كان للناشر/الإدارة فقط).
--
-- التصميم:
--   • جدول daily_report_views بنمط announcement_views (صف واحد لكل موظف
--     وتقرير مع view_count يتزايد عند كل فتح).
--   • record_daily_reports_views(uuid[]) — تسجيل جماعي لفتح صفحة التقرير
--     باستدعاء واحد (نصف عدد الطلبات مقارنة ب RPC مفرد لكل تقرير).
--   • get_daily_report_engagement(uuid) — القائمة الكاملة للمشاهدين والمعجبين.
--   • توسيع get_public_daily_reports_feed بحقول viewersCount/viewers/likers
--     (أول 3 لكل قائمة) لتعرض في البطاقة مباشرة.
--   • إعادة تعريف get_announcement_engagement بلا حارس الصلاحيات —
--     يبقى فقط شرط تسجيل الدخول (auth.uid() is not null).

begin;

-- ---------------------------------------------------------------------------
-- 1) daily_report_views — مشاهدات التقارير اليومية
-- ---------------------------------------------------------------------------
create table if not exists public.daily_report_views (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.daily_reports(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  first_viewed_at timestamptz not null default now(),
  last_viewed_at timestamptz not null default now(),
  view_count integer not null default 1 check (view_count > 0),
  created_by uuid references auth.users(id),
  constraint daily_report_views_uq unique (report_id, employee_id)
);

comment on table public.daily_report_views is
  'مشاهدات التقارير اليومية: صف واحد لكل (تقرير، موظف) و view_count يتزايد عند كل فتح.';

create index if not exists ix_daily_report_views_report_last
  on public.daily_report_views(report_id, last_viewed_at desc);
create index if not exists ix_daily_report_views_employee
  on public.daily_report_views(employee_id);

alter table public.daily_report_views enable row level security;

drop policy if exists daily_report_views_select on public.daily_report_views;
create policy daily_report_views_select on public.daily_report_views
  for select to authenticated
  using (true);

drop policy if exists daily_report_views_insert on public.daily_report_views;
create policy daily_report_views_insert on public.daily_report_views
  for insert to authenticated
  with check (employee_id = public.current_employee_id());

drop policy if exists daily_report_views_update on public.daily_report_views;
create policy daily_report_views_update on public.daily_report_views
  for update to authenticated
  using (employee_id = public.current_employee_id())
  with check (employee_id = public.current_employee_id());

drop policy if exists daily_report_views_delete on public.daily_report_views;
create policy daily_report_views_delete on public.daily_report_views
  for delete to authenticated
  using (employee_id = public.current_employee_id() or public.current_is_full_access());

-- ---------------------------------------------------------------------------
-- 2) record_daily_reports_views — تسجيل جماعي للمشاهدات عند فتح الصفحة
-- ---------------------------------------------------------------------------
create or replace function public.record_daily_reports_views(p_report_ids uuid[])
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_recorded integer;
begin
  if v_me is null then
    raise exception 'employee profile is not linked' using errcode = '42501';
  end if;

  if p_report_ids is null or cardinality(p_report_ids) = 0 then
    return jsonb_build_object('recorded', 0);
  end if;

  with inserted as (
    insert into public.daily_report_views (report_id, employee_id, created_by, view_count)
    select t.id, v_me, auth.uid(), 1
    from unnest(p_report_ids) t(id)
    join public.daily_reports dr on dr.id = t.id
    on conflict (report_id, employee_id)
    do update set
      view_count = public.daily_report_views.view_count + 1,
      last_viewed_at = now()
    returning 1
  )
  select count(*) into v_recorded from inserted;

  return jsonb_build_object('recorded', v_recorded);
end;
$$;
revoke all on function public.record_daily_reports_views(uuid[]) from public;
grant execute on function public.record_daily_reports_views(uuid[]) to authenticated;

comment on function public.record_daily_reports_views(uuid[]) is
  'يسجل مشاهدات التقارير اليومية الحالية دفعة واحدة (يتجاهل ids غير الموجودة).';

-- ---------------------------------------------------------------------------
-- 3) get_daily_report_engagement — قائمة كاملة بمن شاهد ومن تفاعل
-- ---------------------------------------------------------------------------
create or replace function public.get_daily_report_engagement(p_report_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  if not exists (select 1 from public.daily_reports where id = p_report_id) then
    raise exception 'daily report not found' using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'reportId', p_report_id,
    'viewersCount', (
      select count(*)::integer from public.daily_report_views v
      where v.report_id = p_report_id
    ),
    'likersCount', (
      select count(*)::integer from public.daily_report_likes l
      where l.report_id = p_report_id
    ),
    'viewers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'employeeId', e.id,
        'name', e.full_name_ar,
        'photoUrl', e.photo_url,
        'at', v.last_viewed_at,
        'viewCount', v.view_count
      ) order by v.last_viewed_at desc)
      from public.daily_report_views v
      join public.employees e on e.id = v.employee_id
      where v.report_id = p_report_id
    ), '[]'::jsonb),
    'likers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'employeeId', e.id,
        'name', e.full_name_ar,
        'photoUrl', e.photo_url,
        'at', l.created_at
      ) order by l.created_at desc)
      from public.daily_report_likes l
      join public.employees e on e.id = l.employee_id
      where l.report_id = p_report_id
    ), '[]'::jsonb)
  );
end;
$$;
revoke all on function public.get_daily_report_engagement(uuid) from public;
grant execute on function public.get_daily_report_engagement(uuid) to authenticated;

comment on function public.get_daily_report_engagement(uuid) is
  'قائمة المشاهدين والمعجبين لتقرير يومي — يراها كل الموظفين المسجلين.';

-- ---------------------------------------------------------------------------
-- 4) توسيع feed التقارير بحقول المشاهدات (أول 3 أسماء + العدادات)
-- ---------------------------------------------------------------------------
create or replace function public.get_public_daily_reports_feed(
  p_limit integer default 50,
  p_before date default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '42501';
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
      from public.daily_report_views v
      join public.employees ve on ve.id = v.employee_id
      where v.report_id = dr.id
      limit 3
    ), '[]'::jsonb),
    'likers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'employeeId', le.id,
        'name', le.full_name_ar,
        'photoUrl', le.photo_url,
        'at', l.created_at
      ) order by l.created_at desc)
      from public.daily_report_likes l
      join public.employees le on le.id = l.employee_id
      where l.report_id = dr.id
      limit 3
    ), '[]'::jsonb),
    'comments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id,
        'employeeId', c.employee_id,
        'employeeName', ce.full_name_ar,
        'comment', c.comment,
        'createdAt', c.created_at
      ) order by c.created_at asc)
      from public.daily_report_comments c
      join public.employees ce on ce.id = c.employee_id
      where c.report_id = dr.id
    ), '[]'::jsonb)
  ) order by dr.report_date desc, dr.created_at desc), '[]'::jsonb)
  into v_result
  from (
    select * from public.daily_reports
    where (p_before is null or report_date < p_before)
    order by report_date desc, created_at desc
    limit greatest(1, least(coalesce(p_limit, 50), 100))
  ) dr
  join public.employees e on e.id = dr.employee_id
  left join public.job_titles jt on jt.id = e.job_title_id
  left join public.departments d on d.id = e.department_id
  left join public.manager_relations mr on mr.employee_id = e.id
    and mr.relation_type = 'primary' and mr.effective_to is null
  left join public.employees mgr on mgr.id = mr.manager_employee_id
  left join public.employees rv on rv.id = dr.reviewed_by;

  return v_result;
end;
$$;
revoke all on function public.get_public_daily_reports_feed(integer, date) from public;
grant execute on function public.get_public_daily_reports_feed(integer, date) to authenticated;

comment on function public.get_public_daily_reports_feed(integer, date) is
  'صفحة التقارير اليومية العامة: يراها كل موظف مسجّل مع أسماء أول 3 مشاهدين
   ومعجبين وعددهم الكلي لكل تقرير.';

-- ---------------------------------------------------------------------------
-- 5) تخفيف حارس get_announcement_engagement — للجميع (طلب المستخدم)
-- ---------------------------------------------------------------------------
create or replace function public.get_announcement_engagement(p_announcement_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  if not exists (select 1 from public.announcements where id = p_announcement_id) then
    raise exception 'announcement not found' using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'announcementId', p_announcement_id,
    'targetCount', (
      select count(*)::integer
      from public.employees e
      join public.profiles p on p.employee_id = e.id and p.status = 'active'
      where e.is_active and e.status = 'active' and not e.is_deleted
    ),
    'viewerCount', (select count(*)::integer from public.announcement_views v where v.announcement_id = p_announcement_id),
    'reactionCount', (select count(*)::integer from public.announcement_reactions r where r.announcement_id = p_announcement_id),
    'acknowledgedCount', (select count(*)::integer from public.announcement_acknowledgements a where a.announcement_id = p_announcement_id),
    'viewers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'employeeId', e.id,
        'name', e.full_name_ar,
        'photoUrl', e.photo_url,
        'at', v.last_viewed_at,
        'viewCount', v.view_count
      ) order by v.last_viewed_at desc)
      from public.announcement_views v
      join public.employees e on e.id = v.employee_id
      where v.announcement_id = p_announcement_id
    ), '[]'::jsonb),
    'reactions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'employeeId', e.id,
        'name', e.full_name_ar,
        'photoUrl', e.photo_url,
        'at', r.updated_at,
        'reactionType', r.reaction_type
      ) order by r.updated_at desc)
      from public.announcement_reactions r
      join public.employees e on e.id = r.employee_id
      where r.announcement_id = p_announcement_id
    ), '[]'::jsonb),
    'acknowledgements', coalesce((
      select jsonb_agg(jsonb_build_object(
        'employeeId', e.id,
        'name', e.full_name_ar,
        'photoUrl', e.photo_url,
        'at', a.created_at
      ) order by a.created_at desc)
      from public.announcement_acknowledgements a
      join public.employees e on e.id = a.employee_id
      where a.announcement_id = p_announcement_id
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_announcement_engagement(uuid) from public, anon;
grant execute on function public.get_announcement_engagement(uuid) to authenticated;

comment on function public.get_announcement_engagement(uuid) is
  'قائمة المشاهدين والمتفاعلين مع إعلان — يراها كل الموظفين المسجلين.';

notify pgrst, 'reload schema';

commit;