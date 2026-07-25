# SHARED_CONTEXT.md — V17 Discovery Findings

> آخر تحديث: 2026-07-25

## المستودع

| البعد | القيمة |
|---|---|
| الفرع | `codex/v17-master-plan` |
| Baseline tag | `v17-baseline-20260725` |
| Supabase ref | `ujzzvqsodyhnnnpkoaml` |
| Firebase project | `ahla-shabab` |
| Package name | `org.ahlashabab.ahla_shabab_management_os` |
| Web URL | `https://ahla-shabab-management-os.vercel.app` |
| Migrations | 129 files (0001–0129) |
| pgTAP tests | 52 files |
| Edge Functions | 12 (1 stub 410) |
| Flutter version | 0.11.1+12, Dart ≥3.8 |
| Web stack | React 19 + Vite + Tailwind + TanStack Query |

---

## 1. Flutter App — Current Architecture

### Workspaces (5)

| Workspace | File | Priority | Nav tabs |
|---|---|---|---|
| Executive | `executive_workspace.dart` | 1 (highest) | الرئيسية، الوارد، الموقع، التقارير، الحوكمة |
| Field Operations | `operations_workspace.dart` | 2 | يومي، الطلبات، اللجنة، KPI، التشغيل |
| Manager | `manager_workspace.dart` | 3 | يومي، فريقي، الطلبات، KPI، التشغيل |
| Committee | `committee_workspace.dart` | 4 | قضايا اللجنة |
| Employee | `employee_workspace.dart` | 5 (lowest) | يومي، الحضور، طلباتي، KPI، حسابي |

**Resolution:** `app_gate.dart → _mobileWorkspace()` uses priority: executive > fieldOperations > manager > committee > employee.

### Pages (42 files in `mobile_pages/`)

**Core (keep & fix):**
- `employee_home_page.dart` — hero card + summary metrics + quick actions
- `mobile_attendance_page.dart` — check-in/out with GPS + biometric
- `mobile_self_service_page.dart` — 6 request types (leave, mission, convoy, late, early, correction)
- `mobile_kpi_page.dart` — KPI evaluations list with stage filter
- `kpi_evaluation_detail_page.dart` — KPI form (self/manager/HR scoring)
- `mobile_profile_page.dart` — account info, biometric status, device info
- `mobile_requests_page.dart` — request decision center for managers
- `mobile_disputes_page.dart` — complaint submission + viewing

**Executive:**
- `executive_home_page.dart`, `executive_brief_page.dart`, `executive_attendance_tab.dart`
- `executive_people_page.dart`, `executive_location_page.dart`
- `executive_disputes_page.dart`, `executive_decisions_page.dart`
- `executive_reports_page.dart`, `executive_employee_summary_page.dart`

**To HIDE per V17 §4.2:**
- `mobile_learning_page.dart` — تدريب (DELETED from git)
- `mobile_privacy_page.dart` — خصوصية (DELETED from git)
- `mobile_service_portal_page.dart` — مكتب خدمات (DELETED from git)
- Risk/Governance panels in executive workspace

**Still referenced but need removal from navigation:**
- Documents/assets/offboarding/payroll panels in profile/self-service
- `executive_risk_center_page.dart`, `executive_governance_page.dart`

### Data Layer (10 files in `mobile_data/`)

| File | Purpose |
|---|---|
| `mobile_models.dart` | Core DTOs: EmployeeHomeSummary, ManagerDashboard, MobileRequest, etc. |
| `mobile_providers.dart` | Riverpod providers: RPC calls, commands, attendance, location |
| `mobile_operations_models.dart` | Operations-specific DTOs |
| `mobile_operations_providers.dart` | Operations providers |
| `mobile_executive_insights_models.dart` | Executive DTOs |
| `mobile_executive_insights_providers.dart` | Executive providers |
| `location_service.dart` | GPS + geolocator |
| `passkey_attendance_service.dart` | WebAuthn attendance punch |
| `push_service.dart` | FCM + local notifications |
| `release_governance.dart` | App version check + device registration |

### Core Layer (12 files in `core/`)

- `app_config.dart` — dart-define env vars
- `secure_session_storage.dart` — flutter_secure_storage for Supabase session
- `app_theme.dart` — Material 3 theme with design tokens
- `connectivity_service.dart` — online/offline detection
- `brand_logo.dart`, `app_avatar.dart` — shared UI widgets

---

## 2. Web Admin — Current Architecture

### Workspaces (3)

| Workspace | Path | Permission Guard |
|---|---|---|
| HR | `/hr` | `WorkspaceGuard("hr")` |
| Main Admin | `/admin` | `WorkspaceGuard("main_admin")` |
| Committee | `/committee` | `WorkspaceGuard("committee")` |

### Routes (App.tsx)

**HR (`/hr`):** dashboard, employees (CRUD), attendance (+operations), requests, performance, recruitment, onboarding, reports, official-feed, notifications.

