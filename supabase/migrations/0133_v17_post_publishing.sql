-- 0133_v17_post_publishing.sql
-- V17 §18: نشر المنشورات الرسمية — 3 أدوار نشر (أدمن رئيسي/HR/تنفيذي)
-- يضيف صلاحية posts.publish ويمنحها للأدوار الثلاثة،
-- يضيف عمود publisher_channel على announcements،
-- يحدّث سياسات RLS لتقبل posts.publish بجانب comms.announcement.manage.

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. صلاحية نشر المنشورات
-- ═══════════════════════════════════════════════════════════════════════════════

insert into public.permissions(code, module, resource, action, description, risk_level, is_sensitive)
values
  ('posts.publish', 'communications', 'posts', 'publish',
   'نشر المنشورات الرسمية (إعلانات/قرارات)', 'normal', false)
on conflict(code) do update set
  description = excluded.description,
  risk_level  = excluded.risk_level,
  is_sensitive = excluded.is_sensitive;

-- منح لأدوار النشر الثلاثة:
--   main_admin   → executive-secretary (ويب)
--   hr_web       → hr-manager, hr-specialist (ويب)
--   executive_mobile → executive (موبايل)
insert into public.role_permissions(role_id, permission_id, scope, requires_reason)
select r.id, p.id, 'organization', false
from public.roles r
join public.permissions p on p.code = 'posts.publish'
where r.slug in ('executive-secretary', 'hr-manager', 'hr-specialist', 'executive')
on conflict(role_id, permission_id, scope) do nothing;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2. عمود قناة النشر على announcements
-- ═══════════════════════════════════════════════════════════════════════════════

alter table public.announcements
  add column if not exists publisher_channel text
    check(publisher_channel is null or publisher_channel in ('web','mobile'));

comment on column public.announcements.publisher_channel is
  'V17 §18: قناة النشر — web (أدمن رئيسي/HR) أو mobile (تنفيذي). NULL = لم يُحدَّد بعد.';

-- ═══════════════════════════════════════════════════════════════════════════════
-- 3. تحديث سياسات RLS — القراءة والكتابة
-- ═══════════════════════════════════════════════════════════════════════════════

-- القراءة: المنشور المنشور للجميع، أو المسودات لمن لديه صلاحية إدارة/نشر
drop policy if exists announcements_select on public.announcements;
create policy announcements_select on public.announcements
  for select to authenticated
  using (
    status = 'published'
    or public.current_is_full_access()
    or public.has_any_permission(array[
      'comms.announcement.read',
      'comms.announcement.manage',
      'posts.publish'
    ])
  );

-- الكتابة: من لديه manage أو publish أو full-access
drop policy if exists announcements_write on public.announcements;
create policy announcements_write on public.announcements
  for all to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array['comms.announcement.manage','posts.publish'])
  )
  with check (
    public.current_is_full_access()
    or public.has_any_permission(array['comms.announcement.manage','posts.publish'])
  );

-- تحديث سياسة إقرارات الإعلانات — القراءة تشمل posts.publish أيضاً
drop policy if exists ann_ack_select on public.announcement_acknowledgements;
create policy ann_ack_select on public.announcement_acknowledgements
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array['comms.announcement.manage','posts.publish'])
    or employee_id = public.current_employee_id()
  );

-- ═══════════════════════════════════════════════════════════════════════════════
-- 4. دالة مساعدة: نشر منشور رسمي
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.publish_announcement(
  p_announcement_id uuid,
  p_channel         text default null
)
returns public.announcements
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.announcements;
  v_channel text := coalesce(p_channel, 'web');
begin
  -- التحقق من الصلاحية
  if not (
    public.current_is_full_access()
    or public.has_permission('comms.announcement.manage')
    or public.has_permission('posts.publish')
  ) then
    raise exception 'ليس لديك صلاحية نشر المنشورات' using errcode = '42501';
  end if;

  if v_channel not in ('web','mobile') then
    raise exception 'قناة نشر غير صالحة: %', v_channel using errcode = '22023';
  end if;

  update public.announcements
    set status            = 'published',
        published_at      = now(),
        publisher_channel = v_channel,
        updated_at        = now()
  where id = p_announcement_id
    and status = 'draft'
  returning * into v_row;

  if not found then
    raise exception 'المنشور غير موجود أو ليس في حالة مسودة' using errcode = 'P0002';
  end if;

  return v_row;
end;
$$;

revoke execute on function public.publish_announcement(uuid, text) from public, anon;
grant  execute on function public.publish_announcement(uuid, text) to authenticated;

comment on function public.publish_announcement(uuid, text) is
  'V17 §18: نشر منشور رسمي — يحوّل المسودة إلى منشور مع تسجيل قناة النشر (web/mobile).';
