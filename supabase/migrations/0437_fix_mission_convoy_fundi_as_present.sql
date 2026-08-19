-- 0437: المأمورية/القافلة/الفاندي/التكليفات = أيام عمل → present (حضور فعلي)
--       + ضبط الخانات الخاصة (missions/convoy_requests) من payload الطلب
--       + بصمة حضور في أول يوم وانصراف في آخر يوم من أوقات الطلب
--         (الانصراف يُسجَّل تلقائياً عند امتداد المأمورية خارج وقت العمل)
--       + منع تصفية بصمة الخروج الناقصة في أيام التكليفات
-- ملاحظة: الإجازة المعتمدة تبقى on_leave — والمأمورية تسبقها عند التداخل.

-- ═══════════════════════════════════════════════════════════════════════
-- 1) تريجر الموافقات: المأموريات أيام حضور (وليس إجازة)
-- ═══════════════════════════════════════════════════════════════════════
create or replace function public.tg_leave_attendance_on_approval()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_lr public.leave_requests;
  v_day date; v_end date; v_start date; v_emp uuid;
  v_start_ts timestamptz; v_end_ts timestamptz;
  v_type_id uuid; v_year integer;
  v_punch timestamptz;
  v_covered boolean;
begin
  if old.status = new.status then return new; end if;

  -- ── إجازة معتمدة: on_leave (مع حماية أيام العمل المعتمدة الأخرى) ──
  if new.request_type = 'leave' and new.status = 'approved' then
    select * into v_lr from public.leave_requests where request_id = new.id;
    if not found then return new; end if;
    v_day := v_lr.start_date;
    while v_day <= v_lr.end_date loop
      -- يوم مغطّى بمأمورية/قافلة/فاندي/تكليف معتمد = يوم عمل → لا يُعلَّم إجازة
      v_covered := exists (
        select 1 from public.requests r
        where r.employee_id = v_lr.employee_id and r.status = 'approved'
          and r.request_type in ('mission','convoy','fundraising')
          and v_day between public._payload_date(r.payload, 'startDate')
                       and coalesce(public._payload_date(r.payload, 'endDate'), public._payload_date(r.payload, 'startDate'))
      ) or exists (
        select 1 from public.work_assignment_participants wp
        join public.work_assignments wa on wa.id = wp.assignment_id
        where wp.employee_id = v_lr.employee_id and wa.status = 'APPROVED'
          and v_day between (wa.start_at at time zone 'Africa/Cairo')::date
                       and (wa.end_at at time zone 'Africa/Cairo')::date
      );
      if not v_covered then
        insert into public.attendance_daily(employee_id, work_date, status)
        values(v_lr.employee_id, v_day, 'on_leave')
        on conflict on constraint attendance_daily_uq do update
          set status = 'on_leave', updated_at = now()
          where public.attendance_daily.is_finalized = false
            and public.attendance_daily.status <> 'on_leave';
      end if;
      v_day := v_day + 1;
    end loop;
    perform public.log_audit_event(
      'leave.attendance.marked', 'workflow', 'info', 'attendance_daily', v_lr.employee_id,
      'تم تعليم أيام الإجازة المعتمدة كـ on_leave في الحضور',
      format('من %s إلى %s', v_lr.start_date, v_lr.end_date),
      jsonb_build_object('requestId', new.id));
    return new;
  end if;

  -- ── مأمورية/قافلة/فاندي معتمدة: أيام عمل → present (بلا خصم من الرصيد) ──
  if new.request_type in ('mission','convoy','fundraising') and new.status = 'approved' then
    v_emp := new.employee_id;
    if v_emp is null then
      return new; -- لا بيانات مصدرية للطلب → لا تعليم
    end if;
    v_start := public._payload_date(new.payload, 'startDate');
    v_end := coalesce(public._payload_date(new.payload, 'endDate'), v_start);

    if v_start is null then
      -- بلا payload: قراءة التواريخ من الخانات الخاصة (طلبات قديمة / إنشاء مباشر)
      v_start_ts := null; v_end_ts := null;
      if new.request_type = 'mission' then
        select start_at, end_at into v_start_ts, v_end_ts
        from public.missions where request_id = new.id;
      elsif new.request_type = 'convoy' then
        select departure_at, coalesce(return_at, departure_at) into v_start_ts, v_end_ts
        from public.convoy_requests where request_id = new.id;
      end if;
      if v_start_ts is null then
        return new;
      end if;
      v_start := (v_start_ts at time zone 'Africa/Cairo')::date;
      v_end := (v_end_ts at time zone 'Africa/Cairo')::date;
    else
      -- ضبط الخانات الخاصة بالطلب من payload (متوافقة مع قراءة الكشف والتراجع)
      if new.request_type = 'mission'
         and not exists (select 1 from public.missions where request_id = new.id) then
        insert into public.missions (request_id, employee_id, destination, purpose, start_at, end_at, created_by)
        values (
          new.id, v_emp, coalesce(new.payload->>'location', ''), coalesce(new.title, ''),
          (v_start::text || case when new.payload->>'startTime' is not null
                                 then 'T' || (new.payload->>'startTime') || ':00' else 'T00:00:00' end)::timestamp at time zone 'Africa/Cairo',
          (v_end::text   || case when new.payload->>'endTime'   is not null
                                 then 'T' || (new.payload->>'endTime') || ':00' else 'T00:00:00' end)::timestamp at time zone 'Africa/Cairo',
          new.created_by
        );
      elsif new.request_type = 'convoy'
            and not exists (select 1 from public.convoy_requests where request_id = new.id) then
        insert into public.convoy_requests (request_id, employee_id, convoy_name, origin, destination, departure_at, return_at, created_by)
        values (
          new.id, v_emp,
          coalesce(coalesce(new.payload->>'convoyName', new.title), ''),
          coalesce(new.payload->>'origin', ''), coalesce(new.payload->>'location', ''),
          (v_start::text || case when new.payload->>'startTime' is not null
                                 then 'T' || (new.payload->>'startTime') || ':00' else 'T00:00:00' end)::timestamp at time zone 'Africa/Cairo',
          (case when new.payload->>'endTime' is not null
                then (v_end::text || 'T' || (new.payload->>'endTime') || ':00')::timestamp at time zone 'Africa/Cairo'
                when v_end > v_start then (v_end::text || 'T00:00:00')::timestamp at time zone 'Africa/Cairo'
                else null end), -- endDate وحده => منتصف ليل نهايته; نفس اليوم بلا endTime => NULL (لا يخرق ck_convoy_period)
          new.created_by
        );
      end if;
    end if;

    v_day := v_start;
    while v_day <= v_end loop
      -- بصمة حضور في أول يوم (من وقت بدء المأمورية إن وُجد — بدون بصمة = حضور مُسجَّل)
      v_punch := null;
      if v_day = v_start and new.payload->>'startTime' is not null then
        v_punch := (v_day::text || 'T' || (new.payload->>'startTime') || ':00')::timestamp at time zone 'Africa/Cairo';
      end if;
      insert into public.attendance_daily(employee_id, work_date, status, first_check_in)
      values(v_emp, v_day, 'present', v_punch)
      on conflict on constraint attendance_daily_uq do update
        set status = 'present',
            first_check_in = coalesce(public.attendance_daily.first_check_in, excluded.first_check_in),
            updated_at = now()
        where public.attendance_daily.is_finalized = false
          and public.attendance_daily.status not in ('holiday','weekend');

      -- بصمة انصراف في آخر يوم (وقت نهاية المأمورية إن وُجد — يُسجَّل الانصراف عند الامتداد خارج العمل)
      if v_day = v_end and new.payload->>'endTime' is not null then
        update public.attendance_daily
        set last_check_out = (v_day::text || 'T' || (new.payload->>'endTime') || ':00')::timestamp at time zone 'Africa/Cairo',
            updated_at = now()
        where employee_id = v_emp and work_date = v_day
          and last_check_out is null and is_finalized = false;
      end if;

      -- بدل الراحة الأسبوعي: الجمعة خلال مأمورية/قافلة/فاندي
      if extract(isodow from v_day) = 5 then
        select id into v_type_id from public.leave_types where code = 'weekly_rest_comp';
        if v_type_id is not null then
          v_year := extract(year from v_day)::integer;
          perform public.apply_leave_ledger_entry(
            v_emp, v_type_id, v_year, 'credit', 1,
            'weekly-rest:credit:' || v_emp::text || ':' || v_day::text,
            null,
            'بدل راحة أسبوعي عن يوم عمل في ' || new.request_type || ' بتاريخ ' || to_char(v_day, 'YYYY-MM-DD'),
            jsonb_build_object('workDate', v_day::text, 'source', new.request_type, 'requestId', new.id)
          );
        end if;
      end if;
      v_day := v_day + 1;
    end loop;
    perform public.log_audit_event(
      'leave.attendance.marked', 'workflow', 'info', 'attendance_daily', v_emp,
      'تم تعليم أيام ' || new.request_type || ' المعتمدة كحضور عمل (present) بلا خصم',
      format('من %s إلى %s', v_start, v_end),
      jsonb_build_object('requestId', new.id, 'kind', new.request_type));
    return new;
  end if;

  return new;
