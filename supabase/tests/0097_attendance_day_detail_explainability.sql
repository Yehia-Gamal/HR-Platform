-- 0097: 0252 — إثراء كل يوم في كشف الحضور الشهري بكائن "details" توضيحي
-- يثبت أن الواجهة النهائية _build_attendance_statement:
--   1) تستدعي v266 (0266) الذي يستدعي v252 الذي يستدعي v251.
--   2) تضيف لكل يوم details: { leave, assignment, permit, correction, missing }.
--   3) تحمل مفاتيح التفسيرية (attendanceRateBasis, requiredMinutes, compliantWorkMinutes).
--   4) تحافظ على منح الوصول الحصري (service_role فقط، وال版本es الخاصة).

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
set local timezone = 'Africa/Cairo';
select plan(18);

-- =====================================================================
-- 1. البنية والمنح
-- =====================================================================
select ok(
  to_regprocedure('public._build_attendance_statement_v251(uuid,integer,integer)') is not null,
  'المُجمع 0251 محفوظ تحت اسم خاص _build_attendance_statement_v251'
);

select ok(
  has_function_privilege(
    'service_role',
    'public._build_attendance_statement(uuid,integer,integer)',
    'EXECUTE'
  ),
  'service_role ينفّذ الواجهة النهائية للكشف'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public._build_attendance_statement(uuid,integer,integer)',
    'EXECUTE'
  ),
  'authenticated لا ينفّذ الواجهة النهائية مباشرة'
);

select ok(
  not has_function_privilege(
    'anon',
    'public._build_attendance_statement(uuid,integer,integer)',
    'EXECUTE'
  ),
  'anon لا ينفّذ الواجهة النهائية'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public._build_attendance_statement_v251(uuid,integer,integer)',
    'EXECUTE'
  ),
  'v251 (المُجمع 0251) تبقى خاصة'
);

select ok(
  not has_function_privilege(
    'anon',
    'public._build_attendance_statement_v251(uuid,integer,integer)',
    'EXECUTE'
  ),
  'anon لا ينفّذ v251'
);

select lives_ok(
  $live$do $t$
  declare v_final text;
          v_v266  text;
          v_v252  text;
  begin
    select prosrc into v_final from pg_proc
    where proname='_build_attendance_statement' and pronamespace='public'::regnamespace;
    if v_final not ilike '%_build_attendance_statement_v266%' then
      raise exception 'الواجهة النهائية لا تستدعي v266';
    end if;
    select prosrc into v_v266 from pg_proc
    where proname='_build_attendance_statement_v266' and pronamespace='public'::regnamespace;
    if v_v266 not ilike '%_build_attendance_statement_v252%' then
      raise exception 'v266 لا تستدعي v252';
    end if;
    select prosrc into v_v252 from pg_proc
    where proname='_build_attendance_statement_v252' and pronamespace='public'::regnamespace;
    if v_v252 not ilike '%details%'
       or v_v252 not ilike '%typeLabel%'
       or v_v252 not ilike '%_build_attendance_statement_v251%' then
      raise exception 'v252 لا يحوي منطق التفاصيل التوضيحية عبر v251';
    end if;
  end $t$$live$,
  'السلسلة: final → v266 → v252 → v251 مع تفاصيل توضيحية'
);

-- =====================================================================
-- 2. بيانات الاختبار: إجازة معتمدة + إذن + تصحيح ليوم عمل سابق
-- =====================================================================
create temporary table att_detail_fixture(day date);
grant select on att_detail_fixture to public;

do $fixture$
declare
  v_entity uuid := '97000000-0000-4000-8000-000000000000';
  v_dept   uuid := '97000000-0000-4000-8000-000000000001';
  v_emp    uuid := '97000000-0000-4000-8000-000000000010';
  v_shift  uuid := '97000000-0000-4000-8000-000000000020';
  v_lt     uuid := '97000000-0000-4000-8000-000000000030';
  v_req    uuid := '97000000-0000-4000-8000-000000000040';
  v_day    date := case
    when extract(isodow from current_date - 7) = 5 then current_date - 6
    else current_date - 7
  end;
