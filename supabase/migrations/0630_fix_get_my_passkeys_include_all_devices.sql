-- ============================================================================
-- 0630: إظهار كافة الأجهزة الموثوقة والبصمة الحيوية في get_my_passkeys
-- ============================================================================
-- المشكلة: كانت get_my_passkeys تجلب الأجهزة من passkey_credentials فقط،
-- بينما أغلب الموظفين مسجلون عبر البصمة الحيوية المحلية (employee_devices)
-- برقم credential_id فارغ. فكان يظهر للموظف أن جهازه "مُستبدَل" أو لا توجد أجهزة،
-- رغم أن هاتفه الفعلي نشط ومسجل.
--
-- الحل: إعادة بناء get_my_passkeys لتجلب كافة الأجهزة النشطة والمعتمدة
-- من employee_devices أولاً (بما فيها أجهزة البصمة المحلية) وتدمج أي Passkeys.
-- ============================================================================

begin;

create or replace function public.get_my_passkeys()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_uid uuid := auth.uid();
begin
  return coalesce((
    with all_devices as (
      -- 1) الأجهزة المسجلة في employee_devices (البصمة الحيوية المحلية ومفاتيح المرور)
      select
        ed.id::text as id,
        coalesce(ed.credential_id, '') as credential_id,
        ed.id::text as device_id,
        coalesce(ed.device_name, 'هاتف الموظف') as device_label,
        coalesce(ed.status, 'pending') as status,
        (ed.status = 'active') as trusted,
        coalesce(ed.platform, 'android') as device_type,
        false as backed_up,
        greatest(ed.last_used_at, ed.registered_at) as last_used_at,
        coalesce(ed.registered_at, ed.created_at) as created_at,
        ed.approved_at,
        ed.rejection_reason,
        ed.revocation_source,
        coalesce(ed.status in ('blocked', 'revoked', 'replaced'), false) as can_resubmit
      from public.employee_devices ed
      where (v_me is not null and ed.employee_id = v_me)
         or (v_uid is not null and ed.user_id = v_uid)

      union all

      -- 2) أي مفاتيح passkeys قديمة ليست مسجلة بعد في employee_devices
      select
        p.id::text as id,
        p.credential_id,
        p.id::text as device_id,
        coalesce(p.device_label, 'مفتاح مرور مسجل') as device_label,
        case when p.status = 'revoked' then 'revoked' else 'active' end as status,
        (p.status = 'active' and p.trusted) as trusted,
        coalesce(p.credential_device_type, 'unknown') as device_type,
        coalesce(p.credential_backed_up, false) as backed_up,
        p.last_used as last_used_at,
        p.created_at,
        p.created_at as approved_at,
        null as rejection_reason,
        null as revocation_source,
        false as can_resubmit
      from public.passkey_credentials p
      where ((v_me is not null and p.employee_id = v_me) or (v_uid is not null and p.user_id = v_uid))
        and not exists (
          select 1 from public.employee_devices ed2
          where ed2.credential_id = p.credential_id
        )
    )
    select jsonb_agg(jsonb_build_object(
      'id', d.id,
      'credentialId', d.credential_id,
      'deviceId', d.device_id,
      'deviceLabel', d.device_label,
      'status', d.status,
      'trusted', d.trusted,
      'deviceType', d.device_type,
      'backedUp', d.backed_up,
      'lastUsedAt', d.last_used_at,
      'createdAt', d.created_at,
      'approvedAt', d.approved_at,
      'rejectionReason', d.rejection_reason,
      'revocationSource', d.revocation_source,
      'canResubmit', d.can_resubmit
    ) order by
        case d.status when 'active' then 1 when 'pending' then 2 else 3 end,
        coalesce(d.last_used_at, d.created_at) desc)
    from all_devices d
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.get_my_passkeys() from public, anon;
grant execute on function public.get_my_passkeys() to authenticated;

commit;
