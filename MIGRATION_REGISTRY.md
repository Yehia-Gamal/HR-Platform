# Migration Registry — أحلى شباب HR

> سجل شامل لجميع ملفات الترحيل في `supabase/migrations/`.
> آخر تحديث: 2026-07-30 — إعادة تأهيل المرحلة 0 (الاستقرار المؤسسي).

## الإحصائيات الفعلية الحالية

| العنصر | العدد |
|---|---|
| إجمالي الملفات `.sql` المرقمة | 233: 0001–0231 + 0232 + 0233 + 0234 (يشمل placeholders مرقمة) |
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
| 0247 | `0247_admin_panel_rpc_capability_guards.sql` | **P0**: إضافة فحص الصلاحية داخل RPCs لوحة الإدارة (get_audit_security_data / get_operations_center_data / get_integration_center_data / get_employee_photo_url) — كانت تُسرّب بيانات النظام لأي موظف مسجّل رغم أن 0227 سحب anon فقط. الحارس يطابق سياسات RLS في 0011. اختبار pgTAP: `0088_admin_panel_rpc_authz.sql`. |

---

> ✅ **الحالة:** سلسلة متصلة — 0001 → 0247 — بلا تكرار ولا فجوات نشطة.
