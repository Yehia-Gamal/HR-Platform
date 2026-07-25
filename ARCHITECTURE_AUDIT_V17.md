# 🏗️ خريطة المعمارية الحالية — Phase 0 Audit (V17)

> Generated: 2026-07-24 | Branch: `codex/v17-master-plan`

---

## 1. ملخص تنفيذي

| البُعد | القيمة |
|---|---|
| **Migrations** | 128 ملف SQL (0001–0128) |
| **Edge Functions** | 12 دالة |
| **Shared Contracts** | 10 ملفات Zod + 10 test files |
| **Flutter Pages** | 45 صفحة |
| **Flutter Workspaces** | 5 (employee, manager, executive, operations, committee) |
| **Web Pages** | 61 ملف TSX |
| **Web Routes** | 3 workspaces (hr, main_admin, committee) — ~30 route |
| **pgTAP Tests** | 51 ملف اختبار |
| **SECURITY DEFINER** | 33 occurrence في 18 migration |
| **`USING (true)`** | ✅ **صفر** — نظيف |
| **Service Role في Client** | ✅ **صفر** — نظيف |
| **Secrets exposure** | ✅ محمي (.gitignore يغطي كل الأنماط) |

---

## 2. Flutter Mobile — جرد كامل

### 2.1 Workspaces (نقاط الدخول حسب الدور)

| Workspace | الملف | التبويبات |
|---|---|---|
| **Employee** | `employee_workspace.dart` | يومي، الحضور، طلباتي، KPI، حسابي |
| **Manager** | `manager_workspace.dart` | يومي، فريقي، الطلبات، KPI، التشغيل |
| **Executive** | `executive_workspace.dart` | الرئيسية، الوارد، الموقع، التقارير، الحوكمة |
| **Operations** | `operations_workspace.dart` | يومي، الطلبات، اللجنة، KPI، التشغيل |
| **Committee** | `committee_workspace.dart` | (تم قراءته سابقاً — لجنة الخلافات) |

### 2.2 صفحات يجب إخفاؤها/حذفها (V17 §4.2)

| الصفحة | الملف | الإجراء المطلوب |
|---|---|---|
| **Privacy** | `mobile_privacy_page.dart` | 🔴 إخفاء |
| **Learning/Training** | `mobile_learning_page.dart` | 🔴 إخفاء |
| **Service Portal** | `mobile_service_portal_page.dart` | 🔴 إخفاء |
| **Video Verification** | `video_verification_page.dart` | 🔴 **حذف** (الفيديو ملغى نهائياً) |
| **Tasks** | `mobile_tasks_page.dart` | 🟡 مراجعة — قد يكون placeholder |
| **Live Tracking Session** | `live_tracking_session_page.dart` | 🟡 مراجعة — قد يتعلق بالفيديو |

### 2.3 بقايا الفيديو (يجب إزالتها — V17 §9)

| الملف | السطر | المحتوى |
|---|---|---|
| `mobile_providers.dart` | 790-803 | `registerLocationVideo()` + RPC `register_live_location_video` |
| `executive_location_page.dart` | 338, 356 | `videocam` icon + `location_video` mode |
| `location_requests_page.dart` | 8, 184, 191 | import + `needsVideo` check + navigate to `VideoVerificationPage` |
| `location_incoming_overlay.dart` | 6, 149, 159 | import + `needsVideo` check + navigate to `VideoVerificationPage` |
| `connectivity_service.dart` | 100 | `video_required` message check |
| `video_verification_page.dart` | **كامل** | الصفحة بأكملها — حذف |

### 2.4 صفحات وظيفية (P0 Core)

