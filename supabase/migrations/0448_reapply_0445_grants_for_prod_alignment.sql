-- =====================================================================
-- 0448: إعادة تطبيق تشديد صلاحيات 0445 على قواعد بيانات قائمة
-- ---------------------------------------------------------------------
-- السياق (انجراف ترقيم): سُجِّل على الإنتاج migration بالرقم 0445 باسم
-- مختلف (grant_attendance_dashboard_execute) عبر Management API قبل دخول
-- ملف 0445 الحالي إلى المستودع. `supabase db push` يقارن بالأرقام فقط،
-- لذلك يُتجاهَل 0445 المستودعي على أي قاعدة سُجِّل عندها الرقم مسبقاً
-- ولا يصل تشديد الصلاحيات إليها.
--
-- هذا الملف يعيد تطبيق نفس منطق 0445 الشرطي حرفياً (معرّف ذاتياً):
--   - على قاعدة نظيفة: لا تغيير (0445 طبّقه أصلاً — GRANT تكراري بلا أثر).
--   - على قاعدة قائمة (الإنتاج): يطبّق التشديد الفعلي فيتطابق حالها
--     مع القواعد الجديدة.
-- =====================================================================

begin;

do $hardening$
declare
  r record;
begin
  -- دوال تُستهلك من الواجهات: سحب عن public/anon ومنح authenticated
  -- لأي توقيع موجود فعلياً بهذا الاسم (نفس منطق 0445).
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

-- إعادة تحميل كاش PostgREST فوراً بعد تغيير الصلاحيات.
notify pgrst, 'reload schema';
