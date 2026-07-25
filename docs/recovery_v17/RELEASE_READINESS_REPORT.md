# Release readiness — V17 Gate 0

Decision: **NOT READY FOR RELEASE**.

## Gate summary

| Gate | State | Reason |
|---|---|---|
| Recovery point | Pass | Git snapshot/tag and external database dumps exist |
| Gate 0 discovery | Pass | 16 documents written and final code/database re-baseline executed |
| Gate 1 data/security | Fail | missing organization/reporting links, Executive KPI record, migration drift |
| Gate 2 workflows | Not run | no complete six-persona runtime evidence |
| Gate 3 release | Not run | no restore drill, signed V17 build, or physical-device evidence |

## Release blockers

1. Published migration `0126` is locally modified.
2. Remote lacks the Location RPC repair and still exposes two ambiguous overloads.
3. All operational employees lack department/team links in the current remote snapshot; nine lack a current manager relation.
4. An Executive KPI evaluation exists despite the mandatory exclusion.
5. Remote Edge Function inventory differs from source control.
6. Required device/FCM/role E2E evidence does not exist for V17.
7. Backup restore is untested and circular foreign-key warnings were emitted.
8. Deployed password recovery visibility violates V17.

## Evidence that is positive but insufficient

- Web/contract quality gate passed with 71 tests.
- Flutter unit/widget tests passed with 30 tests.
- Debug APK built.
- Local reset and 662 pgTAP assertions passed.
- All remote public tables report RLS enabled.

## Next release decision point

Do not deploy code or migrations until Gate 1 produces: a safe new migration sequence, authoritative organization backfill, Executive KPI cleanup, V17 negative RLS tests, and a clean local re-baseline including Flutter analyzer.
