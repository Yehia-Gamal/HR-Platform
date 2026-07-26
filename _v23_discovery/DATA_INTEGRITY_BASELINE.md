# خط أساس سلامة البيانات — DATA_INTEGRITY_BASELINE

> **تاريخ الجرد:** 2026-07-26 | **Agent 00A**

---

## 1. العلاقات الأساسية (Foreign Keys)

### سلاسل FK الحرجة

```
auth.users ←── profiles.id (1:1)
                 └── employees.id ←── profiles.employee_id
                       ├── manager_relations.employee_id / manager_id
                       ├── employee_assignments.employee_id
                       ├── attendance_events.employee_id
                       ├── attendance_daily.employee_id
                       ├── requests.employee_id
                       ├── kpi_evaluations.employee_id
                       ├── dispute_cases.complainant_id
                       ├── employee_devices.employee_id
                       ├── passkey_credentials.employee_id
                       ├── push_subscriptions.user_id
                       ├── notifications.user_id
                       ├── daily_reports.employee_id
                       ├── employee_departments.employee_id
                       └── work_assignments.employee_id

departments ←── departments.parent_id (شجري)
              ├── employees.department_id
              ├── teams.department_id
              └── positions.department_id

kpi_cycles ←── kpi_evaluations.cycle_id
                └── kpi_scores.evaluation_id
```

### علاقات متعددة الأطراف

| العلاقة | الجداول | النوع |
|---|---|---|
| موظف ↔ إدارات | `employee_departments` | M:N (P0 primary, P1 secondary) |
| طلب ↔ خطوات | `requests` → `request_steps` → `request_actions` | 1:N:N |
| تقييم ↔ درجات | `kpi_evaluations` → `kpi_scores` | 1:N |
| شكوى ↔ جلسات | `dispute_cases` → `dispute_sessions` → `dispute_session_attendance` | 1:N:N |
| قرار ↔ نسخ/أصوات | `administrative_decisions` → `decision_versions` / `decision_polls` → `decision_poll_votes` | 1:N:N |

---

## 2. مخاطر الأيتام (Orphan Risks)

### ⚠️ مخاطر عالية

| الخطر | السبب | التأثير |
|---|---|---|
| حذف موظف بدون cascade | `hard_delete_employee_guarded()` يتطلب تأكيد مزدوج لكن لا يوجد ON DELETE CASCADE على كل الجداول | سجلات يتيمة في attendance_events, requests, kpi_evaluations |
| أرشفة موظف | `archive_employee_secure()` يعلّم `is_deleted=true` لكن لا يحذف البيانات | بيانات تاريخية تبقى مرتبطة بموظف محذوف |
| حذف إدارة | departments.parent_id شجري — حذف إدارة أب يترك فروع يتيمة | كسر الهيكل التنظيمي |

### ✅ محمي

| السيناريو | الحماية |
|---|---|
| حذف مفتاح مرور | `revoke_my_passkey()` يلغي الجهاز المرتبط تلقائياً (cascade) |
| حذف جلسة موظف | `archive_employee_secure()` يسحب الجلسات والأجهزة |
| حذف دورة KPI | مقيد بالحالة (لا يمكن حذف دورة نشطة) |

---

## 3. فحوصات التناسق المطلوبة قبل V23

### فحوصات بيانات

| الفحص | الاستعلام المقترح | الأولوية |
|---|---|---|
| موظفون بدون profile | `SELECT e.id FROM employees e LEFT JOIN profiles p ON p.employee_id = e.id WHERE p.id IS NULL` | P0 |
| profiles بدون موظف | `SELECT p.id FROM profiles p WHERE p.employee_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM employees WHERE id = p.employee_id)` | P0 |
| موظفون نشطون بدون إدارة | `SELECT id FROM employees WHERE is_active AND department_id IS NULL` | P1 |
| تقييمات KPI بدورة غير موجودة | `SELECT id FROM kpi_evaluations WHERE cycle_id NOT IN (SELECT id FROM kpi_cycles)` | P1 |
| طلبات بدون خطوات | `SELECT id FROM requests WHERE status = 'pending' AND NOT EXISTS (SELECT 1 FROM request_steps WHERE request_id = requests.id)` | P1 |
| أجهزة بدون مفتاح مرور | `SELECT id FROM employee_devices WHERE passkey_credential_id IS NOT NULL AND passkey_credential_id NOT IN (SELECT id FROM passkey_credentials)` | P1 |
| إدارات بحلقة دائرية | CTE recursive يبحث عن حلقات في `departments.parent_id` | P0 |

### فحوصات هيكلية

| الفحص | الحالة المتوقعة |
|---|---|
| كل جدول له RLS مفعّل | ~238 جدول — يجب التحقق |
| كل جدول له سياسة SELECT | أغلب الجداول — يجب التحقق من الجديدة |
| لا يوجد USING(true) على جداول بيانات | ~22 فقط على مرجعية — مقبول |
| كل دالة DEFINER لها search_path = public | ~500+ — تحتاج مراجعة للاستثناءات |

---

## 4. مشاكل معروفة من تاريخ الـ Migrations

### تكرار إنشاء/إسقاط

| الدالة/الكائن | المرات | Migrations |
|---|---|---|
| `record_attendance_event()` | 5+ | 0078, 0080, 0081, 0082 |
| `request_live_location()` | 3+ | 0017, 0067, 0128, 0150 |
| `get_kpi_inbox()` | 2 (INVOKER→DEFINER) | 0019, 0101 |
| `get_employee_home()` | 2 (INVOKER→DEFINER) | 0022, 0102 |
| Employee RLS policies | 3 (replaced) | 0004, 0012, 0014 |

### أرقام Migration مكررة

| الرقم | الملفات | الحالة |
|---|---|---|
| 0159 | `fix_permission_matrix_and_admin_display.sql` | ⚠️ واحد فقط لكن الأرقام اللاحقة تبدأ من 0160 |
| 0160 | `v23_dispute_committee_alignment.sql` + `v23_leaves_escalation_split.sql` | ⚠️ تكرار فعلي |
| 0062 | `request_escalation_on_behalf.sql` (أصلي) + اختبارات بنفس الرقم | ⚠️ تكرار في الاختبارات |

### Bridge Placeholders

| Migration | الغرض |
|---|---|
| 0119_bridge_placeholder.sql | حجز رقم |
| 0122_bridge_placeholder.sql | حجز رقم |

---

## 5. توصيات

1. **تشغيل فحوصات الأيتام** قبل أي تغيير V23 على البيانات
2. **إصلاح أرقام Migration المكررة** (0160) قبل `db push`
3. **توحيد search_path** للدوال التي تستخدم `public, auth` بدل `public, pg_temp`
4. **إضافة ON DELETE constraints** مناسبة للجداول الفرعية الجديدة
5. **مراجعة Storage policies** للتأكد من عدم إمكانية التحايل على مسارات الملفات
