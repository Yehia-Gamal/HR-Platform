import {
  releaseGovernanceCatalogSchema,
  type ReleaseGovernanceCatalog,
} from '@ahla/shared-contracts';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';

const now = new Date().toISOString();
const emptyCatalog: ReleaseGovernanceCatalog = {
  policies: [], devices: [], accessReviews: [], reviewItems: [], breakGlass: [], privacyRequests: [],
  outbox: { pending: 0, failed: 0, delivered: 0, oldestPendingAt: null }, roles: [], users: [], lastUpdatedAt: now,
};

export function useReleaseGovernanceCatalog() {
  const auth = useAuth();
  return useQuery({
    queryKey: ['release-governance', auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async () => auth.isMock
      ? emptyCatalog
      : releaseGovernanceCatalogSchema.parse(await rpc('get_release_governance_overview')),
  });
}

export function useReleaseGovernanceCommands() {
  const auth = useAuth();
  const client = useQueryClient();
  const refresh = async () => client.invalidateQueries({ queryKey: ['release-governance'] });

  const updatePolicy = useMutation({
    mutationFn: async (input: {
      platform: 'android' | 'ios' | 'web'; environment: 'development' | 'staging' | 'production';
      latestVersion: string; latestBuild: number; minSupportedVersion: string; minSupportedBuild: number;
      forceUpdate: boolean; maintenance: boolean; maintenanceMessageAr: string; updateMessageAr: string;
      storeUrl: string; rolloutPercent: number; reason: string;
    }) => auth.isMock ? input : rpc('update_release_policy', {
      p_platform: input.platform, p_environment: input.environment,
      p_latest_version: input.latestVersion, p_latest_build: input.latestBuild,
      p_min_supported_version: input.minSupportedVersion, p_min_supported_build: input.minSupportedBuild,
      p_force_update: input.forceUpdate, p_maintenance_enabled: input.maintenance,
      p_maintenance_message_ar: input.maintenanceMessageAr || null,
      p_update_message_ar: input.updateMessageAr || null,
      p_store_url: input.storeUrl || null, p_rollout_percent: input.rolloutPercent, p_reason: input.reason,
    }),
    onSuccess: refresh,
  });

  const revokeDevice = useMutation({
    mutationFn: async (input: { deviceId: string; reason: string }) => auth.isMock ? input : rpc('revoke_managed_device', { p_device_id: input.deviceId, p_reason: input.reason }),
    onSuccess: refresh,
  });

  const createAccessReview = useMutation({
    mutationFn: async (input: { name: string; description: string; dueAt: string }) => auth.isMock ? input : rpc('create_access_review_campaign', { p_name: input.name, p_description: input.description || null, p_due_at: input.dueAt }),
    onSuccess: refresh,
  });

  const decideAccessReview = useMutation({
    mutationFn: async (input: { itemId: string; decision: 'keep' | 'revoke'; reason: string }) => auth.isMock ? input : rpc('decide_access_review_item', { p_item_id: input.itemId, p_decision: input.decision, p_reason: input.reason }),
    onSuccess: refresh,
  });

  const requestBreakGlass = useMutation({
    mutationFn: async (input: { targetUserId: string; roleId: string; durationMinutes: number; reason: string }) => auth.isMock ? input : rpc('request_break_glass', { p_target_user_id: input.targetUserId, p_role_id: input.roleId, p_duration_minutes: input.durationMinutes, p_reason: input.reason }),
    onSuccess: refresh,
  });

  const approveBreakGlass = useMutation({
    mutationFn: async (input: { requestId: string; reason: string }) => auth.isMock ? input : rpc('approve_break_glass', { p_request_id: input.requestId, p_reason: input.reason }),
    onSuccess: refresh,
  });

  const rejectBreakGlass = useMutation({
    mutationFn: async (input: { requestId: string; reason: string }) => auth.isMock ? input : rpc('reject_break_glass', { p_request_id: input.requestId, p_reason: input.reason }),
    onSuccess: refresh,
  });

  const decidePrivacy = useMutation({
    mutationFn: async (input: { requestId: string; status: 'in_review' | 'waiting_requester' | 'approved' | 'rejected' | 'completed'; reason: string }) => auth.isMock ? input : rpc('decide_privacy_request', { p_request_id: input.requestId, p_status: input.status, p_reason: input.reason || null }),
    onSuccess: refresh,
  });

  return { updatePolicy, revokeDevice, createAccessReview, decideAccessReview, requestBreakGlass, approveBreakGlass, rejectBreakGlass, decidePrivacy };
}
