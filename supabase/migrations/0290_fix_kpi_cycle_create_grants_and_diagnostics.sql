-- =====================================================================
-- 0282_fix_kpi_cycle_create_grants_and_diagnostics.sql
-- =====================================================================
-- الجذر المؤكد لعطلَي واجهة «تجهيز دورة KPI» (الأكواد 9A15C484 / 930B96FA):
--
-- 0214_fix_kpi_admin_fullaccess_authz.sql أعاد تعريف create_kpi_cycle_admin
-- إلى توقيع 8-معاملات (بإضافة p_use_parallel_flow)، و0214 عدّل أيضًا
-- manage_kpi_cycle / reschedule_kpi_cycle / decide_kpi_appeal /
-- get_kpi_cycle_report — كلها باستخدام CREATE OR REPLACE (التوقيع نفسه).
--
-- لكن 0214 لم يُصدِر أي REVOKE/GRANT بعد الاستبدال، في حين أن GRANT الوحيد
-- المنشور سابقًا على create_kpi_cycle_admin كان على التوقيع القديم 7-معاملات
-- من 0058. أي أن التوقيع الثماني المنشور حاليًا لا يملك EXECUTE لـ
-- authenticated على الإطلاق → أي ضغطة «تجهيز الدورة» تُسقط بـ
-- PostgREST 401 / SQLSTATE 42501 "permission denied for function
-- create_kpi_cycle_admin"، وهو ما يراه المستخدم كفقاعة «حدث خطأ غير متوقع».
--
-- ما يفعله هذا الـ migration:
--   (1) يُسقط التوقيع القديم 7-معاملات من create_kpi_cycle_admin (إن بقي)
--       لإزالة غموض التحميل الزائد (overload ambiguity).
--   (2) يضيف REVOKE/GRANT صريحة ومتسقة على التوقيعات الحقيقية الثمانية
--       لكل الدوال التي تستخدمها الواجهة.
--   (3) يُصدِر NOTIFY pgrst, 'reload schema' لإجبار PostgREST على تحديث
--       الذاكرة التخزينية فورًا (يحل 930B96FA بدون إعادة تشغيل).
--   (4) يُنشئ الدالة التشخيصية public.kpi_diag_run (jsonb) التي يمكن لأي
--       مشرف تنفيذها في أي وقت لتقرير فوري عن صحة الدوال والمنح.
--   (5) يُنشئ create_kpi_cycle_admin_safe التي تعيد سبب الفشل بالعربية.
--
-- Idempotent: كل عبارات REVOKE/GRANT/DROP آمنة التكرار.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1) إزالة أي overload قديم لـ create_kpi_cycle_admin (7 وسيطات)
--    الذي قد يكون عالقًا من 0029/0058 ويشوش على PostgREST.
-- ---------------------------------------------------------------------
drop function if exists public.create_kpi_cycle_admin(date, uuid, timestamptz, timestamptz, timestamptz, timestamptz, boolean);

-- ---------------------------------------------------------------------
-- 2) منح authenticated على التوقيعات الحقيقية الثمانية والأخرى الحديثة
-- ---------------------------------------------------------------------

-- create_kpi_cycle_admin (0214 — 8 معاملات)
revoke execute on function public.create_kpi_cycle_admin(date, uuid, timestamptz, timestamptz, timestamptz, timestamptz, boolean, boolean) from public, anon;
grant  execute on function public.create_kpi_cycle_admin(date, uuid, timestamptz, timestamptz, timestamptz, timestamptz, boolean, boolean) to authenticated;

-- get_kpi_admin_catalog
revoke execute on function public.get_kpi_admin_catalog(date) from public, anon;
grant  execute on function public.get_kpi_admin_catalog(date) to authenticated;

-- manage_kpi_cycle
revoke execute on function public.manage_kpi_cycle(uuid, text, text, timestamptz) from public, anon;
grant  execute on function public.manage_kpi_cycle(uuid, text, text, timestamptz) to authenticated;

-- reschedule_kpi_cycle
revoke execute on function public.reschedule_kpi_cycle(uuid, timestamptz, timestamptz, text) from public, anon;
grant  execute on function public.reschedule_kpi_cycle(uuid, timestamptz, timestamptz, text) to authenticated;

-- decide_kpi_appeal
revoke execute on function public.decide_kpi_appeal(uuid, text, text) from public, anon;
grant  execute on function public.decide_kpi_appeal(uuid, text, text) to authenticated;

