-- =====================================================================
-- 0445: إصلاح صلاحيات دوال migration 0444 + إعادة تحميل كاش PostgREST
-- ---------------------------------------------------------------------
-- السياق: 0444 أعادت تعريف عدة دوال RPC تستهلكها الواجهات، بعضها
-- جديد تماماً (مثل is_employee_executive) وبعضها استُبدل جسمه فقط.
--
-- ملاحظة PostgreSQL مهمة: CREATE OR REPLACE يحافظ على الـ ACLs القديمة
-- للدوال الموجودة بنفس التوقيع، لكن الدوال الجديدة تأخذ ACL افتراضي
-- (EXECUTE لـ PUBLIC) — وهو ثغرة يجب إغلاقها، والدوال security invoker
-- تحتاج من المستدعي صلاحية EXECUTE على كل دالة تُستدعى داخلياً.
--
-- هذا الملف:
--   1) يسحب EXECUTE عن public/anon ويمنحه لـ authenticated فقط
--      لدوال لمستها 0444 — بشكل شرطي على الوجود الفعلي للتوقيع، لأن
--      0444 أسقطت overload قديماً (get_executive_attendance_today بلا
--      معاملات) واستبدلتها بتوقيع مفلتر، فلا يجوز الربط بتوقيع مفقود
--      وإلا انكسرت السلسلة على قاعدة نظيفة (42883).
--   2) يضمن صلاحية authenticated على is_employee_executive لأن
--      get_attendance_dashboard (security invoker) يستدعيها داخلياً.
--   3) يرسل NOTIFY pgrst لإعادة تحميل كاش الـ schema فوراً حتى لا
--      تفشل نداءات RPC بخطأ PGRST202 بعد نشر 0444.
-- =====================================================================

begin;

do $hardening$
declare
  r record;
begin
  -- دوال تُستهلك من الواجهات: سحب عن public/anon ومنح authenticated
  -- لأي توقيع موجود فعلياً بهذا الاسم (توقيعات 0444 الحالية تحديدًا).
  for r in
    select p.oid::regprocedure AS fn
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in (
        'get_attendance_dashboard',
        'get_executive_attendance_today',
        'get_executive_attendance_overview',
        'get_location_directory',
        'get_mobile_executive_people',
        'get_mobile_employee_directory',
        'get_employees_enriched',
        'request_live_location',
        'is_employee_executive'
      )
  loop
    execute format('revoke execute on function %s from public, anon', r.fn);
    execute format('grant execute on function %s to authenticated', r.fn);
  end loop;

  -- تحديث MV — للاستخدام الداخلي/cron فقط (لا authenticated ولا anon)
  for r in
    select p.oid::regprocedure AS fn
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname = 'refresh_executive_attendance_snapshot'
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', r.fn);
  end loop;
end
$hardening$;

commit;

-- إعادة تحميل كاش PostgREST فوراً حتى لا تُرجع نداءات RPC خطأ
-- "PGRST202 Could not find the function" بعد تغيير التواقيع/الأجسام.
notify pgrst, 'reload schema';
