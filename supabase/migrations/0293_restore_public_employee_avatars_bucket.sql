-- إصلاح صور الموظفين: إعادة bucket employee-avatars إلى القراءة العامة
--
-- السبب الجذري: migration 0211 جعل bucket employee-avatars خاصاً (public = false)
-- بينما كل الطبقات تعتمد على روابط عامة عبر getPublicUrl:
--   - photo_url مخزّنة في الجداول كروابط عامة (object/public/...)
--   - Web (UserAvatar, EmployeeDetail, LiveLocation...) و Flutter (AppAvatar)
--   - جميع RPCs تعيد photo_url كما هي
-- النتيجة: كل الصور كسرت (400) وتظهر الأحرف الأولى بدلاً منها.
--
-- الحل: إعادة public = true + سياسة قراءة عامة — استعادة التصميم الأصلي
-- من 0056 (علّق: "عام للقراءة، والكتابة/الحذف لمن يملك صلاحية إدارة الموظفين").
-- سياسات الكتابة (_manage_) و RLS على الجداول تبقى سليمة دون تغيير.

BEGIN;

update storage.buckets
   set public = true
 where id = 'employee-avatars'
   and public = false;

drop policy if exists employee_avatars_public_read on storage.objects;
create policy employee_avatars_public_read on storage.objects
  for select using (bucket_id = 'employee-avatars');

COMMIT;
