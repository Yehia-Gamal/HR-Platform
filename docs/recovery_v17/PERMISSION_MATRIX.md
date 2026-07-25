# Permission matrix — V17 target

Legend: `self`, `team`, `scope`, `organization`, `none`.

| Capability | Employee | Manager | Operations | Executive | HR | Main Admin/Secretary |
|---|---|---|---|---|---|---|
| Self attendance | self | self | self | none | none | none |
| Monthly statement | self | self + team | self + scope | summary only | scope | organization |
| Personal request create | self | self | self | exceptional only | self if employee | self if employee |
| Own request decision | none | none | none | none | none | none |
| Team request decision | none | team | delegated scope | Operations/escalated paths | workflow scope | audited exception |
| Team directory | none | team | scope | organization | HR scope | organization |
| KPI self evaluation | self | self | self | none | self if evaluated | self if evaluated |
| KPI manager fields | none | team | direct reports only | none | none | audited exception |
| KPI HR fields | none | none | none | none | HR scope | audited exception |
| KPI cycle manage | none | none | none | none | none | only |
| Dispute submit | self | self | self | allowed | allowed | allowed |
| Dispute read | own | own unless assigned | assigned committee | escalated/final | execution or assigned scope | managed scope |
| Proposed administrative action | none | none | committee input | none | none | secretary |
| Final administrative decision | none | none | none | only | none | none |
| Execute approved action | none | none | none | none | only after approval | monitor |
| Official post publish | none | none | none | mobile | HR web | admin web |
| Location request | none | none | none | organization only | none | none |
| Employee administration | none | none | none | none | scope | organization |
| Role/permission administration | none | none | none | none | none | only |

## Enforcement contract

- UI permission checks control visibility only.
- RPC validates permission, role/scope, workflow stage, and identity.
- RLS blocks direct table bypass.
- Main Admin exception requires reason and before/after audit.
- Formal job title stays separate from effective application permissions.

Gate 1 must reconcile existing slugs such as `direct-manager`, `executive-director`, `executive-secretary`, `hr-manager`, and `operations-manager-2` with this capability matrix without displaying raw slugs to users.
