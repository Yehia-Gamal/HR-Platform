import { describe, expect, it } from 'vitest';
import {
  TEXT_MIN_LENGTH,
  TEXT_MAX_LENGTH,
  shortTextSchema,
  longTextSchema,
  optionalShortTextSchema,
  isValidShortText,
  truncateText,
} from './validation.js';

describe('validation utils — V17 §1.3', () => {
  it('constants define 3–300 range', () => {
    expect(TEXT_MIN_LENGTH).toBe(3);
    expect(TEXT_MAX_LENGTH).toBe(300);
  });

  it('shortTextSchema accepts 3–300 chars', () => {
    expect(shortTextSchema.parse('abc')).toBe('abc');
    expect(shortTextSchema.parse('x'.repeat(300))).toHaveLength(300);
    expect(() => shortTextSchema.parse('ab')).toThrow();
    expect(() => shortTextSchema.parse('x'.repeat(301))).toThrow();
  });

  it('longTextSchema accepts 3–2000 chars', () => {
    expect(longTextSchema.parse('abc')).toBe('abc');
    expect(longTextSchema.parse('x'.repeat(2000))).toHaveLength(2000);
    expect(() => longTextSchema.parse('ab')).toThrow();
    expect(() => longTextSchema.parse('x'.repeat(2001))).toThrow();
  });

  it('optionalShortTextSchema allows undefined or up to 300', () => {
    expect(optionalShortTextSchema.parse(undefined)).toBeUndefined();
    expect(optionalShortTextSchema.parse('')).toBe('');
    expect(optionalShortTextSchema.parse('x'.repeat(300))).toHaveLength(300);
    expect(() => optionalShortTextSchema.parse('x'.repeat(301))).toThrow();
  });

  it('isValidShortText returns boolean', () => {
    expect(isValidShortText('abc')).toBe(true);
    expect(isValidShortText('x'.repeat(300))).toBe(true);
    expect(isValidShortText('ab')).toBe(false);
    expect(isValidShortText('x'.repeat(301))).toBe(false);
  });

  it('truncateText adds ellipsis when over limit', () => {
    expect(truncateText('abc', 10)).toBe('abc');
    expect(truncateText('abcdefghijk', 10)).toBe('abcdefghi…');
    expect(truncateText('abcdefghijk', 10)).toHaveLength(10);
  });

  it('Arabic text is validated by character count', () => {
    expect(shortTextSchema.parse('مرحبا')).toBe('مرحبا');
    expect(isValidShortText('مر')).toBe(false);
    expect(isValidShortText('مرحبا بكم في نظام أحلى شباب')).toBe(true);
  });
});
