import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { getSupabase } from '../../core/supabase';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';
import { loadDomainMocks } from '../mock/loadDomainMocks';

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

export function useHolidays(year?: number) {
  const auth = useAuth();
  return useQuery({
    queryKey: [...QUERY_KEY, year, auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<Holiday[]> => {
      if (auth.isMock) return (await loadDomainMocks()).mockHolidays;

      const supabase = await getSupabase();
      let query = supabase.from('public_holidays').select('*').order('holiday_date', { ascending: false });

      if (year) {
        query = query.gte('holiday_date', `${year}-01-01`).lte('holiday_date', `${year}-12-31`);
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
      await rpc('create_public_holiday', {
        p_name: input.name,
        p_holiday_date: input.holiday_date,
        p_end_date: input.end_date ?? null,
        p_scope: input.scope ?? 'all',
        p_legal_entity_id: input.legal_entity_id ?? null,
        p_department_id: input.department_id ?? null,
        p_excluded_department_ids: input.excluded_department_ids ?? [],
        p_notes: input.notes ?? null,
        p_is_recurring: input.is_recurring ?? false,
      });
    },
    meta: { successMessage: 'تم إنشاء العطلة الرسمية بنجاح' },
    onSuccess: () => void client.invalidateQueries({ queryKey: QUERY_KEY }),
  });
}

export function useUpdateHoliday() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async ({
      id,
      ...changes
    }: {
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
      await rpc('update_public_holiday', {
        p_id: id,
        p_name: changes.name ?? null,
        p_holiday_date: changes.holiday_date ?? null,
        p_end_date: changes.end_date ?? null,
        p_scope: changes.scope ?? null,
        p_legal_entity_id: changes.legal_entity_id ?? null,
        p_department_id: changes.department_id ?? null,
        p_excluded_department_ids: changes.excluded_department_ids ?? null,
        p_notes: changes.notes ?? null,
        p_is_recurring: changes.is_recurring ?? null,
        p_is_active: changes.is_active ?? null,
      });
    },
    meta: { successMessage: 'تم تحديث العطلة الرسمية بنجاح' },
    onSuccess: () => void client.invalidateQueries({ queryKey: QUERY_KEY }),
  });
}

export function useDeleteHoliday() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (id: string): Promise<void> => {
      if (auth.isMock) return;
      await rpc('delete_public_holiday', { p_id: id });
    },
    meta: { successMessage: 'تم حذف العطلة الرسمية بنجاح' },
    onSuccess: () => void client.invalidateQueries({ queryKey: QUERY_KEY }),
  });
}
