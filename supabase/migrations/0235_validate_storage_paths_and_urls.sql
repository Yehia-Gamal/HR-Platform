-- 0235_validate_storage_paths_and_urls.sql
-- ═══════════════════════════════════════════════════════════════════════
-- تحقق خادمي من مسارات/روابط الملفات المخزّنة في أعمدة قاعدة البيانات.
--
-- الخلفية الأمنية: عدة مسارات إدخال تخزّن روابط/مسارات ملفات يتحكم بها
-- العميل دون أي تحقق خادمي — أبرزها:
--   • employees.photo_url        (RLS مباشر من الموبايل + provision/update RPCs)
--   • attendance_events.selfie_path (p_selfie_path عبر verify-attendance-punch)
-- لم يكن هناك أي رفض لـ  data:  file:  javascript:  blob:  vbscript:  أو
-- لمسارات الاجتياز (../) — ما يفتح باب Stored-XSS / SSRF عند العرض.
--
-- الحل: دالتا تحقق IMMUTABLE + محفّزات BEFORE INSERT/UPDATE على الجدولين،
-- بحيث يُغطّى كل مسار كتابة (RPCs + تحديث RLS المباشر + أي RPC مستقبلي).
--
-- سياسة الصرامة (مختارة): قائمة حظر مخططات (scheme blocklist):
--   • photo_url:  إمّا https://  أو مسار تخزين نسبي.
--   • selfie_path: مسار تخزين نسبي فقط (بلا مخطط، بلا ../، بلا / بادئة).
--   • يُرفض دائماً:  data:  file:  javascript:  blob:  vbscript:  + محارف تحكّم.
-- ═══════════════════════════════════════════════════════════════════════

begin;

-- ─── 1) رابط آمن: https مطلق أو مسار تخزين نسبي ───
-- يُستخدم لأعمدة قد تحمل رابطاً عاماً كاملاً (photo_url, banner_url, ...).
create or replace function public.is_safe_url_or_path(p_value text)
returns boolean
language sql
immutable
parallel safe
as $$
  select case
    -- الفارغ/NULL يُسمح به (العمود اختياري؛ nullif يحوّله لـ NULL لاحقاً)
    when p_value is null or length(trim(p_value)) = 0 then true
    -- رفض محارف التحكّم و newline/CR/tab (تُستخدم لتجاوز الفلاتر)
    when p_value ~ '[[:cntrl:]]' then false
    -- رفض المخططات الخطِرة صراحةً (غير حسّاس لحالة الأحرف، مع تجاهل مسافات بادئة)
    when lower(ltrim(p_value)) ~ '^(data|file|javascript|blob|vbscript|about|filesystem):' then false
    -- رفض أي مخطط غير https (نسمح فقط بـ https المطلق)
    when p_value ~ '^[a-zA-Z][a-zA-Z0-9+.-]*:' and lower(ltrim(p_value)) !~ '^https://' then false
    -- منع اجتياز المسار في المسارات النسبية
    when p_value ~ '(^|/)\.\.(/|$)' then false
    else true
  end;
$$;

comment on function public.is_safe_url_or_path(text) is
  'يتحقق أن القيمة إمّا رابط https مطلق أو مسار تخزين نسبي آمن. يرفض data:/file:/javascript:/blob:/vbscript: ومحارف التحكّم واجتياز المسار (..). فارغ/NULL مسموح.';

-- ─── 2) مسار تخزين صِرف: بلا مخطط إطلاقاً، بلا ../، بلا / بادئة ───
-- يُستخدم لأعمدة تحمل مسار كائن داخل الحاوية فقط (selfie_path).
create or replace function public.is_safe_storage_path(p_value text)
returns boolean
language sql
immutable
parallel safe
as $$
  select case
    when p_value is null or length(trim(p_value)) = 0 then true
    when p_value ~ '[[:cntrl:]]' then false
    -- أي مخطط (scheme:) مرفوض — يجب أن يكون مساراً نسبياً بحتاً
    when p_value ~ '^[a-zA-Z][a-zA-Z0-9+.-]*:' then false
    -- بلا مسار مطلق ولا اجتياز
    when p_value ~ '^/' then false
    when p_value ~ '(^|/)\.\.(/|$)' then false
    else true
  end;
$$;

comment on function public.is_safe_storage_path(text) is
  'يتحقق أن القيمة مسار كائن تخزين نسبي بحت (بلا أي scheme، بلا / بادئة، بلا اجتياز ..). فارغ/NULL مسموح.';

-- ─── 3) محفّز employees.photo_url ───
create or replace function public.tg_employees_validate_photo_url()
returns trigger
language plpgsql
as $$
begin
  if new.photo_url is not null
     and not public.is_safe_url_or_path(new.photo_url) then
    raise exception 'invalid_photo_url'
      using errcode = '22023',
            detail  = 'photo_url must be an https URL or a relative storage path; data:/file:/javascript: schemes and path traversal are rejected.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_employees_validate_photo_url on public.employees;
create trigger trg_employees_validate_photo_url
  before insert or update of photo_url on public.employees
  for each row execute function public.tg_employees_validate_photo_url();

-- ─── 4) محفّز attendance_events.selfie_path ───
create or replace function public.tg_attendance_validate_selfie_path()
returns trigger
language plpgsql
as $$
begin
  if new.selfie_path is not null
     and not public.is_safe_storage_path(new.selfie_path) then
    raise exception 'invalid_selfie_path'
      using errcode = '22023',
            detail  = 'selfie_path must be a relative storage object path; any URL scheme, absolute path, or path traversal is rejected.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_attendance_validate_selfie_path on public.attendance_events;
create trigger trg_attendance_validate_selfie_path
  before insert or update of selfie_path on public.attendance_events
  for each row execute function public.tg_attendance_validate_selfie_path();

-- ─── 5) صلاحيات دوال التحقق (قراءة فقط، آمنة للجميع) ───
revoke all on function public.is_safe_url_or_path(text) from public;
revoke all on function public.is_safe_storage_path(text) from public;
grant execute on function public.is_safe_url_or_path(text) to authenticated, service_role;
grant execute on function public.is_safe_storage_path(text) to authenticated, service_role;

commit;
