# Migration Registry — أحلى شباب HR

> سجل شامل لجميع ملفات الترحيل في `supabase/migrations/`.
> آخر تحديث: 2026-08-03 — دمج إصلاحات الأمن والحضور وسير الإجازات.

## الإحصائيات الفعلية الحالية

| العنصر | العدد |
|---|---|
| إجمالي الملفات `.sql` المرقمة | 258: 0001–0258 (يشمل placeholders الموثقة) |
| تكرارات نشطة | ✅ لا شيء |
| فجوات | ✅ لا شيء (جسور موثقة: 0119, 0122, 0194, 0219) |
| ملفات مركونة في `_v23_parking/` | ✅ يجب أن تكون فارغة — إن وُجدت تُعاد جدوَلتها عبر Integration Lead |

## السياسة الإلزامية — تجميد الترقيم (Zero-Renumber)

> 🔒 **ممنوع منعًا باتًا** إعادة استخدام أو إعادة ترقيم أي migration سبق دفعه إلى Staging/Production.
> **الترقيم تسلسلي جزافي (monotonic)**: كل ملف جديد يأخذ الرقم التالي الفارغ فقط.

| القاعدة | الإجراء الإلزامي |
|---|---|
| رقم migration جديد | 1) أنشئ الملف في `_v23_parking/NNNN_description.sql`. 2) Integration Lead يتأكد من `npm run check:migrations`. 3) يمنح الرقم التالي المتاح فوراً. |
| اكتشاف تكرار | فشل تلقائي في `check:migrations` + `release-gate`. لا يُسمح بأي commit. |
| فجوة في التسلسل | جسر no-op `[NNNN]_bridge_placeholder.sql` أو إغلاق بالترحيل نفسه إن لم يُدفع بعد. |
| تعديل migration مدفوع | ❌ ممنوع. أنشئ `NNNN_fix_<name>.sql` بترقيم جديد. |
| فحص السلامة | `node scripts/check-migrations-integrity.mjs && node scripts/generate-migrations-manifest.mjs` |

## الأدوات المؤسسية الجديدة (2026-07-30)

| السكربت | الدور |
|---|---|
| `scripts/check-migrations-integrity.mjs` | يكشف التكرار + الفجوات + placeholder غير موثق. مدمج في `check:all`. |
| `scripts/generate-migrations-manifest.mjs` | يولّد SHA-256 manifest لكل ملف (كشف إعادة كتابة). → `supabase/.temp/migrations-manifest.json` |

## الجسور الموثقة — لا تُحذف

| الرقم | الملف | السبب المختصر |
|---|---|---|
| 0119 | `0119_bridge_placeholder.sql` | سد فجوة فقدت أثناء إعادة ترقيم سابقة؛ 0120→0126 دفعت لـ Staging. |
| 0122 | `0122_bridge_placeholder.sql` | سد فجوة بين 0121→0123. |
| 0194 | `0194_placeholder.sql` | محفوظ تاريخياً لسلامة التسلسل. |
| 0219 | `0219_placeholder_sequence_fix.sql` | محفوظ تاريخياً لسلامة التسلسل. |
| 0231 | `0231_bridge_placeholder.sql` | سد فجوة من reset خارجي — 0232→0234 موجودة بالفعل. |
| 0232 | `0232_bridge_placeholder.sql` | سد فجوة من reset خارجي — 0233→0234 موجودة بالفعل. |

## العمليات الحرجة ليوم 2026-07-30

