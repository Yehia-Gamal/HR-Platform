# Migration Registry — أحلى شباب HR

> سجل شامل لجميع ملفات الترحيل في `supabase/migrations/`.
> آخر تحديث: 2026-08-08 — تثبيت السلسلة النهائية 0001–0337 (335 ملفاً): حسم تكرارات المحتوى (0313/0321، 0322/0327، 0331/0332) بجسور موثقة، واستيعاب 0314 داخل 0317.

## الإحصائيات الفعلية الحالية

| العنصر | العدد |
|---|---|
| إجمالي الملفات `.sql` المرقمة | 335: 0001–0337 (يشمل placeholders الموثقة) |
| تكرارات نشطة | ✅ لا شيء |
| فجوات | ✅ لا شيء (جسور موثقة: 0119, 0122, 0194, 0219, 0231, 0232, 0313, 0322, 0332 — والفجوة 0314 مقبولة ومضمّنة في 0317) |
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
| 0313 | `0313_admin_org_chart_rpc.sql` | جسر موثق — محتوى `get_admin_org_chart` نُقل إلى `0321_admin_org_chart_rpc.sql` (إزالة التكرار بعد إعادة الترتيب). |
| 0322 | `0322_observability_permissions_seed.sql` | جسر موثق — محتوى بذر صلاحيات المراقبة نُقل إلى `0327_observability_permissions_seed.sql`. |
| 0332 | `0332_reload_pgrst_final.sql` | جسر موثق — تكرار محتوى 100% مع `0331_reload_pgrst_final.sql`؛ يُحتفظ به لسلامة الترقيم بلا تنفيذ. |

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
| 0259 | `0259_payroll_dsl_interpreter.sql` | مفسر JSON صرف للأنواع الخمسة المسموحة دون SQL ديناميكي أو lookup. اختبار pgTAP: `0100_payroll_dsl_interpreter.sql`. |
| 0260 | `0260_rls_gap_closure.sql` | إغلاق محافظ لفجوات RLS المتبقية مع حفظ السياسات الدقيقة القائمة. اختبار pgTAP: `0101_rls_gap_closure.sql`. |
| 0261 | `0261_fix_ops_center_guard.sql` | استبدال حارس `tasks.read` الواسع بصلاحيات تشغيل/تقارير إدارية لمركز العمليات. اختبار pgTAP: `0102_ops_center_guard.sql`. |
| 0262 | `0262_fix_payroll_dsl_fail_open.sql` | إغلاق فخ Fail-Open في `payroll_validate_dsl_spec` (نتيجة NULL عند نقص حقل). اختبار pgTAP: `0103_payroll_dsl_fail_closed.sql`. |
| 0263 | `0263_audit_fix_rpc_grants_self_guard.sql` | منح EXECUTE لأربع دوال لوحة إدارة كانت محظورة، وحماية `is_deleted`/`national_id_enc` من التعديل الذاتي، وتحصين `rpc_revoke_role` (أدوار full-access)، وفرض `tasks.write` على مهام لوحة العمليات، وتوسيع بوابة كتالوج المؤسسة. اختبار pgTAP: `0104_audit_fix_rpc_grants_self_guard.sql`. |
| 0264 | `0264_cron_http_from_system_settings.sql` | مهام cron HTTP تقرأ الإعدادات من `system_settings` بدل custom GUC (غير مسموح على Supabase المدارة). |
| 0265 | `0265_restore_live_location_video_verification.sql` | استعادة تدقيق فيديو التحقق من البث الحي: طلب الموقع → دفع عالي الأولوية → موظف يُرسل موقعه + فيديو كاميرا أمامية 5 ثوانٍ. |
| 0266 | `0266_monthly_attendance_full_month_rates_and_day_overrides.sql` | نسب حضور/ساعات الشهر الكامل + تعديلات يومية إدارية مع تدقيق. Friday هو الراحة الأسبوعية الوحيدة؛ الوردية الرسمية 10:00-18:00. |
| 0267 | *(مُعاد ترقيمه إلى `0277` — إصلاح توجيه الروابط العميقة)* | — |
| 0268 | `0268_fix_monthly_attendance_status_labels.sql` | تسميات الإصدارات والمنقولة والإجازات في التحليل اليومي. اختبار pgTAP: `0086_*`. |
| 0269 | `0269_revert_live_location_video_verification.sql` | عكس تفعيل التحقق بالفيديو. |
| 0270–0276 | `027x_bridge_placeholder.sql` | جسور ترقيم أثناء إعادة هيكلة سلسلة الحضور. |
| 0277 | `0277_fix_deep_link_action_routing.sql` | إصلاح توجيه الروابط العميقة (كان 0267). |
| 0278 | `0278_weekly_rest_comp_and_holidays_hardening.sql` | تعويض الراحة الأسبوعية وتحصين العطل. |
| 0279 | *(رقم متخطَّى مقصود — مساحة احتياطية)* | — |
| 0280 | `0280_request_live_location_drop_channel_v4.sql` | طلب الموقع الحي — قناة دفع v4. |
| 0281 | `0281_fix_phone_normalization_and_password_activation.sql` | توحيد تطبيع الهاتف + تفعيل الحساب بكلمة مرور. |
| 0282 | `0282_hard_delete_confirmation_and_manager_guards.sql` | تأكيد الحذف النهائي + حراس تغيير المدير. |
| 0283 | `0283_attendance_day_roster_and_dashboard.sql` | رستر اليوم وحضوره في لوحات الحضور. |
| 0284 | `0284_employee_email_in_360.sql` | البريد في تقرير الموظف 360. |
| 0285 | `0285_update_employee_admin_optional_reason.sql` | جعل سبب التعديل الإداري اختيارياً. |
| 0286 | `0286_restore_full_access_live_location_request.sql` | استعادة الصلاحيات الكاملة لطلب الموقع الحي. |
| 0287 | `0287_monthly_attendance_full_month_finalization.sql` | إنهاء كشف حضور الشهر الكامل. |
| 0288 | `0288_restore_lost_0273_diag_function.sql` | استعادة دالة التشخيص المفقودة (0273). |
| 0289 | `0289_fix_profile_activation_trigger.sql` | إصلاح مُشغّل تفعيل الملف (كان 0294 بعد إعادة الترتيب). |
| 0290 | `0290_fix_kpi_cycle_create_grants_and_diagnostics.sql` | منح إنشاء دورة KPI + تشخيص فشلها (كان 0282_fix_kpi). |
| 0291 | `0291_attendance_formatted_display_fields.sql` | حقول العرض المنسّقة (كان 0290). |
| 0292 | `0292_device_cleanup_admin_delete.sql` | حذف إداري للجهاز (كان 0291). |
| 0293 | `0293_restore_public_employee_avatars_bucket.sql` | استعادة سلة صور الموظفين العامة (كان 0289_restore_public...). |
| 0294 | `0294_attendance_drilldown.sql` | Drill-Down كامل للوحات الحضور — قوائم حقيقية خلف كل رقم. اختبار pgTAP: `0107_attendance_drilldown_roster.sql`. |
| 0295 | `0295_attendance_dashboard_visible_scope.sql` | مطابقة عدّادات لوحة الحضور مع قوائم drill-down (اتساق العدد=القائمة). |
| 0296 | `0296_drop_old_attendance_roster_overload.sql` | إزالة overload القديم `get_attendance_day_roster(date,text)`. |
| 0297 | `0297_bridge_placeholder.sql` | جسر ترقيم — إدخال سجل قديم أشار إلى "announcement_acknowledgers"؛ التحقق: الميزة موجودة فعلياً باسم `announcement_acknowledgements` (الجدول في 0008، `publish_official_announcement`/`acknowledge_announcement` في 0015، الأمان في 0209). لا فقدان. |
| 0298 | `0298_bridge_placeholder.sql` | جسر ترقيم — محتوى تنفيذ المأموريات انتقل إلى `0318_mission_executions.sql`. |
| 0299–0300 | `029x_bridge_placeholder.sql` | جسور ترقيم أثناء إعادة هيكلة سلسلة KPI/الموظف. |
| 0301 | `0301_fix_kpi_admin_grants_and_diagnostics.sql` | منح إدارية KPI + تشخيص الفشل. |
| 0302 | `0302_fix_kpi_cycle_open_now_override.sql` | تجاوز `open_now` في دورة KPI. |
| 0303 | `0303_deny_anon_storage_bucket_list.sql` | منع anon من قراءة `storage.buckets` (HIGH security finding). |
| 0304 | `0304_fix_kpi_cycle_create_grants_only.sql` | منح إنشاء دورة KPI فقط. |
| 0305 | `0305_employee_edit_simplify.sql` | تبسيط تعديل بيانات الموظف ومزامنة البريد مع ملف 360° (كان 0302_employee_edit_simplify — أُعيد ترقيمه لتفادي التكرار). |
| 0306 | `0306_re_add_phone_normalization_to_update_employee.sql` | إعادة تطبيع الهاتف في `update_employee_admin` (كان 0304 — أُعيد ترقيمه لتفادي التكرار). |
| 0307 | `0307_fix_kpi_cycle_open_now_override.sql` | تجاوز `open_now` في دورة KPI (أُعيد ترقيمه من 0302 لتفادي التكرار). |
| 0308 | `0308_fix_kpi_cycle_create_grants_only.sql` | منح إنشاء دورة KPI فقط (أُعيد ترقيمه من 0290 لتفادي التكرار). |
| 0309 | `0309_sync_urgent_channel_v6.sql` | مزامنة قناة الإشعار العاجلة للموقع الحي مع معرف القناة الفعلي v6. |
| 0310 | `0310_request_live_location_drop_channel_v4.sql` | تنظيف hardcoded channel v4 من `request_live_location` (يُطبّعها trigger 0309). |
| 0311 | `0311_unified_avatar_rpc_and_backfill.sql` | صور موحدة عبر `get_employee_photo_url`/`set_my_photo_url` + روابط authenticated. |
| 0312 | `0312_fix_kpi_inbox_relation_field.sql` | إضافة حقل `relation` (self/team/review) إلى `get_kpi_inbox`. |
| 0313 | `0313_admin_org_chart_rpc.sql` | جسر موثق بلا تنفيذ — `get_admin_org_chart` نُقل إلى 0321 (انظر الجسور الموثقة). |
| 0314 | *(فجوة مقبولة — المُدرجة في `ACCEPTABLE_GAPS`)* | تريغر إعفاء الحضور عند اعتماد المأمورية/الإذن دُمج بالكامل في `0317` (create or replace + drop trigger if exists). |
| 0315 | `0315_db_performance_partitioning_mvs.sql` | أداء قاعدة البيانات — partitioning + pg_stat_statements + جدولة تحديث MVs. |
| 0316 | `0316_request_event_notifications.sql` | تغطية إشعارات الطلبات — إعادة إنشاء ملف 0299 (الذي استُبدل بجسر no-op) بعد أن ضاع من المستودع أثناء إعادة الهيكلة؛ يضيف إشعارات لـ 20 حدثاً (submit/decide/cancel request, corrections, rosters, break-glass, privacy, signatures, wellbeing, missions, offboarding…) عبر `create or replace` idempotent. مطبَّق على الإنتاج. |
| 0317 | `0317_fix_hr_bypass_72h_and_attendance_exempt.sql` | إصلاحات على سلسلة 0313–0316: دمج إشعار المعتمِد التالي + رفع تجاوز HR إلى 72 ساعة + توسيع CHECK لـ notifications.category + إصلاح فرع المأمورية في تريغر 0314. |
| 0318 | `0318_mission_executions.sql` | تنفيذ المأموريات (بدء/انتهاء + المدة الفعلية + التقرير) — انتقل من 0298. اختبار pgTAP: `0108_mission_execution_contract.sql`. |
| 0319 | `0319_proactive_location_and_manager_attendance_notify.sql` | إشعارات استباقية للموقع الحي وإشعارات حضور للمدير. |
| 0320 | `0320_attendance_weekend_and_grant_fix.sql` | إصلاح عطلة نهاية الأسبوع (`isWeekend`) + إزالة منح `anon` (تكملة لسلسلة 0294/0295 — انظر أيضًا 0323). |
| 0321 | `0321_admin_org_chart_rpc.sql` | `get_admin_org_chart` — شجرة هرمية حقيقية (نُقل من 0313 لإزالة التكرار). |
| 0322 | `0322_observability_permissions_seed.sql` | جسر موثق بلا تنفيذ — بذر صلاحيات المراقبة نُقل إلى 0327 (انظر الجسور الموثقة). |
| 0323 | `0323_attendance_weekend_and_grant_fix.sql` | توثيق لا تنفيذ — إصلاح عطلة نهاية الأسبوع/منح anon مطبَّق فعلياً في 0320؛ أُبقِي لسلامة الترقيم. |
| 0324 | `0324_fix_employee360_manager_rel.sql` | إصلاح علاقة المدير في تقرير الموظف 360° (كان 0324_new — أُعيد وضعه هنا بعد نقل daily_reports إلى 0328). |
| 0325 | `0325_day_mark_requests_fundraising_retroactive.sql` | **تحديد اليوم بأثر رجعي**: نوع طلب `fundraising` في CHECKs والتسمية؛ استخراج `_submit_request_for(p_employee_id,…)` مع إشعار المدير عند غياب خطوات سير عمل؛ `submit_my_request` يدعم fundraising + `dayMark=true` (ماضٍ من نفس الشهر فقط، يوم واحد)؛ RPC إداري `submit_employee_day_mark` للنيابة مع فحص صلاحيات + منع الشهر المغلق؛ تريجر `trg_fundraising_attendance_exempt` (present عند اعتماد فاندي). |
| 0326 | `0326_limit_hr_override_and_unlimited_sick.sql` | تقييد تدخل HR في `decide_request` (طوارئ بعد مهلة المدير) + إلغاء حد الإجازة المرضية (نُقل من 0313 أثناء إعادة الترتيب). |
| 0327 | `0327_observability_permissions_seed.sql` | بذر صلاحيات المراقبة (observability.read, admin.observability…) ومنحها للأدوار الإدارية (نُقل من 0314/0322 أثناء إعادة الترتيب). |
| 0328 | `0328_daily_reports_public_feed_likes.sql` | التقارير اليومية في الخلاصة العامة + الإعجابات (نُقل من 0324 أثناء إعادة الترتيب). |
| 0329 | `0329_reload_pgrst_schema_cache.sql` | إعادة تحميل ذاكرة مخطط pgrst بعد سلسلة الترحيلات (كشف الدوال الجديدة للـ PostgREST). |
| 0330 | `0330_employee_data_integrity.sql` | سلامة بيانات الموظفين — توحيد/إصلاح بعد إعادة تصميم شجرة المنظمة. |
| 0331 | `0331_reload_pgrst_final.sql` | إعادة تحميل نهائية لذاكرة pgrst بعد الدوال الجديدة (انظر 0332 جسر مكرر). |
| 0332 | `0332_reload_pgrst_final.sql` | جسر موثق بلا تنفيذ — تكرار محتوى 100% مع 0331 (انظر الجسور الموثقة). |
| 0333 | `0333_friday_work_override_and_comp_submission.sql` | العمل يوم الجمعة (الراحة الأسبوعية) + تسليم التعويض. |
| 0334 | `0334_fix_org_chart_include_all_employees.sql` | تضمين جميع الموظفين غير المنتهين في شجرة المنظمة. |
| 0335 | `0335_fix_employee_list_org_admin_sees_all.sql` | مسؤول المنظمة يرى قائمة الموظفين كاملة. |
| 0336 | `0336_fix_executive_secretary_full_access.sql` | إصلاح صلاحية السكرتير التنفيذي (full access). |
| 0337 | `0337_seed_kpi_assessment_permissions.sql` | بذر صلاحيات تقييم KPI. |

