-- 0058: V17 §1.3 — قيود طول النص (Word Count Checks) على migration 0135.
-- يختبر: وجود القيود (11 قيد)، والتطبيق الفعلي عبر INSERT على announcements و kpi_criteria.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(18);

-- =====================================================================
-- بيانات أولية بسيطة لاختبار الإدراج الوظيفي على announcements
-- =====================================================================
-- لا يحتاج announcements إلى FK على created_by (nullable)، نمرر null لتجنب تعقيد auth.users.

-- =====================================================================
-- 1. requests — chk_requests_title_length
-- =====================================================================

select ok(
  exists(
    select 1 from pg_constraint c
    join pg_class r on c.conrelid = r.oid
    where r.relname = 'requests'
      and c.conname  = 'chk_requests_title_length'
      and c.contype  = 'c'
  ),
  'قيد chk_requests_title_length موجود على جدول requests'
);

-- =====================================================================
-- 2. requests — chk_requests_reason_length
-- =====================================================================

select ok(
  exists(
    select 1 from pg_constraint c
    join pg_class r on c.conrelid = r.oid
    where r.relname = 'requests'
      and c.conname  = 'chk_requests_reason_length'
      and c.contype  = 'c'
  ),
  'قيد chk_requests_reason_length موجود على جدول requests'
);

-- =====================================================================
-- 3. announcements — chk_announcements_title_length
-- =====================================================================

select ok(
  exists(
    select 1 from pg_constraint c
    join pg_class r on c.conrelid = r.oid
    where r.relname = 'announcements'
      and c.conname  = 'chk_announcements_title_length'
      and c.contype  = 'c'
  ),
  'قيد chk_announcements_title_length موجود على جدول announcements'
);

-- =====================================================================
-- 4. announcements — chk_announcements_body_length
-- =====================================================================

select ok(
  exists(
    select 1 from pg_constraint c
    join pg_class r on c.conrelid = r.oid
    where r.relname = 'announcements'
      and c.conname  = 'chk_announcements_body_length'
      and c.contype  = 'c'
  ),
  'قيد chk_announcements_body_length موجود على جدول announcements'
);

-- =====================================================================
-- 5. dispute_cases — chk_dispute_cases_description_length
-- =====================================================================

select ok(
  exists(
    select 1 from pg_constraint c
    join pg_class r on c.conrelid = r.oid
    where r.relname = 'dispute_cases'
      and c.conname  = 'chk_dispute_cases_description_length'
      and c.contype  = 'c'
  ),
  'قيد chk_dispute_cases_description_length موجود على جدول dispute_cases'
);

-- =====================================================================
-- 6. kpi_criteria — chk_kpi_criteria_name_ar_length
-- =====================================================================

select ok(
  exists(
    select 1 from pg_constraint c
    join pg_class r on c.conrelid = r.oid
    where r.relname = 'kpi_criteria'
      and c.conname  = 'chk_kpi_criteria_name_ar_length'
      and c.contype  = 'c'
  ),
  'قيد chk_kpi_criteria_name_ar_length موجود على جدول kpi_criteria'
);

-- =====================================================================
-- 7. kpi_evaluations — chk_kpi_evaluations_manager_comment_length
-- =====================================================================

select ok(
  exists(
    select 1 from pg_constraint c
    join pg_class r on c.conrelid = r.oid
    where r.relname = 'kpi_evaluations'
      and c.conname  = 'chk_kpi_evaluations_manager_comment_length'
      and c.contype  = 'c'
  ),
  'قيد chk_kpi_evaluations_manager_comment_length موجود على جدول kpi_evaluations'
);

-- =====================================================================
-- 8. kpi_evaluations — chk_kpi_evaluations_employee_comment_length
-- =====================================================================

select ok(
  exists(
    select 1 from pg_constraint c
    join pg_class r on c.conrelid = r.oid
    where r.relname = 'kpi_evaluations'
      and c.conname  = 'chk_kpi_evaluations_employee_comment_length'
      and c.contype  = 'c'
  ),
  'قيد chk_kpi_evaluations_employee_comment_length موجود على جدول kpi_evaluations'
);

-- =====================================================================
-- 9. kpi_evaluations — chk_kpi_evaluations_hr_comment_length
-- =====================================================================

select ok(
  exists(
    select 1 from pg_constraint c
    join pg_class r on c.conrelid = r.oid
    where r.relname = 'kpi_evaluations'
      and c.conname  = 'chk_kpi_evaluations_hr_comment_length'
      and c.contype  = 'c'
  ),
  'قيد chk_kpi_evaluations_hr_comment_length موجود على جدول kpi_evaluations'
);

