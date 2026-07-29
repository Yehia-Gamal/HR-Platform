import { actionCenterItemSchema, type ActionCenterItem } from '@ahla/shared-contracts';
import { useQuery } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';
import { loadDomainMocks } from '../mock/loadDomainMocks';
export function useActionCenter() { const auth = useAuth(); return useQuery({ queryKey: ['action-center', auth.isMock], enabled: auth.status === 'authenticated', queryFn: async (): Promise<ActionCenterItem[]> => { if (auth.isMock) return (await loadDomainMocks()).mockActionCenter; const data = await rpc('get_universal_action_center', { p_limit: 100 }); return actionCenterItemSchema.array().parse(data ?? []); } }); }
