-- Restore the complete V10 release-governance contract after migration 0117
-- accidentally replaced it with an obsolete passkey-based projection that
-- references passkey_credentials.platform (a column that does not exist).

create or replace function public.get_release_governance_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not (
    public.current_is_full_access()
    or public.has_any_permission(array[
      'system.release.read','system.release.manage','access.review.read','access.review.manage',
      'access.break_glass.request','access.break_glass.approve','privacy.request.manage',
      'system.integration.outbox.read','system.integration.outbox.manage','system.integration.manage'
    ])
  ) then
    raise exception 'governance overview denied' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'policies', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',p.id,'platform',p.platform,'environment',p.environment,
        'latestVersion',p.latest_version,'latestBuild',p.latest_build,
        'minSupportedVersion',p.min_supported_version,
        'minSupportedBuild',p.min_supported_build,'forceUpdate',p.force_update,
        'maintenance',p.maintenance_enabled,
        'maintenanceMessageAr',p.maintenance_message_ar,
        'updateMessageAr',p.update_message_ar,'storeUrl',p.store_url,
        'rolloutPercent',p.rollout_percent,
        'updatedAt',coalesce(p.updated_at,p.created_at)
      ) order by p.platform,p.environment)
      from public.app_release_policies p
    ), '[]'::jsonb),
    'devices', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',d.id,'installationId',d.installation_id,'userId',d.user_id,
        'employeeId',d.employee_id,
        'employeeName',coalesce(e.full_name_ar,e.full_name_en),
        'employeeCode',e.employee_code,'platform',d.platform,
        'deviceName',d.device_name,'deviceModel',d.device_model,
        'osVersion',d.os_version,'appVersion',d.app_version,
        'appBuild',d.app_build,'environment',d.environment,
        'trusted',d.trusted,'status',d.status,'lastSeenAt',d.last_seen_at
      ) order by d.last_seen_at desc)
      from public.managed_devices d
      left join public.employees e on e.id = d.employee_id
    ), '[]'::jsonb),
    'accessReviews', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',c.id,'name',c.name,'status',c.status,'startsAt',c.starts_at,
        'dueAt',c.due_at,
        'totalItems',(select count(*) from public.access_review_items i where i.campaign_id=c.id),
        'pendingItems',(select count(*) from public.access_review_items i where i.campaign_id=c.id and i.decision='pending'),
        'revokedItems',(select count(*) from public.access_review_items i where i.campaign_id=c.id and i.decision='revoke')
      ) order by c.created_at desc)
      from public.access_review_campaigns c
    ), '[]'::jsonb),
    'reviewItems', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',i.id,'campaignId',i.campaign_id,'userRoleId',i.user_role_id,
        'userId',i.user_id,'roleId',i.role_id,
        'employeeName',coalesce(e.full_name_ar,e.full_name_en),
        'employeeCode',e.employee_code,'roleName',r.name_ar,
        'decision',i.decision,'decisionReason',i.decision_reason,
        'decidedAt',i.decided_at,'snapshot',i.snapshot
      ) order by i.created_at desc)
      from public.access_review_items i
      left join public.profiles pr on pr.id = i.user_id
      left join public.employees e on e.id = pr.employee_id
      join public.roles r on r.id = i.role_id
      where i.decision = 'pending'
    ), '[]'::jsonb),
    'breakGlass', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',b.id,'targetUserId',b.target_user_id,
        'targetName',coalesce(e.full_name_ar,e.full_name_en),
        'targetCode',e.employee_code,'roleId',b.requested_role_id,
        'roleName',r.name_ar,'durationMinutes',b.duration_minutes,
        'reason',b.reason,'status',b.status,'requestedBy',b.requested_by,
        'requestedAt',b.requested_at,'activeUntil',b.active_until
      ) order by b.requested_at desc)
      from public.break_glass_requests b
      left join public.profiles pr on pr.id = b.target_user_id
      left join public.employees e on e.id = pr.employee_id
      join public.roles r on r.id = b.requested_role_id
    ), '[]'::jsonb),
    'privacyRequests', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',p.id,'requestNumber',p.request_number,
        'requesterUserId',p.requester_user_id,
        'employeeName',coalesce(e.full_name_ar,e.full_name_en),
        'employeeCode',e.employee_code,'requestType',p.request_type,
        'details',p.details,'status',p.status,'dueAt',p.due_at,
        'decisionReason',p.decision_reason,'createdAt',p.created_at
      ) order by p.created_at desc)
      from public.privacy_requests p
      left join public.employees e on e.id = p.requester_employee_id
    ), '[]'::jsonb),
    'outbox', jsonb_build_object(
      'pending',(select count(*) from public.integration_outbox where status in ('pending','retrying')),
      'failed',(select count(*) from public.integration_outbox where status in ('failed','dead_letter')),
      'delivered',(select count(*) from public.integration_outbox where status='delivered'),
      'oldestPendingAt',(select min(created_at) from public.integration_outbox where status in ('pending','retrying'))
    ),
    'roles', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',r.id,'slug',r.slug,'name',r.name_ar,'fullAccess',r.is_full_access
      ) order by r.name_ar)
      from public.roles r
    ), '[]'::jsonb),
    'users', coalesce((
      select jsonb_agg(jsonb_build_object(
        'userId',p.id,'employeeId',p.employee_id,
        'name',coalesce(e.full_name_ar,e.full_name_en),
        'employeeCode',e.employee_code,'status',p.status
      ) order by coalesce(e.full_name_ar,e.full_name_en))
      from public.profiles p
      left join public.employees e on e.id = p.employee_id
    ), '[]'::jsonb),
    'lastUpdatedAt', now()
  );
end;
$$;

revoke all on function public.get_release_governance_overview()
  from public, anon;
grant execute on function public.get_release_governance_overview()
  to authenticated;

comment on function public.get_release_governance_overview() is
  'Complete V10 release, access-review, break-glass, privacy and integration governance overview.';

notify pgrst, 'reload schema';
