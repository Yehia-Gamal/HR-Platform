# Data integrity report — V17 Gate 0

Source: read-only SQL transaction on the linked Supabase database. No employee names, ids, phones, or other PII were emitted.

## Population snapshot

| Check | Result |
|---|---:|
| Employees total | 10 |
| Operational (`active` or `invited`, not deleted) | 10 |
| Active employees missing Auth user link | 0 |
| Operational employees missing profile | 0 |
| Active devices | 6 |
| Blocked devices | 2 |

## P0 relationship gaps

| Check | Count | V17 impact |
|---|---:|---|
| Operational employees missing department | 10 | Directory, HR scope, reports, holiday scope |
| Operational employees missing team | 10 | Manager team, requests, KPI scope |
| Operational employees missing job title | 6 | Profile and organization display |
| Operational employees without a current manager relation | 9 | Requests, team, KPI routing |
| Executive KPI evaluations | 1 | Violates mandatory Executive exclusion |

The missing-manager count may include the Executive record, but the remaining records still require deterministic backfill from actual organizational decisions. No random department, team, title, or manager values may be inserted.

## Integrity checks that passed

| Check | Count |
|---|---:|
| Self-manager relations | 0 |
| Two-node manager cycles | 0 |
| Employees with multiple current managers | 0 |
| Orphan profiles | 0 |
| Active devices missing user/employee identity | 0 |
| Active devices with missing employee record | 0 |
| Duplicate active device hashes | 0 |

## Role snapshot

Active assignments include admin, direct manager, employee, Executive Director, Executive Secretary, HR manager, and Operations manager roles. Raw slugs were inspected only as metadata and must not be shown in UI.

## Required remediation sequence

1. Produce a read-only proposed mapping for each missing department/team/title/manager using authoritative HR input.
2. Review the mapping; do not infer values from role names alone.
3. Run a dry-run backfill and record before/after aggregate counts.
4. Apply through a new idempotent migration or audited administration RPC.
5. Remove/close the Executive KPI evaluation through an approved, auditable data migration.
6. Re-run this report plus persona/RLS tests.

Gate 1 is blocked from completion until authoritative organization mappings exist, but code-level discovery and safe contract repairs can continue.

