import { publicReleasePolicySchema, type PublicReleasePolicy } from '@ahla/shared-contracts';
import { useQuery } from '@tanstack/react-query';
import { useEffect } from 'react';
import { env, hasSupabaseConfig } from '../../core/env';
import { getSupabase } from '../../core/supabase';
import { useAuth } from './AuthProvider';

const installationKey = 'management_os_web_installation_id_v1';
const installationOwnerKey = 'management_os_web_installation_owner_v1';

function installationId(userId?: string) {
  const current = localStorage.getItem(installationKey);
  const owner = localStorage.getItem(installationOwnerKey);

  // إذا الـ ID موجود: نرجعه إذا ما في userId، أو المالك غير مسجّل (ترقية)، أو نفس المستخدم
  if (current && current.length >= 12) {
    if (!userId || !owner || owner === userId) {
      if (userId && !owner) localStorage.setItem(installationOwnerKey, userId);
      return current;
    }
    // المالك مختلف — حساب آخر على نفس المتصفح → نولّد ID جديد
  }

  const next = crypto.randomUUID();
  localStorage.setItem(installationKey, next);
  if (userId) localStorage.setItem(installationOwnerKey, userId);
  return next;
}

const localPolicy: PublicReleasePolicy = {
  action: 'none', platform: 'web', environment: env.appEnvironment,
  currentVersion: env.appVersion, currentBuild: env.appBuild,
  latestVersion: env.appVersion, latestBuild: env.appBuild,
  minSupportedVersion: '0.0.0', minSupportedBuild: 0,
  forceUpdate: false, maintenance: false, messageAr: null, storeUrl: null,
  checkedAt: new Date().toISOString(),
};

export function useWebReleasePolicy() {
  return useQuery({
    queryKey: ['web-release-policy', env.appVersion, env.appBuild, env.appEnvironment],
    staleTime: 5 * 60_000,
    retry: 2,
    queryFn: async () => {
      if (!hasSupabaseConfig) return localPolicy;
      const supabase = await getSupabase();
      const { data, error } = await supabase.rpc('get_public_release_policy', {
        p_platform: 'web', p_environment: env.appEnvironment,
        p_current_version: env.appVersion, p_current_build: env.appBuild,
        p_installation_id: installationId(),
      });
      if (error) throw error;
      return publicReleasePolicySchema.parse(data);
    },
  });
}

export function useRegisterWebDevice() {
  const auth = useAuth();
  useEffect(() => {
    if (auth.status !== 'authenticated' || auth.isMock || !hasSupabaseConfig) return;
    const userId = auth.session?.user.id;
    if (!userId) return;
    let active = true;
    void getSupabase().then(async (supabase) => {
      if (!active) return;
      const { error } = await supabase.rpc('register_my_device', {
        p_installation_id: installationId(userId), p_platform: 'web' as const,
        p_device_name: navigator.platform || 'Web Browser', p_device_model: navigator.userAgent.slice(0, 180),
        p_os_version: (navigator as Navigator & { userAgentData?: { platform?: string } }).userAgentData?.platform ?? navigator.platform ?? null,
        p_app_version: env.appVersion, p_app_build: env.appBuild, p_environment: env.appEnvironment,
        p_push_enabled: Notification.permission === 'granted', p_biometric_available: Boolean(window.PublicKeyCredential),
        p_metadata: { language: navigator.language, timezone: Intl.DateTimeFormat().resolvedOptions().timeZone },
      });
      if (error && import.meta.env.DEV) console.warn('Managed device registration skipped', error.message);
    });
    return () => { active = false; };
  }, [auth.status, auth.isMock, auth.session?.user.id]);
}
