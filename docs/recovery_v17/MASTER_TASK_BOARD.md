# MASTER_TASK_BOARD.md — V17 Gap Analysis & Execution Plan

> آخر تحديث: 2026-07-25  
> المرجع الوحيد: `AHLA_SHABAB_FINAL_ZERO_AMBIGUITY_MASTER_PLAN_V17.md`  
> الحالة: Wave 0 ✅ → Wave 2/3 contracts+migrations ✅ (mig 0129-0139, tests 0052-0059) → Wave 4.5 page-hide ✅ → Wave 6 KPI ✅ → Wave 7 dispute backend ✅ → Wave 8.2 location ✅ → Wave 4 UI ✅ (device/attendance/requests/profile + mig 0139 request-return + mig 0140 attendance-p_days + test 0060) → **Wave 5 manager + Wave 7 UI + Wave 8 UI NEXT**

---

## Legend

- ✅ = Done / Already exists and verified
- 🟡 = Partially done — exists but needs V17 alignment
- 🔲 = Not started
- P0 = Phase 0 (must ship first)
- P1 = Phase 1 (ship after P0)
- `[mig]` = needs new migration
- `[rpc]` = needs RPC change
- `[edge]` = needs Edge Function
- `[web]` = web admin change
- `[mob]` = mobile Flutter change
- `[test]` = needs pgTAP / vitest / flutter test

---

## Wave 0 — Audit & Baseline ✅

| # | Task | Status | Evidence |
|---|------|--------|----------|
| 0.1 | Git branch + baseline tag | ✅ | `codex/v17-master-plan`, tag `v17-baseline-20260725` |
| 0.2 | Supabase inventory (237 tables, ~200 RPCs, ~568 RLS, 52 tests) | ✅ | Discovery scan |
| 0.3 | Web inventory (3 workspaces, 33+ pages, 21 permissions) | ✅ | `App.tsx` full read |
| 0.4 | Flutter inventory (5 workspaces, 42 pages, all functional) | ✅ | Agent report |
| 0.5 | Android/Firebase/Legacy scan | ✅ | Agent report |
| 0.6 | Video/camera references audit | ✅ | Already cleaned per V17 §9 |
| 0.7 | Create recovery_v17/ docs | ✅ | 16 docs + this board |
| 0.8 | Migration numbering check | ✅ | 0001–0129, no duplicates |
| 0.9 | KPI flow analysis (mig 0109 full read) | ✅ | Current: self→manager→HR; V17: self→HR→manager |
| 0.10 | Dispute admin action gap confirmed | ✅ | grep: 0 results for `proposed_administrative_action` |

---

## Wave 2 — Contracts & Foundations

### 2.1 Shared Contract Schemas

| # | Task | V17 Ref | Status | Files |
|---|---|---|---|---|
| 2.1.1 | KPI stage enum: reorder to `self→hr_review→manager_review→manager_final→finalized→closed→archived` | §10 | ✅ | `packages/shared-contracts/src/operations.ts` |
| 2.1.2 | KPI criteria schema: 7 criteria with weights (target 40, competency 20, attendance 20, behavior 5, prayer 5, halaqa 5, initiatives 5) | §10.2 | ✅ | mig 0130 |
| 2.1.3 | Dispute admin-action schema: `proposed_action`, `executive_decision`, `decision_reason`, `approved_action`, `executed_at/by/notes` | §14 | ✅ | `packages/shared-contracts/src/disputes.ts` |
| 2.1.4 | Request type enum: exactly 6 types (leave, mission, convoy, late_permit, early_permit, attendance_correction) | §8 | ✅ | `packages/shared-contracts/src/requests.ts` |
| 2.1.5 | Location request mode: `snapshot` only (no `video`) | §11 | ✅ | `packages/shared-contracts/src/liveLocation.ts` |
| 2.1.6 | Attendance config schema: check-in 10:00, check-out 18:00, grace periods | §7 | ✅ | `packages/shared-contracts/src/attendanceConfig.ts` |
| 2.1.7 | Official holiday schema: name, date, scope (all/dept/entity), exclusions | §1.7 | ✅ | `packages/shared-contracts/src/holidays.ts` |
| 2.1.8 | Post publishing permission schema: who can publish (main_admin, hr_web, executive_mobile) | §18 | ✅ | `packages/shared-contracts/src/postPublishing.ts` |
| 2.1.9 | Word count constraint: 3–300 per field | §1.3 | ✅ | `packages/shared-contracts/src/validation.ts` |

