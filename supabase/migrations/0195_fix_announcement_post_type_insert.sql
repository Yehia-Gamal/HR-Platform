-- Migration 0194: إصلاح publish_official_announcement — post_type مفقود من INSERT
-- المشكلة (1): Migration 0185 أعادت إنشاء الدالة بـ 9 params لكن أزالت post_type
--   من عبارة INSERT — القيمة تُخزّن فقط في metadata JSONB، والعمود يأخذ الافتراضي 'announcement'.
-- المشكلة (2): CHECK constraint من 0165 لا يشمل 'standard' — الدالة تقبل 'standard'
--   كقيمة لـ p_post_type لكن الـ constraint يرفضها.
-- الحل: توسيع CHECK + إضافة post_type للـ INSERT.

begin;

-- ═══════════════════════════════════════════════════════════════════════
-- 1. توسيع CHECK constraint ليشمل 'standard'
-- ═══════════════════════════════════════════════════════════════════════

alter table public.announcements
  drop constraint if exists announcements_post_type_check;

-- الاسم الآلي الذي يُنشئه PostgreSQL عند ADD COLUMN ... CHECK(...)
alter table public.announcements
  drop constraint if exists announcements_post_type_check1;

alter table public.announcements
  add constraint announcements_post_type_check
    check (post_type in (
      'announcement', 'alert', 'poll', 'meeting',
      'holiday_notice', 'kpi_notice', 'attendance_notice',
      'standard'
    ));

-- ═══════════════════════════════════════════════════════════════════════
-- 2. إعادة إنشاء publish_official_announcement مع post_type في INSERT
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
    requires_acknowledgement, banner_url, post_type, published_at, expires_at,
    metadata, created_by
  )
  values (
    trim(p_title), trim(p_body), p_category, p_priority, 'published', 'all',
    coalesce(p_requires_acknowledgement, false),
    nullif(trim(coalesce(p_banner_url, '')), ''),
    coalesce(p_post_type, 'standard'),
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
      'postType', v_row.post_type,
      'hasBanner', v_row.banner_url is not null,
      'hasPoll', p_post_type = 'poll'
    )
  );

  return v_row;
end;
$$;

comment on function public.publish_official_announcement(text,text,text,text,boolean,text,text,jsonb,timestamptz) is
  'نشر إعلان رسمي — يدعم standard|poll|announcement مع post_type في العمود + metadata.';

commit;
