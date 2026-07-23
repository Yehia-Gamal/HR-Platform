-- Migration 0126: إصلاح مشكلتين حرجتين اكتشفهما فحص تطابق العقود
-- ============================================================================
-- P0-A: CHECK constraint على verification_status لا يحتوي 'server_verified'
--       → كل بصمة مُتحقَّقة عبر verify-attendance-punch تفشل بـ23514
-- P0-B: get_release_governance_overview يقرأ e.full_name (غير موجود)
--       → كل استدعاء يرمي 42703 وصفحة Release Governance تفشل 500
-- ============================================================================

-- =====================================================================
-- P0-A: توسعة CHECK constraint على attendance_events.verification_status
-- =====================================================================
-- نحذف القيد القديم ونضيف الجديد بقيمة 'server_verified' الإضافية.
-- اسم القيد المولّد تلقائياً من Postgres يكون: attendance_events_verification_status_check
-- نستخدم do block للأمان (لو الاسم مختلف نبحث عنه).

do $$
declare
  v_constraint_name text;
begin
  -- ابحث عن اسم القيد الفعلي على عمود verification_status
  select cc.constraint_name into v_constraint_name
  from information_schema.check_constraints cc
  join information_schema.constraint_column_usage ccu
    on cc.constraint_name = ccu.constraint_name
    and cc.constraint_schema = ccu.constraint_schema
  where ccu.table_schema = 'public'
    and ccu.table_name = 'attendance_events'
    and ccu.column_name = 'verification_status'
  limit 1;

  if v_constraint_name is not null then
    execute format('alter table public.attendance_events drop constraint %I', v_constraint_name);
    raise notice 'Dropped old verification_status CHECK: %', v_constraint_name;
  end if;
end $$;

-- القيد الجديد يشمل 'server_verified'
alter table public.attendance_events
  add constraint attendance_events_verification_status_check
  check (verification_status in (
    'unverified',
    'passkey_verified',
    'biometric_verified',
    'server_verified',
    'failed'
  ));

comment on constraint attendance_events_verification_status_check on public.attendance_events is
  'V126: أُضيفت server_verified — القيمة التي يضعها record_attendance_event بعد تحقق WebAuthn ناجح عبر verify-attendance-punch.';

-- =====================================================================
-- P0-B: إصلاح e.full_name → e.full_name_ar في get_release_governance_overview
-- =====================================================================
-- نعيد تعريف الدالة بالكامل (CREATE OR REPLACE) مع التصحيح في 5 مواضع + ORDER BY.

create or replace function public.get_release_governance_overview()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  return jsonb_build_object(
    'policies',coalesce((select jsonb_agg(jsonb_build_object(
      'id',p.id,'platform',p.platform,'environment',p.environment,'latestVersion',p.latest_version,'latestBuild',p.latest_build,
      'minSupportedVersion',p.min_supported_version,'minSupportedBuild',p.min_supported_build,'forceUpdate',p.force_update,
      'maintenance',p.maintenance_enabled,'maintenanceMessageAr',p.maintenance_message_ar,'updateMessageAr',p.update_message_ar,
      'storeUrl',p.store_url,'rolloutPercent',p.rollout_percent,'updatedAt',coalesce(p.updated_at,p.created_at)
    ) order by p.platform,p.environment) from public.app_release_policies p),'[]'::jsonb),
    'devices',coalesce((select jsonb_agg(jsonb_build_object(
      'id',d.id,'installationId',d.installation_id,'userId',d.user_id,'employeeId',d.employee_id,
      'employeeName',e.full_name_ar,'employeeCode',e.employee_code,'platform',d.platform,'deviceName',d.device_name,
      'deviceModel',d.device_model,'osVersion',d.os_version,'appVersion',d.app_version,'appBuild',d.app_build,
      'environment',d.environment,'trusted',d.trusted,'status',d.status,'lastSeenAt',d.last_seen_at
    ) order by d.last_seen_at desc) from public.managed_devices d left join public.employees e on e.id=d.employee_id),'[]'::jsonb),
    'accessReviews',coalesce((select jsonb_agg(jsonb_build_object(
      'id',c.id,'name',c.name,'status',c.status,'startsAt',c.starts_at,'dueAt',c.due_at,
      'totalItems',(select count(*) from public.access_review_items i where i.campaign_id=c.id),
      'pendingItems',(select count(*) from public.access_review_items i where i.campaign_id=c.id and i.decision='pending'),
      'revokedItems',(select count(*) from public.access_review_items i where i.campaign_id=c.id and i.decision='revoke')
    ) order by c.created_at desc) from public.access_review_campaigns c),'[]'::jsonb),
    'reviewItems',coalesce((select jsonb_agg(jsonb_build_object(
      'id',i.id,'campaignId',i.campaign_id,'userRoleId',i.user_role_id,'userId',i.user_id,'roleId',i.role_id,
      'employeeName',e.full_name_ar,'employeeCode',e.employee_code,'roleName',r.name_ar,'decision',i.decision,
      'decisionReason',i.decision_reason,'decidedAt',i.decided_at,'snapshot',i.snapshot
    ) order by i.created_at desc) from public.access_review_items i
      left join public.profiles pr on pr.id=i.user_id left join public.employees e on e.id=pr.employee_id join public.roles r on r.id=i.role_id
      where i.decision='pending'),'[]'::jsonb),
    'breakGlass',coalesce((select jsonb_agg(jsonb_build_object(
      'id',b.id,'targetUserId',b.target_user_id,'targetName',e.full_name_ar,'targetCode',e.employee_code,
      'roleId',b.requested_role_id,'roleName',r.name_ar,'durationMinutes',b.duration_minutes,'reason',b.reason,
      'status',b.status,'requestedBy',b.requested_by,'requestedAt',b.requested_at,'activeUntil',b.active_until
    ) order by b.requested_at desc) from public.break_glass_requests b
      left join public.profiles pr on pr.id=b.target_user_id left join public.employees e on e.id=pr.employee_id join public.roles r on r.id=b.requested_role_id),'[]'::jsonb),
    'privacyRequests',coalesce((select jsonb_agg(jsonb_build_object(
      'id',p.id,'requestNumber',p.request_number,'requesterUserId',p.requester_user_id,'employeeName',e.full_name_ar,
      'employeeCode',e.employee_code,'requestType',p.request_type,'details',p.details,'status',p.status,'dueAt',p.due_at,
      'decisionReason',p.decision_reason,'createdAt',p.created_at
    ) order by p.created_at desc) from public.privacy_requests p left join public.employees e on e.id=p.requester_employee_id),'[]'::jsonb),
    'outbox',jsonb_build_object(
      'pending',(select count(*) from public.integration_outbox where status in ('pending','retrying')),
      'failed',(select count(*) from public.integration_outbox where status in ('failed','dead_letter')),
      'delivered',(select count(*) from public.integration_outbox where status='delivered'),
      'oldestPendingAt',(select min(created_at) from public.integration_outbox where status in ('pending','retrying'))
    ),
    'roles',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'slug',r.slug,'name',r.name_ar,'fullAccess',r.is_full_access) order by r.name_ar) from public.roles r),'[]'::jsonb),
    'users',coalesce((select jsonb_agg(jsonb_build_object('userId',p.id,'employeeId',p.employee_id,'name',e.full_name_ar,'employeeCode',e.employee_code,'status',p.status) order by e.full_name_ar) from public.profiles p left join public.employees e on e.id=p.employee_id),'[]'::jsonb),
    'lastUpdatedAt',now()
  );
end;
$$;

-- الـgrants موجودة من 0038 ولا تتأثر بـCREATE OR REPLACE.
