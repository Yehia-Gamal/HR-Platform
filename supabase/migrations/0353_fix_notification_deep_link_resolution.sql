-- 0353: إصلاح دقة الروابط العميقة للإشعارات (recognition / live_location / الطالب)
--
-- ثلاث نقاط كانت تجعل النقر على إشعار يفتح صفحة خطأ/فارغة بدل محتوى الإشعار:
--   1) get_mobile_feed_item كان يدعم announcement/decision فقط، بينما
--      resolve_mobile_action_target يعيد mobileRoute='feed_detail' لأنواع
--      recognition أيضاً → فتح إشعار التقدير كان يفشل بخطأ 'unsupported feed item kind'.
--   2) resolve_mobile_action_target لا يطبّع kind='live_location' (المستعمل في
--      migration 0319 للإشعارات الاستباقية) → كان يفشل بخطأ 'unsupported action kind'.
--   3) get_my_live_location_requests يعيد طلبات الموظف المستهدَف فقط، فيفشل
--      الطالب (المدير/التنفيذي) عند فتح إشعار طلب الموقع عبر deep link
--      بخطأ 'location_request_not_available' رغم أن resolve_mobile_action_target
--      يصرّح له بالوصول.

begin;

-- ─── 1) get_mobile_feed_item: دعم recognition ────────────────────────────────
create or replace function public.get_mobile_feed_item(p_kind text, p_item_id uuid)
returns jsonb
language plpgsql
stable
security definer
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
  elsif lower(p_kind) = 'recognition' then
    -- تقدير: ظاهر للمستلم والمرسِل وللعموم إذا is_public، ولبقية الصلاحيات.
    select jsonb_build_object(
      'id', r.id, 'kind', 'recognition', 'title', r.title, 'body', coalesce(r.message,''),
      'category', r.recognition_type, 'priority', coalesce(r.metadata->>'priority','normal'),
      'status', 'published',
      'requiresAcknowledgement', false,
      'myAcknowledged', false,
      'publishedAt', r.awarded_at, 'expiresAt', null,
      'imageUrl', null,
      'postType', 'recognition',
      'authorName', coalesce(nom.full_name_ar, 'الإدارة'),
      'authorPhotoUrl', null,
      'attachments', '[]'::jsonb
    ) into v_result
    from public.recognitions r
    left join public.employees nom on nom.id = r.nominated_by
    where r.id = p_item_id
      and (
        r.is_public
        or r.recipient_employee_id = public.current_employee_id()
        or r.nominated_by = public.current_employee_id()
        or public.current_is_full_access()
        or public.has_any_permission(array['recognition.read','recognition.manage'])
      );
  else
    raise exception 'unsupported feed item kind' using errcode='22023';
  end if;
  if v_result is null then raise exception 'feed item not found or not visible' using errcode='P0002'; end if;
  return v_result;
end;
$$;

comment on function public.get_mobile_feed_item(text, uuid) is
  'محتوى إعلان/قرار/تقدير لصفحة التفاصيل في الموبايل — مع تخويل لكل نوع. (0353)';

-- ─── 2) resolve_mobile_action_target: تطبيع live_location (0319) ─────────────
create or replace function public.resolve_mobile_action_target(
  p_action_id text,
  p_kind text
)
returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare
  v_kind text := lower(trim(coalesce(p_kind, '')));
  v_raw text := trim(coalesce(p_action_id, ''));
  v_uuid uuid;
  v_req public.live_location_requests;
  v_resolved_kind text;
