import { describe, expect, it } from 'vitest';
import {
  requestTypeSchema,
  REQUEST_TYPE_COUNT,
  REQUEST_TYPE_LABELS,
  requestStatusSchema,
  createRequestInputSchema,
} from './requests.js';

describe('request type contracts — V17 §8', () => {
  it('exactly 6 request types', () => {
    expect(requestTypeSchema.options).toHaveLength(REQUEST_TYPE_COUNT);
  });

  it('types are: leave, mission, convoy, late_permit, early_permit, attendance_correction', () => {
    expect(requestTypeSchema.parse('leave')).toBe('leave');
    expect(requestTypeSchema.parse('mission')).toBe('mission');
    expect(requestTypeSchema.parse('convoy')).toBe('convoy');
    expect(requestTypeSchema.parse('late_permit')).toBe('late_permit');
    expect(requestTypeSchema.parse('early_permit')).toBe('early_permit');
    expect(requestTypeSchema.parse('attendance_correction')).toBe('attendance_correction');
  });

  it('rejects legacy types: attendance_permit, generic', () => {
    expect(() => requestTypeSchema.parse('attendance_permit')).toThrow();
    expect(() => requestTypeSchema.parse('generic')).toThrow();
  });

  it('all 6 types have Arabic labels', () => {
    const keys = Object.keys(REQUEST_TYPE_LABELS);
    expect(keys).toHaveLength(6);
    expect(REQUEST_TYPE_LABELS.leave).toBe('إجازة');
    expect(REQUEST_TYPE_LABELS.late_permit).toBe('إذن حضور');
    expect(REQUEST_TYPE_LABELS.attendance_correction).toBe('تصحيح حضور');
  });

  it('request statuses include draft, pending, approved, rejected, returned, escalated', () => {
    expect(requestStatusSchema.parse('draft')).toBe('draft');
    expect(requestStatusSchema.parse('escalated')).toBe('escalated');
    expect(() => requestStatusSchema.parse('deleted')).toThrow();
  });

  it('create request enforces reason 3–300 chars', () => {
    const valid = createRequestInputSchema.parse({
      type: 'leave',
      reason: 'إجازة سنوية',
      startDate: '2026-08-01',
    });
    expect(valid.type).toBe('leave');
    expect(valid.attachmentIds).toEqual([]);

    expect(() => createRequestInputSchema.parse({
      type: 'leave',
      reason: 'ab',
      startDate: '2026-08-01',
    })).toThrow();

    expect(() => createRequestInputSchema.parse({
      type: 'leave',
      reason: 'x'.repeat(301),
      startDate: '2026-08-01',
    })).toThrow();
  });

  it('create request validates date format', () => {
    expect(() => createRequestInputSchema.parse({
      type: 'mission',
      reason: 'مأمورية عمل',
      startDate: '01-08-2026',
    })).toThrow();
  });

  it('late_permit and early_permit are distinct types', () => {
    const late = createRequestInputSchema.parse({
      type: 'late_permit',
      reason: 'ظرف طارئ',
      startDate: '2026-08-01',
    });
    const early = createRequestInputSchema.parse({
      type: 'early_permit',
      reason: 'موعد طبي',
      startDate: '2026-08-01',
    });
    expect(late.type).not.toBe(early.type);
  });
});