-- refresh_kpi_attendance_inputs
revoke execute on function public.refresh_kpi_attendance_inputs(uuid) from public, anon;
grant  execute on function public.refresh_kpi_attendance_inputs(uuid) to authenticated;

-- get_kpi_cycle_report
revoke execute on function public.get_kpi_cycle_report(uuid) from public, anon;
grant  execute on function public.get_kpi_cycle_report(uuid) to authenticated;

-- send_kpi_notifications_admin
revoke execute on function public.send_kpi_notifications_admin(uuid) from public, anon;
grant  execute on function public.send_kpi_notifications_admin(uuid) to authenticated;

-- create_kpi_policy_version — نبحث عن توقيعها الحالي ديناميكياً
do $$
declare
  v_sig text;
begin
  select pg_get_function_identity_arguments(p.oid)
  into v_sig
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'create_kpi_policy_version'
  order by p.oid desc
  limit 1;

  if v_sig is not null then
    execute format('revoke execute on function public.create_kpi_policy_version(%s) from public, anon', v_sig);
    execute format('grant  execute on function public.create_kpi_policy_version(%s) to authenticated', v_sig);
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 3) إجبار PostgREST على إعادة تحميل الـ schema cache فورًا
--    للتخلص من 930B96FA بدون restart أو نشر جديد.
-- ---------------------------------------------------------------------
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------
-- 4) دالة التشخيص — kpi_diag_run
--    تُعيد jsonb يُجيب على خمسة أسئلة في ثانية واحدة:
--      أ) هل كل الدوال المطلوبة موجودة؟
--      ب) هل كل الجداول/الأعمدة موجودة؟
--      ج) هل يملك authenticated EXECUTE على الدوال الحرجة؟
--      د) هل القالب الرسمي والسياسة النشطة متوفران؟
--      هـ) ماذا يحدث عند استدعاء الدالتين فعليًا (محمي بـROLLBACK)؟
-- ---------------------------------------------------------------------
create or replace function public.kpi_diag_run(p_month date default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_month         date := coalesce(p_month, date_trunc('month', (now() at time zone 'Africa/Cairo'))::date);
  v_report        jsonb := '{}'::jsonb;
  v_template_id   uuid;
  v_policy_id     uuid;
  v_missing_funcs text[];
  v_missing_tbls  text[];
  v_missing_cols  jsonb;
  v_grants        jsonb;
  v_cycle_attempt text;
  v_catalog_attempt text;
  v_sqlstate      text;
  v_sqlerrm       text;
  v_ctx           text;
  v_dummy_cycle_id uuid;
begin
  -- أ) الدوال المساعدة + دوال KPI الحرجة
  select coalesce(array_agg(fname order by fname), '{}'::text[]) into v_missing_funcs
  from (
    values
      ('current_is_full_access'),
      ('current_is_executive_secretary'),
      ('current_is_hr_reviewer'),
      ('current_employee_id'),
      ('has_any_permission'),
      ('has_permission'),
      ('can_access_employee'),
      ('kpi_effective_deadline'),
      ('log_audit_event'),
      ('refresh_kpi_attendance_inputs'),
      ('generate_kpi_cycle_notifications'),
      ('get_kpi_admin_catalog'),
      ('create_kpi_cycle_admin'),
      ('manage_kpi_cycle'),
      ('reschedule_kpi_cycle'),
      ('decide_kpi_appeal'),
      ('get_kpi_cycle_report'),
      ('send_kpi_notifications_admin'),
      ('create_kpi_policy_version')
  ) as t(fname)
  where not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = t.fname
  );
  v_report := jsonb_set(v_report, '{missingFunctions}', to_jsonb(v_missing_funcs), true);

  -- ب) الجداول
  select coalesce(array_agg(tname order by tname), '{}'::text[]) into v_missing_tbls
  from (
    values
      ('kpi_templates'),('kpi_criteria'),('kpi_cycles'),('kpi_evaluations'),
      ('kpi_scores'),('kpi_attendance_snapshots'),('kpi_policy_versions'),
      ('kpi_appeals'),('employees'),('attendance_daily'),('attendance_permits'),
      ('attendance_exceptions'),('attendance_corrections'),('attendance_events'),
      ('roster_days'),('leave_requests'),('requests'),('missions'),
      ('work_assignment_participants'),('work_assignments'),('shifts'),
      ('audit_events'),('user_roles'),('roles')
  ) as t(tname)
  where not exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = t.tname and c.relkind in ('r','p')
  );
  v_report := jsonb_set(v_report, '{missingTables}', to_jsonb(v_missing_tbls), true);

  -- ج) الأعمدة الحرجة
  with required(tbl, col) as (
    values
      ('kpi_templates','official_code'),('kpi_templates','is_active'),
      ('kpi_cycles','period_month'),('kpi_cycles','template_id'),('kpi_cycles','scheduled_open_at'),
      ('kpi_cycles','deadline_at'),('kpi_cycles','self_due_at'),('kpi_cycles','manager_due_at'),
      ('kpi_cycles','secretary_due_at'),('kpi_cycles','executive_due_at'),('kpi_cycles','opened_at'),
      ('kpi_cycles','opened_by'),('kpi_cycles','policy_version_id'),('kpi_cycles','use_parallel_flow'),
      ('kpi_cycles','locked_at'),('kpi_cycles','override_reason'),
      ('kpi_evaluations','employee_id'),('kpi_evaluations','cycle_id'),('kpi_evaluations','template_id'),
      ('kpi_evaluations','stage'),('kpi_evaluations','current_stage'),('kpi_evaluations','workflow_status'),
      ('kpi_evaluations','locked'),('kpi_evaluations','final_score'),('kpi_evaluations','final_rating'),
      ('kpi_policy_versions','is_active'),('kpi_policy_versions','attendance_rules'),('kpi_policy_versions','rating_bands'),
      ('kpi_scores','reviewer_stage'),('kpi_attendance_snapshots','evaluation_id'),
      ('employees','is_active'),('employees','is_deleted'),('employees','user_id'),('employees','status'),
      ('attendance_daily','employee_id'),('attendance_daily','work_date'),('attendance_daily','shift_id'),
      ('attendance_daily','late_minutes'),('attendance_daily','early_leave_minutes'),
      ('attendance_daily','work_minutes'),('attendance_daily','status'),
      ('attendance_daily','first_check_in'),('attendance_daily','last_check_out'),
      ('shifts','crosses_midnight'),('shifts','end_time'),('shifts','start_time'),('shifts','break_minutes'),
      ('work_assignment_participants','assignment_id'),
      ('work_assignments','counts_as_work_day'),('work_assignments','start_at'),
      ('work_assignments','end_at'),('work_assignments','status')
  )
  select coalesce(jsonb_agg(jsonb_build_object('table', tbl, 'column', col) order by tbl, col), '[]'::jsonb)
  into v_missing_cols
  from required
  where not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = required.tbl and column_name = required.col
  );
  v_report := jsonb_set(v_report, '{missingColumns}', v_missing_cols, true);

  -- د) القالب والسياسة
  select id into v_template_id from public.kpi_templates where official_code = 'OFFICIAL_KPI_100' and is_active limit 1;
  select id into v_policy_id   from public.kpi_policy_versions where is_active limit 1;
  v_report := jsonb_set(v_report, '{officialTemplateId}', to_jsonb(v_template_id), true);
  v_report := jsonb_set(v_report, '{activePolicyId}',     to_jsonb(v_policy_id),    true);

  -- هـ) صلاحيات EXECUTE على كل التوقيعات المنشورة
  with fn(sig_label, args) as (
    values
      ('get_kpi_admin_catalog(date)',
        'public.get_kpi_admin_catalog(date)'),
      ('create_kpi_cycle_admin(8 args)',
        'public.create_kpi_cycle_admin(date,uuid,timestamptz,timestamptz,timestamptz,timestamptz,boolean,boolean)'),
      ('manage_kpi_cycle(uuid,text,text,timestamptz)',
        'public.manage_kpi_cycle(uuid,text,text,timestamptz)'),
      ('reschedule_kpi_cycle(uuid,timestamptz,timestamptz,text)',
        'public.reschedule_kpi_cycle(uuid,timestamptz,timestamptz,text)'),
      ('decide_kpi_appeal(uuid,text,text)',
        'public.decide_kpi_appeal(uuid,text,text)'),
      ('refresh_kpi_attendance_inputs(uuid)',
        'public.refresh_kpi_attendance_inputs(uuid)'),
      ('get_kpi_cycle_report(uuid)',
        'public.get_kpi_cycle_report(uuid)'),
      ('send_kpi_notifications_admin(uuid)',
        'public.send_kpi_notifications_admin(uuid)'),
      ('kpi_diag_run(date)',
        'public.kpi_diag_run(date)')
  )
  select jsonb_object_agg(
    sig_label,
    jsonb_build_object(
      'authenticated', coalesce(has_function_privilege('authenticated', args, 'EXECUTE'), false),
      'service_role',  coalesce(has_function_privilege('service_role', args, 'EXECUTE'), false)
    )
  ) into v_grants from fn;
  v_report := jsonb_set(v_report, '{grants}', v_grants, true);

  -- و) نبضة بسيطة — استدعاء get_kpi_admin_catalog الحقيقي
  begin
    perform public.get_kpi_admin_catalog(v_month);
    v_catalog_attempt := 'OK';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_sqlerrm = message_text, v_ctx = pg_exception_context;
    v_catalog_attempt := format('ERR %s: %s | %s', v_sqlstate, v_sqlerrm, v_ctx);
  end;
  v_report := jsonb_set(v_report, '{catalogCall}', to_jsonb(v_catalog_attempt), true);

  -- ز) نبضة بسيطة — استدعاء create_kpi_cycle_admin الحقيقي مع فرض rollback
  if v_template_id is not null and v_policy_id is not null then
    begin
      v_dummy_cycle_id := public.create_kpi_cycle_admin(
        p_month             := v_month,
        p_template_id       := v_template_id,
        p_self_due          := now(),
        p_manager_due       := now(),
        p_secretary_due     := now(),
        p_executive_due     := now(),
        p_open_now          := false,
        p_use_parallel_flow := false
      );
      -- النجاح يلزمنا بالتراجع حتى لا نُنشئ دورة وهمية
      raise exception '__DIAG_FORCE_ROLLBACK__ cycle_id=%', v_dummy_cycle_id using errcode = 'P0001';
    exception when others then
      get stacked diagnostics v_sqlstate = returned_sqlstate, v_sqlerrm = message_text, v_ctx = pg_exception_context;
      if v_sqlerrm like '__DIAG_FORCE_ROLLBACK__%' then
        v_cycle_attempt := 'OK — نجحت الدالة (لم تُحفظ الدورة بسبب التراجع التشخيصي)';
      else
        v_cycle_attempt := format('ERR %s: %s | %s', v_sqlstate, v_sqlerrm, v_ctx);
      end if;
    end;
  else
    v_cycle_attempt := 'SKIPPED — لا قالب رسمي نشط أو لا سياسة نشطة';
  end if;
  v_report := jsonb_set(v_report, '{createCycleCall}', to_jsonb(v_cycle_attempt), true);

  -- metadata
  v_report := jsonb_set(v_report, '{month}', to_jsonb(v_month), true);
  v_report := jsonb_set(v_report, '{diagAt}', to_jsonb(now()), true);
  v_report := jsonb_set(v_report, '{diagVersion}', to_jsonb('0282_v1'::text), true);
  return v_report;
