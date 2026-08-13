-- ============================================================================
-- 0398: دمج طبقة الطلبات المعلّقة (0354) مع adminOverride.leaveType (0362)
--   في النسخة النهائية من _build_attendance_statement.
--
-- السبب:
--   0354 أضاف «طبقة الطلبات المعلّقة» فوق _build_attendance_statement_v286:
--     - الأيام التي عليها طلب معلّق لا تُحتسب غياباً وتُعرض «بانتظار اعتماد…»
--       (hasPendingLeave/hasPendingMission/hasPendingConvoyFundi)
--     - حقول العرض المنسّقة (checkIn12/checkOut12/...Formatted)
--     - summary.pendingDays / absentDays المعاد حسابه
--   0362 أعاد تعريف _build_attendance_statement بعدها فوق
--     _build_attendance_statement_v266 مباشرة (نموذج 0268) لإضافة
--     adminOverride.leaveType — فعملية استبدال حذفت طبقة 0354.
--
-- الحل هنا: تعريف نهائي واحد يجمعهما معاً:
--   v286 (كل الطبقات) ← طبقة المعلّق 0354 ← حقول العرض المنسّقة
--   ← adminOverride.leaveType من جدول attendance_day_overrides.
--
-- ملاحظة: آخر تعريف يسبق هذه الـ migration هو نسخة 0362؛ ولا يوجد تعريف لاحق
--   في المستودع، فيصبح هذا التعريف هو الفعّال النهائي. تُنسخ طبقة 0354 حرفياً.
-- ============================================================================

begin;

create or replace function public._build_attendance_statement(
  p_employee_id uuid,
  p_year integer,
  p_month integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_result jsonb;
  v_days jsonb := '[]'::jsonb;
  v_day_obj jsonb;
  v_day date;
  v_ci text;
  v_co text;
  v_status text;
  v_is_absent boolean;
  v_pending_days integer := 0;
  v_absent_days integer;
  v_pending_leave boolean;
  v_pending_mission boolean;
  v_pending_convoy boolean;
begin
  v_result := public._build_attendance_statement_v286(p_employee_id, p_year, p_month);

  -- طبقة 0354: أعلام الطلبات المعلّقة + إلغاء الغياب + «بانتظار الاعتماد» +
  -- حقول العرض المنسّقة (فوق days من v286).
  for v_day_obj in select value from jsonb_array_elements(v_result->'days')
  loop
    v_day := (v_day_obj->>'date')::date;
    v_ci := v_day_obj->>'checkIn';
    v_co := v_day_obj->>'checkOut';

    v_pending_leave := exists (
      select 1 from public.requests r
      join public.leave_requests lr on lr.request_id = r.id
      where lr.employee_id = p_employee_id
        and r.status = 'pending'
        and v_day between lr.start_date and lr.end_date
    );
    v_pending_mission := exists (
      select 1 from public.requests r
      where r.employee_id = p_employee_id
        and r.request_type = 'mission'
        and r.status = 'pending'
        and v_day between (r.payload->>'startDate')::date
                      and coalesce((r.payload->>'endDate')::date, (r.payload->>'startDate')::date)
    );
    v_pending_convoy := exists (
      select 1 from public.requests r
      where r.employee_id = p_employee_id
        and r.request_type in ('convoy','fundraising')
        and r.status = 'pending'
        and v_day between (r.payload->>'startDate')::date
                      and coalesce((r.payload->>'endDate')::date, (r.payload->>'startDate')::date)
    );

    v_status := v_day_obj->>'status';
    v_is_absent := coalesce((v_day_obj->>'isAbsent')::boolean, false);

    -- يوم عليه طلب معلّق ولا تغطيه قاعدة أخرى (حضور فعلي/طلب معتمد/عطلة) → «بانتظار الاعتماد»
    if (v_pending_leave or v_pending_mission or v_pending_convoy)
       and v_is_absent
       and v_ci is null then
      v_status := case
        when v_pending_leave then 'بانتظار اعتماد إجازة'
        when v_pending_mission then 'بانتظار اعتماد مأمورية'
        else 'بانتظار اعتماد تكليف'
      end;
      v_is_absent := false;
      v_pending_days := v_pending_days + 1;
    end if;

    -- 0362: adminOverride.leaveType — إن كان v286 أخرج override لليوم.
    if (v_day_obj->'adminOverride') is not null then
      v_day_obj := jsonb_set(v_day_obj, '{adminOverride,leaveType}',
        to_jsonb((select o.leave_type from public.attendance_day_overrides o
          where o.employee_id = p_employee_id and o.work_date = v_day and o.is_active)),
        true);
    end if;

    v_day_obj := v_day_obj || jsonb_strip_nulls(jsonb_build_object(
      'checkIn12',  case when v_ci is not null and v_ci <> '' then public._fmt_time_12h(v_ci::time) else null end,
      'checkOut12', case when v_co is not null and v_co <> '' then public._fmt_time_12h(v_co::time) else null end,
      'workHoursFormatted', public._fmt_minutes_ar(
        greatest(0, round(coalesce((v_day_obj->>'workHours')::numeric, 0) * 60))::integer
      ),
      'status', v_status,
      'isAbsent', v_is_absent,
      'hasPendingLeave', v_pending_leave,
      'hasPendingMission', v_pending_mission,
      'hasPendingConvoyFundi', v_pending_convoy
    ));

    v_days := v_days || jsonb_build_array(v_day_obj);
  end loop;

  v_absent_days := (select count(*)::int
    from jsonb_array_elements(v_days) d
    where coalesce((d->>'isAbsent')::boolean, false));

  v_result := v_result || jsonb_build_object(
    'days', v_days,
    'summary', (v_result->'summary') || jsonb_build_object(
      'absentDays', v_absent_days,
      'pendingDays', v_pending_days,
      'totalWorkHoursFormatted', public._fmt_minutes_ar(
        greatest(0, round(coalesce((v_result->'summary'->>'totalWorkHours')::numeric, 0) * 60))::integer
      ),
      'totalRequiredHoursFormatted', public._fmt_minutes_ar(
        greatest(0, round(coalesce((v_result->'summary'->>'totalRequiredHours')::numeric, 0) * 60))::integer
      ),
      'totalDeficitFormatted', public._fmt_minutes_ar(
        greatest(0, coalesce((v_result->'summary'->>'totalDeficitMinutes')::integer, 0))
      ),
      'totalOvertimeFormatted', public._fmt_minutes_ar(
        greatest(0, coalesce((v_result->'summary'->>'totalOvertimeMinutes')::integer, 0))
      ),
      'totalLateFormatted', public._fmt_minutes_ar(
        greatest(0, coalesce((v_result->'summary'->>'totalLateMinutes')::integer, 0))
      ),
      'totalEarlyLeaveFormatted', public._fmt_minutes_ar(
        greatest(0, coalesce((v_result->'summary'->>'totalEarlyLeaveMinutes')::integer, 0))
      )
    )
  );

  return v_result;
end
$$;

revoke execute on function public._build_attendance_statement(uuid, integer, integer)
  from public, anon, authenticated;
grant execute on function public._build_attendance_statement(uuid, integer, integer)
  to service_role;

comment on function public._build_attendance_statement(uuid, integer, integer) is
  '0398: النسخة النهائية المدمجة — v286 (الطبقات الكاملة) + طبقة الطلبات المعلّقة 0354 (حقول منسّقة + pendingDays) + adminOverride.leaveType (0362).';

notify pgrst, 'reload schema';

commit;