| 0338 | `0338_restore_full_access_live_location_request.sql` | استعادة صلاحيات الوصول الكامل لطلب الموقع الحي. |
| 0339 | `0339_fix_account_status_active.sql` | إصلاح حالة الحساب (active). |
| 0340 | `0340_force_all_accounts_active.sql` | إجبار تفعيل جميع الحسابات. |
| 0341 | `0341_fix_get_employee_360_recent_tasks.sql` | إصلاح get_employee_360 (المهام الأخيرة). |
| 0342 | `0342_align_request_live_location_deep_link.sql` | مزامنة رابط طلب الموقع الحي مع deep link. |
| 0343 | `0343_penalties_instapay_audit_settings.sql` | الغرامات + InstaPay + إعدادات التدقيق. |
| 0344 | `0344_grant_knowledge_write.sql` | منح صلاحيات كتابة قاعدة المعرفة. |
| 0345 | `0345_employee_discipline_actions.sql` | جداول إجراءات التأديب. |
| 0346 | `0346_enable_helpdesk_governance_permissions.sql` | تفعيل صلاحيات Helpdesk والحوكمة. |
| 0347 | `0347_open_cron_health_to_authenticated.sql` | فتح صحة cron لـ authenticated. |
| 0348 | `0348_kpi_fix_grants_openflow_inbox_relation.sql` | إصلاح منح KPI + علاقة inbox. |
| 0349 | `0349_complete_rls_all_tables.sql` | RLS شامل لجميع الجداول (bulk grant). |
| 0350 | `0350_attendance_dashboard_dept_branch_manager_filter.sql` | فلتر القسم/الفرع/المدير في لوحة الحضور. |
| 0351 | `0351_fix_checker_found_column_refs.sql` | إصلاح مراجع الأعمدة في دالة التحقق. |
| 0352 | `0352_knowledge_categories_search_manage.sql` | بحث وإدارة تصنيفات المعرفة. |
| 0353 | `0353_fix_notification_deep_link_resolution.sql` | إصلاح حل روابط إشعارات العمق. |
| 0354 | `0354_pending_requests_absence_and_approver_fallback.sql` | الطلبات المعلقة + الغياب + بديل المعتمِد. |
| 0355 | `0355_attendance_derive_all_employees_and_admin_leave_deduction.sql` | احتساب حضور جميع الموظفين + خصم إجازة الإدارة. |
| 0356 | `0356_harden_url_path_validators_leading_ws_and_mixed_slash.sql` | تشديد مدقق المسارات (مسافات بادئة + شرطات مختلطة). |
| 0357 | `0357_analytics_dashboard_rpc.sql` | RPC لوحة التحليلات. |
| 0358 | `0358_announcement_engagement_and_push_nudge.sql` | تفاعل الإعلانات + تنبيه push. |
| 0359 | `0359_restrict_sensitive_read_policies.sql` | تضييق سياسات القراءة الحساسة (رواتب/حوكمة/إجازات). |
| 0360 | `0360_device_auto_accept_registration.sql` | قبول تلقائي لتسجيل الأجهزة. |
| 0361 | `0361_fix_attendance_dashboard_excused_absent.sql` | إصلاح عدّاد excused_absent في لوحة الحضور. |
| 0362 | `0362_attendance_override_leave_type.sql` | تعديل نوع الإجازة في سجل الحضور. |
| 0363 | `0363_delete_v25_test_department.sql` | حذف قسم الاختبار V25. |
| 0364 | `0364_restore_account_status_semantics.sql` | إعادة حالة الحساب الدلالية الحقيقية + تريغر guard. |
| 0365 | `0365_bridge_placeholder.sql` | جسر ترقيم. |
| 0366 | `0366_request_three_tier_delegation_and_sound_notifications.sql` | تفويض ثلاثي المستويات للطلبات + إشعارات صوتية. |
| 0367 | `0367_fundraising_three_tier_and_cron_5min.sql` | جمع التبرعات ثلاثي المستويات + cron كل 5 دقائق. |
| 0368 | `0368_tighten_rls_policies.sql` | تضييق سياسات RLS من bulk grant 0349 (حوكمة/إدارية/مالية). |
| 0369 | `0369_fix_attendance_dashboard_excused_absent.sql` | إصلاح excused_absent في لوحة الحضور (إعادة ترقيم). |
| 0370 | `0370_bridge_placeholder.sql` | جسر ترقيم. |
| 0371 | `0371_device_auto_accept_registration.sql` | قبول تلقائي لتسجيل الأجهزة (إعادة ترقيم). |
| 0372 | `0372_announcement_engagement_and_push_nudge.sql` | تفاعل الإعلانات + push (إعادة ترقيم). |
| 0373 | `0373_restrict_kpi_diag_to_service_role.sql` | **P0**: سحب EXECUTE على `kpi_diag_run` من `authenticated` — SECURITY DEFINER بلا حارس → تسريب schema/UUIDs/stack traces. الإصلاح: service_role فقط. |
| 0374 | `0374_fix_get_employee_360_auth_guard.sql` | **P0**: إضافة فحص صلاحية لـ `get_employee_360` — كانت SECURITY DEFINER بلا أي حارس بعد 0364 → أي موظف يقرأ حالة موظف آخر. الإصلاح: `has_permission('people.employee.read') OR can_access_employee(id)`. |
---

