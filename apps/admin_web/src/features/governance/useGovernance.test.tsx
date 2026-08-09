import { describe, it, expect } from 'vitest';
import { riskItemSchema, riskItemListSchema } from '@ahla/shared-contracts';

const validRisk = {
  id: '11111111-1111-4111-8111-111111111111',
  title: 'خطر أمني',
  description: 'وصف الخطر',
  likelihood: 'high' as const,
  impact: 'high' as const,
  severity: 'critical' as const,
  owner_employee_id: null,
  status: 'open' as const,
  created_at: '2026-01-01T00:00:00.000Z',
  updated_at: null,
  owner_name: null,
};

describe('riskItemSchema', () => {
  it('parses a valid risk item', () => {
    const parsed = riskItemSchema.parse(validRisk);
    expect(parsed.title).toBe('خطر أمني');
    expect(parsed.severity).toBe('critical');
    expect(parsed.status).toBe('open');
  });

  it('parses a list of risks', () => {
    const list = riskItemListSchema.parse([validRisk]);
    expect(list).toHaveLength(1);
  });

  it('rejects invalid severity', () => {
    expect(() => riskItemSchema.parse({ ...validRisk, severity: 'extreme' })).toThrow();
  });

  it('rejects invalid status', () => {
    expect(() => riskItemSchema.parse({ ...validRisk, status: 'pending' })).toThrow();
  });

  it('rejects non-uuid id', () => {
    expect(() => riskItemSchema.parse({ ...validRisk, id: 'r1' })).toThrow();
  });

  it('allows optional owner_name', () => {
    const { owner_name: _o, ...withoutName } = validRisk;
    const parsed = riskItemSchema.parse(withoutName);
    expect(parsed.owner_name).toBeUndefined();
  });
});
