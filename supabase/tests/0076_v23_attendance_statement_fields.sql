-- pgTAP: V23 §14 — حقول كشف الحضور الشهري الجديدة (migration 0176)
-- يتحقق من: الحقول اليومية (isAbsent, isOfficialHoliday, hasLatePermit, hasEarlyPermit, notes, penalties)
--           والملخص (totalRequiredHours, attendanceRate, hoursComplianceRate)
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(18);

-- ═══════════════════════════════════════════════════════════════════════
-- 1) الدالة لا تزال موجودة بنفس التوقيع
-- ═══════════════════════════════════════════════════════════════════════
select has_function('public', '_build_attendance_statement', array['uuid','integer','integer'],
  '_build_attendance_statement(uuid,int,int) exists');

select ok(
  (select p.prosecdef from pg_proc p
   join pg_namespace n on p.pronamespace = n.oid
   where n.nspname = 'public' and p.proname = '_build_attendance_statement'
   and p.pronargs = 3),
  '_build_attendance_statement is SECURITY DEFINER'
);

select ok(
  exists(
    select 1 from pg_proc p
    join pg_namespace n on p.pronamespace = n.oid
    where n.nspname = 'public' and p.proname = '_build_attendance_statement'
    and exists(select 1 from unnest(p.proconfig) c where c like 'search_path=%')
  ),
  '_build_attendance_statement has pinned search_path'
);

-- ═══════════════════════════════════════════════════════════════════════
-- 2) Fixture: موظف + حضور + عطلة + إذن
-- ═══════════════════════════════════════════════════════════════════════
do $fixture$
declare
  v_le uuid := 'fa000000-0000-4000-8000-000000000000';
  v_dept uuid := 'fa000000-0000-4000-8000-000000000001';
  v_emp uuid := 'fa000000-0000-4000-8000-000000000010';
  v_shift uuid := 'fa000000-0000-4000-8000-000000000020';
begin
  insert into public.legal_entities(id,code,name) values(v_le,'ST76-LE','كيان §14');
  insert into public.departments(id,legal_entity_id,code,name) values(v_dept,v_le,'ST76-D','إدارة §14');
  insert into public.employees(id,employee_code,full_name_ar,department_id,status,is_active,birth_date,hire_date)
    values(v_emp,'ST76-001','موظف كشف V23',v_dept,'active',true,'1990-01-01','2020-01-01');

  -- وردية ثابتة (8 ساعات: 09:00-17:00، بدون استراحة)
  insert into public.shifts(id,name,start_time,end_time,crosses_midnight,break_minutes)
    values(v_shift,'وردية اختبار','09:00','17:00',false,0);

  -- 2026-07-01 (أربعاء) — حاضر مع وردية
  insert into public.attendance_daily(employee_id,work_date,status,shift_id,
    first_check_in,last_check_out,work_minutes,late_minutes)
    values(v_emp,'2026-07-01','present',v_shift,
      '2026-07-01 09:05:00+02','2026-07-01 17:10:00+02',485,5);

  -- 2026-07-02 (خميس) — غائب
  insert into public.attendance_daily(employee_id,work_date,status,work_minutes)
    values(v_emp,'2026-07-02','absent',0);

  -- 2026-07-06 (أحد) — حاضر مع وردية + إذن تأخير معتمد
  insert into public.attendance_daily(employee_id,work_date,status,shift_id,
    first_check_in,last_check_out,work_minutes,late_minutes)
    values(v_emp,'2026-07-06','late',v_shift,
      '2026-07-06 09:30:00+02','2026-07-06 17:00:00+02',450,30);

  insert into public.attendance_permits(employee_id,kind,permit_date,status,grace_minutes)
    values(v_emp,'arrival','2026-07-06','approved',30);

  -- 2026-07-07 (اثنين) — حاضر + إذن انصراف مبكر
  insert into public.attendance_daily(employee_id,work_date,status,shift_id,
    first_check_in,last_check_out,work_minutes,early_leave_minutes)
    values(v_emp,'2026-07-07','present',v_shift,
      '2026-07-07 09:00:00+02','2026-07-07 16:00:00+02',420,60);

  insert into public.attendance_permits(employee_id,kind,permit_date,status,grace_minutes)
    values(v_emp,'departure','2026-07-07','approved',60);

  -- عطلة رسمية: 2026-07-09 (أربعاء)
  insert into public.public_holidays(holiday_date,name,is_active)
    values('2026-07-09','عطلة اختبار',true)
    on conflict do nothing;
end $fixture$;

-- ═══════════════════════════════════════════════════════════════════════
-- 3) تشغيل الكشف
-- ═══════════════════════════════════════════════════════════════════════
-- الكشف يُرجع بيانات
select ok(
  public._build_attendance_statement('fa000000-0000-4000-8000-000000000010', 2026, 7) is not null,
  'statement returns data (not null)');

