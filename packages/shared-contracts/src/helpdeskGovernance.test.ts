import { describe, expect, it } from 'vitest';
import {
  decisionRegisterEntrySchema,
  disciplineActionSchema,
  hrTicketListSchema,
  hrTicketSchema,
  incidentItemSchema,
  riskItemSchema,
  ticketMessageSchema,
} from './helpdeskGovernance.js';

const UUID = '11111111-1111-4111-8111-111111111111';
const UUID2 = '22222222-2222-4222-8222-222222222222';

describe('helpdesk/governance contracts', () => {
  it('يقبل تذكرة HR صالحة', () => {
    const ticket = hrTicketSchema.parse({
      id: UUID,
      subject: 'مشكلة',
      category: 'general',
      priority: 'high',
      status: 'open',
      requester_employee_id: UUID2,
      assignee_employee_id: UUID,
      sla_due_at: '2026-01-02T00:00:00Z',
      created_at: '2026-01-01T00:00:00Z',
      updated_at: '2026-01-01T01:00:00Z',
    });
    expect(ticket.priority).toBe('high');
    const list = hrTicketListSchema.parse([ticket]);
    expect(list).toHaveLength(1);
  });

  it('يرفض أولوية خارج المجموعة', () => {
    const base = {
      id: UUID,
      subject: 'x',
      category: null,
      priority: 'low',
      status: 'open',
      requester_employee_id: UUID2,
      assignee_employee_id: null,
      sla_due_at: null,
      created_at: '2026-01-01',
      updated_at: null,
    };
    expect(() => hrTicketSchema.parse({ ...base, priority: 'critical' })).toThrow();
    expect(() => hrTicketSchema.parse({ ...base, status: 'done' })).toThrow();
  });

  it('يقبل رسالة تذكرة', () => {
    const msg = ticketMessageSchema.parse({
      id: UUID,
      ticket_id: UUID2,
      author_id: UUID,
      body: 'رد',
      is_internal: true,
      created_at: '2026-01-01T00:00:00Z',
    });
    expect(msg.is_internal).toBe(true);
  });

  it('يقبل بند مخاطر مع تصنيفات صحيحة', () => {
    const risk = riskItemSchema.parse({
      id: UUID,
      title: 'خطر',
      description: 'وصف',
      likelihood: 'high',
      impact: 'medium',
      severity: 'critical',
      owner_employee_id: UUID2,
      status: 'mitigating',
      created_at: '2026-01-01',
      updated_at: '2026-01-02',
    });
    expect(risk.severity).toBe('critical');
  });

  it('يرفض likelihood/severity خارج المجموعة', () => {
    const base = {
      id: UUID,
      title: 'x',
      description: null,
      likelihood: 'low',
      impact: 'low',
      severity: 'low',
      owner_employee_id: null,
      status: 'open',
      created_at: '2026-01-01',
      updated_at: null,
    };
    expect(() => riskItemSchema.parse({ ...base, likelihood: 'extreme' })).toThrow();
    expect(() => riskItemSchema.parse({ ...base, severity: 'extreme' })).toThrow();
    expect(() => riskItemSchema.parse({ ...base, status: 'done' })).toThrow();
  });

  it('يقبل حادثة', () => {
    const inc = incidentItemSchema.parse({
      id: UUID,
      title: 'حادثة',
      description: null,
      severity: 'medium',
      reported_by: UUID2,
      status: 'investigating',
      resolved_at: null,
      created_at: '2026-01-01',
    });
    expect(inc.status).toBe('investigating');
  });

  it('يقبل بند سجل قرارات', () => {
    const entry = decisionRegisterEntrySchema.parse({
      id: UUID,
      decision_type: 'policy',
      title: 'قرار',
      summary: null,
      status: 'issued',
      issued_at: '2026-01-01',
      created_at: '2026-01-01',
    });
    expect(entry.decision_type).toBe('policy');
  });

  it('يقبل إجراء تأديبي ويرفض type خارج المجموعة', () => {
    const base = {
      id: UUID,
      employee_id: UUID2,
      action_type: 'verbal_warning',
      title: 'إنذار',
      description: 'وصف',
      severity: 'low',
      amount: null,
      effective_from: '2026-01-01',
      effective_to: null,
      status: 'draft',
      decision_note: null,
      decided_by: null,
      decided_at: null,
      created_at: '2026-01-01',
    };
    expect(disciplineActionSchema.parse(base).action_type).toBe('verbal_warning');
    expect(() => disciplineActionSchema.parse({ ...base, action_type: 'firing' })).toThrow();
    expect(() => disciplineActionSchema.parse({ ...base, severity: 'extreme' })).toThrow();
    expect(() => disciplineActionSchema.parse({ ...base, status: 'done' })).toThrow();
  });
});
