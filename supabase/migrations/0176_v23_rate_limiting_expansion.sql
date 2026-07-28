-- =====================================================================
-- 0174: V23 §1E — توسيع تحديد المعدل (Rate Limiting) لـ 7 مجالات
--
-- المرجع: V22 §1E (أمان العمليات الحساسة)
-- الوضع السابق: check_invite_rate_limit فقط (0120)
-- V23: مساعد عام check_rate_limit + 6 مجالات إضافية:
--   • employee_create (10/ساعة)
--   • role_assign (20/ساعة)
--   • device_register (5/ساعة)
--   • attendance_punch (60/ساعة)
--   • location_request (10/ساعة)
--   • post_publish (20/ساعة)
--
-- التصميم:
--   جدول rate_limit_log يسجل كل عملية محدودة
--   دالة check_rate_limit(domain, limit, window) عامة
--   دوال متخصصة لكل مجال بحدود ثابتة
--
-- التراجع: DROP TABLE rate_limit_log; DROP FUNCTION check_rate_limit
--   وكل الدوال المتخصصة
-- =====================================================================

-- ═══════════════════════════════════════════════════════════════════════
-- 1) جدول سجل Rate Limit
-- ═══════════════════════════════════════════════════════════════════════
create table if not exists public.rate_limit_log (
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid(),
  domain text not null,
  created_at timestamptz not null default now()
);

comment on table public.rate_limit_log is
  'V23 §1E: سجل العمليات المحدودة المعدل — يُنظف دوريًا.';

-- فهرس للبحث السريع: مستخدم + مجال + وقت
create index if not exists idx_rate_limit_log_lookup
  on public.rate_limit_log(user_id, domain, created_at desc);

-- تنظيف تلقائي: حذف السجلات الأقدم من 24 ساعة (يُشغل بـ cron)
-- يمكن ربطه بـ pg_cron لاحقًا: SELECT cron.schedule('rate-limit-cleanup', '0 * * * *', $$DELETE FROM public.rate_limit_log WHERE created_at < now() - interval '24 hours'$$);

alter table public.rate_limit_log enable row level security;

-- لا أحد يقرأ السجل مباشرة — الوصول عبر الدوال فقط
create policy rate_limit_log_deny_select on public.rate_limit_log
  for select to authenticated using (false);

create policy rate_limit_log_deny_insert on public.rate_limit_log
  for insert to authenticated with check (false);

-- ═══════════════════════════════════════════════════════════════════════
-- 2) الدالة العامة: check_rate_limit
-- ═══════════════════════════════════════════════════════════════════════
create or replace function public.check_rate_limit(
  p_domain text,
  p_max_count integer,
  p_window_minutes integer default 60
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count integer;
  v_uid uuid := auth.uid();
begin
  -- full-access معفى من Rate Limit
  if public.current_is_full_access() then
    return;
  end if;

  select count(*) into v_count
  from public.rate_limit_log
  where user_id = v_uid
    and domain = p_domain
    and created_at > now() - make_interval(mins => p_window_minutes);

  if v_count >= p_max_count then
    raise exception 'rate_limit_exceeded: % (% في آخر % دقيقة، الحد %)',
      p_domain, v_count, p_window_minutes, p_max_count
      using errcode = '54000';
  end if;

  -- سجل العملية
  insert into public.rate_limit_log(user_id, domain)
  values (v_uid, p_domain);
end;
$$;

comment on function public.check_rate_limit(text, integer, integer) is
  'V23 §1E: مساعد تحديد المعدل — يُطلق استثناء 54000 عند تجاوز الحد.';

revoke execute on function public.check_rate_limit(text, integer, integer) from public;
grant execute on function public.check_rate_limit(text, integer, integer) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- 3) دوال متخصصة لكل مجال (واجهة بسيطة)
-- ═══════════════════════════════════════════════════════════════════════

-- إنشاء موظف: 10/ساعة
create or replace function public.check_employee_create_rate_limit()
returns void language sql security definer set search_path = public, pg_temp
as $$ select public.check_rate_limit('employee_create', 10, 60); $$;

comment on function public.check_employee_create_rate_limit() is
  'V23: حد إنشاء الموظفين — 10 في الساعة.';

-- إسناد دور: 20/ساعة
create or replace function public.check_role_assign_rate_limit()
returns void language sql security definer set search_path = public, pg_temp
as $$ select public.check_rate_limit('role_assign', 20, 60); $$;

comment on function public.check_role_assign_rate_limit() is
  'V23: حد إسناد الأدوار — 20 في الساعة.';

-- تسجيل جهاز: 5/ساعة
create or replace function public.check_device_register_rate_limit()
returns void language sql security definer set search_path = public, pg_temp
as $$ select public.check_rate_limit('device_register', 5, 60); $$;

comment on function public.check_device_register_rate_limit() is
  'V23: حد تسجيل الأجهزة — 5 في الساعة.';

-- تسجيل حضور: 60/ساعة
create or replace function public.check_attendance_punch_rate_limit()
returns void language sql security definer set search_path = public, pg_temp
as $$ select public.check_rate_limit('attendance_punch', 60, 60); $$;

comment on function public.check_attendance_punch_rate_limit() is
  'V23: حد تسجيل الحضور — 60 في الساعة.';

-- طلب موقع: 10/ساعة
create or replace function public.check_location_request_rate_limit()
returns void language sql security definer set search_path = public, pg_temp
as $$ select public.check_rate_limit('location_request', 10, 60); $$;

comment on function public.check_location_request_rate_limit() is
  'V23: حد طلب الموقع — 10 في الساعة.';

-- نشر محتوى: 20/ساعة
create or replace function public.check_post_publish_rate_limit()
returns void language sql security definer set search_path = public, pg_temp
as $$ select public.check_rate_limit('post_publish', 20, 60); $$;

comment on function public.check_post_publish_rate_limit() is
  'V23: حد نشر المحتوى — 20 في الساعة.';

-- ═══════════════════════════════════════════════════════════════════════
-- 4) إلغاء الصلاحيات العامة على الدوال المتخصصة
-- ═══════════════════════════════════════════════════════════════════════
revoke execute on function public.check_employee_create_rate_limit() from public;
revoke execute on function public.check_role_assign_rate_limit() from public;
revoke execute on function public.check_device_register_rate_limit() from public;
revoke execute on function public.check_attendance_punch_rate_limit() from public;
revoke execute on function public.check_location_request_rate_limit() from public;
revoke execute on function public.check_post_publish_rate_limit() from public;

grant execute on function public.check_employee_create_rate_limit() to authenticated;
grant execute on function public.check_role_assign_rate_limit() to authenticated;
grant execute on function public.check_device_register_rate_limit() to authenticated;
grant execute on function public.check_attendance_punch_rate_limit() to authenticated;
grant execute on function public.check_location_request_rate_limit() to authenticated;
grant execute on function public.check_post_publish_rate_limit() to authenticated;
