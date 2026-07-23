# Database tests

تحتوي الحزمة على 47 ملف اختبار pgTAP/SQL مرتبة بأرقام متسلسلة حتى `0047`:

1. `0001_core_security_structure` — الأمان البنيوي ومنع الكتابة المباشرة.
2. `0002_foundation_contracts` — عقود Foundation وإنشاء الموظف.
3. `0003_operational_workspaces` — Workspaces التشغيلية.
4. `0004_management_overviews` — لوحات الإدارة.
5. `0005_live_location_flow` — الموقع والتتبع والفيديو.
6. `0006_request_self_service` — الطلبات الذاتية والتحقق الخادمي.
7. `0007_kpi_attendance_mobile` — KPI والحضور للموبايل.
8. `0008_mobile_details_routing` — تفاصيل الإجراءات والـDeep Links.
9. `0009_mobile_daily_workspaces` — الملف والمهام والفريق والتقارير اليومية.
10. `0010_passkey_revoke_attendance_history` — إلغاء Passkeys وسجل الحضور.
11. `0011_mobile_notifications_contract` — الإشعارات وروابط الإجراءات.
12. `0012_passkey_mobile_action_security` — أمان Passkey ومسارات الموبايل.
13. `0013_admin_operations` — إدارة الهيكل والأدوار والتوظيف وOnboarding ومنع الكتابة المباشرة.
14. `0014_leave_ledger_contract` — سجل أرصدة الإجازات.
15. `0015_decision_lifecycle_contract` — دورة حياة القرارات.
16. `0016_attendance_operations_contract` — عمليات الحضور.
17. `0017_kpi_advanced_contract` — KPI المتقدم.
18. `0018_dispute_committee_contract` — النزاعات واللجان.
19. `0019_lifecycle_contract` — دورة الحياة الوظيفية.
20. `0020_enterprise_talent_learning_contract` — المواهب والتعلّم المؤسسي.
21. `0021_enterprise_management_modules` — وحدات الإدارة المؤسسية.
22. `0022_workforce_payroll_engagement_contract` — القوى العاملة والرواتب والمشاركة.
23. `0023_retention_privacy_contract` — الاحتفاظ والخصوصية.
24. `0024_release_access_privacy_integration_governance` — حوكمة الإصدار والوصول والخصوصية والتكامل.
25. `0025_identifier_login_security` — أمان الدخول بمعرّف متعدد.
26. `0026_release_0_10_contract` — عقد إصدار Build 0.10.0.
27. `0027_persona_rls_runtime` — **Persona RLS Runtime Matrix**: سياقات JWT فعلية لتسعة Personas (موظف/زميل/مدير مباشر/مدير إدارة/HR/تنفيذي/لجنة/مصادق غير مخول/مجهول) ضد RLS وRPCs مباشرة (23 فحصًا فعليًا).
28. `0028_recruitment_interviews_offers_hire` — عقد RPCs التوظيف: التواقيع الدقيقة وSECURITY DEFINER والمنح لجدولة المقابلات والعروض والتعيين (Migration 0044).
29. `0029_break_glass_runtime` — **Break-glass Runtime Lifecycle**: طلب → منع الموافقة الذاتية (Four-eyes) → موافقة معتمِد آخر → دور مؤقت فعّال → انتهاء آلي وسحب الدور عبر `expire_break_glass_access` (9 فحوصات حية).
30. `0030_leave_accrual_scheduling` — **الاستحقاق الشهري للإجازات** (Migration 0047): وجود الحقل والدالة، حماية `service_role`، صحة الحساب، عدم تجاوز الحد السنوي، وسلامة idempotency عند تكرار التشغيل (8 فحوصات حية).
31. `0031_audit_remediation_runtime` — اختبارات Runtime لإصلاحات التدقيق والأمان والصلاحيات.
32. `0032_audit_remediation_p2` — عقود إصلاحات التدقيق ذات الأولوية الثانية.
33. `0033_observability_alerting` — المراقبة والتنبيهات وقواعد تسجيل الأحداث.
34. `0034_audit_remediation_p3_ledger` — عقود دفتر التدقيق وإصلاحات الأولوية الثالثة.
35. `0035_official_kpi_governance` — حوكمة KPI الرسمية ومراحلها وصلاحياتها.
36. `0036_official_kpi_runtime` — سيناريوهات Runtime لمسار KPI الرسمي.
37. `0037_dispute_committee_runtime` — سيناريوهات Runtime للجنة حل المشكلات.
38. `0038_leave_workflow_contract` — **نظام الإجازات الجديد** (0060/0061/0062): الكوتا القانونية (15/6/24)، منع الوضع/رعاية الطفل، قاعدة الـ30 يومًا (سن>50 أو خبرة>10 سنوات)، تحديد المدير المسؤول ومنع الموافقة الذاتية، ووجود دوال التصعيد وصلاحيات السكرتير التنفيذي (24 فحصًا).
39. `0039_work_assignments_contract` — **تكليفات العمل** (0063/0065/0066): إنشاء مأمورية/قافلة/فاندي، المأمورية بالساعات، منع تكليف موظف خارج الفريق، إثبات حي أن التكليفات لا تخصم من رصيد الإجازات، وأن الإجازة الاعتيادية تحجز الرصيد والعارضة تُنفَّذ وتُخصم فورًا (18 فحصًا).
40. `0040_live_location_executive_runtime` — **رحلة المدير التنفيذي لطلب الموقع الحي + فيديو** (Migration 0067): سياقات JWT فعلية (تنفيذي/مدير عمليات/موظف هدف/زميل/غير مخوّل) ضد صلاحيات الطلب حسب النطاق، التحقق من الأوضاع، الوضع المدمج `location_video` (نقطة + فيديو دون إنهاء مبكر)، دورة الاستجابة/النقطة/الفيديو، قراءة النتيجة مع التدقيق وسجل الوصول، عزل RLS، وبوابة الحفظ الإداري (36 فحصًا حيًّا).
41. `0041_v4_location_notification_device_contract` — عقد إشعار الموقع والجهاز الموثوق.
42. `0042_atomic_attendance_contract` — عقد الإنهاء الذري للحضور.
43. `0043_employee_archive_delete_contract` — عقد الأرشفة والحذف المحمي للموظف.
44. `0044_release_0_11_1_deep_audit_contract` — عقد إصلاحات تدقيق الإصدار 0.11.1.
45. `0045_v10_six_role_acceptance` — قبول الأدوار الستة ومسارات الموظف والمدير وOperations والمدير التنفيذي وHR والسكرتير التنفيذي.
46. `0046_employee_avatar_storage_contract` — تخزين صور الموظفين وحدود RLS والصلاحيات.
47. `0047_kpi_validation_array_initialization` — تثبيت نوع مصفوفة أخطاء التحقق من KPI ومنع تحذير `plpgsql_check`.

تشغيلها يتطلب Supabase محليًا:

```bash
npx supabase start
npx supabase db reset
npx supabase test db
```

الاختبارات البنيوية لا تستبدل اختبارات Personas الفعلية. قبل Production يجب إثبات السيناريوهات التالية على Local وStaging:

- الموظف لا يقرأ موظفًا آخر.
- المدير المباشر يرى مرؤوسيه فقط.
- مدير الإدارة يرى نطاقه وفق ABAC.
- HR لا يصل إلى أسرار Main Admin.
- المدير التنفيذي لا ينفذ بصمة شخصية.
- لا توجد موافقة ذاتية.
- الموافقة الأولى تفتح الخطوة التالية ولا تنهي المسار.
- تحدي WebAuthn لا يُستهلك مرتين.
- الفيديو والموقع لا يُقبلان دون طلب نشط وموافقة.
- الكتابة على الإدارات والمناصب والأدوار والتوظيف وOnboarding تتم عبر RPCs المصرح بها فقط.
