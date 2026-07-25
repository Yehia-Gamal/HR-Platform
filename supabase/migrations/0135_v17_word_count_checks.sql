-- Migration 0135: V17 §1.3 — قيود طول النص (Word Count Checks)
-- يُضيف قيود CHECK على حقول النص في الجداول الرئيسية لضمان نطاقات
-- الطول المحدّدة في المواصفات: 3–300 للنص القصير، 3–2000 للنص الطويل.
-- جميع القيود NOT VALID: لا تُفحص البيانات السابقة، تُطبَّق على الكتابة الجديدة فقط.
-- تشغيل عبر: supabase db push

-- =====================================================================
-- 1. جدول: requests
--    title  — نص قصير اختياري (3–300 حرف)
--    reason — نص قصير اختياري (3–300 حرف)
-- =====================================================================

-- V17 §1.3: عنوان الطلب — إن أُدخل يجب أن يكون بين 3 و300 حرف
alter table public.requests
  add constraint chk_requests_title_length
    check (title is null or (length(title) >= 3 and length(title) <= 300))
  not valid;
comment on constraint chk_requests_title_length on public.requests is
  'V17 §1.3 — عنوان الطلب: إن أُدخل، يجب ألّا يقل عن 3 أحرف ولا يتجاوز 300 حرف.';

-- V17 §1.3: سبب الطلب — إن أُدخل يجب أن يكون بين 3 و300 حرف
alter table public.requests
  add constraint chk_requests_reason_length
    check (reason is null or (length(reason) >= 3 and length(reason) <= 300))
  not valid;
comment on constraint chk_requests_reason_length on public.requests is
  'V17 §1.3 — سبب الطلب: إن أُدخل، يجب ألّا يقل عن 3 أحرف ولا يتجاوز 300 حرف.';

-- =====================================================================
-- 2. جدول: announcements
--    title — نص قصير إلزامي (3–300 حرف)
--    body  — نص طويل إلزامي (3–5000 حرف، استثناء مقصود لإتاحة إعلانات مفصّلة)
-- =====================================================================

-- V17 §1.3: عنوان الإعلان — إلزامي، بين 3 و300 حرف
alter table public.announcements
  add constraint chk_announcements_title_length
    check (length(title) >= 3 and length(title) <= 300)
  not valid;
comment on constraint chk_announcements_title_length on public.announcements is
  'V17 §1.3 — عنوان الإعلان: إلزامي، يجب ألّا يقل عن 3 أحرف ولا يتجاوز 300 حرف.';

-- V17 §1.3: نص الإعلان — إلزامي، حتى 5000 حرف (استثناء معتمد للإعلانات المفصّلة)
alter table public.announcements
  add constraint chk_announcements_body_length
    check (length(body) >= 3 and length(body) <= 5000)
  not valid;
comment on constraint chk_announcements_body_length on public.announcements is
  'V17 §1.3 — نص الإعلان: إلزامي، بين 3 أحرف و5000 حرف (استثناء معتمد للمحتوى المفصّل).';

-- =====================================================================
-- 3. جدول: dispute_cases
--    description — نص طويل اختياري (3–2000 حرف)
-- =====================================================================

-- V17 §1.3: وصف قضية النزاع — إن أُدخل يجب أن يكون بين 3 و2000 حرف
alter table public.dispute_cases
  add constraint chk_dispute_cases_description_length
    check (description is null or (length(description) >= 3 and length(description) <= 2000))
  not valid;
comment on constraint chk_dispute_cases_description_length on public.dispute_cases is
  'V17 §1.3 — وصف قضية النزاع: إن أُدخل، يجب ألّا يقل عن 3 أحرف ولا يتجاوز 2000 حرف.';

-- =====================================================================
-- 4. جدول: kpi_criteria
--    name_ar — نص قصير إلزامي (3–300 حرف)
-- =====================================================================

