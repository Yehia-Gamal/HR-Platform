# V17 implementation traceability

Evidence labels:

- `executed-local`: command actually ran in this workspace.
- `read-only-remote`: linked environment inspected without mutation.
- `deployed-ui`: visible deployed behavior inspected without sign-in.
- `pending-runtime`: not yet proven.

| Requirement ID | Source | State before | Root cause / finding | Files or migrations | Tests / evidence | State |
|---|---|---|---|---|---|---|
| V17-G0-01 | Gate 0 | No V17 recovery docs | Prior reports and release metadata are stale/incomplete | `docs/recovery_v17/*` | 16 required documents plus executed re-baseline | Complete |
| V17-DATA-01 | Employee relationships | 10/10 lack department/team; 9/10 lack current manager | Organization seed/links not backfilled to operational employees | New migration not yet assigned | read-only-remote aggregate SQL | Open P0 |
| V17-DATA-02 | Executive exclusion | One Executive KPI evaluation exists | Old KPI generation/workflow did not exclude role | New migration + KPI RPC changes required | read-only-remote aggregate SQL | Open P0 |
| V17-DB-01 | Migration safety | Published `0126` modified locally | Inherited work edited historical migration | Rebase delta to next migration | local/remote migration list | Open P0 |
| V17-LOC-01 | Location-only | Two remote `request_live_location` overloads with mode remain | Remote has not received local repair; contract is ambiguous | `0128` inherited, must be safely rebased/deployed | remote `pg_proc` signatures | Open P0 |
| V17-LOC-02 | No new video | Legacy video/camera references remain | Old V12/runtime/history paths overlap | 38 video files; concurrent cleanup in progress | legacy search; Flutter analyze baseline | Open P0 |
| V17-DEVICE-01 | Device registration | Tables/RPCs/tests exist; device E2E not proven | Source contract exists but physical runtime evidence absent | device/passkey RPC and Flutter profile | pgTAP pass; device test pending | Open P0 |
| V17-ATT-01 | Attendance | Initial analyze failed on a dead video page; concurrent cleanup removed it | Legacy source remained after command removal | mobile Location/video pages | final analyze pass; 662 pgTAP pass; debug APK pass | Workflow E2E still open |
| V17-REQ-01 | Six requests | Generic request estate exists | UI/workflow types not yet verified against all six V17 routes | requests UI/RPC/migrations | pending persona E2E | Open P0 |
| V17-KPI-01 | Employee -> HR -> Manager | Old mixed stage fields and permissions remain | Schema/workflow accumulated prior variants | KPI migrations/RPCs/UI | pending V17 stage tests | Open P0 |
| V17-DISP-01 | Administrative action | Existing dispute module present | V17 proposal/Executive/HR execution semantics not proven | dispute migrations/RPC/UI | pending E2E | Open P0 |
| V17-NOTIF-01 | Unified notifications | Outbox/job infrastructure exists | Remote/source function drift and no physical-device evidence | notification dispatcher/tables/Android | pending device E2E | Open P0 |
| V17-POST-01 | Official posts | Feed and publish RPC exist | Three publisher personas/audience/read receipt not proven | official feed UI/RPC | pending E2E | Open P1 |
| V17-AUTH-01 | Recovery visibility | Deployed login shows recovery immediately | Deployed UI predates V17 rule or source condition is wrong | login pages | deployed-ui DOM, no form submitted | Open P1 |
| V17-UI-01 | Hide secondary modules | Some routes hidden; active RPC/panels still reference legacy modules | Hiding is partial and lacks shared feature flags | app routes/workspace scaffold/profile | source search | Open P1 |
| V17-BASE-01 | Web baseline | Unknown current result | — | current tree before concurrent edits | `npm run check:all`: pass, 71 tests | Executed-local pass |
| V17-BASE-02 | Flutter baseline | Initial analyze failed on dead legacy video source | Concurrent cleanup removed the dead page; unused import removed | Location overlay/pages | final analyze clean; 30 tests pass; current debug APK pass | Executed-local pass |
| V17-BASE-03 | DB baseline | Unknown current reset result | — | migrations `0001`-`0128` | reset pass; 51 files/662 pgTAP pass | Executed-local pass |

`Done` is intentionally unused until runtime acceptance evidence exists.
