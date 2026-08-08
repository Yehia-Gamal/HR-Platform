-- =====================================================================
-- 0318: F5 — التقارير اليومية صفحة عامة للجميع + إعجابات وتعليقات
-- ---------------------------------------------------------------------
-- المتطلبات (من المحادثة الرئيسية):
--   • صفحة تقارير يومية يراها كل الموظفين (وليس المدير المباشر فقط).
--   • لكل تقرير: اسم الموظف وصورته والمسمى الوظيفي ومديره.
--   • إعجاب (like) وتعليقات من الجميع.
--   • إشعار لصاحب التقرير عند الإعجاب أو التعليق.
--
-- التصميم:
--   • RLS على daily_reports يبقى مقيّداً (قراءة مُدارية) — لا نفتح الجدول.
--   • القراءة العامة عبر RPC أمني (security definer) يتحقق فقط من تسجيل
--     الدخول (auth.uid() is not null) → صفحة عامة دون كشف الجدول نفسه.
--   • جدولان جديدان: daily_report_likes / daily_report_comments مع RLS
--     خاص بهما (قراءة للجميع، كتابة للصاحب، حذف للصاحب أو full-access).
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1) daily_report_likes
-- ---------------------------------------------------------------------
create table if not exists public.daily_report_likes (
  id          uuid primary key default gen_random_uuid(),
  report_id   uuid not null references public.daily_reports(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  created_at  timestamptz not null default now(),
  constraint daily_report_likes_uq unique (report_id, employee_id)
);

comment on table public.daily_report_likes is
  'إعجابات التقارير اليومية (موظف واحد لكل تقرير عبر unique).';

create index if not exists ix_daily_report_likes_report on public.daily_report_likes(report_id);
create index if not exists ix_daily_report_likes_employee on public.daily_report_likes(employee_id);

alter table public.daily_report_likes enable row level security;

drop policy if exists daily_report_likes_select on public.daily_report_likes;
create policy daily_report_likes_select on public.daily_report_likes
  for select to authenticated
  using (true);

drop policy if exists daily_report_likes_insert on public.daily_report_likes;
create policy daily_report_likes_insert on public.daily_report_likes
  for insert to authenticated
  with check (employee_id = public.current_employee_id());

drop policy if exists daily_report_likes_delete on public.daily_report_likes;
create policy daily_report_likes_delete on public.daily_report_likes
  for delete to authenticated
  using (employee_id = public.current_employee_id() or public.current_is_full_access());

-- ---------------------------------------------------------------------
-- 2) daily_report_comments
-- ---------------------------------------------------------------------
create table if not exists public.daily_report_comments (
  id          uuid primary key default gen_random_uuid(),
  report_id   uuid not null references public.daily_reports(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  comment     text not null,
  created_at  timestamptz not null default now(),
  constraint daily_report_comments_len_chk check (length(trim(comment)) >= 1)
);

comment on table public.daily_report_comments is
  'تعليقات الموظفين على التقارير اليومية العامة.';

create index if not exists ix_daily_report_comments_report on public.daily_report_comments(report_id);
create index if not exists ix_daily_report_comments_employee on public.daily_report_comments(employee_id);

alter table public.daily_report_comments enable row level security;

drop policy if exists daily_report_comments_select on public.daily_report_comments;
create policy daily_report_comments_select on public.daily_report_comments
  for select to authenticated
  using (true);

drop policy if exists daily_report_comments_insert on public.daily_report_comments;
create policy daily_report_comments_insert on public.daily_report_comments
  for insert to authenticated
  with check (employee_id = public.current_employee_id());

drop policy if exists daily_report_comments_delete on public.daily_report_comments;
create policy daily_report_comments_delete on public.daily_report_comments
  for delete to authenticated
  using (employee_id = public.current_employee_id() or public.current_is_full_access());

-- ---------------------------------------------------------------------
-- 3) get_public_daily_reports_feed — صفحة عامة ببيانات الموظف والمسمى والمدير
-- ---------------------------------------------------------------------
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
  'صفحة التقارير اليومية العامة: كل موظف مسجّل يرى تقارير الجميع مع بيانات
   الموظف والمسمى الوظيفي ومديره وعدد الإعجابات والتعليقات.';