### 2.2 Permission Catalog

| # | Task | V17 Ref | Status | Files |
|---|---|---|---|---|
| 2.2.1 | Verify permission seeds match V17 role matrix | §25.4 | ✅ | mig 0121 seeds 5-tier matrix: executive (13 perms), executive-secretary (10), hr-manager (25), direct-manager (8) + pre-existing admin/employee; 20 job titles + 22 departments |
| 2.2.2 | Add `kpi.hr_review` permission for HR to score compliance metrics | §10 | ✅ | mig 0007 (created), 0058 (RLS), 0109 (`current_is_hr_reviewer()`), 0121 (seeded to hr-manager), 0130 (V17 hr_review stage gate) |
| 2.2.3 | Add `disputes.admin_action.propose` for executive secretary | §14 | ✅ | mig 0131 |
| 2.2.4 | Add `disputes.admin_action.decide` for executive director | §14 | ✅ | mig 0131 |
| 2.2.5 | Add `disputes.admin_action.execute` for HR | §14 | ✅ | mig 0131 |
| 2.2.6 | Add `posts.publish` permission (main_admin, hr, executive) | §18 | ✅ | mig 0133: permission created + granted to 3 roles + wired into announcement RLS policies |
| 2.2.7 | Add `holidays.manage` permission for HR | §1.7 | ✅ | mig 0132 |
| 2.2.8 | Operations personal requests → route to executive director (not self-approve) | §1.2 | ✅ | mig 0134: resolve_request_approver routes ops to executive, self-approval prevention (line 122) |

---

## Wave 3 — Security & Data Layer

### 3.1 Database Migrations (next = 0130+)

| # | Task | V17 Ref | Priority | Status | Depends On |
|---|---|---|---|---|---|
| 3.1.1 | **KPI flow reorder**: change `advance_kpi_stage` routing — `self→hr_review` instead of `self→manager_review` | §10 | P0 | ✅ | mig 0130 |
| 3.1.2 | **KPI criteria weights**: update `kpi_criteria` seed to 7 criteria with V17 weights, assign owner (HR vs Manager per criterion) | §10.2 | P0 | ✅ | mig 0130 |
| 3.1.3 | **KPI editable stages**: update `get_kpi_evaluation_form` so HR fields editable at `hr_review`, manager fields at `manager_review`/`manager_final` | §10 | P0 | ✅ | mig 0130 |
| 3.1.4 | **KPI stage order array**: update trigger validation to `['self','hr_review','manager_review','manager_final','finalized','closed','archived']` | §10 | P0 | ✅ | mig 0130 |
| 3.1.5 | **Dispute admin action fields**: add columns to `dispute_cases`: `proposed_administrative_action`, `executive_decision`, `executive_decision_reason`, `approved_administrative_action`, `executed_at`, `executed_by`, `execution_notes` | §14 | P1 | ✅ | mig 0131 |
| 3.1.6 | **Dispute admin action RPCs**: `propose_admin_action(case_id, action)`, `decide_admin_action(case_id, decision, reason)`, `execute_admin_action(case_id, notes)` | §14 | P1 | ✅ | mig 0131 |
| 3.1.7 | **Official holidays table**: `official_holidays(id, name, date, scope, exclusions, created_by)` | §1.7 | P1 | ✅ | mig 0132, web CRUD page done |
| 3.1.8 | **Attendance config table**: system settings for check-in/out times, grace period, reminder schedule | §7 | P0 | ✅ (shifts table + mig 0057) | existing |
| 3.1.9 | **Operations request routing**: update request approval logic so operations personal requests go to executive director | §1.2 | P0 | ✅ | mig 0134 |
| 3.1.10 | **Post publishing RLS**: restrict `official_posts` INSERT to main_admin + hr + executive roles | §18 | P1 | ✅ | mig 0133 |
| 3.1.11 | **Word count CHECK constraints**: 3–300 character range on text fields (KPI comments, request reasons, dispute descriptions) | §1.3 | P1 | ✅ | mig 0135 |

