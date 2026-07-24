-- =====================================================================
-- 0128: إصلاح request_live_location على staging.
-- =====================================================================
-- خلفية: طُبّق 0124 على staging بنسخة مكسورة (أعمدة غير موجودة
--   target_employee_id/requester_employee_id/mode، overload رباعي ملتبس،
--   وفقدان cooldown/fullScreen/deep-link). لأن 0124 مُسجّل "مُطبّقاً" على
--   remote فلن يُعاد تشغيله بـ db push — لذا هذا الإصلاح المستقل يعيد كتابة
--   الدالة بالنسخة الصحيحة (المطابقة لعقد 0041 وتطبيق الموبايل).
-- idempotent: CREATE OR REPLACE + REVOKE/GRANT صريحة.
-- =====================================================================

drop function if exists public.request_live_location(uuid, text, text, integer);
drop function if exists public.request_live_location(uuid, text, integer);
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
  if not (public.current_is_full_access() or public.can_access_employee(p_employee_id,'live_location.request')) then
    raise exception 'target outside permitted scope' using errcode='42501';
  end if;
  if p_employee_id = v_me then raise exception 'cannot request own location' using errcode='22023'; end if;

  -- V12 §9: أوضاع الفيديو ملغاة نهائيًا — snapshot و track_* فقط.
  if p_mode in ('video_5s', 'location_video') then
    raise exception 'VIDEO_MODE_DISABLED: وضع الفيديو ملغى نهائيًا بسياسة V12 §9. استخدم snapshot أو track_*.'
      using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.employees where id = p_employee_id
      and status in ('active','invited','onboarding') and user_id is not null
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

  -- حساب المدة حسب الوضع (أوضاع الفيديو مرفوضة أعلاه).
  v_duration := case p_mode
    when 'snapshot' then 1
    when 'track_5' then 5 when 'track_10' then 10
    when 'track_15' then 15 when 'track_30' then 30
    else null end;
  if v_duration is null then raise exception 'invalid request mode' using errcode='22023'; end if;

  insert into public.live_location_requests(
    employee_id, requested_by, reason, status, purpose,
    requested_at, expires_at, duration_minutes, metadata, created_by)
  values(
    p_employee_id, v_me, coalesce(nullif(trim(p_reason),''), null),
    'pending', 'verification',
    now(), now() + interval '5 minutes', v_duration,
    jsonb_build_object(
      'mode', p_mode, 'videoSeconds', 0,
      'needsPoint', true, 'needsVideo', false,
      'isTracking', p_mode like 'track_%', 'videoRemoved', true),
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
    jsonb_build_object('mode', p_mode, 'employeeId', p_employee_id, 'requestId', v_req.id));
  perform public.nudge_notification_dispatcher();
  return v_req;
end $$;

-- إعادة الصلاحيات: authenticated فقط (لا public/anon).
revoke execute on function public.request_live_location(uuid, text, text) from public, anon;
grant execute on function public.request_live_location(uuid, text, text) to authenticated;