end $$;

comment on function public.kpi_diag_run(date) is
  'فحص شامل لأسباب فشل KPI cycles على التطبيق. يعيد jsonb بتقرير كامل عن الدوال والجداول والأعمدة والمنح واستدعاء حقيقي محمي بـROLLBACK. منشأ بواسطة 0282.';

revoke execute on function public.kpi_diag_run(date) from public, anon;
grant  execute on function public.kpi_diag_run(date) to authenticated, service_role;

-- ---------------------------------------------------------------------
-- 5) create_kpi_cycle_admin_safe — نسخة محمية تعيد سبب الفشل بالعربية
--    بدلاً من السماح للهيكل بالانهيار مع رمز عشوائي.
-- ---------------------------------------------------------------------
create or replace function public.create_kpi_cycle_admin_safe(
  p_month date,
  p_template_id uuid,
  p_self_due timestamptz,
  p_manager_due timestamptz,
  p_secretary_due timestamptz,
  p_executive_due timestamptz,
  p_open_now boolean default true,
  p_use_parallel_flow boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
  v_sqlstate text;
  v_sqlerrm  text;
  v_ctx      text;
  v_hint     text;
  v_ar_msg   text;
begin
  -- فحص مسبق سريع لأوضح أسباب الفشل
  if not (public.current_is_full_access() or public.current_is_executive_secretary()) then
    return jsonb_build_object('ok', false, 'errorAr',
      'ليس لديك صلاحية إنشاء دورة KPI. تحتاج دور full-access أو سكرتير تنفيذي.',
      'code', 'FORBIDDEN');
  end if;

  if not exists (select 1 from public.kpi_templates where id = p_template_id and official_code = 'OFFICIAL_KPI_100' and is_active) then
    return jsonb_build_object('ok', false, 'errorAr',
      'القالب الرسمي OFFICIAL_KPI_100 غير موجود أو غير نشط.',
      'code', 'NO_TEMPLATE');
  end if;

  if not exists (select 1 from public.kpi_policy_versions where is_active) then
    return jsonb_build_object('ok', false, 'errorAr',
      'لا توجد سياسة KPI نشطة.',
      'code', 'NO_POLICY');
  end if;

  -- محاولة الإنشاء الحقيقية
  begin
    v_id := public.create_kpi_cycle_admin(
      p_month             := p_month,
      p_template_id       := p_template_id,
      p_self_due          := p_self_due,
      p_manager_due       := p_manager_due,
      p_secretary_due     := p_secretary_due,
      p_executive_due     := p_executive_due,
      p_open_now          := p_open_now,
      p_use_parallel_flow := p_use_parallel_flow
    );
    return jsonb_build_object('ok', true, 'cycleId', v_id);
  exception when others then
    get stacked diagnostics
      v_sqlstate = returned_sqlstate,
      v_sqlerrm  = message_text,
      v_ctx      = pg_exception_context,
      v_hint     = pg_exception_hint;

    -- ترجمة الرموز الشائعة إلى عربية محددة للمستخدم
    v_ar_msg := case
      when v_sqlstate = '42501' then 'ليس لديك صلاحية. تأكد من دورك في جدول user_roles.'
      when v_sqlstate = '23505' then 'توجد دورة مسجلة لهذا الشهر بالفعل.'
      when v_sqlstate = '23503' then 'يوجد مرجع مكسور في البيانات (employee أو template غير صالح).'
      when v_sqlstate = '23502' then 'حقل مطلوب فارغ في قاعدة البيانات. راجع إعدادات النموذج.'
      when v_sqlstate = '23514' then 'قيمة تنتهك قيد تحقق في قاعدة البيانات. راجع بيانات الموظفين.'
      when v_sqlstate = '22023' then 'قيمة غير صالحة مرسلة للدالة. تأكد من التواريخ.'
      when v_sqlstate = '42883' then 'الدالة غير موجودة بالتوقيع المطلوب — أعد تحميل schema cache للـ PostgREST.'
      when v_sqlstate = '42P01' then 'جدول مفقود في قاعدة البيانات: ' || coalesce(v_sqlerrm, '')
      when v_sqlstate = '42703' then 'عمود مفقود في قاعدة البيانات: ' || coalesce(v_sqlerrm, '')
      when v_sqlstate = 'P0002' then 'لم يُعثر على سجل: ' || coalesce(v_sqlerrm, '')
      else 'خطأ غير متوقع: ' || coalesce(v_sqlstate, '?') || ' — ' || coalesce(left(v_sqlerrm, 200), '')
    end;

    return jsonb_build_object(
      'ok', false,
      'errorAr', v_ar_msg,
      'code', coalesce(v_sqlstate, 'UNKNOWN'),
      'detail', left(coalesce(v_sqlerrm, ''), 500),
      'hint', left(coalesce(v_hint, ''), 500),
      'context', left(coalesce(v_ctx, ''), 500)
    );
  end;
end $$;

comment on function public.create_kpi_cycle_admin_safe(date, uuid, timestamptz, timestamptz, timestamptz, timestamptz, boolean, boolean) is
  'نسخة محمية من create_kpi_cycle_admin تعيد سبب الفشل بالعربية بدل رفع خطأ غير معروف. منشأة بواسطة 0282.';

revoke execute on function public.create_kpi_cycle_admin_safe(date, uuid, timestamptz, timestamptz, timestamptz, timestamptz, boolean, boolean) from public, anon;
grant  execute on function public.create_kpi_cycle_admin_safe(date, uuid, timestamptz, timestamptz, timestamptz, timestamptz, boolean, boolean) to authenticated;

-- ---------------------------------------------------------------------
-- 6) إعادة تحميل schema cache لـ PostgREST
-- ---------------------------------------------------------------------
notify pgrst, 'reload schema';

commit;
