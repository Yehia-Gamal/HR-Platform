-- =====================================================================
-- 0572: موظفو العيادات — صمت إشعارات كامل + رؤية متبادلة مقفلة
-- ---------------------------------------------------------------------
-- المطلب المعتمد (إدارة العيادات منفصلة، غرضها حسم الحضور والانصراف):
--   1) موظف العيادات (clinic-staff) لا يستقبل أي إشعار من التطبيق
--      (حضور/تذكيرات/تنبيهات شاملة/إعلانات/عقوبات/موقع/قنوات) — عدا
--      نتيجة طلباته هو (entity_type='request' يخصّه): «السماح
--      بإشعارات طلباتهم» كما اعتمده الإدارة.
--   2) لا طلبات موقع إطلاقاً له — مطلقاً حتى من HR/التنفيذي.
--   3) عزل رؤية متبادل: لا يرى باقي الهيكل ولا يظهر له — عدا مديره
--      المباشر وزملاء قسمه؛ ومدير العيادات + HR + المدير التنفيذي
--      يرون الجميع (استثناء صريح بالدور — فجوة مُصلحة هنا).
--   4) أسماء الأقسام تبقى ظاهرة في كتالوج الهيكل بلا موظفين ولا
--      أعداد — قرار الإدارة.
--
-- الآلية:
--   أ) employee_blocks_inbound_alerts + trigger BEFORE INSERT على
--      notifications — نقطة اخت واحدة تغطي كل مسارات الإدخال
--      وpush وRealtime دفعة واحدة.
--   ب) current_can_view_all_employees (استثناءات الدور) داخل
--      can_view_isolated_employee و can_see_directory_entry.
--   ج) can_access_employee: بعد أي scope — هدف معزول بلا حق رؤية ←
--      false (يصلح RLS على employees + كل الدوال المعتمدة عليه).
--   د) فلاتر صريحة في دوال SECURITY DEFINER التي تتجاوز RLS.
--   هـ) تنظيف: حذف سجل إشعاراتهم القديم + إلغاء طلبات الموقع
--      المعلقة لهم (notification_jobs تُحذف تلقائياً CASCADE).
--   و) تفكيك ربط مسار الطلب المعزول بـ medical_leave_v1: يبقى مقصوراً
--      على العزل الإداري (القسم) حتى لا تتغير موافقات موظفي العيادات.
-- ملاحظة: العزل وراثي بالدور (clinic-staff) حتى لو لم يُسند القسم،
-- مع بقاء departments.is_isolated أساس العزل الإداري (0444/0474).
-- =====================================================================

begin;

-- ─── 1) دوال مساعدة جديدة ───

-- من يحق له رؤية كل الموظفين بغضّ النظر عن العزل: كامل الوصول
-- (admin/executive-secretary) أو الأدوار المعفاة صراحةً.
create or replace function public.current_can_view_all_employees()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.current_is_full_access()
      or public.current_has_active_role(array[
           'hr-manager', 'hr-specialist',
           'executive', 'executive-director',
           'clinics-manager'
         ]);
$$;

-- هل يستقبل هذا الموظف أي إشعار/طلب موقع؟ true لدور clinic-staff
-- الفعّال (حسب تواريخ user_roles) — أساس منع الإشعارات والموقع.
create or replace function public.employee_blocks_inbound_alerts(p_employee_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
      from public.employees e
      join public.user_roles ur on ur.user_id = e.user_id
      join public.roles r on r.id = ur.role_id
     where e.id = p_employee_id
       and r.slug = 'clinic-staff'
       and (ur.effective_from is null or ur.effective_from <= now())
       and (ur.effective_to is null or ur.effective_to > now())
  );
$$;

-- مصيدة الإشعارات: تمنع كل إشعار لموظف عيادات — عدا نتيجة طلب
-- يخصّه هو شخصياً (entity_type='request' وملكيته للمستلم).
create or replace function public.notifications_block_clinic_staff()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_emp uuid := new.recipient_employee_id;
begin
  if v_emp is null and new.recipient_user_id is not null then
    select e.id into v_emp
      from public.employees e
     where e.user_id = new.recipient_user_id;
  end if;

  if v_emp is null or not public.employee_blocks_inbound_alerts(v_emp) then
    return new;
  end if;

  -- الاستثناء الوحيد: نتيجة طلب يملكه الموظف نفسه.
  if new.entity_type = 'request'
     and new.entity_id is not null
     and exists (
       select 1 from public.requests rq
        where rq.id = new.entity_id
          and rq.employee_id = v_emp
     ) then
    return new;
  end if;

  return null;
end;
$$;

drop trigger if exists trg_notifications_block_clinic_staff on public.notifications;
create trigger trg_notifications_block_clinic_staff
  before insert on public.notifications
  for each row
  execute function public.notifications_block_clinic_staff();

-- ─── 2) تنظيف البيانات القديمة ───

-- إلغاء أي طلب موقع معلّق/نشط كان موجهاً لموظف عيادات.
update public.live_location_requests
   set status = 'cancelled',
       responded_at = coalesce(responded_at, now())
 where status in ('pending', 'accepted', 'active')
   and public.employee_blocks_inbound_alerts(employee_id);

-- حذف سجل إشعارات موظفي العيادات بالكامل (notification_jobs CASCADE).
delete from public.notifications n
 where public.employee_blocks_inbound_alerts(
   coalesce(
     n.recipient_employee_id,
     (select e.id from public.employees e where e.user_id = n.recipient_user_id)
   )
 );

