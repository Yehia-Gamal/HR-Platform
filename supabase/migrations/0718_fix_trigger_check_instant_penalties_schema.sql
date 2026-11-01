-- Migration 0718: Add processedCount to trigger_check_instant_penalties_now response
-- Resolves Zod contract validation error when clicking "فحص وتطبيق الآن".

create or replace function public.trigger_check_instant_penalties_now()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_gen_count integer;
  v_esc_count integer;
  v_now_cairo timestamp := (now() at time zone 'Africa/Cairo');
begin
  if auth.uid() is not null
     and not (public.current_is_full_access()
              or public.has_any_permission(array['payroll.run.manage', 'payroll.run.approve', 'attendance.record.manage'])) then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;

  -- 1) فحص وتطبيق غرامات اليوم
  v_gen_count := public.auto_generate_instant_penalties();

  -- 2) فحص وتطبيق التصعيد والمضاعفة والتعليق للغرامات غير المسددة
  v_esc_count := public.auto_escalate_instant_penalties();

  return jsonb_build_object(
    'success', true,
    'processedCount', coalesce(v_gen_count, 0) + coalesce(v_esc_count, 0),
    'totalProcessed', coalesce(v_gen_count, 0) + coalesce(v_esc_count, 0),
    'generatedCount', coalesce(v_gen_count, 0),
    'escalatedCount', coalesce(v_esc_count, 0),
    'serverTimeCairo', to_char(v_now_cairo, 'YYYY-MM-DD HH12:MI:SS AM'),
    'message', 'تم فحص الحضور وتطبيق الغرامات والتصعيد بنجاح (المولدة: ' || coalesce(v_gen_count, 0) || '، المصعدة: ' || coalesce(v_esc_count, 0) || ')'
  );
end;
$$;

revoke all on function public.trigger_check_instant_penalties_now() from public, anon;
grant execute on function public.trigger_check_instant_penalties_now() to authenticated, service_role;
