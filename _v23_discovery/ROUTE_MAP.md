# خريطة المسارات — ROUTE_MAP

> **تاريخ الجرد:** 2026-07-26 | **Agent 00A**

---

## 1. مسارات الويب (React)

### مساحة HR (`/hr`)

| المسار | المكون | حارس الصلاحية | الحالة |
|---|---|---|---|
| `/hr` | `DashboardPage type="hr"` | — | ✅ نشط |
| `/hr/employees` | `EmployeesPage` | `people.employee.read` | ✅ نشط |
| `/hr/employees/new` | `CreateEmployeePage` | `people.employee.create` | ✅ نشط |
| `/hr/employees/:employeeId` | `EmployeeDetailPage` | `people.employee.read` | ✅ نشط |
| `/hr/attendance` | `AttendancePage` | `attendance.record.read` | ✅ نشط |
| `/hr/attendance/operations` | `AttendanceOperationsPage` | `attendance.roster.read` | ✅ نشط |
| `/hr/attendance/report` | `MonthlyAttendanceReportPage` | `attendance.record.read` | ✅ نشط |
| `/hr/performance` | `PerformancePage` | `performance.kpi.read` | ✅ نشط |
| `/hr/recruitment` | `RecruitmentPage` | `recruitment.requisition.read` | ✅ نشط |
| `/hr/onboarding` | `OnboardingPage` | `onboarding.journey.read` | ✅ نشط |
| `/hr/reports` | `ReportsPage` | `reports.people.read` | ✅ نشط |
| `/hr/holidays` | `OfficialHolidaysPage` | `holidays.manage` | ✅ نشط |
| `/hr/official-feed` | `OfficialFeedPage` | `comms.announcement.read` | ✅ نشط |
| `/hr/notifications` | `NotificationsPage` | — | ✅ نشط |

### مساحة الإدارة (`/admin`)

| المسار | المكون | حارس الصلاحية | الحالة |
|---|---|---|---|
| `/admin` | `DashboardPage type="admin"` | — | ✅ نشط |
| `/admin/actions` | `ActionCenterPage` | `access.role.read` | ✅ نشط |
| `/admin/live-location` | `LiveLocationPage` | `live_location.request` | ✅ نشط |
| `/admin/live-location/monitoring` | `ExecutiveMonitoringPage` | `live_location.request` | ✅ نشط |
| `/admin/device-approvals` | `DeviceApprovalPage` | `access.role.read` | ✅ نشط |
| `/admin/official-feed` | `OfficialFeedPage` | `comms.announcement.manage` | ✅ نشط |
| `/admin/organization` | `OrganizationPage` | `organization.org_chart.read` | ✅ نشط |
| `/admin/performance/cycles` | `KpiCyclesPage` | `performance.cycle.manage` | ✅ نشط |
| `/admin/disputes` | `DisputesPage` | `relations.case.manage` | ✅ نشط |
| `/admin/access` | `AccessPage` | `access.role.read` | ✅ نشط |
| `/admin/settings` | `SystemPage` | `system.settings.read` | ✅ نشط |
| `/admin/reports/scheduler` | `ReportSchedulerPage` | `reports.schedule.manage` | ✅ نشط |
| `/admin/enterprise` | `EnterpriseManagementPage` | `organization.entity.read` | ✅ نشط |
| `/admin/operations` | `OperationsCenterPage` | `tasks.read` | ✅ نشط |
| `/admin/audit-security` | `AuditSecurityPage` | `audit.view` | ✅ نشط |
| `/admin/integrations` | `IntegrationsJobsPage` | `system.integration.view` | ✅ نشط |
| `/admin/notifications` | `NotificationsPage` | — | ✅ نشط |

### مساحة اللجنة (`/committee`)

| المسار | المكون | حارس الصلاحية | الحالة |
|---|---|---|---|
| `/committee` | `DisputesPage` | `disputes.portal.access` | ✅ نشط |
| `/committee/disputes` | `DisputesPage` | `disputes.portal.access` | ✅ نشط |
| `/committee/notifications` | `NotificationsPage` | — | ✅ نشط |

### مسارات خاصة

| المسار | المكون | الشرط |
|---|---|---|
| `/mobile-redirect` | `MobileRedirectPage` | بدون مصادقة |
| `/auth/setup-password` | `PasswordSetupPage` | استعادة كلمة مرور |
| `/*` | `Navigate` → مساحة افتراضية | Catch-all |

### مسارات مخفية (V17 §4.2)