-- ─── 3) إعادة بناء الدوال (نسخ حية من الإنتاج + فلاتر 0572) ───

-- ===== is_employee_isolated(p_employee_id uuid) =====
CREATE OR REPLACE FUNCTION public.is_employee_isolated(p_employee_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- 0572: العزل وراثي بالدور (clinic-staff) حتى لو لم يُسند قسم معزول؛
  -- ويبقى العزل الإداري (departments.is_isolated) أساساً كما في 0474.
  select coalesce((
    select d.is_isolated
      from public.employees e
      join public.departments d on d.id = e.department_id
     where e.id = p_employee_id
  ), false)
  or public.employee_blocks_inbound_alerts(p_employee_id);
$function$;

-- ===== can_view_isolated_employee(p_target uuid) =====
CREATE OR REPLACE FUNCTION public.can_view_isolated_employee(p_target uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
begin
  if not public.is_employee_isolated(p_target) then return true; end if;
  -- 0572: استثناءات الدور (HR/تنفيذي/مدير العيادات) تتجاوز العزل الإداري.
  if public.current_can_view_all_employees() then return true; end if;
  if v_me is null then return false; end if;
  -- نفس القسم المعزول (زميل في الإدارة الطبية)
  if exists (
    select 1
      from public.employees t
     where t.id = p_target
       and t.department_id = (select e.department_id from public.employees e where e.id = v_me)
  ) then return true; end if;
  -- المدير المباشر (علاقة إشراف سارية)
  if exists (
    select 1 from public.manager_relations mr
     where mr.employee_id = p_target
       and mr.manager_employee_id = v_me
       and mr.effective_from <= now()
       and (mr.effective_to is null or mr.effective_to > now())
  ) then return true; end if;
  return false;
end $function$;

-- ===== can_see_directory_entry(p_viewer uuid, p_target uuid) =====
CREATE OR REPLACE FUNCTION public.can_see_directory_entry(p_viewer uuid, p_target uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if p_target = p_viewer then return true; end if;
  -- 0572: نفس استثناءات الدور في can_view_isolated_employee.
  if public.current_can_view_all_employees() then return true; end if;
  if p_viewer is null or p_target is null then return false; end if;
  -- المعزول لا يظهر لمن خارج نطاقه
  if public.is_employee_isolated(p_target)
     and not public.can_view_isolated_employee(p_target) then
    return false;
  end if;
  -- مشاهد معزول لا يرى عام الفريق (يرى قسمه ومديره فقط)
  if public.is_employee_isolated(p_viewer)
     and not public.is_employee_isolated(p_target) then
    -- يُسمح برؤية مديره المباشر فقط
    return exists (
      select 1 from public.manager_relations mr
       where mr.employee_id = p_viewer
         and mr.manager_employee_id = p_target
         and mr.effective_from <= now()
         and (mr.effective_to is null or mr.effective_to > now())
    );
  end if;
  return true;
end $function$;

-- ===== can_access_employee(p_employee_id uuid, p_code text) =====
CREATE OR REPLACE FUNCTION public.can_access_employee(p_employee_id uuid, p_code text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid;
  v_scope text;
  v_ovr jsonb;
  v_target_dept uuid;
  v_target_branch uuid;
  v_target_team uuid;
  v_allowed boolean := false;
begin
  if p_employee_id is null then return false; end if;
  if public.current_is_full_access() then return true; end if;

  v_me := public.current_employee_id();
  if v_me is null then return false; end if;
  if v_me = p_employee_id then return true; end if;

  if p_code is null then
    return exists (
      select 1
      from public.manager_relations mr
      where mr.manager_employee_id = v_me
        and mr.employee_id = p_employee_id
        and mr.effective_from <= now()
        and (mr.effective_to is null or mr.effective_to > now())
    );
  end if;

  select e.department_id, e.branch_id, e.team_id
    into v_target_dept, v_target_branch, v_target_team
  from public.employees e
  where e.id = p_employee_id;

  if not found then return false; end if;

  for v_scope, v_ovr in
    select rp.scope, coalesce(ur.scope_override, '{}'::jsonb)
    from public.user_roles ur
    join public.role_permissions rp on rp.role_id = ur.role_id
    join public.permissions p on p.id = rp.permission_id
    where ur.user_id = auth.uid()
      and p.code = p_code
      and ur.effective_from <= now()
      and (ur.effective_to is null or ur.effective_to > now())
      and (rp.effective_from is null or rp.effective_from <= now())
      and (rp.effective_to is null or rp.effective_to > now())
  loop
    case v_scope
      when 'organization' then
        v_allowed := true; exit;
      when 'self' then
        if v_me = p_employee_id then v_allowed := true; exit; end if;
      when 'direct_reports' then
        if exists (
          select 1 from public.manager_relations mr
          where mr.manager_employee_id = v_me
            and mr.employee_id = p_employee_id
            and mr.effective_from <= now()
            and (mr.effective_to is null or mr.effective_to > now())
        ) then v_allowed := true; exit; end if;
      when 'management_descendants' then
        if public.is_management_descendant(v_me, p_employee_id) then v_allowed := true; exit; end if;
      when 'department' then
        if v_target_dept is not null and v_target_dept = (
          select e.department_id from public.employees e where e.id = v_me
        ) then v_allowed := true; exit; end if;
      when 'branch' then
        if v_target_branch is not null and v_target_branch = (
          select e.branch_id from public.employees e where e.id = v_me
        ) then v_allowed := true; exit; end if;
      when 'team' then
        if v_target_team is not null and v_target_team = (
          select e.team_id from public.employees e where e.id = v_me
        ) then v_allowed := true; exit; end if;
      when 'selected_departments' then
        if v_target_dept is not null
           and coalesce(v_ovr->'department_ids', '[]'::jsonb) ? v_target_dept::text then
          v_allowed := true; exit;
        end if;
      when 'selected_branches' then
        if v_target_branch is not null
           and coalesce(v_ovr->'branch_ids', '[]'::jsonb) ? v_target_branch::text then
          v_allowed := true; exit;
        end if;
      when 'selected_employees' then
        if coalesce(v_ovr->'employee_ids', '[]'::jsonb) ? p_employee_id::text then
          v_allowed := true; exit;
        end if;
      else
        null;
    end case;
  end loop;

  -- 0572: أي scope لا يتجاوز عزل الهدف عن غير المرئين له —
  -- هنا تُصلَح RLS على employees وكل الدوال المعتمدة على هذه الدالة.
  if v_allowed
     and public.is_employee_isolated(p_employee_id)
     and not public.can_view_isolated_employee(p_employee_id) then
    return false;
  end if;

  return v_allowed;
end;
$function$;

-- ===== request_live_location(p_employee_id uuid, p_mode text, p_reason text) =====
CREATE OR REPLACE FUNCTION public.request_live_location(p_employee_id uuid, p_mode text DEFAULT 'snapshot'::text, p_reason text DEFAULT ''::text)
 RETURNS live_location_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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

  -- 0444: استبعاد المدير التنفيذي كهدف — لا نطلب موقعاً من المدير التنفيذي.
  if public.is_employee_executive(p_employee_id) then
    raise exception 'cannot request location of executive director' using errcode='22023';
  end if;

  -- 0572: موظف العيادات لا يستقبل أي طلب موقع إطلاقاً (حتى من HR/التنفيذي).
  if public.employee_blocks_inbound_alerts(p_employee_id) then
    raise exception 'employee does not accept location requests' using errcode='22023';
  end if;

  -- V12 §9: طلبات الموقع snapshot فقط — الفيديو أُزيل نهائياً.
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

  -- مهلة 30 ثانية من نفس الطالب لنفس المستهدف.
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

  -- 0342: HTTPS App Link بدل ahlashabab:// حتى تفتح الواجهة فوق الإشعار.
  v_deep_link := 'https://ahla-shabab-management-os.vercel.app/action/live_location_request/' || v_req.id::text;

  select user_id into v_target_user from public.employees where id = p_employee_id;
  if v_target_user is not null then
    insert into public.notifications(
      recipient_user_id, recipient_employee_id, title, body, category, priority,
      action_url, entity_type, entity_id, metadata, created_by)
    values(
      v_target_user, p_employee_id,
      'طلب موقع عاجل',
      'اجتمع التنفيذ لمعرفة موقعك فوراً. يرجى الضغط للموافقة.',
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
    'live_location_requests', v_req.id, 'دق طلب موقع حي', null,
    jsonb_build_object('mode', 'snapshot', 'employeeId', p_employee_id, 'requestId', v_req.id));
  return v_req;
end $function$;

-- ===== request_live_location_broadcast(p_mode text, p_reason text) =====
CREATE OR REPLACE FUNCTION public.request_live_location_broadcast(p_mode text DEFAULT 'snapshot'::text, p_reason text DEFAULT 'تحقق ميداني جماعي'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
      and not public.employee_blocks_inbound_alerts(e.id)  -- 0572: استبعاد موظفي العيادات من البث
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
$function$;

-- ===== get_my_live_location_requests(p_limit integer) =====
CREATE OR REPLACE FUNCTION public.get_my_live_location_requests(p_limit integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',q.id,'requesterName',q.requester_name,'reason',q.reason,'status',q.effective_status,
    'mode',q.mode,'durationMinutes',q.duration_minutes,'requestedAt',q.requested_at,
    'expiresAt',q.expires_at
  ) order by q.requested_at desc),'[]'::jsonb)
  from (
    select r.id,req.full_name_ar requester_name,r.reason,
      case when r.status in ('pending','accepted','active') and r.expires_at<now() then 'expired' else r.status end effective_status,
      coalesce(r.metadata->>'mode','snapshot') mode,r.duration_minutes,r.requested_at,r.expires_at
    from public.live_location_requests r left join public.employees req on req.id=r.requested_by
    where r.employee_id=public.current_employee_id()
      and not public.employee_blocks_inbound_alerts(r.employee_id)  -- 0572
    order by r.requested_at desc limit greatest(1,least(coalesce(p_limit,30),100))
  ) q;
$function$;

-- ===== get_active_broadcast_alert() =====
CREATE OR REPLACE FUNCTION public.get_active_broadcast_alert()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select to_jsonb(x)
    from (
      select a.id, a.message, a.created_at, a.expires_at
        from public.broadcast_alerts a
       where a.is_active = true
         and a.expires_at > now()
         -- 0572: موظف العيادات لا يرى تنبيهات البث الشامل (null ← false ← يظهر).
         and not public.employee_blocks_inbound_alerts(public.current_employee_id())
       order by a.created_at desc
       limit 1
    ) x;
$function$;

-- ===== get_location_directory(p_search text, p_limit integer) =====
CREATE OR REPLACE FUNCTION public.get_location_directory(p_search text DEFAULT NULL::text, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
        AND NOT public.employee_blocks_inbound_alerts(e.id)  -- 0572: موظفو العيادات خارج دليل الموقع
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
$function$;

-- ===== get_admin_org_chart() =====
CREATE OR REPLACE FUNCTION public.get_admin_org_chart()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_result jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  IF NOT (
    public.current_is_full_access()
    OR public.has_permission('organization.org_chart.read')
  ) THEN
    RAISE EXCEPTION 'ERR_FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  WITH RECURSIVE
  -- جميع الموظفين غير المحذوفين وغير المنتهين (بما فيهم الموقوفون والمدعوون وفترة الإخطار)
  emp_base AS (
    SELECT
      e.id,
      e.full_name_ar,
      e.full_name_en,
      e.photo_url,
      coalesce(jt.name, jt.name_en, '') AS job_title,
      coalesce(d.name, '') AS department_name,
      e.employee_code,
      e.department_id,
      e.status,
      e.is_active,
      e.is_deleted
    FROM public.employees e
    LEFT JOIN public.job_titles jt ON jt.id = e.job_title_id
    LEFT JOIN public.departments d ON d.id = e.department_id
    WHERE e.is_deleted = false
      AND e.status NOT IN ('terminated', 'draft')
      AND NOT (
        public.is_employee_isolated(e.id)
        AND NOT public.can_view_isolated_employee(e.id)
      )  -- 0572: إخفاء المعزول عن غير المرئين له في الشجرة
  ),
  -- العلاقات النشطة فقط (مدير رئيسي نشط)
  active_primary_managers AS (
    SELECT
      mr.employee_id,
      mr.manager_employee_id
    FROM public.manager_relations mr
    WHERE mr.relation_type = 'primary'
      AND mr.effective_to IS NULL
      AND mr.employee_id IN (SELECT id FROM emp_base)
      AND mr.manager_employee_id IN (SELECT id FROM emp_base)
  ),
  -- الشجرة الهرمية المتكررة بدءًا من الجذور (موظفون بلا مدير رئيسي)
  org_tree AS (
    -- الجذور: موظفون ليس لديهم مدير رئيسي نشط
    SELECT
      eb.id,
      eb.full_name_ar,
      eb.full_name_en,
      eb.photo_url,
      eb.job_title,
      eb.department_name,
      eb.employee_code,
      eb.department_id,
      eb.status,
      eb.is_active,
      NULL::uuid AS manager_employee_id,
      0 AS depth,
      ARRAY[eb.id]::uuid[] AS path
    FROM emp_base eb
    LEFT JOIN active_primary_managers apm ON apm.employee_id = eb.id
    WHERE apm.employee_id IS NULL

    UNION ALL

    -- الأبناء: موظفون مديرهم موجود بالفعل في الشجرة
    SELECT
      eb.id,
      eb.full_name_ar,
      eb.full_name_en,
      eb.photo_url,
      eb.job_title,
      eb.department_name,
      eb.employee_code,
      eb.department_id,
      eb.status,
      eb.is_active,
      apm.manager_employee_id,
      ot.depth + 1,
      ot.path || eb.id
    FROM emp_base eb
    JOIN active_primary_managers apm ON apm.employee_id = eb.id
    JOIN org_tree ot ON ot.id = apm.manager_employee_id
    WHERE NOT eb.id = ANY(ot.path)
  ),
  -- عدّ المرؤوسين المباشرين لكل موظف
  direct_counts AS (
    SELECT
      manager_employee_id AS emp_id,
      COUNT(*) AS direct_reports_count
    FROM active_primary_managers
    GROUP BY manager_employee_id
  )
  SELECT jsonb_build_object(
    'employees', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'id', t.id,
        'fullNameAr', t.full_name_ar,
        'fullNameEn', t.full_name_en,
        'photoUrl', t.photo_url,
        'jobTitle', t.job_title,
        'departmentName', t.department_name,
        'employeeCode', t.employee_code,
        'departmentId', t.department_id,
        'status', t.status,
        'isActive', t.is_active,
        'managerEmployeeId', t.manager_employee_id,
        'directReportsCount', coalesce(dc.direct_reports_count, 0),
        'depth', t.depth,
        'path', t.path
      ) ORDER BY t.path, t.full_name_ar)
      FROM org_tree t
      LEFT JOIN direct_counts dc ON dc.emp_id = t.id
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

-- ===== get_employees_enriched(p_search text, p_status text, p_limit integer) =====
CREATE OR REPLACE FUNCTION public.get_employees_enriched(p_search text DEFAULT NULL::text, p_status text DEFAULT NULL::text, p_limit integer DEFAULT 200)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_search text := nullif(trim(lower(coalesce(p_search, ''))), '');
  v_is_org_admin boolean := false;
begin
  if auth.uid() is null then
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  v_is_org_admin := public.current_is_full_access()
    or public.has_permission('organization.org_chart.read');

  return coalesce((
    select jsonb_agg(row_data order by row_data->>'fullNameAr')
    from (
      select jsonb_build_object(
        'id', e.id,
        'employeeCode', e.employee_code,
        'fullNameAr', e.full_name_ar,
        'fullNameEn', e.full_name_en,
        'phoneE164', e.phone_e164,
        'status', e.status,
        'isActive', e.is_active,
        'photoUrl', e.photo_url,
        'departmentId', e.department_id,
        'department', coalesce(
          (
            select string_agg(d_sub.name, ' / ' order by ed_sub.is_primary desc, d_sub.name)
            from public.employee_departments ed_sub
            join public.departments d_sub on d_sub.id = ed_sub.department_id
            where ed_sub.employee_id = e.id
          ),
          d.name
        ),
        'teamId', e.team_id,
        'team', t.name,
        'branchId', e.branch_id,
        'branch', b.name,
        'jobTitle', jt.name,
        'createdAt', e.created_at
      ) as row_data
      from public.employees e
      left join public.departments d on d.id = e.department_id
      left join public.teams t on t.id = e.team_id
      left join public.branches b on b.id = e.branch_id
      left join public.job_titles jt on jt.id = e.job_title_id
      where e.is_deleted = false
        and not public.is_employee_executive(e.id)
        and (
          not public.is_employee_isolated(e.id)
          or public.can_view_isolated_employee(e.id)
        ) -- 0572
        and (p_status is null or e.status = p_status)
        and (
          v_search is null
          or lower(e.full_name_ar) like '%' || v_search || '%'
          or lower(coalesce(e.full_name_en, '')) like '%' || v_search || '%'
          or lower(e.employee_code) like '%' || v_search || '%'
          or e.phone_e164 like '%' || v_search || '%'
          or lower(coalesce(d.name, '')) like '%' || v_search || '%'
          or exists (
            select 1 from public.employee_departments ed_srch
            join public.departments d_srch on d_srch.id = ed_srch.department_id
            where ed_srch.employee_id = e.id and lower(d_srch.name) like '%' || v_search || '%'
          )
        )
        and (
          v_is_org_admin
          or public.can_access_employee(e.id, 'people.employee.read')
        )
      order by e.created_at desc
      limit greatest(1, least(coalesce(p_limit, 200), 500))
    ) sub
  ), '[]'::jsonb);
end;
$function$;

-- ===== get_organization_admin_catalog() =====
CREATE OR REPLACE FUNCTION public.get_organization_admin_catalog()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if not (
    public.current_is_full_access()
    or public.has_any_permission(array[
      'organization.entity.read','organization.org_chart.read',
      'organization.department.manage','organization.position.manage',
      'organization.unit.manage'
    ])
  ) then
    raise exception 'وصول كتالوج الهيكل مرفوض' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'entities', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', e.id, 'code', e.code, 'name', e.name,
        'active', e.is_active
      ) order by e.name)
      from public.legal_entities e
    ), '[]'::jsonb),
    'branches', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', b.id, 'entityId', b.legal_entity_id, 'code', b.code,
        'name', b.name, 'active', b.is_active
      ) order by b.name)
      from public.branches b
    ), '[]'::jsonb),
    'departments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id, 'entityId', d.legal_entity_id, 'branchId', d.branch_id,
        'parentId', d.parent_id, 'managerId', d.manager_id,
        'code', d.code, 'name', d.name, 'nameEn', d.name_en,
        'active', d.is_active,
        'employeeCount', (select count(*) from public.employees e where e.department_id = d.id and e.is_deleted = false and (not public.is_employee_isolated(e.id) or public.can_view_isolated_employee(e.id))),
        'positionCount', (select count(*) from public.positions p where p.department_id = d.id and p.is_active = true)
      ) order by d.name)
      from public.departments d
    ), '[]'::jsonb),
    'teams', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'departmentId', t.department_id, 'parentId', t.parent_id,
        'leadId', t.lead_id, 'code', t.code, 'name', t.name,
        'active', t.is_active,
        'employeeCount', (select count(*) from public.employees e where e.team_id = t.id and e.is_deleted = false and (not public.is_employee_isolated(e.id) or public.can_view_isolated_employee(e.id)))
      ) order by t.name)
      from public.teams t
    ), '[]'::jsonb),
    'positions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'departmentId', p.department_id, 'teamId', p.team_id,
        'jobTitleId', p.job_title_id, 'gradeId', p.job_grade_id,
        'reportsToId', p.reports_to_position_id,
        'code', p.code, 'name', p.name, 'nameEn', p.name_en,
        'headcount', p.headcount, 'active', p.is_active,
        'assignedCount', (select count(*) from public.employees e where e.position_id = p.id and e.is_deleted = false and e.status <> 'terminated' and (not public.is_employee_isolated(e.id) or public.can_view_isolated_employee(e.id)))
      ) order by p.name)
      from public.positions p
    ), '[]'::jsonb),
    'employees', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', e.id, 'code', e.employee_code, 'name', e.full_name_ar,
        'departmentId', e.department_id, 'teamId', e.team_id,
        'positionId', e.position_id, 'active', e.is_active
      ) order by e.full_name_ar)
      from public.employees e where e.is_deleted = false
        and (not public.is_employee_isolated(e.id) or public.can_view_isolated_employee(e.id)) -- 0572
    ), '[]'::jsonb),
    'jobTitles', coalesce((
      select jsonb_agg(jsonb_build_object('id', j.id, 'name', j.name, 'active', j.is_active) order by j.name)
      from public.job_titles j
    ), '[]'::jsonb),
    'grades', coalesce((
      select jsonb_agg(jsonb_build_object('id', g.id, 'name', g.name, 'level', g.level, 'active', g.is_active) order by g.level, g.name)
      from public.job_grades g
    ), '[]'::jsonb),
    'lastUpdatedAt', now()
  );
