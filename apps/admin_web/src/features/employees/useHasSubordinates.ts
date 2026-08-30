import { useQuery } from '@tanstack/react-query';
import { getSupabase } from '../../core/supabase';
import { useAuth } from '../auth/AuthProvider';
import { loadDomainMocks } from '../mock/loadDomainMocks';

export function useHasSubordinates() {
  const auth = useAuth();
  return useQuery({
    queryKey: ['has-subordinates', auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<boolean> => {
      if (auth.isMock) {
        const mocks = await loadDomainMocks();
        return (mocks.mockManagerRelations?.length ?? 0) > 0;
      }
      const supabase = await getSupabase();
      const { count, error } = await supabase
        .from('manager_relations')
        .select('*', { count: 'exact', head: true })
        .eq('manager_employee_id', auth.access?.employeeId)
        .eq('relation_type', 'primary')
        .lte('effective_from', new Date().toISOString())
        .or('effective_to.is.null,effective_to.gte.' + new Date().toISOString());
      if (error) throw error;
      return (count ?? 0) > 0;
    },
    staleTime: 5 * 60 * 1000,
  });
}

export function useSubordinatesList() {
  const auth = useAuth();
  return useQuery({
    queryKey: ['subordinates-list', auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async () => {
      if (auth.isMock) {
        const mocks = await loadDomainMocks();
        return mocks.mockSubordinates ?? [];
      }
      const supabase = await getSupabase();
      const { data, error } = await supabase
        .from('manager_relations')
        .select(
          `
          id,
          employee_id,
          effective_from,
          effective_to,
          employees!manager_relations_employee_id_fkey (
            id,
            full_name_ar,
            employee_code,
            job_title,
            department_id,
            photo_url,
            departments ( name_ar ),
            branches ( name_ar )
          )
        `,
        )
        .eq('manager_employee_id', auth.access?.employeeId)
        .eq('relation_type', 'primary')
        .lte('effective_from', new Date().toISOString())
        .or('effective_to.is.null,effective_to.gte.' + new Date().toISOString());
      if (error) throw error;
      return data ?? [];
    },
    staleTime: 5 * 60 * 1000,
  });
}
