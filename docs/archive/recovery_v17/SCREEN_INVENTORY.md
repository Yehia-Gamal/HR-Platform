# Screen and route inventory — V17 Gate 0

## Flutter route entrypoints

`app.dart` exposes `/` and `/action/:kind/:actionId`. Role selection occurs inside `AppGate`, then a role workspace renders an `IndexedStack`.

| Workspace | Current primary tabs | V17 assessment |
|---|---|---|
| Employee | يومي، الحضور، طلباتي، KPI، حسابي | Keep; rename/reshape requests and KPI contracts |
| Manager | يومي، فريقي، الطلبات، KPI، التشغيل | Keep core; split team attendance/evaluations clearly |
| Operations | يومي، الطلبات، اللجنة، KPI، التشغيل | Keep scoped operations; personal requests must route to Executive |
| Executive | home, inbox, location, reports, governance | Keep core; hide governance/empty secondary modules |
| Committee | disputes | Keep within assigned-case scope |

## Flutter screen files requiring keep/refactor

- Core: `employee_home_page.dart`, `mobile_attendance_page.dart`, `mobile_requests_page.dart`, `mobile_self_service_page.dart`, `mobile_kpi_page.dart`, `mobile_profile_page.dart`.
- Team/Operations: `manager_home_page.dart`, `mobile_team_page.dart`, `manager_operations_page.dart`, `mobile_tasks_page.dart`.
- Executive: `executive_home_page.dart`, `executive_brief_page.dart`, `executive_attendance_tab.dart`, `executive_people_page.dart`, `executive_location_page.dart`, `executive_disputes_page.dart`, `executive_decisions_page.dart`.
- Cross-role: `mobile_notifications_page.dart`, `mobile_official_feed_page.dart`, `mobile_disputes_page.dart`, `monthly_attendance_statement_page.dart`, action/deep-link pages.

## Flutter legacy/secondary screens

| File/module | Current decision |
|---|---|
| `mobile_privacy_page.dart` | Remove route; move required account controls to profile |
| `mobile_learning_page.dart` | Hide |
| `mobile_service_portal_page.dart` | Hide behind an actual feature flag |
| documents/assets/offboarding/payroll panels in profile/self-service | Hide/remove from Production navigation |
| risk/governance/report duplicates | Hide or merge into the approved executive surfaces |
| video verification and video URL flow | Disable new use; retain historical cleanup only |

## Web routes currently mounted

HR routes: dashboard, employees, create/detail employee, attendance, attendance operations, requests, performance, recruitment, onboarding, reports, official feed, notifications.

Main Admin routes: dashboard, actions, live location, location monitoring, official feed, organization, KPI cycles, disputes, access, settings, report scheduler, enterprise, operations, audit/security, integrations, notifications.

Committee routes: committee dashboard/disputes and notifications.

## Web action decisions

- Keep employee, organization, attendance, requests, KPI, devices/accounts, disputes, official feed, settings, audit, and basic reports.
- Hide learning, documents, lifecycle/offboarding, service desk, payroll/people-finance, and empty governance routes until end-to-end contracts exist.
- Add an HR official-holiday management route with scope and exclusions only after its backend contract and tests exist.
- The deployed unauthenticated page currently shows password recovery before an invalid-credential response; this conflicts with V17.

