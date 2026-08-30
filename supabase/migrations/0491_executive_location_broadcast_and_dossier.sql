-- 0491: المتابعة الميدانية التنفيذية — تحسينات صفحة الموبايل للمدير التنفيذي
--  1) get_location_directory: إضافة photoUrl (إعادة بناء canonical كاملة).
--  2) request_live_location_broadcast: طلب موقع فوري من جميع الموظفين دفعة واحدة.
--  3) get_employee_location_dossier: ملف موقع موظف (آخر نقطة + نقاط + طلبات) لصفحة ملف الموظف.

-- ═══════════════════════════════════════════════════════════════════════
-- 1) get_location_directory — إضافة الصورة الشخصية (photoUrl)
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.get_location_directory(
  p_search text    default null,
  p_limit  integer default 100
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_search text;
BEGIN
  IF NOT (public.current_is_full_access() OR public.has_permission('live_location.request')) THEN
    RAISE EXCEPTION 'live location request permission required' USING errcode = '42501';
  END IF;

  v_search := nullif(trim(coalesce(p_search, '')), '');

  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'id',                  q.id,
      'name',                q.full_name_ar,
      'employeeCode',        q.employee_code,
      'jobTitle',            q.job_title,
      'department',          q.department,
      'photoUrl',            q.photo_url,           -- 0491: صورة الموظف في دليل الموقع
      'lastLatitude',        q.latitude,
      'lastLongitude',       q.longitude,
      'lastAccuracy',        q.accuracy,
      'lastRecordedAt',      q.recorded_at,
      'activeRequestId',     q.active_request_id,
      'activeRequestStatus', q.active_request_status
    ) ORDER BY q.full_name_ar)
    FROM (
      SELECT
        e.id, e.full_name_ar, e.employee_code, e.photo_url,
        jt.name  job_title,
        d.name   department,
        last_point.latitude, last_point.longitude,
        last_point.accuracy, last_point.recorded_at,
        active_req.id     active_request_id,
        active_req.status active_request_status
      FROM public.employees e
      LEFT JOIN public.job_titles  jt  ON jt.id = e.job_title_id
      LEFT JOIN public.departments d   ON d.id  = e.department_id
      LEFT JOIN LATERAL (
        SELECT l.latitude, l.longitude, l.accuracy, l.recorded_at
        FROM public.employee_locations l
        WHERE l.employee_id = e.id
        ORDER BY l.recorded_at DESC LIMIT 1
      ) last_point ON TRUE
      LEFT JOIN LATERAL (
        SELECT r.id, r.status
        FROM public.live_location_requests r
        WHERE r.employee_id = e.id
          AND r.status IN ('pending','accepted','active')
          AND (r.expires_at IS NULL OR r.expires_at > now())
        ORDER BY r.requested_at DESC LIMIT 1
      ) active_req ON TRUE
      WHERE e.status IN ('active', 'invited', 'onboarding')
        AND e.is_deleted = false
        AND e.id IS DISTINCT FROM public.current_employee_id()
        AND e.user_id IS NOT NULL
        AND NOT public.is_employee_executive(e.id)  -- استبعاد المدير التنفيذي
        AND (
          public.current_is_full_access()
          OR public.can_access_employee(e.id, 'live_location.request')
        )
        AND (
          v_search IS NULL
          OR e.full_name_ar  ILIKE '%' || public.escape_ilike(v_search) || '%'
          OR e.employee_code ILIKE '%' || public.escape_ilike(v_search) || '%'
        )
      ORDER BY e.full_name_ar
      LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 100), 300))
    ) q
  ), '[]'::jsonb);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_location_directory(text, integer) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.get_location_directory(text, integer) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- 2) request_live_location_broadcast — طلب موقع فوري من كل الفريق دفعة واحدة
