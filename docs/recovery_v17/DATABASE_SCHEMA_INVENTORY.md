# Database schema inventory — V17 Gate 0

Source: read-only metadata from linked project `ujzzvqsodyhnnnpkoaml` on 2026-07-24.

## Remote totals

| Object | Count |
|---|---:|
| PostgreSQL version | 17.6 |
| Public base tables | 237 |
| Public views | 4 |
| Public functions | 415 |
| Public RLS policies | 521 |
| Public tables with RLS enabled | 237 |
| Recorded remote migrations | 125 |

## Migration drift

- Local files: 128, sequential with no duplicate four-digit prefix.
- Remote contains `0001` through `0127` except `0119` and `0122`.
- Local-only: `0119_bridge_placeholder.sql`, `0122_bridge_placeholder.sql`, and `0128_repair_request_live_location_staging.sql`.
- Remote already records `0126`; the inherited index contains a modification to local `0126`. A published migration must not be edited. Its intended delta must move to a new migration.
- Local reset applied all 128 migrations successfully. That is local evidence only; no migration was pushed remotely.

## Key current contracts

| Domain | Main objects observed |
|---|---|
| Identity | `employees`, `profiles`, `roles`, `user_roles`, `permissions`, `role_permissions` |
| Organization | `departments`, `teams`, `job_titles`, `employee_assignments`, `manager_relations` |
| Device | `employee_devices`, `passkey_credentials`, challenge and installation tables |
| Attendance | `attendance_events`, `attendance_daily`, shifts, schedules, exceptions |
| Requests | `requests`, subtype tables, `request_actions`, workflow instances/steps |
| KPI | `kpi_cycles`, `kpi_evaluations`, `kpi_scores`, criteria and policy tables |
| Disputes | `dispute_cases`, parties, sessions, decisions, execution/receipt records |
| Location | `live_location_requests`, `location_request_responses`, employee locations, historical video metadata |
| Notifications | `notifications`, `notification_jobs`, `notification_delivery_log`, `integration_outbox` |

## Structural findings

- `employee_assignments` is an assignment/change record with from/to organization columns; current organization is also stored on `employees` and `profiles`. A canonical current-assignment view is still required.
- `kpi_evaluations` carries old and new stage fields plus secretary/executive approval fields. V17 requires one employee -> HR -> manager workflow and Executive exclusion.
- `live_location_requests` still has a `purpose` field and remote RPC overloads that accept mode. V17 requires Location-only for new requests.
- Data-only backup reported circular foreign keys in organization and several legacy/enterprise tables. Restore must be tested with a controlled constraint/trigger strategy.

## Required next migration rules

1. Do not rewrite `0126` or any remote-recorded migration.
2. Rebase inherited SQL changes into the next unique migration after checking concurrent work.
3. Use additive constraints/views and explicit backfill dry runs before making columns required.
4. Stop new video creation without deleting historical video records.
5. Add tests for every data constraint and negative authorization path.