تعليق صريح في `App.tsx` يؤكد إخفاء هذه المسارات:

| المسار المخفي | المكون | السبب |
|---|---|---|
| lifecycle | `LifecycleOperationsPage` | مخفي — import محذوف |
| learning | `LearningPage` | مخفي — تدريب ومهارات |
| documents | `DocumentStudioPage` | مخفي — مستنداتي |
| people-finance | `PeopleFinancePage` | مخفي — رواتب ممنوعة |
| governance | `ReleaseGovernancePage` | مخفي — حوكمة |
| helpdesk | `ServiceDeskPage` | مخفي — مكتب خدمات |
| org-chart | `OrgChartPage` | لم يُنفذ بعد |

---

## 2. مسارات الموبايل (Flutter GoRouter)

### مسارات التطبيق

| المسار | المكون | الغرض |
|---|---|---|
| `/` | `AppGate` | بوابة اختيار المساحة |
| `/action/:kind/:actionId` | `MobileActionDeepLinkPage` | رابط عميق للإجراءات |

### التنقل داخل مساحات العمل

التنقل بين الصفحات داخل كل مساحة يتم عبر `Navigator.push` المباشر وليس GoRouter:

#### مساحة الموظف
- `employee_home_page.dart` — الصفحة الرئيسية
- `mobile_attendance_page.dart` — الحضور
- `mobile_attendance_services_page.dart` — خدمات الحضور
- `attendance_history_page.dart` — سجل الحضور
- `monthly_attendance_statement_page.dart` — كشف شهري
- `mobile_requests_page.dart` — الطلبات
- `mobile_request_detail_page.dart` — تفاصيل الطلب
- `mobile_kpi_page.dart` — تقييم الأداء
- `kpi_evaluation_detail_page.dart` — تفاصيل التقييم
- `mobile_disputes_page.dart` — الشكاوى
- `mobile_self_service_page.dart` — الخدمة الذاتية
- `mobile_tasks_page.dart` — المهام
- `mobile_daily_reports_page.dart` — التقارير اليومية
- `mobile_official_feed_page.dart` — المنشورات
- `mobile_feed_detail_page.dart` — تفاصيل المنشور
- `mobile_notifications_page.dart` — الإشعارات
- `mobile_profile_page.dart` — الملف الشخصي
- `passkey_devices_page.dart` — أجهزة مفاتيح المرور
- `org_chart_page.dart` — الهيكل التنظيمي
- `mobile_team_page.dart` — الفريق
- `mobile_action_inbox_page.dart` — صندوق الإجراءات
- `mobile_action_deep_link_page.dart` — رابط عميق
- `mobile_action_router.dart` — موجه الإجراءات

#### مساحة المدير
- `manager_home_page.dart` — الصفحة الرئيسية
- `manager_operations_page.dart` — العمليات
- + جميع صفحات الموظف

#### مساحة التنفيذي
- `executive_home_page.dart` — الصفحة الرئيسية
- `executive_brief_page.dart` — ملخص تنفيذي
- `executive_people_page.dart` — الموظفون
- `executive_employee_summary_page.dart` — ملخص موظف
- `executive_attendance_tab.dart` — الحضور
- `executive_location_page.dart` — الموقع المباشر
- `executive_decisions_page.dart` — القرارات
- `executive_disputes_page.dart` — الشكاوى
- `executive_reports_page.dart` — التقارير
- `executive_announcement_page.dart` — الإعلانات
- `executive_governance_page.dart` — الحوكمة
- `executive_risk_center_page.dart` — المخاطر
- `executive_emergency_page.dart` — الطوارئ
- `live_tracking_session_page.dart` — تتبع مباشر
- `location_requests_page.dart` — طلبات الموقع
- `location_incoming_overlay.dart` — إشعار موقع وارد
- `mobile_location_request_deep_link_page.dart` — رابط عميق

#### مساحة اللجنة
- `committee_dispute_list_page.dart` — قائمة الشكاوى

#### مساحة التشغيل
- صفحات الموظف + صلاحيات المدير ضمن النطاق

---

## 3. حراس الحماية

### الويب
1. **`WorkspaceGuard`** — يتحقق `auth.access.workspaces.includes(workspace)`
2. **`RequirePermission`** — يتحقق `hasPermission(auth.access, perm)` → يعرض `ForbiddenState` عند الرفض

### الموبايل
1. **`AppGate`** — بوابة المصادقة واختيار المساحة
2. **`AccessContext`** — كائن صلاحيات يحدد المساحات والصلاحيات المتاحة
