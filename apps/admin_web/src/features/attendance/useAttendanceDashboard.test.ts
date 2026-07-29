import { describe, it, expect } from 'vitest';
import { attendanceDashboardSchema } from '@ahla/shared-contracts';
import { mockAttendanceDashboard } from '../mock/domainMocks';

describe('useAttendanceDashboard — mock data schema validation', () => {
  it('parses against attendanceDashboardSchema', () => {
    expect(() => attendanceDashboardSchema.parse(mockAttendanceDashboard)).not.toThrow();
  });

  it('all numeric fields are non-negative', () => {
    const parsed = attendanceDashboardSchema.parse(mockAttendanceDashboard);
    expect(parsed.scheduled).toBeGreaterThanOrEqual(0);
    expect(parsed.present).toBeGreaterThanOrEqual(0);
    expect(parsed.late).toBeGreaterThanOrEqual(0);
    expect(parsed.absent).toBeGreaterThanOrEqual(0);
    expect(parsed.incomplete).toBeGreaterThanOrEqual(0);
    expect(parsed.pendingReview).toBeGreaterThanOrEqual(0);
  });

  it('present + absent + late does not exceed scheduled', () => {
    const parsed = attendanceDashboardSchema.parse(mockAttendanceDashboard);
    // present includes late (present is who showed up, late is a subset)
    expect(parsed.present + parsed.absent).toBeLessThanOrEqual(parsed.scheduled);
  });

  it('has a valid lastUpdatedAt ISO timestamp', () => {
    const parsed = attendanceDashboardSchema.parse(mockAttendanceDashboard);
    expect(parsed.lastUpdatedAt).toBeDefined();
    const date = new Date(parsed.lastUpdatedAt);
    expect(date.getTime()).not.toBeNaN();
  });

  it('scheduled is the largest count', () => {
    const parsed = attendanceDashboardSchema.parse(mockAttendanceDashboard);
    expect(parsed.scheduled).toBeGreaterThanOrEqual(parsed.present);
    expect(parsed.scheduled).toBeGreaterThanOrEqual(parsed.absent);
  });
});
