# قائمة التحقق التشغيلية

## Database
- [x] `supabase db reset` ينجح مرتين متتاليتين. (محليًا 2026-07-14، Exit 0 ×2)
- [x] كل migrations 0001→0048 تظهر في migration history. (`max(version)=0048`، 48 صفًا)
- [x] Seed 0001 و0002 يعملان دون صلاحيات مفقودة.
- [x] pgTAP ينجح. (Result: PASS — Files=30, Tests=341, صفر فشل، مرتين متتاليتين)

## RLS Personas (tests/0027 — 23/23 فحص فعلي ✅)
- [x] Employee: self only.
- [x] Direct Manager: direct reports only.
- [x] Department Manager: department only.
- [x] HR: organization read؛ لا إدراج مباشر (Provisioning RPC فقط).
- [x] Executive: قراءة المنظمة؛ لا بصمة حضور شخصية عبر Trusted RPC.
- [ ] Admin/Main Admin: full access with MFA/audit؛ no executive impersonation. (منطق الوصول الكامل عبر `current_is_full_access`؛ يُغطى ببيئة Staging بحسابات فعلية)

## Workflow
- [x] First approval activates next step. (منطق `decide_request` متعدد المراحل؛ tests/0027 يثبت اعتماد المدير المباشر)
- [x] Self-approval is rejected. (tests/0027 فحص 4 → 42501)
- [ ] Reject closes the request. (منطق موجود؛ يُغطى بسيناريو Runtime إضافي على Staging)
- [ ] Concurrent retries remain idempotent. (يُختبر تحت حمل على Staging)

## Attendance/WebAuthn
- [x] No direct authenticated INSERT into attendance_events. (tests/0010 + 0027؛ 0045 يسحب الكتابة المباشرة)
- [x] Challenge single-use + expiry منطق. (tests/0012 أمان Passkey/التحدي)
- [x] لا كتابة مباشرة على passkey_credentials/webauthn_challenges للدور authenticated. (tests/0012 + 0045)
- [ ] RP ID hash, origin, user presence والتحقق على جهاز فعلي. (Edge Function `verify-attendance-punch`؛ يتطلب جهازًا فعليًا — BLOCKED)
- [ ] Sign counter replay detection على جهاز فعلي. (منطق موجود؛ يتطلب جهازًا)
- [ ] Geofence/accuracy على جهاز فعلي. (BLOCKED — لا جهاز)

## Release evidence
- [ ] Flutter/React builds are signed/production.
- [ ] Accessibility and RTL tested.
- [ ] Backup restore drill passed.
- [ ] Rollback tested.
- [ ] No P0/P1 open.
