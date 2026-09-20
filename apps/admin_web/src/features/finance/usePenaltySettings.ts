import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';

export interface PenaltySetting {
  setting_key: string;
  setting_value: unknown;
  description: string;
  updated_at: string;
}

export function usePenaltySettings() {
  return useQuery<PenaltySetting[]>({
    queryKey: ['penaltySettings'],
    queryFn: async () => {
      return await rpc<PenaltySetting[]>('get_penalty_settings');
    },
  });
}

export function useUpdatePenaltySettings() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (settings: { key: string; value: unknown }[]) => {
      await rpc('update_penalty_settings', {
        p_settings: settings,
      });
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['penaltySettings'] });
    },
  });
}