### 3.2 RLS & Security

| # | Task | V17 Ref | Status | Files |
|---|---|---|---|---|
| 3.2.1 | RLS on `dispute_cases` admin action columns: secretary propose, director decide, HR execute | §14 | ✅ | mig 0131 (SECURITY DEFINER RPCs) |
| 3.2.2 | RLS on `official_holidays`: HR manage, all read | §1.7 | ✅ | mig 0132 |
| 3.2.3 | Verify `kpi_evaluations` RLS allows HR to edit at `hr_review` stage | §10 | ✅ | SECURITY DEFINER RPCs bypass RLS; role-gated on hr-manager/hr-specialist |
| 3.2.4 | Verify attendance RLS excludes executive director from mandatory punch | §7 | ✅ | `get_my_access_context()` returns `attendanceRequired:false` for executives (mig 0013 line 120); mobile checks flag |

### 3.3 Tests

| # | Task | V17 Ref | Status |
|---|---|---|---|
| 3.3.1 | pgTAP: KPI V17 flow order (self→HR→manager→finalized) | §10 | ✅ | test 0036 rewritten |
| 3.3.2 | pgTAP: KPI executive exclusion still works | §10 | ✅ | test 0036 (16 assertions) |
| 3.3.3 | pgTAP: dispute admin action lifecycle | §14 | ✅ | test 0054 (22 assertions) |
| 3.3.4 | pgTAP: operations request routes to executive | §1.2 | ✅ | test 0057 |
| 3.3.5 | pgTAP: official holiday CRUD + scope | §1.7 | ✅ | test 0055 (20 assertions) |
| 3.3.6 | pgTAP: post publishing permission enforcement | §18 | ✅ | test 0056 |
| 3.3.7 | pgTAP: word count constraint enforcement | §1.3 | ✅ | test 0058 |

---

## Wave 4 — Core Employee Features (P0)

### 4.1 Device Registration & Biometric (§6)

| # | Task | Status | Files |
|---|---|---|---|
| 4.1.1 | Verify device registration flow (hardware key, NOT Samsung Pass) | ✅ | Two paths: (1) Passkey/WebAuthn via `registerPasskey()` + `passkeyAttendanceServiceProvider`, (2) Local biometric via `registerLocalBiometricDevice()` |
| 4.1.2 | Verify local biometric prompt before attendance punch | ✅ | `punchAttendanceLocal()` checks canCheckBiometrics + `localAuth.authenticate(biometricOnly:true, stickyAuth:true)` before every punch |
| 4.1.3 | Device info display in profile page | ✅ | `_DeviceSecuritySection` shows biometric support, registered PasskeyDevice list (label, status, trusted, deviceType, lastUsedAt), register/revoke actions |

### 4.2 Attendance (§7)

| # | Task | Status | Files |
|---|---|---|---|
| 4.2.1 | Check-in/out with GPS coordinates capture | ✅ | `mobile_attendance_page.dart` |
| 4.2.2 | Biometric verification before punch | 🟡 | `passkey_attendance_service.dart` |
| 4.2.3 | Show last 30 days history on attendance page | ✅ | `myAttendanceHistoryProvider` (p_limit:100, p_days:30); mig 0140 adds `p_days` param to `get_my_attendance_history`; test 0060 (14 assertions) |
| 4.2.4 | Monthly attendance statement page | ✅ | `monthly_attendance_statement_page.dart` |
| 4.2.5 | Executive director excluded from mandatory attendance | ✅ | Server-driven: `AccessContext.attendancePolicy.selfPunchEnabled` gates attendance button; executive record sets flags to false |
| 4.2.6 | Attendance reminder notifications (9:45/10:00/17:45/18:00) | 🔲 | `[edge]` or cron |

### 4.3 Request Center (§8)

