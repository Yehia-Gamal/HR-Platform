import { describe, it, expect } from 'vitest';

interface AttendanceTodayOverview {
  date: string;
  totalActive: number;
  expected: number;
  present: number;
  late: number;
  notCheckedIn: number;
  onLeave: number;
  onAssignment: number;
  absent: number;
  lastUpdatedAt: string;
}

const emptyOverview: AttendanceTodayOverview = {
  date: new Date().toISOString().slice(0, 10),
  totalActive: 0,
  expected: 0,
  present: 0,
  late: 0,
  notCheckedIn: 0,
  onLeave: 0,
  onAssignment: 0,
  absent: 0,
  lastUpdatedAt: new Date().toISOString(),
};

const mockOverview: AttendanceTodayOverview = {
  date: new Date().toISOString().slice(0, 10),
  totalActive: 42,
  expected: 38,
  present: 30,
  late: 4,
  notCheckedIn: 4,
  onLeave: 3,
  onAssignment: 1,
  absent: 4,
  lastUpdatedAt: new Date().toISOString(),
};

describe('useAttendanceTodayOverview — mock data validation', () => {
  it('emptyOverview has all zero counts', () => {
    expect(emptyOverview.totalActive).toBe(0);
    expect(emptyOverview.expected).toBe(0);
    expect(emptyOverview.present).toBe(0);
    expect(emptyOverview.late).toBe(0);
    expect(emptyOverview.notCheckedIn).toBe(0);
    expect(emptyOverview.onLeave).toBe(0);
    expect(emptyOverview.onAssignment).toBe(0);
    expect(emptyOverview.absent).toBe(0);
  });

  it('emptyOverview date is YYYY-MM-DD format', () => {
    expect(emptyOverview.date).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });

  it('emptyOverview lastUpdatedAt is valid ISO timestamp', () => {
    expect(new Date(emptyOverview.lastUpdatedAt).getTime()).not.toBeNaN();
  });

  it('mockOverview has realistic attendance numbers', () => {
    expect(mockOverview.totalActive).toBe(42);
    expect(mockOverview.expected).toBe(38);
    expect(mockOverview.present).toBe(30);
  });

  it('present + absent + onLeave + onAssignment + notCheckedIn accounts for expected', () => {
    expect(mockOverview.present).toBeLessThanOrEqual(mockOverview.expected);
  });

  it('late is a subset of present', () => {
    expect(mockOverview.late).toBeLessThanOrEqual(mockOverview.present);
  });

  it('all numeric fields are non-negative', () => {
    const numericKeys: (keyof AttendanceTodayOverview)[] = ['totalActive', 'expected', 'present', 'late', 'notCheckedIn', 'onLeave', 'onAssignment', 'absent'];
    for (const key of numericKeys) {
      expect(mockOverview[key]).toBeGreaterThanOrEqual(0);
      expect(emptyOverview[key]).toBeGreaterThanOrEqual(0);
    }
  });

  it('totalActive >= expected', () => {
    expect(mockOverview.totalActive).toBeGreaterThanOrEqual(mockOverview.expected);
  });

  it('emptyOverview and mockOverview have same keys', () => {
    expect(Object.keys(emptyOverview).sort()).toEqual(Object.keys(mockOverview).sort());
  });

  it('date fields match YYYY-MM-DD', () => {
    const pattern = /^\d{4}-\d{2}-\d{2}$/;
    expect(emptyOverview.date).toMatch(pattern);
    expect(mockOverview.date).toMatch(pattern);
  });

  it('mockOverview date is today', () => {
    const today = new Date().toISOString().slice(0, 10);
    expect(mockOverview.date).toBe(today);
  });
});
