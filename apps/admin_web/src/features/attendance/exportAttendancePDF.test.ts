import { describe, it, expect } from 'vitest';
import { fmtTime, pctColor, esc } from './exportAttendancePDF';

describe('fmtTime', () => {
  it('returns "—" for null', () => {
    expect(fmtTime(null)).toBe('—');
  });

  it('returns first 5 chars of "08:30:00" → "08:30"', () => {
    expect(fmtTime('08:30:00')).toBe('08:30');
  });

  it('returns first 5 chars of "14:15" → "14:15"', () => {
    expect(fmtTime('14:15')).toBe('14:15');
  });
});

describe('pctColor', () => {
  it('returns green (#059669) for 100', () => {
    expect(pctColor(100)).toBe('#059669');
  });

  it('returns green (#059669) for 95', () => {
    expect(pctColor(95)).toBe('#059669');
  });

  it('returns green (#059669) for 90', () => {
    expect(pctColor(90)).toBe('#059669');
  });

  it('returns amber (#f59e0b) for 89', () => {
    expect(pctColor(89)).toBe('#f59e0b');
  });

  it('returns amber (#f59e0b) for 80', () => {
    expect(pctColor(80)).toBe('#f59e0b');
  });

  it('returns amber (#f59e0b) for 75', () => {
    expect(pctColor(75)).toBe('#f59e0b');
  });

  it('returns red (#dc2626) for 74', () => {
    expect(pctColor(74)).toBe('#dc2626');
  });

  it('returns red (#dc2626) for 50', () => {
    expect(pctColor(50)).toBe('#dc2626');
  });

  it('returns red (#dc2626) for 0', () => {
    expect(pctColor(0)).toBe('#dc2626');
  });
});

describe('esc', () => {
  it('escapes & to &amp;', () => {
    expect(esc('a&b')).toBe('a&amp;b');
  });

  it('escapes < to &lt;', () => {
    expect(esc('a<b')).toBe('a&lt;b');
  });

  it('escapes > to &gt;', () => {
    expect(esc('a>b')).toBe('a&gt;b');
  });

  it('escapes " to &quot;', () => {
    expect(esc('a"b')).toBe('a&quot;b');
  });

  it('handles null → empty string', () => {
    expect(esc(null)).toBe('');
  });

  it('handles undefined → empty string', () => {
    expect(esc(undefined)).toBe('');
  });

  it('handles numbers → string representation', () => {
    expect(esc(42)).toBe('42');
  });

  it('handles combined escaping', () => {
    expect(esc('<script>"alert(1)"</script>')).toBe(
      '&lt;script&gt;&quot;alert(1)&quot;&lt;/script&gt;',
    );
  });
});
