-- 0090: Archive preserves history; permanent deletion is a tightly guarded exception.
create or replace function public.archive_employee_secure(p_employee_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare
  v_actor uuid := public.current_employee_id();
  v_employee public.employees%rowtype;
  v_user_id uuid;
  v_sessions integer := 0;
  v_devices integer := 0;
begin
  if p_employee_id is null or length(trim(coalesce(p_reason,''))) < 5 then raise exception 'archive_reason_required' using errcode='22023'; end if;
  if p_employee_id=v_actor then raise exception 'self_archive_not_allowed' using errcode='42501'; end if;
  if not (public.current_is_full_access() or (public.has_any_permission(array['employees.delete','people.employee.update']) and public.can_access_employee(p_employee_id))) then raise exception 'forbidden' using errcode='42501'; end if;
  select * into v_employee from public.employees where id=p_employee_id for update;
  if v_employee.id is null then raise exception 'employee_not_found' using errcode='P0002'; end if;
  select id into v_user_id from public.profiles where employee_id=p_employee_id;

  update public.employees set is_active=false,is_deleted=true,status='archived',updated_at=now() where id=p_employee_id;
  if v_user_id is not null then
    update public.profiles set status='disabled',updated_at=now() where id=v_user_id;
    update public.push_subscriptions set is_active=false,updated_at=now() where user_id=v_user_id and is_active=true;
    delete from auth.sessions where user_id=v_user_id;
    get diagnostics v_sessions=row_count;
    delete from auth.refresh_tokens where user_id=v_user_id::text;
  end if;
  update public.employee_devices set status='revoked',revoked_at=coalesce(revoked_at,now()),updated_at=now(),metadata=metadata||jsonb_build_object('revokedByArchive',true) where employee_id=p_employee_id and status<>'revoked';
  get diagnostics v_devices=row_count;
  update public.passkey_credentials set status='revoked',trusted=false,updated_at=now() where employee_id=p_employee_id and status<>'revoked';
  perform public.log_audit_event('employee.archived','security','warning','employees',p_employee_id,trim(p_reason),to_jsonb(v_employee),jsonb_build_object('status','archived','sessionsRevoked',v_sessions,'devicesRevoked',v_devices,'userId',v_user_id));
  return jsonb_build_object('ok',true,'employeeId',p_employee_id,'status','archived','sessionsRevoked',v_sessions,'devicesRevoked',v_devices,'historyPreserved',true);
end; $$;
revoke all on function public.archive_employee_secure(uuid,text) from public,anon;
grant execute on function public.archive_employee_secure(uuid,text) to authenticated;

create or replace function public.hard_delete_employee_guarded(p_employee_id uuid,p_confirmation_code text,p_reason text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_employee public.employees%rowtype;
begin
  if not public.current_is_full_access() then raise exception 'main_admin_required' using errcode='42501'; end if;
  if p_employee_id=public.current_employee_id() then raise exception 'self_delete_not_allowed' using errcode='42501'; end if;
  if length(trim(coalesce(p_reason,'')))<10 then raise exception 'delete_reason_required' using errcode='22023'; end if;
  select * into v_employee from public.employees where id=p_employee_id for update;
  if v_employee.id is null then raise exception 'employee_not_found' using errcode='P0002'; end if;
  if p_confirmation_code is distinct from v_employee.employee_code then raise exception 'delete_confirmation_mismatch' using errcode='22023'; end if;
  if exists(select 1 from public.profiles where employee_id=p_employee_id)
    or exists(select 1 from public.attendance_events where employee_id=p_employee_id)
    or exists(select 1 from public.attendance_daily where employee_id=p_employee_id)
    or exists(select 1 from public.requests where employee_id=p_employee_id)
    or exists(select 1 from public.kpi_evaluations where employee_id=p_employee_id)
    or exists(select 1 from public.employee_devices where employee_id=p_employee_id)
    or exists(select 1 from public.passkey_credentials where employee_id=p_employee_id)
  then raise exception 'employee_history_requires_archive' using errcode='55000'; end if;
  perform public.log_audit_event('employee.permanent_delete_approved','security','critical','employees',p_employee_id,trim(p_reason),to_jsonb(v_employee),jsonb_build_object('confirmationCode',p_confirmation_code));
  delete from public.employees where id=p_employee_id;
  return jsonb_build_object('ok',true,'employeeId',p_employee_id,'deleted',true);
end; $$;
revoke all on function public.hard_delete_employee_guarded(uuid,text,text) from public,anon;
grant execute on function public.hard_delete_employee_guarded(uuid,text,text) to authenticated;
drop policy if exists employees_delete on public.employees;
revoke delete on public.employees from authenticated;
