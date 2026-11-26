-- ============================================================================
-- 0740: تحديد معدل ذري لعمليات الإدارة الحساسة وإعادة إرسال الدعوات
-- ============================================================================
-- يُزيل نافذة السباق (TOCTOU) بين SELECT count(*) و INSERT في:
--   • admin-set-password (admin_sensitive_ops_log)
--   • admin-update-email (admin_sensitive_ops_log)
--   • admin-resend-invite (auth_invite_log)
-- باستخدام pg_advisory_xact_lock + فحص وإدراج في معاملة SQL ذرية واحدة.
-- ============================================================================

begin;

create or replace function public.consume_admin_sensitive_op_quota(
  p_actor_id uuid,
  p_op_type text,
  p_employee_id uuid,
  p_max_count integer default 5,
  p_window_seconds integer default 300
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_recent_count integer;
begin
  if p_actor_id is null or p_employee_id is null then
    raise exception 'actor_id and employee_id are required';
  end if;

  if p_op_type not in ('set_password', 'update_email') then
    raise exception 'invalid op_type: %', coalesce(p_op_type, '<null>');
  end if;

  if coalesce(p_max_count, 0) <= 0 or coalesce(p_window_seconds, 0) <= 0 then
    raise exception 'max_count and window_seconds must be positive';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('admin_sensitive_ops:' || p_actor_id::text || ':' || p_op_type, 0)
  );

  select count(*)::integer
    into v_recent_count
  from public.admin_sensitive_ops_log
  where actor_id = p_actor_id
    and op_type = p_op_type
    and created_at >= now() - make_interval(secs => p_window_seconds);

  if v_recent_count >= p_max_count then
    return false;
  end if;

  insert into public.admin_sensitive_ops_log (op_type, actor_id, employee_id)
  values (p_op_type, p_actor_id, p_employee_id);

  return true;
end;
$$;

revoke all on function public.consume_admin_sensitive_op_quota(uuid, text, uuid, integer, integer)
  from public, anon, authenticated;
grant execute on function public.consume_admin_sensitive_op_quota(uuid, text, uuid, integer, integer)
  to service_role;

create or replace function public.consume_auth_invite_quota(
  p_employee_id uuid,
  p_sent_by uuid,
  p_email text,
  p_window_seconds integer default 60
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_employee_id is null or p_sent_by is null or coalesce(trim(p_email), '') = '' then
    raise exception 'employee_id, sent_by, and email are required';
  end if;

  if coalesce(p_window_seconds, 0) <= 0 then
    raise exception 'window_seconds must be positive';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('auth_invite:' || p_employee_id::text, 0)
  );

  if exists (
    select 1
    from public.auth_invite_log
    where employee_id = p_employee_id
      and created_at >= now() - make_interval(secs => p_window_seconds)
  ) then
    return false;
  end if;

  insert into public.auth_invite_log (employee_id, sent_by, email)
  values (p_employee_id, p_sent_by, lower(trim(p_email)));

  return true;
end;
$$;

revoke all on function public.consume_auth_invite_quota(uuid, uuid, text, integer)
  from public, anon, authenticated;
grant execute on function public.consume_auth_invite_quota(uuid, uuid, text, integer)
  to service_role;

commit;
