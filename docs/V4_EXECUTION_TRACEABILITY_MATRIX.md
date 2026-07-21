# Ahla Shabab V4 execution traceability matrix

Binding sources:

- `AHLA_SHABAB_STANDALONE_UNIFIED_EXECUTION_PLAN_V4.md` (controlling reference)
- `AHLA_SHABAB_UNIFIED_EXECUTION_PLAN_V2_ALL_ISSUES.md` (supplemental evidence requirements)

Status rules:

- `OPEN`: not implemented or not yet inspected deeply enough.
- `IMPLEMENTED / TEST PENDING`: code exists, but the plan's acceptance test has not passed with recorded evidence.
- `ACCEPTED`: the exact acceptance test passed and its evidence is linked. No row may be marked accepted from static inspection alone.
- Hardware, killed-app FCM, Play Protect, and Samsung layout rows remain open until tested on physical devices.

## Clause-to-component map

| Area | Authoritative implementation | Acceptance evidence | Status |
|---|---|---|---|
| Audit RPC signature/idempotency | migrations `0074`, `0082`, `0089_atomic_idempotent_attendance_finalize.sql` | Direct SQL + attendance fault/replay test | IMPLEMENTED / TEST PENDING |
| Passkey challenge and server verification | `supabase/functions/webauthn-challenge`, `passkey-register`, `verify-attendance-punch` | WebAuthn registration/assertion runtime | IMPLEMENTED / TEST PENDING |
| Trusted device activation | `supabase/migrations/0083_location_history_and_verified_devices.sql` | `0041_v4_location_notification_device_contract.sql` + physical registration | IMPLEMENTED / TEST PENDING |
| Five-second silent front-camera video | `apps/mobile_flutter/lib/features/mobile_pages/video_verification_page.dart` | Physical Samsung recording, duration/media inspection | IMPLEMENTED / TEST PENDING |
| GPS preflight/resume and exact attendance | `location_service.dart`, `mobile_attendance_page.dart`, `verify-attendance-punch`, migration `0082` | GPS-off/resume + in/out-geofence runtime | IMPLEMENTED / TEST PENDING |
| Strong foreground/background/killed FCM | `notification-dispatcher`, `push_service.dart`, Android manifest | Three-state physical-device FCM run | IMPLEMENTED / TEST PENDING |
| Full-screen Android 14 access | Android manifest, `push_service.dart`, `LocationRequestFullActivity.kt` | Lock-screen Android 14/15 run | IMPLEMENTED / TEST PENDING |
| Exact deep-link authorization | `app.dart`, `mobile_action_deep_link_page.dart`, backend action-target RPC | Authorized/unauthorized ID tests | IMPLEMENTED / TEST PENDING |
| All-person executive attendance/location lists | migrations `0069`, `0077`, `0081`, mobile executive pages | Yahya + no-event employee runtime | IMPLEMENTED / TEST PENDING |
| Independent resend after 30 seconds | migration `0083`, SQL tests `0040`/`0041` | Two surviving request IDs after cooldown | IMPLEMENTED / TEST PENDING |
| Private storage/signed URLs/24h cleanup | migrations `0034`, `0037`, functions `live-location-video-url`, `retention-cleanup` | Owner/manager/stranger + expiry/deletion runtime | IMPLEMENTED / TEST PENDING |
| Release signing/R8/backup/cleartext | Gradle, manifest, XML security policies, CI release workflow | `apksigner`, `apkanalyzer`, Play Protect | IMPLEMENTED / TEST PENDING |
| Crash reporting/correlation IDs | migration `0089`, attendance Edge response/logs | Forced-error correlation lookup; crash SDK still required | IMPLEMENTED / TEST PENDING |
| Executive decision center | Executive mobile pages and decision/announcement/poll/dispute RPCs | CRUD/route/persona E2E | OPEN |
| Provisioning/leave/KPI repair | migrations `0079`, `0082`, admin employee function | First-login and replay test | IMPLEMENTED / TEST PENDING |
| HR employee/structure editing | migration `0084_secure_employee_manager_change.sql`, admin employee UI | HR scope + audit + downstream request test | IMPLEMENTED / TEST PENDING |
| Web manager invitation | `admin-create-employee`/invitation flow | Main Admin invite and first-login run | OPEN |
| Responsive/RTL/contrast/branding | Flutter themes/pages and admin web | Viewport, semantics, phone-LTR, visual evidence | OPEN |
| Cross-client contracts | Shared Supabase RPCs | Same-persona web/mobile comparison | OPEN |

