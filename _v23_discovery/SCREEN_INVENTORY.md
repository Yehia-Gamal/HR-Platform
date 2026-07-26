# جرد الشاشات — SCREEN_INVENTORY

> **تاريخ الجرد:** 2026-07-26 | **Agent 00A**

---

## ملخص

| المنصة | نشط | مخفي | لم يُنفذ | المجموع |
|---|---|---|---|---|
| ويب (صفحات) | 33 | 6 | 1 | 40 |
| ويب (مكونات مشتركة) | 22 | — | — | 22 |
| موبايل (صفحات) | 40 | — | — | 40 |
| موبايل (مساحات عمل) | 7 | — | — | 7 |
| **المجموع** | **102** | **6** | **1** | **109** |

---

## 1. صفحات الويب

### المصادقة

| الملف | المسار | الاسم | الحالة |
|---|---|---|---|
| `features/auth/LoginPage.tsx` | — (شرطي) | تسجيل الدخول | ✅ نشط |
| `features/auth/PasswordSetupPage.tsx` | `/auth/setup-password` | إعداد كلمة المرور | ✅ نشط |
| `features/auth/MobileRedirectPage.tsx` | `/mobile-redirect` | إعادة توجيه الموبايل | ✅ نشط |
| `features/auth/WebReleaseStatusPage.tsx` | — (شرطي) | حالة الإصدار | ✅ نشط |
| `features/auth/AuthProvider.tsx` | — | مزود المصادقة | ✅ نشط (provider) |

### مساحة HR

| الملف | المسار | الاسم | الحالة |
|---|---|---|---|
| `features/workspaces/DashboardPage.tsx` | `/hr` | لوحة المعلومات HR | ✅ نشط |
| `features/employees/EmployeesPage.tsx` | `/hr/employees` | قائمة الموظفين | ✅ نشط |
| `features/employees/CreateEmployeePage.tsx` | `/hr/employees/new` | إنشاء موظف | ✅ نشط |
| `features/employees/EmployeeDetailPage.tsx` | `/hr/employees/:id` | تفاصيل الموظف | ✅ نشط |
| `features/attendance/AttendancePage.tsx` | `/hr/attendance` | سجل الحضور | ✅ نشط |
| `features/advanced/AttendanceOperationsPage.tsx` | `/hr/attendance/operations` | عمليات الحضور | ✅ نشط |
| `features/attendance/MonthlyAttendanceReportPage.tsx` | `/hr/attendance/report` | التقرير الشهري | ✅ نشط |
| `features/performance/PerformancePage.tsx` | `/hr/performance` | تقييم الأداء | ✅ نشط |
| `features/management/RecruitmentPage.tsx` | `/hr/recruitment` | التوظيف | ✅ نشط |
| `features/management/OnboardingPage.tsx` | `/hr/onboarding` | التهيئة | ✅ نشط |
| `features/management/ReportsPage.tsx` | `/hr/reports` | التقارير | ✅ نشط |
| `features/holidays/OfficialHolidaysPage.tsx` | `/hr/holidays` | الإجازات الرسمية | ✅ نشط |
| `features/communications/OfficialFeedPage.tsx` | `/hr/official-feed` | المنشورات | ✅ نشط |
| `features/notifications/NotificationsPage.tsx` | `/hr/notifications` | الإشعارات | ✅ نشط |

### مساحة Admin