-- ═══════════════════════════════════════════════════════════════════════
-- 4) V23 حقول يومية — isAbsent
-- ═══════════════════════════════════════════════════════════════════════
-- يوم 2026-07-01 (حاضر) — isAbsent = false
select is(
  (select (d->>'isAbsent')::boolean
   from jsonb_array_elements(
     public._build_attendance_statement('fa000000-0000-4000-8000-000000000010', 2026, 7)->'days'
   ) d where d->>'date' = '2026-07-01'),
  false, '2026-07-01 (present) → isAbsent = false');

-- يوم 2026-07-02 (غائب) — isAbsent = true
select is(
  (select (d->>'isAbsent')::boolean
   from jsonb_array_elements(
     public._build_attendance_statement('fa000000-0000-4000-8000-000000000010', 2026, 7)->'days'
   ) d where d->>'date' = '2026-07-02'),
  true, '2026-07-02 (absent) → isAbsent = true');

-- ═══════════════════════════════════════════════════════════════════════
-- 5) V23 حقول يومية — isOfficialHoliday
-- ═══════════════════════════════════════════════════════════════════════
-- يوم 2026-07-09 (عطلة) — isOfficialHoliday = true
select is(
  (select (d->>'isOfficialHoliday')::boolean
   from jsonb_array_elements(
     public._build_attendance_statement('fa000000-0000-4000-8000-000000000010', 2026, 7)->'days'
   ) d where d->>'date' = '2026-07-09'),
  true, '2026-07-09 (holiday) → isOfficialHoliday = true');

-- يوم 2026-07-01 (عادي) — isOfficialHoliday = false
select is(
  (select (d->>'isOfficialHoliday')::boolean
   from jsonb_array_elements(
     public._build_attendance_statement('fa000000-0000-4000-8000-000000000010', 2026, 7)->'days'
   ) d where d->>'date' = '2026-07-01'),
  false, '2026-07-01 (normal) → isOfficialHoliday = false');

-- ═══════════════════════════════════════════════════════════════════════
-- 6) V23 حقول يومية — hasLatePermit / hasEarlyPermit
-- ═══════════════════════════════════════════════════════════════════════
-- يوم 2026-07-06 — hasLatePermit = true
select is(
  (select (d->>'hasLatePermit')::boolean
   from jsonb_array_elements(
     public._build_attendance_statement('fa000000-0000-4000-8000-000000000010', 2026, 7)->'days'
   ) d where d->>'date' = '2026-07-06'),
  true, '2026-07-06 (arrival permit) → hasLatePermit = true');

-- يوم 2026-07-06 — hasEarlyPermit = false
select is(
  (select (d->>'hasEarlyPermit')::boolean
   from jsonb_array_elements(
     public._build_attendance_statement('fa000000-0000-4000-8000-000000000010', 2026, 7)->'days'
   ) d where d->>'date' = '2026-07-06'),
  false, '2026-07-06 (no departure permit) → hasEarlyPermit = false');

-- يوم 2026-07-07 — hasEarlyPermit = true
select is(
  (select (d->>'hasEarlyPermit')::boolean
   from jsonb_array_elements(
     public._build_attendance_statement('fa000000-0000-4000-8000-000000000010', 2026, 7)->'days'
   ) d where d->>'date' = '2026-07-07'),
  true, '2026-07-07 (departure permit) → hasEarlyPermit = true');

-- ═══════════════════════════════════════════════════════════════════════
-- 7) V23 حقول يومية — notes و penalties
-- ═══════════════════════════════════════════════════════════════════════
-- notes = null لأن attendance_daily ليس فيه عمود notes بعد
select is(
  (select d->>'notes'
   from jsonb_array_elements(
     public._build_attendance_statement('fa000000-0000-4000-8000-000000000010', 2026, 7)->'days'
   ) d where d->>'date' = '2026-07-01'),
  null::text, '2026-07-01 notes = null (column not yet in attendance_daily)');

-- penalties = 0
select is(
  (select (d->>'penalties')::integer
   from jsonb_array_elements(
     public._build_attendance_statement('fa000000-0000-4000-8000-000000000010', 2026, 7)->'days'
   ) d where d->>'date' = '2026-07-01'),
  0, '2026-07-01 penalties = 0 (placeholder)');

-- ═══════════════════════════════════════════════════════════════════════
-- 8) V23 ملخص — totalRequiredHours
-- ═══════════════════════════════════════════════════════════════════════
select ok(
  (public._build_attendance_statement('fa000000-0000-4000-8000-000000000010', 2026, 7)->'summary' ? 'totalRequiredHours'),
  'summary contains totalRequiredHours');

-- ═══════════════════════════════════════════════════════════════════════
-- 9) V23 ملخص — attendanceRate
-- ═══════════════════════════════════════════════════════════════════════
select ok(
  (public._build_attendance_statement('fa000000-0000-4000-8000-000000000010', 2026, 7)->'summary' ? 'attendanceRate'),
  'summary contains attendanceRate');

-- ═══════════════════════════════════════════════════════════════════════
-- 10) V23 ملخص — hoursComplianceRate
-- ═══════════════════════════════════════════════════════════════════════
select ok(
  (public._build_attendance_statement('fa000000-0000-4000-8000-000000000010', 2026, 7)->'summary' ? 'hoursComplianceRate'),
  'summary contains hoursComplianceRate');

select * from finish();
rollback;
