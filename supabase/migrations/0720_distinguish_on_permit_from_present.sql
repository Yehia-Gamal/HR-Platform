-- 0720: Distinguish on-permit employees from present and prevent unpunched permits from showing as present
-- ==============================================================================
-- المشكلة:
-- عند اعتماد إذن تأخير (late_permit) أو إذن عمل لموظف لم يبصم حضوراً بعد (مثل بلال محمد إبراهيم الشاكر)،
-- كان التريجر tg_request_approved_attendance_exempt ينشئ أو يحدّث سجلاً في attendance_daily
-- بالحالة 'present' رغم أن first_check_in = NULL!
-- وبالتالي كانت دالة get_attendance_day_roster تدرج الموظف في تبويب الحاضرين (category = 'present')
-- وتمنحه شارة "حاضر" بلون أخضر مع شرطات (--) لوقت الحضور والتأخير والموقع، وهو تضليل للمتابعة الإدارية.
--
-- الحل الجذري:
-- 1. إضافة 'on_permit' للحالات المسموحة في جدول attendance_daily.
-- 2. تحديث tg_request_approved_attendance_exempt بحيث لا يضع status = 'present' لمن لم يبصم حضوراً بعد،
--    بل يضعه 'on_permit' لحين بصمته الفعلية، أو يكتفي بتسجيل الاستثناء دون افتراض حضوره بالمقر.
-- 3. تحديث get_attendance_day_roster:
--    - كشف أذونات العمل وتصاريح التأخير المعتمدة والمعلقة (approved_permits / active_attendance_permits).
--    - للموظف الذي لم يسجل حضوراً ولديه إذن معتمد: تكون حالته 'on_permit' (في إذن معتمد).
--    - للموظف الذي لم يسجل حضوراً ولديه إذن معلق: تكون حالته 'pending_permit' (إذن قيد المراجعة).
--    - اشتراط first_check_in is not null في تبويب 'present' ليقتصر حصراً على من حضروا فعلياً للمقر.
--    - استبعاد أصحاب الأذونات المعتمدة والمعلقة من الغياب غير المبرر (unexcused_absent).
--    - تمرير بيانات الإذن (hasApprovedPermit, permitType, permitTitle, permitMinutes) في عناصر الروستر.
-- 4. تحديث _today_status_public لدعم 'on_permit' بالتسمية العربية 'في إذن معتمد'.
-- 5. تنظيف بأثر رجعي لأي سجل attendance_daily مسجل بحالة 'present' دون بصمة حضور ولديه إذن معتمد.
-- ==============================================================================

begin;

-- ─── 1) تحديث قيد الحالة في attendance_daily ─────────────────────────────────
alter table public.attendance_daily drop constraint if exists attendance_daily_status_check;
alter table public.attendance_daily add constraint attendance_daily_status_check
  check (status in ('present', 'absent', 'late', 'on_leave', 'on_permit', 'holiday', 'weekend', 'partial', 'pending', 'missing_checkout'));

-- ─── 2) تحديث _today_status_public لدعم on_permit ───────────────────────────
create or replace function public._today_status_public(
  p_board_status text,
  p_offsite boolean,
  p_offsite_kind text,
  p_is_holiday boolean,
  p_checked_in boolean,
  p_checked_out boolean,
  p_detailed boolean
)
returns jsonb
language sql
immutable
set search_path = public, pg_temp
as $function$
  select jsonb_build_object(
    'status', s.status,
    'statusLabel', case s.status
      when 'mission' then 'في مأمورية'
      when 'convoy' then 'في قافلة'
      when 'fundraising' then 'في فاندي ترفيهي'
      when 'on_leave' then 'في إجازة'
      when 'on_permit' then 'في إذن معتمد'
      when 'holiday' then 'عطلة رسمية'
      when 'weekend' then 'إجازة أسبوعية'
      when 'exempt' then 'معفى من البصمة'
      when 'late' then 'متأخر'
      when 'left_early' then 'انصرف مبكرًا'
      when 'checked_out' then 'انصرف'
      when 'present' then 'حاضر في الجمعية'
      when 'absent' then 'غائب'
      else 'لم يسجّل حضوره بعد'
    end
  )
  from (
    select case
      when coalesce(p_offsite, false) then case p_offsite_kind
        when 'CONVOY' then 'convoy'
        when 'FUNDRAISING' then 'fundraising'
        else 'mission'
      end
      when p_board_status = 'assignment' then 'mission'
      when p_board_status = 'on_leave' then 'on_leave'
      when p_board_status in ('on_permit', 'permit', 'late_permit', 'early_permit') then 'on_permit'
      when p_board_status = 'weekend' then
        case when coalesce(p_is_holiday, false) then 'holiday' else 'weekend' end
      when p_board_status = 'exempt' then
        case
          when not coalesce(p_checked_in, false) then 'exempt'
          when coalesce(p_checked_out, false) then 'checked_out'
          else 'present'
        end
      when p_board_status = 'late' then
        case
          when coalesce(p_detailed, false) then 'late'
          when coalesce(p_checked_out, false) then 'checked_out'
          else 'present'
        end
      when p_board_status = 'left_early' then
        case when coalesce(p_detailed, false) then 'left_early' else 'checked_out' end
      when p_board_status in ('present', 'checked_out', 'absent') then p_board_status
      else 'not_recorded'
    end as status
  ) s;