| الملف | المسار | الاسم | الحالة |
|---|---|---|---|
| `features/workspaces/DashboardPage.tsx` | `/admin` | لوحة المعلومات Admin | ✅ نشط |
| `features/actions/ActionCenterPage.tsx` | `/admin/actions` | مركز الإجراءات | ✅ نشط |
| `features/management/LiveLocationPage.tsx` | `/admin/live-location` | الموقع المباشر | ✅ نشط |
| `features/management/ExecutiveMonitoringPage.tsx` | `/admin/live-location/monitoring` | المراقبة التنفيذية | ✅ نشط |
| `features/devices/DeviceApprovalPage.tsx` | `/admin/device-approvals` | اعتماد الأجهزة | ✅ نشط |
| `features/management/OrganizationPage.tsx` | `/admin/organization` | الهيكل التنظيمي | ✅ نشط |
| `features/advanced/KpiCyclesPage.tsx` | `/admin/performance/cycles` | دورات KPI | ✅ نشط |
| `features/advanced/DisputesPage.tsx` | `/admin/disputes` | الشكاوى | ✅ نشط |
| `features/management/AccessPage.tsx` | `/admin/access` | الصلاحيات | ✅ نشط |
| `features/management/SystemPage.tsx` | `/admin/settings` | الإعدادات | ✅ نشط |
| `features/management/ReportSchedulerPage.tsx` | `/admin/reports/scheduler` | جدولة التقارير | ✅ نشط |
| `features/management/EnterpriseManagementPage.tsx` | `/admin/enterprise` | الإدارة المؤسسية | ✅ نشط |
| `features/management/OperationsCenterPage.tsx` | `/admin/operations` | مركز العمليات | ✅ نشط |
| `features/management/AuditSecurityPage.tsx` | `/admin/audit-security` | المراجعة والأمان | ✅ نشط |
| `features/management/IntegrationsJobsPage.tsx` | `/admin/integrations` | التكاملات | ✅ نشط |

### صفحات مخفية (V17 §4.2)

| الملف | الاسم | الحالة | السبب |
|---|---|---|---|
| `features/advanced/LifecycleOperationsPage.tsx` | دورة حياة الموظف | 🔒 مخفي | import محذوف من App.tsx |
| `features/management/LearningPage.tsx` | التعلم والتدريب | 🔒 مخفي | تدريب ومهارات (V23 §13) |
| `features/management/DocumentStudioPage.tsx` | استوديو المستندات | 🔒 مخفي | مستنداتي (V23 §13) |
| `features/management/PeopleFinancePage.tsx` | المالية والرواتب | 🔒 مخفي | رواتب ممنوعة (V23 §13) |
| `features/management/ReleaseGovernancePage.tsx` | حوكمة الإصدار | 🔒 مخفي | حوكمة شكلية (V23 §13) |
| `features/management/ServiceDeskPage.tsx` | مكتب الخدمات | 🔒 مخفي | حتى اكتمال Ticket workflow |

### لم يُنفذ

| الاسم | الحالة | ملاحظة |
|---|---|---|
| OrgChartPage | ❌ لم يُنفذ | تعليق في App.tsx: "not yet implemented" |

### مكونات مساعدة (ليست صفحات مستقلة)

| الملف | الغرض |
|---|---|
| `features/attendance/MonthlyStatementSection.tsx` | قسم ضمن صفحة الحضور |
| `features/management/LiveLocationMap.tsx` | مكون خريطة Leaflet |
| `features/management/LiveLocationResultCard.tsx` | بطاقة نتيجة موقع |
| `features/performance/KpiEvaluationEditor.tsx` | محرر تقييم KPI |
| `features/workspaces/WorkspaceShell.tsx` | هيكل المساحة (sidebar + outlet) |

---

## 2. صفحات الموبايل

### الصفحات الرئيسية

| الملف | الاسم | المساحة | الحالة |
|---|---|---|---|
| `employee_home_page.dart` | الصفحة الرئيسية للموظف | Employee | ✅ نشط |
| `manager_home_page.dart` | الصفحة الرئيسية للمدير | Manager | ✅ نشط |
| `executive_home_page.dart` | الصفحة الرئيسية للتنفيذي | Executive | ✅ نشط |

### الحضور

| الملف | الاسم | الحالة |
|---|---|---|
| `mobile_attendance_page.dart` | تسجيل الحضور | ✅ نشط |
| `mobile_attendance_services_page.dart` | خدمات الحضور | ✅ نشط |
| `attendance_history_page.dart` | سجل الحضور | ✅ نشط |
| `monthly_attendance_statement_page.dart` | كشف الحضور الشهري | ✅ نشط |
| `executive_attendance_tab.dart` | حضور تنفيذي | ✅ نشط |

### الطلبات والخدمة الذاتية

