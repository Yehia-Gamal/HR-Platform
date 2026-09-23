-- =====================================================================
-- 0551: سحب EXECUTE من PUBLIC/anon على دوال SECURITY DEFINER المتسرّبة
--
-- الخلل المتكرر (0536، 0541، 0547، 0532): create/replace أو grant لـ
-- authenticated يعيدان منحة PUBLIC الافتراضية (=X) أو منحة anon الصريحة.
-- في PostgreSQL: has_function_privilege(anon, …, 'EXECUTE') = true طالما
-- PUBLIC يملك EXECUTE — حتى لو سُحبت منحة anon الصريحة.
--
-- الأثر: أي زائر (anon key) يمكنه استدعاء دوال HR عبر REST rpc —
-- قوائم الحضور، إعدادات الغرامة، الخزينة، مخطط التنظيمي …
--
-- الإصلاح (بنمط 0209 المعتمد):
--   1) REVOKE EXECUTE … FROM PUBLIC, anon على كل دوال public
--      عدا الاستثناءات المقصودة (get_public_*, activate_*, handle_new_user)
--      + دوال الامتدادات + دوال trigger.
--   2) GRANT EXECUTE … TO authenticated, service_role (تثبيت صريح).
--   3) منع الانحدار عبر ALTER DEFAULT PRIVILEGES (مكرر مع 0209 — آمن).
-- ملاحظة: count (authenticated عبر PUBLIC فقط) = 0 قبل هذا الترحيل،
-- فسحب PUBLIC لا يكسر أي مستخدم مصادَق.
-- =====================================================================

begin;

do $revoke$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure::text as sig,
           p.proname
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname not in (
        -- استثناءات مقصودة (0207/0209/0038)
        'handle_new_user',
        'activate_employee_after_first_login',
        'get_public_release_policy'
      )
      and p.proname not like 'get\_public\_%'
      -- لا نلمس دوال الامتدادات
      and not exists (
        select 1
        from pg_depend d
        join pg_extension e on d.refobjid = e.oid
        where d.objid = p.oid and d.deptype = 'e'
      )
  loop
    execute format('revoke execute on function %s from public, anon', r.sig);
    execute format('grant execute on function %s to authenticated, service_role', r.sig);
  end loop;
end $revoke$;

-- استثناءات: تضمن بقاء الوظائف المقصودة لـ anon
grant execute on function public.handle_new_user() to anon;
grant execute on function public.activate_employee_after_first_login() to anon;
grant execute on function public.get_public_release_policy(text, text, text, integer, text) to anon;

-- دوال get_public_* الأخرى المعلنة بالاسم (إن وجدت overload)
do $keep_public$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure::text as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname like 'get\_public\_%'
  loop
    execute format('grant execute on function %s to anon, authenticated, service_role', r.sig);
  end loop;
end $keep_public$;

-- منع انحدار الدوال الجديدة (تكرار مع 0209 — idempotent)
alter default privileges in schema public
  revoke execute on functions from public;
alter default privileges in schema public
  grant execute on functions to authenticated, service_role;

commit;