| الصفحة | الملف | الحالة |
|---|---|---|
| Employee Home | `employee_home_page.dart` | ✅ وظيفي |
| Attendance | `mobile_attendance_page.dart` | ✅ وظيفي |
| Self Service (طلبات) | `mobile_self_service_page.dart` | ✅ وظيفي |
| KPI | `mobile_kpi_page.dart` | ✅ وظيفي |
| Profile | `mobile_profile_page.dart` | ✅ وظيفي |
| Notifications | `mobile_notifications_page.dart` | ✅ وظيفي |
| Passkey Devices | `passkey_devices_page.dart` | ✅ وظيفي |
| Action Inbox | `mobile_action_inbox_page.dart` | ✅ وظيفي |
| Location Requests | `location_requests_page.dart` | ⚠️ يحتاج تنظيف الفيديو |
| Location Incoming | `location_incoming_overlay.dart` | ⚠️ يحتاج تنظيف الفيديو |
| Executive Location | `executive_location_page.dart` | ⚠️ يحتاج تنظيف الفيديو |
| Executive Home | `executive_home_page.dart` | ✅ وظيفي |
| Executive Brief | `executive_brief_page.dart` | ✅ وظيفي |
| Executive People | `executive_people_page.dart` | ✅ وظيفي |
| Executive Reports | `executive_reports_page.dart` | ✅ وظيفي |
| Executive Governance | `executive_governance_page.dart` | 🟡 مراجعة — V17 يخفي Risk/Governance |
| Executive Risk Center | `executive_risk_center_page.dart` | 🔴 إخفاء |
| Manager Home | `manager_home_page.dart` | ✅ وظيفي |
| Manager Operations | `manager_operations_page.dart` | ✅ وظيفي |
| Requests | `mobile_requests_page.dart` | ✅ وظيفي |
| Request Detail | `mobile_request_detail_page.dart` | ✅ وظيفي |
| Daily Reports | `mobile_daily_reports_page.dart` | ✅ وظيفي |
| Disputes | `mobile_disputes_page.dart` | ✅ وظيفي |
| Attendance Services | `mobile_attendance_services_page.dart` | ✅ وظيفي |
| Attendance History | `attendance_history_page.dart` | ✅ وظيفي |
| Monthly Statement | `monthly_attendance_statement_page.dart` | ✅ وظيفي |
| Org Chart | `org_chart_page.dart` | ✅ وظيفي |
| Official Feed | `mobile_official_feed_page.dart` | ✅ وظيفي |
| Team | `mobile_team_page.dart` | ✅ وظيفي |
| KPI Evaluation Detail | `kpi_evaluation_detail_page.dart` | ✅ وظيفي |
| Executive Decisions | `executive_decisions_page.dart` | ✅ وظيفي |
| Executive Disputes | `executive_disputes_page.dart` | ✅ وظيفي |
| Executive Employee Summary | `executive_employee_summary_page.dart` | ✅ وظيفي |
| Executive Emergency | `executive_emergency_page.dart` | 🟡 مراجعة |
| Executive Attendance Tab | `executive_attendance_tab.dart` | ✅ وظيفي |

---

## 3. Web Admin Panel — جرد كامل

### 3.1 Routes والصفحات

#### HR Workspace (`/hr`)

| Route | الصفحة | الحالة V17 |
|---|---|---|
| `/hr` | DashboardPage (hr) | ✅ |
| `/hr/employees` | EmployeesPage | ✅ P0 Core |
| `/hr/employees/new` | CreateEmployeePage | ✅ P0 Core |
| `/hr/employees/:id` | EmployeeDetailPage | ✅ P0 Core |
| `/hr/attendance` | AttendancePage | ✅ P0 Core |
| `/hr/attendance/operations` | AttendanceOperationsPage | ✅ |
| `/hr/requests` | RequestsPage | ✅ P0 Core |
| `/hr/performance` | PerformancePage | ✅ P0 Core |
| `/hr/recruitment` | RecruitmentPage | 🟡 P1 |
| `/hr/onboarding` | OnboardingPage | 🟡 P1 |
| `/hr/reports` | ReportsPage | ✅ |
| `/hr/learning` | LearningPage | 🔴 إخفاء |
| `/hr/documents/studio` | DocumentStudioPage | 🔴 إخفاء |
| `/hr/lifecycle` | LifecycleOperationsPage | 🔴 إخفاء |
| `/hr/official-feed` | OfficialFeedPage | ✅ |
| `/hr/notifications` | NotificationsPage | ✅ |

#### Admin Workspace (`/admin`)

| Route | الصفحة | الحالة V17 |
|---|---|---|
| `/admin` | DashboardPage (admin) | ✅ |
| `/admin/actions` | ActionCenterPage | ✅ |
| `/admin/live-location` | LiveLocationPage | ✅ — تنظيف فيديو |
| `/admin/live-location/monitoring` | ExecutiveMonitoringPage | ✅ |
| `/admin/official-feed` | OfficialFeedPage | ✅ |
| `/admin/organization` | OrganizationPage | ✅ |
| `/admin/performance/cycles` | KpiCyclesPage | ✅ |
| `/admin/disputes` | DisputesPage | ✅ |
| `/admin/lifecycle` | LifecycleOperationsPage | 🔴 إخفاء |
| `/admin/access` | AccessPage | ✅ |
| `/admin/settings` | SystemPage | ✅ |
| `/admin/governance` | ReleaseGovernancePage | 🔴 إخفاء |
| `/admin/documents/studio` | DocumentStudioPage | 🔴 إخفاء |
| `/admin/reports/scheduler` | ReportSchedulerPage | 🟡 مراجعة |
| `/admin/enterprise` | EnterpriseManagementPage | 🟡 مراجعة |
| `/admin/operations` | OperationsCenterPage | 🟡 مراجعة |
| `/admin/helpdesk` | ServiceDeskPage | 🔴 إخفاء |
| `/admin/people-finance` | PeopleFinancePage | 🔴 إخفاء (payroll ممنوع) |
| `/admin/audit-security` | AuditSecurityPage | ✅ |
| `/admin/integrations` | IntegrationsJobsPage | 🟡 مراجعة |
| `/admin/notifications` | NotificationsPage | ✅ |

#### Committee Workspace (`/committee`)

| Route | الصفحة | الحالة V17 |
|---|---|---|
| `/committee` | DisputesPage | ✅ |
| `/committee/disputes` | DisputesPage | ✅ |
| `/committee/notifications` | NotificationsPage | ✅ |

### 3.2 بقايا الفيديو في Web

