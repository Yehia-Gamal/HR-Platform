import { kpiEvaluationFormSchema, kpiEvaluationSummarySchema, type KpiEvaluationSummary } from '@ahla/shared-contracts';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';
import { loadDomainMocks } from '../mock/loadDomainMocks';

export function usePerformance() {
  const auth = useAuth();
  return useQuery({
    queryKey: ['kpi-evaluations', auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<KpiEvaluationSummary[]> => {
      if (auth.isMock) return (await loadDomainMocks()).mockKpiEvaluations;
      const data = await rpc('get_kpi_inbox', { p_limit: 100 });
      return kpiEvaluationSummarySchema.array().parse(data ?? []);
    },
  });
}

// V23: وسّعنا نوع action ليشمل مراحل المسار المتوازي الجديدة.
export function useAdvanceKpi() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async ({ evaluationId, action, note, scores }: { evaluationId: string; action: string; note: string; scores?: Array<{ criterion_id: string; score: number; note: string }> }) => {
      if (auth.isMock) return { evaluationId, action };
      return rpc('advance_kpi_stage', { p_evaluation_id: evaluationId, p_action: action, p_scores: scores ?? null, p_note: note || null });
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
      const data = await rpc('get_kpi_evaluation_form', { p_evaluation_id: evaluationId! });
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
      return rpc(name, params);
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
