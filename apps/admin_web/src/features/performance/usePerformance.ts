import { kpiEvaluationFormSchema, kpiEvaluationSummarySchema, type KpiEvaluationSummary } from '@ahla/shared-contracts';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { getSupabase } from '../../core/supabase';
import { useAuth } from '../auth/AuthProvider';
import { loadDomainMocks } from '../mock/loadDomainMocks';

export function usePerformance() {
  const auth = useAuth();
  return useQuery({
    queryKey: ['kpi-evaluations', auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<KpiEvaluationSummary[]> => {
      if (auth.isMock) return (await loadDomainMocks()).mockKpiEvaluations;
      const supabase = await getSupabase();
      const { data, error } = await supabase.rpc('get_kpi_inbox', { p_limit: 100 });
      if (error) throw error;
      return kpiEvaluationSummarySchema.array().parse(data ?? []);
    },
  });
}

export function useAdvanceKpi() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async ({ evaluationId, action, note, scores }: { evaluationId: string; action: 'self' | 'manager_review' | 'hr_review' | 'manager_final'; note: string; scores?: Array<{ criterion_id: string; score: number; note: string }> }) => {
      if (auth.isMock) return { evaluationId, action };
      const supabase = await getSupabase();
      const { data, error } = await supabase.rpc('advance_kpi_stage', { p_evaluation_id: evaluationId, p_action: action, p_scores: scores ?? null, p_note: note || null });
      if (error) throw error;
      return data;
    },
    onSuccess: () => Promise.all([
      client.invalidateQueries({ queryKey: ['kpi-evaluations'] }),
      client.invalidateQueries({ queryKey: ['action-center'] }),
    ]),
  });
}

export function useKpiEvaluationForm(evaluationId: string | null) {
  const auth = useAuth();
  return useQuery({
    queryKey: ['kpi-evaluation-form', evaluationId, auth.isMock],
    enabled: auth.status === 'authenticated' && Boolean(evaluationId) && !auth.isMock,
    queryFn: async () => {
      const supabase = await getSupabase();
      const { data, error } = await supabase.rpc('get_kpi_evaluation_form', { p_evaluation_id: evaluationId! });
      if (error) throw error;
      return kpiEvaluationFormSchema.parse(data);
    },
  });
}

export function useKpiFormCommands(evaluationId: string) {
  const auth = useAuth();
  const client = useQueryClient();
  const refresh = () => Promise.all([
    client.invalidateQueries({ queryKey: ['kpi-evaluation-form', evaluationId] }),
    client.invalidateQueries({ queryKey: ['kpi-evaluations'] }),
    client.invalidateQueries({ queryKey: ['kpi-admin'] }),
  ]);
  const call = (name: string) => useMutation({
    mutationFn: async (params: Record<string, unknown>) => {
      if (auth.isMock) return params;
      const supabase = await getSupabase();
      const { data, error } = await supabase.rpc(name, params);
      if (error) throw error;
      return data;
    },
    onSuccess: refresh,
  });
  return {
    saveGoal: call('save_kpi_goal'),
    saveSession: call('save_kpi_review_session'),
    saveCompliance: call('save_kpi_compliance_metric'),
    acknowledge: call('acknowledge_kpi_evaluation'),
    returnStage: call('return_kpi_stage'),
    overrideScore: call('override_kpi_score'),
    addEvidence: call('add_kpi_evidence'),
  };
}
