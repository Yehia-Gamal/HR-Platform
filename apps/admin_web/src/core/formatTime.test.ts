import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { relativeTime, formatClock } from './formatTime';

// اختبارات أدوات تنسيق الوقت المشتركة
// نتحكم في "الآن" عبر تجميد وقت نسبي معروف.

describe('relativeTime', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-08-07T10:00:00Z'));
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it('يرجع fallback الافتراضي "—" للقيمة الفارغة', () => {
    expect(relativeTime(null)).toBe('—');
    expect(relativeTime(undefined)).toBe('—');
    expect(relativeTime('')).toBe('—');
  });

  it('يرجع fallback مخصص عند تمريره', () => {
    expect(relativeTime(null, 'لم يُسجل موقع بعد')).toBe('لم يُسجل موقع بعد');
  });

  it('يرجع "الآن" للأقل من دقيقة', () => {
    expect(relativeTime('2026-08-07T09:59:45Z')).toBe('الآن');
  });

  it('يرجع "منذ X د" للدقائق', () => {
    expect(relativeTime('2026-08-07T09:55:00Z')).toBe('منذ 5 د');
  });

  it('يرجع "منذ X س" للساعات', () => {
    expect(relativeTime('2026-08-07T07:00:00Z')).toBe('منذ 3 س');
  });

  it('يرجع "منذ X يوم" للأيام', () => {
    expect(relativeTime('2026-08-04T10:00:00Z')).toBe('منذ 3 يوم');
  });

  it('لا يرجع قيمة سالبة (يحدها بصفر)', () => {
    // تاريخ في المستقبل
    expect(relativeTime('2026-08-07T11:00:00Z')).toBe('الآن');
  });
});

describe('formatClock', () => {
  it('يرجع "—" للقيمة الفارغة', () => {
    expect(formatClock(null)).toBe('—');
    expect(formatClock(undefined)).toBe('—');
  });

  it('ينسّق الساعة والدقيقة فقط', () => {
    const result = formatClock('2026-08-07T14:30:00Z');
    // أرقام عربية (٠-٩) مع نقطتين — لا يحوي تاريخًا
    expect(result).toMatch(/[\u0660-\u0669]{1,2}:[\u0660-\u0669]{2}/);
    expect(result).not.toMatch(/2026/);
  });
});
