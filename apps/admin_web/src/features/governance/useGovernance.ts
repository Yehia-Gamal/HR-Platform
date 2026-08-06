import { z } from 'zod';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';

const servicePortalSchema = z.object({
  catalog: z.array(z.object({
    id: z.string(),
    code: z.string().nullable().optional(),
    name: z.string(),
    description: z.string().nullable().optional(),
    category: z.string().nullable().optional(),
    slaHours: z.number().nullable().optional(),
  }).catch({ id: '', name: '—' })).default([]),
  requests: z.array(z.object({
    id: z.string(),
    number: z.string(),
    serviceName: z.string().nullable().optional(),
    title: z.string(),
    description: z.string().nullable().optional(),
    priority: z.string(),
    status: z.string(),
    dueAt: z.string().nullable().optional(),
  }).catch({ id: '', number: '—', title: '—', priority: 'normal', status: 'open' })).default([]),
});

const enterpriseCatalogSchema = z.object({
  risks: z.array(z.object({
    id: z.string(),
    number: z.string(),
    title: z.string(),
    category: z.string(),
    probability: z.number(),
    impact: z.number(),
    score: z.number(),
    status: z.string(),
    reviewDate: z.string().nullable().optional(),
  }).catch({ id: '', number: '—', title: '—', category: '—', probability: 0, impact: 0, score: 0, status: 'open' })).default([]),
  incidents: z.array(z.object({
    id: z.string(),
    number: z.string(),
    title: z.string(),
    severity: z.string(),
    status: z.string(),
    occurredAt: z.string().nullable().optional(),
  }).catch({ id: '', number: '—', title: '—', severity: 'low', status: 'open' })).default([]),
  audits: z.array(z.object({
    id: z.string(),
    code: z.string(),
    title: z.string(),
    status: z.string(),
    plannedStart: z.string().nullable().optional(),
    findings: z.number().default(0),
  }).catch({ id: '', code: '—', title: '—', status: 'draft', findings: 0 })).default([]),
  projects: z.array(z.object({
    id: z.string(),
    code: z.string(),
    name: z.string(),
    status: z.string(),
    priority: z.string(),
    progress: z.number(),
  }).catch({ id: '', code: '—', name: '—', status: 'draft', priority: 'normal', progress: 0 })).default([]),
  lastUpdatedAt: z.string().optional(),
});

export type EnterpriseCatalog = z.infer<typeof enterpriseCatalogSchema>;
export type ServicePortal = z.infer<typeof servicePortalSchema>;

export function useEnterpriseCatalog() {
  const auth = useAuth();
  return useQuery({
    queryKey: ['enterprise-catalog'],
    enabled: auth.status === 'authenticated',
    queryFn: async () => enterpriseCatalogSchema.parse(await rpc('get_enterprise_management_catalog', {})),
    staleTime: 30_000,
  });
}

export function useMyServicePortal() {
  const auth = useAuth();
  return useQuery({
    queryKey: ['my-service-portal'],
    enabled: auth.status === 'authenticated',
    queryFn: async () => servicePortalSchema.parse(await rpc('get_my_service_portal', {})),
    staleTime: 30_000,
  });
}

export function useSubmitServiceRequest() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (input: { catalogItemId: string; title: string; description: string; priority?: string }) =>
      rpc('submit_my_service_request', {
        p_catalog_item_id: input.catalogItemId,
        p_title: input.title,
        p_description: input.description,
        p_priority: input.priority ?? 'normal',
      }),
    onSuccess: () => client.invalidateQueries({ queryKey: ['my-service-portal'] }),
    meta: { successMessage: 'تم تقديم طلب الخدمة بنجاح' },
  });
}