-- يعتمد منطق الطلب الفردي (request_live_location) نفسه: يُنشئ طلب snapshot
-- لكل موظف نشط داخل نطاق الصلاحية وليس لديه طلب سارٍ، مع إشعار عاجل لكل مستهدف.
-- ═══════════════════════════════════════════════════════════════════════
create or replace function public.request_live_location_broadcast(
  p_mode   text default 'snapshot',
  p_reason text default 'تحقق ميداني جماعي'
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me            uuid := public.current_employee_id();
  v_duration      integer;
  v_video_seconds integer := 0;
  v_needs_point   boolean := true;
  v_needs_video   boolean := false;
  v_target        public.employees;
  v_row           public.live_location_requests;
  v_created       integer := 0;
  v_items         jsonb := '[]'::jsonb;
begin
  if v_me is null then raise exception 'requester has no employee profile' using errcode='42501'; end if;
  if not (public.current_is_full_access() or public.has_permission('live_location.request')) then
    raise exception 'live location request permission required' using errcode='42501';
  end if;
  if length(trim(coalesce(p_reason,'')))<5 then raise exception 'reason is required' using errcode='22023'; end if;

  v_duration := case p_mode
    when 'snapshot'       then 1
    when 'video_5s'       then 2
    when 'location_video' then 2      -- الوضع المدمج للمدير التنفيذي: نقطة + فيديو 5 ثوانٍ
    when 'track_5'        then 5
    when 'track_10'       then 10
    when 'track_15'       then 15
    when 'track_30'       then 30
    else null end;
  if v_duration is null then raise exception 'invalid request mode' using errcode='22023'; end if;

  if p_mode = 'video_5s' then
    v_video_seconds := 5; v_needs_point := false; v_needs_video := true;
  elsif p_mode = 'location_video' then
    v_video_seconds := 5; v_needs_point := true;  v_needs_video := true;
  end if;

  for v_target in
    select e.*
    from public.employees e
    where e.status = 'active'
      and e.is_deleted = false
      and e.id <> v_me
      and e.user_id is not null
      and not public.is_employee_executive(e.id)
      and not exists (
        select 1 from public.live_location_requests r
        where r.employee_id = e.id
          and r.status in ('pending','accepted','active')
          and (r.expires_at is null or r.expires_at > now())
      )
      and (
        public.current_is_full_access()
        or public.can_access_employee(e.id, 'live_location.request')
      )
    order by e.full_name_ar
    limit 200
  loop
    -- تجاهل غير النشطين لحظة الإرسال (نافذة ضيقة بين الفلتر والدورة).
    if not exists (select 1 from public.employees where id=v_target.id and status='active') then
      continue;
    end if;

    insert into public.live_location_requests(employee_id,requested_by,reason,status,purpose,requested_at,expires_at,duration_minutes,metadata,created_by)
    values(
      v_target.id,v_me,trim(p_reason),'pending','verification',now(),now()+interval '5 minutes',v_duration,
      jsonb_build_object(
        'mode',p_mode,
        'videoSeconds',v_video_seconds,
        'needsPoint',v_needs_point,
        'needsVideo',v_needs_video,
        'broadcast',true
      ),
      auth.uid()
    ) returning * into v_row;

    v_created := v_created + 1;
    v_items := v_items || jsonb_build_object('employeeId', v_target.id, 'requestId', v_row.id);

    if v_target.user_id is not null then
      insert into public.notifications(recipient_user_id,recipient_employee_id,title,body,category,priority,action_url,entity_type,entity_id,metadata,created_by)
      values(
        v_target.user_id,v_target.id,
        'طلب موقع عاجل',
        'طلب موقع من '||coalesce((select full_name_ar from public.employees where id=v_me),'الإدارة')||' — السبب: '||trim(p_reason),
        'system','urgent','ahlashabab://action/live_location_request/'||v_row.id::text,
        'live_location_request',v_row.id,
        -- بيانات الإشعار العاجل: شاشة كاملة + قناة عالية الأولوية + Deep Link
        jsonb_build_object(
          'fullScreen', true,
          'kind', 'live_location_request',
          'entityId', v_row.id,
          'channel', 'urgent_location',
          'sound', 'urgent',
          'requiresVideo', v_needs_video,
          'deepLink', 'ahlashabab://action/live_location_request/'||v_row.id::text
        ),
        auth.uid()
      );
    end if;
  end loop;

  perform public.log_audit_event(
    'live_location.requested','security','warning','live_location_requests',null,
    'بث جماعي لطلب الموقع',null,
    jsonb_build_object('mode',p_mode,'created',v_created,'reason',trim(p_reason))
  );

  -- نبضة فورية لإرسال الإشعارات العاجلة دون انتظار كرون الدقيقتين (اختيارية وآمنة).
  perform public.nudge_notification_dispatcher();

  return jsonb_build_object(
    'created', v_created,
    'items', v_items
  );
end;
$$;

REVOKE EXECUTE ON FUNCTION public.request_live_location_broadcast(text, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.request_live_location_broadcast(text, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- 3) get_employee_location_dossier — ملف موقع موظف لصفحة المدير التنفيذي
-- يعرض آخر نقطة + آخر النقاط المسجّلة + سجلّ طلبات الموقع الخاصة بالموظف
-- بنقطة واحدة، ليُبنى منها ملف الموظف في الموبايل.
-- ═══════════════════════════════════════════════════════════════════════
create or replace function public.get_employee_location_dossier(
  p_employee_id uuid,
  p_points_limit   integer default 60,
  p_requests_limit integer default 30
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_emp public.employees;
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  if not (
    public.current_is_full_access()
    or public.has_permission('people.employee.read')
    or public.has_permission('live_location.request')
    or public.can_access_employee(p_employee_id)
  ) then
    raise exception 'ERR_FORBIDDEN' using errcode = '42501';
  end if;

  select * into v_emp from public.employees where id = p_employee_id;
  if not found then
    raise exception 'EMPLOYEE_NOT_FOUND' using errcode = 'P0002';
  end if;

  select jsonb_build_object(
    'employee', jsonb_build_object(
      'id', v_emp.id,
      'name', v_emp.full_name_ar,
      'employeeCode', v_emp.employee_code,
      'photoUrl', v_emp.photo_url,
      'jobTitle', (select name from public.job_titles where id = v_emp.job_title_id),
      'department', (select name from public.departments where id = v_emp.department_id),
      'status', v_emp.status
    ),
    'lastPoint', (
      select jsonb_build_object(
        'id', l.id,
        'latitude', l.latitude,
        'longitude', l.longitude,
        'accuracy', l.accuracy,
        'isMock', l.is_mock,
        'source', l.source,
        'addressAr', l.address_ar,
        'recordedAt', l.recorded_at
      )
      from public.employee_locations l
      where l.employee_id = p_employee_id
      order by l.recorded_at desc
      limit 1
    ),
    'points', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', l.id,
        'latitude', l.latitude,
        'longitude', l.longitude,
        'accuracy', l.accuracy,
        'altitude', l.altitude,
        'speed', l.speed,
        'heading', l.heading,
        'isMock', l.is_mock,
        'source', l.source,
        'batteryLevel', l.battery_level,
        'addressAr', l.address_ar,
        'recordedAt', l.recorded_at,
        'createdAt', l.created_at,
        'requestId', l.live_request_id,
        'requestMode', (
          select m.metadata->>'mode'
          from public.live_location_requests m
          where m.id = l.live_request_id
        )
      ) order by l.recorded_at desc)
      from (
        select *
        from public.employee_locations
        where employee_id = p_employee_id
        order by recorded_at desc
        limit greatest(1, least(coalesce(p_points_limit, 60), 200))
      ) l
    ), '[]'::jsonb),
    'requests', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', lr.id,
        'status', case
          when lr.status in ('pending','accepted','active') and lr.expires_at < now() then 'expired'
          else lr.status
        end,
        'mode', coalesce(lr.metadata->>'mode', 'snapshot'),
        'reason', lr.reason,
        'requestedByName', rb.full_name_ar,
        'requestedAt', lr.requested_at,
        'respondedAt', lr.responded_at,
        'startsAt', lr.starts_at,
        'expiresAt', lr.expires_at,
        'durationMinutes', lr.duration_minutes,
        'pointCount', (
          select count(*)
          from public.employee_locations lp
          where lp.live_request_id = lr.id
        )
      ) order by lr.requested_at desc)
      from (
        select *
        from public.live_location_requests
        where employee_id = p_employee_id
        order by requested_at desc
        limit greatest(1, least(coalesce(p_requests_limit, 30), 100))
      ) lr
      left join public.employees rb on rb.id = lr.requested_by
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

REVOKE EXECUTE ON FUNCTION public.get_employee_location_dossier(uuid, integer, integer) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.get_employee_location_dossier(uuid, integer, integer) TO authenticated;