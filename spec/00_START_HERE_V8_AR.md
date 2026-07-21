# START HERE — وكيل الذكاء الاصطناعي — Ahla Shabab Management OS V8

أنت مسؤول عن بناء النظام من الصفر، وليس ترقيع النظام القديم.

## اقرأ بالترتيب

1. `AHLA_SHABAB_MANAGEMENT_OS_V8_SINGLE_SOURCE_OF_TRUTH_AR.md`
2. `HR_V2_V8_IMPLEMENTATION_ROADMAP_AR.md`
3. `HR_V2_V8_ACCEPTANCE_SCENARIOS_AR.md`
4. `HR_V2_V7_SQL_P0_REMEDIATION_PLAN_AR.md`
5. الملفات المرجعية القديمة وSQL داخل `sql_draft_do_not_run/` كمرجع فقط.

## القرارات النهائية

- Flutter App واحدة للموظف والمدير والمدير التنفيذي، وWorkspaces حسب الخادم.
- React Web واحدة تضم HR Workspace وMain Admin/Product Operations Workspaces.
- Supabase Backend واحد، وRLS/ABAC هو الحماية الحقيقية.
- المدير التنفيذي يستخدم Executive Workspace من الهاتف، ولا يسجل حضورًا شخصيًا.
- لا Chat داخلي في Release 1؛ Official News & Decisions Feed فقط.
- SQL القديمة Draft وغير مسموح تشغيلها قبل P0 Remediation واختبارات RLS.

## البداية الإلزامية

لا تبدأ UI أولًا. أنشئ:

- Requirements Traceability Matrix.
- Architecture Decisions.
- ERD وData Dictionary.
- Permission/Scope/Field Matrix.
- Workflow and Event Catalog.
- Migration Manifest.
- Test Strategy.
- Release Gates.

ثم نفذ Phase 0 وPhase 1، وبعدها Vertical Slice واحد فقط: إنشاء موظف → حساب وصلاحية → تسجيل دخول → Workspace صحيح → Audit/RLS Tests.

لا تدّعِ نجاح أي اختبار أو Build أو Migration دون تشغيله وإرفاق الدليل.