end;
$function$;

-- ===== get_attendance_day_roster(p_date date, p_department_id uuid, p_branch_id uuid, p_manager_id uuid) =====
CREATE OR REPLACE FUNCTION public.get_attendance_day_roster(p_date date DEFAULT NULL::date, p_department_id uuid DEFAULT NULL::uuid, p_branch_id uuid DEFAULT NULL::uuid, p_manager_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_date date := coalesce(p_date, (now() at time zone 'Africa/Cairo')::date);
begin
  -- 0572: موظف العيادات لا يطّلع على دفتر حضور الآخرين.
  if public.employee_blocks_inbound_alerts(public.current_employee_id()) then
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  return coalesce((
    with base as (
      select
        e.id,
        e.full_name_ar,
        e.employee_code,
        e.photo_url,
        jt.name_ar as job_title,
        d.name_ar  as department,
        m.full_name_ar as manager_name,
        ad.status as att_status,
        ad.first_check_in,
        ad.last_check_out,
        ad.late_minutes,
        ad.early_leave_minutes,
        exists (
          select 1 from public.leave_requests lr
          join public.requests r on r.id = lr.request_id
          where lr.employee_id = e.id
            and r.status in ('approved', 'completed')
            and v_date between lr.start_date and lr.end_date
        ) as on_leave,
        (
          select wa.assignment_type
          from public.work_assignments wa
          where wa.responsible_employee_id = e.id
            and wa.status in ('APPROVED','IN_PROGRESS')
            and v_date between (wa.start_at at time zone 'Africa/Cairo')::date
                           and (wa.end_at   at time zone 'Africa/Cairo')::date
          limit 1
        ) as assignment_type
      from public.employees e
      left join public.job_titles jt on jt.id = e.job_title_id
      left join public.departments d on d.id = e.department_id
      left join public.manager_relations mr on mr.employee_id = e.id
        and mr.effective_from <= now()
        and (mr.effective_to is null or mr.effective_to > now())
      left join public.employees m on m.id = mr.manager_employee_id
      left join public.attendance_daily ad on ad.employee_id = e.id and ad.work_date = v_date
      where e.status = 'active'
        and coalesce(e.is_deleted, false) = false
        and not public.is_employee_attendance_exempt(e.id) -- 0532: استبعاد المعفيين
        and (
          not public.is_employee_isolated(e.id)
          or public.can_view_isolated_employee(e.id)
        ) -- 0572: إخفاء المعزول عن غير المرئين له
        and (p_department_id is null or e.department_id = p_department_id)
        and (p_branch_id is null or e.branch_id = p_branch_id)
        and (
          p_manager_id is null or exists (
            select 1 from public.manager_relations mr2
            where mr2.employee_id = e.id
              and mr2.manager_employee_id = p_manager_id
              and mr2.effective_from <= now()
              and (mr2.effective_to is null or mr2.effective_to > now())
          )
        )
    ),
    classified as (
      select *,
        case
          when on_leave then 'on_leave'
          when assignment_type is not null then 'assignment'
          when att_status = 'present' and coalesce(late_minutes, 0) > 0 then 'late'
          when att_status = 'present' then 'present'
          when att_status = 'late' then 'late'
          when last_check_out is not null and coalesce(early_leave_minutes, 0) > 0 then 'left_early'
          when last_check_out is not null then 'checked_out'
          when att_status = 'absent' then 'absent'
          when extract(isodow from v_date) = 5 then 'weekend'
          else 'not_yet'
        end as derived_status
      from base
    )
    select jsonb_agg(jsonb_build_object(
      'id', id,
      'name', full_name_ar,
      'employeeCode', employee_code,
      'avatarUrl', photo_url,
      'jobTitle', job_title,
      'department', department,
      'managerName', manager_name,
      'status', derived_status,
      'attStatus', att_status,
      'firstCheckIn', first_check_in,
      'lastCheckOut', last_check_out,
      'lateMinutes', late_minutes,
      'earlyLeaveMinutes', early_leave_minutes,
      'onLeave', on_leave,
      'assignmentType', assignment_type
    ) order by full_name_ar)
    from classified
  ), '[]'::jsonb);
end;
$function$;

-- ===== get_my_mobile_team(p_limit integer) =====
CREATE OR REPLACE FUNCTION public.get_my_mobile_team(p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_manager_id uuid := public.current_employee_id();
  v_result jsonb;
begin
  if v_manager_id is null then
    raise exception 'لا يوجد ملف موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  if not (
    public.current_is_full_access()
    or public.has_any_permission(array[
      'people.employee.read',
      'requests.request.approve',
      'performance.kpi.manager_assess',
      'attendance.record.read'
    ])
    or exists (
      select 1 from public.manager_relations mr
      where mr.manager_employee_id = v_manager_id
        and mr.relation_type = 'primary'
        and mr.effective_from <= (now() at time zone 'Africa/Cairo')::date
        and (mr.effective_to is null or mr.effective_to >= (now() at time zone 'Africa/Cairo')::date)
    )
  ) then
    raise exception 'manager workspace is not allowed' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', e.id,
    'employeeCode', e.employee_code,
    'name', e.full_name_ar,
    'photoUrl', e.photo_url,
    'jobTitle', jt.name,
    'department', d.name,
    'team', tm.name,
    'attendanceStatus', ad.status,
    'lateMinutes', coalesce(ad.late_minutes, 0),
    'firstCheckIn', ad.first_check_in,
    'pendingRequests', (
      select count(*) from public.requests r
      where r.employee_id = e.id and r.status = 'pending'
    ),
    'kpiStage', (
      select ke.current_stage
      from public.kpi_evaluations ke
      join public.kpi_cycles kc on kc.id = ke.cycle_id
      where ke.employee_id = e.id
      order by kc.period_month desc, ke.created_at desc
      limit 1
    )
  ) order by e.full_name_ar), '[]'::jsonb)
  into v_result
  from (
    select child.*
    from public.manager_relations mr
    join public.employees child on child.id = mr.employee_id
    where mr.manager_employee_id = v_manager_id
      and mr.relation_type = 'primary'
      and mr.effective_from <= (now() at time zone 'Africa/Cairo')::date
      and (mr.effective_to is null or mr.effective_to >= (now() at time zone 'Africa/Cairo')::date)
      and child.is_active = true
      and child.is_deleted = false
      and (
        not public.is_employee_isolated(child.id)
        or public.can_view_isolated_employee(child.id)
      ) -- 0572: المدير يرى مرؤوسه المعزول، ولا يرى معزولاً غير مرئي له
    order by child.full_name_ar
    limit greatest(1, least(coalesce(p_limit, 100), 200))
  ) e
  left join public.job_titles jt on jt.id = e.job_title_id
  left join public.departments d on d.id = e.department_id
  left join public.teams tm on tm.id = e.team_id
  left join public.attendance_daily ad on ad.employee_id = e.id and ad.work_date = (now() at time zone 'Africa/Cairo')::date;

  return v_result;
