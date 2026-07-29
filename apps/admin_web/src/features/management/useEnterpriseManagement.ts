import {
  enterpriseManagementCatalogSchema,
} from '@ahla/shared-contracts';
import { useQuery } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';
import { loadDomainMocks } from '../mock/loadDomainMocks';

export function useEnterpriseManagementCatalog() {
  const a = useAuth();
  return useQuery({
    queryKey: ['enterprise-management', a.isMock],
    enabled: a.status === 'authenticated',
    queryFn: async () =>
      a.isMock
        ? (await loadDomainMocks()).mockEnterpriseManagement
        : enterpriseManagementCatalogSchema.parse(
            await rpc('get_enterprise_management_catalog'),
          ),
  });
}