begin
  insert into public.legal_entities(id, code, name)
    values(v_entity, 'DET-LE', 'كيان تفاصيل الحضور');
  insert into public.departments(id, legal_entity_id, code, name)
    values(v_dept, v_entity, 'DET-D', 'إدارة تفاصيل الحضور');

  insert into public.employees(
    id, employee_code, full_name_ar, department_id, status, is_active,
    birth_date, hire_date
  ) values(
    v_emp, 'DET-001', 'موظف تفاصيل الحضور', v_dept, 'active', true,
    '1992-01-01', '2021-01-01'
  );

  insert into public.shifts(
    id, code, name, start_time, end_time, crosses_midnight,
    break_minutes, grace_in_minutes, grace_out_minutes, is_active
  ) values(
    v_shift, 'DET-SHIFT', 'وردية تفاصيل الحضور', '09:00', '17:00',
    false, 60, 15, 15, true
  );

  insert into public.shift_assignments(
    employee_id, shift_id, effective_from, effective_to, is_active
  ) values(
    v_emp, v_shift, date_trunc('month', v_day)::date, null, true
  );

  insert into public.attendance_daily(
    employee_id, work_date, shift_id, first_check_in, last_check_out,
    work_minutes, status
  ) values(
    v_emp, v_day, v_shift,
    (v_day + time '08:45') at time zone 'Africa/Cairo',
    (v_day + time '17:15') at time zone 'Africa/Cairo',
    480, 'present'
  );

  insert into public.leave_types(id, code, name_ar, affects_balance)
    values(v_lt, 'DET-LT', 'إجازة اختبار التفاصيل', false);

  insert into public.requests(
    id, request_type, employee_id, title, status, workflow_status
  ) values(
    v_req, 'leave', v_emp, 'إجازة ليوم التفاصيل', 'approved', 'completed'
  );

  insert into public.leave_requests(
    request_id, employee_id, leave_type_id, start_date, end_date, days_count
  ) values(
    v_req, v_emp, v_lt, v_day, v_day, 1
  );

  insert into public.attendance_permits(
    employee_id, kind, permit_date, grace_minutes, reason, status
  ) values(
    v_emp, 'arrival', v_day, 15, 'إذن تأخر اختباري', 'approved'
  );

  insert into public.attendance_corrections(
    employee_id, attendance_daily_id, work_date, correction_type,
    reason, status, reviewed_at
  )
  select
    v_emp, ad.id, v_day, 'wrong_time',
    'تصحيح وقت بصمة', 'approved', now()
  from public.attendance_daily ad
  where ad.employee_id = v_emp and ad.work_date = v_day;

  insert into att_detail_fixture(day) values(v_day);
end
$fixture$;

-- =====================================================================
-- 3. السلوك الوظيفي: التفاصيل لكل يوم
-- =====================================================================
select ok(
  (select (d->'details') ? 'leave'
   from jsonb_array_elements(public._build_attendance_statement(
     '97000000-0000-4000-8000-000000000010',
     extract(year from (select day from att_detail_fixture))::integer,
     extract(month from (select day from att_detail_fixture))::integer
   )->'days') d
   where (d->>'date')::date = (select day from att_detail_fixture)),
  'details.leave موجودة ليوم الإجازة'
);

select is(
  (select d->'details'->'leave'->>'typeLabel'
   from jsonb_array_elements(public._build_attendance_statement(
     '97000000-0000-4000-8000-000000000010',
     extract(year from (select day from att_detail_fixture))::integer,
     extract(month from (select day from att_detail_fixture))::integer
   )->'days') d
   where (d->>'date')::date = (select day from att_detail_fixture)),
  'إجازة اختبار التفاصيل',
  'typeLabel يحمل اسم نوع الإجازة'
);

select is(
  (select (d->'details'->'leave'->>'daysCount')::numeric
   from jsonb_array_elements(public._build_attendance_statement(
     '97000000-0000-4000-8000-000000000010',
     extract(year from (select day from att_detail_fixture))::integer,
     extract(month from (select day from att_detail_fixture))::integer
   )->'days') d
   where (d->>'date')::date = (select day from att_detail_fixture)),
  1::numeric,
  'daysCount = 1 ليوم الإجازة'
);

