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

export function useAttendanceOperationsCommands() {
  const auth = useAuth(); const client = useQueryClient();
  const mutate = (name: string) => useMutation({ mutationFn: async (params: Record<string, unknown>) => auth.isMock ? params : rpc(name, params), onSuccess: () => client.invalidateQueries({ queryKey: ['attendance-operations'] }) });
  return {
    saveShift: mutate('save_shift_admin'),
    decideCorrection: mutate('decide_attendance_correction'),
    decideOvertime: mutate('decide_overtime_record'),
    closePeriod: mutate('close_attendance_period'),
    unlockPeriod: mutate('unlock_attendance_period'),
  };
}

export function useKpiAdmin(month: string) {
  const auth = useAuth();
  return useQuery({ queryKey: ['kpi-admin', month, auth.isMock], enabled: auth.status === 'authenticated', queryFn: async () => auth.isMock ? (await loadDomainMocks()).mockKpiAdminCatalog : kpiAdminCatalogSchema.parse(await rpc('get_kpi_admin_catalog', { p_month: `${month}-01` })) });
}

/** مصنع mutation مشترك لعمليات KPI — يوحّد الإبطال والمحاكاة */
function useKpiMutationFactory() {
  const auth = useAuth(); const client = useQueryClient();
  return (name: string) => useMutation({ mutationFn: async (params: Record<string, unknown>) => auth.isMock ? params : rpc(name, params), onSuccess: () => Promise.all([client.invalidateQueries({ queryKey: ['kpi-admin'] }), client.invalidateQueries({ queryKey: ['kpi-evaluations'] })]) });
}

/** إدارة دورات KPI — إنشاء وجدولة والتحكم بالحالة */
export function useKpiCycleCommands() {
  const mutate = useKpiMutationFactory();
  return { createCycle: mutate('create_kpi_cycle_admin'), manageCycle: mutate('manage_kpi_cycle'), rescheduleCycle: mutate('reschedule_kpi_cycle') };
}

/** سياسة KPI والاعتراضات — تحديث السياسة والبتّ في الاعتراضات */
export function useKpiPolicyCommands() {
  const mutate = useKpiMutationFactory();
  return { updatePolicy: mutate('create_kpi_policy_version'), decideAppeal: mutate('decide_kpi_appeal') };
}

/** عمليات تشغيلية — تحديث الحضور، التقارير، الإشعارات */
export function useKpiOperationsCommands() {
  const mutate = useKpiMutationFactory();
  return { refreshAttendance: mutate('refresh_kpi_attendance_inputs'), getReport: mutate('get_kpi_cycle_report'), sendNotifications: mutate('send_kpi_notifications_admin') };
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

// --- مصنع mutation مشترك للعمليات القضائية ---

/** يُنشئ خيارات mutation موحدة لاستدعاء RPC مع إبطال التخزين المؤقت */
function rpcMutationOpts(isMock: boolean, name: string, onInvalidate: () => Promise<unknown>, successMessage: string) {
  return {
    mutationFn: async (params: Record<string, unknown>) => isMock ? params : rpc(name, params),
    onSuccess: () => void onInvalidate(),
    meta: { successMessage },
  };
}

// --- Domain-grouped dispute hooks ---

/** إدارة القضية: قبول، انتقال حالة، تشكيل لجنة */
export function useDisputeCaseManagement() {
  const auth = useAuth(); const client = useQueryClient();
  const invalidate = () => Promise.all([client.invalidateQueries({ queryKey: ['dispute-operations'] }), client.invalidateQueries({ queryKey: ['action-center'] })]);
  return {
    acceptCase: useMutation(rpcMutationOpts(auth.isMock, 'accept_dispute_case', invalidate, 'تم قبول القضية بنجاح')),
    transitionCase: useMutation(rpcMutationOpts(auth.isMock, 'transition_dispute_case', invalidate, 'تم تحديث حالة القضية بنجاح')),
    setCommittee: useMutation(rpcMutationOpts(auth.isMock, 'set_dispute_committee', invalidate, 'تم تشكيل اللجنة بنجاح')),
  };
}

/** الجلسات والإفادات */
export function useDisputeSessionCommands() {
  const auth = useAuth(); const client = useQueryClient();
  const invalidate = () => Promise.all([client.invalidateQueries({ queryKey: ['dispute-operations'] }), client.invalidateQueries({ queryKey: ['action-center'] })]);
  return {
    addStatement: useMutation(rpcMutationOpts(auth.isMock, 'submit_dispute_statement', invalidate, 'تم تقديم الإفادة بنجاح')),
    scheduleSession: useMutation(rpcMutationOpts(auth.isMock, 'schedule_dispute_session_v2', invalidate, 'تمت جدولة الجلسة بنجاح')),
    finalizeSession: useMutation(rpcMutationOpts(auth.isMock, 'finalize_dispute_session_v2', invalidate, 'تم إنهاء الجلسة بنجاح')),
  };
}

/** القرارات: إصدار، تسوية، تنفيذ إجراء، اعتراضات */
export function useDisputeDecisionCommands() {
  const auth = useAuth(); const client = useQueryClient();
  const invalidate = () => Promise.all([client.invalidateQueries({ queryKey: ['dispute-operations'] }), client.invalidateQueries({ queryKey: ['action-center'] })]);
  return {
    issueDecision: useMutation(rpcMutationOpts(auth.isMock, 'issue_dispute_decision', invalidate, 'تم إصدار القرار بنجاح')),
    recordSettlement: useMutation(rpcMutationOpts(auth.isMock, 'record_dispute_settlement', invalidate, 'تم تسجيل التسوية بنجاح')),
    completeAction: useMutation(rpcMutationOpts(auth.isMock, 'complete_dispute_action', invalidate, 'تم تنفيذ الإجراء بنجاح')),
    decideAppeal: useMutation(rpcMutationOpts(auth.isMock, 'decide_dispute_appeal', invalidate, 'تم البتّ في الاعتراض بنجاح')),
  };
}

/** مسار الإجراء الإداري: اقتراح، قرار تنفيذي، تنفيذ */
export function useDisputeAdminActionCommands() {
  const auth = useAuth(); const client = useQueryClient();
  const invalidate = () => Promise.all([client.invalidateQueries({ queryKey: ['dispute-operations'] }), client.invalidateQueries({ queryKey: ['action-center'] })]);
  return {
    proposeAdminAction: useMutation(rpcMutationOpts(auth.isMock, 'propose_admin_action', invalidate, 'تم اقتراح الإجراء الإداري بنجاح')),
    decideAdminAction: useMutation(rpcMutationOpts(auth.isMock, 'decide_admin_action', invalidate, 'تم البتّ في الإجراء الإداري بنجاح')),
    executeAdminAction: useMutation(rpcMutationOpts(auth.isMock, 'execute_admin_action', invalidate, 'تم تنفيذ الإجراء الإداري بنجاح')),
  };
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
