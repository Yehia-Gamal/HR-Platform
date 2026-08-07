# خطة تنفيذ شاملة — 7 ميزات جديدة

## الميزة 1: تقييد صلاحية HR على الطلبات (رؤية + تدخل طارئ فقط)
**المشكلة الحالية:** `decide_request` (0253) يسمح لـ HR بالموافقة/الرفض بعد 12 ساعة من انتهاء مهلة المدير.
**الحل:** رفع مهلة تدخل HR إلى 72 ساعة (3 أيام) — أي فقط بعد 3 أيام من عدم اتخاذ قرار من المدير المباشر، كحالة طارئة. المدير المباشر يظل المتخذ الأساسي للقرار.

**الملفات:**
- `supabase/migrations/0313_*.sql` — تعديل `decide_request`: تغيير شرط HR من 12h إلى 72h
- لا حاجة لتغيير واجهة — HR يرى الطلبات عبر `get_request_inbox` و RLS الموجودة

---

## الميزة 2: الإجازة المرضية بدون حد (unlimited)
**المشكلة الحالية:** `max_days_per_year = 24` في `leave_types` + hardcoded `24` في `open_annual_leave_entitlement` و `effective_annual_entitlement`.

**الحل:**
- `UPDATE leave_types SET max_days_per_year = NULL WHERE code = 'sick'`
- تعديل `open_annual_leave_entitlement` و `effective_annual_entitlement`: sick → NULL/0 (غير محدود)
- تعديل `apply_monthly_leave_accrual`: تخطّي sick من فحص الحد الأقصى

**الملفات:**
- `supabase/migrations/0313_*.sql` — سطر UPDATE + إعادة تعريف الدوال

---

## الميزة 3: المأمورية + الإذنات تُعفي من التأخير/الغياب
**المشكلة الحالية:** الإجازة المعتمدة تُسجّل `on_leave` في `attendance_daily`، لكن المأمورية و إذن التأخير/الانصراف لا يُحدثان حالة الحضور.

**الحل:** تريجر على `requests` (AFTER UPDATE status → approved): إذا النوع `mission` → ضبط `attendance_daily.status = 'present'` + علم `mission_exempt = true`؛ إذا `late_permit` → ضبط `attendance_daily.status = 'present'` + تقليل `late_minutes` إلى 0؛ إذا `early_permit` → لا تغيير في الحالة لكن علم `early_leave_exempt = true`.

**الملفات:**
- `supabase/migrations/0314_*.sql` — تريجر `tg_request_approved_attendance_exempt`
- تعديل `refresh_kpi_attendance_inputs` (إن لزم) لاحترام الأعلام الجديدة

---

## الميزة 4: تفويض المدير التنفيذي للأوبريشن بعد 6 ساعات
**الحالة الحالية:** هذا المنطق **موجود بالفعل** — `process_request_sla` (0062) يعمل كل 10 دقائق ويعيد التعيين إلى `operations-officer` بعد 6 ساعات للمدير التنفيذي (0173). 

**التحقق:** سأتأكد من أن الـ cron job يعمل وأن `get_escalation_hours` ترجع 6 للـ executive-director. قد أحتاج تعديلاً بسيطاً إذا كان هناك خلل في المسار.

**الملفات:**
- تحقق فقط + إصلاح بسيط إن لزم

---

## الميزة 5: صفحة التقارير اليومية العامة + تفاعل (لايك/تعليق)
**المشكلة الحالية:** التقارير اليومية موجودة لكن للموبايل فقط ويرى المدير تقارير فريقه فقط. لا يوجد نظام لايك/تعليق.

**الحل:**
- جدول جديد `daily_report_likes` (report_id, employee_id, created_at)
- جدول جديد `daily_report_comments` (id, report_id, employee_id, comment, created_at)
- RPC جديد `get_daily_reports_feed(p_limit, p_offset)` — يرجع كل التقارير مع بيانات الموظف (الاسم/الصورة/المسمى/المدير) + عدد اللايكات + آخر التعليقات. متاح لكل المستخدمين المصادق عليهم.
- RPC `toggle_daily_report_like(p_report_id)`
- RPC `add_daily_report_comment(p_report_id, p_comment)` / `delete_daily_report_comment(p_comment_id)`
- إشعار تلقائي للموظف عند التعليق/الإعجاب بتقريره
- صفحة ويب جديدة `DailyReportsFeedPage.tsx` في admin_web
- صفحة موبايل جديدة/محدّثة في mobile_flutter

