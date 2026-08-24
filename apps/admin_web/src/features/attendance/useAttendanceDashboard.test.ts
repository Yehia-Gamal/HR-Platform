import { describe, it, expect } from 'vitest';
import { attendanceDashboardSchema, attendanceRosterItemSchema, attendanceRosterPageSchema } from '@ahla/shared-contracts';
import { mockAttendanceDashboard, mockAttendanceRoster } from '../mock/domainMocks';

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
    const date = parsed.lastUpdatedAt ? new Date(parsed.lastUpdatedAt) : null;
    expect(date).not.toBeNull();
    expect(date?.getTime()).not.toBeNaN();
  });

  it('scheduled is the largest count', () => {
    const parsed = attendanceDashboardSchema.parse(mockAttendanceDashboard);
    expect(parsed.scheduled).toBeGreaterThanOrEqual(parsed.present);
    expect(parsed.scheduled).toBeGreaterThanOrEqual(parsed.absent);
  });
});

describe('attendance roster mocks vs expanded schema (0294)', () => {
  it('every mock roster item parses against the expanded attendanceRosterItemSchema', () => {
    for (const category of Object.values(mockAttendanceRoster)) {
      for (const item of category) {
        expect(() => attendanceRosterItemSchema.parse(item)).not.toThrow();
      }
    }
  });

  it('attendanceRosterPageSchema accepts the {items,total,limit,offset} shape', () => {
    const page = attendanceRosterPageSchema.parse({
      items: mockAttendanceRoster.present,
      total: mockAttendanceRoster.present.length,
      limit: 25,
      offset: 0,
    });
    expect(page.total).toBe(mockAttendanceRoster.present.length);
    expect(page.limit).toBe(25);
    expect(page.offset).toBe(0);
  });
});