end $function$;

-- ═══════════════════════════════════════════════════════════════════════
-- 2) ربط تكليفات العمل: الأيام = حضور (وليس إجازة)
-- ═══════════════════════════════════════════════════════════════════════
create or replace function public.tg_work_assignment_attendance_link()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_p record; v_day date; v_end date; v_type_id uuid; v_year integer; v_emp uuid;
begin
  if old is not null and old.status = new.status then return new; end if;

  -- اعتماد (بما فيه الإنشاء بحالة APPROVED من create_work_assignment)
  if new.status = 'APPROVED' then
    for v_p in
      select employee_id from public.work_assignment_participants where assignment_id = new.id
      union select new.responsible_employee_id where new.responsible_employee_id is not null
    loop
      v_emp := v_p.employee_id;
      v_day := (new.start_at at time zone 'Africa/Cairo')::date;
      v_end := (new.end_at at time zone 'Africa/Cairo')::date;
      while v_day <= v_end loop
        if coalesce(new.counts_as_work_day, true) then
          insert into public.attendance_daily(employee_id, work_date, status)
          values(v_emp, v_day, 'present')
          on conflict on constraint attendance_daily_uq do update
            set status = 'present', updated_at = now()
            where public.attendance_daily.is_finalized = false
              and public.attendance_daily.status not in ('holiday','weekend');
        end if;
        -- بدل الراحة الأسبوعي عن الجمعة ضمن التكليف
        if extract(isodow from v_day) = 5 then
          select id into v_type_id from public.leave_types where code = 'weekly_rest_comp';
          if v_type_id is not null then
            v_year := extract(year from v_day)::integer;
            perform public.apply_leave_ledger_entry(
              v_emp, v_type_id, v_year, 'credit', 1,
              'weekly-rest:credit:' || v_emp::text || ':' || v_day::text,
              null,
              'رصيد بدل راحة أسبوعي عن تكليف عمل يوم الجمعة ' || to_char(v_day, 'YYYY-MM-DD'),
              jsonb_build_object('workDate', v_day::text, 'source', 'work-assignment', 'assignmentId', new.id)
            );
          end if;
        end if;
        v_day := v_day + 1;
      end loop;
    end loop;
    return new;
  end if;

  -- إلغاء/رفض بعد اعتماد: تراجع عن الأيام غير المثبتة ما لم يغطّها اعتماد آخر
  if old.status = 'APPROVED' and new.status in ('REJECTED','CANCELLED') then
    for v_p in
      select employee_id from public.work_assignment_participants where assignment_id = new.id
      union select new.responsible_employee_id where new.responsible_employee_id is not null
    loop
      v_emp := v_p.employee_id;
      v_day := (new.start_at at time zone 'Africa/Cairo')::date;
      v_end := (new.end_at at time zone 'Africa/Cairo')::date;
      while v_day <= v_end loop
        update public.attendance_daily ad
        set status = 'absent', updated_at = now()
        where ad.employee_id = v_emp and ad.work_date = v_day
          and ad.is_finalized = false and ad.status = 'present'
          and ad.first_check_in is null and ad.last_check_out is null
          and not exists (
            select 1 from public.leave_requests lr join public.requests r on r.id = lr.request_id
            where lr.employee_id = v_emp and r.status = 'approved'
              and v_day between lr.start_date and lr.end_date)
          and not exists (
            select 1 from public.missions m join public.requests r on r.id = m.request_id
            where m.employee_id = v_emp and r.status = 'approved'
              and v_day between (m.start_at at time zone 'Africa/Cairo')::date and (m.end_at at time zone 'Africa/Cairo')::date)
          and not exists (
            select 1 from public.convoy_requests c join public.requests r on r.id = c.request_id
            where c.employee_id = v_emp and r.status = 'approved'
              and v_day between (c.departure_at at time zone 'Africa/Cairo')::date and (coalesce(c.return_at,c.departure_at) at time zone 'Africa/Cairo')::date)
          and not exists (
            select 1 from public.work_assignment_participants wp2 join public.work_assignments wa2 on wa2.id = wp2.assignment_id
            where wp2.employee_id = v_emp and wa2.status = 'APPROVED' and wa2.id <> new.id
              and v_day between (wa2.start_at at time zone 'Africa/Cairo')::date and (wa2.end_at at time zone 'Africa/Cairo')::date);
        v_day := v_day + 1;
      end loop;
    end loop;
  end if;
  return new;