select ok(
  (select (d->'details') ? 'permit'
   from jsonb_array_elements(public._build_attendance_statement(
     '97000000-0000-4000-8000-000000000010',
     extract(year from (select day from att_detail_fixture))::integer,
     extract(month from (select day from att_detail_fixture))::integer
   )->'days') d
   where (d->>'date')::date = (select day from att_detail_fixture)),
  'details.permit موجودة ليوم الإذن'
);

select is(
  (select d->'details'->'permit'->>'kindLabel'
   from jsonb_array_elements(public._build_attendance_statement(
     '97000000-0000-4000-8000-000000000010',
     extract(year from (select day from att_detail_fixture))::integer,
     extract(month from (select day from att_detail_fixture))::integer
   )->'days') d
   where (d->>'date')::date = (select day from att_detail_fixture)),
  'إذن حضور متأخر',
  'kindLabel يصف نوع الإذن'
);

select ok(
  (select (d->'details') ? 'correction'
   from jsonb_array_elements(public._build_attendance_statement(
     '97000000-0000-4000-8000-000000000010',
     extract(year from (select day from att_detail_fixture))::integer,
     extract(month from (select day from att_detail_fixture))::integer
   )->'days') d
   where (d->>'date')::date = (select day from att_detail_fixture)),
  'details.correction موجودة ليوم التصحيح'
);

select is(
  (select d->'details'->'correction'->>'correctionType'
   from jsonb_array_elements(public._build_attendance_statement(
     '97000000-0000-4000-8000-000000000010',
     extract(year from (select day from att_detail_fixture))::integer,
     extract(month from (select day from att_detail_fixture))::integer
   )->'days') d
   where (d->>'date')::date = (select day from att_detail_fixture)),
  'wrong_time',
  'correctionType يعكس نوع التصحيح'
);

select ok(
  not (select coalesce((d->'details'->'missing'->>'checkIn')::boolean, true)
   from jsonb_array_elements(public._build_attendance_statement(
     '97000000-0000-4000-8000-000000000010',
     extract(year from (select day from att_detail_fixture))::integer,
     extract(month from (select day from att_detail_fixture))::integer
   )->'days') d
   where (d->>'date')::date = (select day from att_detail_fixture)),
  'missing.checkIn = false عند تسجيل الحضور'
);

select ok(
  not (select coalesce((d->'details'->'missing'->>'checkOut')::boolean, true)
   from jsonb_array_elements(public._build_attendance_statement(
     '97000000-0000-4000-8000-000000000010',
     extract(year from (select day from att_detail_fixture))::integer,
     extract(month from (select day from att_detail_fixture))::integer
   )->'days') d
   where (d->>'date')::date = (select day from att_detail_fixture)),
  'missing.checkOut = false عند تسجيل الانصراف'
);

with s as (
  select
    public._build_attendance_statement(
      '97000000-0000-4000-8000-000000000010',
      extract(year from (select day from att_detail_fixture))::integer,
      extract(month from (select day from att_detail_fixture))::integer
    )->'summary' as final_summary
)
select ok(
  (s.final_summary ? 'attendanceRateBasis')
  and (s.final_summary->'attendanceRateBasis' ? 'presentInDue')
  and (s.final_summary ? 'requiredMinutes')
  and jsonb_typeof(s.final_summary->'requiredMinutes') = 'number'
  and (s.final_summary ? 'compliantWorkMinutes')
  and jsonb_typeof(s.final_summary->'compliantWorkMinutes') = 'number',
  'الملخص يحوي أساس النسبة والدقائق المطلوبة وال_minutes المتوافقة'
)
from s;

select is(
  (select count(*)::integer
   from jsonb_array_elements(public._build_attendance_statement(
     '97000000-0000-4000-8000-000000000010',
     extract(year from (select day from att_detail_fixture))::integer,
     extract(month from (select day from att_detail_fixture))::integer
   )->'days') d
   where not (d ? 'details')),
  0,
  'كل يوم في الكشف يملك كائن details'
);

select * from finish();
rollback;
