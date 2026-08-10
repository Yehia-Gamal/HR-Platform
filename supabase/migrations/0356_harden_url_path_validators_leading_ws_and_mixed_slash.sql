-- 0248_harden_url_path_validators_leading_ws_and_mixed_slash.sql
-- ═══════════════════════════════════════════════════════════════════════
-- إصلاح ثغرتين في دوال التحقق من الروابط/المسارات (0235 + 0243):
--
--   (أ) تجاوز الفراغ البادئ لبند اكتشاف المخطط:
--       البند الرابع كان يفحص القيمة الخام (p_value ~ '^[a-zA-Z]...:') بينما
--       تستخدم بقية البنود ltrim. مسافة بادئة واحدة تُبطل ^[a-zA-Z] فيُتخطّى
--       البند بالكامل، فيمرّ أي مخطط غير مدرَج في القائمة السوداء
--       (chrome: intent: jar: ms-*: ...). المتصفح يزيل الفراغ عند العرض
--       فيصبح المخطط حيّاً في src/href.
--
--   (ب) تجاوز الخلط بين / و \ لبند الروابط بلا-مخطط:
--       البند الخامس '^(//|\\)' يمسك // أو \ فقط، ويفوته الخلط:
--       /\evil.com و \/evil.com — يطبّعها المتصفح إلى //evil.com (رابط
--       بلا-مخطط لمضيف المهاجم) → إعادة توجيه مفتوح / حقن مورد خارجي.
--
-- الإصلاح: تطبيع القيمة بـ ltrim مرة واحدة عبر CTE بحيث تعمل كل البنود على
-- القيمة المُنظَّفة، وتوسيع بند الروابط بلا-مخطط إلى '^([/\\]){2}' ليمسك
-- // و \\ و /\ و \/ معاً. لا مساس بـ 0235/0243 (منشورتان) — إعادة تعريف فقط.
--
-- ليست ثغرة XSS: القائمة السوداء (data|javascript|vbscript...) تصمد حتى مع
-- مسافة بادئة (تستخدم ltrim). هذه ثغرات إعادة-توجيه/حقن-مورد فقط.
-- ═══════════════════════════════════════════════════════════════════════

begin;

-- ─── 1) رابط آمن: https مطلق أو مسار تخزين نسبي (photo_url, banner_url) ───
create or replace function public.is_safe_url_or_path(p_value text)
returns boolean
language sql
immutable
parallel safe
as $$
  with n as (select ltrim($1) as v)
  select case
    -- الفارغ/NULL يُسمح به (العمود اختياري)
    when $1 is null or length(trim($1)) = 0 then true
    -- رفض محارف التحكّم و newline/CR/tab (على القيمة الخام)
    when $1 ~ '[[:cntrl:]]' then false
    -- رفض المخططات الخطِرة صراحةً (على القيمة المُنظَّفة)
    when lower((select v from n)) ~ '^(data|file|javascript|blob|vbscript|about|filesystem):' then false
    -- رفض أي مخطط غير https (على القيمة المُنظَّفة — يشمل حالة الفراغ البادئ)
    when (select v from n) ~ '^[a-zA-Z][a-zA-Z0-9+.-]*:' and lower((select v from n)) !~ '^https://' then false
    -- رفض الروابط بلا-مخطط: أي محرفَي / أو \ بادئين (يمسك // \\ /\ \/)
    when (select v from n) ~ '^[/\\]{2}' then false
    -- منع اجتياز المسار في المسارات النسبية
    when (select v from n) ~ '(^|/)\.\.(/|$)' then false
    else true
  end;
$$;

comment on function public.is_safe_url_or_path(text) is
  'يتحقق أن القيمة إمّا رابط https مطلق أو مسار تخزين نسبي آمن. يرفض data:/file:/javascript:/blob:/vbscript:/about:/filesystem: وأي مخطط غير https ومحارف التحكّم واجتياز المسار (..) والروابط بلا-مخطط (// \\ /\ \/). يُطبِّع القيمة بـ ltrim أولاً فلا تتجاوزه مسافة بادئة. فارغ/NULL مسموح. (0248)';

-- ─── 2) مسار تخزين صِرف: بلا مخطط، بلا / بادئة، بلا اجتياز (selfie_path) ───
create or replace function public.is_safe_storage_path(p_value text)
returns boolean
language sql
immutable
parallel safe
as $$
  with n as (select ltrim($1) as v)
  select case
    when $1 is null or length(trim($1)) = 0 then true
    when $1 ~ '[[:cntrl:]]' then false
    -- أي مخطط (scheme:) مرفوض — على القيمة المُنظَّفة (يشمل الفراغ البادئ)
    when (select v from n) ~ '^[a-zA-Z][a-zA-Z0-9+.-]*:' then false
    -- رفض المسار المطلق والروابط بلا-مخطط (/ أو \ أو خلطهما في البداية)
    when (select v from n) ~ '^[/\\]' then false
    when (select v from n) ~ '(^|/)\.\.(/|$)' then false
    else true
  end;
$$;

comment on function public.is_safe_storage_path(text) is
  'يتحقق أن القيمة مسار كائن تخزين نسبي بحت (بلا أي scheme، بلا / أو \ بادئة، بلا اجتياز ..). يُطبِّع بـ ltrim أولاً. فارغ/NULL مسموح. (0248)';

-- ─── 3) رابط مرجعي خارجي: كـ is_safe_url_or_path لكن يسمح http أيضاً ───
-- (external_url في kpi_evidence — يُعرض كـ <a href> لروابط الأدلة المرجعية)
create or replace function public.is_safe_external_link(p_value text)
returns boolean
language sql
immutable
parallel safe
as $$
  with n as (select ltrim($1) as v)
  select case
    when $1 is null or length(trim($1)) = 0 then true
    when $1 ~ '[[:cntrl:]]' then false
    when lower((select v from n)) ~ '^(data|file|javascript|blob|vbscript|about|filesystem):' then false
    -- رفض أي مخطط عدا http/https (على القيمة المُنظَّفة)
    when (select v from n) ~ '^[a-zA-Z][a-zA-Z0-9+.-]*:' and lower((select v from n)) !~ '^https?://' then false
    -- رفض الروابط بلا-مخطط (// \\ /\ \/)
    when (select v from n) ~ '^[/\\]{2}' then false
    when (select v from n) ~ '(^|/)\.\.(/|$)' then false
    else true
  end;
$$;

comment on function public.is_safe_external_link(text) is
  'يتحقق أن القيمة رابط http/https مطلق أو مسار نسبي آمن. يرفض data:/file:/javascript:/blob:/vbscript:/about:/filesystem: وأي مخطط آخر ومحارف التحكّم واجتياز المسار والروابط بلا-مخطط (// \\ /\ \/). يُطبِّع بـ ltrim أولاً. أوسع من is_safe_url_or_path (يسمح http) لروابط الأدلة. فارغ/NULL مسموح. (0248)';

-- ─── 4) صلاحيات (إعادة تأكيد؛ CREATE OR REPLACE يحافظ عليها لكن للتوضيح) ───
revoke all on function public.is_safe_url_or_path(text) from public;
revoke all on function public.is_safe_storage_path(text) from public;
revoke all on function public.is_safe_external_link(text) from public;
grant execute on function public.is_safe_url_or_path(text) to authenticated, service_role;
grant execute on function public.is_safe_storage_path(text) to authenticated, service_role;
grant execute on function public.is_safe_external_link(text) to authenticated, service_role;

commit;
