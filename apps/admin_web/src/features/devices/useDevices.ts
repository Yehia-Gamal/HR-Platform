import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';

export interface PendingDevice {
  id: string;
  employeeId: string;
  employeeName: string;
  employeeCode: string | null;
  employeePhotoUrl: string | null;
  deviceName: string | null;
  platform: string;
  status: 'pending' | 'blocked';
  registeredAt: string;
  lastUsedAt: string | null;
  rejectionReason: string | null;
  revocationSource: string | null;
  metadata: Record<string, unknown>;
}

export interface AdminDevice {
  id: string;
  employeeId: string;
  employeeName: string;
  employeeCode: string | null;
  deviceName: string | null;
  platform: string;
  status: 'pending' | 'active' | 'blocked' | 'revoked' | 'replaced' | 'auto_revoked';
  registeredAt: string;
  approvedAt: string | null;
  revokedAt: string | null;
  lastUsedAt: string | null;
  rejectionReason: string | null;
  revocationSource: string | null;
}

export function useDeviceApprovals() {
  const auth = useAuth();
  return useQuery({
    queryKey: ['device-approvals', auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<PendingDevice[]> => {
      if (auth.isMock) return [];
      return (await rpc<PendingDevice[]>('get_pending_devices_admin')) ?? [];
    },
  });
}

export function useApproveDevice() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ deviceId, approved, reason }: { deviceId: string; approved: boolean; reason?: string }) => {
      return rpc('approve_device', {
        p_device_id: deviceId,
        p_approved: approved,
        p_reason: reason ?? null,
      });
    },
    meta: { successMessage: 'تم البتّ في طلب الجهاز بنجاح' },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['device-approvals'] });
      void qc.invalidateQueries({ queryKey: ['all-devices'] });
    },
  });
}

export function useAllDevices(status?: string, includeTerminated = false) {
  const auth = useAuth();
  return useQuery({
    queryKey: ['all-devices', status, includeTerminated, auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<AdminDevice[]> => {
      if (auth.isMock) return [];
      return (
        (await rpc<AdminDevice[]>('get_all_devices_admin', {
          p_status_filter: status ?? null,
          p_include_terminated: includeTerminated,
        })) ?? []
      );
    },
  });
}

export function useRevokeDevice() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ deviceId, reason }: { deviceId: string; reason?: string }) => {
      return rpc('admin_revoke_device', {
        p_device_id: deviceId,
        p_reason: reason ?? null,
      });
    },
    meta: { successMessage: 'تم سحب صلاحية الجهاز بنجاح' },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['device-approvals'] });
      void qc.invalidateQueries({ queryKey: ['all-devices'] });
    },
  });
}

export function useDeleteDevice() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ deviceId, reason }: { deviceId: string; reason?: string }) => {
      return rpc('admin_delete_device', {
        p_device_id: deviceId,
        p_reason: reason ?? null,
      });
    },
    meta: { successMessage: 'تم حذف الجهاز نهائياً' },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['device-approvals'] });
      void qc.invalidateQueries({ queryKey: ['all-devices'] });
    },
  });
}
