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
    meta: { successMessage: 'تم تقديم تقييم الأداء بنجاح' },
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

// ---------------------------------------------------------------------------
// مساعد يُرجع خيارات mutation عادية — لا يستدعي hooks.
// كل hook يستدعي useMutation مباشرة لضمان التوافق مع Rules of Hooks.
// ---------------------------------------------------------------------------
function kpiFormMutationOpts(
  isMock: boolean,
  name: string,
  refresh: () => Promise<unknown>,
  successMessage?: string,
) {
  return {
    mutationFn: async (params: Record<string, unknown>) => {
      if (isMock) return params;
      return rpc(name, params);
    },
    meta: successMessage ? { successMessage } : undefined,
    onSuccess: refresh,
  };
}

export function useKpiFormCommands(evaluationId: string) {
  const auth = useAuth();
  const client = useQueryClient();
  const refresh = () => Promise.all([
    client.invalidateQueries({ queryKey: ['kpi-evaluation-form', evaluationId] }),
    client.invalidateQueries({ queryKey: ['kpi-evaluations'] }),
    client.invalidateQueries({ queryKey: ['kpi-admin'] }),
  ]);
  return {
    saveGoal: useMutation(kpiFormMutationOpts(auth.isMock, 'save_kpi_goal', refresh, 'تم حفظ الهدف بنجاح')),
    saveSession: useMutation(kpiFormMutationOpts(auth.isMock, 'save_kpi_review_session', refresh, 'تم حفظ جلسة المراجعة بنجاح')),
    saveCompliance: useMutation(kpiFormMutationOpts(auth.isMock, 'save_kpi_compliance_metric', refresh, 'تم حفظ مؤشر الامتثال بنجاح')),
    acknowledge: useMutation(kpiFormMutationOpts(auth.isMock, 'acknowledge_kpi_evaluation', refresh, 'تم الاطلاع على التقييم بنجاح')),
    returnStage: useMutation(kpiFormMutationOpts(auth.isMock, 'return_kpi_stage', refresh, 'تم إرجاع المرحلة بنجاح')),
    overrideScore: useMutation(kpiFormMutationOpts(auth.isMock, 'override_kpi_score', refresh, 'تم تعديل الدرجة بنجاح')),
    addEvidence: useMutation(kpiFormMutationOpts(auth.isMock, 'add_kpi_evidence', refresh, 'تمت إضافة المستند الداعم بنجاح')),
  };
}
