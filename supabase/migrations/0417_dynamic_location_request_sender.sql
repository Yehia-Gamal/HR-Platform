-- 0414: جعل جسم إشعار طلب الموقع ديناميكياً — يستخدم اسم المرسل الفعلي
--
-- المشكلة: كان جسم الإشعار ثابتاً: "السكرتير التنفيذي أو المدير التنفيذي يطلب موقعك الآن"
-- بصرف النظر عن من أرسل الطلب فعلياً.
--
-- الإصلاح: نستخرج اسم الموظف المرسل (v_me) ونضعه في الجسم،
-- بنفس نمط share_my_location_proactively (0319).
-- الـ fallback "الإدارة" يبقى محايداً ولا يذكر المدير التنفيذي صراحةً.

begin;
  create or replace function public.request_live_location(
    p_employee_id uuid,
    p_purpose text default 'verification',
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
    v_requester_name text;
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

    v_deep_link := 'https://ahla-shabab-management-os.vercel.app/action/live_location_request/' || v_req.id::text;

    -- 0414: استخرج اسم المرسل الفعلي بدلاً من النص الثابت.
    select full_name_ar into v_requester_name
      from public.employees where id = v_me;

    select user_id into v_target_user from public.employees where id = p_employee_id;
    if v_target_user is not null then
      insert into public.notifications(
        recipient_user_id, recipient_employee_id, title, body, category, priority,
        action_url, entity_type, entity_id, metadata, created_by)
      values(
        v_target_user, p_employee_id, 'طلب تحديد موقع فوري',
        format('%s يطلب موقعك الآن. يرجى الاستجابة.',
          coalesce(v_requester_name, 'الإدارة')),
        'system', 'urgent',
        v_deep_link,
        'live_location_request', v_req.id, jsonb_build_object(
          'fullScreen', true, 'kind', 'live_location_request', 'requestId', v_req.id,
          'entityId', v_req.id, 'channel', 'urgent_location_v6',
          'deepLink', v_deep_link, 'requesterName', coalesce(v_requester_name, 'الإدارة')),
        auth.uid());
    end if;

    perform public.log_audit_event(
      'live_location.requested', 'security', 'info',
      'live_location_requests', v_req.id, 'تم طلب الموقع اللحظي', null,
      jsonb_build_object('mode', 'snapshot', 'employeeId', p_employee_id, 'requestId', v_req.id,
        'requesterName', coalesce(v_requester_name, 'الإدارة')));
    return v_req;
  end $$;

  revoke execute on function public.request_live_location(uuid, text, text) from public, anon;
  grant execute on function public.request_live_location(uuid, text, text) to authenticated;

  -- أعد تحميل مخطط PostgREST ليلتقط التغيير.
  notify pgrst, 'reload schema';
commit;
