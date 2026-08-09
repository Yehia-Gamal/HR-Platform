import { z } from 'zod';

const uuid = z.string().uuid();
const date = z.string().nullable();
const timestamp = z.string().nullable();

export const hrTicketSchema = z.object({
  id: uuid,
  subject: z.string(),
  category: z.string().nullable(),
  priority: z.enum(['low', 'medium', 'high', 'urgent']),
  status: z.enum(['open', 'in_progress', 'resolved', 'closed', 'cancelled']),
  requester_employee_id: uuid,
  assignee_employee_id: uuid.nullable(),
  sla_due_at: timestamp,
  created_at: z.string(),
  updated_at: timestamp,
  requester_name: z.string().nullable().optional(),
  assignee_name: z.string().nullable().optional(),
});
export type HrTicket = z.infer<typeof hrTicketSchema>;
export const hrTicketListSchema = z.array(hrTicketSchema);

export const ticketMessageSchema = z.object({
  id: uuid,
  ticket_id: uuid,
  author_id: uuid.nullable(),
  body: z.string(),
  is_internal: z.boolean(),
  created_at: z.string(),
  author_name: z.string().nullable().optional(),
});
export type TicketMessage = z.infer<typeof ticketMessageSchema>;
export const ticketMessageListSchema = z.array(ticketMessageSchema);

export const riskItemSchema = z.object({
  id: uuid,
  title: z.string(),
  description: z.string().nullable(),
  likelihood: z.enum(['low', 'medium', 'high']),
  impact: z.enum(['low', 'medium', 'high']),
  severity: z.enum(['low', 'medium', 'high', 'critical']),
  owner_employee_id: uuid.nullable(),
  status: z.enum(['open', 'mitigating', 'closed', 'accepted']),
  created_at: z.string(),
  updated_at: timestamp,
  owner_name: z.string().nullable().optional(),
});
export type RiskItem = z.infer<typeof riskItemSchema>;
export const riskItemListSchema = z.array(riskItemSchema);

export const incidentItemSchema = z.object({
  id: uuid,
  title: z.string(),
  description: z.string().nullable(),
  severity: z.enum(['low', 'medium', 'high', 'critical']),
  reported_by: uuid.nullable(),
  status: z.enum(['open', 'investigating', 'resolved', 'closed']),
  resolved_at: timestamp,
  created_at: z.string(),
  reporter_name: z.string().nullable().optional(),
});
export type IncidentItem = z.infer<typeof incidentItemSchema>;
export const incidentItemListSchema = z.array(incidentItemSchema);

export const decisionRegisterEntrySchema = z.object({
  id: uuid,
  decision_type: z.string().nullable().optional(),
  title: z.string().nullable().optional(),
  summary: z.string().nullable().optional(),
  status: z.string().nullable().optional(),
  issued_at: timestamp,
  created_at: z.string(),
});
export type DecisionRegisterEntry = z.infer<typeof decisionRegisterEntrySchema>;
export const decisionRegisterEntryListSchema = z.array(decisionRegisterEntrySchema);

export const disciplineActionSchema = z.object({
  id: uuid,
  employee_id: uuid,
  action_type: z.enum(['verbal_warning', 'written_warning', 'salary_deduction', 'suspension', 'termination']),
  title: z.string(),
  description: z.string(),
  severity: z.enum(['low', 'moderate', 'high', 'critical']),
  amount: z.number().nullable(),
  effective_from: date,
  effective_to: date,
  status: z.enum(['draft', 'pending', 'approved', 'rejected']),
  decision_note: z.string().nullable(),
  decided_by: uuid.nullable(),
  decided_at: timestamp,
  created_at: z.string(),
});
export type DisciplineAction = z.infer<typeof disciplineActionSchema>;
export const disciplineActionListSchema = z.array(disciplineActionSchema);
