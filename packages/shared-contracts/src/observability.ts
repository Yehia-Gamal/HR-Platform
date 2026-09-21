import { z } from 'zod';

const uuid = z.string().uuid();

/** صحة مهمة pg_cron واحدة */
export const cronJobHealthSchema = z
  .object({
    jobid: z.number().int(),
    jobname: z.string(),
    schedule: z.string(),
    active: z.boolean(),
    last_status: z.string().nullable(),
    last_message: z.string().nullable(),
    last_start: z.string().nullable(),
    last_end: z.string().nullable(),
    duration_seconds: z.number().nullable(),
    failures_24h: z.number().int(),
    health_status: z.enum(['disabled', 'never_run', 'failing', 'unstable', 'healthy']),
  })
  .strict();
export type CronJobHealth = z.infer<typeof cronJobHealthSchema>;

/** ملخص صحة pg_cron */
export const cronHealthSummarySchema = z
  .object({
    total_jobs: z.number().int(),
    active: z.number().int(),
    failing: z.number().int(),
    unstable: z.number().int(),
    healthy: z.number().int(),
    never_run: z.number().int(),
    disabled: z.number().int(),
    checked_at: z.string(),
    failures_24h_total: z.number().int(),
  })
  .strict();
export type CronHealthSummary = z.infer<typeof cronHealthSummarySchema>;

/** حدث observability */
export const observabilityEventSchema = z
  .object({
    id: uuid,
    created_at: z.string(),
    level: z.enum(['debug', 'info', 'warning', 'error', 'critical']),
    source: z.string(),
    event_type: z.string(),
    request_id: z.string().nullable(),
    message: z.string(),
    error_name: z.string().nullable(),
    duration_ms: z.number().nullable(),
    metadata: z.record(z.string(), z.unknown()),
  })
  .strict();
export type ObservabilityEvent = z.infer<typeof observabilityEventSchema>;
