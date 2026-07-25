-- Migration 0142: Announcement image storage + RPC updates for image support
-- V17 §18 — Post with text + optional image
--
-- 1. Create 'announcement-images' public storage bucket
-- 2. Storage RLS policies (public read, auth write for comms managers)
-- 3. Update publish_official_announcement to accept p_banner_url
-- 4. Update get_official_feed_admin to include imageUrl
-- 5. Update get_mobile_feed_item to include imageUrl at top level

begin;

-- ─────────────────────────────────────────────────────────
-- 1. Storage bucket for announcement banner images
-- ─────────────────────────────────────────────────────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'announcement-images',
  'announcement-images',
  true,
  5242880, -- 5 MiB
  array['image/jpeg','image/png','image/webp']
)
on conflict (id) do nothing;

-- ─────────────────────────────────────────────────────────
-- 2. Storage RLS policies
-- ─────────────────────────────────────────────────────────
drop policy if exists "announcement_images_public_read" on storage.objects;
create policy "announcement_images_public_read" on storage.objects
  for select using (bucket_id = 'announcement-images');

drop policy if exists "announcement_images_auth_write" on storage.objects;
create policy "announcement_images_auth_write" on storage.objects
  for insert with check (
    bucket_id = 'announcement-images'
    and auth.role() = 'authenticated'
    and (
      public.current_is_full_access()
      or public.has_permission('comms.announcement.manage')
      or public.has_permission('posts.publish')
    )
  );

drop policy if exists "announcement_images_auth_update" on storage.objects;
create policy "announcement_images_auth_update" on storage.objects
  for update using (
    bucket_id = 'announcement-images'
    and auth.role() = 'authenticated'
    and (
      public.current_is_full_access()
      or public.has_permission('comms.announcement.manage')
      or public.has_permission('posts.publish')
    )
  );

drop policy if exists "announcement_images_auth_delete" on storage.objects;
create policy "announcement_images_auth_delete" on storage.objects
  for delete using (
    bucket_id = 'announcement-images'
    and auth.role() = 'authenticated'
    and (
      public.current_is_full_access()
      or public.has_permission('comms.announcement.manage')
      or public.has_permission('posts.publish')
    )
  );

-- ─────────────────────────────────────────────────────────
-- 3. Update publish_official_announcement to accept banner_url
-- ─────────────────────────────────────────────────────────
create or replace function public.publish_official_announcement(
  p_title text,
  p_body text,
  p_category text default 'general',
  p_priority text default 'normal',
  p_requires_acknowledgement boolean default false,
  p_banner_url text default null
)
returns public.announcements
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_row public.announcements;
begin
  if not (public.current_is_full_access() or public.has_permission('comms.announcement.manage')
          or public.has_permission('posts.publish')) then
    raise exception 'not authorized to publish announcements' using errcode = '42501';
  end if;
  if length(trim(p_title)) < 3 or length(trim(p_body)) < 10 then
    raise exception 'title or body is too short' using errcode = '22023';
  end if;
  insert into public.announcements(title, body, category, priority, status, target_type,
    requires_acknowledgement, banner_url, published_at, created_by)
  values (trim(p_title), trim(p_body), p_category, p_priority, 'published', 'all',
    coalesce(p_requires_acknowledgement,false), nullif(trim(coalesce(p_banner_url,'')), ''),
    now(), auth.uid()) returning * into v_row;
  perform public.log_audit_event(
    'announcement.published','workflow','info','announcements',v_row.id,
    'نشر إعلان رسمي',null,jsonb_build_object('title',v_row.title,'priority',v_row.priority,'hasBanner', v_row.banner_url is not null)
  );
  return v_row;
end;
$$;
revoke execute on function public.publish_official_announcement(text,text,text,text,boolean,text) from public;
grant execute on function public.publish_official_announcement(text,text,text,text,boolean,text) to authenticated;