$function$;

-- ─── 3) تصحيح تريجر tg_request_approved_attendance_exempt ───────────────────
create or replace function public.tg_request_approved_attendance_exempt()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_work_date date;
  v_start_date date;
  v_end_date date;
  v_day date;
  v_employee_id uuid;
  v_employee_name text;
  v_permit_mins integer := 0;
begin
  -- فقط عند الموافقة على الطلب
  if new.status <> 'approved' or (old.status = new.status) then
    return new;
  end if;

  v_employee_id := new.employee_id;

  -- تجاهل الإجازات — لها تريجر خاص (tg_leave_attendance_on_approval)
  if new.request_type = 'leave' then
    return new;
  end if;

  -- اسم الموظف للإشعار
  select full_name_ar into v_employee_name from public.employees where id = v_employee_id;

  -- ─── المأمورية/القافلة/الفاندي: قراءة التواريخ من payload الطلب ──────────
  if new.request_type in ('mission', 'convoy', 'fundraising') then
    v_start_date := (new.payload->>'startDate')::date;
    v_end_date   := coalesce((new.payload->>'endDate')::date, v_start_date);
    if v_start_date is null then return new; end if;

    v_day := v_start_date;
    while v_day <= v_end_date loop
      insert into public.attendance_daily (employee_id, work_date, status)
      values (v_employee_id, v_day, 'present')
      on conflict on constraint attendance_daily_uq do update
        set status = 'present',
            updated_at = now()
        where public.attendance_daily.is_finalized = false
          and public.attendance_daily.status not in ('on_leave', 'holiday', 'weekend');

      -- سجل استثناء: مأمورية معتمدة
      insert into public.attendance_exceptions (
        employee_id, attendance_daily_id, work_date, kind, description, status, created_by
      )
      select v_employee_id, ad.id, v_day, 'manual_adjustment',
             'مأمورية معتمدة — إعفاء من التأخير/الغياب',
             'approved', auth.uid()
      from public.attendance_daily ad
      where ad.employee_id = v_employee_id and ad.work_date = v_day
      on conflict do nothing;

      v_day := v_day + 1;
    end loop;

    perform public.log_audit_event(
      'request.attendance_exempted', 'workflow', 'info',
      'attendance_daily', v_employee_id,
      'إعفاء حضور بعد اعتماد مأمورية',
      format('من %s إلى %s', v_start_date, v_end_date),
      jsonb_build_object('requestId', new.id, 'requestType', new.request_type,
                         'startDate', v_start_date, 'endDate', v_end_date)
    );
    return new;
  end if;

  -- ─── إذن تأخير/انصراف/عمل: قراءة permitDate من payload ──────────────────
  if new.request_type in ('late_permit', 'early_permit', 'permit', 'attendance_permit', 'early_leave_permit', 'temporary_departure_permit') then
    v_work_date := coalesce(
      public.try_cast_date(new.payload->>'permitDate'),
      public.try_cast_date(new.payload->>'date'),
      public.try_cast_date(new.payload->>'startDate'),
      public.try_cast_date(new.payload->>'start_date'),
      (new.created_at at time zone 'Africa/Cairo')::date
    );
    if v_work_date is null then return new; end if;

    v_permit_mins := coalesce(nullif(new.payload->>'minutes', '')::integer, 0);

    if new.request_type in ('late_permit', 'attendance_permit', 'permit') then
      -- إذا كان الموظف قد بصم حضوراً بالفعل، نعيد احتساب التأخير
      update public.attendance_daily
      set late_minutes = greatest(0, late_minutes - v_permit_mins),
          status = case
            when greatest(0, late_minutes - v_permit_mins) > 0 then 'late'
            when status in ('on_leave','holiday','weekend') then status
            else 'present'
          end,
          updated_at = now()
      where employee_id = v_employee_id
        and work_date = v_work_date
        and first_check_in is not null
        and is_finalized = false;

      -- إذا لم يكن قد بصم بعد، نضع الحالة 'on_permit' بدلاً من 'present' الكاذبة
      update public.attendance_daily
      set status = 'on_permit',
          late_minutes = 0,
          updated_at = now()
      where employee_id = v_employee_id
        and work_date = v_work_date
        and first_check_in is null
        and is_finalized = false;

      insert into public.attendance_exceptions (
        employee_id, work_date, kind, description, minutes_adjustment, status, created_by
      )
      values (v_employee_id, v_work_date, 'late',
              'إذن تأخير معتمد — إعفاء من دقائق التأخير (' || v_permit_mins || ' دقيقة)',
              v_permit_mins, 'approved', auth.uid())
      on conflict do nothing;
    else
      -- إذن انصراف مبكر: سجل استثناء
      insert into public.attendance_exceptions (
        employee_id, work_date, kind, description, minutes_adjustment, status, created_by
      )
      values (v_employee_id, v_work_date, 'early_leave',
              'إذن انصراف مبكر معتمد (' || v_permit_mins || ' دقيقة)',
              v_permit_mins, 'approved', auth.uid())
      on conflict do nothing;
    end if;

    perform public.log_audit_event(
      'request.attendance_exempted', 'workflow', 'info',
      'attendance_daily', v_employee_id,
      'إعفاء حضور بعد اعتماد طلب إذن',
      format('النوع: %s، التاريخ: %s، الدقائق: %s', new.request_type, v_work_date, v_permit_mins),
      jsonb_build_object('requestId', new.id, 'requestType', new.request_type, 'workDate', v_work_date, 'minutes', v_permit_mins)
    );
    return new;
  end if;

  return new;
