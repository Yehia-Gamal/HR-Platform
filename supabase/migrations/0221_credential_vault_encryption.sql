-- 0221: تشفير خزنة الاعتمادات — دوال SECURITY DEFINER للقراءة والكتابة المشفّرة
--
-- يعتمد على: 0011 (credential_vault + audit_events + log_audit_event),
--             0045 (REVOKE authenticated/anon),
--             0001/0048 (pgcrypto)
--
-- التشفير يستخدم pgp_sym_encrypt/decrypt مع مفتاح التطبيق app.credential_key
-- الذي يُضبط كـ Supabase secret أو عبر ALTER DATABASE ... SET app.credential_key.
--
-- الجدول credential_vault موجود مسبقاً مع عمود secret_ciphertext (bytea).
-- هذه الهجرة تضيف دوال آمنة للتعامل مع التشفير/فكّ التشفير + تسجيل تدقيقي.

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════
-- 0) حماية: إنشاء الجدول إن لم يكن موجوداً (احتياطي فقط)
-- ═══════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.credential_vault (
  id                uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  key_name          text        NOT NULL UNIQUE,
  category          text        NOT NULL DEFAULT 'general'
                      CHECK (category IN ('general','integration','smtp','sms','payment','signing','api_key','oauth')),
  secret_ciphertext bytea,
  secret_hint       text,
  metadata          jsonb       NOT NULL DEFAULT '{}'::jsonb,
  rotated_at        timestamptz,
  expires_at        timestamptz,
  is_active         boolean     NOT NULL DEFAULT true,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz,
  created_by        uuid        REFERENCES auth.users(id)
);

ALTER TABLE public.credential_vault ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.credential_vault FORCE ROW LEVEL SECURITY;

