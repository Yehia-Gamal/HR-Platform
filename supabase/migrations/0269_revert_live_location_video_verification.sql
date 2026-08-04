-- =====================================================================
-- 0269: إلغاء إعادة تفعيل فيديو التحقق في الموقع الحي (عكس 0265).
-- =====================================================================
-- القرار: V12 §9 "إلغاء الفيديو نهائيًا" يبقى نافذًا.
-- 0265 أعاد أوضاع video_5s / location_video + auto-cancel + منح الطلب لأي
-- حامل permission live_location.request. يعيد هذا migration العقد إلى V17 (0150):
--   * snapshot فقط — أوضاع الفيديو والتتبع مرفوضة بـ 22023 (0040-4/5/10).
--   * لا auto-cancel للطلبات السابقة (0041-6).
--   * الطلب للمدير التنفيذي / executive-director وأدوار full-access فقط (0040-13).
--   * metadata: needsPoint=true, needsVideo=false, videoRemoved=true (0040-3).
--   * تسجيل الفيديو معطّل (التوقيع يبقى كما تفرضه 0005) والبوابة ترجع false.
--   * السجل التاريخي (جداول الفيديو) يبقى كما هو — تُوقف الكتابة فقط.

begin;

-- 1) إعادة request_live_location إلى عقد V17 (نص 0150 حرفيًا).
create or replace function public.request_live_location(
  p_employee_id uuid,
  p_mode text default 'snapshot',
  p_reason text default ''
)
returns public.live_location_requests
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_req public.live_location_requests;
  v_duration integer;
  v_target_user uuid;
begin
  if v_me is null then raise exception 'requester has no employee profile' using errcode='42501'; end if;

  -- FIX: السماح لأدوار full-access (admin) بالإضافة للمدير التنفيذي.
  if not (public.current_is_full_access() or public.current_has_active_role(array['executive', 'executive-director'])) then
    raise exception 'only executive director may request employee location' using errcode='42501';
  end if;

  if p_employee_id = v_me then raise exception 'cannot request own location' using errcode='22023'; end if;

  -- V17: الطلب الجديد لقطة موقع فورية فقط. تبقى القيم القديمة للقراءة التاريخية.
  if coalesce(p_mode, '') <> 'snapshot' then
    raise exception 'LOCATION_MODE_DISABLED: V17 allows snapshot location requests only'
      using errcode='22023';
  end if;

  if not exists (
    select 1 from public.employees where id = p_employee_id
      and status = 'active' and is_active and not is_deleted and user_id is not null
  ) then
    raise exception 'employee is not active or has no linked user account' using errcode='P0002';
  end if;

  -- بوابة تهدئة 30 ثانية بين الطلبات لنفس الموظف من نفس الطالب.
  if exists (
    select 1 from public.live_location_requests
    where requested_by = v_me and employee_id = p_employee_id
      and requested_at > now() - interval '30 seconds'
  ) then
    raise exception 'cooldown_active: please wait 30 seconds between requests' using errcode='22023';
  end if;

  v_duration := 1;

  insert into public.live_location_requests(
    employee_id, requested_by, reason, status, purpose,
    requested_at, expires_at, duration_minutes, metadata, created_by)
  values(
    p_employee_id, v_me, coalesce(nullif(trim(p_reason),''), null),
    'pending', 'verification',
    now(), now() + interval '5 minutes', v_duration,
    jsonb_build_object(
      'mode', 'snapshot', 'videoSeconds', 0,
      'needsPoint', true, 'needsVideo', false,
      'isTracking', false, 'videoRemoved', true, 'policyVersion', 'V17'),
    auth.uid())
  returning * into v_req;

  update public.live_location_requests
    set metadata = metadata || jsonb_build_object('requestId', v_req.id)
    where id = v_req.id returning * into v_req;

  -- إشعار الموظف المستهدف (full-screen + deep-link — بدون فيديو).
  select user_id into v_target_user from public.employees where id = p_employee_id;
  if v_target_user is not null then
    insert into public.notifications(
      recipient_user_id, recipient_employee_id, title, body, category, priority,
      action_url, entity_type, entity_id, metadata, created_by)
    values(
      v_target_user, p_employee_id, 'طلب تحقق من الموقع',
      'المدير يطلب التحقق من موقعك. يرجى الاستجابة فوراً.', 'system', 'urgent',
      'ahlashabab://action/live_location_request/'||v_req.id::text,
      'live_location_request', v_req.id, jsonb_build_object(
        'fullScreen', true, 'kind', 'live_location_request', 'requestId', v_req.id,
        'entityId', v_req.id, 'deepLink', 'ahlashabab://action/live_location_request/'||v_req.id::text,
        'channel', 'urgent_location_v4'), auth.uid());
  end if;

  perform public.log_audit_event(
    'live_location.requested', 'security', 'warning',
    'live_location_requests', v_req.id, 'طلب موقع حي', null,
    jsonb_build_object('mode', 'snapshot', 'employeeId', p_employee_id, 'requestId', v_req.id));
  perform public.nudge_notification_dispatcher();
  return v_req;
end $$;

revoke execute on function public.request_live_location(uuid, text, text) from public, anon;
grant execute on function public.request_live_location(uuid, text, text) to authenticated;

-- 2) تعطيل تسجيل الفيديو: الدالة تبقى موجودة (التوقيع تفرضه 0005) لكنها ترفض التنفيذ.
create or replace function public.register_live_location_video(
  p_request_id uuid,
  p_storage_path text,
  p_duration_seconds integer,
  p_size_bytes bigint,
  p_mime_type text,
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy double precision
)
returns public.live_location_videos_meta
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  raise exception 'VIDEO_MODE_DISABLED: وضع الفيديو ملغى نهائيًا بسياسة V12 §9'
    using errcode = '22023';
end $$;

revoke execute on function public.register_live_location_video(uuid, text, integer, bigint, text, double precision, double precision, double precision) from public, anon;
grant execute on function public.register_live_location_video(uuid, text, integer, bigint, text, double precision, double precision, double precision) to authenticated;

-- 3) بوابة عرض الفيديو ترجع false دائمًا (V12).
drop function if exists public.can_view_live_location_video(uuid);
create or replace function public.can_view_live_location_video(
  p_request_id uuid
)
returns boolean
language plpgsql stable security definer set search_path = public, pg_temp
as $$
begin
  -- V12 §9: الفيديو ملغى نهائيًا — ترجع false دائمًا.
  return false;
end $$;

revoke execute on function public.can_view_live_location_video(uuid) from public, anon;
grant execute on function public.can_view_live_location_video(uuid) to authenticated;

-- 4) إزالة سياسة رفع الفيديو — لا يُكتب فيديو جديد بعد الآن.
drop policy if exists live_location_videos_owner_write on storage.objects;

-- 5) تسجيل الإلغاء رسميًا في إعدادات النظام.
insert into public.system_settings (key, value, value_type, group_name, label_ar, description, is_editable)
values('live_location_video_enabled', 'false'::jsonb, 'boolean', 'live_location',
  'تفعيل الفيديو في طلب الموقع',
  'V12 §9: تم إلغاء الفيديو نهائيًا. لا تُفعّل هذا الإعداد.',
  false)
on conflict (key) do update set value = 'false'::jsonb, is_editable = false, updated_at = now();

commit;
