# V17 rollback plan

## Existing recovery points

### Git

- Branch: `codex/v17-master-plan`.
- Preflight tag: `backup/v17-preflight-20260724-221845`.
- Snapshot object including inherited indexed changes: `03318b27b5e3ed976e333d4925979381da684ff6`.

The working tree must not be reset destructively. Recovery uses a new branch/worktree from the tag or snapshot, then selectively reapplies reviewed changes.

### Database

External backup directory:

```text
C:\Users\Elhamd\Documents\AhlaShababBackups\v17-preflight-20260724-2235
```

| File | Bytes | SHA-256 |
|---|---:|---|
| `schema.sql` | 1,658,746 | `BCE9ED394BFDDF4164EB03E10947F78DB8AEFDFF3B36E86057278ACBE4BB9837` |
| `roles.sql` | 297 | `25873CEC56A2CC6514E204F420231777F85C03DA818CAA7090CDCDFA89776ECD` |
| `data.sql` | 1,720,567 | `76C7C075A3637846199B8D1F494A6916E6FDC0F0283C1288C82F85EBB0A20488` |

These files are outside Git because they may contain sensitive data.

## Migration rollback strategy

- Prefer forward corrective migrations; do not edit or delete remote migration history.
- Every V17 migration must be idempotent or have a documented precondition, verification query, and compensating migration.
- Destructive column/table removal is deferred until a later release after caller and retention verification.
- Backfills first write a dry-run aggregate report, then execute in a controlled transaction, then re-run integrity counts.

## Deployment rollback

1. Record current web deployment id, Edge Function versions, migration list, and mobile artifact hash.
2. Deploy one vertical slice at a time behind server/UI flags where practical.
3. On failure, disable the slice/route, restore the previous web deployment/Edge version, and apply a forward database correction.
4. Do not restore the full database over the linked environment unless data-loss scope is confirmed and explicitly authorized.

## Restore drill still required

The data dump reported circular foreign-key constraints in organization and legacy tables. Before Gate 3:

1. Create an isolated PostgreSQL/Supabase restore target.
2. Restore roles/schema, then data with the documented trigger/constraint strategy.
3. Compare table counts and critical integrity aggregates.
4. Run pgTAP and persona tests against the restored target.
5. Record duration, warnings, and exact commands without secrets.

Until this drill passes, the backup is a recovery asset but not a proven recovery procedure.
