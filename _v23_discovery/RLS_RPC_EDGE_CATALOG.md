# كتالوج RLS/RPC/Edge — RLS_RPC_EDGE_CATALOG

> **تاريخ الجرد:** 2026-07-26 | **Agent 00A**

---

## ملخص

| المقياس | القيمة |
|---|---|
| سياسات RLS (CREATE POLICY) | ~583 |
| دوال SECURITY DEFINER | ~500+ |
| دوال SECURITY INVOKER | ~20 |
| Triggers صريحة | 1 + ديناميكية |
| Edge Functions | 12 (+ 1 معطل) |
| وحدات _shared | 3 |
| USING(true) policies | ~22 (جداول مرجعية فقط) |

---

## 1. سياسات RLS — حسب الجدول

### جداول مرجعية بـ USING(true) — مقبولة

| الجدول | السياسة | العملية | Migration |
|---|---|---|---|
| `permissions` | `permissions_read` | SELECT | 0002 |
| `roles` | `roles_read` | SELECT | 0002 |
| `role_permissions` | `role_perms_read` | SELECT | 0002 |
| `leave_types` | `leave_types_select` | SELECT | 0006 |
| `workflow_definitions` | `workflow_definitions_select` | SELECT | 0006 |
| `workflow_steps` | `workflow_steps_select` | SELECT | 0006 |
| `kpi_templates` | `kpi_templates_select` | SELECT | 0007 |
| `kpi_criteria` | `kpi_criteria_select` | SELECT | 0007 |
| `competencies` | `competencies_select` | SELECT | 0007 |
| `competency_levels` | `competency_levels_select` | SELECT | 0007 |
| `role_competency_profiles` | `role_competency_profiles_select` | SELECT | 0007 |
| `review_cycle_templates` | `review_cycle_templates_select` | SELECT | 0007 |
| `feature_flags` | `feature_flags_select` | SELECT | 0011 |
| `kpi_policy_versions` | `kpi_policy_versions_read` | SELECT | 0058 |
| `public_holidays` | `public_holidays_select` | SELECT | 0132 |
| `employee_departments` | `employee_departments_select` | SELECT | 0156 |
| جداول تنظيمية (~15) | دينامكية | SELECT | 0003 |

### جداول محمية — أنماط RLS الرئيسية

**الموظفون:**
- `employees` — SELECT/INSERT/UPDATE/DELETE via `can_access_employee()` + `current_is_full_access()`
- `profiles` — self-access (`id = auth.uid()`) + full-access

**الحضور:**
- `attendance_events` — self-read أو full-access، INSERT يتطلب `attendance.record.manual_create`
- `passkey_credentials` — self-access via `current_employee_id()`
- `webauthn_challenges` — self-access

**الطلبات:**
- `requests` — self (requester) أو has_permission
- `leave_requests`, `missions`, `convoy_requests` — مرتبطة بـ requests

**KPI:**
- `kpi_evaluations` — evaluator/evaluatee/full-access/permission
- `kpi_scores` — مرتبطة بالتقييم

**الشكاوى:**
- `dispute_cases` — via `can_access_dispute(id)` function
- جميع الجداول الفرعية — نفس النمط

**التخزين (Storage):**
- `employee-documents`, `candidate-documents`, `employee-avatars`, `announcement-images`, `request-attachments`, `report-files`, `live-location-map-snapshots` — مسار مرتبط بـ employee_id

---

## 2. الدوال/RPCs الرئيسية

### دوال التخويل الأساسية (mig 0002)

| الدالة | النوع | الوصف |
|---|---|---|
| `current_is_full_access()` | DEFINER, stable | هل المستخدم full-access? |
| `current_is_super_admin()` | DEFINER, stable | هل المستخدم super admin? |
| `has_permission(text)` | DEFINER, stable | فحص صلاحية واحدة |
| `has_any_permission(text[])` | DEFINER, stable | فحص أي صلاحية من مجموعة |
| `current_employee_id()` | DEFINER, stable | UUID الموظف الحالي |
| `can_access_employee(uuid)` | DEFINER, stable | هل يمكن الوصول لهذا الموظف? |
| `rpc_assign_role()` | DEFINER | إسناد دور |
| `rpc_revoke_role()` | DEFINER | سحب دور |