> ⚠️ **مخاطرة مؤجلة (0293 — سلة الصور العامة):** سلة `employee-avatars` عادت إلى `public = true` لإصلاح الصور المكسورة (يُخزَّن `photo_url` كرابط عام `object/public/...` ويُستهلك في الويب والموبايل والـ RPCs). هذا يعكس توصية التدقيق (0056) ويُعرّض صور الموظفين للقراءة العامة.
>
> **الخطة المؤجلة للتراجع الآمن:** 1) سلة خاصة + سياسات RLS على `storage.objects` (قراءة للمصادقين فقط، إدارة للأدمن/المُفوّضين)؛ 2) تحويل جهة القراءة في الويب (`UserAvatar`, `WorkspaceShell`, `EmployeeDetailPage`) والموبايل (`AppAvatar`) إلى `createSignedUrl` مع TTL قصير؛ 3) تحديث عقد `0046_employee_avatar_storage_contract.sql` ليعكس العقد الجديد؛ 4) إبقاء عمود `photo_url` لكن بتخزين المسار بدل الرابط العام مع تحويل البيانات القديمة. يُنفَّذ في migration جديد (لا تعديل على المنشور 0293).

---

> ✅ **الحالة:** سلسلة متصلة — 0001 → 0374 — بلا تكرار أو فجوات.