-- =====================================================================
-- 10. kpi_evaluations — chk_kpi_evaluations_secretary_comment_length
-- =====================================================================

select ok(
  exists(
    select 1 from pg_constraint c
    join pg_class r on c.conrelid = r.oid
    where r.relname = 'kpi_evaluations'
      and c.conname  = 'chk_kpi_evaluations_secretary_comment_length'
      and c.contype  = 'c'
  ),
  'قيد chk_kpi_evaluations_secretary_comment_length موجود على جدول kpi_evaluations'
);

-- =====================================================================
-- 11. kpi_evaluations — chk_kpi_evaluations_executive_comment_length
-- =====================================================================

select ok(
  exists(
    select 1 from pg_constraint c
    join pg_class r on c.conrelid = r.oid
    where r.relname = 'kpi_evaluations'
      and c.conname  = 'chk_kpi_evaluations_executive_comment_length'
      and c.contype  = 'c'
  ),
  'قيد chk_kpi_evaluations_executive_comment_length موجود على جدول kpi_evaluations'
);

-- =====================================================================
-- اختبارات وظيفية: announcements (عنوان وجسم)
-- announcements.title و body إلزاميان — نختبر الرفض مباشرة بدون FK معقد.
-- =====================================================================

-- 12. عنوان أقصر من 3 محارف يُرفض
select throws_ok(
  $$insert into public.announcements(title, body, status, created_by)
    values('أب', 'نص كافٍ للاختبار يغطي الحد الأدنى', 'draft', null)$$,
  '23514', null,
  'announcements: عنوان من حرفين يُرفض بقيد chk_announcements_title_length'
);

-- 13. عنوان أطول من 300 محرف يُرفض
select throws_ok(
  $$insert into public.announcements(title, body, status, created_by)
    values(repeat('أ', 301), 'نص كافٍ للاختبار يغطي الحد الأدنى', 'draft', null)$$,
  '23514', null,
  'announcements: عنوان من 301 حرف يُرفض بقيد chk_announcements_title_length'
);

-- 14. جسم أقصر من 3 محارف يُرفض
select throws_ok(
  $$insert into public.announcements(title, body, status, created_by)
    values('عنوان صحيح كافٍ', 'نص', 'draft', null)$$,
  '23514', null,
  'announcements: جسم من حرفين يُرفض بقيد chk_announcements_body_length'
);

-- 15. جسم أطول من 5000 محرف يُرفض
select throws_ok(
  $$insert into public.announcements(title, body, status, created_by)
    values('عنوان صحيح كافٍ', repeat('أ', 5001), 'draft', null)$$,
  '23514', null,
  'announcements: جسم من 5001 حرف يُرفض بقيد chk_announcements_body_length'
);

-- =====================================================================
-- اختبارات وظيفية: kpi_criteria
-- يحتاج template_id → kpi_templates. ننشئ قالب مؤقت داخل الاختبار.
-- =====================================================================

-- قالب مؤقت لاختبار kpi_criteria فقط
insert into public.kpi_templates(id, name_ar)
  values('a5800000-0000-4000-8000-000000000f01', 'قالب اختبار مؤقت للقيود');

-- 16. name_ar أقصر من 3 محارف يُرفض
select throws_ok(
  $$insert into public.kpi_criteria(template_id, name_ar, weight, max_score)
    values('a5800000-0000-4000-8000-000000000f01', 'أب', 10, 100)$$,
  '23514', null,
  'kpi_criteria: name_ar من حرفين يُرفض بقيد chk_kpi_criteria_name_ar_length'
);

-- 17. name_ar أطول من 300 محرف يُرفض
select throws_ok(
  $$insert into public.kpi_criteria(template_id, name_ar, weight, max_score)
    values('a5800000-0000-4000-8000-000000000f01', repeat('أ', 301), 10, 100)$$,
  '23514', null,
  'kpi_criteria: name_ar من 301 حرف يُرفض بقيد chk_kpi_criteria_name_ar_length'
);

-- =====================================================================
-- 18. جميع قيود chk_*_length هي NOT VALID (تطبق على الكتابة الجديدة فقط)
-- =====================================================================

select ok(
  (
    select count(*) filter (where not c.convalidated) = count(*)
    from pg_constraint c
    join pg_class r on c.conrelid = r.oid
    where c.conname like 'chk_%_length'
      and c.contype = 'c'
      and r.relnamespace = (select oid from pg_namespace where nspname = 'public')
  ),
  'جميع قيود chk_*_length هي NOT VALID — لا تُفحص البيانات السابقة'
);

select * from finish();
rollback;
