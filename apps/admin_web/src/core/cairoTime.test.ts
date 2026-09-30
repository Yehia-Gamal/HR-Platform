import { describe, it, expect } from 'vitest';
import { cairoTodayIso, cairoMonthIso, addDays, startOfWeek, endOfWeek, startOfMonth, endOfMonth, formatISO } from './cairoTime';

describe('cairoTime calculations', () => {
  it('cairoTodayIso returns a valid YYYY-MM-DD string', () => {
    const today = cairoTodayIso();
    expect(today).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });

  it('cairoMonthIso returns a valid YYYY-MM string', () => {
    const month = cairoMonthIso();
    expect(month).toMatch(/^\d{4}-\d{2}$/);
    expect(month).toBe(cairoTodayIso().slice(0, 7));
  });

  describe('startOfWeek and endOfWeek (Week starts on Saturday, ends on Thursday)', () => {
    it('accurately calculates week range for a Friday date (weekly rest day)', () => {
      // 2026-05-01 is a Friday. Week started on Saturday 2026-04-25 and ended on Thursday 2026-04-30.
      expect(startOfWeek('2026-05-01')).toBe('2026-04-25');
      expect(endOfWeek('2026-05-01')).toBe('2026-04-30');
    });

    it('accurately calculates week range for a Saturday date (start of week)', () => {
      // 2026-05-02 is a Saturday. Week starts Saturday 2026-05-02 and ends Thursday 2026-05-07.
      expect(startOfWeek('2026-05-02')).toBe('2026-05-02');
      expect(endOfWeek('2026-05-02')).toBe('2026-05-07');
    });

    it('accurately calculates week range for a Sunday date', () => {
      // 2026-05-03 is a Sunday. Week starts Saturday 2026-05-02 and ends Thursday 2026-05-07.
      expect(startOfWeek('2026-05-03')).toBe('2026-05-02');
      expect(endOfWeek('2026-05-03')).toBe('2026-05-07');
    });

    it('accurately calculates week range for a Thursday date (end of week)', () => {
      // 2026-05-07 is a Thursday. Week starts Saturday 2026-05-02 and ends Thursday 2026-05-07.
      expect(startOfWeek('2026-05-07')).toBe('2026-05-02');
      expect(endOfWeek('2026-05-07')).toBe('2026-05-07');
    });

    it('does not shift dates backwards when passing local Date object at midnight', () => {
      const may2 = new Date(2026, 4, 2); // Saturday
      expect(startOfWeek(may2)).toBe('2026-05-02');
      expect(endOfWeek(may2)).toBe('2026-05-07');
    });
  });

  describe('startOfMonth and endOfMonth', () => {
    it('accurately calculates month range for May (31 days)', () => {
      expect(startOfMonth('2026-05-15')).toBe('2026-05-01');
      expect(endOfMonth('2026-05-15')).toBe('2026-05-31');
    });

    it('accurately calculates month range for April (30 days)', () => {
      expect(startOfMonth('2026-04-10')).toBe('2026-04-01');
      expect(endOfMonth('2026-04-10')).toBe('2026-04-30');
    });

    it('accurately calculates month range for February (non-leap year 2026: 28 days)', () => {
      expect(startOfMonth('2026-02-14')).toBe('2026-02-01');
      expect(endOfMonth('2026-02-14')).toBe('2026-02-28');
    });

    it('accurately calculates month range for February (leap year 2028: 29 days)', () => {
      expect(startOfMonth('2028-02-14')).toBe('2028-02-01');
      expect(endOfMonth('2028-02-14')).toBe('2028-02-29');
    });
  });

  describe('addDays', () => {
    it('correctly adds days across month boundaries', () => {
      expect(addDays('2026-04-28', 5)).toBe('2026-05-03');
      expect(addDays('2026-05-01', -2)).toBe('2026-04-29');
    });
  });

  describe('formatISO', () => {
    it('formats string or Date into YYYY-MM-DD correctly', () => {
      expect(formatISO('2026-05-01')).toBe('2026-05-01');
    });
  });
});
