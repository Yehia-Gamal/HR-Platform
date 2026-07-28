-- Migration 0182: إصلاح نشر المنشور الرسمي
-- يُصلح 3 أخطاء:
--   1. publish_official_announcement لا تقبل p_post_type → PostgREST 404
--   2. CHECK constraint على category لا يشمل القيم المرسلة من الواجهة
--   3. إضافة p_poll_options لحفظ خيارات التصويت في metadata
--
-- التغييرات:
--   - تحديث CHECK constraint على announcements.category
--   - إعادة إنشاء publish_official_announcement مع p_post_type + p_poll_options

begin;

-- ═══════════════════════════════════════════════════════════════════════
-- 1. توسيع CHECK constraint على category ليشمل القيم المستخدمة بالواجهة
-- ═══════════════════════════════════════════════════════════════════════
-- القيم القديمة: general, event, urgent, policy, celebration, maintenance
-- القيم الجديدة: + hr, organizational, financial, disciplinary

alter table public.announcements
  drop constraint if exists announcements_category_check;

alter table public.announcements
  add constraint announcements_category_check
    check (category in (
      'general', 'event', 'urgent', 'policy', 'celebration', 'maintenance',
      'hr', 'organizational', 'financial', 'disciplinary'
    ));

-- ═══════════════════════════════════════════════════════════════════════
-- 2. إعادة إنشاء publish_official_announcement مع دعم التصويت
-- ═══════════════════════════════════════════════════════════════════════

create or replace function public.publish_official_announcement(
  p_title text,
  p_body text,
  p_category text default 'general',
  p_priority text default 'normal',
  p_requires_acknowledgement boolean default false,
  p_banner_url text default null,
  p_post_type text default 'standard',
  p_poll_options jsonb default null,
  p_expires_at timestamptz default null
)
returns public.announcements
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row public.announcements;
  v_metadata jsonb;
begin
  -- التحقق من الصلاحية
  if not (public.current_is_full_access()
          or public.has_permission('comms.announcement.manage')
          or public.has_permission('posts.publish')) then
    raise exception 'not authorized to publish announcements' using errcode = '42501';
  end if;

  -- التحقق من طول العنوان والمحتوى
  if length(trim(p_title)) < 3 or length(trim(p_body)) < 10 then
    raise exception 'title or body is too short' using errcode = '22023';
  end if;

  -- التحقق من نوع المنشور
  if p_post_type not in ('standard', 'poll', 'announcement') then
    raise exception 'invalid post type: %', p_post_type using errcode = '22023';
  end if;

  -- بناء metadata
  v_metadata := jsonb_build_object('postType', p_post_type);
  if p_post_type = 'poll' and p_poll_options is not null then
    v_metadata := v_metadata || jsonb_build_object('pollOptions', p_poll_options);
  end if;

  insert into public.announcements(
    title, body, category, priority, status, target_type,
    requires_acknowledgement, banner_url, published_at, expires_at,
    metadata, created_by
  )
  values (
    trim(p_title), trim(p_body), p_category, p_priority, 'published', 'all',
    coalesce(p_requires_acknowledgement, false),
    nullif(trim(coalesce(p_banner_url, '')), ''),
    now(),
    p_expires_at,
    v_metadata,
    auth.uid()
  )
  returning * into v_row;

  perform public.log_audit_event(
    'announcement.published', 'workflow', 'info', 'announcements', v_row.id,
    'نشر إعلان رسمي', null,
    jsonb_build_object(
      'title', v_row.title,
      'priority', v_row.priority,
      'postType', p_post_type,
      'hasBanner', v_row.banner_url is not null,
      'hasPoll', p_post_type = 'poll'
    )
  );

  return v_row;
end;
$$;

-- إلغاء الصلاحيات القديمة (6 params) وإعادة منحها للجديدة (9 params)
revoke execute on function public.publish_official_announcement(text,text,text,text,boolean,text,text,jsonb,timestamptz) from public;
grant execute on function public.publish_official_announcement(text,text,text,text,boolean,text,text,jsonb,timestamptz) to authenticated;

comment on function public.publish_official_announcement(text,text,text,text,boolean,text,text,jsonb,timestamptz) is
  'نشر إعلان رسمي مع دعم التصويت — p_post_type: standard|poll|announcement, p_poll_options: jsonb array of strings';

commit;
