-- سحب صلاحية EXECUTE من anon على كل الدوال التطبيقية الموجودة
-- يستثنى: دوال الامتدادات (citext, pgcrypto, pg_trgm, etc.)
-- يُعاد منح: handle_new_user, activate_employee_after_first_login, get_public_release_policy
-- هذا إصلاح أمني حرج — يمنع المستخدمين غير المصادقين من الوصول للدوال الحساسة
-- ملاحظة: نلغي ديناميكيًا فقط الدوال الموجودة في قاعدة البيانات الحالية (robust عبر البيئات).

BEGIN;

-- دوال يجب أن تبقى متاحة لـ anon (مُعاد منحها بعد السحب)
CREATE TEMPORARY TABLE _0207_keep_anon (fn_name text PRIMARY KEY);
INSERT INTO _0207_keep_anon VALUES
  ('activate_employee_after_first_login'),
  ('get_public_release_policy'),
  ('handle_new_user');

DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure::text AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public'
      -- استثناء الدوال التي أُعيد منحها لـ anon
      AND p.proname NOT IN (SELECT fn_name FROM _0207_keep_anon)
      -- استثناء دوال الامتدادات الشائعة (تُنشأ في public أحيانًا)
      AND p.proname NOT LIKE '%citext%'
      AND p.proname NOT LIKE '%pgcrypto%'
      AND p.proname NOT LIKE '%pg_trgm%'
  LOOP
    EXECUTE 'REVOKE EXECUTE ON FUNCTION ' || r.sig || ' FROM anon';
  END LOOP;
END
$$;

-- إعادة منح الدوال التي تحتاج وصول anon بموجب التصميم
GRANT EXECUTE ON FUNCTION public.activate_employee_after_first_login() TO anon;
GRANT EXECUTE ON FUNCTION public.get_public_release_policy(p_platform text, p_environment text, p_current_version text, p_current_build integer, p_installation_id text) TO anon;
GRANT EXECUTE ON FUNCTION public.handle_new_user() TO anon;

DROP TABLE _0207_keep_anon;

COMMIT;
