# V17 test results

Date: 2026-07-24. These are Gate 0 results only.

| Command / check | Result | Executed evidence |
|---|---|---|
| `npm run check:all` | PASS | Re-run after concurrent cleanup: shared contracts 39 tests; admin web 32 tests; typecheck/build/source integrity/foundation/secret scan passed |
| `flutter analyze --no-fatal-infos` | PASS after cleanup | Initial run failed on legacy `registerLocationVideo`; final run reports `No issues found` after the dead page cleanup and unused-import removal |
| `flutter test` | PASS | 30 tests passed |
| `flutter build apk --debug` | PASS | Rebuilt current `app-debug.apk` after the final analyzer pass |
| `supabase db reset --local` | PASS | 128 migrations applied from empty database and seeds completed |
| `supabase test db` | PASS | 51 files, 662 tests, Result PASS |
| Remote migration list | MIXED | 125 remote records; local-only 0119, 0122, 0128; published 0126 differs locally |
| Remote schema/RLS metadata | READ ONLY | PostgreSQL 17.6; 237 tables; all report RLS enabled; 521 policies; 415 functions |
| Remote data integrity aggregate | FAIL GATE | organization/reporting gaps and one Executive KPI evaluation found |
| Deployed `/admin` unauthenticated page | PARTIAL | Loads Arabic login page without console errors; password recovery is visible too early |
| Database backup | PASS WITH WARNING | schema/roles/data dumps created with SHA-256; circular-FK restore warning requires drill |

## Explicitly not tested yet

- Remote persona login/RLS chains.
- Production/staging mutation or migration deployment.
- Real employee, manager, Operations, Executive, HR, or Main Admin end-to-end journeys.
- Physical-device biometric, GPS, FCM, full-screen, locked-screen behavior.
- Release-signed build for the V17 result.
- Backup restore.
- PDF/CSV parity and visual regression.

## Baseline interpretation

The current tree can build web and a debug APK, passes source analysis, and can rebuild/test the local database. It is not release-ready because remote data violates V17 relationships/exclusions, migration history is unsafe, and role/device workflows lack runtime evidence.