| الملف | المشكلة |
|---|---|
| `LiveLocationResultCard.tsx` | فيديو تشغيل + legal hold + عرض — كامل |
| `useControlCenters.ts` (implied) | `useLiveLocationVideoUrl` hook |
| `domainMocks.ts:235` | feature flag `live_location_video` |

---

## 4. Edge Functions — جرد

| الدالة | الغرض | فيديو؟ | الإجراء |
|---|---|---|---|
| `admin-create-employee` | إنشاء موظف جديد | لا | ✅ |
| `admin-resend-invite` | إعادة إرسال دعوة | لا | ✅ |
| `identifier-sign-in` | تسجيل دخول بالمعرف | لا | ✅ |
| `integration-outbox-worker` | معالجة صندوق التكامل | لا | ✅ |
| `notification-dispatcher` | إرسال FCM | لا | ✅ |
| `passkey-register` | تسجيل Passkey | لا | ✅ |
| `retention-cleanup` | تنظيف الاحتفاظ | لا | ✅ |
| `scheduled-report-runner` | تقارير مجدولة | لا | ✅ |
| `verify-attendance-punch` | تحقق بصمة حضور | لا | ✅ |
| `webauthn-challenge` | تحدي WebAuthn | لا | ✅ |
| `live-location-map-url` | توقيع رابط خريطة | لا | ✅ |
| **`live-location-video-url`** | **توقيع رابط فيديو** | **نعم** | 🔴 **إلغاء/إزالة** |

---

## 5. Shared Contracts — جرد

| الملف | المحتوى |
|---|---|
| `access.ts` | Zod schemas للوصول والصلاحيات |
| `adminOperations.ts` | عمليات الإدارة |
| `advancedOperations.ts` | عمليات متقدمة |
| `employee.ts` | بيانات الموظف |
| `enterpriseManagement.ts` | إدارة المؤسسة |
| `enterpriseOperations.ts` | عمليات المؤسسة |
| `liveLocation.ts` | الموقع المباشر |
| `management.ts` | الإدارة العامة |
| `operations.ts` | العمليات |
| `releaseGovernance.ts` | حوكمة الإصدار |
| `index.ts` | تصدير مركزي |

---

## 6. أمان — ملخص

| البند | الحالة |
|---|---|
| `USING (true)` على جداول حساسة | ✅ **نظيف — صفر** |
| Service Role في Flutter/React | ✅ **نظيف — صفر** |
| Secrets في Git | ✅ **محمي** (`.gitignore` يغطي كل الأنماط) |
| SECURITY DEFINER بدون search_path | ⚠️ **يحتاج تدقيق** — 33 occurrence في 18 ملف |
| `staging_generated_secrets.local.txt` | ✅ في `.gitignore` |

---

## 7. Tests — ملخص

- **51 ملف pgTAP** (0001–0051) يغطون:
  - Core security, foundation, workspaces, management, live location
  - KPI, attendance, requests, passkey, notifications, admin ops
  - Leave, decisions, disputes, enterprise, retention, privacy
  - Release, identifier login, persona RLS, recruitment
  - Observability, official KPI, work assignments, atomic attendance
  - Employee archive, monthly statement, provision employee
- **Flutter tests**: `mobile_models_test.dart` (278 سطر)
- **Web tests**: `PasswordSetupPage.test.tsx`, `WorkspaceSearch.test.tsx`, `ThemeToggle.test.tsx`, `UserAvatar.test.tsx`, `AppErrorBoundary.test.tsx`
- **Contract tests**: 10 ملفات `.test.ts` في shared-contracts

---

## 8. ⚡ خطة التنفيذ — أولويات P0 الفورية

### الخطوة 1: إخفاء/حذف الصفحات الثانوية (V17 §31 بند 1)

**Flutter — حذف/إخفاء:**
1. حذف `video_verification_page.dart` بالكامل
2. إخفاء `mobile_privacy_page.dart` (إزالة من الـ navigation)
3. إخفاء `mobile_learning_page.dart`
4. إخفاء `mobile_service_portal_page.dart`
5. إخفاء `executive_risk_center_page.dart`
6. تنظيف بقايا الفيديو من 4 ملفات

**Web — إخفاء Routes:**
1. `/hr/learning` — LearningPage
2. `/hr/documents/studio` — DocumentStudioPage
3. `/hr/lifecycle` — LifecycleOperationsPage
4. `/admin/lifecycle` — LifecycleOperationsPage
5. `/admin/governance` — ReleaseGovernancePage
6. `/admin/documents/studio` — DocumentStudioPage
7. `/admin/helpdesk` — ServiceDeskPage
8. `/admin/people-finance` — PeopleFinancePage (payroll ممنوع)
9. تنظيف فيديو من `LiveLocationResultCard.tsx`

**Edge Functions:**
1. إلغاء `live-location-video-url` function

### الخطوة 2: تنظيف بقايا الفيديو بالكامل (V17 §9)

### الخطوة 3-9: P0 Core Features حسب V17 §29

---

*هذا المستند هو نتيجة Phase 0 Audit. التنفيذ يبدأ فوراً بالخطوة 1.*
