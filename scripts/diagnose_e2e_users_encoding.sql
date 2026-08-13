-- ═════════════════════════════════════════════════════════════════════════
-- تشخيص: أسماء عربية فاسدة (????) لمستخدمي E2E/الهاتف في صفحة الإسنادات
-- ═════════════════════════════════════════════════════════════════════════
-- الهدف: تحديد طبيعة الفساد ومصدره. كلها SELECT للقراءة فقط — لا تعديل.
--
-- كيفية التشغيل:
--   لوحة تحكم Supabase → SQL Editor → الصق هذا الملف → Run
--
-- اقرأ النتائج بالترتيب:
--   1) فلتر الترميز: هل القيمة المخزّنة `3f` (?) حرفياً أم بايتات عربية d8..؟
--   2) auth.users: هل الفساد موجود في البيانات الوصفية أيضاً؟
--   3) الإنشاء: متى ومن أنشأ هذين الموظفين؟
--   4) الأدوار: تأكيد "بلا دور فعال".
--   5) مقارنة: موظف عربي سليم لإثبات أن العمود يقبل العربية.
-- ═════════════════════════════════════════════════════════════════════════

-- 1) ── الموظفان المشبوهان: القيمة النصية + الطول + البايتات الخام ───────
select
  e.id                                         as employee_id,
  e.user_id,
  e.employee_code,
  e.phone_e164,
  e.full_name_ar                               as name_as_stored,
  char_length(e.full_name_ar)                  as name_char_len,
  octet_length(e.full_name_ar)                 as name_byte_len,
  encode(e.full_name_ar::bytea, 'hex')         as name_hex,        -- 3f3f = '??' / d8a3 = 'أ'
  e.status,
  e.is_active,
  e.is_deleted,
  e.created_by,
  e.created_at
from public.employees e
where e.phone_e164 in ('+201522553042', '+201083619233')
   or e.employee_code in ('+201522553042', '+201083619233')
order by e.created_at;

-- 2) ── auth.users المقابل: هل الفساد في البيانات الوصفية أيضاً؟ ──────────
--    إن كان معطوباً هنا أيضاً → الفساد حدث قبل وصوله Postgres (سكربت/HTTP).
--    إن كان سليماً هنا ومعطوباً في employees → المشكلة في مسار الإدراج.
select
  u.id,
  u.phone,
  u.email,
  u.created_at,
  u.raw_user_meta_data,
  u.raw_user_meta_data->>'full_name'      as meta_full_name,
  u.raw_user_meta_data->>'full_name_ar'   as meta_full_name_ar,
  u.raw_user_meta_data->>'employee_code'  as meta_employee_code,
  u.raw_app_meta_data
from auth.users u
where u.phone in ('+201522553042', '+201083619233')
order by u.created_at;

-- 3) ── مَن أنشأ هذين السجلَّين (created_by → من الممارس الفعلي)؟ ─────────
select
  e.id,
  e.employee_code,
  e.phone_e164,
  e.created_by,
  cu.email     as created_by_email,
  cu.phone     as created_by_phone,
  e.created_at
from public.employees e
left join auth.users cu on cu.id = e.created_by
where e.phone_e164 in ('+201522553042', '+201083619233')
   or e.employee_code in ('+201522553042', '+201083619233');

-- 4) ── أدوار هذين المستخدمين (تأكيد "بلا دور فعال") ───────────────────
select
  p.id            as user_id,
  p.status        as profile_status,
  r.slug          as role_slug,
  r.name_ar       as role_name,
  ur.effective_from,
  ur.effective_to,
  ur.granted_by,
  case
    when ur.role_id is null then 'بلا دور (لا صفوف في user_roles)'
    when ur.effective_from > now() then 'دور مستقبلي (لم يبدأ بعد)'
    when ur.effective_to is not null and ur.effective_to <= now() then 'دور منتهٍ'
    else 'دور فعال'
  end             as role_state
from public.profiles p
left join public.user_roles ur
       on ur.user_id = p.id
      and ur.effective_from <= now()
      and (ur.effective_to is null or ur.effective_to > now())
left join public.roles r on r.id = ur.role_id
where p.id in (
  select e.user_id from public.employees e
  where e.phone_e164 in ('+201522553042', '+201083619233')
     or e.employee_code in ('+201522553042', '+201083619233')
)
order by p.id;

-- 5) ── مقارنة: موظفون عرب آخرون لإثبات أن العمود يقبل UTF-8 ──────────────
-- ملاحظة: Postgres regex لا يدعم \x{NNNN}؛ نكتشف العربية بمقارنة
-- octet_length (بايتات) مع char_length (أحرف) — العربية UTF-8 متعدد البايت
-- (octet > char يعني وجود أحرف غير ASCII)، مع استبعاد أي اسم يحوي '?'.
select
  e.employee_code,
  e.full_name_ar,
  char_length(e.full_name_ar)   as char_len,
  octet_length(e.full_name_ar)  as byte_len,
  encode(e.full_name_ar::bytea, 'hex') as name_hex
from public.employees e
where octet_length(e.full_name_ar) > char_length(e.full_name_ar)  -- متعدد البايت (عربية)
  and position('?' in e.full_name_ar) = 0                          -- ليس معطوباً
order by e.created_at desc
limit 5;

-- 6) ── إعدادات الترميز للجلسة وقاعدة البيانات والعمود ─────────────────
select current_database()                              as db_name,
       pg_encoding_to_char(encoding)                   as db_encoding,   -- يُتوقع UTF8
       pg_catalog.pg_encoding_to_char(d.encoding)      as server_encoding,
       (select setting from pg_settings where name = 'client_encoding') as client_encoding,
       (select setting from pg_settings where name = 'server_encoding') as server_setting;

-- 7) ── نوع العمود وترتيبه (تأكيد أنه text بترتيب يدعم العربية) ─────────
select column_name, data_type, character_maximum_length,
       collation_name, is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name   = 'employees'
  and column_name in ('full_name_ar', 'employee_code', 'phone_e164');