-- ---------------------------------------------------------------------
-- 4) toggle_daily_report_like — إعجاب/إلغاء + إشعار لصاحب التقرير
-- ---------------------------------------------------------------------
create or replace function public.toggle_daily_report_like(p_report_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_author uuid;
  v_liked boolean;
  v_count integer;
begin
  if v_me is null then
    raise exception 'employee profile is not linked' using errcode = '42501';
  end if;

  select employee_id into v_author
  from public.daily_reports
  where id = p_report_id;
  if not found then
    raise exception 'daily report not found' using errcode = 'P0002';
  end if;

  if exists (
    select 1 from public.daily_report_likes
    where report_id = p_report_id and employee_id = v_me
  ) then
    delete from public.daily_report_likes
    where report_id = p_report_id and employee_id = v_me;
    v_liked := false;
  else
    insert into public.daily_report_likes (report_id, employee_id)
    values (p_report_id, v_me);
    v_liked := true;

    -- إشعار صاحب التقرير (لا يشعر نفسه)
    if v_author is distinct from v_me then
      perform public.notify_employee(
        v_author,
        'أُعجب شخص بتقريرك اليومي',
        'أُعجب أحد زملائك بتقريرك اليومي.',
        'general', 'low', 'daily_reports', p_report_id,
        jsonb_build_object('event', 'daily_report_like')
      );
    end if;
  end if;

  select count(*) into v_count
  from public.daily_report_likes
  where report_id = p_report_id;

  return jsonb_build_object('liked', v_liked, 'count', v_count);
end;
$$;
revoke all on function public.toggle_daily_report_like(uuid) from public;
grant execute on function public.toggle_daily_report_like(uuid) to authenticated;

comment on function public.toggle_daily_report_like(uuid) is
  'يبدّل إعجاب الموظف الحالي بتقرير يومي ويُشعر صاحب التقرير عند الإعجاب.';

-- ---------------------------------------------------------------------
-- 5) add_daily_report_comment — تعليق + إشعار لصاحب التقرير
-- ---------------------------------------------------------------------
create or replace function public.add_daily_report_comment(
  p_report_id uuid,
  p_comment text
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_author uuid;
  v_id uuid;
begin
  if v_me is null then
    raise exception 'employee profile is not linked' using errcode = '42501';
  end if;
  if nullif(trim(coalesce(p_comment, '')), '') is null then
    raise exception 'comment is required' using errcode = '22023';
  end if;

  select employee_id into v_author
  from public.daily_reports
  where id = p_report_id;
  if not found then
    raise exception 'daily report not found' using errcode = 'P0002';
  end if;

  insert into public.daily_report_comments (report_id, employee_id, comment)
  values (p_report_id, v_me, trim(p_comment))
  returning id into v_id;

  if v_author is distinct from v_me then
    perform public.notify_employee(
      v_author,
      'تعليق جديد على تقريرك اليومي',
      trim(p_comment),
      'general', 'normal', 'daily_reports', p_report_id,
      jsonb_build_object('event', 'daily_report_comment', 'commentId', v_id)
    );
  end if;

  return v_id;
end;
$$;
revoke all on function public.add_daily_report_comment(uuid, text) from public;
grant execute on function public.add_daily_report_comment(uuid, text) to authenticated;

comment on function public.add_daily_report_comment(uuid, text) is
  'يضيف تعليق الموظف الحالي على تقرير يومي ويُشعر صاحب التقرير.';

-- ---------------------------------------------------------------------
-- 6) delete_daily_report_comment — حذف تعليق (صاحبه أو full-access)
-- ---------------------------------------------------------------------
create or replace function public.delete_daily_report_comment(p_comment_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_owner uuid;
begin
  if v_me is null then
    raise exception 'employee profile is not linked' using errcode = '42501';
  end if;

  select employee_id into v_owner
  from public.daily_report_comments
  where id = p_comment_id;
  if not found then
    raise exception 'comment not found' using errcode = 'P0002';
  end if;

  if v_owner is distinct from v_me and not public.current_is_full_access() then
    raise exception 'not authorized to delete this comment' using errcode = '42501';
  end if;

  delete from public.daily_report_comments where id = p_comment_id;
end;
$$;
revoke all on function public.delete_daily_report_comment(uuid) from public;
grant execute on function public.delete_daily_report_comment(uuid) to authenticated;

comment on function public.delete_daily_report_comment(uuid) is
  'يحذف تعليقاً على تقرير يومي (صاحب التعليق أو full-access).';

notify pgrst, 'reload schema';

commit;
