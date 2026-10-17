-- ============================================================================
-- 0635: منع إبطال أجهزة الويب وسماحها بالوصول الدائم (Fix Web Device Revocation)
-- (أُعيد ترقيمه من 0629 إلى 0633 إلى 0635 — 0629 مستخدَم بملف منشور في prod،
--  و0633 مستخدَم لاحقاً بملف unstick_legacy_parallel_kpi_evaluations)
-- ============================================================================
-- المشكلة: الزناد trg_managed_devices_single_active في 0469 كان يلغي جميع أجهزة
-- الموظف عند تسجيل جهاز جديد دون استثناء الويب (platform = 'web').
-- وبما أن get_public_release_policy كان يفحص حالة أي installation_id،
-- فإن مستخدمي المتصفح ومطوري لوحة التحكم كان يظهر لهم "تم إبطال هذا الجهاز".
--
-- الحل:
-- 1) استثناء platform = 'web' من زناد قصر النشاط على جهاز واحد (مخصص لهواتف البصمة).
-- 2) استثناء platform = 'web' في get_public_release_policy من فحص الإلغاء.
-- 3) تنشيط كافة أجهزة الويب المعطلة لموظفي المنظومة.
-- ============================================================================

begin;

-- 1) تعديل زناد الأجهزة المدارة لاستثناء الويب
create or replace function public.trg_fn_managed_devices_single_active()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- أجهزة الويب لا تُقيد بجهاز واحد ولا تُبطل الهواتف المحمولة
  if NEW.platform = 'web' then
    return NEW;
  end if;

  update public.managed_devices
  set status = 'revoked',
      revoked_at = now(),
      revoke_reason = 'superseded_by_device_' || NEW.id::text
  where employee_id = NEW.employee_id
    and id <> NEW.id
    and platform <> 'web'
    and status = 'active';
  return NEW;
end;
$$;

-- 2) تعديل دالة فحص السياسة لاستثناء الويب من إبطال الأجهزة
create or replace function public.get_public_release_policy(
  p_platform text,
  p_environment text default 'production',
  p_current_version text default '0.0.0',
  p_current_build integer default 0,
  p_installation_id text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_policy public.app_release_policies;
  v_device_status text;
  v_action text := 'none';
  v_rollout_bucket integer := 1;
begin
  if p_platform not in ('android','ios','web') then
    raise exception 'invalid platform' using errcode = '22023';
  end if;
  if p_environment not in ('development','staging','production') then
    raise exception 'invalid environment' using errcode = '22023';
  end if;

  select * into v_policy
  from public.app_release_policies
  where platform = p_platform and environment = p_environment
    and effective_from <= now() and (effective_to is null or effective_to > now())
  limit 1;

  if not found then
    return jsonb_build_object(
      'action','none','platform',p_platform,'environment',p_environment,
      'currentVersion',coalesce(p_current_version,'0.0.0'),'currentBuild',greatest(coalesce(p_current_build,0),0),
      'latestVersion',coalesce(p_current_version,'0.0.0'),'latestBuild',greatest(coalesce(p_current_build,0),0),
      'minSupportedVersion','0.0.0','minSupportedBuild',0,'forceUpdate',false,
      'maintenance',false,'messageAr',null,'storeUrl',null,'checkedAt',now()
    );
  end if;

  -- فحص إبطال الجهاز للهواتف فقط، الويب معفى دائماً من الإبطال
  if p_installation_id is not null and p_platform <> 'web' then
    v_rollout_bucket := (abs(hashtext(p_installation_id)) % 100) + 1;
    select status into v_device_status from public.managed_devices where installation_id = p_installation_id;
    if v_device_status in ('revoked','blocked') then
      v_action := 'blocked';
    end if;
  end if;

  if v_action = 'none' and v_policy.maintenance_enabled then
    v_action := 'maintenance';
  elsif v_action = 'none' and greatest(coalesce(p_current_build,0),0) < v_policy.min_supported_build then
    v_action := 'update_required';
  elsif v_action = 'none' and greatest(coalesce(p_current_build,0),0) < v_policy.latest_build then
    if v_policy.force_update then
      v_action := 'update_required';
    elsif v_rollout_bucket <= v_policy.rollout_percent then
      v_action := 'update_available';
    end if;
  end if;

  return jsonb_build_object(
    'action',v_action,'platform',v_policy.platform,'environment',v_policy.environment,
    'currentVersion',coalesce(p_current_version,'0.0.0'),'currentBuild',greatest(coalesce(p_current_build,0),0),
    'latestVersion',v_policy.latest_version,'latestBuild',v_policy.latest_build,
    'minSupportedVersion',v_policy.min_supported_version,'minSupportedBuild',v_policy.min_supported_build,
    'forceUpdate',v_policy.force_update,'maintenance',v_policy.maintenance_enabled,
    'messageAr',case when v_action='maintenance' then v_policy.maintenance_message_ar else v_policy.update_message_ar end,
    'storeUrl',v_policy.store_url,'checkedAt',now()
  );
end;
$$;

revoke execute on function public.get_public_release_policy(text,text,text,integer,text) from public;
grant execute on function public.get_public_release_policy(text,text,text,integer,text) to anon, authenticated;

-- 3) إعادة تفعيل جميع أجهزة الويب للموظفين
update public.managed_devices
set status = 'active',
    revoked_at = null,
    revoke_reason = null
where platform = 'web'
  and status = 'revoked';

commit;
