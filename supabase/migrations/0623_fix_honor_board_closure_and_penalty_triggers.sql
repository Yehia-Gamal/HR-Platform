-- 0623: إحكام ما تبقّى من تعديلات 0614–0619 + عطل كامن في data_quality_rules
-- ===========================================================================
-- 1) لوحة الشرف: 0619 أرادت «إغلاقًا مؤقتًا للتحديث بطلب الإدارة» لكنها أنشأت
--    دالة جديدة get_honor_board(p_month) لا يستدعيها التطبيق (يستدعي
--    get_honor_board(p_period, p_category))، فبقيت اللوحة تعمل، وصار الاستدعاء بلا
--    معاملات مبهمًا (42725)، ومنحت الدالة الجديدة لـ anon و PUBLIC.
--    ← حذف الدالة الزائدة وتنفيذ الإغلاق على الدالة التي يستدعيها التطبيق.
--    لإعادة الفتح: أعد تطبيق تعريف get_honor_board من 0618 كما هو.
-- 2) tg_prevent_admin_penalty_fn (0616) مربوطة بجدولي الغرامات، وتكتب
--    NEW.cancelled_reason غير الموجود في employee_penalties (السبب فيه waive_reason)
--    → أي تعديل لغرامة عادية لموظف معفى يفشل بخطأ تقني. ← دالة مستقلة للجدول
--    العادي. وأُزيل رقم الموظف من رسالة السجل (لا معرّفات في السجلات)، وسُحب
--    التنفيذ من anon و PUBLIC.
-- 3) data_quality_rules عليها تريجر tg_set_updated_at بلا عمود updated_at →
--    أي تعديل عليها يفشل (42703). ← إضافة العمود.
-- ===========================================================================

begin;

-- 1) لوحة الشرف
drop function if exists public.get_honor_board(text);

create or replace function public.get_honor_board(
  p_period text default 'month'::text,
  p_category text default 'attendance'::text
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  if auth.uid() is null then
    raise exception 'يلزم تسجيل الدخول أولاً' using errcode = '42501';
  end if;

  -- مغلقة مؤقتًا للتحديث بطلب الإدارة (0619). لإعادة الفتح: تعريف 0618.
  return '[]'::jsonb;
end;
$function$;

revoke execute on function public.get_honor_board(text, text) from public, anon;
grant execute on function public.get_honor_board(text, text) to authenticated, service_role;

-- 2) منع غرامات المعفيين — جدول الغرامات الفورية (cancelled_reason)
create or replace function public.tg_prevent_admin_penalty_fn()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  -- فحص: هل الموظف معفى دائماً من الغرامات؟
  if public.is_employee_penalty_exempt(NEW.employee_id)
     or public.is_employee_attendance_exempt(NEW.employee_id) then

    if TG_OP = 'INSERT' then
      -- منع إدراج أي غرامة جديدة للموظف المعفى تماماً
      raise notice 'tg_prevent_admin_penalty: blocked INSERT for an exempt employee';
      return null;
    elsif TG_OP = 'UPDATE' then
      -- السماح بتحديث الحالة إلى ملغاة فقط
      if NEW.status <> 'cancelled' then
        NEW.status := 'cancelled';
        NEW.cancelled_reason := coalesce(
          nullif(trim(coalesce(NEW.cancelled_reason, '')), ''),
          'إلغاء تلقائي: الموظف معفى من الغرامات بقرار إداري دائم'
        );
      end if;
      return NEW;
    end if;
  end if;
  return NEW;
end;
$function$;

revoke all on function public.tg_prevent_admin_penalty_fn() from public, anon;

-- 2ب) منع غرامات المعفيين — جدول الغرامات العادية (waive_reason)
create or replace function public.tg_prevent_admin_regular_penalty_fn()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  if public.is_employee_penalty_exempt(NEW.employee_id)
     or public.is_employee_attendance_exempt(NEW.employee_id) then

    if TG_OP = 'INSERT' then
      raise notice 'tg_prevent_admin_regular_penalty: blocked INSERT for an exempt employee';
      return null;
    elsif TG_OP = 'UPDATE' then
      if NEW.status <> 'cancelled' then
        NEW.status := 'cancelled';
        NEW.waive_reason := coalesce(
          nullif(trim(coalesce(NEW.waive_reason, '')), ''),
          'إلغاء تلقائي: الموظف معفى من الغرامات بقرار إداري دائم'
        );
      end if;
      return NEW;
    end if;
  end if;
  return NEW;
end;
$function$;

revoke all on function public.tg_prevent_admin_regular_penalty_fn() from public, anon;

drop trigger if exists tg_prevent_admin_penalty_regular on public.employee_penalties;
create trigger tg_prevent_admin_penalty_regular
  before insert or update on public.employee_penalties
  for each row execute function public.tg_prevent_admin_regular_penalty_fn();

-- 3) data_quality_rules: العمود الذي يكتبه تريجر updated_at
alter table public.data_quality_rules
  add column if not exists updated_at timestamptz not null default now();

commit;
