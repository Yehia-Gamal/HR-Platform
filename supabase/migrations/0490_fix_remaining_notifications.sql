-- ============================================================
-- 0490: fix remaining broken notifications missed by 0489
-- - attendance_daily self: use recipient_employee_id for employee name
-- - request bodies: join with requests table via deepLink to get clean camp/mission name
-- ============================================================

-- Helper: clean time string (same as 0489)
create or replace function public._clean_notif_time_v2(p_raw text, p_event text)
returns text language sql immutable as $$
  select case
    when p_raw is null then null
    when p_raw !~ '\uFFFD' then p_raw
    else regexp_replace(p_raw, '\uFFFD.', '') ||
      case when p_event = 'attendance_check_in' then ' ص' else ' م' end
  end;
$$;

-- ============================================================
-- 1) attendance_daily self notifications (5 rows)
-- metadata has self=true but no employeeId — use recipient_employee_id
-- ============================================================
update public.notifications n
set
  title = case (n.metadata->>'event')
    when 'attendance_check_in' then 'تم تسجيل حضورك'
    when 'attendance_check_out' then 'تم تسجيل انصرافك'
    else 'تحديث حضور'
  end,
  body = format(
    'تم تسجيل %s الساعة %s',
    case (n.metadata->>'event')
      when 'attendance_check_in' then 'حضورك'
      when 'attendance_check_out' then 'انصرافك'
      else 'حضور'
    end,
    public._clean_notif_time_v2(n.metadata->>'time', n.metadata->>'event')
  )
where n.entity_type = 'attendance_daily'
  and (n.metadata->>'self')::boolean = true
  and encode(convert_to(coalesce(n.title,''),'UTF8'),'hex') like '%efbfbd%';

-- ============================================================
-- 2) attendance_daily manager/executive notifications (if any left)
-- Use recipient_employee_id for employee name (already have join in 0489 but ensure coverage)
-- ============================================================
update public.notifications n
set
  title = case (n.metadata->>'event')
    when 'attendance_check_in' then format('وصل %s للعمل بالمجمع', coalesce(e.full_name_ar, 'موظف'))
    when 'attendance_check_out' then format('خرج %s من المجمع', coalesce(e.full_name_ar, 'موظف'))
    else 'تحديث حضور'
  end,
  body = format(
    '%s — %s الساعة %s',
    coalesce(e.full_name_ar, 'موظف'),
    case (n.metadata->>'event')
      when 'attendance_check_in' then 'دخل'
      when 'attendance_check_out' then 'انصرف'
      else 'حدث'
    end,
    public._clean_notif_time_v2(n.metadata->>'time', n.metadata->>'event')
  )
from public.employees e
where n.entity_type = 'attendance_daily'
  and ((n.metadata->>'self')::boolean is not true)
  and e.id = n.recipient_employee_id
  and encode(convert_to(coalesce(n.title,''),'UTF8'),'hex') like '%efbfbd%';

-- ============================================================
-- 3) request bodies for operations-manager-1 escalation
-- Get clean camp/mission name from requests table via deepLink request ID
-- request_type: 'mission', 'convoy', 'leave', etc. payload->>'location' has the place name
-- ============================================================
update public.notifications n
set body = format(
  '%s — ثبت في حين ما زالت وردية مفتوحة',
  coalesce(
    (select case
      when r.request_type = 'mission' then 'مأمورية'
      when r.request_type = 'convoy' then r.payload->>'location'
      when r.request_type = 'leave' then 'إجازة'
      else r.payload->>'location'
    end from public.requests r where r.id = (substring(n.metadata->>'deepLink' from '/requests/([0-9a-f-]+)'))::uuid),
    'مأمورية'
  )
)
where n.entity_type = 'request'
  and (n.metadata->>'escalation') = 'operations-manager-1'
  and encode(convert_to(coalesce(n.body,''),'UTF8'),'hex') like '%efbfbd%';

-- ============================================================
-- 4) request bodies for final_reminder escalation
-- ============================================================
update public.notifications n
set body = format(
  '%s — تحتاج قرار المدير (الأمر). الأمر المباشر قد وافق على طلب تصديق إضافي.',
  coalesce(
    (select case
      when r.request_type = 'mission' then 'مأمورية'
      when r.request_type = 'convoy' then r.payload->>'location'
      when r.request_type = 'leave' then 'إجازة'
      else r.payload->>'location'
    end from public.requests r where r.id = (substring(n.metadata->>'deepLink' from '/requests/([0-9a-f-]+)'))::uuid),
    'مأمورية'
  )
)
where n.entity_type = 'request'
  and (n.metadata->>'escalation') = 'final_reminder'
  and encode(convert_to(coalesce(n.body,''),'UTF8'),'hex') like '%efbfbd%';

-- ============================================================
-- 5) request bodies for request_approval_needed (if any left)
-- ============================================================
update public.notifications n
set body = format(
  '%s — تحتاج قرار المدير',
  case (n.metadata->>'requestType')
    when 'mission' then 'مأمورية'
    when 'leave' then 'إجازة'
    when 'device' then 'جهاز'
    when 'access' then 'صلاحية'
    else 'طلب'
  end
)
where n.entity_type = 'request'
  and (n.metadata->>'kind') = 'request_approval_needed'
  and encode(convert_to(coalesce(n.body,''),'UTF8'),'hex') like '%efbfbd%';

-- Cleanup
drop function public._clean_notif_time_v2(text, text);

-- Verification
do $$
declare
  v_bt int; v_bb int;
begin
  select count(*) into v_bt from public.notifications where encode(convert_to(coalesce(title,''),'UTF8'),'hex') like '%efbfbd%';
  select count(*) into v_bb from public.notifications where encode(convert_to(coalesce(body,''),'UTF8'),'hex') like '%efbfbd%';
  raise notice 'After 0490: broken_titles=%, broken_bodies=%', v_bt, v_bb;
end $$;