| الملف | الاسم | الحالة |
|---|---|---|
| `mobile_requests_page.dart` | قائمة الطلبات | ✅ نشط |
| `mobile_request_detail_page.dart` | تفاصيل الطلب | ✅ نشط |
| `mobile_self_service_page.dart` | الخدمة الذاتية | ✅ نشط |

### الأداء (KPI)

| الملف | الاسم | الحالة |
|---|---|---|
| `mobile_kpi_page.dart` | تقييم الأداء | ✅ نشط |
| `kpi_evaluation_detail_page.dart` | تفاصيل التقييم | ✅ نشط |

### الشكاوى

| الملف | الاسم | الحالة |
|---|---|---|
| `mobile_disputes_page.dart` | شكاوى الموظف | ✅ نشط |
| `committee_dispute_list_page.dart` | قائمة شكاوى اللجنة | ✅ نشط |

### الموقع المباشر

| الملف | الاسم | الحالة |
|---|---|---|
| `executive_location_page.dart` | موقع تنفيذي | ✅ نشط |
| `location_requests_page.dart` | طلبات الموقع | ✅ نشط |
| `location_incoming_overlay.dart` | إشعار موقع وارد | ✅ نشط |
| `live_tracking_session_page.dart` | جلسة تتبع | ✅ نشط |
| `mobile_location_request_deep_link_page.dart` | رابط عميق للموقع | ✅ نشط |

### التنفيذي

| الملف | الاسم | الحالة |
|---|---|---|
| `executive_brief_page.dart` | ملخص تنفيذي | ✅ نشط |
| `executive_people_page.dart` | موظفون تنفيذي | ✅ نشط |
| `executive_employee_summary_page.dart` | ملخص موظف | ✅ نشط |
| `executive_decisions_page.dart` | قرارات | ✅ نشط |
| `executive_disputes_page.dart` | شكاوى تنفيذي | ✅ نشط |
| `executive_reports_page.dart` | تقارير تنفيذي | ✅ نشط |
| `executive_announcement_page.dart` | إعلانات | ✅ نشط |
| `executive_governance_page.dart` | حوكمة | ✅ نشط |
| `executive_risk_center_page.dart` | مركز المخاطر | ✅ نشط |
| `executive_emergency_page.dart` | طوارئ | ✅ نشط |

### أخرى

| الملف | الاسم | الحالة |
|---|---|---|
| `manager_operations_page.dart` | عمليات المدير | ✅ نشط |
| `mobile_tasks_page.dart` | المهام | ✅ نشط |
| `mobile_daily_reports_page.dart` | التقارير اليومية | ✅ نشط |
| `mobile_official_feed_page.dart` | المنشورات الرسمية | ✅ نشط |
| `mobile_feed_detail_page.dart` | تفاصيل المنشور | ✅ نشط |
| `mobile_notifications_page.dart` | الإشعارات | ✅ نشط |
| `mobile_profile_page.dart` | الملف الشخصي | ✅ نشط |
| `mobile_team_page.dart` | الفريق | ✅ نشط |
| `passkey_devices_page.dart` | أجهزة مفاتيح المرور | ✅ نشط |
| `org_chart_page.dart` | الهيكل التنظيمي | ✅ نشط |
| `mobile_action_inbox_page.dart` | صندوق الإجراءات | ✅ نشط |
| `mobile_action_deep_link_page.dart` | رابط عميق | ✅ نشط |
| `mobile_action_router.dart` | موجه الإجراءات | ✅ نشط |
| `mobile_widgets.dart` | مكونات مشتركة | ✅ نشط |

### مساحات العمل (Workspaces)

| الملف | الاسم | الحالة |
|---|---|---|
| `app_gate.dart` | بوابة التطبيق | ✅ نشط |
| `employee_workspace.dart` | مساحة الموظف | ✅ نشط |
| `manager_workspace.dart` | مساحة المدير | ✅ نشط |
| `executive_workspace.dart` | مساحة التنفيذي | ✅ نشط |
| `operations_workspace.dart` | مساحة التشغيل | ✅ نشط |
| `committee_workspace.dart` | مساحة اللجنة | ✅ نشط |
| `workspace_scaffold.dart` | هيكل المساحة المشترك | ✅ نشط |
