-- ============================================================================
-- Migration 0180: بذر أنواع التوظيف الأساسية
--   جدول employment_types كان فارغاً — القائمة المنسدلة تظهر فارغة في واجهة التعديل.
--   يُضاف ON CONFLICT لتجنب الخطأ عند إعادة التشغيل.
-- ============================================================================

insert into public.employment_types (id, code, name, name_en, is_full_time, is_active)
values
  (gen_random_uuid(), 'full_time',  'دوام كامل', 'Full-time',  true,  true),
  (gen_random_uuid(), 'part_time',  'دوام جزئي', 'Part-time',  false, true),
  (gen_random_uuid(), 'contract',   'عقد مؤقت',  'Contract',   false, true),
  (gen_random_uuid(), 'volunteer',  'تطوعي',     'Volunteer',  false, true),
  (gen_random_uuid(), 'internship', 'تدريب',     'Internship', false, true)
on conflict (code) do nothing;

notify pgrst, 'reload schema';
