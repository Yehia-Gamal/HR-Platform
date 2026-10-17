-- 0656: Ensure get_all_devices_admin returns approvedAt
create or replace function public.get_all_devices_admin(
  p_status_filter text default null::text,
  p_include_terminated boolean default false
)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case
    when not (
      public.current_is_full_access()
      or public.current_has_active_role(array['admin','super-admin','executive','executive-director','general-manager','hr-manager'])
      or public.has_permission('access.role.read')
    ) then '[]'::jsonb
    else coalesce(jsonb_agg(jsonb_build_object(
      'id', d.id,
      'employeeId', d.employee_id,
      'employeeName', coalesce(e.full_name_ar, e.full_name_en, 'موظف'),
      'employeeCode', e.employee_code,
      'employeePhotoUrl', e.photo_url,
      'deviceName', coalesce(d.device_name, d.platform),
      'platform', d.platform,
      'status', d.status,
      'registeredAt', d.registered_at,
      'approvedAt', d.approved_at,
      'lastUsedAt', d.last_used_at,
      'revokedAt', d.revoked_at,
      'revocationSource', d.revocation_source,
      'approvedBy', d.approved_by,
      'rejectionReason', d.rejection_reason,
      'metadata', d.metadata
    ) order by d.registered_at desc), '[]'::jsonb)
  end
  from public.employee_devices d
  join public.employees e on e.id = d.employee_id
  where (p_status_filter is null or d.status = p_status_filter)
    and (
      p_include_terminated = true
      or d.status in ('pending', 'active', 'blocked')
    );
$$;

comment on function public.get_all_devices_admin(text, boolean) is
  '0656: جلب كافة أجهزة الموظفين للأدوار الإدارية والـ HR مع وقت الموافقة.';
revoke all on function public.get_all_devices_admin(text, boolean) from public, anon;
grant execute on function public.get_all_devices_admin(text, boolean) to authenticated;
