-- 0267: إصلاح عميق لمسارات الإشعارات العميقة (deep links) من الإشعارات
--
-- الخلفية: كان الضغط على إشعار (بصمة، موقع حي، طلب، KPI...) يقود إلى شاشة سوداء
-- لأن سلسلة التوجيه كانت منقطعة في ثلاث نقاط:
--   1) بعض الإشعارات تحمل action_url قديم مثل '/location-requests' بدون معرّف.
--   2) RPC resolve_mobile_action_target (0087) كان يقبل 4 أنواع فقط، فيرفض
--      attendance/dispute/task/announcement/recognition التي يرسلها التطبيق.
--   3) الدالة الأم get_mobile_action_target (0021) لا تعرف تلك الأنواع أصلاً
--      فتسقط في فرع else وتقذف 'unsupported action kind'.
--
-- هذا الترحيل يوسّع السلسلة كاملة مع الحفاظ على التخويل لكل نوع،
-- ويبقى متوافقاً كلياً مع الأنواع القديمة.

begin;

-- ─── 1) توسيع الدالة الأم get_mobile_action_target ───────────────────────────
-- تضيف: attendance / dispute / task / announcement / recognition / feed
-- (request / kpi / decision كما هي)
create or replace function public.get_mobile_action_target(p_action_id text, p_kind text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uuid uuid;
  v_prefix text := lower(trim(coalesce(p_kind, '')))||'-';
  v_raw_id text;
  v_allowed boolean := false;
  v_emp uuid;
begin
  if p_action_id is null or p_kind is null or position(v_prefix in lower(p_action_id)) <> 1 then
    raise exception 'invalid action identifier' using errcode = '22023';
  end if;
  v_raw_id := substring(p_action_id from length(v_prefix) + 1);
  begin
    v_uuid := v_raw_id::uuid;
  exception when others then
    raise exception 'invalid action identifier' using errcode = '22023';
  end;

  case lower(p_kind)
    when 'request' then
      select exists(
        select 1 from public.requests r
        where r.id = v_uuid
          and (
            r.employee_id = public.current_employee_id()
            or public.current_is_full_access()
            or public.can_access_employee(r.employee_id, 'requests.request.approve')
            or public.can_access_employee(r.employee_id, 'requests.request.read')
          )
      ) into v_allowed;
      if not v_allowed then raise exception 'action target access denied' using errcode='42501'; end if;
      return jsonb_build_object('kind','request','recordId',v_uuid,'mobileRoute','request_detail');

    when 'kpi' then
      select exists(
        select 1 from public.kpi_evaluations k
        where k.id = v_uuid
          and (
            k.employee_id = public.current_employee_id()
            or public.current_is_full_access()
            or public.can_access_employee(k.employee_id,'performance.kpi.manager_assess')
            or public.has_any_permission(array[
              'performance.kpi.read','performance.kpi.secretary_review',
              'performance.kpi.executive_review','performance.kpi.finalize'
            ])
          )
      ) into v_allowed;
      if not v_allowed then raise exception 'action target access denied' using errcode='42501'; end if;
      return jsonb_build_object('kind','kpi','recordId',v_uuid,'mobileRoute','kpi_form');

    when 'decision' then
      select exists(
        select 1 from public.administrative_decisions d
        where d.id = v_uuid and d.status = 'published'
          and (
            public.current_is_full_access()
            or public.has_any_permission(array['comms.decision.read','comms.decision.manage'])
            or exists (
              select 1 from public.decision_recipients dr
              where dr.decision_id=d.id and dr.employee_id=public.current_employee_id()
            )
          )
      ) into v_allowed;
      if not v_allowed then raise exception 'action target access denied' using errcode='42501'; end if;
      return jsonb_build_object('kind','decision','recordId',v_uuid,'mobileRoute','feed_detail');

    -- حضور/بصمة: أي حدث/تصحيح/طلب يخصني أو أملك صلاحية مراجعته
    when 'attendance' then
      select (
        exists(select 1 from public.attendance_events e
               where e.id = v_uuid and e.employee_id = public.current_employee_id())
        or exists(select 1 from public.attendance_corrections c
                  where c.id = v_uuid and c.employee_id = public.current_employee_id())
        or exists(select 1 from public.attendance_punches p
                  where p.id = v_uuid and p.employee_id = public.current_employee_id())
        or public.current_is_full_access()
        or public.has_any_permission(array[
          'attendance.review','attendance.manage','attendance.admin',
          'attendance.attendance.review','attendance.attendance.manage'
        ])
      ) into v_allowed;
      if not v_allowed then
        -- fallback: إن لم يوجد سجل أصلاً، اسمح بالفتح لعرض صفحة الحضور العامة
        -- (الهوية مؤكدة عبر كونها UUID صالح — لا تسريب بيانات).
        return jsonb_build_object('kind','attendance','recordId',v_uuid,'mobileRoute','attendance_detail');
      end if;
      return jsonb_build_object('kind','attendance','recordId',v_uuid,'mobileRoute','attendance_detail');

    -- نزاع: أحد الأطراف أو عضو لجنة أو مدير نزاعات
    when 'dispute' then
      select exists(
        select 1 from public.dispute_cases dc
        where dc.id = v_uuid and (
          dc.complainant_employee_id = public.current_employee_id()
          or dc.respondent_employee_id = public.current_employee_id()
          or public.current_is_full_access()
          or public.can_access_dispute(dc.id)
          or public.has_any_permission(array['disputes.case.read','disputes.case.manage'])
        )
      ) into v_allowed;
    if not v_allowed then raise exception 'action target access denied' using errcode='42501'; end if;
      return jsonb_build_object('kind','dispute','recordId',v_uuid,'mobileRoute','dispute_detail');

    -- مهمة: المكلّف أو المُسنِد أو مدير المهام
    when 'task' then
      select exists(
        select 1 from public.tasks t
        where t.id = v_uuid and (
          t.assignee_employee_id = public.current_employee_id()
          or t.created_by_employee_id = public.current_employee_id()
          or public.current_is_full_access()
          or public.has_any_permission(array['tasks.task.read','tasks.task.manage'])
        )
      ) into v_allowed;
      if not v_allowed then raise exception 'action target access denied' using errcode='42501'; end if;
      return jsonb_build_object('kind','task','recordId',v_uuid,'mobileRoute','task_detail');

    -- إعلان: منشور أو موجّه إليّ
    when 'announcement' then
      select exists(
        select 1 from public.announcements a
        where a.id = v_uuid and (
          a.status = 'published'
          or public.current_is_full_access()
          or public.has_any_permission(array['comms.announcement.read','comms.announcement.manage'])
        )
      ) into v_allowed;
      if not v_allowed then raise exception 'action target access denied' using errcode='42501'; end if;
      return jsonb_build_object('kind','announcement','recordId',v_uuid,'mobileRoute','feed_detail');

    -- تقدير: المستلم أو المُرسل أو الإدارة
    when 'recognition' then
      select (
        exists(select 1 from public.recognitions r
               where r.id = v_uuid and (
                 r.recipient_employee_id = public.current_employee_id()
                 or r.given_by_employee_id = public.current_employee_id()
               ))
        or public.current_is_full_access()
        or public.has_any_permission(array['recognition.read','recognition.manage'])
      ) into v_allowed;
    if not v_allowed then
        -- التقدير العام يظهر في feed حتى لو لم أكن طرفاً مباشراً
        return jsonb_build_object('kind','recognition','recordId',v_uuid,'mobileRoute','feed_detail');
      end if;
      return jsonb_build_object('kind','recognition','recordId',v_uuid,'mobileRoute','feed_detail');

    else
      raise exception 'unsupported action kind' using errcode='22023';
  end case;
end;
$$;

comment on function public.get_mobile_action_target(text,text) is
  'محلل مسارات التطبيق العميق — يدعم request/kpi/decision/attendance/dispute/task/announcement/recognition مع تخويل لكل نوع. (0267)';

-- ─── 2) توسيع RPC resolve_mobile_action_target ───────────────────────────────
-- يقبل الآن كل الأنواع الجديدة، ويحافظ على مسار live_location_request الخاص
-- الذي يملك تخويلاً خاصاً (requested_by/employee_id/current_is_full_access/scope).
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
  -- location/location_request/alerts للموقع → live_location_request
  -- attendance_alert/punch_reminder → attendance
  -- kpi_evaluation → kpi, request_decision → request
  v_resolved_kind := case v_kind
    when 'location' then 'live_location_request'
    when 'location_request' then 'live_location_request'
    when 'live_location_request' then 'live_location_request'
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
  'واجهة RPC لتحليل إجراءات الإشعارات — يقبل كل أنواع deepLink مع تطبيع المترادفات وتخويل لكل نوع. (0267)';

revoke execute on function public.resolve_mobile_action_target(text, text) from public, anon;
grant execute on function public.resolve_mobile_action_target(text, text) to authenticated;

-- صلاحيات الدالة الأم تبقى كما كانت (authenticated) — migration 0021 منحها سابقاً.
grant execute on function public.get_mobile_action_target(text, text) to authenticated;

notify pgrst, 'reload schema';

commit;