end $function$;

create or replace function public.tg_work_assignment_participant_link()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_wa public.work_assignments;
  v_day date; v_end date; v_type_id uuid; v_year integer;
begin
  select * into v_wa from public.work_assignments where id = new.assignment_id;
  if not found or v_wa.status <> 'APPROVED' then return new; end if;
  v_day := (v_wa.start_at at time zone 'Africa/Cairo')::date;
  v_end := (v_wa.end_at at time zone 'Africa/Cairo')::date;
  while v_day <= v_end loop
    if coalesce(v_wa.counts_as_work_day, true) then
      insert into public.attendance_daily(employee_id, work_date, status)
      values(new.employee_id, v_day, 'present')
      on conflict on constraint attendance_daily_uq do update
        set status = 'present', updated_at = now()
        where public.attendance_daily.is_finalized = false
          and public.attendance_daily.status not in ('holiday','weekend');
    end if;
    if extract(isodow from v_day) = 5 then
      select id into v_type_id from public.leave_types where code = 'weekly_rest_comp';
      if v_type_id is not null then
        v_year := extract(year from v_day)::integer;
        perform public.apply_leave_ledger_entry(
          new.employee_id, v_type_id, v_year, 'credit', 1,
          'weekly-rest:credit:' || new.employee_id::text || ':' || v_day::text,
          null,
          'رصيد بدل راحة أسبوعي عن تكليف عمل يوم الجمعة ' || to_char(v_day, 'YYYY-MM-DD'),
          jsonb_build_object('workDate', v_day::text, 'source', 'work-assignment', 'assignmentId', v_wa.id)
        );
      end if;
    end if;
    v_day := v_day + 1;
  end loop;
  return new;
