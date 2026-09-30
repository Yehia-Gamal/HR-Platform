import { describe, it, expect } from 'vitest';
import { dateRange, monthDates } from './exportRangeReports';

describe('exportRangeReports date logic', () => {
  describe('dateRange', () => {
    it('generates an exact 7-day range for a week with no timezone shifts', () => {
      const dates = dateRange('2026-05-01', '2026-05-07');
      expect(dates).toHaveLength(7);
      expect(dates[0]).toBe('2026-05-01');
      expect(dates[1]).toBe('2026-05-02');
      expect(dates[2]).toBe('2026-05-03');
      expect(dates[3]).toBe('2026-05-04');
      expect(dates[4]).toBe('2026-05-05');
      expect(dates[5]).toBe('2026-05-06');
      expect(dates[6]).toBe('2026-05-07');
    });

    it('correctly handles month boundary ranges', () => {
      const dates = dateRange('2026-04-29', '2026-05-02');
      expect(dates).toEqual(['2026-04-29', '2026-04-30', '2026-05-01', '2026-05-02']);
    });

    it('handles single-day range', () => {
      const dates = dateRange('2026-05-01', '2026-05-01');
      expect(dates).toEqual(['2026-05-01']);
    });

    it('returns empty array for invalid inputs', () => {
      expect(dateRange('', '')).toEqual([]);
      expect(dateRange('invalid', 'dates')).toEqual([]);
    });
  });

  describe('monthDates', () => {
    it('generates 31 days for May 2026', () => {
      const dates = monthDates('2026-05');
      expect(dates).toHaveLength(31);
      expect(dates[0]).toBe('2026-05-01');
      expect(dates[30]).toBe('2026-05-31');
    });

    it('generates 30 days for April 2026', () => {
      const dates = monthDates('2026-04');
      expect(dates).toHaveLength(30);
      expect(dates[0]).toBe('2026-04-01');
      expect(dates[29]).toBe('2026-04-30');
    });

    it('generates 28 days for February 2026 (non-leap year)', () => {
      const dates = monthDates('2026-02');
      expect(dates).toHaveLength(28);
      expect(dates[0]).toBe('2026-02-01');
      expect(dates[27]).toBe('2026-02-28');
    });

    it('generates 29 days for February 2028 (leap year)', () => {
      const dates = monthDates('2028-02');
      expect(dates).toHaveLength(29);
      expect(dates[0]).toBe('2028-02-01');
      expect(dates[28]).toBe('2028-02-29');
    });
  });
});
