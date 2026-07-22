-- =====================================================================
-- 0067: رحلة المدير التنفيذي — طلب الموقع الحي + فيديو التحقق (تكامل كامل)
-- =====================================================================
-- يبني على البنية القائمة (0011 الجداول، 0017 دورة حياة الـ RPC، 0037 الاحتفاظ
-- وسجل الوصول). لا ينشئ نظامًا موازيًا؛ يوسّع الدوال الحالية ويسدّ الفجوات:
--
--   1) وضع مدمج جديد 'location_video' = موقع دقيق + فيديو 5 ثوانٍ في طلب واحد.
--   2) إبقاء أوضاع snapshot/video_5s/track_* كما هي.
--   3) الموقع لا يُنهي الطلب في الوضع المدمج حتى يصل الفيديو أيضًا (والعكس).
--   4) حفظ العنوان العكسي (reverse geocode) مع نقطة الموقع.
--   5) دالة قراءة موحّدة للمدير التنفيذي: get_live_location_response.
--   6) بوابة صلاحية للفيديو تستخدمها دالة Edge لتوقيع رابط قصير: can_view_live_location_video.
--   7) لوحة المتابعة اليومية: get_executive_attendance_overview.
--   8) الحفظ الإداري بعد 24 ساعة: set_live_location_legal_hold (بوابة manage_retention/full-access).
--   9) إسقاط سياسات الكتابة القديمة (location.request.manage) — الكتابة عبر الـ RPC فقط.
--  10) بيانات إشعار عاجل (fullScreen) + نبضة pg_net فورية لإرسال الإشعار دون انتظار الكرون.
--
-- كل الدوال SECURITY DEFINER مع search_path=public,pg_temp، وتعيد التحقق من الصلاحية.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- (أ) دلتا المخطط: أعمدة العنوان العكسي + تريغر updated_at الناقص
-- ---------------------------------------------------------------------
alter table public.employee_locations
  add column if not exists address_ar    text,   -- العنوان التقريبي (reverse geocode)
  add column if not exists geocode_source text;   -- مصدر الترميز الجغرافي (nominatim/...)

comment on column public.employee_locations.address_ar is
  'العنوان التقريبي الناتج عن الترميز الجغرافي العكسي وقت تسجيل النقطة (قد يكون NULL عند ضعف الدقة).';

-- كان العمود updated_at موجودًا دون تريغر على employee_locations (فجوة مرصودة).
drop trigger if exists trg_emp_locations_updated_at on public.employee_locations;
create trigger trg_emp_locations_updated_at
before update on public.employee_locations
for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------
-- (ب) تنظيف سياسات RLS القديمة: لا مسار كتابة مباشر — الكتابة عبر RPC فقط
--     السياسات القديمة من 0011 كانت تعتمد 'location.request.manage'.
-- ---------------------------------------------------------------------
drop policy if exists live_loc_req_manage      on public.live_location_requests;
drop policy if exists live_loc_req_insert       on public.live_location_requests;
drop policy if exists live_loc_req_update       on public.live_location_requests;
drop policy if exists live_vid_meta_manage       on public.live_location_videos_meta;
drop policy if exists live_vid_meta_insert        on public.live_location_videos_meta;
drop policy if exists emp_locations_write          on public.employee_locations;
drop policy if exists emp_locations_insert_direct   on public.employee_locations;

-- ---------------------------------------------------------------------
-- (ج) توسعة request_live_location: وضع 'location_video' + بيانات إشعار عاجل
-- ---------------------------------------------------------------------
create or replace function public.request_live_location(p_employee_id uuid, p_mode text, p_reason text)
returns public.live_location_requests
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_me            uuid := public.current_employee_id();
  v_duration      integer;
  v_video_seconds integer := 0;
  v_needs_point   boolean := true;
  v_needs_video   boolean := false;
  v_row           public.live_location_requests;
  v_target_user   uuid;
