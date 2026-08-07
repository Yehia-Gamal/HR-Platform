-- =====================================================================
-- 0290_fix_kpi_cycle_create_grants_only.sql
-- =====================================================================
-- الإصلاح الجذري لخطأ "تجهيز دورة KPI" (9A15C484 / 930B96FA):
-- 0214 أعاد تعريف create_kpi_cycle_admin إلى 8 معاملات لكن لم يُصدِر
-- GRANT EXECUTE جديدًا → authenticated لا يملك صلاحية الاستدعاء
-- → PostgREST يرمي 42501 "permission denied for function".
--
-- هذا الـ migration يمنح EXECUTE على كل دوال KPI الحديثة لـ authenticated
-- ويُجبر PostgREST على إعادة تحميل schema cache.
-- Idempotent: كل REVOKE/GRANT/DROP آمنة التكرار.
-- =====================================================================

begin;

-- 1) إسقاط التوقيع القديم 7-معاملات (إن بقي) لمنع التباس PostgREST
drop function if exists public.create_kpi_cycle_admin(date, uuid, timestamptz, timestamptz, timestamptz, timestamptz, boolean);

-- 2) GRANT EXECUTE على كل دوال KPI الحديثة
revoke execute on function public.create_kpi_cycle_admin(date, uuid, timestamptz, timestamptz, timestamptz, timestamptz, boolean, boolean) from public, anon;
grant  execute on function public.create_kpi_cycle_admin(date, uuid, timestamptz, timestamptz, timestamptz, timestamptz, boolean, boolean) to authenticated;

revoke execute on function public.get_kpi_admin_catalog(date) from public, anon;
grant  execute on function public.get_kpi_admin_catalog(date) to authenticated;

revoke execute on function public.manage_kpi_cycle(uuid, text, text, timestamptz) from public, anon;
grant  execute on function public.manage_kpi_cycle(uuid, text, text, timestamptz) to authenticated;

revoke execute on function public.reschedule_kpi_cycle(uuid, timestamptz, timestamptz, text) from public, anon;
grant  execute on function public.reschedule_kpi_cycle(uuid, timestamptz, timestamptz, text) to authenticated;

revoke execute on function public.decide_kpi_appeal(uuid, text, text) from public, anon;
grant  execute on function public.decide_kpi_appeal(uuid, text, text) to authenticated;

revoke execute on function public.refresh_kpi_attendance_inputs(uuid) from public, anon;
grant  execute on function public.refresh_kpi_attendance_inputs(uuid) to authenticated;

revoke execute on function public.get_kpi_cycle_report(uuid) from public, anon;
grant  execute on function public.get_kpi_cycle_report(uuid) to authenticated;

revoke execute on function public.send_kpi_notifications_admin(uuid) from public, anon;
grant  execute on function public.send_kpi_notifications_admin(uuid) to authenticated;

-- create_kpi_policy_version (توقيع ديناميكي)
do $$
declare v_sig text;
begin
  select pg_get_function_identity_arguments(p.oid) into v_sig
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'create_kpi_policy_version'
  order by p.oid desc limit 1;
  if v_sig is not null then
    execute format('revoke execute on function public.create_kpi_policy_version(%s) from public, anon', v_sig);
    execute format('grant  execute on function public.create_kpi_policy_version(%s) to authenticated', v_sig);
  end if;
end $$;

-- 3) إجبار PostgREST على تحديث schema cache فورًا
notify pgrst, 'reload schema';

commit;