end;
$function$;

-- ===== get_mobile_org_chart() =====
CREATE OR REPLACE FUNCTION public.get_mobile_org_chart()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_user_id uuid := auth.uid();
  v_result  jsonb;
begin
  if v_user_id is null then
    raise exception 'غير مصرح' using errcode = 'P0001';
  end if;

  -- 0572: بوابة الهيكل — موظف العيادات وغير المرخّص لهم لا يطّلعون عليه.
  if public.employee_blocks_inbound_alerts(public.current_employee_id())
     or not (
       public.current_can_view_all_employees()
       or public.has_permission('organization.org_chart.read')
     ) then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;

  with recursive dept_tree as (
    select d.id, d.name, d.parent_id, d.manager_id,
           0 as depth, array[d.id] as path
    from departments d
    where d.parent_id is null
    union all
    select c.id, c.name, c.parent_id, c.manager_id,
           t.depth + 1, t.path || c.id
    from departments c
    join dept_tree t on c.parent_id = t.id
    where not c.id = any(t.path)
  ),
  emp_data as (
    select
      e.id,
      e.full_name_ar,
      e.employee_code,
      coalesce(jt.name, jt.name_en, '') as job_title,
      e.photo_url,
      e.department_id,
      coalesce(d.name, '') as department_name,
      d.manager_id as dept_manager_id,
      e.is_active,
      e.status
    from employees e
    left join job_titles jt on jt.id = e.job_title_id
    left join departments d on d.id = e.department_id
    where e.is_active = true
      and e.is_deleted = false
      and e.status in ('active', 'probation_failed', 'onboarding')
      and (
        not public.is_employee_isolated(e.id)
        or public.can_view_isolated_employee(e.id)
      ) -- 0572
  )
  select jsonb_build_object(
    'departments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', dt.id,
        'name', dt.name,
        'parentId', dt.parent_id,
        'managerId', dt.manager_id,
        'depth', dt.depth
      ) order by dt.path)
      from dept_tree dt
    ), '[]'::jsonb),
    'employees', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', ed.id,
        'fullNameAr', ed.full_name_ar,
        'employeeCode', ed.employee_code,
        'jobTitle', ed.job_title,
        'photoUrl', ed.photo_url,
        'departmentId', ed.department_id,
        'departmentName', ed.department_name,
        'isDeptManager', ed.dept_manager_id = ed.id
      ) order by (ed.dept_manager_id = ed.id) desc, ed.full_name_ar)
      from emp_data ed
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$function$;

