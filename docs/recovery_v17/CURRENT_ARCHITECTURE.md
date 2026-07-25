# Current architecture — V17 Gate 0

Date: 2026-07-24 (Africa/Cairo)  
Scope: repository, local clean database, and read-only metadata from linked Supabase project.

## Recovery point

- Working branch: `codex/v17-master-plan`.
- Preflight tag: `backup/v17-preflight-20260724-221845`.
- Recoverable Git snapshot: `03318b27b5e3ed976e333d4925979381da684ff6`.
- Database backup is outside Git at `C:\Users\Elhamd\Documents\AhlaShababBackups\v17-preflight-20260724-2235`.
- No Production database mutation was performed during Gate 0.

## Repository shape

```text
apps/admin_web/          React 19 + Vite + TanStack Query
apps/mobile_flutter/     Flutter + Riverpod + GoRouter
packages/                shared contracts and design tokens
supabase/migrations/     PostgreSQL schema, RLS, RPC and jobs
supabase/functions/      Edge Functions
supabase/tests/          pgTAP contracts and persona tests
scripts/                 validation and release helpers
```

Observed inventory:

| Item | Count |
|---|---:|
| Web source files | 97 |
| Flutter library files | 77 after the concurrent V17 page removals |
| Local migrations | 128 |
| pgTAP files | 51 |
| Local Edge Functions | 12 |
| Remote Edge Functions | 16 |
| Web test files | 8 |
| Flutter test files | 6 |

## Runtime topology

```text
React admin / Flutter mobile
  -> Supabase Auth session
  -> PostgREST tables and RPCs
  -> RLS plus permission helpers
  -> notification/integration jobs
  -> Edge Functions
  -> FCM / Android notification channels
```

The web app has one route tree with HR, Main Admin, and committee workspaces. The Flutter app has one `MaterialApp.router` and role-selected workspaces for employee, manager, Operations, committee, and executive.

## State-management and data access

- Web uses TanStack Query hooks and shared Zod contracts; several components still depend on large management catalog hooks.
- Mobile uses Riverpod, but many screens still call a broad `mobile_providers.dart` layer and large model catalogs.
- Flutter role shells use `IndexedStack`, so all tab pages stay mounted.
- Server state is spread across 237 public tables, 4 views, and 415 public functions on the linked environment.

## Version state

- Root package and `RELEASE_STATUS.json`: `0.10.0`.
- Flutter package: `0.11.1+12`.
- Existing staged APK: `0.11.1`.
- `RELEASE_STATUS.json` is stale: it reports 59 migrations while the current tree has 128.

## Important workspace condition

The branch inherited 41 staged files. During Gate 0, additional unstaged files changed concurrently, including Location-only cleanup and deletion of four secondary/video pages. Those changes were preserved. Gate 0 only corrected one malformed JSX comment and one unused import before the final re-baseline.
