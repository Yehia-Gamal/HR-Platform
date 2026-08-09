import { describe, it, expect } from 'vitest';
import { LIFECYCLE_STAGES, JOURNEY_STATUS_LABELS, TASK_STATUS_LABELS, TASK_STATUS_ORDER } from './useLifecycle';

describe('lifecycle constants', () => {
  it('exports correct stages', () => {
    expect(LIFECYCLE_STAGES).toContain('onboarding');
    expect(LIFECYCLE_STAGES).toContain('active');
    expect(LIFECYCLE_STAGES).toHaveLength(4);
  });

  it('has Arabic labels for journey statuses', () => {
    expect(JOURNEY_STATUS_LABELS.not_started).toBe('لم تبدأ');
    expect(JOURNEY_STATUS_LABELS.in_progress).toBe('قيد التنفيذ');
    expect(JOURNEY_STATUS_LABELS.completed).toBe('مكتملة');
  });

  it('has Arabic labels for task statuses', () => {
    expect(TASK_STATUS_LABELS.pending).toBe('قيد الانتظار');
    expect(TASK_STATUS_LABELS.completed).toBe('مكتمل');
    expect(TASK_STATUS_LABELS.skipped).toBe('تم تجاوزها');
  });

  it('task status order is correct', () => {
    expect(TASK_STATUS_ORDER[0]).toBe('pending');
    expect(TASK_STATUS_ORDER[TASK_STATUS_ORDER.length - 1]).toBe('skipped');
  });
});
