# USING(true) RLS Allowlist — أحلى شباب HR V23

> **تاريخ المراجعة:** 2026-07-27
> **المراجع:** Agent 14 (Integration)
> **القاعدة:** `USING(true)` مقبول **فقط** على جداول القراءة المرجعية (CLAUDE.md §Security).
> كل جدول هنا يستخدم `FOR SELECT TO authenticated USING(true)` — أي موظف مسجّل يقرأ.
> العمليات الأخرى (INSERT/UPDATE/DELETE) محمية بـ `current_is_full_access()` أو `has_permission()`.

---

## الجداول المعتمدة (31 جدول)

### مجموعة 1: الصلاحيات والأدوار (Migration 0002)
| الجدول | السياسة | المبرر | الخطر |
|---|---|---|---|
| `permissions` | `permissions_read` | قائمة ثابتة لأسماء الصلاحيات — لا بيانات حساسة | 🟢 LOW |
| `roles` | `roles_read` | قوالب الأدوار — أسماء عربية ثابتة | 🟢 LOW |
| `role_permissions` | `role_perms_read` | ربط M2M بين الأدوار والصلاحيات — معرّفات فقط | 🟢 LOW |

### مجموعة 2: الهيكل التنظيمي (Migration 0003)
| الجدول | السياسة | المبرر | الخطر |
|---|---|---|---|
| `legal_entities` | `legal_entities_select_authenticated` | الكيانات القانونية — مرجعي | 🟢 LOW |
| `branches` | `branches_select_authenticated` | الفروع — مرجعي | 🟢 LOW |
| `work_sites` | `work_sites_select_authenticated` | مواقع العمل — يحتاجها تطبيق الحضور | 🟢 LOW |
| `cost_centers` | `cost_centers_select_authenticated` | مراكز التكلفة — مرجعي | 🟢 LOW |
| `departments` | `departments_select_authenticated` | الإدارات — مرجعي، يحتاجها كل الموظفين | 🟢 LOW |
| `teams` | `teams_select_authenticated` | الفرق — مرجعي | 🟢 LOW |
| `positions` | `positions_select_authenticated` | المناصب — مرجعي | 🟢 LOW |
| `job_titles` | `job_titles_select_authenticated` | المسميات الوظيفية — مرجعي | 🟢 LOW |
| `job_grades` | `job_grades_select_authenticated` | الدرجات الوظيفية — مرجعي | 🟢 LOW |
| `employment_types` | `employment_types_select_authenticated` | أنواع التوظيف — مرجعي | 🟢 LOW |
| `geofences` | `geofences_select_authenticated` | نطاقات جغرافية — يحتاجها تطبيق الحضور | 🟡 MEDIUM |
| `shifts` | `shifts_select_authenticated` | الورديات — مرجعي | 🟢 LOW |
| `shift_patterns` | `shift_patterns_select_authenticated` | أنماط الورديات — مرجعي | 🟢 LOW |
| `public_holidays` | `public_holidays_select_authenticated` | العطل الرسمية — مرجعي عام | 🟢 LOW |
| `working_calendars` | `working_calendars_select_authenticated` | تقاويم العمل — مرجعي | 🟢 LOW |

### مجموعة 3: سير العمل (Migration 0006)
| الجدول | السياسة | المبرر | الخطر |
|---|---|---|---|
| `leave_types` | `leave_types_select` | أنواع الإجازات (اعتيادية/عارضة/مرضية) — مرجعي | 🟢 LOW |
| `workflow_definitions` | `workflow_definitions_select` | تعريفات سير العمل — مرجعي | 🟢 LOW |
| `workflow_steps` | `workflow_steps_select` | خطوات سير العمل — مرجعي | 🟢 LOW |

### مجموعة 4: الأداء والكفاءات (Migration 0007)
| الجدول | السياسة | المبرر | الخطر |
|---|---|---|---|
| `kpi_templates` | `kpi_templates_select` | قوالب مؤشرات الأداء — مرجعي | 🟢 LOW |
| `kpi_criteria` | `kpi_criteria_select` | معايير التقييم — مرجعي (أوزان ثابتة) | 🟢 LOW |
| `competencies` | `competencies_select` | قائمة الكفاءات — مرجعي | 🟢 LOW |
| `competency_levels` | `competency_levels_select` | مستويات الكفاءات — مرجعي | 🟢 LOW |
| `role_competency_profiles` | `role_competency_profiles_select` | ربط الأدوار بالكفاءات — مرجعي | 🟢 LOW |
| `review_cycle_templates` | `review_cycle_templates_select` | قوالب دورات المراجعة — مرجعي | 🟢 LOW |

### مجموعة 5: مهام وأصول (Migration 0009)
| الجدول | السياسة | المبرر | الخطر |
|---|---|---|---|
| `task_templates` | `task_templates_select` | قوالب المهام — مرجعي | 🟢 LOW |
| `asset_inventory` | `asset_inventory_select` | سجل الأصول — ⚠️ يحتوي بيانات مادية | 🟡 MEDIUM |

### مجموعة 6: ميزات ونظام (Migrations 0011, 0033, 0058)
| الجدول | السياسة | المبرر | الخطر |
|---|---|---|---|
| `feature_flags` | `feature_flags_select` | أعلام الميزات — يحتاجها العميل لعرض الواجهة | 🟢 LOW |
| `learning_course_sessions` | `learning_sessions_read` | جلسات التدريب — مرجعي (الصفحة مخفية V17 §4.2) | 🟢 LOW |
| `kpi_policy_versions` | `kpi_policy_versions_read` | إصدارات سياسة KPI — مرجعي | 🟢 LOW |

### مجموعة 7: V23 إضافات (Migrations 0156, 0165)
| الجدول | السياسة | المبرر | الخطر |
|---|---|---|---|
| `employee_departments` | `employee_departments_select` | ربط M2M موظف↔إدارة — يحتاجها الهيكل التنظيمي | 🟡 MEDIUM |
| `attendance_settings` | `attendance_settings_select` | إعدادات الحضور (geofence radius, accuracy) — مرجعي | 🟢 LOW |

---

## ملخص المخاطر

| المستوى | العدد | الجداول |
|---|---|---|
| 🟢 LOW | 28 | صلاحيات، أدوار، هيكل تنظيمي، ورديات، عطل، قوالب، ميزات |
| 🟡 MEDIUM | 3 | `geofences` (إحداثيات مواقع)، `asset_inventory` (أصول مادية)، `employee_departments` (ربط موظف↔إدارة) |
| 🔴 HIGH | 0 | لا يوجد |

## التوصيات

1. **الجداول الـ28 LOW**: ✅ مقبولة — بيانات مرجعية بحتة لا تحتوي معلومات شخصية.
2. **`geofences`**: مقبول — الإحداثيات مطلوبة لتطبيق الحضور على الهاتف. لا تحتوي PII.
3. **`asset_inventory`**: ⚠️ مراقبة — إذا أُضيفت بيانات تخصيص شخصية (من يملك ماذا)، يجب تقييد القراءة.
4. **`employee_departments`**: مقبول — الربط ضروري لعرض الهيكل التنظيمي. لا PII مباشر.

## القرار

**جميع الـ31 جدول مقبولة** حسب سياسة CLAUDE.md. لا يوجد جدول حساس يستخدم `USING(true)`.
البيانات الحساسة (employees, attendance_daily, kpi_evaluations, dispute_cases, leave_requests, audit_log)
محمية بسياسات RLS مقيّدة — لم يُعثر على `USING(true)` عليها.
