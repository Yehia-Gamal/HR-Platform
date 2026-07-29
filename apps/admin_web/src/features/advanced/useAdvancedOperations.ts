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

// --- Domain-grouped dispute hooks ---

/** إدارة القضية: قبول، انتقال حالة، تشكيل لجنة */
export function useDisputeCaseManagement() {
  const auth = useAuth(); const client = useQueryClient();
  const mutate = (name: string) => useMutation({ mutationFn: async (params: Record<string, unknown>) => auth.isMock ? params : rpc(name, params), onSuccess: () => Promise.all([client.invalidateQueries({ queryKey: ['dispute-operations'] }), client.invalidateQueries({ queryKey: ['action-center'] })]) });
  return {
    acceptCase: mutate('accept_dispute_case'),
    transitionCase: mutate('transition_dispute_case'),
    setCommittee: mutate('set_dispute_committee'),
  };
}

/** الجلسات والإفادات */
export function useDisputeSessionCommands() {
  const auth = useAuth(); const client = useQueryClient();
  const mutate = (name: string) => useMutation({ mutationFn: async (params: Record<string, unknown>) => auth.isMock ? params : rpc(name, params), onSuccess: () => Promise.all([client.invalidateQueries({ queryKey: ['dispute-operations'] }), client.invalidateQueries({ queryKey: ['action-center'] })]) });
  return {
    addStatement: mutate('submit_dispute_statement'),
    scheduleSession: mutate('schedule_dispute_session_v2'),
    finalizeSession: mutate('finalize_dispute_session_v2'),
  };
}

/** القرارات: إصدار، تسوية، تنفيذ إجراء، اعتراضات */
export function useDisputeDecisionCommands() {
  const auth = useAuth(); const client = useQueryClient();
  const mutate = (name: string) => useMutation({ mutationFn: async (params: Record<string, unknown>) => auth.isMock ? params : rpc(name, params), onSuccess: () => Promise.all([client.invalidateQueries({ queryKey: ['dispute-operations'] }), client.invalidateQueries({ queryKey: ['action-center'] })]) });
  return {
    issueDecision: mutate('issue_dispute_decision'),
    recordSettlement: mutate('record_dispute_settlement'),
    completeAction: mutate('complete_dispute_action'),
    decideAppeal: mutate('decide_dispute_appeal'),
  };
}

/** مسار الإجراء الإداري: اقتراح، قرار تنفيذي، تنفيذ */
export function useDisputeAdminActionCommands() {
  const auth = useAuth(); const client = useQueryClient();
  const mutate = (name: string) => useMutation({ mutationFn: async (params: Record<string, unknown>) => auth.isMock ? params : rpc(name, params), onSuccess: () => Promise.all([client.invalidateQueries({ queryKey: ['dispute-operations'] }), client.invalidateQueries({ queryKey: ['action-center'] })]) });
  return {
    proposeAdminAction: mutate('propose_admin_action'),
    decideAdminAction: mutate('decide_admin_action'),
    executeAdminAction: mutate('execute_admin_action'),
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
