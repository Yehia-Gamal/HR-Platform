# Screen action matrix — V17

| Surface | Role | Action | Backend gate | Status |
|---|---|---|---|---|
| Employee home | Employee/Manager/Operations | Refactor to true daily state and primary CTAs | canonical daily summary | Pending Gate 2 |
| Device security | Employee/Manager/Operations | Create/complete | device registration + challenge + admin decision | Pending Gate 1 |
| Attendance | Employee/Manager/Operations | Refactor | device signature + schedule + attendance RPC | Pending Gate 2 |
| Unified requests | All employee personas | Merge six request types | request state machine + routing | Pending Gate 2 |
| Team requests | Manager/Operations | Refactor | scoped inbox + no self-approval | Pending Gate 2 |
| Monthly statement | Employee/Manager/HR/Admin | Complete | canonical report RPC | In inherited changes; runtime not verified |
| My KPI | Evaluated employee only | Refactor | employee -> HR -> manager | Pending Gate 2 |
| Team KPI | Direct manager | Separate from My KPI | direct-report scope | Pending Gate 2 |
| KPI cycles | Main Admin/secretary only | Keep and harden | `performance.cycle.manage` | Pending Gate 1 |
| Dispute submission | Employee personas | Simplify | 3-300 word server validation | Pending Gate 2 |
| Dispute decision | Secretary/committee/Executive/HR | Refactor | proposal -> approval -> HR execution | Pending Gate 2 |
| Official feed | readers; Admin/HR/Executive publishers | Refactor | audience + version + outbox | Pending Gate 2 |
| Executive daily brief | Executive | Refactor | expected-attendance canonical view | Pending Gate 2 |
| Location request | Executive | Location-only | single RPC signature + outbox/FCM | P0 drift found |
| Account/profile | All | Merge account controls | profile/device APIs | Pending Gate 2 |
| Privacy standalone | None | Remove route | none | Pending safe removal |
| Learning/training | None in current release | Hide | feature flag | Pending |
| Documents/custody/offboarding/payroll | None on mobile | Hide/remove navigation | feature flag | Pending |
| Service desk | None in current release | Hide | feature flag | Pending |
| Risk/governance duplicate pages | None in current release | Hide/merge | canonical report/decision contract | Pending |
| HR official holidays | HR/Main Admin | Add only as vertical slice | holiday scope + attendance + notification | Pending Gate 2 |

No row may move to `Done` without an executed acceptance test and linked runtime evidence.