### إدارة الموظفين

| الدالة | Migration | الوصف |
|---|---|---|
| `provision_employee_record()` | 0004+ | إنشاء سجل موظف (يتجاوز rpc_assign_role) |
| `handle_new_user()` | 0004 | auth trigger عند إنشاء مستخدم |
| `archive_employee_secure()` | 0090 | أرشفة آمنة (يلغي أجهزة/مفاتيح/جلسات) |
| `hard_delete_employee_guarded()` | 0090 | حذف نهائي (يتطلب تأكيد مزدوج) |
| `change_employee_manager_admin()` | 0084 | تغيير المدير |

### الحضور

| الدالة | Migration | الوصف |
|---|---|---|
| `finalize_verified_attendance()` | 0089 | تسجيل حضور ذري idempotent |
| `punch_attendance_local()` | 0094 | حضور بصمة محلية |
| `get_attendance_dashboard()` | 0005+ | لوحة الحضور (INVOKER) |
| `get_my_attendance_state()` | 0005+ | حالة حضوري |
| `get_my_attendance_services()` | 0005+ | خدمات حضوري |

### الطلبات

| الدالة | Migration | الوصف |
|---|---|---|
| `submit_my_request()` | 0006+ | تقديم طلب |
| `resolve_request_approver()` | 0006+ | تحديد المعتمد |
| `process_request_sla()` | 0018 | SLA (service_role فقط) |
| `get_request_inbox()` | 0006+ | صندوق الطلبات (INVOKER) |

### KPI

| الدالة | Migration | الوصف |
|---|---|---|
| `advance_kpi_stage()` | 0007+ | تقديم مرحلة KPI |
| `return_kpi_stage()` | 0007+ | إعادة مرحلة |
| `create_kpi_cycle_admin()` | 0058 | إنشاء دورة |
| `manage_kpi_cycle()` | 0058 | إدارة دورة |
| `override_kpi_score()` | 0058 | تجاوز درجة |

### الموقع المباشر

| الدالة | Migration | الوصف |
|---|---|---|
| `request_live_location()` | 0017+ | طلب موقع |
| `respond_live_location_request()` | 0017+ | استجابة موقع |
| `get_location_directory()` | 0017+ | دليل الموظفين |
| `cancel_location_request()` | 0070 | إلغاء طلب |

### الشكاوى

| الدالة | Migration | الوصف |
|---|---|---|
| `submit_my_dispute()` | 0059 | تقديم شكوى |
| `transition_dispute_case()` | 0059 | تغيير حالة |
| `can_access_dispute()` | 0030 | فحص الوصول |
| `get_committee_dispute_portal()` | 0152 | بوابة اللجنة |

### الأجهزة

| الدالة | Migration | الوصف |
|---|---|---|
| `activate_verified_passkey_device()` | 0073+ | تفعيل جهاز |
| `approve_device()` | 0145 | اعتماد جهاز |
| `revoke_my_passkey()` | 0023 | إلغاء مفتاح مرور |
| `register_my_device()` | 0095 | تسجيل جهاز |

### المراجعة

| الدالة | Migration | الوصف |
|---|---|---|
| `log_audit_event()` | 0011 | تسجيل حدث مراجعة (المسار الوحيد) |
| `log_security_event()` | 0011 | تسجيل حدث أمني |
| `get_system_health()` | 0054 | صحة النظام |

### دوال الـ Cron (service_role فقط)

| الدالة | الوصف |
|---|---|
| `process_request_sla()` | معالجة SLA الطلبات |
| `process_dispute_sla()` | معالجة SLA الشكاوى |
| `detect_and_raise_alerts()` | رصد التنبيهات |
| `generate_kpi_cycle_notifications()` | إشعارات KPI |
| `process_kpi_cycle_schedule()` | جدولة دورات KPI |
| `generate_punch_reminders()` | تذكيرات الحضور |