| # | الملف | الغرض |
|---|---|---|
| 0233 | `0233_critical_cron_consolidation.sql` | جدولة موحدة idempotent للمهام الحرجة + فحص صحي يومي + تنبيهات `system_alerts` عند الفقد. |
| 0234 | `0234_revoke_remaining_internal_rpcs.sql` | (موجود) التشديد الأمني على RPC الداخلية. |
| 0235 | `0235_validate_storage_paths_and_urls.sql` | تحقق من مسارات/روابط التخزين (منع data:/file:/traversal). |
| 0236 | `0236_finalize_attendance_selfie_path_scope.sql` | تثبيت نطاق مسار selfie الحضور. |
| 0237 | `0237_fix_work_assignments_rls_recursion.sql` | إصلاح تكرار RLS (42P17) على work_assignments. |
| 0238 | `0238_batch_size_limits_dos_hardening.sql` | حدود حجم الدفعات (batch) لتقليل مخاطر الإرهاق. |
| 0239 | `0239_fix_finalize_selfie_nul_check.sql` | إصلاح فحص NUL في مسار selfie عند الإنهاء. |
| 0240 | `0240_admin_reinstate_device.sql` | إعادة تفعيل جهاز بواسطة المسؤول. |
| 0241 | `0241_device_reinstate_and_reregister_fix.sql` | إصلاح إعادة التفعيل/إعادة التسجيل للأجهزة. |
| 0242 | `0242_repair_runtime_rpcs_and_cron_health.sql` | إصلاح RPCs التشغيلية + صحة cron. |
| 0243 | `0243_validate_announcement_and_kpi_evidence_urls.sql` | تحقق من روابط الإعلانات وأدلة KPI. |
| 0244 | `0244_production_observability_cron_health.sql` | مراقبة الإنتاج + صحة cron. |
| 0245 | `0245_secdef_cross_employee_authz.sql` | حراس صلاحية على دوال SECURITY DEFINER عابرة للموظفين (get_employee_departments…). |
| 0246 | `0246_fix_auth_admin_execute_handle_new_user.sql` | إصلاح EXECUTE لـ handle_new_user (auth admin). |
| 0247 | `0247_harden_cron_http_header_json.sql` | بناء ترويسة `x-cron-secret` كـ JSON آمن عند إعادة جدولة مهام HTTP. |
| 0248 | `0248_admin_reinstate_device.sql` | استعادة RPC إعادة تفعيل الجهاز الإداري. |
| 0249 | `0249_harden_url_path_validators.sql` | تشديد التحقق من المسارات والروابط ضد المسافات السابقة والشرطات المختلطة والاجتياز. |
| 0250 | `0250_harden_external_link_validator.sql` | توحيد تشديد روابط KPI الخارجية مع مدققات المسارات. |
| 0251 | `0251_fix_monthly_attendance_as_of_date.sql` | احتساب تقرير الشهر الحالي حتى تاريخ ووقت التنفيذ دون تحويل المستقبل إلى غياب. |
| 0252 | `0252_attendance_day_detail_explainability.sql` | إضافة تفاصيل تفسيرية لكل يوم في كشف الحضور الشهري. اختبار pgTAP: `0097_attendance_day_detail_explainability.sql`. |
| 0253 | `0253_leave_workflow_and_device_reinstate.sql` | استعادة سير الإجازة ذي الخطوتين وإصلاح دورة إعادة تفعيل الجهاز. اختبار pgTAP: `0098_leave_workflow_two_step.sql`. |
| 0254 | `0254_restrict_employee_departments_read.sql` | تشديد RLS لقراءة ربط الموظفين بالإدارات. |
| 0255 | `0255_payroll_formula_templates_schema.sql` | قائمة أنواع عقد DSL المسموحة وواجهة قراءتها للخدمة فقط. |
| 0256 | `0256_admin_panel_rpc_capability_guards.sql` | **P0**: فحص الصلاحية داخل RPCs لوحة الإدارة. اختبار pgTAP: `0090_admin_panel_rpc_authz.sql`. |
| 0257 | `0257_attendance_rate_exclude_open_shift.sql` | استبعاد الوردية الحالية المفتوحة من مقامي نسب الحضور والالتزام بالساعات. |
| 0258 | `0258_payroll_dsl_security_foundation.sql` | جداول قوالب معادلات الرواتب وموافقاتها مع JSON constraints وRLS/ACL. اختبار pgTAP: `0099_payroll_dsl_validation.sql`. |

---

> ✅ **الحالة:** سلسلة متصلة — 0001 → 0258 — بلا تكرار ولا فجوات نشطة.
