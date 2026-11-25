# RLS policy matrix — V17 Gate 0

Remote metadata shows RLS enabled on all 237 public tables and 521 public policies. Presence is not behavioral proof; local pgTAP/persona tests are the current runtime evidence.

| Object | Remote policy count | Current policy verbs observed | V17 acceptance requirement |
|---|---:|---|---|
| `employees` | 2 | SELECT, UPDATE | self/team/HR/org scope; archive through guarded RPC |
| `profiles` | 4 | SELECT/INSERT/UPDATE/DELETE | self plus administrative scope; protected fields |
| `employee_assignments` | 4 | full CRUD | HR/Admin only for writes; scoped read |
| `manager_relations` | 4 | full CRUD | guarded write; manager sees direct scope |
| `employee_devices` | 1 | SELECT | self read; decisions through guarded RPC |
| `passkey_credentials` | 1 | SELECT | self only; mutation through verified functions |
| `attendance_daily` | 2 | SELECT, ALL | self/team/HR/org scope; no client overwrite |
| `attendance_events` | 3 | SELECT/UPDATE/DELETE | append/finalize through secure attendance path only |
| `requests` | 2 | SELECT, UPDATE | self/inbox scope; create/decide RPC enforcement |
| `request_actions` | 1 | SELECT | immutable action history |
| `kpi_cycles` | 4 | full CRUD | cycle write only Main Admin/secretary |
| `kpi_evaluations` | 4 | full CRUD | self/direct team/HR fields; Executive excluded |
| `kpi_scores` | 4 | full CRUD | field-owner stage enforcement |
| `live_location_requests` | 1 | SELECT | Executive creates; target reads/responds |
| `location_request_responses` | 1 | SELECT | target write through guarded RPC only |
| `dispute_cases` | 1 | SELECT | owner/assigned committee/secretary/escalated Executive |
| `dispute_decisions` | 1 | SELECT | stage-specific mutation RPCs |
| `notifications` | 4 | full CRUD | recipient read/update only; server insert |
| `push_subscriptions` | 4 | full CRUD | own subscription only |

## Mandatory negative personas

- Employee reads another employee KPI: deny.
- Manager reads employee outside direct team: deny.
- Operations decides own request: deny.
- HR manages KPI cycle: deny.
- Manager changes HR-owned KPI scores: deny.
- Ordinary user publishes an official post: deny.
- Non-Executive creates an organization location request: deny.
- HR executes an unapproved administrative action: deny.
- Auth user without an active employee reads business data: deny.
- Modified client supplies another employee id: deny.

## Evidence state

- Local: `supabase test db` passed 51 files / 662 assertions, including persona runtime tests.
- Remote: policy metadata and data counts inspected read-only; remote persona chains were not executed in Gate 0.
- Gate 1 cannot pass until the V17-specific negative cases above are present and executed against a reset database.

