import { actionCenterItemSchema, type ActionCenterItem } from '@ahla/shared-contracts';
import { useQuery } from '@tanstack/react-query';
import { getSupabase } from '../../core/supabase';
import { useAuth } from '../auth/AuthProvider';
import { loadDomainMocks } from '../mock/loadDomainMocks';
export function useActionCenter() { const auth = useAuth(); return useQuery({ queryKey: ['action-center', auth.isMock], enabled: auth.status === 'authenticated', queryFn: async (): Promise<ActionCenterItem[]> => { if (auth.isMock) return (await loadDomainMocks()).mockActionCenter; const supabase = await getSupabase(); const { data, error } = await supabase.rpc('get_universal_action_center', { p_limit: 100 }); if (error) throw error; return actionCenterItemSchema.array().parse(data ?? []); } }); }
