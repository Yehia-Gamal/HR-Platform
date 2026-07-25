import { describe, expect, it } from 'vitest';
import {
  gracePeriodSchema,
  attendanceReminderSchema,
  DEFAULT_ATTENDANCE_REMINDERS,
  attendanceConfigSchema,
} from './attendanceConfig.js';

describe('attendance config contracts — V17 §7', () => {
  it('default check-in is 10:00, check-out is 18:00', () => {
    const config = attendanceConfigSchema.parse({});
    expect(config.checkInTime).toBe('10:00');
    expect(config.checkOutTime).toBe('18:00');
    expect(config.timezone).toBe('Africa/Cairo');
  });

  it('default grace periods are 15 minutes each', () => {
    const grace = gracePeriodSchema.parse({});
    expect(grace.lateGraceMinutes).toBe(15);
    expect(grace.earlyLeaveGraceMinutes).toBe(15);
  });

  it('grace period rejects values > 60 minutes', () => {
    expect(() => gracePeriodSchema.parse({ lateGraceMinutes: 61 })).toThrow();
    expect(() => gracePeriodSchema.parse({ earlyLeaveGraceMinutes: -1 })).toThrow();
  });

  it('default reminders match V17 schedule (09:45, 10:00, 17:45, 18:00)', () => {
    expect(DEFAULT_ATTENDANCE_REMINDERS).toHaveLength(4);
    expect(DEFAULT_ATTENDANCE_REMINDERS[0]).toEqual({ time: '09:45', type: 'check_in_reminder' });
    expect(DEFAULT_ATTENDANCE_REMINDERS[1]).toEqual({ time: '10:00', type: 'check_in_due' });
    expect(DEFAULT_ATTENDANCE_REMINDERS[2]).toEqual({ time: '17:45', type: 'check_out_reminder' });
    expect(DEFAULT_ATTENDANCE_REMINDERS[3]).toEqual({ time: '18:00', type: 'check_out_due' });
  });

  it('reminder schema validates HH:mm format', () => {
    expect(attendanceReminderSchema.parse({ time: '09:45', type: 'check_in_reminder' }).time).toBe('09:45');
    expect(() => attendanceReminderSchema.parse({ time: '9:45', type: 'check_in_reminder' })).toThrow();
    expect(() => attendanceReminderSchema.parse({ time: '09:45:00', type: 'check_in_reminder' })).toThrow();
  });

  it('executive director is exempted by default', () => {
    const config = attendanceConfigSchema.parse({});
    expect(config.exemptRoles).toContain('executive_director');
  });

  it('full config round-trips with custom values', () => {
    const config = attendanceConfigSchema.parse({
      checkInTime: '08:00',
      checkOutTime: '16:00',
      timezone: 'Asia/Riyadh',
      gracePeriod: { lateGraceMinutes: 10, earlyLeaveGraceMinutes: 5 },
      reminders: [{ time: '07:45', type: 'check_in_reminder' }],
      exemptRoles: ['executive_director', 'chairman'],
    });
    expect(config.checkInTime).toBe('08:00');
    expect(config.gracePeriod.lateGraceMinutes).toBe(10);
    expect(config.reminders).toHaveLength(1);
    expect(config.exemptRoles).toHaveLength(2);
  });
});
