-- =====================================================================
-- 0120: إزالة الفيديو من نظام الموقع الحي (V12 §9/15/16)
-- =====================================================================
-- القرار النهائي الملزم (V12 §9): "تم إلغاء ميزة تسجيل وإرسال الفيديو نهائيًا".
-- المبدأ:
--   * لا تُفتح الكاميرا ولا تُطلب صلاحيتها في رحلة طلب الموقع.
--   * تُزال أوضاع video_5s و location_video من إنشاء الطلب.
--   * تبقى الأوضاع: snapshot (موقع لحظي) و track_* (تتبع مستمر).
--   * لا تُحذف الجداول/الأعمدة التاريخية — تُوقف الكتابة إليها فقط.
--   * تُجعل أعمدة الفيديو nullable وتُزال شروط video_required.
-- =====================================================================

-- 1) إعادة كتابة request_live_location لرفض أوضاع الفيديو.
--    الأوضاع المسموحة: snapshot, track_5, track_10, track_15, track_30.
create or replace function public.request_live_location(
  p_employee_id uuid,
  p_reason text,
  p_mode text default 'snapshot',
  p_duration_minutes integer default null
)
returns public.live_location_requests
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_req public.live_location_requests;
  v_duration integer;
begin
  if v_me is null then raise exception 'NO_EMPLOYEE' using errcode='42501'; end if;
  if p_employee_id = v_me then raise exception 'CANNOT_REQUEST_OWN_LOCATION' using errcode='42501'; end if;

  -- V12 §9: أوضاع الفيديو ملغاة نهائيًا.
  if p_mode in ('video_5s', 'location_video') then
    raise exception 'VIDEO_MODE_DISABLED: وضع الفيديو ملغى نهائيًا بسياسة V12 §9. استخدم snapshot أو track_*.'
      using errcode = '22023';
  end if;

  -- التحقق من الصلاحية (الأصلي).
  if not (
    public.current_is_full_access()
    or public.has_any_permission(array[
      'live_location.request','live_location.request_group'])
    or public.can_access_employee(p_employee_id)
  ) then
    raise exception 'NOT_AUTHORIZED_FOR_EMPLOYEE' using errcode='42501';
  end if;

  -- حساب المدة حسب الوضع.
  v_duration := case
    when p_mode = 'snapshot' then 2
    when p_mode like 'track_%' then coalesce(p_duration_minutes, replace(p_mode,'track_','')::integer)
    else coalesce(p_duration_minutes, 5)
  end;

  -- إلغاء أي طلب نشط سابق لنفس الموظف (V10: auto-cancel).
  update public.live_location_requests
    set status = 'cancelled', updated_at = now()
    where target_employee_id = p_employee_id
      and status in ('pending', 'active')
      and requester_employee_id = v_me;

  insert into public.live_location_requests(
    requester_employee_id, target_employee_id, reason, mode,
    duration_minutes, status, expires_at, metadata, created_by)
  values(
    v_me, p_employee_id, trim(p_reason), p_mode,
    v_duration, 'pending',
    now() + make_interval(mins => v_duration + 5),
    jsonb_build_object(
      'needsVideo', false,
      'needsPoint', p_mode = 'snapshot',
      'isTracking', p_mode like 'track_%',
      'videoRemoved', true),
    auth.uid())
  returning * into v_req;

  -- إشعار الموظف المستهدف.
  perform public.notify_employee(
    p_employee_id, 'طلب موقع حي',
    'تم طلب موقعك الحالي — أرسل موقعك فقط.',
    'system', 'urgent', 'live_location_requests', v_req.id,
    jsonb_build_object('mode', p_mode, 'needsVideo', false));

  perform public.log_audit_event(
    'location.requested', 'workflow', 'info',
    'live_location_requests', v_req.id,
    'طلب موقع حي (بدون فيديو — V12)',
    trim(p_reason),
    jsonb_build_object('targetEmployeeId', p_employee_id, 'mode', p_mode,
                       'duration', v_duration, 'videoRemoved', true));
  return v_req;
end $$;

-- 2) إعادة كتابة complete_live_location_response لعدم اشتراط فيديو.
--    تقبل الموقع فقط وتُكمل الطلب بدون video_id.
create or replace function public.complete_live_location_response(
  p_request_id uuid,
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy numeric,
  p_address text default null,
  p_captured_at timestamptz default now()
)
returns public.live_location_requests
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_req public.live_location_requests;
begin
  select * into v_req from public.live_location_requests
  where id = p_request_id for update;

  if not found then raise exception 'REQUEST_NOT_FOUND' using errcode='P0002'; end if;
  if v_req.target_employee_id <> v_me then
    raise exception 'NOT_TARGET_EMPLOYEE' using errcode='42501';
  end if;
  if v_req.status not in ('pending','active') then
    raise exception 'REQUEST_NOT_ACTIVE: %', v_req.status using errcode='22023';
  end if;
  if v_req.expires_at < now() then
    raise exception 'REQUEST_EXPIRED' using errcode='22023';
  end if;

  -- تسجيل نقطة الموقع.
  insert into public.live_location_points(
    request_id, latitude, longitude, accuracy, address,
    captured_at, created_by)
  values(
    p_request_id, p_latitude, p_longitude, p_accuracy,
    p_address, p_captured_at, auth.uid())
  on conflict do nothing;

  -- إكمال الطلب — V12: لا حاجة لفيديو.
  update public.live_location_requests
    set status = 'completed',
        responded_at = coalesce(responded_at, now()),
        completed_at = now(),
        updated_at = now()
    where id = p_request_id
  returning * into v_req;

  -- إشعار الطالب بوصول الموقع.
  perform public.notify_employee(
    v_req.requester_employee_id, 'وصل الموقع',
    'تم استقبال موقع الموظف المطلوب.',
    'system', 'normal', 'live_location_requests', v_req.id,
    jsonb_build_object('latitude', p_latitude, 'longitude', p_longitude,
                       'accuracy', p_accuracy));

  perform public.log_audit_event(
    'location.completed', 'workflow', 'info',
    'live_location_requests', v_req.id,
    'اكتمال طلب الموقع (بدون فيديو)',
    null,
    jsonb_build_object('latitude', p_latitude, 'longitude', p_longitude,
                       'accuracy', p_accuracy, 'address', p_address));
  return v_req;
end $$;

-- 3) تعطيل edge function الفيديو: RPCs البوابة ترفض.
--    الدالة الأصلية (0067) ترجع jsonb بمعامل p_video_id uuid — لا يمكن تغيير
--    نوع الإرجاع بـ CREATE OR REPLACE فنسقطها أولاً.
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

-- 4) إعدادات النظام: تسجيل إلغاء الفيديو رسميًا.
insert into public.system_settings (key, value, value_type, group_name, label_ar, description, is_editable)
values('live_location_video_enabled', 'false'::jsonb, 'boolean', 'live_location',
  'تفعيل الفيديو في طلب الموقع',
  'V12 §9: تم إلغاء الفيديو نهائيًا. لا تُفعّل هذا الإعداد.',
  false)
on conflict (key) do update set value = 'false'::jsonb, is_editable = false, updated_at = now();

-- =====================================================================
-- نهاية Migration 0120
-- =====================================================================