-- ===== get_dispute_participant_directory(p_search text, p_limit integer) =====
CREATE OR REPLACE FUNCTION public.get_dispute_participant_directory(p_search text DEFAULT NULL::text, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_search text := NULLIF(trim(p_search), '');
  v_limit integer := GREATEST(1, LEAST(COALESCE(p_limit, 100), 200));
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'ERR_UNAUTHENTICATED' USING ERRCODE = '28000';
  END IF;

  IF NOT (
    public.current_is_full_access()
    OR public.has_permission('relations.case.manage')
    OR public.has_permission('disputes.portal.access')
  ) THEN
    RAISE EXCEPTION 'ERR_FORBIDDEN: صلاحية غير كافية للوصول لدليل المشاركين'
      USING ERRCODE = '42501';
  END IF;

  RETURN (
    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id', q.id,
          'name', q.full_name_ar,
          'employeeCode', q.employee_code,
          'department', q.department
        )
        ORDER BY q.full_name_ar
      ),
      '[]'::jsonb
    )
    FROM (
      SELECT e.id, e.full_name_ar, e.employee_code, d.name AS department
      FROM public.employees e
      LEFT JOIN public.departments d ON d.id = e.department_id
      WHERE e.status = 'active'
        AND e.is_active
        AND NOT e.is_deleted
        AND (
          NOT public.is_employee_isolated(e.id)
          OR public.can_view_isolated_employee(e.id)
        ) -- 0572
        AND e.id IS DISTINCT FROM public.current_employee_id()
        AND (
          v_search IS NULL
          OR e.full_name_ar ILIKE '%' || public.escape_ilike(v_search) || '%'
          OR e.employee_code ILIKE '%' || public.escape_ilike(v_search) || '%'
        )
      ORDER BY e.full_name_ar
      LIMIT v_limit
    ) q
  );
