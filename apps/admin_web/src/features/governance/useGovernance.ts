import { incidentItemListSchema, riskItemListSchema, type IncidentItem, type RiskItem } from '@ahla/shared-contracts';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { getSupabase } from '../../core/supabase';
import { useAuth } from '../auth/AuthProvider';

const RISKS_KEY = 'governance-risks';
const INCIDENTS_KEY = 'governance-incidents';

function rows(value: unknown): Array<Record<string, unknown>> {
  return Array.isArray(value) ? (value as Array<Record<string, unknown>>) : [];
}

export function useRisks() {
  const auth = useAuth();
  return useQuery({
    queryKey: [RISKS_KEY, auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<RiskItem[]> => {
      if (auth.isMock) return [];
      const supabase = await getSupabase();
      const { data, error } = await supabase
        .from('risks')
        .select(
          'id,title,description,likelihood,impact,severity,owner_employee_id,status,created_at,updated_at,owner:owner_employee_id!risks_owner_employee_id_fkey(full_name_ar)',
        )
        .order('created_at', { ascending: false })
        .limit(200);
      if (error) throw error;
      return riskItemListSchema.parse(
        rows(data).map((row) => {
          const owner = row.owner as { full_name_ar?: string } | { full_name_ar?: string }[] | null | undefined;
          const ownerName = Array.isArray(owner) ? owner[0]?.full_name_ar : owner?.full_name_ar;
          return { ...row, owner_name: ownerName ?? null };
        }),
      );
    },
  });
}

export function useIncidents() {
  const auth = useAuth();
  return useQuery({
    queryKey: [INCIDENTS_KEY, auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<IncidentItem[]> => {
      if (auth.isMock) return [];
      const supabase = await getSupabase();
      const { data, error } = await supabase
        .from('incidents')
        .select('id,title,description,severity,reported_by,status,resolved_at,created_at,reporter:reported_by!incidents_reported_by_fkey(full_name_ar)')
        .order('created_at', { ascending: false })
        .limit(200);
      if (error) throw error;
      return incidentItemListSchema.parse(
        rows(data).map((row) => {
          const reporter = row.reporter as { full_name_ar?: string } | { full_name_ar?: string }[] | null | undefined;
          const reporterName = Array.isArray(reporter) ? reporter[0]?.full_name_ar : reporter?.full_name_ar;
          return { ...row, reporter_name: reporterName ?? null };
        }),
      );
    },
  });
}

export function useUpsertRisk() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (input: {
      id?: string | null;
      title: string;
      description?: string | null;
      likelihood: string;
      impact: string;
      severity: string;
      status: string;
      ownerEmployeeId?: string | null;
    }): Promise<void> => {
      if (auth.isMock) return;
      const supabase = await getSupabase();
      const payload = {
        title: input.title.trim(),
        description: input.description?.trim() || null,
        likelihood: input.likelihood,
        impact: input.impact,
        severity: input.severity,
        status: input.status,
        owner_employee_id: input.ownerEmployeeId || null,
      };
      if (input.id) {
        const { error } = await supabase.from('risks').update(payload).eq('id', input.id);
        if (error) throw error;
      } else {
        const { error } = await supabase.from('risks').insert(payload);
        if (error) throw error;
      }
    },
    meta: { successMessage: 'تم حفظ المخاطرة' },
    onSuccess: () => client.invalidateQueries({ queryKey: [RISKS_KEY] }),
  });
}

export function useUpsertIncident() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (input: { id?: string | null; title: string; description?: string | null; severity: string; status: string }): Promise<void> => {
      if (auth.isMock) return;
      const supabase = await getSupabase();
      const payload = {
        title: input.title.trim(),
        description: input.description?.trim() || null,
        severity: input.severity,
        status: input.status,
        resolved_at: input.status === 'resolved' || input.status === 'closed' ? new Date().toISOString() : null,
      };
      if (input.id) {
        const { error } = await supabase.from('incidents').update(payload).eq('id', input.id);
        if (error) throw error;
      } else {
        const { error } = await supabase.from('incidents').insert(payload);
        if (error) throw error;
      }
    },
    meta: { successMessage: 'تم حفظ الحادث' },
    onSuccess: () => client.invalidateQueries({ queryKey: [INCIDENTS_KEY] }),
  });
}
