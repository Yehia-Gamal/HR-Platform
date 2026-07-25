# RPC and Edge Function catalog — V17 Gate 0

## RPC estate

The remote public schema contains 415 functions. Client source references 55 distinct RPC names. Domain-name inventory on remote:

| Domain heuristic | Function count |
|---|---:|
| Attendance | 25 |
| Requests/leave/mission | 40 |
| KPI | 32 |
| Employees/profile | 22 |
| Disputes | 26 |
| Location | 11 |
| Notifications/push | 8 |
| Other/legacy/administration | 251 |

## Critical client RPCs

| Domain | RPCs in active source | Gate 0 finding |
|---|---|---|
| Access | `get_my_access_context`, `has_permission`, `current_is_full_access` | Keep as canonical guard helpers |
| Employee | `provision_employee_record`, `activate_employee_after_first_login`, `get_employee_360`, `get_employee_home`, `get_my_mobile_profile`, `change_employee_manager_admin`, `archive_employee_secure` | Provisioning is Security Definer; Gate 1 data consistency required |
| Attendance | `get_my_attendance_state`, `get_my_attendance_history`, `finalize_verified_attendance`, `get_attendance_dashboard`, executive attendance RPCs | Local contracts pass; device/runtime evidence pending |
| Requests | `get_request_inbox`, `decide_request`, `reassign_request`, `extend_request_deadline`, `withdraw_escalation` | Six-type unified flow and Operations personal routing pending |
| KPI | `get_kpi_inbox`, `get_kpi_evaluation_form`, `advance_kpi_stage` | Remote data already has one Executive evaluation; workflow repair required |
| Disputes | `get_my_dispute_portal`, decision draft/transition RPCs | V17 action approval/execution semantics pending |
| Location | `request_live_location`, `get_my_live_location_requests`, `get_live_location_response`, `get_location_directory` | P0: two remote overloads remain, causing PostgREST ambiguity risk |
| Feed/notifications | `publish_official_announcement`, `get_official_feed_admin`, `get_my_notifications`, `mark_my_notifications_read` | Outbox/dedup/deep-link acceptance pending |

Legacy client RPC references still exist for learning, payslips, offboarding, service portal, and video retention. They must not be reachable from current Production navigation.

## Remote `request_live_location` drift

Remote signatures:

```text
(p_employee_id uuid, p_mode text, p_reason text)
(p_employee_id uuid, p_reason text, p_mode text, p_duration_minutes integer)
```

V17 requires one unambiguous Location-only contract. Local `0128` attempts a repair but is not deployed and must be rebased after resolving the published-`0126` modification.

## Edge Functions

Local directories (12): admin create/resend, identifier sign-in, integration worker, map/video URL, notification dispatcher, passkey register, retention cleanup, scheduled reports, attendance verification, WebAuthn challenge.

Remote active functions (16) add four functions absent locally:

- `admin-create-user`
- `complete-initial-password`
- `process-request-sla`
- `resolve-login-identifier`

Remote also still deploys `live-location-video-url`. Historical video retention may require a server path, but new location requests must never depend on it.

Most local Edge Function entries set `verify_jwt=false`; each function therefore must prove its own bearer/session/service-secret validation. This is an audit item, not an automatic vulnerability conclusion.

## Required cleanup sequence

1. Map every source RPC call to one remote signature and one test.
2. Repair overloads in a new migration.
3. Reconcile the four remote-only Edge Functions with source control before deployment.
4. Remove legacy calls from active navigation.
5. Retire functions only after logs, callers, and rollback are verified.

