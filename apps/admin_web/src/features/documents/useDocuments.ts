import { documentsCatalogSchema, type DocumentsCatalog } from '@ahla/shared-contracts';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';

const QUERY_KEY = 'documents-catalog';

export function useDocumentsCatalog() {
  const auth = useAuth();
  return useQuery({
    queryKey: [QUERY_KEY, auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<DocumentsCatalog> => {
      if (auth.isMock) {
        return { documents: [], assets: [], offboarding: [], expiringDocuments: 0, assignedAssets: 0, openOffboarding: 0, lastUpdatedAt: new Date().toISOString() };
      }
      return documentsCatalogSchema.parse(await rpc('get_documents_assets_offboarding_catalog'));
    },
  });
}

export function useReviewDocument() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (input: { documentId: string; decision: 'verified' | 'rejected' | 'archived'; reason?: string }): Promise<void> => {
      if (auth.isMock) return;
      await rpc('review_employee_document', {
        p_document_id: input.documentId,
        p_decision: input.decision,
        p_reason: input.reason ?? null,
      });
    },
    onSuccess: () => client.invalidateQueries({ queryKey: [QUERY_KEY] }),
  });
}

export const DOCUMENT_STATUS_LABELS: Record<string, string> = {
  active: 'ساري',
  expired: 'منتهي',
  rejected: 'مرفوض',
  archived: 'مؤرشف',
};

export const ASSET_STATUS_LABELS: Record<string, string> = {
  available: 'متاح',
  assigned: 'مُسلم',
  return_requested: 'طلب استرجاع',
  returned: 'مسترجع',
  retired: 'متقاعد',
};

export const OFFBOARDING_STATUS_LABELS: Record<string, string> = {
  draft: 'مسودة',
  submitted: 'مُقدّم',
  in_clearance: 'في التخليص',
  ready_for_approval: 'جاهز للاعتماد',
  approved: 'معتمد',
  completed: 'مكتمل',
  cancelled: 'ملغي',
};

export const CLEARANCE_CATEGORY_LABELS: Record<string, string> = {
  manager: 'المدير',
  hr: 'الموارد البشرية',
  it: 'تقنية المعلومات',
  finance: 'المالية',
  assets: 'العهد',
  documents: 'المستندات',
  access: 'الصلاحيات',
  knowledge_transfer: 'نقل المعرفة',
  other: 'أخرى',
};