-- V17 §1.3: اسم معيار KPI بالعربية — إلزامي، بين 3 و300 حرف
alter table public.kpi_criteria
  add constraint chk_kpi_criteria_name_ar_length
    check (length(name_ar) >= 3 and length(name_ar) <= 300)
  not valid;
comment on constraint chk_kpi_criteria_name_ar_length on public.kpi_criteria is
  'V17 §1.3 — اسم معيار الأداء (عربي): إلزامي، يجب ألّا يقل عن 3 أحرف ولا يتجاوز 300 حرف.';

-- =====================================================================
-- 5. جدول: kpi_evaluations
--    حقول التعليق (manager_comment، employee_comment، hr_comment،
--    secretary_comment، executive_comment) — نص طويل اختياري (3–2000 حرف)
--    أُضيفت الحقول عبر ALTER في migration 0058.
-- =====================================================================

-- V17 §1.3: تعليق المدير — إن أُدخل يجب أن يكون بين 3 و2000 حرف
alter table public.kpi_evaluations
  add constraint chk_kpi_evaluations_manager_comment_length
    check (manager_comment is null or (length(manager_comment) >= 3 and length(manager_comment) <= 2000))
  not valid;
comment on constraint chk_kpi_evaluations_manager_comment_length on public.kpi_evaluations is
  'V17 §1.3 — تعليق المدير على التقييم: إن أُدخل، يجب ألّا يقل عن 3 أحرف ولا يتجاوز 2000 حرف.';

-- V17 §1.3: تعليق الموظف — إن أُدخل يجب أن يكون بين 3 و2000 حرف
alter table public.kpi_evaluations
  add constraint chk_kpi_evaluations_employee_comment_length
    check (employee_comment is null or (length(employee_comment) >= 3 and length(employee_comment) <= 2000))
  not valid;
comment on constraint chk_kpi_evaluations_employee_comment_length on public.kpi_evaluations is
  'V17 §1.3 — تعليق الموظف على التقييم: إن أُدخل، يجب ألّا يقل عن 3 أحرف ولا يتجاوز 2000 حرف.';

-- V17 §1.3: تعليق الموارد البشرية — إن أُدخل يجب أن يكون بين 3 و2000 حرف
alter table public.kpi_evaluations
  add constraint chk_kpi_evaluations_hr_comment_length
    check (hr_comment is null or (length(hr_comment) >= 3 and length(hr_comment) <= 2000))
  not valid;
comment on constraint chk_kpi_evaluations_hr_comment_length on public.kpi_evaluations is
  'V17 §1.3 — تعليق الموارد البشرية على التقييم: إن أُدخل، يجب ألّا يقل عن 3 أحرف ولا يتجاوز 2000 حرف.';

-- V17 §1.3: تعليق السكرتير — إن أُدخل يجب أن يكون بين 3 و2000 حرف
alter table public.kpi_evaluations
  add constraint chk_kpi_evaluations_secretary_comment_length
    check (secretary_comment is null or (length(secretary_comment) >= 3 and length(secretary_comment) <= 2000))
  not valid;
comment on constraint chk_kpi_evaluations_secretary_comment_length on public.kpi_evaluations is
  'V17 §1.3 — تعليق السكرتير على التقييم: إن أُدخل، يجب ألّا يقل عن 3 أحرف ولا يتجاوز 2000 حرف.';

-- V17 §1.3: تعليق المدير التنفيذي — إن أُدخل يجب أن يكون بين 3 و2000 حرف
alter table public.kpi_evaluations
  add constraint chk_kpi_evaluations_executive_comment_length
    check (executive_comment is null or (length(executive_comment) >= 3 and length(executive_comment) <= 2000))
  not valid;
comment on constraint chk_kpi_evaluations_executive_comment_length on public.kpi_evaluations is
  'V17 §1.3 — تعليق المدير التنفيذي على التقييم: إن أُدخل، يجب ألّا يقل عن 3 أحرف ولا يتجاوز 2000 حرف.';
