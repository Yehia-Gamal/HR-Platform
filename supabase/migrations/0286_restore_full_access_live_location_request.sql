-- =====================================================================
-- 0286: إعادة السماح للمسؤول full-access بطلب موقع موظف.
-- =====================================================================
-- خلفية: 0280 أزال 'channel' المرمّز من request_live_location، لكنه أعاد
-- كتابة الدالة كاملة وأسقط الشرط current_is_full_access() الذي أضافته
-- 0150 (إصلاح علة 0128). النتيجة: مسؤول Main Admin (full-access) لا يستطيع
-- طلب موقع موظف — 42501 — رغم أن 0150/0269 كانا يسمحان له.
-- هذا الإصلاح يعيد الحارس الأصلي مع إبقاء كل تغييرات 0280 الأخرى.
-- idempotent: CREATE OR REPLACE فقط.
-- =====================================================================

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
  -- FIX: المسؤول full-access (admin) يُسمح له بطلب الموقع كما في 0150.
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
  -- ملاحظة: حقل channel/sound/ybni يُملأ بواسطة trigger
  -- normalize_live_location_notification (0276).
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
        'entityId', v_req.id, 'deepLink', 'ahlashabab://action/live_location_request/'||v_req.id::text),
      auth.uid());
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