---

## 3. Triggers

| الاسم | الجدول | الدالة | Migration |
|---|---|---|---|
| `trg_employee_open_leave_entitlement` | employees (INSERT) | `tg_open_employee_leave_entitlement()` | 0082 |
| updated_at triggers | عديدة | `trigger_set_timestamp()` | ديناميكي |
| audit triggers | جداول حساسة | `log_audit_event()` | ديناميكي |

---

## 4. Edge Functions

| الوظيفة | الطريقة | المصادقة | الجداول المستخدمة | وحدات _shared |
|---|---|---|---|---|
| `identifier-sign-in` | POST | عام | login_auth_attempts, employees, profiles | cors, phone |
| `admin-create-employee` | POST | Bearer + permission | roles, profiles | cors, phone |
| `admin-resend-invite` | POST | Bearer + permission | profiles, auth_invite_log | cors |
| `passkey-register` | POST | Bearer | profiles, webauthn_challenges, passkey_credentials | cors |
| `webauthn-challenge` | POST | Bearer | profiles, employees, webauthn_challenges, passkey_credentials | cors |
| `verify-attendance-punch` | POST | Bearer | profiles, attendance_punch_attempts, passkey_credentials, employee_devices, webauthn_challenges | cors |
| `live-location-map-url` | POST | Bearer + RPC gate | live_location_map_access_logs + Storage | cors |
| `live-location-video-url` | ANY | — | — (معطل 410) | cors |
| `notification-dispatcher` | POST | x-cron-secret | notification_jobs, notifications, push_subscriptions, notification_delivery_log | cors, secret |
| `integration-outbox-worker` | POST | x-cron-secret | integration_outbox, integrations, integration_logs | cors, secret |
| `retention-cleanup` | POST | x-cron-secret | location_request_responses, login_auth_attempts + Storage | cors, secret |
| `scheduled-report-runner` | POST | x-cron-secret | report_runs + RPC | cors, secret |

### وحدات _shared

| الملف | الصادرات | المستخدمة بواسطة |
|---|---|---|
| `cors.ts` | `corsHeaders()`, `json()`, `preflight()` | جميع الوظائف |
| `phone.ts` | `normalizePhone()` | admin-create-employee, (identifier-sign-in يستخدم نسخة داخلية) |
| `secret.ts` | `timingSafeEqual()` | integration-outbox-worker, notification-dispatcher, retention-cleanup, scheduled-report-runner |

---

## 5. تقييم أمني

### ✅ نقاط القوة
1. **SECURITY DEFINER + search_path**: جميع الدوال (~500+) تستخدم `set search_path = public, pg_temp`
2. **Revoke-from-public**: كل RPC حساس يتبع `revoke from public; grant to authenticated`
3. **Defense-in-depth**: جداول حساسة لديها DML revoked (dispute, decision, leave_ledger, attendance, KPI)
4. **USING(true) مقيد**: فقط على جداول القراءة المرجعية
5. **Service-role isolation**: دوال Cron محدودة لـ service_role
6. **مسار مراجعة موحد**: `log_audit_event()` هو المسار الوحيد للكتابة
7. **منع الإسناد الذاتي**: mig 0159/0161 يمنع منح full-access لنفس المستخدم

### ⚠️ ملاحظات
1. **تكرار أرقام Migration**: 0159 (ملف واحد)، 0160 (ملفان بنفس الرقم)، 0062 (3 ملفات)
2. **تكرار إنشاء دوال**: `record_attendance_event` أُنشئ/أُسقط 5+ مرات (0078-0082)
3. **search_path مع auth**: بعض الدوال (0033-0036) تستخدم `public, auth` بدل `public, pg_temp`
4. **Storage policies**: تعتمد على مسارات ملفات (folder name = employee_id) — قد تُخدع
