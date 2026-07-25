import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { getSupabase } from '../../core/supabase';
import { useAuth } from '../auth/AuthProvider';

export interface Holiday {
  id: string;
  name: string;
  name_en: string | null;
  holiday_date: string;
  end_date: string | null;
  scope: 'all' | 'legal_entity' | 'department';
  legal_entity_id: string | null;
  department_id: string | null;
  excluded_department_ids: string[];
  notes: string | null;
  is_recurring: boolean;
  is_active: boolean;
  created_at: string;
  created_by: string | null;
}

const QUERY_KEY = ['official-holidays'];

const mockHolidays: Holiday[] = [
  {
    id: '00000000-0000-4000-8000-000000000001',
    name: 'عيد الفطر',
    name_en: 'Eid Al-Fitr',
    holiday_date: '2026-03-31',
    end_date: '2026-04-02',
    scope: 'all',
    legal_entity_id: null,
    department_id: null,
    excluded_department_ids: [],
    notes: null,
    is_recurring: true,
    is_active: true,
    created_at: new Date().toISOString(),
    created_by: null,
  },
];

export function useHolidays(year?: number) {
  const auth = useAuth();
  return useQuery({
    queryKey: [...QUERY_KEY, year, auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<Holiday[]> => {
      if (auth.isMock) return mockHolidays;

      const supabase = await getSupabase();
      let query = supabase
        .from('public_holidays')
        .select('*')
        .order('holiday_date', { ascending: false });

      if (year) {
        query = query
          .gte('holiday_date', `${year}-01-01`)
          .lte('holiday_date', `${year}-12-31`);
      }

      const { data, error } = await query;
      if (error) throw error;
      return (data ?? []) as Holiday[];
    },
  });
}

export function useCreateHoliday() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (input: {
      name: string;
      holiday_date: string;
      end_date?: string | null;
      scope?: 'all' | 'legal_entity' | 'department';
      legal_entity_id?: string | null;
      department_id?: string | null;
      excluded_department_ids?: string[];
      notes?: string | null;
      is_recurring?: boolean;
    }): Promise<void> => {
      if (auth.isMock) return;
      const supabase = await getSupabase();
      const { error } = await supabase.from('public_holidays').insert({
        name: input.name,
        holiday_date: input.holiday_date,
        end_date: input.end_date ?? null,
        scope: input.scope ?? 'all',
        legal_entity_id: input.legal_entity_id ?? null,
        department_id: input.department_id ?? null,
        excluded_department_ids: input.excluded_department_ids ?? [],
        notes: input.notes ?? null,
        is_recurring: input.is_recurring ?? false,
        created_by: (await supabase.auth.getUser()).data.user?.id ?? null,
      });
      if (error) throw error;
    },
    onSuccess: () => void client.invalidateQueries({ queryKey: QUERY_KEY }),
  });
}

export function useUpdateHoliday() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, ...changes }: {
      id: string;
      name?: string;
      holiday_date?: string;
      end_date?: string | null;
      scope?: 'all' | 'legal_entity' | 'department';
      legal_entity_id?: string | null;
      department_id?: string | null;
      excluded_department_ids?: string[];
      notes?: string | null;
      is_recurring?: boolean;
      is_active?: boolean;
    }): Promise<void> => {
      if (auth.isMock) return;
      const supabase = await getSupabase();
      const { error } = await supabase.from('public_holidays').update(changes).eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => void client.invalidateQueries({ queryKey: QUERY_KEY }),
  });
}

export function useDeleteHoliday() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (id: string): Promise<void> => {
      if (auth.isMock) return;
      const supabase = await getSupabase();
      const { error } = await supabase.from('public_holidays').delete().eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => void client.invalidateQueries({ queryKey: QUERY_KEY }),
  });
}