| # | Task | Status | Files |
|---|---|---|---|
| 4.3.1 | 6 request types: leave, mission, convoy, late_permit, early_permit, attendance_correction | ✅ | `mobile_self_service_page.dart`: all 6 types with type-specific forms + `_NewRequestSheet` + `_ForgotPunchSheet` |
| 4.3.2 | Each request has: type, dates, reason (3-300 chars), attachments | ✅ | `_NewRequestSheet` renders type-specific form fields with validation |
| 4.3.3 | Manager sees pending requests with approve/reject/return | ✅ | `MobileRequestsPage(allowDecision:true)` + `MobileRequestDetailPage` return button; mig 0139 adds 'returned' status + decide_request 'return' action (with comment enforcement); test 0060 |
| 4.3.4 | Employee sees own request history with status | ✅ | Previous requests section with status filters (all/pending/approved/rejected) + leave balances cards |

### 4.4 Employee Profile (§13)

| # | Task | Status | Files |
|---|---|---|---|
| 4.4.1 | Show: name, photo, job title, department, employee code, join date | ✅ | `_Header` (fullNameAr, jobTitle, employeeCode, status, photo) + `_InfoSection` (department, team, position, branch, hireDate) |
| 4.4.2 | Show: device info, biometric status, app version | ✅ | `_DeviceSecuritySection` shows biometric support, registered devices with metadata, register/revoke actions |
| 4.4.3 | Show: direct manager name | ✅ | `mobile_profile_page.dart` (via `get_my_mobile_profile()` → `managerName`) |
| 4.4.4 | Remove: documents, custody, contract end, payroll panels | ✅ | `mobile_profile_page.dart` |

### 4.5 Page Cleanup (§4.2) — INDEPENDENT, can start NOW

| # | Task | Status | Files |
|---|---|---|---|
| 4.5.1 | Remove privacy page from all navigation | ✅ (file deleted) | verify nav refs |
| 4.5.2 | Remove learning/training page from all navigation | ✅ (file deleted) | verify nav refs |
| 4.5.3 | Remove service portal page from all navigation | ✅ (file deleted) | verify nav refs |
| 4.5.4 | Hide risk center from executive quick links | ✅ | `executive_home_page.dart` |
| 4.5.5 | Hide governance from executive "More" menu + Reports duplicate | ✅ | `workspace_scaffold.dart` |
| 4.5.6 | Remove documents/custody/payroll panels from self-service | ✅ (never existed) | `mobile_self_service_page.dart` |
| 4.5.7 | Remove offboarding/contract-end from profile | ✅ | `mobile_profile_page.dart` |
| 4.5.8 | Web: verify hidden routes stay hidden (learning, documents, lifecycle, governance, helpdesk, payroll) | ✅ (routes removed + dead imports cleaned) | `App.tsx` |

---

## Wave 5 — Manager & Operations (P0)

### 5.1 Employee-Manager Linking (§9)

| # | Task | Status | Files |
|---|---|---|---|
| 5.1.1 | Verify `reporting_lines` / `manager_relations` tables work correctly | 🟡 | existing migrations |
| 5.1.2 | Manager sees only their direct reports | ✅ | `mobileTeamProvider` calls server-side RPC `get_my_mobile_team`; scoping enforced by RPC |
| 5.1.3 | `kpi_is_direct_manager` function works with V17 flow | 🟡 | mig 0109 |

### 5.2 Manager Dashboard

| # | Task | Status | Files |
|---|---|---|---|
| 5.2.1 | Team attendance summary (today) | 🟡 | `manager_home_page.dart` |
| 5.2.2 | Pending requests count + list | 🟡 | `mobile_requests_page.dart` |
| 5.2.3 | Pending KPI evaluations (manager_review stage in V17 flow) | ✅ | `ManagerDashboardSummary.pendingKpi` from `get_manager_dashboard` RPC; team page shows per-employee KPI stage |
| 5.2.4 | Quick approve/reject actions | 🟡 | `mobile_requests_page.dart` |

### 5.3 Operations Workspace

| # | Task | Status | Files |
|---|---|---|---|
| 5.3.1 | Operations personal requests route to executive director | ✅ | mig 0134 (RPC) + `OperationsWorkspace` includes `MobileRequestsPage(allowDecision:true)`; routing handled server-side by `decide_request` RPC |
| 5.3.2 | Operations daily view | 🟡 | `operations_workspace.dart` |

---

