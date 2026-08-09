-- =====================================================================
-- 0342: محاذاة deep link في request_live_location مع العقد المُلزَم
-- ---------------------------------------------------------------------
-- الخلفية: التطبيع trigger trg_normalize_live_location_notification
-- (أنشئ في 0096، أُعيد تعريفه في 0309) يطلق BEFORE INSERT OR UPDATE
-- على notifications ويكتب بصورة صلبة:
--   v_deep_link := 'https://ahla-shabab-management-os.vercel.app/action/live_location_request/' || v_request_id;
-- فوق action_url و metadata.deepLink — متجاهلاً ما يكتبه المنتِج.
--
-- لكن request_live_location كتبت ahlashabab:// (المخطط الأصلي) في 0128
-- و0150 و0286 و0310 و0338 — خمسة migrations متتالية — مما يجعل
-- الرابط الأصلي **رمزاً ميتاً** يُطغى عليه فوراً قبل INSERT.
--
-- عقد الاختبار 0044 (release_0_11_1_deep_audit_contract) يُلزِم بأن
-- HTTPS App Link هو المسار الأساسي ("verified HTTPS App Link is the
-- primary notification route"). assetlinks.json منشور على Vercel
-- والـ AndroidManifest يسجّل intent-filter بـ autoVerify=true للـ https.
--
-- الإصلاح: محاذاة request_live_location لتكتب HTTPS App Link نفسه
-- الذي يطبّعه الـ trigger — فيتطابق المنتِج مع المسار المُلزَم،
-- ويُزال الرمز الميت. لا تغيير سلوكي (الإشعارات تستلم HTTPS فعلاً
-- عبر الـ trigger)، لكن يُزال خطر كامن: لو حُذف الـ trigger مستقبلاً
-- لكان المنتِج يكتب فجأة ahlashabab:// بدل HTTPS.
--
-- Idempotent: CREATE OR REPLACE فقط.
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
  v_deep_link text;
begin
  if v_me is null then raise exception 'requester has no employee profile' using errcode='42501'; end if;
  if not (public.current_is_full_access() or public.current_has_active_role(array['executive', 'executive-director'])) then
    raise exception 'only executive director may request employee location' using errcode='42501';
  end if;
  if p_employee_id = v_me then raise exception 'cannot request own location' using errcode='22023'; end if;

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

  -- 0342: استخدم HTTPS App Link (المسار المُلزَم في 0096/0309/0044)
  -- لا ahlashabab:// الذي كان رمزاً ميتاً يُطغى عليه فوراً قبل INSERT.
  v_deep_link := 'https://ahla-shabab-management-os.vercel.app/action/live_location_request/' || v_req.id::text;

  select user_id into v_target_user from public.employees where id = p_employee_id;
  if v_target_user is not null then
    insert into public.notifications(
      recipient_user_id, recipient_employee_id, title, body, category, priority,
      action_url, entity_type, entity_id, metadata, created_by)
    values(
      v_target_user, p_employee_id, 'طلب تحديد موقع فوري',
      'السكرتير التنفيذي أو المدير التنفيذي يطلب موقعك الآن. يرجى الاستجابة.',
      'system', 'urgent',
      v_deep_link,
      'live_location_request', v_req.id, jsonb_build_object(
        'fullScreen', true, 'kind', 'live_location_request', 'requestId', v_req.id,
        'entityId', v_req.id, 'channel', 'urgent_location_v6',
        'deepLink', v_deep_link),
      auth.uid());
  end if;

  perform public.log_audit_event(
    'live_location.requested', 'security', 'info',
    'live_location_requests', v_req.id, 'تم طلب الموقع اللحظي', null,
    jsonb_build_object('mode', 'snapshot', 'employeeId', p_employee_id, 'requestId', v_req.id));
  return v_req;
end $$;

revoke execute on function public.request_live_location(uuid, text, text) from public, anon;
grant execute on function public.request_live_location(uuid, text, text) to authenticated;
