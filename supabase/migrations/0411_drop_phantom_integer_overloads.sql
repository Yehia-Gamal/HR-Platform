-- 0411: حذف overloads الوهمية (integer) المتبقية في DB
--
-- بعض الدوال عُدّلت في migrations سابقة (0382/0383/0385) من تواقيع integer
-- إلى uuid (لأن employees.id أصبح uuid)، لكن overloads القديمة التي تأخذ
-- integer بقيت منشورة في الـ DB وظلّت قابلة للاستدعاء — مصدر لبس وخلل محتمل:
--   · apply_leave_ledger_entry(integer, integer, text, numeric, text, text, date)
--   · set_employee_attendance_day_admin(integer, date, text, text)
-- نعيد إنشاء النسخ uuid عبر 0382/0383/0387؛ هنا نحذف فقط الوهمية idempotent
-- (drop function if exists) مع حارس يتحقق أن النسخ uuid موجودة قبل الحذف.

begin;

drop function if exists public.apply_leave_ledger_entry(
  integer, integer, text, numeric, text, text, date
);

drop function if exists public.set_employee_attendance_day_admin(
  integer, date, text, text
);

-- حارس: لا نحذف إلا إذا كانت النسخ uuid موجودة (أي الترقية تمّت فعلاً)
do $$
begin
  if to_regprocedure('public.apply_leave_ledger_entry(uuid, uuid, integer, text, numeric, text, uuid, text, jsonb)') is null then
    raise exception 'apply_leave_ledger_entry(uuid,...) غير موجودة رغم الحذف';
  end if;
  if to_regprocedure('public.set_employee_attendance_day_admin(uuid, date, text, time without time zone, time without time zone, boolean, boolean, text, text, text)') is null then
    raise exception 'set_employee_attendance_day_admin(uuid 10-arg) غير موجودة رغم الحذف';
  end if;
end $$;

commit;