## Wave 6 — KPI System (P0) ⚠️ CRITICAL

### Current vs V17 Flow Diagram

```
CURRENT (mig 0109, line 269–273):
  Employee (self) ──→ Manager (manager_review) ──→ HR (hr_review) ──→ Manager (manager_final) ──→ finalized

V17 REQUIRED:
  Employee (self) ──→ HR (hr_review) ──→ Manager (manager_review) ──→ Manager (manager_final) ──→ finalized
                      │                   │
                      │ HR scores:        │ Manager scores:
                      │ • attendance 20   │ • target 40
                      │ • prayer 5        │ • competency 20
                      │ • halaqa 5        │ • behavior 5
                      │                   │ • initiatives 5
                      └───────────────────┘
                            Total = 100
```

### 6.1 Backend Flow Change

| # | Task | Status | Key Code Reference |
|---|---|---|---|
| 6.1.1 | New migration: rewrite `advance_kpi_stage` routing (line 269: `self→hr_review`, line 270: `hr_review→manager_review`) | ✅ | mig 0130 |
| 6.1.2 | New migration: update stage order validation array | ✅ | mig 0130 |
| 6.1.3 | New migration: update `get_kpi_evaluation_form` editability per stage | ✅ | mig 0130 |
| 6.1.4 | New migration: update `save_kpi_compliance_metric` stage check (currently checks `<>'hr_review'`) | ✅ | mig 0130 |
| 6.1.5 | New migration: update KPI criteria seed (7 criteria, weights, HR vs Manager owner) | ✅ | mig 0130 |
| 6.1.6 | Verify: executive exclusion still works in `create_kpi_cycle_admin` | ✅ | mig 0130 preserves |
| 6.1.7 | pgTAP tests for full V17 KPI flow | ✅ | test 0053 (18 assertions) |

### 6.2 Mobile KPI

| # | Task | Status | Files |
|---|---|---|---|
| 6.2.1 | Update filter labels: reorder stage pills to match V17 flow | ✅ | `mobile_kpi_page.dart` |
| 6.2.2 | Update `_allowedAction()`: add hr_review action for HR users | ✅ | `mobile_kpi_page.dart` |
| 6.2.3 | Update KPI detail form: HR fields editable at hr_review, manager fields at manager_review | ✅ | `kpi_evaluation_detail_page.dart` |
| 6.2.4 | Update stage labels in employee home summary | ✅ | `employee_home_page.dart` |
| 6.2.5 | "إرسال إلى HR" button label (not "إرسال إلى المدير") at self stage | ✅ | `kpi_evaluation_detail_page.dart` |

### 6.3 Web KPI

| # | Task | Status | Files |
|---|---|---|---|
| 6.3.1 | Update KPI cycles page to show V17 flow stages | ✅ | `KpiCyclesPage.tsx` |
| 6.3.2 | Update performance page to reflect V17 flow | ✅ | `PerformancePage.tsx`, `KpiEvaluationEditor.tsx` |

---

## Wave 7 — Complaints & Administrative Actions (P1)

### 7.1 Backend

| # | Task | Status | Depends On |
|---|---|---|---|
| 7.1.1 | Migration: add admin action columns to `dispute_cases` | ✅ | mig 0131 |
| 7.1.2 | Migration: create admin action RPCs (propose/decide/execute) | ✅ | mig 0131 |
| 7.1.3 | Migration: RLS for admin action columns | ✅ | mig 0131 (SECURITY DEFINER) |
| 7.1.4 | pgTAP: admin action lifecycle tests | ✅ | test 0054 |

### 7.2 Mobile Complaints

| # | Task | Status | Files |
|---|---|---|---|
| 7.2.1 | Employee: submit complaint with description (3-300 chars) + evidence | ✅ | `_NewDisputeForm`: 12 case types, priority, title/description validation, respondent/witness picker, image attachments (up to 5), truth+confidentiality checkboxes |
| 7.2.2 | Executive: view dispute with proposed admin action | 🟡 | `executive_disputes_page.dart`: UI structure exists (escalated/pending/historical categories) but approve button is a stub — never calls backend RPC |
| 7.2.3 | Executive: approve/reject/return admin action | 🟡 | `_showDecisionDialog` renders form but approve button only calls `Navigator.pop` + snackbar — decision text never sent to server. REMAINING: wire to backend RPC |