begin
  if v_me is null then raise exception 'requester has no employee profile' using errcode='42501'; end if;
  if not public.can_access_employee(p_employee_id,'live_location.request') then raise exception 'target outside permitted scope' using errcode='42501'; end if;
  if p_employee_id=v_me then raise exception 'cannot request own location' using errcode='22023'; end if;
  if length(trim(coalesce(p_reason,'')))<5 then raise exception 'reason is required' using errcode='22023'; end if;
  if not exists(select 1 from public.employees where id=p_employee_id and status='active') then raise exception 'employee is not active' using errcode='P0002'; end if;

  -- خريطة الأوضاع → المدة بالدقائق + متطلبات النقطة/الفيديو
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

  if exists(select 1 from public.live_location_requests where employee_id=p_employee_id and status in ('pending','accepted','active') and (expires_at is null or expires_at>now())) then
    raise exception 'employee already has an active location request' using errcode='23505';
  end if;

  insert into public.live_location_requests(employee_id,requested_by,reason,status,purpose,requested_at,expires_at,duration_minutes,metadata,created_by)
  values(
    p_employee_id,v_me,trim(p_reason),'pending','verification',now(),now()+interval '5 minutes',v_duration,
    jsonb_build_object(
      'mode',p_mode,
      'videoSeconds',v_video_seconds,
      'needsPoint',v_needs_point,
      'needsVideo',v_needs_video
    ),
    auth.uid()
  ) returning * into v_row;

  select user_id into v_target_user from public.employees where id=p_employee_id;
  if v_target_user is not null then
    insert into public.notifications(recipient_user_id,recipient_employee_id,title,body,category,priority,action_url,entity_type,entity_id,metadata,created_by)
    values(
      v_target_user,p_employee_id,
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

  perform public.log_audit_event(
    'live_location.requested','security','warning','live_location_requests',v_row.id,
    'طلب موقع حي',null,
    jsonb_build_object('employeeId',p_employee_id,'mode',p_mode,'duration',v_duration,'needsVideo',v_needs_video,'reason',trim(p_reason))
  );

  -- نبضة فورية لإرسال الإشعار العاجل دون انتظار كرون الدقيقتين (اختيارية وآمنة).
  perform public.nudge_notification_dispatcher();

  return v_row;
end;
$$;
revoke execute on function public.request_live_location(uuid,text,text) from public;
grant execute on function public.request_live_location(uuid,text,text) to authenticated;

-- ---------------------------------------------------------------------
-- (د) submit_live_location_point: تخزين العنوان + عدم الإنهاء المبكر للوضع المدمج
--     نعيد تعريف الدالة بتوقيع واحد يضيف p_address_ar. نُسقط التوقيع القديم
--     (8 وسائط) لتجنّب غموض الحمل الزائد عند الاستدعاء بوسائط افتراضية.
-- ---------------------------------------------------------------------
drop function if exists public.submit_live_location_point(uuid,double precision,double precision,double precision,double precision,double precision,double precision,boolean);

create or replace function public.submit_live_location_point(
  p_request_id uuid,
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy double precision,
  p_altitude double precision default null,
  p_speed double precision default null,
  p_heading double precision default null,
  p_is_mock boolean default false,
  p_address_ar text default null
)
returns public.employee_locations
language plpgsql security definer set search_path=public,pg_temp
as $$
declare
  v_me       uuid := public.current_employee_id();
  v_req      public.live_location_requests;
  v_row      public.employee_locations;
  v_mode     text;
  v_needs_video boolean;
begin
  if p_latitude not between -90 and 90 or p_longitude not between -180 and 180 then raise exception 'invalid coordinates' using errcode='22023'; end if;
  if p_accuracy is null or p_accuracy<0 or p_accuracy>10000 then raise exception 'invalid accuracy' using errcode='22023'; end if;
  select * into v_req from public.live_location_requests where id=p_request_id for update;
  if not found or v_req.employee_id is distinct from v_me then raise exception 'request not found' using errcode='P0002'; end if;
  if v_req.status<>'active' or v_req.expires_at<=now() then raise exception 'location session is not active' using errcode='22023'; end if;

  insert into public.employee_locations(employee_id,live_request_id,latitude,longitude,accuracy,altitude,speed,heading,source,is_mock,address_ar,geocode_source,recorded_at,created_by)
  values(v_me,p_request_id,p_latitude,p_longitude,p_accuracy,p_altitude,p_speed,p_heading,'mobile',coalesce(p_is_mock,false),
    nullif(trim(coalesce(p_address_ar,'')),''),
    case when nullif(trim(coalesce(p_address_ar,'')),'') is not null then 'nominatim' else null end,
    now(),auth.uid())
  returning * into v_row;

  v_mode := coalesce(v_req.metadata->>'mode','snapshot');
  v_needs_video := coalesce((v_req.metadata->>'needsVideo')::boolean, v_mode='video_5s');

  -- الوضع اللحظي (snapshot) ينتهي بالنقطة. الأوضاع التي تتطلب فيديو تنتظره.
  if v_mode='snapshot' then
    update public.live_location_requests set status='completed',expires_at=now() where id=p_request_id;
  end if;
  return v_row;
end;
$$;
revoke execute on function public.submit_live_location_point(uuid,double precision,double precision,double precision,double precision,double precision,double precision,boolean,text) from public;
grant execute on function public.submit_live_location_point(uuid,double precision,double precision,double precision,double precision,double precision,double precision,boolean,text) to authenticated;

-- ---------------------------------------------------------------------
-- (هـ) register_live_location_video: قبول الوضع المدمج + إنهاء ذكي
-- ---------------------------------------------------------------------
create or replace function public.register_live_location_video(
  p_request_id uuid,p_storage_path text,p_duration_seconds integer,p_size_bytes bigint,
  p_mime_type text,p_latitude double precision,p_longitude double precision,p_accuracy double precision
)
returns public.live_location_videos_meta
language plpgsql security definer set search_path=public,pg_temp
as $$
declare
  v_me   uuid := public.current_employee_id();
  v_req  public.live_location_requests;
  v_row  public.live_location_videos_meta;
  v_mode text;
  v_needs_point boolean;
  v_has_point   boolean;
begin
  select * into v_req from public.live_location_requests where id=p_request_id for update;
  if not found or v_req.employee_id is distinct from v_me then raise exception 'request not found' using errcode='P0002'; end if;
  v_mode := coalesce(v_req.metadata->>'mode','snapshot');
  if v_req.status<>'active' or v_req.expires_at<=now() or v_mode not in ('video_5s','location_video') then
    raise exception 'video request is not active' using errcode='22023';
  end if;
  if p_duration_seconds not between 4 and 7 then raise exception 'video must be approximately five seconds' using errcode='22023'; end if;
  if p_size_bytes<=0 or p_size_bytes>15728640 then raise exception 'invalid video size' using errcode='22023'; end if;
  if p_storage_path not like v_me::text||'/'||p_request_id::text||'/%' then raise exception 'invalid storage path' using errcode='42501'; end if;

  insert into public.live_location_videos_meta(live_request_id,employee_id,storage_path,storage_bucket,duration_seconds,size_bytes,mime_type,captured_lat,captured_lng,captured_accuracy,captured_at,status,created_by)
  values(p_request_id,v_me,p_storage_path,'live-location-videos',p_duration_seconds,p_size_bytes,p_mime_type,p_latitude,p_longitude,p_accuracy,now(),'ready',auth.uid())
  returning * into v_row;

  -- الإنهاء: video_5s ينتهي بالفيديو. location_video ينتهي فقط عند توفر النقطة أيضًا.
  v_needs_point := coalesce((v_req.metadata->>'needsPoint')::boolean, false);
  if v_mode='video_5s' or not v_needs_point then
    update public.live_location_requests set status='completed',expires_at=now() where id=p_request_id;
  else
    select exists(select 1 from public.employee_locations where live_request_id=p_request_id) into v_has_point;
    if v_has_point then
      update public.live_location_requests set status='completed',expires_at=now() where id=p_request_id;
    end if;
  end if;

  perform public.log_audit_event('live_location.video_registered','security','warning','live_location_videos_meta',v_row.id,'تسجيل فيديو تحقق حي',null,jsonb_build_object('requestId',p_request_id,'durationSeconds',p_duration_seconds,'mode',v_mode));
  return v_row;
end;
$$;
revoke execute on function public.register_live_location_video(uuid,text,integer,bigint,text,double precision,double precision,double precision) from public;
grant execute on function public.register_live_location_video(uuid,text,integer,bigint,text,double precision,double precision,double precision) to authenticated;

-- ---------------------------------------------------------------------
-- (و) get_live_location_response: مسار القراءة الموحّد للمدير التنفيذي
--     يعيد رأس الطلب + كل النقاط + بيانات الفيديو (دون رابط خام).
-- ---------------------------------------------------------------------
create or replace function public.get_live_location_response(p_request_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path=public,pg_temp
as $$
declare
  v_req      public.live_location_requests;
  v_emp      public.employees;
  v_result   jsonb;
  v_has_video boolean;
begin
  select * into v_req from public.live_location_requests where id=p_request_id;
  if not found then raise exception 'request not found' using errcode='P0002'; end if;

  -- الصلاحية: صاحب الطلب (الموظف) أو من يملك view_response عليه أو full-access.
  if not (
    v_req.employee_id = public.current_employee_id()
    or v_req.requested_by = public.current_employee_id()
    or public.can_access_employee(v_req.employee_id,'live_location.view_response')
  ) then
    raise exception 'not permitted to view this response' using errcode='42501';
  end if;

  select * into v_emp from public.employees where id=v_req.employee_id;

  select exists(select 1 from public.live_location_videos_meta m where m.live_request_id=p_request_id and m.status<>'deleted')
    into v_has_video;

  v_result := jsonb_build_object(
    'request', jsonb_build_object(
      'id',v_req.id,'status',
        case when v_req.status in ('pending','accepted','active') and v_req.expires_at<now() then 'expired' else v_req.status end,
      'mode',coalesce(v_req.metadata->>'mode','snapshot'),
      'reason',v_req.reason,'purpose',v_req.purpose,
      'requestedAt',v_req.requested_at,'respondedAt',v_req.responded_at,
      'startsAt',v_req.starts_at,'expiresAt',v_req.expires_at,
      'durationMinutes',v_req.duration_minutes,
      'needsVideo',coalesce((v_req.metadata->>'needsVideo')::boolean,false),
      'needsPoint',coalesce((v_req.metadata->>'needsPoint')::boolean,true)
    ),
    'employee', jsonb_build_object(
      'id',v_emp.id,'name',v_emp.full_name_ar,'employeeCode',v_emp.employee_code,
      'jobTitle',(select name from public.job_titles where id=v_emp.job_title_id),
      'department',(select name from public.departments where id=v_emp.department_id)
    ),
    'requesterName',(select full_name_ar from public.employees where id=v_req.requested_by),
    'points', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',l.id,'latitude',l.latitude,'longitude',l.longitude,'accuracy',l.accuracy,
        'altitude',l.altitude,'speed',l.speed,'heading',l.heading,'isMock',l.is_mock,
        'source',l.source,'addressAr',l.address_ar,'recordedAt',l.recorded_at,'createdAt',l.created_at
      ) order by l.recorded_at)
      from public.employee_locations l where l.live_request_id=p_request_id
    ),'[]'::jsonb),
    'video', (
      select jsonb_build_object(
        'id',m.id,'durationSeconds',m.duration_seconds,'sizeBytes',m.size_bytes,'mimeType',m.mime_type,
        'capturedLat',m.captured_lat,'capturedLng',m.captured_lng,'capturedAccuracy',m.captured_accuracy,
        'capturedAt',m.captured_at,'status',m.status,
        'retentionDeleteAfter',m.retention_delete_after,'legalHoldUntil',m.legal_hold_until
      )
      from public.live_location_videos_meta m
      where m.live_request_id=p_request_id and m.status<>'deleted'
      order by m.created_at desc limit 1
    )
  );

  perform public.log_audit_event('live_location.response_viewed','security','info','live_location_requests',p_request_id,'اطّلاع على نتيجة طلب الموقع',null,jsonb_build_object('hasVideo',v_has_video));
  if v_has_video then
    insert into public.live_location_video_access_logs(video_id,actor_user_id,actor_employee_id,action)
    select m.id, auth.uid(), public.current_employee_id(), 'view'
    from public.live_location_videos_meta m
    where m.live_request_id=p_request_id and m.status<>'deleted'
    order by m.created_at desc limit 1;
  end if;

  return v_result;
