-- 0356: حذف إدارة V25 الاختبارية
-- ===========================================================================
-- ظهر قسم باسم "إدارة V25" (code=V25-D) إثر جلسة V25 الاختبارية وهو ليس إدارة
-- فعلية. كان غير نشط (is_active=false) ومربوطًا بموظفي اختبار فقط
-- (مدير الاختبار / موظف الاختبار). يُعاد ترتيب الموظفين إلى "إدارة الموارد
-- البشرية" قبل الحذف احترامًا لقيد on delete restrict على employees.department_id.
-- ثم يُحذف القسم نهائيًا.
-- تم تنفيذ نفس التغيير على قاعدة الإنتاج المرتبطة (linked) عبر db query.

UPDATE public.employees
   SET department_id = (SELECT id FROM public.departments WHERE code = 'HR'),
       updated_at = now()
 WHERE department_id = 'a8600000-0000-4000-8000-000000000010';

DELETE FROM public.departments
 WHERE id = 'a8600000-0000-4000-8000-000000000010';
