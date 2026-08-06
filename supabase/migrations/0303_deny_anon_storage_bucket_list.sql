-- 0303: منع anon من سرد buckets التخزين
-- المشكلة: storage.buckets قابلة للقراءة من anon (HIGH finding من security assessment)
-- الحل: سياسة SELECT تمنع anon من سرد buckets
-- تأثير جانبي: لا شيء — التطبيقات تستخدم service_role للإدارة

BEGIN;

-- إزالة السياسات القديمة على storage.buckets إن وُجدت
drop policy if exists "Allow anon to read buckets" on storage.buckets;
drop policy if exists "bucket_select_anon" on storage.buckets;

-- anon لا يرى أي bucket
create policy "buckets_anon_denied" on storage.buckets
  for select to anon
  using (false);

-- authenticated يرى buckets العامة فقط (public = true)
create policy "buckets_authenticated_public_only" on storage.buckets
  for select to authenticated
  using (public = true);

COMMIT;

NOTIFY pgrst, 'reload schema';