## Mandatory acceptance ledger

| # | Acceptance outcome | Current status | Required evidence |
|---:|---|---|---|
| 1 | Executive sees all employees including Yahya | IMPLEMENTED / TEST PENDING | Executive seeded/production runtime |
| 2 | Send location + 5-second video without a reason | IMPLEMENTED / TEST PENDING | UI + inserted request payload |
| 3 | Notification arrives while app is open | OPEN | Physical FCM run |
| 4 | Notification arrives in background | OPEN | Physical FCM run |
| 5 | Notification arrives after app is killed | OPEN | Physical FCM run |
| 6 | Notification opens the exact request | IMPLEMENTED / TEST PENDING | Route and authorization runtime |
| 7 | GPS-off prompt resumes the same request | IMPLEMENTED / TEST PENDING | Physical lifecycle run |
| 8 | Front camera opens without black screen | OPEN | Physical Samsung run |
| 9 | Camera preview is not stretched | OPEN | Portrait screenshot/video |
| 10 | Exactly five seconds records without audio permission | IMPLEMENTED / TEST PENDING | Media metadata + permission inspection |
| 11 | Fresh accurate location is captured | IMPLEMENTED / TEST PENDING | Timestamp/accuracy runtime |
| 12 | Map, address, and map snapshot appear | IMPLEMENTED / TEST PENDING | Employee/executive runtime evidence |
| 13 | Video uploads successfully | IMPLEMENTED / TEST PENDING | Storage row/object evidence |
| 14 | Result appears immediately for executive | OPEN | Two-client E2E |
| 15 | Result appears in employee profile | OPEN | Profile runtime |
| 16 | Resend after 30 seconds does not cancel prior request | IMPLEMENTED / TEST PENDING | SQL `0040` plus UI runtime |
| 17 | Device/passkey registration succeeds | IMPLEMENTED / TEST PENDING | Physical WebAuthn runtime |
| 18 | Attendance arrival/departure succeeds with passkey | IMPLEMENTED / TEST PENDING | Two punches and server records |
| 19 | User sees no technical exception text | IMPLEMENTED / TEST PENDING | Forced-failure UI suite |
| 20 | Bottom bar covers no content/button | OPEN | Widget + device viewport suite |
| 21 | GPS-off attendance resumes same operation | IMPLEMENTED / TEST PENDING | Physical lifecycle run |
| 22 | No PGRST203; real arrival/departure recorded | IMPLEMENTED / TEST PENDING | Direct RPC + Flutter run |
| 23 | Schedule/corrections works without legal_entity_id error | IMPLEMENTED / TEST PENDING | Two legal-entity personas |
| 24 | Today's attendance includes people without events | IMPLEMENTED / TEST PENDING | LEFT JOIN runtime dataset |
| 25 | Loading times out into error/retry | IMPLEMENTED / TEST PENDING | Delayed-network test |
| 26 | Scroll content ends above bottom navigation | OPEN | Widget/device evidence |
| 27 | Every icon/card/notification opens correct page | OPEN | Route/widget matrix |
| 28 | Dispute confirmation text is usable | OPEN | Widget/golden/device evidence |
| 29 | KPI cycle opens/closes only for Main Admin | OPEN | Persona RPC + UI tests |
| 30 | Camera preview is correct on Samsung portrait | OPEN | Physical Samsung evidence |
| 31 | Location result has map snapshot and 5-second video | IMPLEMENTED / TEST PENDING | Full response E2E |
| 32 | Executive plays video and opens employee marker | OPEN | Executive device E2E |
| 33 | Executive creates decision, announcement and poll; receives issues | OPEN | CRUD workflow E2E |
| 34 | Offboarding/assets/payroll pages and routes absent on mobile | IMPLEMENTED / TEST PENDING | Route/source/widget tests |
| 35 | Employee changes photo and password | IMPLEMENTED / TEST PENDING | Auth/storage/profile E2E |
| 36 | Invited first login provisions one complete employee record | IMPLEMENTED / TEST PENDING | Replay-safe first-login test |
| 37 | HR manager change affects new requests and writes audit | IMPLEMENTED / TEST PENDING | HR-to-employee workflow E2E |
| 38 | Main Admin securely invites a web manager | OPEN | Invite/first-login E2E |
| 39 | Phone numbers render LTR inside RTL | OPEN | Widget/device screenshot |
| 40 | No PostgREST/Function/SQL/stack text reaches users | IMPLEMENTED / TEST PENDING | Forced-error UI suite |
| 41 | Release uses stable institutional certificate, not debug key | OPEN | `apksigner verify --print-certs` |
| 42 | Trusted-device attendance is marked verified server-side | IMPLEMENTED / TEST PENDING | Physical passkey + DB record |
| 43 | Server failure leaves no partial/duplicate attendance | IMPLEMENTED / TEST PENDING | Migration `0089` fault/replay SQL test |
| 44 | Field monitoring never loads forever and lists everyone | OPEN | Timeout + executive runtime |
| 45 | Same account sees same scoped data on web and mobile | OPEN | Contract comparison |
| 46 | Mobile and web KPI counts match | OPEN | Same-persona comparison |
| 47 | Employee edit updates department/manager and downstream requests | OPEN | Admin workflow E2E |
| 48 | Archive revokes sessions/devices and preserves history | IMPLEMENTED / TEST PENDING | Migration `0090` + auth/device/data runtime |
| 49 | Hard delete requires Main Admin, confirmation, and reason | IMPLEMENTED / TEST PENDING | Migration `0090` persona/confirmation/audit tests |
| 50 | Every notification routes exactly once to its entity | IMPLEMENTED / TEST PENDING | Dedup + route suite |
| 51 | Full-screen location UX remains active and accessible | IMPLEMENTED / TEST PENDING | Android 14/15 lock-screen run |
| 52 | Camera records five seconds without RECORD_AUDIO | IMPLEMENTED / TEST PENDING | APK permission + media inspection |
| 53 | Web has no horizontal overflow at 1366x768 | OPEN | Browser viewport suite |
| 54 | KPI date picker is Arabic and Cairo-time based | OPEN | Locale/timezone test |
| 55 | Creating document template/training updates data and counts | OPEN | CRUD/reload E2E |
| 56 | Leave/mission/convoy/fandi routes to correct manager | OPEN | Four-type persona workflow |
| 57 | Accepted dispute gets assignee and audited workflow | OPEN | Dispute lifecycle E2E |
| 58 | Every disabled control explains why | OPEN | Semantics/widget/visual audit |
| 59 | Launcher, splash, and notifications have no Flutter branding | IMPLEMENTED / TEST PENDING | Release APK/device inspection |
| 60 | Loading, empty, and error states never overlap | OPEN | State-transition widget suite |

## Evidence backlog from V2

- Short runtime capture: GPS off -> settings -> return -> passkey -> attendance saved.
- Short runtime capture: urgent request -> location -> five-second video -> map result -> executive playback.
- Post-fix screenshots for affected phone and web pages.
- Direct database/query evidence that executive employee lists start from `employees`, not attendance events.
- Route tests for every clickable card, icon, and notification.
