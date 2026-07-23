-- Migration 0117: إصلاح خطأين حرجين مؤكّدين من تدقيق العقود عبر الطبقات
-- ============================================================================
-- (A) verification_status CHECK لا يتضمن 'server_verified' → كل بصمة مُتحقَّقة تفشل 23514
-- (B) get_release_governance_overview يقرأ e.full_name (غير موجود) → صفحة Release Governance تفشل 500
-- ============================================================================

-- =====================================================================
-- (A) توسيع CHECK constraint على attendance_events.verification_status
-- =====================================================================
-- الـCHECK الحالي (0005:234): ('unverified','passkey_verified','biometric_verified','failed')
-- record_attendance_event يحط 'server_verified' عند نجاح التحقق → 23514
-- الإصلاح: drop + recreate مع القيمة الجديدة

alter table public.attendance_events
  drop constraint if exists attendance_events_verification_status_check;

alter table public.attendance_events
  add constraint attendance_events_verification_status_check
  check (verification_status in (
    'unverified','passkey_verified','biometric_verified','server_verified','failed'
  ));

comment on column public.attendance_events.verification_status is
  'حالة التحقق: unverified (لم يُتحقَّق)، passkey_verified (passkey فقط بدون assertion كامل)، biometric_verified (بيومتري)، server_verified (WebAuthn assertion كامل عبر Edge Function)، failed (فشل التحقق).';

-- =====================================================================
-- (B) إصلاح e.full_name → e.full_name_ar في get_release_governance_overview
-- =====================================================================
-- الدالة في 0038 تقرأ e.full_name 5 مرات (696,708,714,720,731)
-- الجدول employees فيه full_name_ar و full_name_en فقط (0004:37-38)
-- الإصلاح: إعادة تعريف الدالة بالأسماء الصحيحة

create or replace function public.get_release_governance_overview()
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_result jsonb;
begin
  select jsonb_build_object(
    'devices', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', pc.id,
        'employeeName', e.full_name_ar,
        'employeeCode', e.employee_code,
        'credentialId', pc.credential_id,
        'status', pc.status,
        'trusted', pc.trusted,
        'platform', pc.platform,
        'lastUsed', pc.last_used,
        'createdAt', pc.created_at
      ) order by pc.created_at desc)
      from public.passkey_credentials pc
      join public.employees e on e.id = pc.employee_id
    ), '[]'::jsonb),

    'reviewItems', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', ae.id,
        'employeeName', e.full_name_ar,
        'eventType', ae.event_type,
        'eventAt', ae.event_at,
        'requiresReview', ae.requires_review,
        'verificationStatus', ae.verification_status,
        'riskLevel', coalesce(
          (select aic.risk_level from public.attendance_identity_checks aic
           where aic.attendance_event_id = ae.id limit 1),
          'unknown'
        )
      ) order by ae.event_at desc)
      from public.attendance_events ae
      join public.employees e on e.id = ae.employee_id
      where ae.requires_review = true
      limit 100
    ), '[]'::jsonb),

    'breakGlass', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', se.id,
        'actorId', se.actor_id,
        'targetName', e.full_name_ar,
        'eventType', se.event_type,
        'severity', se.severity,
        'description', se.description,
        'createdAt', se.created_at
      ) order by se.created_at desc)
      from public.security_events se
      left join public.employees e on e.user_id = se.actor_id
      where se.event_type ilike '%break_glass%'
      limit 50
    ), '[]'::jsonb),

    'privacyRequests', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', pr.id,
        'employeeName', e.full_name_ar,
        'requestType', pr.request_type,
        'status', pr.status,
        'createdAt', pr.created_at,
        'resolvedAt', pr.resolved_at
      ) order by pr.created_at desc)
      from public.privacy_requests pr
      join public.employees e on e.id = pr.employee_id
      limit 50
    ), '[]'::jsonb),

    'users', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id,
        'name', e.full_name_ar,
        'employeeCode', e.employee_code,
        'status', p.status,
        'createdAt', p.created_at
      ) order by e.full_name_ar)
      from public.profiles p
      left join public.employees e on e.id = p.employee_id
      limit 200
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

comment on function public.get_release_governance_overview() is
  'نظرة عامة على الحوكمة: الأجهزة، البصمات للمراجعة، أحداث break-glass، طلبات الخصوصية، والمستخدمين. مُصلَح: e.full_name_ar بدل e.full_name (0117).';