### 7.3 Web Complaints

| # | Task | Status | Files |
|---|---|---|---|
| 7.3.1 | Admin disputes: show admin action workflow status | ✅ | `DisputesPage.tsx` (304 lines): summary metrics, filterable case list, 12 case transition actions, committee formation, session scheduling, decision issuance (7 outcome types), action execution tracking |
| 7.3.2 | Secretary: propose admin action UI | ✅ | `DisputesPage.tsx`: committee notes with visibility control, settlement/apology recording, all via `useAdvancedOperations` mutation hooks |
| 7.3.3 | HR: execute approved admin action UI | ✅ | `DisputesPage.tsx`: action execution tracking with proof, appeal handling (accept/reject with resolution) |

---

## Wave 8 — Executive & Communications (P1)

### 8.1 Executive Daily Report (§12)

| # | Task | Status | Files |
|---|---|---|---|
| 8.1.1 | Summary metrics: attendance %, pending requests, active KPI count | 🟡 | `executive_home_page.dart` |
| 8.1.2 | Department-level attendance breakdown | 🟡 | `executive_attendance_tab.dart` |
| 8.1.3 | Pending disputes with admin action status | 🔲 | needs Wave 7 first |

### 8.2 Location Request (§11)

| # | Task | Status | Files |
|---|---|---|---|
| 8.2.1 | Snapshot-only mode (no video) | ✅ | contracts + providers |
| 8.2.2 | FCM delivery + alarm notification | ✅ | native Android services |
| 8.2.3 | Full-screen overlay on receive | ✅ | `location_incoming_overlay.dart` |
| 8.2.4 | Map display with coordinates | ✅ | `executive_location_page.dart` |

### 8.3 Official Posts (§18)

| # | Task | Status | Files |
|---|---|---|---|
| 8.3.1 | Publishing restricted to: main_admin (web), HR (web), executive (mobile) | ✅ | mig 0133 (permission+RLS+RPC); web `OfficialFeedPage` gates publish button via `hasPermission(comms.announcement.manage)`; mobile feed is read-only (no publish) |
| 8.3.2 | Post with text + optional image | 🟡 | `OfficialFeedPage`, `mobile_official_feed_page.dart` |
| 8.3.3 | All employees see posts (read-only in mobile) | 🟡 | existing |

### 8.4 Employee Photos (§19)

| # | Task | Status | Files |
|---|---|---|---|
| 8.4.1 | Show employee photo in: home hero, team lists, attendance, KPI, requests | 🔲 | multiple pages |
| 8.4.2 | Upload photo from profile page | 🟡 | `mobile_profile_page.dart` |

---

## Wave 9 — UI/UX & Performance (P1)

### 9.1 Theme & RTL (§20)

| # | Task | Status |
|---|---|---|
| 9.1.1 | Consistent RTL throughout all pages | 🟡 |
| 9.1.2 | Design tokens from `ahla_design_tokens` package | 🟡 |
| 9.1.3 | Loading/error/empty states on all pages | 🟡 |
| 9.1.4 | Skeleton loaders during data fetch | 🟡 |

### 9.2 Notification System (§17)

| # | Task | Status |
|---|---|---|
| 9.2.1 | Attendance reminders (9:45, 10:00, 17:45, 18:00) with exclusions | 🔲 |
| 9.2.2 | KPI stage change notifications | 🔲 |
| 9.2.3 | Request status change notifications | 🔲 |
| 9.2.4 | New complaint notifications | 🔲 |
| 9.2.5 | New official post notifications | 🔲 |
| 9.2.6 | Notification center page (mobile + web) | 🟡 |

### 9.3 Login & Password (§16)

| # | Task | Status |
|---|---|---|
| 9.3.1 | Login via email/phone/employee-code | ✅ |
| 9.3.2 | Password reset flow | ✅ |
| 9.3.3 | First-login password setup | ✅ |
| 9.3.4 | Web redirect from unauthenticated recovery URL | 🟡 |

### 9.4 Cleanup Items (from Android/Firebase scan)