-- ═══════════════════════════════════════════════════════════════════════
-- 1) دالة تخزين اعتماد مشفّر — store_credential
--    تُدخل أو تُحدّث سجلاً في credential_vault بقيمة مشفّرة عبر PGP.
--    مسموحة فقط لأصحاب الصلاحية الكاملة (full-access).
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.store_credential(
  p_key_name    text,
  p_value       text,
  p_category    text    DEFAULT 'general',
  p_hint        text    DEFAULT NULL,
  p_metadata    jsonb   DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_enc_key text;
BEGIN
  -- فحص الصلاحية
  IF NOT public.current_is_full_access() THEN
    RAISE EXCEPTION 'ERR_FORBIDDEN'
      USING HINT = 'store_credential يتطلب صلاحية full-access';
  END IF;

  -- التحقق من وجود مفتاح التشفير
  v_enc_key := current_setting('app.credential_key', true);
  IF v_enc_key IS NULL OR length(trim(v_enc_key)) = 0 THEN
    RAISE EXCEPTION 'ERR_MISSING_ENCRYPTION_KEY'
      USING HINT = 'app.credential_key غير مُعرَّف — اضبطه كـ Supabase secret';
  END IF;

  -- إدراج أو تحديث
  INSERT INTO public.credential_vault
    (key_name, secret_ciphertext, category, secret_hint, metadata, rotated_at, created_by)
  VALUES (
    p_key_name,
    pgp_sym_encrypt(p_value, v_enc_key),
    p_category,
    p_hint,
    COALESCE(p_metadata, '{}'::jsonb),
    now(),                          -- rotated_at = وقت آخر تدوير
    auth.uid()
  )
  ON CONFLICT (key_name) DO UPDATE SET
    secret_ciphertext = pgp_sym_encrypt(p_value, v_enc_key),
    category          = COALESCE(NULLIF(p_category, ''), credential_vault.category),
    secret_hint       = COALESCE(p_hint, credential_vault.secret_hint),
    metadata          = credential_vault.metadata || COALESCE(p_metadata, '{}'::jsonb),
    rotated_at        = now(),
    updated_at        = now();

  -- تسجيل تدقيقي
  PERFORM public.log_audit_event(
    p_event_type   := 'credential.stored',
    p_category     := 'security',
    p_severity     := 'notice',
    p_target_table := 'credential_vault',
    p_summary_ar   := 'تخزين/تحديث اعتماد مشفّر: ' || p_key_name,
    p_metadata     := jsonb_build_object(
      'key_name', p_key_name,
      'category', p_category,
      'has_hint', (p_hint IS NOT NULL)
    )
  );
END;
$$;

COMMENT ON FUNCTION public.store_credential(text, text, text, text, jsonb) IS
  'تخزين اعتماد مشفّر في credential_vault (UPSERT). يتطلب full-access + app.credential_key.';

-- صلاحيات التنفيذ
REVOKE ALL ON FUNCTION public.store_credential(text, text, text, text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.store_credential(text, text, text, text, jsonb) TO authenticated;


-- ═══════════════════════════════════════════════════════════════════════
-- 2) دالة قراءة اعتماد مفكوك التشفير — read_credential
--    تُرجع القيمة النصية المفكوكة أو NULL إن لم يُوجد السجل.
--    مسموحة فقط لأصحاب الصلاحية الكاملة (full-access).
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.read_credential(p_key_name text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_ciphertext bytea;
  v_enc_key    text;
BEGIN
  -- فحص الصلاحية
  IF NOT public.current_is_full_access() THEN
    RAISE EXCEPTION 'ERR_FORBIDDEN'
      USING HINT = 'read_credential يتطلب صلاحية full-access';
  END IF;

  -- جلب القيمة المشفّرة (فقط السجلات النشطة)
  SELECT secret_ciphertext
    INTO v_ciphertext
    FROM public.credential_vault
   WHERE key_name = p_key_name
     AND is_active = true;

  IF v_ciphertext IS NULL THEN
    RETURN NULL;
  END IF;

  -- التحقق من وجود مفتاح التشفير
  v_enc_key := current_setting('app.credential_key', true);
  IF v_enc_key IS NULL OR length(trim(v_enc_key)) = 0 THEN
    RAISE EXCEPTION 'ERR_MISSING_ENCRYPTION_KEY'
      USING HINT = 'app.credential_key غير مُعرَّف — اضبطه كـ Supabase secret';
  END IF;

  -- تسجيل تدقيقي (قبل فك التشفير — حتى لو فشل)
  PERFORM public.log_audit_event(
    p_event_type   := 'credential.read',
    p_category     := 'security',
    p_severity     := 'notice',
    p_target_table := 'credential_vault',
    p_summary_ar   := 'قراءة اعتماد مشفّر: ' || p_key_name,
    p_metadata     := jsonb_build_object('key_name', p_key_name)
  );

  RETURN pgp_sym_decrypt(v_ciphertext, v_enc_key);
END;
$$;

COMMENT ON FUNCTION public.read_credential(text) IS
  'قراءة اعتماد مفكوك التشفير من credential_vault. يتطلب full-access + app.credential_key.';

-- صلاحيات التنفيذ
REVOKE ALL ON FUNCTION public.read_credential(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.read_credential(text) TO authenticated;


-- ═══════════════════════════════════════════════════════════════════════
-- 3) دالة حذف (تعطيل) اعتماد — revoke_credential
--    لا تحذف فعلياً — تُعطّل السجل (soft delete) مع تسجيل تدقيقي.
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.revoke_credential(p_key_name text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_found boolean;
BEGIN
  -- فحص الصلاحية
  IF NOT public.current_is_full_access() THEN
    RAISE EXCEPTION 'ERR_FORBIDDEN'
      USING HINT = 'revoke_credential يتطلب صلاحية full-access';
  END IF;

  UPDATE public.credential_vault
     SET is_active   = false,
         updated_at  = now()
   WHERE key_name    = p_key_name
     AND is_active   = true;

  v_found := FOUND;

  IF v_found THEN
    PERFORM public.log_audit_event(
      p_event_type   := 'credential.revoked',
      p_category     := 'security',
      p_severity     := 'warning',
      p_target_table := 'credential_vault',
      p_summary_ar   := 'تعطيل اعتماد: ' || p_key_name,
      p_metadata     := jsonb_build_object('key_name', p_key_name)
    );
  END IF;

  RETURN v_found;
END;
$$;

COMMENT ON FUNCTION public.revoke_credential(text) IS
  'تعطيل اعتماد في credential_vault (soft delete). يتطلب full-access.';

REVOKE ALL ON FUNCTION public.revoke_credential(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.revoke_credential(text) TO authenticated;


-- ═══════════════════════════════════════════════════════════════════════
-- 4) دالة استعراض الاعتمادات — list_credentials
--    تُرجع البيانات الوصفية فقط (بدون القيمة المشفّرة أبداً).
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.list_credentials(
  p_category text DEFAULT NULL,
  p_active_only boolean DEFAULT true
)
RETURNS TABLE (
  key_name      text,
  category      text,
  secret_hint   text,
  metadata      jsonb,
  is_active     boolean,
  rotated_at    timestamptz,
  expires_at    timestamptz,
  created_at    timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
BEGIN
  IF NOT public.current_is_full_access() THEN
    RAISE EXCEPTION 'ERR_FORBIDDEN'
      USING HINT = 'list_credentials يتطلب صلاحية full-access';
  END IF;

  RETURN QUERY
    SELECT cv.key_name, cv.category, cv.secret_hint, cv.metadata,
           cv.is_active, cv.rotated_at, cv.expires_at, cv.created_at
      FROM public.credential_vault cv
     WHERE (p_category IS NULL OR cv.category = p_category)
       AND (NOT p_active_only OR cv.is_active = true)
     ORDER BY cv.key_name;
END;
$$;

COMMENT ON FUNCTION public.list_credentials(text, boolean) IS
  'استعراض بيانات الاعتمادات الوصفية (بدون القيم المشفّرة). يتطلب full-access.';

REVOKE ALL ON FUNCTION public.list_credentials(text, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_credentials(text, boolean) TO authenticated;


-- ═══════════════════════════════════════════════════════════════════════
-- 5) تأكيد سحب الصلاحيات المباشرة (دفاع بالعمق — idempotent)
-- ═══════════════════════════════════════════════════════════════════════
REVOKE SELECT, INSERT, UPDATE, DELETE ON public.credential_vault FROM authenticated, anon;


-- ═══════════════════════════════════════════════════════════════════════
-- 6) إعادة تحميل مخطط PostgREST
-- ═══════════════════════════════════════════════════════════════════════
NOTIFY pgrst, 'reload schema';

COMMIT;
