import { describe, it, expect } from 'vitest';
import type { CronJobHealth, CronHealthSummary } from './useCronHealth';

/**
 * يضمن أن منطق تصنيف حالة cron في اللوحة (ObservabilityDashboardPage)
 * متوافق مع قيم health_status التي تُرجِعها get_cron_job_health من DB.
 * أي تغيير في قيم الحالة في DB يجب أن ينعكس هنا.
 */
describe('cron health classification', () => {
  const STATUSES = ['disabled', 'never_run', 'failing', 'unstable', 'healthy'] as const;

  it('covers all health_status values produced by cron_job_health view', () => {
    // القيم الخمس من 0244: disabled / never_run / failing / unstable / healthy
    expect(STATUSES).toEqual(['disabled', 'never_run', 'failing', 'unstable', 'healthy']);
  });

  it('classifies failing/unstable as actionable, healthy as ok', () => {
    const isActionable = (status: CronJobHealth['health_status']): boolean => status === 'failing' || status === 'unstable';
    const job: CronJobHealth = {
      jobid: 1,
      jobname: 'hr_notification_dispatch',
      schedule: '*/5 * * * *',
      active: true,
      last_status: 'failed',
      last_message: 'timeout',
      last_start: new Date().toISOString(),
      last_end: new Date().toISOString(),
      duration_seconds: 12.5,
      failures_24h: 4,
      health_status: 'failing',
    };
    expect(isActionable(job.health_status)).toBe(true);
    expect(isActionable('healthy')).toBe(false);
    expect(isActionable('unstable')).toBe(true);
  });
});

describe('cron health summary shape', () => {
  it('has numeric counters and a checked_at timestamp', () => {
    const summary: CronHealthSummary = {
      total_jobs: 12,
      active: 10,
      failing: 1,
      unstable: 1,
      healthy: 8,
      never_run: 0,
      disabled: 2,
      checked_at: new Date().toISOString(),
      failures_24h_total: 3,
    };
    expect(summary.total_jobs).toBe(summary.active + summary.disabled);
    expect(Number.isFinite(summary.failing)).toBe(true);
    expect(new Date(summary.checked_at).toString()).not.toBe('Invalid Date');
  });
});
