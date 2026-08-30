import { describe, expect, it } from 'vitest';
import { buildComparisonCsv, deriveDeltas, deriveHistory, formatMonthLabel, toEvaluationsSeries, toRadarData, toScoreSeries } from '../kpiHistory';

const cycles = [
  { periodMonth: '2026-06-01', status: 'closed', evaluations: 10, finalized: 8, overdue: 1, averageScore: 78.5 },
  { periodMonth: '2026-05-01', status: 'closed', evaluations: 12, finalized: 9, overdue: 2, averageScore: 74 },
  { periodMonth: '2026-07-01', status: 'closed', evaluations: 10, finalized: 10, overdue: 0, averageScore: 82.3 },
];

describe('kpiHistory — deriveHistory', () => {
  it('يرتب الدورات تصاعديًا حسب الشهر رغم ترتيب الإدخال', () => {
    const points = deriveHistory(cycles);
    expect(points.map((p) => p.monthKey)).toEqual(['2026-05', '2026-06', '2026-07']);
  });

  it('يحسب نسبة الإنجاز المستديرة', () => {
    const points = deriveHistory(cycles);
    const july = points.find((p) => p.monthKey === '2026-07');
    expect(july?.completionRate).toBe(100);
  });

  it('يُدمج دورات متعددة لنفس الشهر', () => {
    const merged = deriveHistory([
      { periodMonth: '2026-07-01', status: 'closed', evaluations: 10, finalized: 6, overdue: 0, averageScore: 80 },
      { periodMonth: '2026-07-01', status: 'closed', evaluations: 5, finalized: 4, overdue: 1, averageScore: 85 },
    ]);
    expect(merged).toHaveLength(1);
    expect(merged[0].evaluations).toBe(15);
    expect(merged[0].finalized).toBe(10);
    expect(merged[0].overdue).toBe(1);
  });

  it('يتجاهل الدورات بلا شهر صالح', () => {
    expect(deriveHistory([{ periodMonth: '', evaluations: 1 }])).toHaveLength(0);
    expect(deriveHistory(undefined)).toEqual([]);
  });
});

describe('kpiHistory — deriveDeltas', () => {
  it('يحسب الفروق مقابل الشهر السابق فقط', () => {
    const points = deriveHistory(cycles);
    const deltas = deriveDeltas(points);
    expect(deltas[0].averageScoreDelta).toBeNull();
    expect(deltas[1].averageScoreDelta).toBe(4.5);
    expect(deltas[2].averageScoreDelta).toBe(3.8);
    expect(deltas[2].finalizedDelta).toBe(2);
  });
});

describe('kpiHistory — toScoreSeries / toEvaluationsSeries / toRadarData', () => {
  it('يبني سلسلة متوسط الدرجات', () => {
    const series = toScoreSeries(deriveHistory(cycles));
    expect(series).toHaveLength(3);
    expect(series[0]).toHaveProperty('score');
  });

  it('يبني سلسلة الإنجاز والمتأخر', () => {
    const series = toEvaluationsSeries(deriveHistory(cycles));
    expect(series[0]).toHaveProperty('finalized');
    expect(series[0]).toHaveProperty('overdue');
  });

  it('يختار القالب الرسمي لبيانات الرادار', () => {
    const radar = toRadarData({
      templates: [
        {
          id: 't1',
          name: 'قالب قديم',
          version: 1,
          active: false,
          criteria: [{ id: 'c1', code: null, name: 'أ', weight: 20, maxScore: 20, sourceType: 'auto', attendanceMetric: null, requiresEvidence: false }],
        },
        {
          id: 't2',
          name: 'الرسمي',
          version: 3,
          active: true,
          officialCode: 'OFFICIAL_KPI_100',
          criteria: [{ id: 'c2', code: null, name: 'ب', weight: 30, maxScore: 30, sourceType: 'auto', attendanceMetric: null, requiresEvidence: false }],
        },
      ],
    });
    expect(radar).toHaveLength(1);
    expect(radar[0].subject).toBe('ب');
  });

  it('يُرجع قائمة فارغة عند غياب القوالب', () => {
    expect(toRadarData({ templates: [] })).toEqual([]);
  });
});

describe('kpiHistory — formatMonthLabel / buildComparisonCsv', () => {
  it('يُنسّق الشهر إلى تسمية عربية', () => {
    expect(formatMonthLabel('2026-07-01')).toContain('يوليو');
  });

  it('يبني ملف CSV بترويسة وصفوف', () => {
    const csv = buildComparisonCsv(deriveHistory(cycles));
    expect(csv).toContain('الشهر');
    expect(csv).toContain('متوسط الدرجات');
    expect(csv.split('\n')).toHaveLength(4);
  });
});
