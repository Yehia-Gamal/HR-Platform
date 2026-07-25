# Legacy removal report — V17 Gate 0

Status: inventory only. No destructive data removal was performed.

## Search results

File counts exclude Markdown, build output, `dist-mobile`, and dependencies.

| Term | Files | Interpretation |
|---|---:|---|
| `video` | 38 | Active, historical retention, tests, and legacy paths are mixed |
| `camera` | 7 | Must be removed from Location-only runtime unless used elsewhere by an approved feature |
| `video_required` | 4 | Legacy request contract |
| `video_id` | 5 | Historical response/retention contract |
| `urgent_location_v3` | 2 | Old notification/channel identifier |
| `device_not_active` | 8 | Error mapping and device contract |
| `PGRST203` | 4 | Known RPC overload failure path |
| `privacy` | 21 | Backend governance plus standalone UI are mixed |
| `documents` | 36 | HR/legacy/mobile panels mixed |
| `payroll` | 14 | Must not be exposed in current mobile release |
| `risk` | 41 | Several executive/enterprise modules remain |
| `governance` | 26 | Several executive/admin modules remain |

Raw role slugs also remain in source: `direct-manager` in 16 files, `executive-director` in 19, and `executive-secretary` in 19. Storage values may remain; presentation must be Arabic and permission-based.

## Classification

| Legacy group | Runtime action | Data action |
|---|---|---|
| New location video capture | Disable/remove all active callers and permissions | Do not create new records |
| Historical video metadata/retention | Keep server-only until retention finishes | Delete only through audited retention policy |
| Privacy standalone page | Remove navigation/route | Keep server privacy/audit controls |
| Learning/training/skills | Hide | Keep data until future module decision |
| Documents/custody/offboarding/payroll | Remove from mobile navigation | Keep HR/history data |
| Service desk | Hide via actual flag | Keep schema |
| Risk/governance/report duplicates | Hide/merge | Keep audit/history data |

## Concurrent cleanup observed

During Gate 0, unstaged changes appeared in 11 files, including removal of `video_verification_page.dart` and edits to Location UI/provider/web files. These changes were not authored or overwritten by this documentation pass. They require review, tests, and attribution before staging.

## Removal gate

For every file/RPC/route: identify runtime caller -> introduce replacement/flag -> run source/runtime tests -> observe logs -> document rollback -> remove. Historical columns and records are deferred to a later migration.

