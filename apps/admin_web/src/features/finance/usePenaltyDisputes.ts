import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';

export interface PenaltyDispute {
  id: string;
  penalty_id: string;
  employee_id: string;
  employee_name: string;
  department: string;
  penalty_date: string;
  penalty_amount: number;
  reason: string;
  status: 'pending' | 'approved' | 'rejected';
  reviewed_by: string | null;
  reviewer_name: string | null;
  review_note: string | null;
  reviewed_at: string | null;
  created_at: string;
}

export function usePenaltyDisputes(statusFilter?: string) {
  const auth = useAuth();
  return useQuery<PenaltyDispute[]>({
    queryKey: ['penaltyDisputes', statusFilter],
    enabled: auth.status === 'authenticated',
    queryFn: async () => {
      const data = await rpc<PenaltyDispute[]>('get_penalty_disputes', {
        p_status: statusFilter || null,
      });
      return data ?? [];
    },
  });
}

export function useSubmitPenaltyDispute() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ penaltyId, reason }: { penaltyId: string; reason: string }) => {
      const data = await rpc<string>('submit_penalty_dispute', {
        p_penalty_id: penaltyId,
        p_reason: reason,
      });
      return data;
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['penaltyDisputes'] });
    },
  });
}

export function useReviewPenaltyDispute() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ disputeId, status, note }: { disputeId: string; status: 'approved' | 'rejected'; note?: string }) => {
      await rpc('review_penalty_dispute', {
        p_dispute_id: disputeId,
        p_status: status,
        p_review_note: note || null,
      });
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['penaltyDisputes'] });
      void qc.invalidateQueries({ queryKey: ['instant-penalties'] });
    },
  });
}
