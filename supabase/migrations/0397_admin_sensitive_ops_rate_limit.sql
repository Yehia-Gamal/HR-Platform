-- ============================================================================
-- 0395: admin_sensitive_ops_log — جدول تحديد معدل عمليات الإدارة الحساسة
-- ============================================================================
-- يُستخدم من edge functions (admin-set-password / admin-update-email) لمنع
-- الإسراف في تعيين كلمات المرور وتغيير البريد (5 عمليات كل 5 دقائق/مشرف).
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.admin_sensitive_ops_log (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  op_type     text        NOT NULL CHECK (op_type IN ('set_password', 'update_email')),
  actor_id    uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  employee_id uuid        NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
  created_at  timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.admin_sensitive_ops_log IS
  'سجل عمليات تعيين كلمة المرور وتغيير البريد — يُستخدم لتحديد المعدل في edge functions.';

CREATE INDEX IF NOT EXISTS idx_sensitive_ops_actor_type_time
  ON public.admin_sensitive_ops_log (actor_id, op_type, created_at DESC);

-- service_role فقط (عبر Edge Functions) — لا وصول مباشر للمستخدمين
ALTER TABLE public.admin_sensitive_ops_log ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.admin_sensitive_ops_log FROM anon, authenticated;

-- تنظيف تلقائي: احتفظ بسجلات آخر ساعة فقط
CREATE OR REPLACE FUNCTION public.tg_cleanup_sensitive_ops_log()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  DELETE FROM public.admin_sensitive_ops_log
  WHERE created_at < now() - interval '1 hour';
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cleanup_sensitive_ops ON public.admin_sensitive_ops_log;
CREATE TRIGGER trg_cleanup_sensitive_ops
  AFTER INSERT ON public.admin_sensitive_ops_log
  FOR EACH STATEMENT EXECUTE FUNCTION public.tg_cleanup_sensitive_ops_log();

COMMIT;