end;
$$;

-- ─── 4) تحديث get_attendance_day_roster ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_attendance_day_roster(
  p_date date DEFAULT NULL::date,
  p_category text DEFAULT 'scheduled'::text,
  p_search text DEFAULT NULL::text,
  p_department_id uuid DEFAULT NULL::uuid,
  p_branch_id uuid DEFAULT NULL::uuid,
  p_manager_id uuid DEFAULT NULL::uuid,
  p_sort text DEFAULT 'name'::text,
  p_direction text DEFAULT 'asc'::text,
  p_limit integer DEFAULT 100,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_work_date date := coalesce(p_date, (now() at time zone 'Africa/Cairo')::date);
  v_today     date := (now() at time zone 'Africa/Cairo')::date;
  v_is_today  boolean := (v_work_date = v_today);
  v_search    text := nullif(trim(coalesce(p_search, '')), '');
  v_limit     int  := greatest(1, least(coalesce(p_limit, 100), 500));
  v_offset    int  := greatest(0, coalesce(p_offset, 0));
  v_result    jsonb;
begin
  if p_category not in (
    'scheduled','present','late','absent','unexcused_absent',
    'incomplete','pending_review','location_requests','location_responded',
    'on_leave','on_mission','missing_checkout'
  ) then
    raise exception 'invalid attendance roster category: %', p_category
      using errcode = '22023';
  end if;
  if p_limit is not null and p_limit <= 0 then
    raise exception 'invalid roster limit: %', p_limit using errcode = '22023';
  end if;
  if p_offset is not null and p_offset < 0 then
    raise exception 'invalid roster offset: %', p_offset using errcode = '22023';
  end if;
  if p_sort not in ('name','check_in','late','status') then
    raise exception 'invalid roster sort: %', p_sort using errcode = '22023';
  end if;
  if p_direction not in ('asc','desc') then
    raise exception 'invalid roster direction: %', p_direction using errcode = '22023';
  end if;

  with visible_employees as (
      select e.id, e.employee_code, e.full_name_ar, e.photo_url,
             e.department_id, e.branch_id,
             d.name as department_name,
             b.name as branch_name,
             jt.name as job_title,
             e.is_attendance_exempt,
             mr.manager_employee_id,
             me.full_name_ar as manager_name
      from public.employees e
      left join public.departments d on d.id = e.department_id
      left join public.branches b on b.id = e.branch_id
      left join public.job_titles jt on jt.id = e.job_title_id
      left join lateral (
        select mr.manager_employee_id
          from public.manager_relations mr
         where mr.employee_id = e.id
           and mr.relation_type = 'primary'
           and mr.effective_to is null
         order by mr.effective_from desc
         limit 1
      ) mr on true
      left join public.employees me on me.id = mr.manager_employee_id
     where e.is_active = true and coalesce(e.is_deleted, false) = false
       and (p_department_id is null or e.department_id = p_department_id)
       and (p_branch_id is null or e.branch_id = p_branch_id)
       and (p_manager_id is null or mr.manager_employee_id = p_manager_id)
       and not (public.is_employee_isolated(e.id) and not public.can_view_isolated_employee(e.id))
       and not (
         (
           coalesce(e.is_attendance_exempt, false)
           or public.is_employee_attendance_exempt(e.id)
           or public.is_employee_executive(e.id)
         )
         and not exists (
           select 1 from public.attendance_daily ad
            where ad.employee_id = e.id
              and ad.work_date = v_work_date
              and ad.first_check_in is not null
         )
         and not exists (
           select 1 from public.attendance_events ae
            where ae.employee_id = e.id
              and (ae.event_at at time zone 'Africa/Cairo')::date = v_work_date
         )
       )
       and (v_search is null
         or lower(e.full_name_ar) like '%' || v_search || '%'
         or lower(e.employee_code) like '%' || v_search || '%')
  ), daily as (
    select d.* from public.attendance_daily d where d.work_date = v_work_date
  ), events_day as (
    select e.* from public.attendance_events e
     where (e.event_at at time zone 'Africa/Cairo')::date = v_work_date
  ), approved_leaves as (
    select distinct on (lr.employee_id)
           lr.employee_id,
           lt.is_paid,
           lt.code as leave_code,
           coalesce(lt.name_ar, lt.name_en, lt.code) as leave_name,
           r.title as leave_title,
           coalesce(r.reason, r.payload->>'reason') as leave_reason,
           r.request_number as leave_request_number
      from public.leave_requests lr
      join public.requests r on r.id = lr.request_id and r.status = 'approved'
      join public.leave_types lt on lt.id = lr.leave_type_id
     where v_work_date between lr.start_date and lr.end_date
     order by lr.employee_id, lr.start_date desc
  ), approved_direct_requests as (
    select distinct on (r.employee_id)
           r.employee_id,
           r.request_type,
           coalesce(r.title, 'طلب ' || r.request_type) as request_title,
           coalesce(r.reason, r.payload->>'reason') as request_reason,
           r.request_number
      from public.requests r
     where r.status = 'approved'
       and v_work_date between coalesce(public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'), public.try_cast_date(r.payload->>'date'), (r.created_at at time zone 'Africa/Cairo')::date)
                           and coalesce(public.try_cast_date(r.payload->>'endDate'), public.try_cast_date(r.payload->>'end_date'), public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'), public.try_cast_date(r.payload->>'date'), (r.created_at at time zone 'Africa/Cairo')::date)
     order by r.employee_id, r.created_at desc
  ), approved_permits as (
    select distinct on (r.employee_id)
           r.employee_id,
           r.id as permit_request_id,
           r.request_number as permit_request_number,
           r.request_type as permit_type,
           coalesce(r.title, case
             when r.request_type = 'late_permit' then 'إذن تأخير'
             when r.request_type = 'early_permit' then 'إذن انصراف'
             else 'إذن عمل'
           end) as permit_title,
           coalesce(r.reason, r.payload->>'reason') as permit_reason,
           coalesce(nullif(r.payload->>'minutes', '')::integer, 0) as permit_minutes
      from public.requests r
     where r.status = 'approved'
       and r.request_type in (
         'late_permit', 'early_permit', 'early_leave_permit',
         'temporary_departure_permit', 'permit', 'attendance_permit', 'permission'
       )
       and v_work_date between coalesce(public.try_cast_date(r.payload->>'permitDate'), public.try_cast_date(r.payload->>'date'), public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'), (r.created_at at time zone 'Africa/Cairo')::date)
                           and coalesce(public.try_cast_date(r.payload->>'endDate'), public.try_cast_date(r.payload->>'end_date'), public.try_cast_date(r.payload->>'permitDate'), public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'), public.try_cast_date(r.payload->>'date'), (r.created_at at time zone 'Africa/Cairo')::date)
     order by r.employee_id, r.created_at desc
  ), active_attendance_permits as (
    select distinct on (ap.employee_id)
           ap.employee_id,
           ap.id as permit_id,
           ap.kind as permit_type,
           coalesce(ap.reason, 'إذن عمل') as permit_title,
           ap.reason as permit_reason,
           coalesce(ap.grace_minutes, 0) as permit_minutes
      from public.attendance_permits ap
     where ap.status = 'approved'
       and ap.permit_date = v_work_date
     order by ap.employee_id, ap.created_at desc
  ), pending_requests as (
    select distinct on (r.employee_id)
           r.employee_id,
           r.id as request_id,
           r.request_number,
           r.request_type,
           coalesce(r.title, 'طلب ' || r.request_type) as request_title,
           coalesce(r.reason, r.payload->>'reason') as request_reason,
           case
             when r.request_type in ('leave', 'annual_leave', 'casual_leave', 'sick_leave', 'unpaid_leave', 'weekly_rest_comp', 'compensation')
               then 'leave'
             when r.request_type in ('mission', 'external_mission', 'convoy', 'field_convoy', 'fundraising', 'fandy')
               then 'mission'
             when r.request_type in ('late_permit', 'early_permit', 'early_leave_permit', 'temporary_departure_permit', 'permit', 'attendance_permit', 'permission')
               then 'permit'
             else r.request_type
           end as normalized_type
      from public.requests r
     where r.status in ('pending', 'submitted')
       and r.request_type in (
         'leave', 'compensation', 'annual_leave', 'casual_leave', 'sick_leave', 'unpaid_leave', 'weekly_rest_comp',
         'mission', 'external_mission', 'convoy', 'field_convoy', 'fundraising', 'fandy',
         'late_permit', 'early_permit', 'early_leave_permit', 'temporary_departure_permit', 'permit', 'attendance_permit', 'permission'
       )
       and v_work_date between coalesce(public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'), public.try_cast_date(r.payload->>'permitDate'), public.try_cast_date(r.payload->>'date'), (r.created_at at time zone 'Africa/Cairo')::date)
                           and coalesce(public.try_cast_date(r.payload->>'endDate'), public.try_cast_date(r.payload->>'end_date'), public.try_cast_date(r.payload->>'permitDate'), public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'), public.try_cast_date(r.payload->>'date'), (r.created_at at time zone 'Africa/Cairo')::date)
     order by r.employee_id, r.created_at desc
  ), active_missions as (
    select distinct p.employee_id
       from public.work_assignment_participants p
       join public.work_assignments wa on wa.id = p.assignment_id
      where wa.status in ('APPROVED','IN_PROGRESS')
        and v_work_date between wa.start_at::date and wa.end_at::date
     union
     select r.employee_id
       from approved_direct_requests r
      where r.request_type in ('mission', 'external_mission', 'convoy', 'field_convoy', 'fundraising', 'fandy')
  ), location_requests_day as (
    select distinct on (llr.employee_id)
           llr.employee_id, llr.status as llr_status, llr.requested_at, llr.responded_at,
           (llr.responded_at is not null or llr.status in ('accepted','active','completed')) as responded
      from public.live_location_requests llr
     where (llr.requested_at at time zone 'Africa/Cairo')::date = v_work_date
        or (llr.responded_at is not null and (llr.responded_at at time zone 'Africa/Cairo')::date = v_work_date)
     order by llr.employee_id, llr.requested_at desc
  ), review_reasons as (
    select distinct on (e.employee_id) e.employee_id,
           case
             when e.verification_status = 'failed' then 'فشل التحقق من الهوية'
             when e.latitude is null or e.longitude is null then 'لا يوجد موقع مؤكد'
             when e.accuracy_meters is not null and e.accuracy_meters > 100 then 'دقة GPS منخفضة'
             when e.distance_meters is not null and e.distance_meters > 0 then 'خارج النطاق المعتمد'
             when e.status = 'flagged' then 'أُشعر تلقائياً للمراجعة'
             else 'يحتاج مراجعة بشرية'
           end as reason
      from events_day e
     where e.requires_review = true
     order by e.employee_id, e.created_at desc
  ), base as (
    select
      ve.id            as employee_id,
      ve.employee_code,
      ve.full_name_ar,
      ve.photo_url,
      ve.department_id,
      ve.department_name,
      ve.branch_id,
      ve.branch_name,
      ve.job_title,
      ve.manager_employee_id,
      ve.manager_name,
      d.id             as daily_id,
      d.status         as daily_status,
      d.first_check_in,
      d.last_check_out,
      coalesce(d.late_minutes, 0) as late_minutes,
      coalesce(d.is_finalized, false) as is_finalized,
      coalesce(s.name, emp_shift.name) as shift_name,
      coalesce(s.start_time, emp_shift.start_time) as shift_start,
      coalesce(s.end_time, emp_shift.end_time) as shift_end,
      coalesce(
        (select bool_or(e.requires_review) from events_day e where e.employee_id = ve.id),
        false
      ) or (pr.employee_id is not null and (d.first_check_in is null or d.status in ('absent', 'pending'))) as requires_review,
      coalesce(
        rr.reason,
        case
          when pr.employee_id is not null and pr.normalized_type = 'leave' then
            'طلب إجازة قيد المراجعة (#' || pr.request_number || '): ' || pr.request_title
          when pr.employee_id is not null and pr.normalized_type = 'mission' then
            'طلب مأمورية قيد المراجعة (#' || pr.request_number || '): ' || pr.request_title
          when pr.employee_id is not null and pr.normalized_type = 'permit' then
            'طلب إذن قيد المراجعة (#' || pr.request_number || '): ' || pr.request_title
          when pr.employee_id is not null then
            'طلب قيد المراجعة (#' || pr.request_number || '): ' || pr.request_title
          else null
        end
      ) as review_reason,
      coalesce(al.employee_id is not null or adr.request_type in ('leave', 'compensation', 'annual_leave', 'casual_leave', 'sick_leave', 'unpaid_leave'), false) as has_approved_leave,
      coalesce(
        al.leave_code,
        adr.request_type,
        case
          when pr.normalized_type = 'leave' then 'pending_leave'
          when pr.normalized_type = 'mission' then 'pending_mission'
          when pr.normalized_type = 'permit' then 'pending_permit'
          when pr.normalized_type is not null then 'pending_' || pr.normalized_type
          else null
        end
      ) as leave_code,
      coalesce(al.leave_name, adr.request_title, pr.request_title) as leave_name,
      coalesce(al.leave_title, adr.request_title, pr.request_title) as leave_title,
      coalesce(al.leave_reason, adr.request_reason, pr.request_reason) as leave_reason,
      coalesce(al.leave_request_number, adr.request_number, pr.request_number) as leave_request_number,
      coalesce(al.is_paid, true) as leave_is_paid,
      coalesce(am.employee_id is not null, false) as has_mission,
      -- الأذونات المعتمدة
      coalesce(ap.employee_id is not null or aap.employee_id is not null, false) as has_approved_permit,
      coalesce(ap.permit_type, aap.permit_type) as permit_type,
      coalesce(ap.permit_title, aap.permit_title) as permit_title,
      coalesce(ap.permit_reason, aap.permit_reason) as permit_reason,
      coalesce(ap.permit_minutes, aap.permit_minutes, 0) as permit_minutes,
      coalesce(pr.employee_id is not null, false) as has_pending_request,
      pr.request_id    as pending_request_id,
      pr.request_number as pending_request_number,
      pr.request_title  as pending_request_title,
      pr.normalized_type as pending_request_type,
      lrd.llr_status   as location_request_status,
      lrd.requested_at as location_requested_at,
      lrd.responded_at as location_responded_at,
      coalesce(lrd.responded, false) as location_responded_today,
      (
        (
          ve.department_name in ('إدارة العيادات الطبية', 'العيادات الطبية')
          or coalesce(ve.job_title, '') in ('تمريض', 'دكتورة المعمل', 'موظف استقبال')
        )
        and ve.id not in (
          '4120ce3a-8999-453e-8d9d-acd8f3b5f04c',
          'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'
        )
        and coalesce(ve.job_title, '') not like '%مدير%'
        and coalesce(ve.job_title, '') not like '%أدارة%'
        and coalesce(ve.job_title, '') not like '%ادارة%'
        and coalesce(ve.job_title, '') not like '%مسؤول%'
      ) as is_clinic_medical_staff,
      case
        -- غير المطالبين بالبصمة لا يُعتبرون غائبين أبداً
        when (coalesce(ve.is_attendance_exempt, false) or public.is_employee_attendance_exempt(ve.id) or public.is_employee_executive(ve.id))
             and d.first_check_in is null
          then 'exempt'
        -- المأموريات والإجازات المعتمدة تعلو على نقص بصمة الانصراف
        when am.employee_id is not null then 'on_mission'
        when (al.employee_id is not null or adr.request_type in ('leave', 'compensation', 'annual_leave', 'casual_leave', 'sick_leave', 'unpaid_leave')) then 'on_leave'
        -- أذونات العمل المعتمدة لمن لم يبصم بعد (تمنع احتسابه حاضراً كاذباً وتمنع احتسابه غياباً دون إذن)
        when (ap.employee_id is not null or aap.employee_id is not null) and d.first_check_in is null then 'on_permit'
        -- المأموريات والإجازات والأذونات المعلّقة لمن لم يبصم بعد
        when pr.employee_id is not null and pr.normalized_type = 'mission' and d.first_check_in is null then 'on_mission'
        when pr.employee_id is not null and pr.normalized_type = 'leave' and d.first_check_in is null then 'on_leave'
        when pr.employee_id is not null and pr.normalized_type = 'permit' and d.first_check_in is null then 'pending_permit'
        -- بصمة بلا انصراف
        when d.id is not null and d.first_check_in is not null and d.last_check_out is null
             and (
               d.status = 'missing_checkout'
               or d.is_finalized
               or not v_is_today
               or coalesce(ado.clear_check_out, false) = true
             )
          then 'missing_checkout'
        -- عند وجود بصمة حضور فعلية
        when d.id is not null and d.first_check_in is not null and d.status in ('present','late') then d.status
        when d.id is not null and d.first_check_in is not null then d.status
        -- عند وجود سجل معتمد بدون بصمة
        when d.id is not null and d.status in ('on_permit', 'on_leave') then d.status
        when public.is_official_holiday(v_work_date, ve.id) then 'holiday'
        when extract(isodow from v_work_date) = 5 then 'weekend'
        -- إذا لم يحضر ولديه طلب معلق آخر
        when pr.employee_id is not null then 'absent'
        -- غياب قطعي بدون إذن
        else 'unexcused_absent'
      end as derived_status
    from visible_employees ve
    left join daily d on d.employee_id = ve.id
    left join public.attendance_day_overrides ado on ado.employee_id = ve.id and ado.work_date = v_work_date and ado.is_active = true
    left join public.shifts s on s.id = d.shift_id
    left join lateral (
      select s2.name, s2.start_time, s2.end_time
        from public.shift_assignments sa2
        join public.shifts s2 on s2.id = sa2.shift_id
       where sa2.employee_id = ve.id
         and sa2.is_active = true
         and v_work_date >= sa2.effective_from
         and (sa2.effective_to is null or v_work_date <= sa2.effective_to)
       order by sa2.effective_from desc
       limit 1
    ) emp_shift on true
    left join review_reasons rr on rr.employee_id = ve.id
    left join approved_leaves al on al.employee_id = ve.id
    left join approved_direct_requests adr on adr.employee_id = ve.id
    left join approved_permits ap on ap.employee_id = ve.id
    left join active_attendance_permits aap on aap.employee_id = ve.id
    left join active_missions am on am.employee_id = ve.id
    left join pending_requests pr on pr.employee_id = ve.id
    left join location_requests_day lrd on lrd.employee_id = ve.id
  ), categorized as (
    select b.*,
           case when b.is_clinic_medical_staff then 1 else 0 end as clinic_staff_order,
           case p_sort
             when 'check_in' then coalesce(to_char(b.first_check_in, 'YYYY-MM-DD HH24:MI:SS'), '9999-99-99 99:99:99')
             when 'late'     then lpad(coalesce(b.late_minutes::text, '0'), 12, '0')
             when 'status'   then coalesce(b.derived_status, '')
             else coalesce(b.full_name_ar, '')
           end as sort_key
      from base b
     where case p_category
        when 'scheduled'          then b.derived_status <> 'exempt'
        -- الحاضرون: حصراً من سجلوا حضوراً فعلياً بالمقر
        when 'present'            then b.first_check_in is not null and b.derived_status in ('present','late','partial','missing_checkout')
        when 'late'               then b.first_check_in is not null and (b.derived_status = 'late' or b.late_minutes > 0)
        -- إجمالي الغياب: يشمل كل من لم يسجل حضوراً اليوم وليس في مأمورية ميدانية
        when 'absent'             then (
                                       b.first_check_in is null
                                       and b.derived_status not in ('exempt', 'on_mission')
                                       and not coalesce(b.has_mission, false)
                                     )
        -- غياب بدون إذن: حصراً من لم يسجل حضوراً وليس لديه أي إجازة معتمدة أو مأمورية أو إذن معتمد أو أي طلب معلق
        when 'unexcused_absent'   then (
                                       b.derived_status = 'unexcused_absent'
                                       or (
                                         b.first_check_in is null
                                         and b.derived_status in ('absent', 'unexcused_absent')
                                         and not coalesce(b.has_pending_request, false)
                                         and not coalesce(b.has_approved_leave, false)
                                         and not coalesce(b.has_approved_permit, false)
                                         and not coalesce(b.has_mission, false)
                                       )
                                     )
        when 'incomplete'         then b.derived_status in ('partial','pending')
        when 'on_leave'           then (b.derived_status in ('on_leave', 'on_permit') or b.has_approved_leave = true or b.has_approved_permit = true or (b.has_pending_request = true and b.pending_request_type in ('leave', 'permit')))
        when 'on_mission'         then (b.derived_status = 'on_mission' or b.has_mission = true or (b.has_pending_request = true and b.pending_request_type = 'mission'))
        when 'missing_checkout'   then (
                                       b.derived_status = 'missing_checkout'
                                       or (b.first_check_in is not null and b.last_check_out is null and (not v_is_today or b.is_finalized or b.daily_status = 'missing_checkout'))
                                     )
        when 'pending_review'     then (b.requires_review = true or b.has_pending_request = true)
        when 'location_requests'  then b.location_requested_at is not null
                                    or b.location_responded_at is not null
        when 'location_responded' then b.location_responded_today = true
        else false
      end
  )
  select jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(item)
        from (
          select jsonb_build_object(
            'employeeId', c.employee_id,
            'employeeCode', c.employee_code,
            'employeeName', c.full_name_ar,
            'photoUrl', c.photo_url,
            'departmentId', c.department_id,
            'departmentName', c.department_name,
            'branchId', c.branch_id,
            'branchName', c.branch_name,
            'jobTitle', c.job_title,
            'managerEmployeeId', c.manager_employee_id,
            'managerName', c.manager_name,
            'status', c.derived_status,
            'firstCheckIn', c.first_check_in,
            'lastCheckOut', c.last_check_out,
            'lateMinutes', c.late_minutes,
            'shiftName', c.shift_name,
            'shiftStart', c.shift_start,
            'shiftEnd', c.shift_end,
            'requiresReview', c.requires_review,
            'reviewReason', c.review_reason,
            'hasApprovedLeave', c.has_approved_leave,
            'leaveCode', c.leave_code,
            'leaveName', c.leave_name,
            'leaveTitle', c.leave_title,
            'leaveReason', c.leave_reason,
            'leaveRequestNumber', c.leave_request_number,
            'leaveIsPaid', c.leave_is_paid,
            'hasMission', c.has_mission,
            'hasApprovedPermit', c.has_approved_permit,
            'permitType', c.permit_type,
            'permitTitle', c.permit_title,
            'permitReason', c.permit_reason,
            'permitMinutes', c.permit_minutes,
            'hasPendingRequest', c.has_pending_request,
            'pendingRequestId', c.pending_request_id,
            'pendingRequestNumber', c.pending_request_number,
            'pendingRequestTitle', c.pending_request_title,
            'pendingRequestType', c.pending_request_type,
            'isClinicMedicalStaff', c.is_clinic_medical_staff,
            'locationRequestStatus', c.location_request_status,
            'locationRequestedAt', c.location_requested_at,
            'locationRespondedAt', c.location_responded_at,
            'locationRespondedToday', c.location_responded_today
          ) as item
          from categorized c
          order by
            c.clinic_staff_order asc,
            case when p_direction = 'asc'  then c.sort_key end asc,
            case when p_direction = 'desc' then c.sort_key end desc,
            c.full_name_ar asc
          limit v_limit offset v_offset
        ) sub
    ), '[]'::jsonb),
    'total', (select count(*) from categorized),
    'limit', v_limit,
    'offset', v_offset
  ) into v_result;

  return v_result;
end;
$function$;

revoke all on function public.get_attendance_day_roster(date, text, text, uuid, uuid, uuid, text, text, integer, integer) from public, anon;
grant execute on function public.get_attendance_day_roster(date, text, text, uuid, uuid, uuid, text, text, integer, integer) to authenticated, service_role;
comment on function public.get_attendance_day_roster(date, text, text, uuid, uuid, uuid, text, text, integer, integer) is
  '0720: تمييز أصحاب أذونات العمل وتصاريح التأخير المعتمدة والمعلقة ومنع ظهورهم كحاضرين قبل تسجيل البصمة الفعلية.';

-- ─── 5) تصحيح تنظيفي لسجلات attendance_daily الكاذبة بدون بصمة ───────────────
update public.attendance_daily ad
set status = 'on_permit',
    late_minutes = 0,
    updated_at = now()
where ad.first_check_in is null
  and ad.status = 'present'
  and exists (
    select 1 from public.requests r
    where r.employee_id = ad.employee_id
      and r.status = 'approved'
      and r.request_type in ('late_permit', 'early_permit', 'permit', 'attendance_permit', 'permission')
      and ad.work_date between coalesce(public.try_cast_date(r.payload->>'permitDate'), public.try_cast_date(r.payload->>'date'), public.try_cast_date(r.payload->>'startDate'), r.created_at::date)
                           and coalesce(public.try_cast_date(r.payload->>'endDate'), public.try_cast_date(r.payload->>'permitDate'), public.try_cast_date(r.payload->>'startDate'), r.created_at::date)
  );

commit;
