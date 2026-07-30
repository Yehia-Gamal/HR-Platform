-- =====================================================================
-- الهجرة 0223: تفعيل FORCE RLS على جميع الجداول + حذف سياسات DML الميتة
-- =====================================================================
-- المشكلة:
--   • ~200 جدول يملك ENABLE ROW LEVEL SECURITY لكن ليس FORCE.
--     بدون FORCE، مالك الجدول (postgres / service_role) يتجاوز RLS.
--   • جداول مرجعية (0003) تملك سياسات INSERT/UPDATE/DELETE مبنية على
--     صلاحيات organization.<table>.manage غير المُسجَّلة — ميتة فعلياً
--     لكنها تُبقي ثغرة نظرية. التطبيق يستخدم RPCs حصرياً للكتابة.
--   • scheduled_reports يملك سياسة FOR ALL مفتوحة (0033).
--   • auth_invite_log يملك RLS مُفعّل + GRANT SELECT لكن بدون سياسة.
--
-- الإصلاحات:
--   1. تفعيل ENABLE + FORCE على كل جدول public (حلقة ديناميكية).
--   2. حذف سياسات DML الميتة من الجداول المرجعية.
--   3. استبدال FOR ALL بـ SELECT فقط على scheduled_reports.
--   4. إضافة سياسة SELECT لـ auth_invite_log (full_access فقط).
--   5. شبكة أمان — تحذير بأي جدول متبقٍّ بدون حماية.
-- =====================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════
-- 1. فحص تشخيصي — تسجيل الجداول المكشوفة قبل الإصلاح
-- ═══════════════════════════════════════════════════════════════════════

DO $$
DECLARE
  r       RECORD;
  v_count int := 0;
BEGIN
  FOR r IN
    SELECT c.relname,
           c.relrowsecurity  AS has_enable,
           c.relforcerowsecurity AS has_force
    FROM   pg_class c
    JOIN   pg_namespace n ON n.oid = c.relnamespace
    WHERE  n.nspname = 'public'
      AND  c.relkind = 'r'
      AND  (NOT c.relrowsecurity OR NOT c.relforcerowsecurity)
    ORDER BY c.relname
  LOOP
    RAISE NOTICE '[تشخيص] % — ENABLE=% FORCE=%', r.relname, r.has_enable, r.has_force;
    v_count := v_count + 1;
  END LOOP;

  IF v_count = 0 THEN
    RAISE NOTICE '[تشخيص] جميع الجداول محمية بالفعل — لا توجد ثغرات.';
  ELSE
    RAISE NOTICE '[تشخيص] إجمالي الجداول المكشوفة: %', v_count;
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════════════════════
-- 2. تفعيل ENABLE + FORCE ROW LEVEL SECURITY على جميع جداول public
--    العملية مُتَساقة (idempotent) — لا ضرر إن كان الجدول محمياً سلفاً.
-- ═══════════════════════════════════════════════════════════════════════

DO $$
DECLARE
  r       RECORD;
  v_fixed int := 0;
BEGIN
  FOR r IN
    SELECT c.relname
    FROM   pg_class c
    JOIN   pg_namespace n ON n.oid = c.relnamespace
    WHERE  n.nspname = 'public'
      AND  c.relkind = 'r'
      AND  (NOT c.relrowsecurity OR NOT c.relforcerowsecurity)
    ORDER BY c.relname
  LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', r.relname);
    EXECUTE format('ALTER TABLE public.%I FORCE ROW LEVEL SECURITY', r.relname);
    RAISE NOTICE '[إصلاح] ENABLE + FORCE RLS: %', r.relname;
    v_fixed := v_fixed + 1;
  END LOOP;

  RAISE NOTICE '[إصلاح] تم تأمين % جدول.', v_fixed;
END $$;

-- ═══════════════════════════════════════════════════════════════════════
-- 3. حذف سياسات DML الميتة من الجداول المرجعية (0003)
--    هذه السياسات تستخدم صلاحيات organization.<table>.manage غير المُسجّلة
--    في جدول permissions. فعلياً فقط full_access يمرّ منها.
--    التطبيق يستخدم RPCs (SECURITY DEFINER) حصرياً لكتابة هذه الجداول.
--    نحذفها لإغلاق الثغرة النظرية: الكتابة عبر RPC فقط.
--
--    الجداول: legal_entities, branches, work_sites, cost_centers,
--    departments, teams, positions, job_titles, job_grades,
--    employment_types, shifts, shift_patterns, working_calendars
--    (geofences مُستثنى — سياسة SELECT مقيّدة خاصة)
--    (public_holidays حُذفت سياساته في 0211)
-- ═══════════════════════════════════════════════════════════════════════

