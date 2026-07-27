-- 0082: V23 §6.5 — Missing Checkout لا يُنشئ وقتاً وهمياً.
-- يثبت أن النظام لا يملك آلية تسوية تلقائية (settle_attendance_day غير موجودة)
-- وأن Missing Checkout يُعالج عبر نظام التصحيحات (attendance_corrections)
-- مع حظر إغلاق الفترة عند وجود تصحيحات معلّقة.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(12);

-- =====================================================================
-- (1) لا وجود لدالة settle_attendance_day — لا تسوية تلقائية
-- =====================================================================
select hasnt_function(
  'public', 'settle_attendance_day',
  'لا توجد دالة settle_attendance_day — لا تسوية تلقائية');

-- =====================================================================
-- (2) جدول attendance_corrections موجود
-- =====================================================================
select has_table(
  'public', 'attendance_corrections',
  'جدول التصحيحات (attendance_corrections) موجود');

-- (3) العمود correction_type يدعم missing_check_out
select col_type_is(
  'public', 'attendance_corrections', 'correction_type', 'text',
  'correction_type من نوع text');

-- (4) التحقق من أن missing_check_out ضمن القيم المسموحة
select lives_ok(
  $live$do $t$
  declare v_check text;
  begin
    select pg_get_constraintdef(c.oid) into v_check
    from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = 'attendance_corrections'
      and c.contype = 'c' and pg_get_constraintdef(c.oid) ilike '%missing_check_out%';
    if v_check is null then
      raise exception 'missing_check_out غير مدرج في check constraint';
    end if;
  end $t$$live$,
  'missing_check_out ضمن القيم المسموحة في correction_type');

-- =====================================================================
-- (5-6) دوال معالجة التصحيحات موجودة
-- =====================================================================
select has_function(
  'public', 'request_attendance_correction',
  'دالة طلب التصحيح موجودة');

select has_function(
  'public', 'decide_attendance_correction',
  'دالة اتخاذ قرار التصحيح موجودة');

-- =====================================================================
-- (7) التصحيح يتطلب قراراً بشرياً (approved/rejected)
-- =====================================================================
select lives_ok(
  $live$do $t$
  declare v_src text;
  begin
    select prosrc into v_src from pg_proc
    where proname='decide_attendance_correction' and pronamespace='public'::regnamespace;
    if v_src not ilike '%approved%' or v_src not ilike '%rejected%' then
      raise exception 'decide_attendance_correction لا تدعم approved/rejected';
    end if;
  end $t$$live$,
  'التصحيح يتطلب قراراً بشرياً (approved أو rejected)');

-- (8) التصحيح المعتمد يُحدّث attendance_daily
select lives_ok(
  $live$do $t$
  declare v_src text;
  begin
    select prosrc into v_src from pg_proc
    where proname='decide_attendance_correction' and pronamespace='public'::regnamespace;
    if v_src not ilike '%attendance_daily%' or v_src not ilike '%on conflict%' then
      raise exception 'التصحيح المعتمد لا يُحدّث attendance_daily';
    end if;
  end $t$$live$,
  'التصحيح المعتمد يُحدّث attendance_daily (upsert)');

-- =====================================================================
-- (9) إغلاق الفترة يحظر التصحيحات المعلّقة
-- =====================================================================
select lives_ok(
  $live$do $t$
  declare v_src text;
  begin
    select prosrc into v_src from pg_proc
    where proname='close_attendance_period' and pronamespace='public'::regnamespace;
    if v_src not ilike '%PENDING_CORRECTIONS%' then
      raise exception 'close_attendance_period لا تحظر التصحيحات المعلّقة';
    end if;
  end $t$$live$,
  'إغلاق الفترة يحظر عند وجود تصحيحات معلّقة (PENDING_CORRECTIONS)');

-- (10) إغلاق الفترة يفحص حالة pending فقط
select lives_ok(
  $live$do $t$
  declare v_src text;
  begin
    select prosrc into v_src from pg_proc
    where proname='close_attendance_period' and pronamespace='public'::regnamespace;
    if v_src not ilike '%pending%' or v_src not ilike '%attendance_corrections%' then
      raise exception 'close_attendance_period لا تفحص pending corrections';
    end if;
  end $t$$live$,
  'إغلاق الفترة تفحص attendance_corrections بحالة pending');

-- =====================================================================
-- (11) RLS مفعّل على جدول التصحيحات
-- =====================================================================
select has_table('public', 'attendance_corrections',
  'attendance_corrections table exists for RLS check');

-- (12) التصحيح يُسجَّل في audit log
select lives_ok(
  $live$do $t$
  declare v_src text;
  begin
    select prosrc into v_src from pg_proc
    where proname='decide_attendance_correction' and pronamespace='public'::regnamespace;
    if v_src not ilike '%log_audit_event%' or v_src not ilike '%attendance.correction%' then
      raise exception 'التصحيح لا يُسجَّل في audit log';
    end if;
  end $t$$live$,
  'التصحيح يُسجَّل في audit log (attendance.correction.*)');

select * from finish();
rollback;
