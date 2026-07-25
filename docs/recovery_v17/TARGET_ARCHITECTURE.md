# Target architecture — V17

Status: approved target; implementation remains gate-controlled.

## Principles

- One Flutter application, one admin web application, one Supabase project.
- Feature-first modules with one route and one canonical contract per business capability.
- UI never calls Supabase directly; all reads and writes pass through query/repository or controller layers.
- Personal operations derive identity from JWT, not a client-supplied employee id.
- Permissions are enforced by UI guard, RPC validation, and RLS.
- Domain events feed one notification outbox; Realtime only refreshes open screens.
- Legacy code is removed only after replacement, test evidence, feature flag, and rollback path exist.

## Flutter target

```text
lib/
  app/{router,theme,localization,guards}
  core/{auth,network,errors,notifications,biometrics,location,audit,widgets}
  features/
    onboarding/
    profile/
    device_security/
    attendance/
    attendance_statement/
    requests/{leave,permission,mission,official_duty,correction}/
    team/
    kpi/
    complaints/
    live_location/
    notifications/
    official_feed/
    executive_dashboard/
```

Each feature owns `presentation`, `application`, `domain`, and `data`. Role shells compose the same features; they do not clone pages.

## Web target

```text
src/
  app/
  core/{auth,permissions,errors,network}
  features/{employees,organization,attendance,monthly_statements,requests,kpi,devices,complaints,official_feed,reports,settings,audit}
  shared/
```

The route tree remains single. HR and Main Admin differences are permission-driven.

## Canonical business flows

1. Provision employee -> link Auth/Profile/Employee/assignment/reporting line -> register device.
2. Device challenge -> local biometric -> hardware-backed signature -> attendance RPC.
3. Unified request -> manager or Executive route -> decision -> attendance/balance/report recalculation.
4. KPI: employee -> HR -> direct manager -> final report; Executive Director excluded.
5. Dispute: employee -> secretary -> committee -> proposed action -> Executive decision -> HR execution.
6. Official post -> audience -> domain event -> notification outbox -> FCM -> deep link/read receipt.
7. Location request: Executive only -> outbox/FCM -> employee consent -> fresh location -> Executive result. No new video path.

## Transition order

- Gate 1: canonical employee relationships, permissions, RLS, device identity.
- Gate 2: attendance, requests, KPI, disputes, posts, notifications, location, dashboards.
- Gate 3: remove legacy, perform role/device E2E, restore drill, then release.

