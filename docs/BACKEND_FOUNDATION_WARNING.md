# NOT PRODUCTION READY

لا تُشغّل هذه الحزمة على Production قبل:
1. نجاح `supabase db reset` و`supabase test db` مرتين محليًا.
2. نجاح نفس الخطوات على Staging.
3. إغلاق جميع P0/P1 المذكورة في `audit/HR_PLATFORM_DEEP_AUDIT_AR.md`.
4. اختبار WebAuthn والحضور على أجهزة حقيقية.
5. مراجعة أمنية مستقلة لـRLS وEdge Functions.