begin
  -- تطبيع الأسماء المترادفة القادمة من الإشعارات ومن تطبيق الموبايل:
  -- location/location_request/live_location/live_location_request → live_location_request
  -- attendance_alert/punch_reminder → attendance
  -- kpi_evaluation → kpi, request_decision → request
  v_resolved_kind := case v_kind
    when 'location' then 'live_location_request'
    when 'location_request' then 'live_location_request'
    when 'live_location_request' then 'live_location_request'
    when 'live_location' then 'live_location_request'
    when 'attendance_alert' then 'attendance'
    when 'punch_reminder' then 'attendance'
    when 'attendance' then 'attendance'
    when 'request' then 'request'
    when 'request_decision' then 'request'
    when 'kpi' then 'kpi'
    when 'kpi_evaluation' then 'kpi'
    when 'decision' then 'decision'
    when 'dispute' then 'dispute'
    when 'task' then 'task'
    when 'announcement' then 'announcement'
    when 'recognition' then 'recognition'
    else null
  end;

  if v_resolved_kind is null then
    raise exception 'unsupported action kind' using errcode = '22023';
  end if;

  -- strip prefix إن وُجد (kind-uuid)
  if position(v_resolved_kind || '-' in lower(v_raw)) = 1 then
    v_raw := substring(v_raw from length(v_resolved_kind) + 2);
  end if;

  begin
    v_uuid := v_raw::uuid;
  exception when others then
    raise exception 'invalid action identifier' using errcode = '22023';
  end;

  -- live_location_request: تخويل خاص (لا يمر عبر get_mobile_action_target)
  if v_resolved_kind = 'live_location_request' then
    select * into v_req from public.live_location_requests where id = v_uuid;
    if not found then
      raise exception 'action target not found' using errcode = 'P0002';
    end if;
    if not (
      v_req.employee_id = public.current_employee_id()
      or v_req.requested_by = public.current_employee_id()
      or public.current_is_full_access()
      or public.can_access_employee(v_req.employee_id, 'live_location.view_response')
    ) then
      raise exception 'action target access denied' using errcode = '42501';
    end if;

    return jsonb_build_object(
      'kind', v_resolved_kind,
      'recordId', v_uuid,
      'mobileRoute', 'live_location_request'
    );
  end if;

  -- بقية الأنواع: المرور عبر الدالة الأم التي تحمل التخويل المناسب
  return public.get_mobile_action_target(v_resolved_kind || '-' || v_uuid::text, v_resolved_kind);
end;
$$;

comment on function public.resolve_mobile_action_target(text,text) is
  'واجهة RPC لتحليل إجراءات الإشعارات — يقبل كل أنواع deepLink مع تطبيع المترادفات وتخويل لكل نوع. (0353)';

-- ─── 3) get_live_location_request_by_id: فتح الطلب بالمعرّف للطرفين ─────────
-- يسمح للمستهدَف (الموظف) وللطالب (المدير/التنفيذي) ولأصحاب الصلاحية بفتح
-- طلب موقع محدد عبر deep link من الإشعار — بدل الاعتماد على آخر 100 طلب
-- التي يعيدها get_my_live_location_requests (للمستهدَف فقط).
create or replace function public.get_live_location_request_by_id(p_request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_result jsonb;
begin
  select jsonb_build_object(
    'id', q.id, 'requesterName', q.requester_name, 'reason', q.reason,
    'status', q.effective_status, 'mode', q.mode,
    'durationMinutes', q.duration_minutes, 'requestedAt', q.requested_at,
    'expiresAt', q.expires_at
  ) into v_result
  from (
    select r.id, req.full_name_ar requester_name, r.reason,
      case when r.status in ('pending','accepted','active') and r.expires_at<now() then 'expired' else r.status end effective_status,
      coalesce(r.metadata->>'mode','snapshot') mode, r.duration_minutes, r.requested_at, r.expires_at
    from public.live_location_requests r
    left join public.employees req on req.id = r.requested_by
    where r.id = p_request_id
      and (
        r.employee_id = public.current_employee_id()
        or r.requested_by = public.current_employee_id()
        or public.current_is_full_access()
        or public.can_access_employee(r.employee_id, 'live_location.view_response')
      )
  ) q;

  if v_result is null then
    raise exception 'location request not found or not visible' using errcode = 'P0002';
  end if;
  return v_result;
end;
$$;

comment on function public.get_live_location_request_by_id(uuid) is
  'جلب طلب موقع محدد بالمعرّف للمستهدَف أو الطالب أو أصحاب الصلاحية — لفتح الإشعار عبر deep link. (0353)';

revoke execute on function public.get_mobile_feed_item(text, uuid) from public, anon;
grant execute on function public.get_mobile_feed_item(text, uuid) to authenticated;

revoke execute on function public.resolve_mobile_action_target(text, text) from public, anon;
grant execute on function public.resolve_mobile_action_target(text, text) to authenticated;

revoke execute on function public.get_live_location_request_by_id(uuid) from public, anon;
grant execute on function public.get_live_location_request_by_id(uuid) to authenticated;

notify pgrst, 'reload schema';

commit;
