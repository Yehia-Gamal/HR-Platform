-- 0074_fix_log_audit_event_overload.sql
-- Provides a backward-compatible 4-parameter overload for log_audit_event
-- to fix PostgrestException errors from older migrations or edge functions.

create or replace function public.log_audit_event(
  p_event_type    text,
  p_target_table  text,
  p_target_id     uuid,
  p_metadata      jsonb
)
returns public.audit_events
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  return public.log_audit_event(
    p_event_type,       -- p_event_type
    'general',          -- p_category
    'info',             -- p_severity
    p_target_table,     -- p_target_table
    p_target_id,        -- p_target_id
    null,               -- p_summary_ar
    null,               -- p_description
    p_metadata          -- p_metadata
  );
end;
$$;
comment on function public.log_audit_event(text, text, uuid, jsonb) is
  'RPC: Overload لضمان التوافقية مع استدعاءات 4 معاملات لتسجيل الأحداث';

revoke execute on function public.log_audit_event(text, text, uuid, jsonb) from public;
grant  execute on function public.log_audit_event(text, text, uuid, jsonb) to authenticated;