DO $$
DECLARE
  t text;
  -- الجداول المرجعية من 0003 (باستثناء public_holidays — نُظّف في 0211)
  ref_tables text[] := ARRAY[
    'legal_entities','branches','work_sites','cost_centers',
    'departments','teams','positions','job_titles','job_grades',
    'employment_types','shifts','shift_patterns','working_calendars',
    'geofences'
  ];
BEGIN
  FOREACH t IN ARRAY ref_tables LOOP
    -- حذف سياسات INSERT/UPDATE/DELETE الميتة
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_insert_manage', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_update_manage', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_delete_manage', t);
    RAISE NOTICE '[تنظيف] حذف سياسات DML الميتة: %', t;
  END LOOP;
END $$;

-- ═══════════════════════════════════════════════════════════════════════
-- 4. إصلاح scheduled_reports — استبدال FOR ALL بـ SELECT فقط
--    السياسة الحالية scheduled_reports_manage (FOR ALL) من 0033 تسمح
--    بـ INSERT/UPDATE/DELETE مباشرة. الكتابة يجب أن تكون عبر RPCs فقط.
-- ═══════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS scheduled_reports_manage ON public.scheduled_reports;

-- السياسة scheduled_reports_read (SELECT) من 0033 لا تزال قائمة —
-- full_access أو reports.schedule.manage. لا حاجة لتعديلها.

-- ═══════════════════════════════════════════════════════════════════════
-- 5. إضافة سياسة SELECT لـ auth_invite_log
--    الجدول يملك RLS مُفعّل (0193) + GRANT SELECT لـ authenticated (0209)
--    لكن بدون أي سياسة SELECT — فعلياً يعيد 0 صفوف دائماً.
--    نضيف سياسة قراءة لـ full_access فقط (سجل الدعوات حساس).
-- ═══════════════════════════════════════════════════════════════════════

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'auth_invite_log'
      AND policyname = 'auth_invite_log_select'
  ) THEN
    EXECUTE $pol$
      CREATE POLICY auth_invite_log_select
        ON public.auth_invite_log
        FOR SELECT TO authenticated
        USING (public.current_is_full_access())
    $pol$;
    RAISE NOTICE '[إصلاح] سياسة SELECT أُضيفت: auth_invite_log';
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════════════════════
-- 6. شبكة أمان — تحذير بأي جدول متبقٍّ بدون RLS
--    للتدقيق المستقبلي: أي هجرة جديدة تنشئ جدولاً بدون ENABLE/FORCE
--    ستظهر هنا عند تشغيل supabase db reset.
-- ═══════════════════════════════════════════════════════════════════════

DO $$
DECLARE
  r       RECORD;
  v_count int := 0;
BEGIN
  FOR r IN
    SELECT c.relname,
           c.relrowsecurity       AS has_enable,
           c.relforcerowsecurity  AS has_force
    FROM   pg_class c
    JOIN   pg_namespace n ON n.oid = c.relnamespace
    WHERE  n.nspname = 'public'
      AND  c.relkind = 'r'
      AND  (NOT c.relrowsecurity OR NOT c.relforcerowsecurity)
    ORDER BY c.relname
  LOOP
    RAISE WARNING '[شبكة أمان] جدول لا يزال مكشوفاً بعد الهجرة 0223: % (ENABLE=% FORCE=%)',
                  r.relname, r.has_enable, r.has_force;
    v_count := v_count + 1;
  END LOOP;

  IF v_count > 0 THEN
    RAISE WARNING '[شبكة أمان] يوجد % جدول بدون حماية RLS كاملة — راجع الهجرات الأخيرة!', v_count;
  ELSE
    RAISE NOTICE '[شبكة أمان] ✓ جميع جداول public محمية بـ ENABLE + FORCE RLS.';
  END IF;
END $$;

COMMIT;