end;
$$;
revoke execute on function public.get_live_location_response(uuid) from public;
grant execute on function public.get_live_location_response(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- (ز) can_view_live_location_video: بوابة تستدعيها دالة Edge قبل توقيع الرابط
--     تعيد مسار التخزين إن كان مسموحًا، وإلا NULL.
-- ---------------------------------------------------------------------
create or replace function public.can_view_live_location_video(p_video_id uuid)
returns jsonb
language plpgsql stable security definer set search_path=public,pg_temp
as $$
declare v_m public.live_location_videos_meta;
begin
  select * into v_m from public.live_location_videos_meta where id=p_video_id;
  if not found or v_m.status='deleted' then return null; end if;
  if not (
    v_m.employee_id = public.current_employee_id()
    or public.can_access_employee(v_m.employee_id,'live_location.view_response')
  ) then
    return null;
  end if;
  return jsonb_build_object('storagePath',v_m.storage_path,'bucket',v_m.storage_bucket,'employeeId',v_m.employee_id);
end;
$$;
revoke execute on function public.can_view_live_location_video(uuid) from public;
grant execute on function public.can_view_live_location_video(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- (ح) set_live_location_legal_hold: الحفظ الإداري بعد 24 ساعة
--     بوابة manage_retention أو full-access (السكرتير التنفيذي = full-access).
-- ---------------------------------------------------------------------
create or replace function public.set_live_location_legal_hold(
  p_video_id uuid, p_hold_until timestamptz, p_reason text
)
returns public.live_location_videos_meta
language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_row public.live_location_videos_meta;
begin
  if not (public.current_is_full_access() or public.has_permission('live_location.manage_retention')) then
    raise exception 'retention management permission required' using errcode='42501';
  end if;
  if length(trim(coalesce(p_reason,'')))<5 then raise exception 'legal hold reason is required' using errcode='22023'; end if;

  update public.live_location_videos_meta
    set legal_hold_until = p_hold_until,
        retention_delete_after = case when p_hold_until is not null then greatest(coalesce(retention_delete_after,now()), p_hold_until) else retention_delete_after end
    where id=p_video_id and status<>'deleted'
    returning * into v_row;
  if not found then raise exception 'video not found' using errcode='P0002'; end if;

  insert into public.live_location_video_access_logs(video_id,actor_user_id,actor_employee_id,action,reason)
  values(p_video_id, auth.uid(), public.current_employee_id(), case when p_hold_until is null then 'release_hold' else 'legal_hold' end, trim(p_reason));

  perform public.log_audit_event(
    case when p_hold_until is null then 'live_location.hold_released' else 'live_location.legal_hold' end,
    'security','warning','live_location_videos_meta',p_video_id,'حفظ إداري لفيديو التحقق',null,
    jsonb_build_object('holdUntil',p_hold_until,'reason',trim(p_reason))
  );
  return v_row;
end;
$$;
revoke execute on function public.set_live_location_legal_hold(uuid,timestamptz,text) from public;
grant execute on function public.set_live_location_legal_hold(uuid,timestamptz,text) to authenticated;

-- ---------------------------------------------------------------------
-- (ط) get_executive_attendance_overview: لوحة المتابعة اليومية
--     يعيد ملخصًا + صفوف الموظفين مع حالة الحضور/الإجازة/التكليف وآخر موقع.
--     البوابة: reports.attendance.read أو live_location.request أو full-access.
-- ---------------------------------------------------------------------
create or replace function public.get_executive_attendance_overview(p_date date default null)
returns jsonb
language plpgsql stable security definer set search_path=public,pg_temp
as $$
declare
  v_date date := coalesce(p_date, current_date);
  v_rows jsonb;
  v_summary jsonb;
begin
  if not (
    public.current_is_full_access()
    or public.has_permission('reports.attendance.read')
    or public.has_permission('live_location.request')
  ) then
    raise exception 'attendance overview permission required' using errcode='42501';
  end if;

  with base as (
    select
      e.id, e.full_name_ar, e.employee_code, e.department_id, e.photo_url,
      jt.name as job_title, d.name as department,
      -- المدير المباشر
      (select mgr.full_name_ar from public.manager_relations mr
         join public.employees mgr on mgr.id=mr.manager_employee_id
        where mr.employee_id=e.id and mr.effective_from<=now() and (mr.effective_to is null or mr.effective_to>now())
        order by mr.effective_from desc limit 1) as manager_name,
      ad.status as att_status, ad.first_check_in, ad.last_check_out,
      ad.late_minutes, ad.early_leave_minutes, ad.updated_at as att_updated_at,
      -- إجازة معتمدة تشمل اليوم
      exists(
        select 1 from public.leave_requests lr join public.requests rq on rq.id=lr.request_id
        where lr.employee_id=e.id and rq.status='approved' and v_date between lr.start_date and lr.end_date
      ) as on_leave,
      -- تكليف عمل معتمد/جارٍ يشمل اليوم (مأمورية/قافلة/فاندي)
      (select wa.assignment_type from public.work_assignment_participants wp
         join public.work_assignments wa on wa.id=wp.assignment_id
        where wp.employee_id=e.id and wa.status in ('APPROVED','IN_PROGRESS','REPORT_PENDING','REPORT_SUBMITTED')
          and v_date between wa.start_at::date and wa.end_at::date
        order by wa.start_at desc limit 1) as assignment_type,
      -- آخر موقع مسجّل
      lp.latitude, lp.longitude, lp.accuracy, lp.recorded_at, lp.address_ar, lp.source as loc_source,
      -- طلب موقع نشط
      ar.id as active_request_id, ar.status as active_request_status
    from public.employees e
    left join public.job_titles jt on jt.id=e.job_title_id
    left join public.departments d on d.id=e.department_id
    left join public.attendance_daily ad on ad.employee_id=e.id and ad.work_date=v_date
    left join lateral (
      select l.latitude,l.longitude,l.accuracy,l.recorded_at,l.address_ar,l.source
      from public.employee_locations l where l.employee_id=e.id order by l.recorded_at desc limit 1
    ) lp on true
    left join lateral (
      select r.id,r.status from public.live_location_requests r
      where r.employee_id=e.id and r.status in ('pending','accepted','active')
        and (r.expires_at is null or r.expires_at>now())
      order by r.requested_at desc limit 1
    ) ar on true
    where e.status='active'
      and public.can_access_employee(e.id,'live_location.request')
  ),
  classified as (
    select *,
      case
        when on_leave then 'on_leave'
        when assignment_type is not null then 'assignment'
        when att_status='present' and coalesce(late_minutes,0)>0 then 'late'
        when att_status='present' then 'present'
        when att_status='late' then 'late'
        when last_check_out is not null and coalesce(early_leave_minutes,0)>0 then 'left_early'
        when last_check_out is not null then 'checked_out'
        when att_status='absent' then 'absent'
        else 'not_yet'
      end as derived_status
    from base
  )
  select
    jsonb_agg(jsonb_build_object(
      'id',id,'name',full_name_ar,'employeeCode',employee_code,'avatarUrl',photo_url,
      'jobTitle',job_title,'department',department,'managerName',manager_name,
      'status',derived_status,'attStatus',att_status,
      'firstCheckIn',first_check_in,'lastCheckOut',last_check_out,
      'lateMinutes',late_minutes,'earlyLeaveMinutes',early_leave_minutes,
      'onLeave',on_leave,'assignmentType',assignment_type,
      'lastLatitude',latitude,'lastLongitude',longitude,'lastAccuracy',accuracy,
      'lastLocationAt',recorded_at,'lastAddressAr',address_ar,'locationSource',loc_source,
      'statusUpdatedAt',greatest(coalesce(att_updated_at,recorded_at),coalesce(recorded_at,att_updated_at)),
      'activeRequestId',active_request_id,'activeRequestStatus',active_request_status
    ) order by full_name_ar),
    jsonb_build_object(
      'total',count(*),
      'present',count(*) filter (where derived_status='present'),
      'late',count(*) filter (where derived_status='late'),
      'notYet',count(*) filter (where derived_status='not_yet'),
      'absent',count(*) filter (where derived_status='absent'),
      'checkedOut',count(*) filter (where derived_status='checked_out'),
      'leftEarly',count(*) filter (where derived_status='left_early'),
      'onLeave',count(*) filter (where derived_status='on_leave'),
      'onAssignment',count(*) filter (where derived_status='assignment'),
      'onMission',count(*) filter (where assignment_type='MISSION'),
      'onConvoy',count(*) filter (where assignment_type='CONVOY'),
      'onFundraising',count(*) filter (where assignment_type='FUNDRAISING'),
      'activeLocationRequests',count(*) filter (where active_request_id is not null)
    )
  into v_rows, v_summary
  from classified;

  return jsonb_build_object(
    'date', v_date,
    'summary', coalesce(v_summary, jsonb_build_object('total',0)),
    'employees', coalesce(v_rows,'[]'::jsonb),
    'generatedAt', now()
  );
end;
$$;
revoke execute on function public.get_executive_attendance_overview(date) from public;
grant execute on function public.get_executive_attendance_overview(date) to authenticated;

-- ---------------------------------------------------------------------
-- (ي) nudge_notification_dispatcher: نبضة pg_net فورية لدالة الإشعارات
--     تُستدعى من request_live_location لإرسال الإشعار العاجل دون انتظار الكرون.
--     آمنة: تتخطى بهدوء إن غاب pg_net أو الإعدادات (مثل 0049).
-- ---------------------------------------------------------------------
create or replace function public.nudge_notification_dispatcher()
returns void
language plpgsql security definer set search_path=public,pg_temp
as $$
declare
  v_has_net boolean;
  v_base    text;
  v_secret  text;
begin
  select exists(select 1 from pg_extension where extname='pg_net') into v_has_net;
  if not v_has_net then return; end if;
  v_base   := current_setting('app.settings.functions_base_url', true);
  v_secret := current_setting('app.settings.cron_secret', true);
  if v_base is null or v_base='' or v_secret is null or v_secret='' then return; end if;
  perform net.http_post(
    url     => v_base||'/notification-dispatcher',
    headers => jsonb_build_object('Content-Type','application/json','x-cron-secret',v_secret),
    body    => jsonb_build_object('trigger','urgent_location','expedite',true)
  );
exception when others then
  -- لا تُفشل الطلب بسبب فشل النبضة؛ الكرون يبقى الاحتياط.
  return;
end;
$$;
revoke execute on function public.nudge_notification_dispatcher() from public;
grant execute on function public.nudge_notification_dispatcher() to authenticated;

-- ---------------------------------------------------------------------
-- (ك) دعم رمز FCM في push_subscriptions + RPC لتسجيله من التطبيق
--     الجدول كان بشكل Web Push فقط (endpoint/p256dh/auth). نضيف عمود fcm_token
--     ومنصة، ونسمح لصف اشتراك FCM بمفاتيح Web Push فارغة (placeholder).
-- ---------------------------------------------------------------------
alter table public.push_subscriptions
  add column if not exists fcm_token text,
  add column if not exists platform  text;

create unique index if not exists ux_push_subscriptions_fcm
  on public.push_subscriptions(fcm_token) where fcm_token is not null;

create or replace function public.upsert_my_push_token(p_fcm_token text, p_platform text)
returns void
language plpgsql security definer set search_path=public,pg_temp
as $$
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if length(trim(coalesce(p_fcm_token,'')))<16 then raise exception 'invalid fcm token' using errcode='22023'; end if;
  if p_platform is not null and p_platform not in ('android','ios','web') then raise exception 'invalid platform' using errcode='22023'; end if;

  insert into public.push_subscriptions(user_id,endpoint,p256dh_key,auth_key,fcm_token,platform,is_active,last_used_at,created_by)
  values(auth.uid(),'fcm://'||p_fcm_token,'-','-',p_fcm_token,coalesce(p_platform,'android'),true,now(),auth.uid())
  on conflict (fcm_token) do update
    set user_id=excluded.user_id, is_active=true, platform=excluded.platform,
        last_used_at=now(), updated_at=now();
end;
$$;
revoke execute on function public.upsert_my_push_token(text,text) from public;
grant execute on function public.upsert_my_push_token(text,text) to authenticated;

commit;
