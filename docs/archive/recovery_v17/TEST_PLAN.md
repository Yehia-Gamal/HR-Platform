# V17 test plan

## Evidence policy

- Static inspection, local runtime, remote metadata, deployed UI, and physical-device evidence are reported separately.
- A passing build does not prove a business workflow.
- A passing local database test does not prove the linked environment.
- No scenario is marked complete without command/log/screenshot evidence and the tested persona.

## Gate 0 — baseline

- `npm run check:all`.
- `flutter analyze --no-fatal-infos`.
- `flutter test`.
- debug and release APK builds.
- clean `supabase db reset --local`.
- `supabase test db`.
- local/remote migration comparison.
- deployed unauthenticated route inspection.

## Gate 1 — data and security

- Clean migration reset plus rollback/forward migration rehearsal.
- Data integrity assertions for current assignment/reporting lines/devices/Executive exclusions.
- RLS negative tests for employee, manager, Operations, Executive, HR, Main Admin, unlinked Auth, and anonymous.
- RPC direct-call bypass tests, including alternate employee ids and out-of-stage writes.
- Edge Function authentication tests for every `verify_jwt=false` function.

## Gate 2 — vertical workflow slices

For each feature, execute backend -> web/mobile -> notification -> report consistency:

1. Provision employee and assign manager.
2. Register/approve/revoke device and local biometric challenge.
3. Check in/out with GPS off/on, duplicate prevention, schedule/leave exceptions.
4. Submit, clarify, approve, reject, cancel, and escalate each of six request types.
5. KPI employee -> HR -> manager with field ownership and Executive exclusion.
6. Dispute -> committee -> secretary proposal -> Executive decision -> HR execution.
7. Official post from Admin, HR, and Executive with read receipt.
8. Location-only urgent request and response with deduplication.
9. Executive daily brief and HR/phone/report count consistency.

## Gate 3 — release candidate

- `npm run check:all` after final changes.
- Flutter analyze/test and signed release APK/AAB.
- Restore backup into isolated database and validate row/object counts.
- Physical Android matrix: Samsung, another vendor, oldest supported, Android 13, Android 14/15.
- Foreground/background/terminated/locked notifications.
- Light/dark, RTL, small-screen, bottom inset, and error/empty/offline visual checks.
- Performance/query-plan checks and APK size comparison.
- Zero unaccepted P0/P1 issues.

## Required artifacts

Logs must be redacted. Screenshots/video must avoid unnecessary PII. Every result is linked from `TEST_RESULTS.md` and `IMPLEMENTATION_TRACEABILITY.md`.