-- ─────────────────────────────────────────────────────────
-- 4. Update get_official_feed_admin to include imageUrl
-- ─────────────────────────────────────────────────────────
create or replace function public.get_official_feed_admin(p_limit integer default 100)
returns jsonb
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(item order by sort_at desc), '[]'::jsonb)
  from (
    select item, sort_at
    from (
    select jsonb_build_object(
      'id', a.id, 'kind', 'announcement', 'title', a.title, 'body', a.body,
      'category', a.category, 'priority', a.priority, 'status', a.status,
      'requiresAcknowledgement', a.requires_acknowledgement,
      'publishedAt', a.published_at, 'expiresAt', a.expires_at,
      'imageUrl', a.banner_url,
      'acknowledgedCount', (select count(*) from public.announcement_acknowledgements x where x.announcement_id = a.id),
      'targetCount', null,
      'myAcknowledged', exists(select 1 from public.announcement_acknowledgements x where x.announcement_id=a.id and x.employee_id=public.current_employee_id()),
      'createdAt', a.created_at
    ) as item, coalesce(a.published_at, a.created_at) as sort_at from public.announcements a
    union all
    select jsonb_build_object(
      'id', d.id, 'kind', 'decision', 'title', d.title, 'body', coalesce(d.body,''),
      'category', d.category, 'priority', coalesce(d.metadata->>'priority','high'), 'status', d.status,
      'requiresAcknowledgement', d.requires_read_receipt,
      'publishedAt', d.published_at, 'expiresAt', d.expiry_date,
      'imageUrl', d.attachment_url,
      'acknowledgedCount', (select count(*) from public.decision_reads x where x.decision_id = d.id and x.acknowledged = true),
      'targetCount', (select count(*) from public.decision_recipients x where x.decision_id = d.id),
      'myAcknowledged', exists(select 1 from public.decision_reads x where x.decision_id=d.id and x.employee_id=public.current_employee_id() and x.acknowledged=true),
      'createdAt', d.created_at
    ) as item, coalesce(d.published_at, d.created_at) as sort_at from public.administrative_decisions d
    ) unioned
    order by sort_at desc
    limit greatest(1, least(coalesce(p_limit,100),500))
  ) feed;
$$;
grant execute on function public.get_official_feed_admin(integer) to authenticated;

-- ─────────────────────────────────────────────────────────
-- 5. Update get_mobile_feed_item to include imageUrl top-level
-- ─────────────────────────────────────────────────────────
create or replace function public.get_mobile_feed_item(p_kind text, p_item_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $$
declare
  v_result jsonb;
begin
  if lower(p_kind) = 'announcement' then
    select jsonb_build_object(
      'id', a.id, 'kind', 'announcement', 'title', a.title, 'body', a.body,
      'category', a.category, 'priority', a.priority, 'status', a.status,
      'requiresAcknowledgement', a.requires_acknowledgement,
      'myAcknowledged', exists(select 1 from public.announcement_acknowledgements x where x.announcement_id=a.id and x.employee_id=public.current_employee_id()),
      'publishedAt', a.published_at, 'expiresAt', a.expires_at,
      'imageUrl', a.banner_url,
      'attachments', case when a.banner_url is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('url',a.banner_url,'type','banner')) end
    ) into v_result
    from public.announcements a where a.id=p_item_id and a.status='published';
  elsif lower(p_kind) = 'decision' then
    select jsonb_build_object(
      'id', d.id, 'kind', 'decision', 'title', d.title, 'body', coalesce(d.body,''),
      'category', d.category, 'priority', coalesce(d.metadata->>'priority','high'), 'status', d.status,
      'requiresAcknowledgement', d.requires_read_receipt,
      'myAcknowledged', exists(select 1 from public.decision_reads x where x.decision_id=d.id and x.employee_id=public.current_employee_id() and x.acknowledged=true),
      'publishedAt', d.published_at, 'expiresAt', d.expiry_date,
      'imageUrl', d.attachment_url,
      'decisionNumber', d.decision_number,
      'effectiveDate', d.effective_date,
      'attachments', case when d.attachment_url is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('url',d.attachment_url,'type','attachment')) end
    ) into v_result
    from public.administrative_decisions d where d.id=p_item_id and d.status='published';
  else
    raise exception 'unsupported feed item kind' using errcode='22023';
  end if;
  if v_result is null then raise exception 'feed item not found or not visible' using errcode='P0002'; end if;
  return v_result;
end;
$$;
grant execute on function public.get_mobile_feed_item(text,uuid) to authenticated;

commit;
