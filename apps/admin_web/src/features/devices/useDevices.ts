import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { getSupabase } from '../../core/supabase';
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
  metadata: Record<string, unknown>;
}

export function useDeviceApprovals() {
  const auth = useAuth();
  return useQuery({
    queryKey: ['device-approvals', auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<PendingDevice[]> => {
      if (auth.isMock) return [];
      const supabase = await getSupabase();
      const { data, error } = await supabase.rpc('get_pending_devices_admin');
      if (error) throw error;
      return (data as PendingDevice[]) ?? [];
    },
  });
}

export function useApproveDevice() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ deviceId, approved, reason }: { deviceId: string; approved: boolean; reason?: string }) => {
      const supabase = await getSupabase();
      const { data, error } = await supabase.rpc('approve_device', {
        p_device_id: deviceId,
        p_approved: approved,
        p_reason: reason ?? null,
      });
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['device-approvals'] });
    },
  });
}
