import {
  recruitmentWorkbenchSchema,
  reportSchedulerCatalogSchema,
  type RecruitmentWorkbench,
  type ReportSchedulerCatalog,
} from '@ahla/shared-contracts';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';

const id = (tail: string) => `90000000-0000-4000-8000-${tail.padStart(12, '0')}`;
const now = new Date().toISOString();

const mockRecruitment: RecruitmentWorkbench = {
  requisitions: [{ id: id('1'), title: 'أخصائي تشغيل', departmentId: id('2'), departmentName: 'التشغيل', headcount: 2, status: 'approved', createdAt: now }],
  postings: [{ id: id('3'), requisitionId: id('1'), title: 'أخصائي تشغيل', slug: 'operations-specialist', visibility: 'external', status: 'published', publishedAt: now, closesAt: null }],
  applications: [{ id: id('4'), candidateId: id('5'), candidateName: 'مرشح تجريبي', postingId: id('3'), jobTitle: 'أخصائي تشغيل', status: 'active', stageId: id('6'), stageName: 'مقابلة', appliedAt: now, assigneeId: null }],
  candidates: [{ id: id('5'), name: 'مرشح تجريبي', email: 'candidate@example.com', phone: '+201000000000', source: 'referral', tags: ['تشغيل'], createdAt: now }],
  stages: [{ id: id('6'), postingId: id('3'), name: 'مقابلة', orderIndex: 3, slaDays: 3 }],
  interviews: [], offers: [], lastUpdatedAt: now,
};
const mockReports: ReportSchedulerCatalog = { schedules: [], runs: [], notificationQueue: { queued: 0, failed: 0 }, lastUpdatedAt: now };

export function useRecruitmentWorkbench() {
  const auth = useAuth();
  return useQuery({ queryKey: ['recruitment-workbench', auth.isMock], enabled: auth.status === 'authenticated', queryFn: async () => auth.isMock ? mockRecruitment : recruitmentWorkbenchSchema.parse(await rpc('get_recruitment_workbench_catalog')) });
}

export function useRecruitmentWorkbenchCommands() {
  const auth = useAuth(); const client = useQueryClient();
  const refresh = async () => client.invalidateQueries({ queryKey: ['recruitment-workbench'] });
  const moveStage = useMutation({
    mutationFn: async (input: { applicationId: string; stageId: string; reason?: string }) => auth.isMock ? input : rpc('move_application_stage_admin', { p_application_id: input.applicationId, p_to_stage_id: input.stageId, p_reason: input.reason ?? null }),
    onSuccess: refresh,
  });
  const scheduleInterview = useMutation({
    mutationFn: async (input: { applicationId: string; mode: string; scheduledAt: string; locationOrLink?: string; panelists?: string[] }) => auth.isMock ? input : rpc('schedule_interview_admin', { p_application_id: input.applicationId, p_mode: input.mode, p_scheduled_at: input.scheduledAt, p_location_or_link: input.locationOrLink ?? null, p_panelists: input.panelists?.length ? input.panelists : null, p_interview_id: null }),
    onSuccess: refresh,
  });
  const decideInterview = useMutation({
    mutationFn: async (input: { interviewId: string; status: 'completed' | 'cancelled' | 'no_show' }) => auth.isMock ? input : rpc('decide_interview_admin', { p_interview_id: input.interviewId, p_status: input.status }),
    onSuccess: refresh,
  });
  const createOffer = useMutation({
    mutationFn: async (input: { applicationId: string; title?: string; salary?: number | null; contractType?: string; startDate?: string | null; expiresAt?: string | null }) => auth.isMock ? input : rpc('create_job_offer_admin', { p_application_id: input.applicationId, p_title: input.title ?? null, p_salary: input.salary ?? null, p_contract_type: input.contractType ?? null, p_start_date: input.startDate ?? null, p_expires_at: input.expiresAt ?? null }),
    onSuccess: refresh,
  });
  const transitionOffer = useMutation({
    mutationFn: async (input: { offerId: string; action: 'submit' | 'approve' | 'send' | 'accept' | 'decline' | 'withdraw' }) => auth.isMock ? input : rpc('transition_job_offer_admin', { p_offer_id: input.offerId, p_action: input.action }),
    onSuccess: refresh,
  });
  const hireApplicant = useMutation({
    mutationFn: async (input: { applicationId: string }) => auth.isMock ? input : rpc('hire_from_application_admin', { p_application_id: input.applicationId }),
    onSuccess: refresh,
  });
  return { moveStage, scheduleInterview, decideInterview, createOffer, transitionOffer, hireApplicant };
}

export function useReportSchedulerCatalog() {
  const auth = useAuth();
  return useQuery({ queryKey: ['report-scheduler', auth.isMock], enabled: auth.status === 'authenticated', queryFn: async () => auth.isMock ? mockReports : reportSchedulerCatalogSchema.parse(await rpc('get_report_scheduler_catalog')) });
}
export function useReportSchedulerCommands() {
  const auth = useAuth(); const client = useQueryClient();
  const upsert = useMutation({ mutationFn: async (input: { code: string; name: string; reportType: string; audienceScope: string; scheduleKind: string; runHour: number; channels: string[] }) => auth.isMock ? id('40') : rpc('upsert_scheduled_report_admin', { p_id: null, p_code: input.code, p_name_ar: input.name, p_report_type: input.reportType, p_audience_scope: input.audienceScope, p_schedule_kind: input.scheduleKind, p_run_hour: input.runHour, p_run_weekday: input.scheduleKind === 'weekly' ? 1 : null, p_run_monthday: input.scheduleKind === 'monthly' ? 1 : null, p_delivery_channels: input.channels, p_active: true }), onSuccess: async () => client.invalidateQueries({ queryKey: ['report-scheduler'] }) });
  return { upsert };
}