end $function$;

-- ═══════════════════════════════════════════════════════════════════════
-- 3) تصفية بصمة الخروج الناقصة: استثناء أيام التكليفات المعتمدة
--    (البصمة المُشتقّة من المأمورية ليست نقصاً — المأمورية نفسها انصراف)
-- ═══════════════════════════════════════════════════════════════════════
create or replace function public.finalize_missing_checkouts()
 returns integer
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_count integer := 0;
  v_grace_minutes integer;
  v_tz text;
  v_now timestamptz := now();
  v_rec record;
  v_shift public.shifts%rowtype;
  v_deadline timestamptz;
begin
  if current_user not in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'attendance_trusted_server_required' using errcode = '42501';
  end if;

  select s.missing_checkout_grace_minutes, s.timezone
    into v_grace_minutes, v_tz
  from public.attendance_settings s
  limit 1;
  v_grace_minutes := coalesce(v_grace_minutes, 60);
  v_tz := coalesce(v_tz, 'Africa/Cairo');

  for v_rec in
    select ad.id, ad.employee_id, ad.work_date, ad.shift_id
    from public.attendance_daily ad
    where ad.first_check_in is not null
      and ad.last_check_out is null
      and not ad.is_finalized
      and ad.status not in ('on_leave', 'holiday', 'weekend', 'missing_checkout')
      -- يوم مغطّى بمأمورية/قافلة/فاندي/تكليف معتمد = عمل خارجي → لا يُصفّى كنقص
      and not exists (
        select 1 from public.requests r
        where r.employee_id = ad.employee_id and r.status = 'approved'
          and r.request_type in ('mission','convoy','fundraising')
          and ad.work_date between public._payload_date(r.payload, 'startDate')
                               and coalesce(public._payload_date(r.payload, 'endDate'), public._payload_date(r.payload, 'startDate'))
      )
      and not exists (
        select 1 from public.work_assignment_participants wp
        join public.work_assignments wa on wa.id = wp.assignment_id
        where wp.employee_id = ad.employee_id and wa.status = 'APPROVED'
          and ad.work_date between (wa.start_at at time zone 'Africa/Cairo')::date
                               and (wa.end_at at time zone 'Africa/Cairo')::date
      )
    for update skip locked
  loop
    v_shift := null;
    if v_rec.shift_id is not null then
      select * into v_shift
      from public.shifts
      where id = v_rec.shift_id;
    end if;

    if v_shift.id is not null then
      v_deadline := (
        v_rec.work_date
        + case when v_shift.crosses_midnight then 1 else 0 end
        + v_shift.end_time
      ) at time zone v_tz
      + make_interval(mins => v_grace_minutes);
    else
      v_deadline := (v_rec.work_date + '18:00'::time) at time zone v_tz
                    + make_interval(mins => v_grace_minutes);
    end if;

    if v_now > v_deadline then
      update public.attendance_daily
      set status = 'missing_checkout', updated_at = now()
      where id = v_rec.id and not is_finalized;

      if found then
        insert into public.attendance_exceptions(
          employee_id, attendance_daily_id, work_date, kind, description
        )
        select
          v_rec.employee_id,
          v_rec.id,
          v_rec.work_date,
          'missing_check_out',
          'بصمة خروج مفقودة — أُنشئ تلقائياً بواسطة finalize_missing_checkouts'
        where not exists (
          select 1
          from public.attendance_exceptions ae
          where ae.attendance_daily_id = v_rec.id
            and ae.kind = 'missing_check_out'
            and ae.status in ('open', 'approved', 'resolved')
        );

        perform public.log_audit_event(
          'attendance.missing_checkout_finalized', 'operations', 'warning',
          'attendance_daily', v_rec.id,
          'بصمة خروج مفقودة — تصفية تلقائية', null,
          jsonb_build_object(
            'workDate', v_rec.work_date,
            'shiftId', v_rec.shift_id,
            'deadline', v_deadline
          )
        );
        v_count := v_count + 1;
      end if;
    end if;
  end loop;

  return v_count;
