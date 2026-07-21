# التعديلات المطبقة على HR_Platform

## ملفات جديدة
- `spec/` — مواصفة V8 واختباراتها وخارطة الطريق.
- `audit/HR_PLATFORM_DEEP_AUDIT_AR.md`.
- `audit/RUNTIME_VERIFICATION_CHECKLIST_AR.md`.
- `supabase/config.toml`.
- `supabase/migrations/0012_core_p0_hardening.sql`.
- `supabase/functions/webauthn-challenge/`.
- `supabase/tests/0001_core_security_structure.sql`.

## ملفات معدلة
- `BUILD_MASTER.md` — إزالة ادعاء الجاهزية غير المثبت وتثبيت المعمارية النهائية.
- `docs/IMPLEMENTATION_PLAN_AR.md` — تصحيح ترتيب 0003/0004 ومسار KPI.
- `supabase/migrations/README.md` — إضافة 0012 وتأجيل Payroll إلى 0013+.
- `supabase/functions/verify-attendance-punch/index.ts` — تقوية WebAuthn والحضور.

## أهم الإصلاحات
- Scope-aware RLS في الجداول الأساسية.
- Recursive management descendants.
- منع INSERT المباشر إلى attendance_events.
- منع الكتابة المباشرة على passkey credentials/challenges.
- Workflow متعدد المراحل بدل إنهائه عند أول موافقة.
- تصحيح البحث عن WebAuthn credential عبر `credential_id` بدل UUID `id`.
- RP ID hash + UP/UV + sign counter + atomic challenge consumption.

## ما لم يُنفذ بعد
- تشغيل migrations فعليًا.
- Persona-based RLS tests كاملة.
- `passkey-register` والتحقق الكامل من attestation.
- Flutter وReact.
- Storage buckets/policies.
- CI/CD وبقية Edge Functions.
- ترحيل البيانات واختبارات الأجهزة.
