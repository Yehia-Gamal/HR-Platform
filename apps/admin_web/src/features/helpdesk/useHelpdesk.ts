import { hrTicketListSchema, ticketMessageListSchema, type HrTicket, type TicketMessage } from '@ahla/shared-contracts';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { getSupabase } from '../../core/supabase';
import { useAuth } from '../auth/AuthProvider';

const TICKETS_KEY = 'helpdesk-tickets';
const MESSAGES_KEY = 'helpdesk-messages';

function rows(value: unknown): Array<Record<string, unknown>> {
  return Array.isArray(value) ? (value as Array<Record<string, unknown>>) : [];
}

const TICKET_FIELDS = [
  'id',
  'subject',
  'category',
  'priority',
  'status',
  'requester_employee_id',
  'assignee_employee_id',
  'sla_due_at',
  'created_at',
  'updated_at',
  'requester:requester_employee_id!hr_tickets_requester_employee_id_fkey(full_name_ar)',
  'assignee:assignee_employee_id!hr_tickets_assignee_employee_id_fkey(full_name_ar)',
].join(',');

export function useHelpdeskTickets() {
  const auth = useAuth();
  return useQuery({
    queryKey: [TICKETS_KEY, auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<HrTicket[]> => {
      if (auth.isMock) return [];
      const supabase = await getSupabase();
      const { data, error } = await supabase.from('hr_tickets').select(TICKET_FIELDS).order('created_at', { ascending: false }).limit(200);
      if (error) throw error;
      return hrTicketListSchema.parse(
        rows(data).map((row) => {
          const requester = row.requester as { full_name_ar?: string } | { full_name_ar?: string }[] | null | undefined;
          const assignee = row.assignee as { full_name_ar?: string } | { full_name_ar?: string }[] | null | undefined;
          const requesterName = Array.isArray(requester) ? requester[0]?.full_name_ar : requester?.full_name_ar;
          const assigneeName = Array.isArray(assignee) ? assignee[0]?.full_name_ar : assignee?.full_name_ar;
          return { ...row, requester_name: requesterName ?? null, assignee_name: assigneeName ?? null };
        }),
      );
    },
  });
}

export function useTicketMessages(ticketId: string | null) {
  const auth = useAuth();
  return useQuery({
    queryKey: [MESSAGES_KEY, ticketId, auth.isMock],
    enabled: auth.status === 'authenticated' && Boolean(ticketId),
    queryFn: async (): Promise<TicketMessage[]> => {
      if (auth.isMock || !ticketId) return [];
      const supabase = await getSupabase();
      const { data, error } = await supabase
        .from('ticket_messages')
        .select('id,ticket_id,author_id,body,is_internal,created_at,author:author_id(email)')
        .eq('ticket_id', ticketId)
        .order('created_at', { ascending: true })
        .limit(200);
      if (error) throw error;
      return ticketMessageListSchema.parse(
        rows(data).map((row) => {
          const author = row.author as { email?: string } | { email?: string }[] | null | undefined;
          const authorEmail = Array.isArray(author) ? author[0]?.email : author?.email;
          return { ...row, author_name: authorEmail ?? null };
        }),
      );
    },
  });
}

export function useCreateTicket() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (input: { subject: string; category: string; priority: string; description?: string }): Promise<void> => {
      if (auth.isMock) return;
      const supabase = await getSupabase();
      const { data: ticket, error } = await supabase
        .from('hr_tickets')
        .insert({
          subject: input.subject.trim(),
          category: input.category.trim() || null,
          priority: input.priority,
        })
        .select('id')
        .single();
      if (error) throw error;
      if (input.description?.trim()) {
        const { error: msgError } = await supabase.from('ticket_messages').insert({
          ticket_id: ticket.id,
          body: input.description.trim(),
          is_internal: false,
        });
        if (msgError) throw msgError;
      }
    },
    meta: { successMessage: 'تم إنشاء التذكرة بنجاح' },
    onSuccess: () => client.invalidateQueries({ queryKey: [TICKETS_KEY] }),
  });
}

export function useSendTicketMessage() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (input: { ticketId: string; body: string; isInternal?: boolean }): Promise<void> => {
      if (auth.isMock) return;
      const supabase = await getSupabase();
      const { error } = await supabase.from('ticket_messages').insert({
        ticket_id: input.ticketId,
        body: input.body.trim(),
        is_internal: input.isInternal ?? false,
      });
      if (error) throw error;
    },
    meta: { successMessage: 'تم إرسال الرد' },
    onSuccess: (_data, vars) => client.invalidateQueries({ queryKey: [MESSAGES_KEY, vars.ticketId] }),
  });
}

export function useUpdateTicketStatus() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (input: { id: string; status: string; assigneeId?: string | null }): Promise<void> => {
      if (auth.isMock) return;
      const supabase = await getSupabase();
      const patch: Record<string, string | null> = { status: input.status };
      if (input.assigneeId !== undefined) patch.assignee_employee_id = input.assigneeId;
      const { error } = await supabase.from('hr_tickets').update(patch).eq('id', input.id);
      if (error) throw error;
    },
    meta: { successMessage: 'تم تحديث التذكرة' },
    onSuccess: () => client.invalidateQueries({ queryKey: [TICKETS_KEY] }),
  });
}