END
$function$;

-- ===== _submit_request_for(p_employee_id uuid, p_request_type text, ...) =====
CREATE OR REPLACE FUNCTION public._submit_request_for(p_employee_id uuid, p_request_type text, p_workflow_definition_id uuid DEFAULT NULL::uuid, p_manager_employee_id uuid DEFAULT NULL::uuid, p_title text DEFAULT NULL::text, p_reason text DEFAULT NULL::text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me             uuid := public.current_employee_id();
  v_def            public.workflow_definitions;
  v_due            timestamptz;
  v_esc            timestamptz;
  v_row            public.requests;
  v_first_approver uuid;
  v_label          text;
begin
  if p_employee_id is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  if p_request_type not in (
    'leave','mission','convoy','fundraising',
    'late_permit','early_permit','attendance_correction',
    'attendance_permit','generic'
  ) then
    raise exception 'invalid request_type: %', p_request_type using errcode = '22023';
  end if;

  -- إذا كان المدير مسجلاً كنفس الموظف أو فارغاً، نحل معتمداً أعلى تلقائياً
  if p_manager_employee_id is null or p_manager_employee_id = p_employee_id then
    p_manager_employee_id := public.resolve_request_approver(p_employee_id);
  end if;

  -- التعرف التلقائي لتعريف سير العمل
  if p_workflow_definition_id is not null then
    select * into v_def from public.workflow_definitions where id = p_workflow_definition_id;
  else
    -- 0572: مسار الإدارة الطبية يبقى للعزل الإداري (قسم is_isolated) فقط؛
    -- العزل بالدور (clinic-staff) لا يغيّر مسار طلبات موظفي العيادات.
    if exists (
      select 1 from public.employees e
      join public.departments d on d.id = e.department_id
      where e.id = p_employee_id and d.is_isolated
    ) then
      select * into v_def from public.workflow_definitions
        where code = 'medical_leave_v1' and request_type = p_request_type and is_active = true
        order by version desc limit 1;
    end if;
    if v_def.id is null then
      select * into v_def from public.workflow_definitions
        where request_type = p_request_type and is_default = true and is_active = true
        order by version desc limit 1;
    end if;
  end if;

  if v_def.id is not null then
    v_due := now() + make_interval(hours => coalesce(v_def.default_due_hours, 48));
    if v_def.auto_escalate then v_esc := v_due; end if;
  else
    v_due := now() + interval '48 hours';
  end if;

  insert into public.requests (
    request_type, employee_id, manager_employee_id, workflow_definition_id,
    status, workflow_status, title, reason, decision_due_at, escalation_deadline,
    payload, created_by
  ) values (
    p_request_type, p_employee_id, p_manager_employee_id, v_def.id,
    'pending', 'submitted', p_title, p_reason, v_due, v_esc,
    coalesce(p_payload, '{}'::jsonb), auth.uid()
  )
  returning * into v_row;

  -- إنشاء خطوات سير العمل
  if v_def.id is not null then
    insert into public.request_steps (
      request_id, workflow_step_id, step_order, name_ar, step_type,
      assignee_employee_id, assignee_role_slug, status, sla_hours,
      due_at, escalation_deadline, created_by
    )
    select
      v_row.id, ws.id, ws.step_order, ws.name_ar, ws.step_type,
      case
        when ws.approver_type = 'specific_employee' then ws.approver_employee_id
        when ws.approver_type in ('direct_manager','department_manager') then p_manager_employee_id
        else null
      end,
      ws.approver_role_slug,
      case when ws.step_order = 1 then 'active' else 'pending' end,
      ws.sla_hours,
      case when ws.step_order = 1
           then now() + make_interval(hours => coalesce(ws.sla_hours, 48)) end,
      case when ws.step_order = 1 and ws.escalate_after_hours is not null
           then now() + make_interval(hours => ws.escalate_after_hours) end,
      auth.uid()
    from public.workflow_steps ws
    where ws.definition_id = v_def.id and ws.is_active = true
    order by ws.step_order;

    insert into public.workflow_instances (
      definition_id, request_id, definition_version, status, current_step_order, created_by
    ) values (
      v_def.id, v_row.id, coalesce(v_def.version, 1), 'running', 1, auth.uid()
    );
  end if;

  insert into public.request_actions (
    request_id, actor_employee_id, action, to_status, comment, created_by
  ) values (v_row.id, coalesce(v_me, p_employee_id), 'submit', 'pending', p_reason, auth.uid());

  v_label := format('%s — %s',
    public.request_type_label(v_row.request_type),
    coalesce(v_row.title, ''));

  -- إشعار المدير المعتمد للخطوة النشطة
  select s.assignee_employee_id into v_first_approver
  from public.request_steps s
  where s.request_id = v_row.id and s.status = 'active'
  order by s.step_order limit 1;

  if v_first_approver is null then
    v_first_approver := v_row.manager_employee_id;
  end if;

  if v_first_approver is not null and v_first_approver <> v_row.employee_id then
    perform public.notify_employee(
      v_first_approver,
      'طلب جديد بانتظار مراجعتك',
      v_label,
      'request', 'high', 'request', v_row.id,
      jsonb_build_object(
        'requestType', v_row.request_type,
        'requestId', v_row.id,
        'employeeId', v_row.employee_id,
        'deepLink', '/requests/' || v_row.id
      )
    );
  end if;

  return v_row;
end;
$function$;

-- ─── 4) صلاحيات الدوال الجديدة ───
revoke all on function public.current_can_view_all_employees() from public, anon;
revoke all on function public.employee_blocks_inbound_alerts(uuid) from public, anon;
revoke all on function public.notifications_block_clinic_staff() from public, anon;
grant execute on function public.current_can_view_all_employees() to authenticated, service_role;
grant execute on function public.employee_blocks_inbound_alerts(uuid) to authenticated, service_role;

commit;

notify pgrst, 'reload schema';
