# Ahla Shabab V4 end-to-end runtime guide

This guide records the repeatable acceptance procedure. A check is evidence only when the command or physical-device scenario actually ran against the release candidate and its output was retained under `docs/runtime-evidence/`.

## 1. Required configuration

Configure values through local environment/CI secrets; never commit them:

- Supabase URL and publishable key for Flutter/web.
- Supabase CLI access token for deployment.
- `WEBAUTHN_RP_ID`, `WEBAUTHN_RP_NAME`, allowed web/Android origins.
- `FCM_PROJECT_ID` and `FCM_SERVICE_ACCOUNT_JSON` for real push delivery.
- Release keystore path, alias, store password, and key password.
- `CRON_SECRET` for dispatcher/retention invocations.

Use a stable release keystore. Never substitute the Android debug keystore.

## 2. Local backend reset and SQL/RLS suite

```powershell
npx supabase start
npx supabase db reset
npx supabase test db
```

The suite must include persona JWT contexts for employee, manager, HR, executive, Main Admin, unrelated authenticated user, and anonymous user. Retain the TAP output. In particular, run `0040_live_location_executive_runtime.sql` and `0041_v4_location_notification_device_contract.sql`.

## 3. Flutter checks

```powershell
Set-Location apps/mobile_flutter
flutter pub get
flutter analyze --no-pub
flutter test
```

No analyzer error, failing test, indefinite spinner, or raw backend exception is acceptable.

## 4. Signed release build

```powershell
$env:RELEASE_KEYSTORE_PATH='C:\secure\ahla-shabab-release.jks'
$env:RELEASE_KEY_ALIAS='ahla-shabab'
$env:RELEASE_STORE_PASSWORD='<from-secret-store>'
$env:RELEASE_KEY_PASSWORD='<from-secret-store>'
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build\symbols
flutter build appbundle --release --obfuscate --split-debug-info=build\symbols
```

Verify each APK with Android SDK tools:

```powershell
apksigner verify --verbose --print-certs build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
apkanalyzer manifest permissions build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
```

Evidence must show a non-debug, stable certificate; v2/v3 verification; no `RECORD_AUDIO`; no legacy storage permissions; cleartext disabled; backup disabled; and the intended full-screen/notification/location permissions.

## 5. Physical Android device matrix

Use at least Samsung devices covering Android 13, 14, and 15 when available. Before each run record device model, OS, app version/build, certificate SHA-256, network, user/persona, and Cairo timestamp.

### Passkey and attendance

1. Sign in as an invited employee and confirm one employee/profile/leave/KPI setup only.
2. Register a passkey; confirm the UI does not say active before the server response.
3. Confirm matching active rows in `passkey_credentials` and `employee_devices`, both tied to the same employee/user.
4. Turn GPS off and start arrival. Confirm settings opens before biometric verification.
5. Enable GPS and return. Confirm the same pending operation resumes.
6. Complete biometric verification inside the complex; confirm a server-verified arrival and dashboard state.
7. Repeat for departure. Retry the same idempotency key and confirm no duplicate.
8. Attempt outside the geofence, with stale/inaccurate location, mock location, revoked device, and replayed assertion; confirm precise safe error codes and no partial row.

### Urgent location request

1. Sign in on device A as employee and device/browser B as executive.
2. Test notification delivery with A foreground, background, killed, and locked.
3. On Android 14/15 deny then allow full-screen special access and record both the heads-up fallback and allowed full-screen behavior.
4. Tap each notification and confirm it opens that exact authorized request ID once.
5. Turn GPS off, accept the request, enable GPS, and return to the same request.
6. Record with the front camera in portrait. Inspect the resulting MP4: five seconds, no audio track, correct aspect ratio.
7. Repeat using “send location only” after cancelling video.
8. Confirm fresh coordinates, accuracy, reverse-geocoded address, map marker, map snapshot, private video object, and executive playback.
9. Send again at 29 seconds (must reject), then after 30 seconds (must create a new UUID without changing the previous request).
10. Confirm signed URLs expire and the retention job removes video/map artifacts after the configured 24-hour window, with retry/dead-letter evidence for a forced deletion failure.

## 6. Web/mobile administrative workflows

Run each operation with allowed and denied personas:

- Executive: all-person attendance/location directory, employee profile, decision, announcement, poll, dispute decision, map and video.
- Main Admin: KPI cycle open/close, secure manager invite, permanent-delete guard.
- HR: employee edit/archive, department/direct-manager change, provisioning repair, audit record.
- Employee/manager: leave, mission, convoy, fandi, KPI, dispute and notification routing.
- Documents/training: create a real record, reload, and verify list/count changes.

Compare the same account's employee, KPI, request, and attendance counts on Flutter and web. Capture the underlying RPC response to distinguish UI filtering from authorization.

For attendance replay evidence, retain the returned `operationId` and
`correlationId`, repeat the identical request after a simulated response loss,
and verify that the second response has `replayed: true` with the same
`eventId`. Query `attendance_punch_attempts` with the service role and confirm
one attempt and one linked attendance event. Then inject an unexpected failure
inside a disposable test transaction and confirm that challenge `used_at`, the
credential counter, attempt row, and attendance row roll back together.

## 7. Responsive, RTL, and state testing

- Web: 1366x768 and narrower supported widths, with zero horizontal overflow.
- Samsung portrait: camera ratio, SafeArea, keyboard, bottom navigation, dialogs, light/dark contrast.
- Phone numbers remain LTR inside Arabic RTL pages.
- Loading transitions only to data, empty, or retryable error; these states never overlap.
- Every clickable control has a semantic label and route test; every disabled control explains its reason.
- Launcher, splash, and notification icon use Ahla Shabab assets, not Flutter defaults.

## 8. Deployment order

```powershell
npx supabase link --project-ref <project-ref>
npx supabase db push --linked
npx supabase functions deploy passkey-register --project-ref <project-ref>
npx supabase functions deploy webauthn-challenge --project-ref <project-ref>
npx supabase functions deploy verify-attendance-punch --project-ref <project-ref>
npx supabase functions deploy notification-dispatcher --project-ref <project-ref>
npx supabase functions deploy live-location-video-url --project-ref <project-ref>
npx supabase functions deploy retention-cleanup --project-ref <project-ref>
```

After deployment, verify migration versions, deployed function versions, required secret names (not values), PostgREST schema reload, cron jobs, storage policies, and smoke queries. Publish web/mobile only after the matching backend contract is live.

## 9. Evidence and closure

For each acceptance row, retain:

- test ID, date/time, environment, build SHA/version and persona;
- exact commands or physical steps;
- sanitized logs/query results and correlation/request IDs;
- screenshot/video path where visual or lifecycle behavior matters;
- pass/fail and linked defect if failed.

Update `docs/V4_EXECUTION_TRACEABILITY_MATRIX.md` to `ACCEPTED` only after this evidence exists. External prerequisites (FCM service account, institutional signing certificate, physical devices, Play Protect/MDM distribution) must remain explicitly open if unavailable.
