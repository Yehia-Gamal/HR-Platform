-- 0435: توحيد أنواع كيانات الإشعارات الفعلية المخزّنة في resolve_mobile_action_target
--
-- الخلفية: تطبيق الموبايل يقبل أنواعاً محددة فقط (request/kpi/decision/...)، بينما
-- تُنشئ دوال الإشعارات (notify_employee/notify_user/insert المباشر) صفوفاً بـ
-- entity_type مختلفة تماماً عن القائمة المدعومة:
--   live_location_requests (الجمع) — 0017/0067/0124/0242/0316/0319/0342
--   attendance_daily (0319/0416), attendance_event (0389),
--   attendance_corrections (0316), overtime_records (0316), work_rosters (0316)
--   requests (0062), dispute_case (0164)
-- النتيجة: الضغط على إشعار من إشعار النظام أو من داخل التطبيق كان يفشل
-- بخطأ 'unsupported action kind' أو لا يفتح أي مسار إطلاقاً.
--
-- هذا الترحيل يوسّع خريطة التطبيع في resolve_mobile_action_target لتغطي
-- الأنواع الفعلية المخزّنة، مع الإبقاء على التخويل لكل نوع عبر الدالة الأم
-- get_mobile_action_target. الأنواع بلا صفحة موبايل (kpi_appeals,
-- work_assignments, break_glass_requests, offboarding_cases, privacy_requests,
-- service_requests, wellbeing_requests, document_signature_requests,
-- employee_device, public_holiday, role, daily_reports) تبقى غير مدعومة
-- ويُعالجها التطبيق كإشعارات معلوماتية (تعليم مقروء فقط).

begin;

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
  -- location/location_request/live_location/live_location_request →
  --   live_location_request (بالإضافة إلى الصيغة الجمعية live_location_requests)
  -- attendance_alert/punch_reminder/attendance/attendance_daily/
  --   attendance_event/attendance_corrections/overtime_records/work_rosters → attendance
  -- kpi_evaluation → kpi, request_decision/requests → request, dispute_case → dispute
  v_resolved_kind := case v_kind
    when 'location' then 'live_location_request'
    when 'location_request' then 'live_location_request'
    when 'live_location_request' then 'live_location_request'
    when 'live_location' then 'live_location_request'
    when 'live_location_requests' then 'live_location_request'
    when 'attendance_alert' then 'attendance'
    when 'punch_reminder' then 'attendance'
    when 'attendance' then 'attendance'
    when 'attendance_daily' then 'attendance'
    when 'attendance_event' then 'attendance'
    when 'attendance_corrections' then 'attendance'
    when 'overtime_records' then 'attendance'
    when 'work_rosters' then 'attendance'
    when 'request' then 'request'
    when 'requests' then 'request'
    when 'request_decision' then 'request'
    when 'kpi' then 'kpi'
    when 'kpi_evaluation' then 'kpi'
    when 'decision' then 'decision'
    when 'dispute' then 'dispute'
    when 'dispute_case' then 'dispute'
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
  'واجهة RPC لتحليل إجراءات الإشعارات — يطبّع كل أسماء entity_type المخزّنة (0435) مع تخويل لكل نوع.';

revoke execute on function public.resolve_mobile_action_target(text, text) from public, anon;
grant execute on function public.resolve_mobile_action_target(text, text) to authenticated;

notify pgrst, 'reload schema';

commit;
