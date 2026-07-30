import {
  attendanceOperationsCatalogSchema,
  disputeOperationsCatalogSchema,
  disputeParticipantDirectorySchema,
  kpiAdminCatalogSchema,
  type DisputeParticipant,
} from '@ahla/shared-contracts';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';
import { loadDomainMocks } from '../mock/loadDomainMocks';

export function useAttendanceOperations(month: string) {
  const auth = useAuth();
  return useQuery({ queryKey: ['attendance-operations', month, auth.isMock], enabled: auth.status === 'authenticated', queryFn: async () => auth.isMock ? (await loadDomainMocks()).mockAttendanceOps : attendanceOperationsCatalogSchema.parse(await rpc('get_attendance_operations_catalog', { p_month: `${month}-01` })) });
}

/** خيارات mutation مشتركة — لا يستدعي hooks */
function attendanceMutationOpts(auth: ReturnType<typeof useAuth>, client: ReturnType<typeof useQueryClient>, name: string) {
  return { mutationFn: async (params: Record<string, unknown>) => auth.isMock ? params : rpc(name, params), onSuccess: () => { client.invalidateQueries({ queryKey: ['attendance-operations'] }); } };
}

export function useAttendanceOperationsCommands() {
  const auth = useAuth(); const client = useQueryClient();
  const saveShift = useMutation(attendanceMutationOpts(auth, client, 'save_shift_admin'));
  const decideCorrection = useMutation(attendanceMutationOpts(auth, client, 'decide_attendance_correction'));
  const decideOvertime = useMutation(attendanceMutationOpts(auth, client, 'decide_overtime_record'));
  const closePeriod = useMutation(attendanceMutationOpts(auth, client, 'close_attendance_period'));
  const unlockPeriod = useMutation(attendanceMutationOpts(auth, client, 'unlock_attendance_period'));
  return { saveShift, decideCorrection, decideOvertime, closePeriod, unlockPeriod };
}

export function useKpiAdmin(month: string) {
  const auth = useAuth();
  return useQuery({ queryKey: ['kpi-admin', month, auth.isMock], enabled: auth.status === 'authenticated', queryFn: async () => auth.isMock ? (await loadDomainMocks()).mockKpiAdminCatalog : kpiAdminCatalogSchema.parse(await rpc('get_kpi_admin_catalog', { p_month: `${month}-01` })) });
}

/** خيارات mutation مشتركة لعمليات KPI — لا يستدعي hooks */
function kpiMutationOpts(auth: ReturnType<typeof useAuth>, client: ReturnType<typeof useQueryClient>, name: string) {
  return { mutationFn: async (params: Record<string, unknown>) => auth.isMock ? params : rpc(name, params), onSuccess: () => { Promise.all([client.invalidateQueries({ queryKey: ['kpi-admin'] }), client.invalidateQueries({ queryKey: ['kpi-evaluations'] })]); } };
}

/** إدارة دورات KPI — إنشاء وجدولة والتحكم بالحالة */
export function useKpiCycleCommands() {
  const auth = useAuth(); const client = useQueryClient();
  const createCycle = useMutation(kpiMutationOpts(auth, client, 'create_kpi_cycle_admin'));
  const manageCycle = useMutation(kpiMutationOpts(auth, client, 'manage_kpi_cycle'));
  const rescheduleCycle = useMutation(kpiMutationOpts(auth, client, 'reschedule_kpi_cycle'));
  return { createCycle, manageCycle, rescheduleCycle };
}

/** سياسة KPI والاعتراضات — تحديث السياسة والبتّ في الاعتراضات */
export function useKpiPolicyCommands() {
  const auth = useAuth(); const client = useQueryClient();
  const updatePolicy = useMutation(kpiMutationOpts(auth, client, 'create_kpi_policy_version'));
  const decideAppeal = useMutation(kpiMutationOpts(auth, client, 'decide_kpi_appeal'));
  return { updatePolicy, decideAppeal };
}

/** عمليات تشغيلية — تحديث الحضور، التقارير، الإشعارات */
export function useKpiOperationsCommands() {
  const auth = useAuth(); const client = useQueryClient();
  const refreshAttendance = useMutation(kpiMutationOpts(auth, client, 'refresh_kpi_attendance_inputs'));
  const getReport = useMutation(kpiMutationOpts(auth, client, 'get_kpi_cycle_report'));
  const sendNotifications = useMutation(kpiMutationOpts(auth, client, 'send_kpi_notifications_admin'));
  return { refreshAttendance, getReport, sendNotifications };
}