**Main Admin (`/admin`):** dashboard, actions, live-location (+monitoring), official-feed, organization, KPI cycles, disputes, access, settings, report-scheduler, enterprise, operations, audit-security, integrations, notifications.

**Committee (`/committee`):** disputes, notifications.

**Hidden per V17 §4.2 comments:** learning, documents, lifecycle (HR); lifecycle, governance, documents, helpdesk, payroll (Admin).

### Feature Structure

```
src/features/
  auth/            — login, password setup, mobile redirect, web release
  employees/       — list, create, detail
  attendance/      — attendance page, monthly statement
  requests/        — request management
  performance/     — KPI dashboard
  management/      — organization, access, system, reports, live-location, etc.
  advanced/        — attendance ops, KPI cycles, disputes, lifecycle ops
  actions/         — action center
  communications/  — official feed
  notifications/   — notification center
  workspaces/      — shell, dashboard, access helpers
  mock/            — domain mocks for dev mode
```

---

## 3. Supabase Backend — Current State

### Scale
- **237 tables**, **~200 RPC functions**, **~568 RLS policies**, **~130 triggers**
- **4 monitoring views**, **0 custom enums** (CHECK constraints only)
- **12 Edge Functions** (1 returns 410 Gone — `live-location-video-url`)

### KPI System (Migration 0109)

**CURRENT flow:** `self → manager_review → hr_review → manager_final → finalized → closed → archived`

The `advance_kpi_stage` function routes:
- `self` → `manager_review` (SUBMITTED_TO_DIRECT_MANAGER)
- `manager_review` → `hr_review` (HR_REVIEW)
- `hr_review` → `manager_final` (RETURNED_TO_MANAGER_FOR_FINAL_APPROVAL)
- `manager_final` → `finalized` (INCLUDED_IN_MONTHLY_REPORT)

**V17 REQUIRED flow:** `self → hr_review → manager_review/final → finalized`
- Employee submits to HR first
- HR scores attendance/prayer/halaqa then sends to manager
- Manager scores targets/competency/behavior/initiatives then approves

**Executive Director exclusion:** Already implemented in `create_kpi_cycle_admin` — excludes users with `executive` or `executive-director` roles.

### Complaints System (Migrations 0008, 0030, 0059, 0064)

Tables: `dispute_cases`, `dispute_parties`, `dispute_evidence`, `dispute_statements`, `dispute_sessions`, `dispute_decisions`, `dispute_actions`, `dispute_settlements`, `dispute_appeals`.

**GAP:** V17 requires `proposed_administrative_action`, `executive_decision`, `executive_decision_reason`, `approved_administrative_action`, `executed_at`, `executed_by`, `execution_notes` — these fields do NOT exist in the current schema.

### Location System

- Video permanently disabled (V17 §9 ✅)
- `newLiveLocationRequestModeSchema` restricts to `'snapshot'` only ✅
- FCM via native `UrgentLocationMessagingService` ✅
- Channel `urgent_location_v6` with MAX importance ✅

### Notification System

- `notification_outbox` table with `notification-dispatcher` Edge Function
- FCM native path for urgent location
- Missing: attendance reminders, KPI notifications, complaint notifications, official post notifications

---

## 4. Android/Firebase — Current State

### Permissions (Active)
- `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `INTERNET`, `POST_NOTIFICATIONS`
- `USE_FULL_SCREEN_INTENT`, `VIBRATE`, `WAKE_LOCK`
- `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`
- `MODIFY_AUDIO_SETTINGS` — **V17 FLAG: possibly vestigial from video**

### Removed Permissions
- `RECORD_AUDIO` — explicitly removed (V17 video removal) ✅
- `READ_EXTERNAL_STORAGE`, `WRITE_EXTERNAL_STORAGE` — blocked ✅
- Ad ID permissions — blocked ✅

### Firebase
- Project: `ahla-shabab` (379745613572)
- FCM: native `UrgentLocationMessagingService` + `UrgentAlarmService`
- Analytics: deactivated ✅

---

## 5. V17 Cleanup Items (from Android/Firebase scan)

| Item | Location | Action |
|---|---|---|
| `MODIFY_AUDIO_SETTINGS` | AndroidManifest.xml | Verify if needed for alarm, remove if not |
| `camera=(self)` in Permissions-Policy | vercel.json:31 | Change to `camera=()` |
| `live-location-video-url` edge fn | supabase/functions/ | 410 stub, consider full removal |
| Video schemas in shared-contracts | liveLocation.ts | Kept for historical data, intentional |

---

## 6. Critical Dependencies

```
Supabase Auth → user_profiles → employees → employee_assignments
                                          → reporting_lines / manager_relations
                                          → departments → teams
                                          → legal_entities
employees → devices (device registration)
         → attendance_records (check-in/out)
         → leave_requests, missions, convoys (requests)
         → kpi_evaluations (KPI)
         → dispute_cases (complaints)
         → notification_outbox (notifications)
         → live_location_requests (location)
```