end $function$;

-- ═══════════════════════════════════════════════════════════════════════
-- 4) Backfill: إعادة تعليم الأيام المعلّمة إجازة إلى حضور + ضبط الخانات
-- ═══════════════════════════════════════════════════════════════════════
do $backfill$
declare
  v_r record;
  v_start date; v_end date; v_t text;
begin
  -- أ) ضبط الخانات الخاصة للطلبات المعتمدة القديمة (من payload)
  insert into public.missions (request_id, employee_id, destination, purpose, start_at, end_at, created_by)
  select r.id, r.employee_id, coalesce(r.payload->>'location', ''), coalesce(r.title, ''),
         (public._payload_date(r.payload, 'startDate')::text
          || case when r.payload->>'startTime' is not null then 'T' || (r.payload->>'startTime') || ':00' else 'T00:00:00' end)::timestamp at time zone 'Africa/Cairo',
         (coalesce(public._payload_date(r.payload, 'endDate'), public._payload_date(r.payload, 'startDate'))::text
          || case when r.payload->>'endTime' is not null then 'T' || (r.payload->>'endTime') || ':00' else 'T00:00:00' end)::timestamp at time zone 'Africa/Cairo',
         r.created_by
  from public.requests r
  where r.request_type = 'mission' and r.status = 'approved'
    and public._payload_date(r.payload, 'startDate') is not null
    and not exists (select 1 from public.missions m where m.request_id = r.id);

  insert into public.convoy_requests (request_id, employee_id, convoy_name, origin, destination, departure_at, return_at, created_by)
  select r.id, r.employee_id,
         coalesce(coalesce(r.payload->>'convoyName', r.title), ''),
         coalesce(r.payload->>'origin', ''), coalesce(r.payload->>'location', ''),
         (public._payload_date(r.payload, 'startDate')::text
          || case when r.payload->>'startTime' is not null then 'T' || (r.payload->>'startTime') || ':00' else 'T00:00:00' end)::timestamp at time zone 'Africa/Cairo',
         (coalesce(public._payload_date(r.payload, 'endDate'), public._payload_date(r.payload, 'startDate'))::text
          || case when r.payload->>'endTime' is not null then 'T' || (r.payload->>'endTime') || ':00' else 'T00:00:00' end)::timestamp at time zone 'Africa/Cairo',
         r.created_by
  from public.requests r
  where r.request_type = 'convoy' and r.status = 'approved'
    and public._payload_date(r.payload, 'startDate') is not null
    and not exists (select 1 from public.convoy_requests c where c.request_id = r.id);

  -- ب) إعادة تعليم أيام المأموريات/القوافل/الفاندي/التكليفات من on_leave إلى present
  update public.attendance_daily ad
  set status = 'present', updated_at = now()
  where ad.status = 'on_leave' and ad.is_finalized = false
    and (
      exists (
        select 1 from public.requests r
        where r.employee_id = ad.employee_id and r.status = 'approved'
          and r.request_type in ('mission','convoy','fundraising')
          and ad.work_date between public._payload_date(r.payload, 'startDate')
                               and coalesce(public._payload_date(r.payload, 'endDate'), public._payload_date(r.payload, 'startDate'))
      )
      or exists (
        select 1 from public.missions m join public.requests r on r.id = m.request_id
        where m.employee_id = ad.employee_id and r.status = 'approved'
          and ad.work_date between (m.start_at at time zone 'Africa/Cairo')::date
                               and (m.end_at at time zone 'Africa/Cairo')::date
      )
      or exists (
        select 1 from public.convoy_requests c join public.requests r on r.id = c.request_id
        where c.employee_id = ad.employee_id and r.status = 'approved'
          and ad.work_date between (c.departure_at at time zone 'Africa/Cairo')::date
                               and (coalesce(c.return_at, c.departure_at) at time zone 'Africa/Cairo')::date
      )
      or exists (
        select 1 from public.work_assignment_participants wp join public.work_assignments wa on wa.id = wp.assignment_id
        where wp.employee_id = ad.employee_id and wa.status = 'APPROVED'
          and ad.work_date between (wa.start_at at time zone 'Africa/Cairo')::date
                               and (wa.end_at at time zone 'Africa/Cairo')::date
      )
    );

  -- ج) بصمات الحضور/الانصراف من أوقات الطلبات المعتمدة
  for v_r in
    select r.id, r.employee_id, r.payload
    from public.requests r
    where r.status = 'approved' and r.request_type in ('mission','convoy')
      and r.payload is not null
      and public._payload_date(r.payload, 'startDate') is not null
  loop
    v_start := public._payload_date(v_r.payload, 'startDate');
    v_end := coalesce(public._payload_date(v_r.payload, 'endDate'), v_start);
    v_t := v_r.payload->>'startTime';
    if v_t is not null then
      update public.attendance_daily
      set first_check_in = (v_start::text || 'T' || v_t || ':00')::timestamp at time zone 'Africa/Cairo',
          updated_at = now()
      where employee_id = v_r.employee_id and work_date = v_start
        and first_check_in is null and is_finalized = false;
    end if;
    v_t := v_r.payload->>'endTime';
    if v_t is not null then
      update public.attendance_daily
      set last_check_out = (v_end::text || 'T' || v_t || ':00')::timestamp at time zone 'Africa/Cairo',
          updated_at = now()
      where employee_id = v_r.employee_id and work_date = v_end
        and last_check_out is null and is_finalized = false;
    end if;
  end loop;
end $backfill$;
