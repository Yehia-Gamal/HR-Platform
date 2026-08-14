import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { z } from 'zod';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';
import type { DocumentStudioCatalog } from './documents-studio.types';

const catalogSchema = z.object({
  templates: z
    .array(
      z
        .object({
          id: z.string(),
          code: z.string(),
          name: z.string(),
          documentType: z.string(),
          version: z.number(),
          active: z.boolean(),
          requiresEmployeeSignature: z.boolean(),
          requiresManagerSignature: z.boolean(),
          requiresHrSignature: z.boolean(),
          requiresExecutiveSignature: z.boolean(),
        })
        .catch({
          id: '',
          code: '',
          name: '—',
          documentType: 'other',
          version: 1,
          active: false,
          requiresEmployeeSignature: false,
          requiresManagerSignature: false,
          requiresHrSignature: false,
          requiresExecutiveSignature: false,
        }),
    )
    .default([]),
  documents: z
    .array(
      z
        .object({
          id: z.string(),
          referenceNumber: z.string().nullable(),
          title: z.string(),
          documentType: z.string(),
          employeeId: z.string().nullable(),
          employeeName: z.string().nullable(),
          status: z.string(),
          createdAt: z.string(),
          issuedAt: z.string().nullable(),
          pendingSignatures: z.number(),
        })
        .catch({
          id: '',
          referenceNumber: null,
          title: '—',
          documentType: 'other',
          employeeId: null,
          employeeName: null,
          status: 'draft',
          createdAt: '',
          issuedAt: null,
          pendingSignatures: 0,
        }),
    )
    .default([]),
  lastUpdatedAt: z.string().optional(),
});

export function useDocumentStudioCatalog() {
  const auth = useAuth();
  return useQuery({
    queryKey: ['document-studio'],
    enabled: auth.status === 'authenticated',
    queryFn: async () => catalogSchema.parse(await rpc('get_document_studio_catalog', {})) as DocumentStudioCatalog,
    staleTime: 30_000,
  });
}

export interface TemplateInput {
  id?: string | null;
  code: string;
  name_ar: string;
  document_type: string;
  body_template?: string;
  requires_employee: boolean;
  requires_manager: boolean;
  requires_hr: boolean;
  requires_executive: boolean;
  active: boolean;
}

export function useUpsertTemplate() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (input: TemplateInput) =>
      rpc('upsert_document_template_admin', {
        p_id: input.id ?? null,
        p_code: input.code,
        p_name_ar: input.name_ar,
        p_document_type: input.document_type,
        p_body_template: input.body_template ?? '',
        p_requires_employee: input.requires_employee,
        p_requires_manager: input.requires_manager,
        p_requires_hr: input.requires_hr,
        p_requires_executive: input.requires_executive,
        p_active: input.active,
      }),
    onSuccess: () => client.invalidateQueries({ queryKey: ['document-studio'] }),
    meta: { successMessage: 'تم حفظ القالب بنجاح' },
  });
}
