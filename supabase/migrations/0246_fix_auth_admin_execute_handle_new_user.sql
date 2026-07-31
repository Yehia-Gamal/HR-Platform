-- 0246_fix_auth_admin_execute_handle_new_user.sql
-- ═══════════════════════════════════════════════════════════════════════
-- إصلاح حرج: فشل إنشاء الموظفين (admin-create-employee → HTTP 500
-- account_create_failed). السبب الجذري:
--
--   GoTRUE ينفّذ INSERT في auth.users بدور supabase_auth_admin. هذا الإدراج
--   يُطلق المحفّز on_auth_user_created الذي يستدعي public.handle_new_user().
--   محافظات الأمان 0207/0209/0227 سحبت EXECUTE من PUBLIC على كل الدوال
--   وأعادت منح handle_new_user لـ anon فقط — ولم تُمنح أبداً لـ
--   supabase_auth_admin (الدور الذي يُطلق المحفّز فعلياً).
--
--   النتيجة: "permission denied for function handle_new_user" داخل معاملة
--   إنشاء المستخدم → إلغاء المعاملة → GoTRUE يعيد unexpected_failure 500.
--   القراءة (listUsers = SELECT بلا محفّز) تعمل، بينما الإنشاء (INSERT مع
--   المحفّز) يفشل — وهي البصمة المطابقة تماماً للعطل المُلاحَظ.
--
-- الإصلاح: منح EXECUTE على handle_new_user لـ supabase_auth_admin. نُعيد
-- أيضاً تأكيد جسم الدالة كـ no-op (كما في 0081) دفاعياً، ونضمن ثبات المحفّز.
-- ═══════════════════════════════════════════════════════════════════════

begin;

-- إعادة تأكيد الدالة كـ no-op (التوفير يتم صراحةً عبر provision_employee_record
-- / admin-create-employee). SECURITY DEFINER يبقى ليعمل جسمها بصلاحيات المالك.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- فارغة عمداً: توفير الموظفين يتم صراحةً وليس عبر محفّز auth.users.
  return new;
end;
$$;

-- المنح الحاسم: الدور الذي يُطلق المحفّز (supabase_auth_admin) يجب أن يملك
-- EXECUTE، وإلا يفشل كل إدراج في auth.users بـ permission denied.
revoke all on function public.handle_new_user()
  from public, anon, authenticated;
grant execute on function public.handle_new_user() to supabase_auth_admin;

-- ضمان وجود المحفّز وربطه بالدالة الصحيحة (idempotent).
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

commit;
