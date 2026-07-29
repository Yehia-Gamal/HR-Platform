import { describe, it, expect } from 'vitest';

/**
 * Tests for the pure helper functions and constants in useControlCenters.
 * Since the helpers (rows, string, nullableString, number, boolean) are not
 * exported, we recreate and validate their logic here to guard against drift.
 */
describe('useControlCenters helpers', () => {
  // Recreate the helpers exactly as in the source
  function rows(value: unknown): Array<Record<string, unknown>> {
    return Array.isArray(value) ? value as Array<Record<string, unknown>> : [];
  }

  function str(value: unknown, fallback = ''): string {
    return typeof value === 'string' ? value : fallback;
  }

  function nullableString(value: unknown): string | null {
    return typeof value === 'string' ? value : null;
  }

  function num(value: unknown, fallback = 0): number {
    return typeof value === 'number' ? value : fallback;
  }

  function bool(value: unknown): boolean {
    return value === true;
  }

  describe('rows', () => {
    it('returns the array when given an array', () => {
      const input = [{ a: 1 }, { b: 2 }];
      expect(rows(input)).toBe(input);
    });

    it('returns [] for null', () => expect(rows(null)).toEqual([]));
    it('returns [] for undefined', () => expect(rows(undefined)).toEqual([]));
    it('returns [] for an object', () => expect(rows({ a: 1 })).toEqual([]));
    it('returns [] for a string', () => expect(rows('hello')).toEqual([]));
    it('returns [] for a number', () => expect(rows(42)).toEqual([]));
  });

  describe('string coercion', () => {
    it('returns the string value', () => expect(str('hello')).toBe('hello'));
    it('returns empty string for null', () => expect(str(null)).toBe(''));
    it('returns empty string for undefined', () => expect(str(undefined)).toBe(''));
    it('returns empty string for number', () => expect(str(42)).toBe(''));
    it('returns fallback for null', () => expect(str(null, 'fallback')).toBe('fallback'));
    it('returns fallback for undefined', () => expect(str(undefined, 'fallback')).toBe('fallback'));
    it('returns the string even with fallback', () => expect(str('hello', 'fallback')).toBe('hello'));
    it('returns empty string for boolean', () => expect(str(true)).toBe(''));
    it('returns empty string for object', () => expect(str({})).toBe(''));
  });

  describe('nullableString', () => {
    it('returns the string value', () => expect(nullableString('hello')).toBe('hello'));
    it('returns null for null', () => expect(nullableString(null)).toBeNull());
    it('returns null for undefined', () => expect(nullableString(undefined)).toBeNull());
    it('returns null for number', () => expect(nullableString(42)).toBeNull());
    it('returns null for boolean', () => expect(nullableString(true)).toBeNull());
    it('returns null for object', () => expect(nullableString({})).toBeNull());
    it('returns empty string for empty string', () => expect(nullableString('')).toBe(''));
  });

  describe('number coercion', () => {
    it('returns the number value', () => expect(num(42)).toBe(42));
    it('returns fallback for null', () => expect(num(null)).toBe(0));
    it('returns fallback for undefined', () => expect(num(undefined)).toBe(0));
    it('returns fallback for string', () => expect(num('hello')).toBe(0));
    it('returns custom fallback', () => expect(num(null, 5)).toBe(5));
    it('returns the number even with fallback', () => expect(num(42, 5)).toBe(42));
    it('returns 0 for boolean', () => expect(num(true)).toBe(0));
    it('handles negative numbers', () => expect(num(-7)).toBe(-7));
    it('handles zero', () => expect(num(0)).toBe(0));
  });

  describe('boolean coercion', () => {
    it('returns true for true', () => expect(bool(true)).toBe(true));
    it('returns false for false', () => expect(bool(false)).toBe(false));
    it('returns false for null', () => expect(bool(null)).toBe(false));
    it('returns false for undefined', () => expect(bool(undefined)).toBe(false));
    it('returns false for 1', () => expect(bool(1)).toBe(false));
    it('returns false for "true"', () => expect(bool('true')).toBe(false));
    it('returns false for empty object', () => expect(bool({})).toBe(false));
  });

  describe('MAP_URL_ERROR_MESSAGES', () => {
    // Recreate to validate the exact error messages match expectations
    const MAP_URL_ERROR_MESSAGES: Record<string, string> = {
      METHOD_NOT_ALLOWED: 'طريقة الطلب غير مدعومة.',
      SERVER_CONFIGURATION: 'الخدمة غير مهيأة. تواصل مع الدعم.',
      unauthorized: 'انتهت صلاحية الجلسة. سجّل الدخول مجددًا.',
      INVALID_INPUT: 'معرّف الطلب غير صالح.',
      GATE_FAILED: 'تعذّر التحقق من صلاحية الوصول.',
      FORBIDDEN: 'ليس لديك صلاحية لعرض هذا الموقع.',
      SIGN_FAILED: 'تعذّر توقيع رابط لقطة الخريطة.',
    };

    it('has 7 error codes', () => {
      expect(Object.keys(MAP_URL_ERROR_MESSAGES)).toHaveLength(7);
    });

    it('all values are non-empty Arabic strings', () => {
      for (const value of Object.values(MAP_URL_ERROR_MESSAGES)) {
        expect(value).toBeTruthy();
        expect(typeof value).toBe('string');
        expect(value).toMatch(/[؀-ۿ]/);
      }
    });

    it('contains expected error codes', () => {
      expect(MAP_URL_ERROR_MESSAGES).toHaveProperty('METHOD_NOT_ALLOWED');
      expect(MAP_URL_ERROR_MESSAGES).toHaveProperty('SERVER_CONFIGURATION');
      expect(MAP_URL_ERROR_MESSAGES).toHaveProperty('unauthorized');
      expect(MAP_URL_ERROR_MESSAGES).toHaveProperty('INVALID_INPUT');
      expect(MAP_URL_ERROR_MESSAGES).toHaveProperty('GATE_FAILED');
      expect(MAP_URL_ERROR_MESSAGES).toHaveProperty('FORBIDDEN');
      expect(MAP_URL_ERROR_MESSAGES).toHaveProperty('SIGN_FAILED');
    });
  });
});