| # | Task | Status | Files |
|---|---|---|---|
| 9.4.1 | Verify/remove `MODIFY_AUDIO_SETTINGS` if vestigial | ✅ | `AndroidManifest.xml` (tools:node=remove) |
| 9.4.2 | Change `camera=(self)` to `camera=()` in Permissions-Policy | ✅ | `vercel.json:31` |
| 9.4.3 | Consider full removal of `live-location-video-url` edge fn (currently 410 stub) | 🔲 | `supabase/functions/` |

---

## Wave 10 — Full Validation

| # | Task | Status |
|---|---|---|
| 10.1 | All pgTAP tests pass (existing 52 + new V17 tests) | 🔲 |
| 10.2 | All vitest tests pass (web + contracts) | 🔲 |
| 10.3 | All flutter tests pass | 🔲 |
| 10.4 | `npm run check:all` clean | 🔲 |
| 10.5 | Web production build succeeds | 🔲 |
| 10.6 | Flutter analyze clean (no fatal infos) | 🔲 |
| 10.7 | Manual smoke test: all 5 mobile workspace roles | 🔲 |
| 10.8 | Manual smoke test: all 3 web workspace roles | 🔲 |
| 10.9 | V17 acceptance criteria checklist from §33 (Appendix A) | 🔲 |

---

## Dependency Graph — Task Execution Order

```
Wave 2 (Contracts) — ALL INDEPENDENT, run in parallel
  ├─ 2.1.1 KPI stage enum ──────────────────────────┐
  ├─ 2.1.2 KPI criteria schema ─────────────────────┤
  ├─ 2.1.3 Dispute admin action schema ─────────────┤
  ├─ 2.1.6 Attendance config schema ────────────────┤
  ├─ 2.1.7 Holiday schema ─────────────────────────┤
  └─ 2.2.* Permission catalog ─────────────────────┤
                                                     │
Wave 3 (Data Layer) ◄───────────────────────────────┘
  ├─ 3.1.1–4 KPI flow mig (SINGLE migration) ──────┐
  ├─ 3.1.5–6 Dispute columns+RPCs mig ─────────────┤
  ├─ 3.1.7 Holidays table mig ─────────────────────┤
  ├─ 3.1.8 Attendance config mig ───────────────────┤
  ├─ 3.1.9 Ops request routing mig ────────────────┤
  └─ 3.3.* pgTAP tests ────────────────────────────┤
                                                     │
Wave 4–5 (UI: Employee + Manager) ◄────────────────┘
  ├─ 4.5.* Page cleanup ← INDEPENDENT, start NOW
  ├─ 4.2.* Attendance (mostly done)
  ├─ 4.3.* Request center (mostly done)
  ├─ 4.4.* Profile cleanup
  └─ 5.* Manager dashboard
                                                     │
Wave 6 (KPI UI) ◄──── depends on 3.1.1–3.1.4 ─────┘
  ├─ 6.2.* Mobile KPI updates
  └─ 6.3.* Web KPI updates
                                                     │
Wave 7 (Complaints) ◄── depends on 3.1.5–3.1.6 ────┘
  ├─ 7.2.* Mobile complaints
  └─ 7.3.* Web complaints
                                                     │
Wave 8–9 (Exec + UI/UX + Notifications) ◄──────────┘
                                                     │
Wave 10 (Validation) ◄─────────────────────────────┘
```

### Independent Tracks (can execute in parallel with anything)

1. **Page cleanup** (4.5.*) — no backend dependency, start immediately
2. **Profile cleanup** (4.4.4, 4.4.3) — UI-only removal of hidden panels
3. **Location system** (8.2.*) — already ✅ complete
4. **Login/auth** (9.3.*) — mostly ✅ complete
5. **Theme/RTL polish** (9.1.*) — independent UI work
6. **Cleanup items** (9.4.*) — Android/vercel fixes, independent

### Sequential Chains (must wait for dependencies)

