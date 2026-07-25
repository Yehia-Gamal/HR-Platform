# Notification catalog — V17

## Current infrastructure observed

- Remote tables/views include `notifications`, `notification_jobs`, `notification_delivery_log`, `kpi_notification_receipts`, `integration_outbox`, and `v_monitor_notifications`.
- Local and remote Edge Functions include `notification-dispatcher`.
- Remote Edge estate is ahead of source control; reconciliation is required before deployment.
- Current runtime delivery on physical Android devices was not tested in Gate 0.

## Required domain events

| Domain | Required events | Recipient | Channel |
|---|---|---|---|
| Attendance | 09:45 reminder, 10:00 due, grace-period late, 17:45 reminder, 18:00 due, missed checkout | employee; manager/HR where specified | work reminders |
| Requests | submitted, clarification, approved, rejected, cancelled, escalated, delegated decision, recalculated | requester and current actor | requests |
| KPI | cycle opened, employee due/submitted, HR due/submitted, manager due/returned/finalized, closing soon, closed | stage owner and reporting users | KPI |
| Disputes | received, clarification, committee assignment, proposed action, Executive decision, HR execution, closed | authorized parties only | administrative |
| Official posts | published, superseded, cancelled, acknowledgement due | affected active employees | announcements |
| Device/security | approved, rejected, revoked, new sign-in, password changed | account owner | security |
| Location | urgent request, terminal delivery failure, completed, declined, expired | target employee / Executive | urgent full-screen |
| Holidays | published, changed, cancelled | affected scope | attendance + announcements |

## Delivery contract

```text
Domain transaction
  -> one immutable event id
  -> notification outbox/job
  -> dispatcher
  -> FCM
  -> Android channel/deep link
  -> delivery/open result
```

Deduplication key must include domain entity, transition, recipient, and version. Realtime refreshes an open UI but does not create a second notification.

## Timing and exclusions

- Operating schedule baseline: 10:00 to 18:00, Africa/Cairo.
- Reminders are skipped after a successful punch and for approved leave, mission, convoy/fundraising duty, official holiday, rest/non-scheduled day, archived/disabled account, and Executive Director.
- Lock-screen text must not expose sensitive dispute or HR details.

## Acceptance evidence still required

- Foreground, background, terminated, and locked states.
- Android 13 notification permission and Android 14/15 full-screen behavior.
- One domain event produces exactly one visible notification.
- Deep link opens the exact entity.
- Delivery/open/failure state is persisted and visible to authorized users.