**الملفات:**
- `supabase/migrations/0315_*.sql` — الجداول + RPCs + RLS + إشعارات
- `apps/admin_web/src/features/reports/DailyReportsFeedPage.tsx` — صفحة جديدة
- `apps/admin_web/src/ui/` — مكوّنات اللايك/التعليق
- `apps/mobile_flutter/lib/features/mobile_pages/daily_reports_feed_page.dart` — صفحة موبايل

---

## الميزة 6: إرسال الموقع المباشر تلقائياً للشيخ محمد
**المشكلة الحالية:** لا يوجد مسار لإرسال الموقع من الموظف → المدير التنفيذي. النظام الحالي manager→employee فقط.

**الحل:**
- RPC جديد `share_my_location_proactively(p_latitude, p_longitude, p_accuracy, p_address_ar)`:
  - يُنشئ `live_location_requests` بـ `requested_by = NULL` (تلقائي) + `status = 'active'` + `purpose = 'safety'`
  - يُدرج نقطة في `employee_locations`
  - يُدرج إشعار `urgent` للمدير التنفيذي (موظف bearing role `executive-director`)
  - يُستدعي `nudge_notification_dispatcher()` لإرسال FCM فوراً
- زر في تطبيق الموبايل: "مشاركة موقعي مع الشيخ محمد"
- بطاقة عرض للإشعار على ويب/موبايل المدير التنفيذي

**الملفات:**
- `supabase/migrations/0316_*.sql` — RPC + إشعار
- `apps/mobile_flutter/lib/features/mobile_pages/proactive_location_share_page.dart` أو زر في البروفايل
- استعمال `get_live_location_response` الموجودة لعرض النتيجة

---

## الميزة 7: إشعارات المدير عند حضور/انصراف الموظفين
**المشكلة الحالية:** لا يوجد إشعار للمدير عند تسجيل موظفيه البصمة.

**الحل:**
- تريجر على `attendance_daily` (AFTER INSERT/UPDATE when first_check_in/last_check_out يُسجل):
  - يجمع كل `manager_relations` حيث `employee_id = NEW.employee_id` و `relation_type = 'primary'`
  - يُدرج إشعار `general` لكل مدير: "وصل {اسم الموظف} إلى العمل في {الوقت}" أو "انصرف {اسم الموظف} في {الوقت}"
  - الأولوية `normal` (ليست urgent) — لا تُوقظ الجهاز
- لا حاجة لتغيير UI — الإشعارات تظهر في القائمة الموجودة

**الملفات:**
- `supabase/migrations/0317_*.sql` — تريجر `tg_attendance_manager_notify`

---

## ترتيب التنفيذ (6 migrations + 3 صفحات)

| # | المايقريشن | الميزة |
|---|-----------|--------|
| 1 | `0313_limit_hr_override_and_unlimited_sick.sql` | HR تقييد + إجازة مرضية غير محدودة |
| 2 | `0314_attendance_exempt_for_mission_permits.sql` | مأمورية/إذن = حاضر |
| 3 | `0315_daily_reports_feed_likes_comments.sql` | تقارير يومية عامة + تفاعل |
| 4 | `0316_proactive_location_share.sql` | مشاركة موقع تلقائية |
| 5 | `0317_attendance_manager_notification.sql` | إشعار المدير بالحضور/الانصراف |
| 6 | (تحقق فقط) | تفويض 6 ساعات — موجود مسبقاً |

| الصفحة | المنصة | الميزة |
|--------|--------|--------|
| `DailyReportsFeedPage.tsx` | ويب | #5 |
| `daily_reports_feed_page.dart` | موبايل | #5 |
| زر "مشاركة موقعي" | موبايل | #6 |

## ملاحظات
- كل المايقريشنز تستخدم `CREATE OR REPLACE` (لا تُسقط بيانات)
- الإشعارات تمر عبر `notifications` + `notification-dispatcher` الموجود
- RLS جديدة للتقارير: كل المستخدمين المصادق عليهم يرون التقارير
- نشر: supabase db push → deploy edge functions → vercel deploy