1. **KPI chain**: contracts (2.1.1-2) → migration (3.1.1-4) → pgTAP (3.3.1) → mobile UI (6.2.*) → web UI (6.3.*)
2. **Complaints chain**: contracts (2.1.3) → migration (3.1.5-6) → pgTAP (3.3.3) → mobile UI (7.2.*) → web UI (7.3.*)
3. **Holidays chain**: contracts (2.1.7) → migration (3.1.7) → pgTAP (3.3.5) → web UI (HR route)
4. **Notifications chain**: attendance config (3.1.8) → notification RPCs → edge function → mobile integration (9.2.*)

---

## Files Created (Wave 3)

| File | Purpose | Status |
|---|---|---|
| `supabase/migrations/0130_v17_kpi_flow_reorder.sql` | KPI stage routing + criteria + form editability | ✅ |
| `supabase/migrations/0131_v17_dispute_admin_actions.sql` | Dispute administrative action columns + RPCs + RLS | ✅ |
| `supabase/migrations/0132_v17_official_holidays.sql` | Holidays table + RLS | ✅ |
| `supabase/migrations/0133_v17_post_publishing.sql` | Post publishing permission + RLS + RPC | ✅ |
| `supabase/migrations/0134_v17_request_types.sql` | Request types V17 alignment + operations routing | ✅ |
| `supabase/migrations/0135_v17_word_count_checks.sql` | Text field NOT VALID CHECK constraints | ✅ |
| `supabase/tests/0053_v17_kpi_flow.sql` | KPI V17 flow order tests (18 assertions) | ✅ |
| `supabase/tests/0054_v17_dispute_admin_actions.sql` | Dispute admin action lifecycle tests (22 assertions) | ✅ |
| `supabase/tests/0055_v17_official_holidays.sql` | Holiday CRUD + scope tests (20 assertions) | ✅ |
| `supabase/tests/0056_v17_post_publishing.sql` | Post publishing permission tests (16 assertions) | ✅ |
| `supabase/tests/0057_v17_request_types.sql` | Request types + operations routing tests (18 assertions) | ✅ |
| `supabase/tests/0058_v17_word_count_checks.sql` | Word count constraint tests (14 assertions) | ✅ |
| `apps/admin_web/src/features/holidays/useHolidays.ts` | Holiday CRUD hooks (TanStack Query) | ✅ |
| `apps/admin_web/src/features/holidays/OfficialHolidaysPage.tsx` | Full holidays admin page with create/edit/delete | ✅ |
| `apps/admin_web/src/features/holidays/useHolidays.ts` | Holidays CRUD hooks (TanStack Query) | ✅ |
| `apps/admin_web/src/features/holidays/OfficialHolidaysPage.tsx` | Holidays admin page (full CRUD + scope + metrics) | ✅ |
| `supabase/migrations/0139_v17_request_return_status.sql` | Add 'returned' to request status + decide_request 'return' decision | ✅ |

## Key Files to Modify

| File | Change | Wave |
|---|---|---|
| `mobile_kpi_page.dart:80-87` | Reorder filter stage pills | 6 |
| `mobile_kpi_page.dart:232-246` | Add hr_review action for HR users | 6 |
| `kpi_evaluation_detail_page.dart` | HR/Manager field editability per V17 stage | 6 |
| `employee_home_page.dart:278-287` | KPI stage labels reorder | 6 |
| `mobile_profile_page.dart` | Remove documents/custody/payroll, add manager name | 4 |
| `mobile_self_service_page.dart` | Remove hidden panels | 4 |
| `workspace_scaffold.dart` | Hide risk/governance from More menu | 4 |
| `mobile_providers.dart` | KPI provider updates for V17 flow | 6 |
| `mobile_models.dart` | KPI model updates if needed | 6 |
| `KpiCyclesPage.tsx` | V17 flow stage display | 6 |
| `DisputesPage.tsx` | Admin action workflow UI | 7 |
| `PerformancePage.tsx` | V17 flow reflection | 6 |
| `vercel.json:31` | `camera=(self)` → `camera=()` | 9 |
| `AndroidManifest.xml` | Verify/remove `MODIFY_AUDIO_SETTINGS` | 9 |

---

## Migration Counter

Last existing: `0139_v17_request_return_status.sql`  
Next available: **0140**  
⚠️ Always run `ls supabase/migrations/ | cut -c1-4 | sort | uniq -d` before creating!
