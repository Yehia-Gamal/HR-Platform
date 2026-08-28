import { type KpiEvaluationSummary } from '@ahla/shared-contracts';
import { useQuery } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';
import { loadDomainMocks } from '../mock/loadDomainMocks';

export type { KpiEvaluationSummary } from '@ahla/shared-contracts';

export interface KpiCycleSnapshot {
  id: string;
  periodMonth: string;
  status: string;
  templateName: string;
  evaluations: number;
  finalized: number;
  averageScore: number | null;
}

export interface KpiHistoricalData {
  cycles: KpiCycleSnapshot[];
  stageCounts: Record<string, number>;
  currentEvaluations: KpiEvaluationSummary[];
}

export function useKpiHistory() {
  const auth = useAuth();
  return useQuery({
    queryKey: ['kpi-history', auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<KpiHistoricalData> => {
      if (auth.isMock) {
        const mocks = await loadDomainMocks();
        return {
          cycles: mocks.mockKpiCycles ?? [],
          stageCounts: mocks.mockKpiStageCounts ?? {},
          currentEvaluations: mocks.mockKpiEvaluations ?? [],
        };
      }
      const [catalog, inbox] = await Promise.all([rpc('get_kpi_admin_catalog'), rpc('get_kpi_inbox', { p_limit: 200 })]);
      const cycles = (catalog?.cycles as KpiCycleSnapshot[]) ?? [];
      const stageCounts = (catalog?.stageCounts as Record<string, number>) ?? {};
      return {
        cycles,
        stageCounts,
        currentEvaluations: inbox ?? [],
      };
    },
  });
}

export function useKpiComparisonData(periodMonth?: string) {
  const auth = useAuth();
  return useQuery({
    queryKey: ['kpi-comparison', periodMonth, auth.isMock],
    enabled: auth.status === 'authenticated' && Boolean(periodMonth),
    queryFn: async () => {
      if (auth.isMock) {
        const mocks = await loadDomainMocks();
        return { previous: null, current: mocks.mockKpiEvaluations ?? [] };
      }
      const current = await rpc('get_kpi_inbox', { p_limit: 200 });
      const previous = periodMonth ? await rpc('get_kpi_inbox', { p_limit: 200, p_period_month: periodMonth }) : null;
      return { previous: previous ?? [], current: current ?? [] };
    },
  });
}

export function computePeriodComparison(current: KpiEvaluationSummary[], previous: KpiEvaluationSummary[]) {
  const currentScores = current.filter((e) => e.finalScore !== null).map((e) => e.finalScore!);
  const previousScores = previous.filter((e) => e.finalScore !== null).map((e) => e.finalScore!);

  const avg = (arr: number[]) => (arr.length ? arr.reduce((a, b) => a + b, 0) / arr.length : 0);

  const byCriterionCurrent: Record<string, number[]> = {};
  const byCriterionPrevious: Record<string, number[]> = {};

  current.forEach((e) => {
    if (e.finalBreakdown) {
      Object.entries(e.finalBreakdown).forEach(([code, score]) => {
        if (typeof score === 'number') {
          (byCriterionCurrent[code] ??= []).push(score);
        }
      });
    }
  });

  previous.forEach((e) => {
    if (e.finalBreakdown) {
      Object.entries(e.finalBreakdown).forEach(([code, score]) => {
        if (typeof score === 'number') {
          (byCriterionPrevious[code] ??= []).push(score);
        }
      });
    }
  });

  const criteriaCodes = ['TARGET', 'EFFICIENCY', 'ATTENDANCE', 'CONDUCT', 'PRAYER', 'HALAQA', 'INITIATIVES'] as const;

  const criterionComparison = criteriaCodes.map((code) => ({
    code,
    currentAvg: avg(byCriterionCurrent[code] ?? []),
    previousAvg: avg(byCriterionPrevious[code] ?? []),
    delta: avg(byCriterionCurrent[code] ?? []) - avg(byCriterionPrevious[code] ?? []),
  }));

  return {
    overall: {
      currentAvg: avg(currentScores),
      previousAvg: avg(previousScores),
      delta: avg(currentScores) - avg(previousScores),
      currentCount: currentScores.length,
      previousCount: previousScores.length,
    },
    byCriterion: criterionComparison,
    distribution: {
      current: computeDistribution(currentScores),
      previous: computeDistribution(previousScores),
    },
  };
}

function computeDistribution(scores: number[]) {
  const bins = [0, 20, 40, 60, 80, 100];
  const dist = bins.slice(0, -1).map((min, i) => ({
    range: `${min}-${bins[i + 1]}`,
    count: scores.filter((s) => s >= min && s < bins[i + 1]).length,
  }));
  return dist;
}

export function prepareTrendData(cycles: KpiCycleSnapshot[]) {
  return cycles
    .slice()
    .sort((a, b) => a.periodMonth.localeCompare(b.periodMonth))
    .map((c) => ({
      period: c.periodMonth,
      averageScore: c.averageScore ?? 0,
      evaluations: c.evaluations,
      finalized: c.finalized,
      completionRate: c.evaluations ? (c.finalized / c.evaluations) * 100 : 0,
    }));
}
