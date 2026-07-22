-- =====================================================================
-- 0048: ضمان توفّر pgcrypto (digest) للدوال — إصلاح جذر مشكلة النشر المُدار
-- =====================================================================
-- المشكلة (ظهرت عند db push إلى Supabase المُدار):
--   migration 0027 يعرّف public.decision_content_hash التي تستدعي digest(...,'sha256')
--   من إضافة pgcrypto. على Supabase المُدار تُثبَّت pgcrypto في schema اسمه
--   "extensions" لا "public"، ودالة 0027 كانت بلا search_path صريح، فلا ترى digest
--   وتفشل بـ: function digest(text, unknown) does not exist (SQLSTATE 42883).
--
-- الإصلاح الدائم (immutable-safe، لا يعدّل 0001/0027 المطبّقين):
--   1) ضمان تثبيت pgcrypto (idempotent). في البيئة المحلية تُثبَّت في public؛
--      وعلى Supabase المُدار تكون في extensions أصلًا — كلا الحالتين تُغطّى بمسار
--      البحث الصريح أدناه.
--   2) إعادة تعريف decision_content_hash مع set search_path = public, extensions
--      حتى تُحلّ digest أينما وُجدت، في أي بيئة (محلي / staging / production جديدة).
-- =====================================================================

create extension if not exists pgcrypto;

create or replace function public.decision_content_hash(p_title text, p_body text, p_version integer)
returns text
language sql
immutable
set search_path = public, extensions
as $$
  select encode(
    digest(coalesce(p_title, '') || E'\n' || coalesce(p_body, '') || E'\n' || p_version::text, 'sha256'),
    'hex'
  )
$$;

comment on function public.decision_content_hash(text, text, integer) is
  'تجزئة محتوى القرار (sha256). search_path يشمل extensions ليُحلّ digest على Supabase المُدار.';