/** واجهة موحدة — تجمع كل أوامر KPI الإدارية للتوافق مع المستهلكين الحاليين */
export function useKpiAdminCommands() {
  return { ...useKpiCycleCommands(), ...useKpiPolicyCommands(), ...useKpiOperationsCommands() };
}

export function useDisputeOperations(status?: string) {
  const auth = useAuth();
  return useQuery({ queryKey: ['dispute-operations', status ?? 'all', auth.isMock], enabled: auth.status === 'authenticated', queryFn: async () => auth.isMock ? (await loadDomainMocks()).mockDisputeOps : disputeOperationsCatalogSchema.parse(await rpc('get_dispute_operations_catalog', { p_status: status || null })) });
}

export function useDisputeParticipantDirectory(search = '') {
  const auth = useAuth();
  return useQuery<DisputeParticipant[]>({
    queryKey: ['dispute-participant-directory', search, auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async () => auth.isMock ? [] : disputeParticipantDirectorySchema.parse(await rpc('get_dispute_participant_directory', { p_search: search || null, p_limit: 200 })),
    staleTime: 5 * 60 * 1000,
  });
}

// --- Domain-grouped dispute hooks ---

/** خيارات mutation مشتركة لعمليات النزاعات — لا يستدعي hooks */
function disputeMutationOpts(auth: ReturnType<typeof useAuth>, client: ReturnType<typeof useQueryClient>, name: string) {
  return { mutationFn: async (params: Record<string, unknown>) => auth.isMock ? params : rpc(name, params), onSuccess: () => { Promise.all([client.invalidateQueries({ queryKey: ['dispute-operations'] }), client.invalidateQueries({ queryKey: ['action-center'] })]); } };
}

/** إدارة القضية: قبول، انتقال حالة، تشكيل لجنة */
export function useDisputeCaseManagement() {
  const auth = useAuth(); const client = useQueryClient();
  const acceptCase = useMutation(disputeMutationOpts(auth, client, 'accept_dispute_case'));
  const transitionCase = useMutation(disputeMutationOpts(auth, client, 'transition_dispute_case'));
  const setCommittee = useMutation(disputeMutationOpts(auth, client, 'set_dispute_committee'));
  return { acceptCase, transitionCase, setCommittee };
}

/** الجلسات والإفادات */
export function useDisputeSessionCommands() {
  const auth = useAuth(); const client = useQueryClient();
  const addStatement = useMutation(disputeMutationOpts(auth, client, 'submit_dispute_statement'));
  const scheduleSession = useMutation(disputeMutationOpts(auth, client, 'schedule_dispute_session_v2'));
  const finalizeSession = useMutation(disputeMutationOpts(auth, client, 'finalize_dispute_session_v2'));
  return { addStatement, scheduleSession, finalizeSession };
}

/** القرارات: إصدار، تسوية، تنفيذ إجراء، اعتراضات */
export function useDisputeDecisionCommands() {
  const auth = useAuth(); const client = useQueryClient();
  const issueDecision = useMutation(disputeMutationOpts(auth, client, 'issue_dispute_decision'));
  const recordSettlement = useMutation(disputeMutationOpts(auth, client, 'record_dispute_settlement'));
  const completeAction = useMutation(disputeMutationOpts(auth, client, 'complete_dispute_action'));
  const decideAppeal = useMutation(disputeMutationOpts(auth, client, 'decide_dispute_appeal'));
  return { issueDecision, recordSettlement, completeAction, decideAppeal };
}

/** مسار الإجراء الإداري: اقتراح، قرار تنفيذي، تنفيذ */
export function useDisputeAdminActionCommands() {
  const auth = useAuth(); const client = useQueryClient();
  const proposeAdminAction = useMutation(disputeMutationOpts(auth, client, 'propose_admin_action'));
  const decideAdminAction = useMutation(disputeMutationOpts(auth, client, 'decide_admin_action'));
  const executeAdminAction = useMutation(disputeMutationOpts(auth, client, 'execute_admin_action'));
  return { proposeAdminAction, decideAdminAction, executeAdminAction };
}

/** Facade — backward-compatible aggregate of all dispute mutations */
export function useDisputeCommands() {
  return {
    ...useDisputeCaseManagement(),
    ...useDisputeSessionCommands(),
    ...useDisputeDecisionCommands(),
    ...useDisputeAdminActionCommands(),
  };
}
