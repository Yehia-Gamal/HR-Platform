# HR Platform V8 — Reviewed Foundation

هذه الحزمة أساس Backend مُراجع، وليست النظام الكامل.

## ابدأ هنا
1. `spec/00_START_HERE_V8_AR.md`
2. `spec/01_V8_SINGLE_SOURCE_OF_TRUTH_AR.md`
3. `audit/HR_PLATFORM_DEEP_AUDIT_AR.md`
4. `supabase/migrations/README.md`

## المعمارية المعتمدة
- تطبيق Flutter واحد: Employee / Manager / Executive Workspaces بالصلاحيات.
- React Web واحدة: HR Workspace + Main Admin Workspace.
- Supabase Backend واحد.

## تحذير
لا تستخدم Production قبل نجاح migrations والاختبارات مرتين على Local/Staging. لا تعتبر عبارات الجاهزية القديمة دليلًا على التشغيل.
