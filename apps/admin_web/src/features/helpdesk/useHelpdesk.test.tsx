import { describe, it, expect } from 'vitest';
import { hrTicketSchema, hrTicketListSchema } from '@ahla/shared-contracts';

const validTicket = {
  id: '11111111-1111-4111-8111-111111111111',
  subject: 'مشكلة دخول',
  category: 'auth',
  priority: 'high' as const,
  status: 'open' as const,
  requester_employee_id: '22222222-2222-4222-8222-222222222222',
  assignee_employee_id: null,
  sla_due_at: null,
  created_at: '2026-01-01T00:00:00.000Z',
  updated_at: null,
  requester_name: null,
  assignee_name: null,
};

describe('hrTicketSchema', () => {
  it('parses a valid ticket', () => {
    const parsed = hrTicketSchema.parse(validTicket);
    expect(parsed.subject).toBe('مشكلة دخول');
    expect(parsed.status).toBe('open');
    expect(parsed.priority).toBe('high');
  });

  it('parses a list of tickets', () => {
    const list = hrTicketListSchema.parse([validTicket]);
    expect(list).toHaveLength(1);
  });

  it('rejects invalid priority', () => {
    expect(() => hrTicketSchema.parse({ ...validTicket, priority: 'critical' })).toThrow();
  });

  it('rejects invalid status', () => {
    expect(() => hrTicketSchema.parse({ ...validTicket, status: 'pending' })).toThrow();
  });

  it('rejects non-uuid id', () => {
    expect(() => hrTicketSchema.parse({ ...validTicket, id: 't1' })).toThrow();
  });

  it('allows null optional fields', () => {
    const parsed = hrTicketSchema.parse({ ...validTicket, category: null, assignee_employee_id: null });
    expect(parsed.category).toBeNull();
    expect(parsed.assignee_employee_id).toBeNull();
  });
});
