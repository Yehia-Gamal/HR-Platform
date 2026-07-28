-- Migration 0175: V23 Task-10 gap fixes
-- 1. Storage bucket for announcement banners/attachments
-- 2. Notification broadcast on publish_official_announcement
begin;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. Storage bucket — announcements
-- ═══════════════════════════════════════════════════════════════════════════════
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'announcements',
  'announcements',
  true,
  5242880, -- 5 MB
  array['image/jpeg','image/png','image/webp','image/gif']
)
on conflict (id) do nothing;

-- سياسة رفع: مستخدم مسجل فقط
create policy "auth_upload_announcements"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'announcements');

-- سياسة قراءة عامة (الباكت public)
create policy "public_read_announcements"
  on storage.objects for select
  to public
  using (bucket_id = 'announcements');

-- سياسة حذف: صاحب الملف فقط
create policy "owner_delete_announcements"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'announcements' and (storage.foldername(name))[1] = auth.uid()::text);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2. إعادة تعريف publish_official_announcement مع بث الإشعارات
-- ═══════════════════════════════════════════════════════════════════════════════
create or replace function public.publish_official_announcement(
  p_title text,
  p_body text,
  p_category text default 'general',
  p_priority text default 'normal',
  p_requires_acknowledgement boolean default false,
  p_banner_url text default null,
  p_post_type text default 'announcement'
)
returns public.announcements
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_row public.announcements;
  v_emp record;
  v_notif_title text;
begin
  -- صلاحيات
  if not (public.current_is_full_access()
          or public.has_permission('comms.announcement.manage')
          or public.has_permission('posts.publish')) then
    raise exception 'not authorized to publish announcements' using errcode = '42501';
  end if;

  -- تحقق من المدخلات
  if length(trim(p_title)) < 3 or length(trim(p_body)) < 10 then
    raise exception 'title or body is too short' using errcode = '22023';
  end if;

  -- إدراج الإعلان
  insert into public.announcements(title, body, category, priority, status, target_type,
    requires_acknowledgement, banner_url, post_type, published_at, created_by)
  values (trim(p_title), trim(p_body), p_category, p_priority, 'published', 'all',
    coalesce(p_requires_acknowledgement, false), nullif(trim(coalesce(p_banner_url,'')), ''),
    coalesce(p_post_type, 'announcement'),
    now(), auth.uid()) returning * into v_row;

  -- سجل التدقيق
  perform public.log_audit_event(
    'announcement.published','workflow','info','announcements',v_row.id,
    jsonb_build_object('title',v_row.title,'priority',v_row.priority,
      'postType',v_row.post_type,'hasBanner', v_row.banner_url is not null)
  );

  -- ═══ بث الإشعارات لجميع الموظفين النشطين ═══
  v_notif_title := case v_row.priority
    when 'urgent' then '🔴 ' || v_row.title
    when 'high'   then '🟠 ' || v_row.title
    else v_row.title
  end;

  for v_emp in
    select id from public.employees
    where status = 'active'
  loop
    begin
      perform public.notify_employee(
        v_emp.id,
        v_notif_title,
        left(v_row.body, 200),
        'announcement',
        v_row.priority,
        'announcements',
        v_row.id,
        jsonb_build_object('postType', v_row.post_type, 'category', v_row.category)
      );
    exception when others then
      -- لا نوقف النشر بسبب إشعار فاشل لموظف واحد
      null;
    end;
  end loop;

  return v_row;
end;
$fn$;

-- الصلاحيات (نفس التوقيع)
revoke execute on function public.publish_official_announcement(text,text,text,text,boolean,text,text) from public;
grant execute on function public.publish_official_announcement(text,text,text,text,boolean,text,text) to authenticated;

commit;
