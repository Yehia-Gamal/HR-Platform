import { recruitmentWorkbenchSchema, reportSchedulerCatalogSchema } from '@ahla/shared-contracts';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';
import { loadDomainMocks } from '../mock/loadDomainMocks';

export function useRecruitmentWorkbench() {
  const auth = useAuth();
  return useQuery({
    queryKey: ['recruitment-workbench', auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async () =>
      auth.isMock ? (await loadDomainMocks()).mockRecruitmentWorkbench : recruitmentWorkbenchSchema.parse(await rpc('get_recruitment_workbench_catalog')),
  });
}

export function useRecruitmentWorkbenchCommands() {
  const auth = useAuth();
  const client = useQueryClient();
  const refresh = async () => client.invalidateQueries({ queryKey: ['recruitment-workbench'] });
  const moveStage = useMutation({
    mutationFn: async (input: { applicationId: string; stageId: string; reason?: string }) =>
      auth.isMock
        ? input
        : rpc('move_application_stage_admin', { p_application_id: input.applicationId, p_to_stage_id: input.stageId, p_reason: input.reason ?? null }),
    meta: { successMessage: 'تم نقل المرشح إلى المرحلة التالية بنجاح' },
    onSuccess: refresh,
  });
  const scheduleInterview = useMutation({
    mutationFn: async (input: { applicationId: string; mode: string; scheduledAt: string; locationOrLink?: string; panelists?: string[] }) =>
      auth.isMock
        ? input
        : rpc('schedule_interview_admin', {
            p_application_id: input.applicationId,
            p_mode: input.mode,
            p_scheduled_at: input.scheduledAt,
            p_location_or_link: input.locationOrLink ?? null,
            p_panelists: input.panelists?.length ? input.panelists : null,
            p_interview_id: null,
          }),
    onSuccess: refresh,
  });
  const decideInterview = useMutation({
    mutationFn: async (input: { interviewId: string; status: 'completed' | 'cancelled' | 'no_show' }) =>
      auth.isMock ? input : rpc('decide_interview_admin', { p_interview_id: input.interviewId, p_status: input.status }),
    onSuccess: refresh,
  });
  const createOffer = useMutation({
    mutationFn: async (input: {
      applicationId: string;
      title?: string;
      salary?: number | null;
      contractType?: string;
      startDate?: string | null;
      expiresAt?: string | null;
    }) =>
      auth.isMock
        ? input
        : rpc('create_job_offer_admin', {
            p_application_id: input.applicationId,
            p_title: input.title ?? null,
            p_salary: input.salary ?? null,
            p_contract_type: input.contractType ?? null,
            p_start_date: input.startDate ?? null,
            p_expires_at: input.expiresAt ?? null,
          }),
    onSuccess: refresh,
  });
  const transitionOffer = useMutation({
    mutationFn: async (input: { offerId: string; action: 'submit' | 'approve' | 'send' | 'accept' | 'decline' | 'withdraw' }) =>
      auth.isMock ? input : rpc('transition_job_offer_admin', { p_offer_id: input.offerId, p_action: input.action }),
    onSuccess: refresh,
  });
  const hireApplicant = useMutation({
    mutationFn: async (input: { applicationId: string }) =>
      auth.isMock ? input : rpc('hire_from_application_admin', { p_application_id: input.applicationId }),
    onSuccess: refresh,
  });
  return { moveStage, scheduleInterview, decideInterview, createOffer, transitionOffer, hireApplicant };
}

export function useReportSchedulerCatalog() {
  const auth = useAuth();
  return useQuery({
    queryKey: ['report-scheduler', auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async () =>
      auth.isMock ? (await loadDomainMocks()).mockReportScheduler : reportSchedulerCatalogSchema.parse(await rpc('get_report_scheduler_catalog')),
  });
}
export function useReportSchedulerCommands() {
  const auth = useAuth();
  const client = useQueryClient();
  const upsert = useMutation({
    mutationFn: async (input: {
      code: string;
      name: string;
      reportType: string;
      audienceScope: string;
      scheduleKind: string;
      runHour: number;
      channels: string[];
    }) =>
      auth.isMock
        ? '90000000-0000-4000-8000-000000000040'
        : rpc('upsert_scheduled_report_admin', {
            p_id: null,
            p_code: input.code,
            p_name_ar: input.name,
            p_report_type: input.reportType,
            p_audience_scope: input.audienceScope,
            p_schedule_kind: input.scheduleKind,
            p_run_hour: input.runHour,
            p_run_weekday: input.scheduleKind === 'weekly' ? 1 : null,
            p_run_monthday: input.scheduleKind === 'monthly' ? 1 : null,
            p_delivery_channels: input.channels,
            p_active: true,
          }),
    onSuccess: async () => client.invalidateQueries({ queryKey: ['report-scheduler'] }),
  });
  return { upsert };
}
