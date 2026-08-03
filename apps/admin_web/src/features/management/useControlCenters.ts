import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { getSupabase } from '../../core/supabase';
import { rpc, invokeEdgeFunction } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';
import { loadDomainMocks } from '../mock/loadDomainMocks';
import type {
  AuditSecurityData,
  ExecutiveOverviewData,
  IntegrationCenterData,
  LiveLocationResponseData,
  LocationDirectoryItem,
  OperationsCenterData,
} from './controlCenterTypes';

export type {
  AuditSecurityData,
  ExecutiveOverviewData,
  IntegrationCenterData,
  LiveLocationResponseData,
  LocationDirectoryItem,
  OperationsCenterData,
} from './controlCenterTypes';

function rows(value: unknown): Array<Record<string, unknown>> {
  return Array.isArray(value) ? (value as Array<Record<string, unknown>>) : [];
}

function string(value: unknown, fallback = ''): string {
  return typeof value === 'string' ? value : fallback;
}

function nullableString(value: unknown): string | null {
  return typeof value === 'string' ? value : null;
}

function number(value: unknown, fallback = 0): number {
  return typeof value === 'number' ? value : fallback;
}

function boolean(value: unknown): boolean {
  return value === true;
}

async function tableRows(table: string, columns: string, orderBy: string, limit = 100) {
  const supabase = await getSupabase();
  const result = await supabase.from(table).select(columns).order(orderBy, { ascending: false }).limit(limit);
  if (result.error) throw result.error;
  return rows(result.data);
}

export function useLocationDirectory(search: string) {
  const auth = useAuth();
  return useQuery({
    queryKey: ['location-directory', search, auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<LocationDirectoryItem[]> => {
      if (auth.isMock) {
        const term = search.trim().toLocaleLowerCase('ar');
        const { mockLocations } = await loadDomainMocks();
        return mockLocations.filter((item) => !term || `${item.name} ${item.employeeCode} ${item.department ?? ''}`.toLocaleLowerCase('ar').includes(term));
      }
      const data = await rpc('get_location_directory', { p_search: search.trim() || null, p_limit: 200 });
      return rows(data).map((item) => ({
        id: string(item.id),
        name: string(item.name, 'موظف'),
        employeeCode: string(item.employeeCode, '—'),
        jobTitle: nullableString(item.jobTitle),
        department: nullableString(item.department),
        lastLatitude: typeof item.lastLatitude === 'number' ? item.lastLatitude : null,
        lastLongitude: typeof item.lastLongitude === 'number' ? item.lastLongitude : null,
        lastAccuracy: typeof item.lastAccuracy === 'number' ? item.lastAccuracy : null,
        lastRecordedAt: nullableString(item.lastRecordedAt),
        activeRequestId: nullableString(item.activeRequestId),
        activeRequestStatus: nullableString(item.activeRequestStatus),
      }));
    },
  });
}

export function useLiveLocationCommands() {
  const auth = useAuth();
  const client = useQueryClient();
  const request = useMutation({
    mutationFn: async (input: { employeeId: string; reason: string }) => {
      if (auth.isMock) return input;
      return rpc('request_live_location', {
        p_employee_id: input.employeeId,
        p_mode: 'snapshot',
        p_reason: input.reason,
      });
    },
    meta: { successMessage: 'تم إرسال طلب الموقع بنجاح' },
    onSuccess: async () => client.invalidateQueries({ queryKey: ['location-directory'] }),
  });
  return { request };
}

// نتيجة طلب موقع واحد (رأس + نقاط + فيديو) — get_live_location_response.
// تُستقصى دوريًا أثناء نشاط الطلب لعرض لحظي دون realtime.
export function useLiveLocationResponse(requestId: string | null, isActive: boolean) {
  const auth = useAuth();
  return useQuery({
    queryKey: ['live-location-response', requestId, auth.isMock],
    enabled: auth.status === 'authenticated' && Boolean(requestId) && !auth.isMock,
    refetchInterval: isActive ? 8000 : false,
    queryFn: async (): Promise<LiveLocationResponseData | null> => {
      if (!requestId) return null;
      return (await rpc<LiveLocationResponseData | null>('get_live_location_response', { p_request_id: requestId })) ?? null;
    },
  });
}

// V17 §9: useLiveLocationVideoUrl removed — video permanently disabled.

const MAP_URL_ERROR_MESSAGES: Record<string, string> = {
  METHOD_NOT_ALLOWED: 'طريقة الطلب غير مدعومة.',
  SERVER_CONFIGURATION: 'الخدمة غير مهيأة. تواصل مع الدعم.',
  unauthorized: 'انتهت صلاحية الجلسة. سجّل الدخول مجددًا.',
  INVALID_INPUT: 'معرّف الطلب غير صالح.',
  GATE_FAILED: 'تعذّر التحقق من صلاحية الوصول.',
  FORBIDDEN: 'ليس لديك صلاحية لعرض هذا الموقع.',
  SIGN_FAILED: 'تعذّر توقيع رابط لقطة الخريطة.',
};

export function useLiveLocationMapUrl() {
  return useMutation({
    mutationFn: async (requestId: string): Promise<string> => {
      const result = await invokeEdgeFunction<{ url?: string }>(
        'live-location-map-url',
        { requestId },
        MAP_URL_ERROR_MESSAGES,
        'تعذّر توقيع رابط لقطة الخريطة.',
      );
      const url = result?.url;
      if (!url) throw new Error('تعذّر توقيع رابط لقطة الخريطة.');
      return url;
    },
  });
}

// V17 §9: useLiveLocationLegalHold removed — video permanently disabled.

// لوحة المتابعة اليومية للمدير التنفيذي — get_executive_attendance_overview.
export function useExecutiveAttendanceOverview(date: string | null) {
  const auth = useAuth();
  return useQuery({
    queryKey: ['executive-attendance-overview', date, auth.isMock],
    enabled: auth.status === 'authenticated' && !auth.isMock,
    refetchInterval: 60000,
    queryFn: async (): Promise<ExecutiveOverviewData> => {
      const data = await rpc<ExecutiveOverviewData | null>('get_executive_attendance_overview', { p_date: date });
      return (data ?? { summary: { total: 0 }, employees: [] }) as ExecutiveOverviewData;
    },
  });
}

export function useOperationsCenter() {
  const auth = useAuth();
  return useQuery({
    queryKey: ['operations-center', auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<OperationsCenterData> => {
      if (auth.isMock) return (await loadDomainMocks()).mockOperations;
      const [employeeRows, taskRows, missionRows, convoyRows, requestRows] = await Promise.all([
        tableRows('employees', 'id,full_name_ar', 'full_name_ar', 500),
        tableRows('tasks', 'id,title,description,assignee_employee_id,priority,due_date,status', 'created_at', 200),
        tableRows('missions', 'id,request_id,employee_id,destination,purpose,start_at,end_at,transport_mode', 'start_at', 100),
        tableRows(
          'convoy_requests',
          'id,request_id,employee_id,convoy_name,origin,destination,departure_at,return_at,passengers_count,vehicles_count',
          'departure_at',
          100,
        ),
        tableRows('requests', 'id,status', 'created_at', 300),
      ]);
      const employees = employeeRows.map((item) => ({ id: string(item.id), name: string(item.full_name_ar, 'موظف') }));
      const employeeNames = new Map(employees.map((item) => [item.id, item.name]));
      const requestStatuses = new Map(requestRows.map((item) => [string(item.id), string(item.status, 'pending')]));
      return {
        employees,
        tasks: taskRows.map((item) => ({
          id: string(item.id),
          title: string(item.title),
          description: nullableString(item.description),
          assigneeId: nullableString(item.assignee_employee_id),
          assigneeName: employeeNames.get(string(item.assignee_employee_id)) ?? 'غير مسندة',
          priority: string(item.priority, 'medium'),
          dueDate: nullableString(item.due_date),
          status: string(item.status, 'pending'),
        })),
        missions: missionRows.map((item) => ({
          id: string(item.id),
          employeeName: employeeNames.get(string(item.employee_id)) ?? 'موظف',
          destination: string(item.destination),
          purpose: string(item.purpose),
          startAt: string(item.start_at),
          endAt: string(item.end_at),
          status: requestStatuses.get(string(item.request_id)) ?? 'pending',
          transportMode: nullableString(item.transport_mode),
        })),
        convoys: convoyRows.map((item) => ({
          id: string(item.id),
          employeeName: employeeNames.get(string(item.employee_id)) ?? 'موظف',
          name: string(item.convoy_name),
          origin: string(item.origin),
          destination: string(item.destination),
          departureAt: string(item.departure_at),
          returnAt: nullableString(item.return_at),
          passengers: number(item.passengers_count, 1),
          vehicles: number(item.vehicles_count, 1),
          status: requestStatuses.get(string(item.request_id)) ?? 'pending',
        })),
      };
    },
  });
}

export function useOperationsCommands() {
  const auth = useAuth();
  const client = useQueryClient();
  const refresh = async () => client.invalidateQueries({ queryKey: ['operations-center'] });
  const createTask = useMutation({
    mutationFn: async (input: { title: string; description: string; assigneeId: string; priority: string; dueDate: string }) => {
      if (auth.isMock) return input;
      const id = await rpc<string>('admin_create_task', {
        p_title: input.title,
        p_description: input.description || null,
        p_assignee_id: input.assigneeId || null,
        p_priority: input.priority,
        p_due_date: input.dueDate || null,
      });
      return { id };
    },
    meta: { successMessage: 'تم إنشاء المهمة بنجاح' },
    onSuccess: refresh,
  });
  const transitionTask = useMutation({
    mutationFn: async (input: { id: string; status: string }) => {
      if (auth.isMock) return input;
      await rpc('admin_transition_task', { p_id: input.id, p_status: input.status });
      return input;
    },
    onSuccess: refresh,
  });
  return { createTask, transitionTask };
}
export function useAuditSecurityCenter() {
  const auth = useAuth();
  return useQuery({
    queryKey: ['audit-security-center', auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<AuditSecurityData> => {
      if (auth.isMock) return (await loadDomainMocks()).mockAudit;
      const raw = await rpc<Record<string, unknown>>('get_audit_security_data');
      const securityRows = rows(raw.securityEvents);
      const auditRows = rows(raw.auditEvents);
      const deviceRows = rows(raw.devices);
      return {
        securityEvents: securityRows.map((item) => ({
          id: string(item.id),
          eventType: string(item.event_type),
          severity: string(item.severity),
          outcome: string(item.outcome),
          handled: boolean(item.handled),
          occurredAt: string(item.occurred_at),
        })),
        auditEvents: auditRows.map((item) => ({
          id: string(item.id),
          eventType: string(item.event_type),
          category: string(item.category),
          severity: string(item.severity),
          summary: nullableString(item.summary_ar),
          targetTable: nullableString(item.target_table),
          occurredAt: string(item.occurred_at),
        })),
        devices: deviceRows.map((item) => ({
          id: string(item.id),
          name: string(item.device_name) || string(item.device_model, 'جهاز غير مسمى'),
          platform: string(item.platform),
          appVersion: string(item.app_version),
          environment: string(item.environment),
          trusted: boolean(item.trusted),
          status: string(item.status),
          lastSeenAt: string(item.last_seen_at),
          firstSeenAt: string(item.first_seen_at),
          employeeId: nullableString(item.employee_id),
          employeeName: nullableString(item.employee_name),
          deviceModel: nullableString(item.device_model),
          osVersion: nullableString(item.os_version),
        })),
      };
    },
  });
}

export function useAuditSecurityCommands() {
  const auth = useAuth();
  const client = useQueryClient();
  const handleEvent = useMutation({
    mutationFn: async (id: string) => {
      if (auth.isMock) return id;
      await rpc('admin_handle_security_event', { p_id: id });
      return id;
    },
    onSuccess: async () => client.invalidateQueries({ queryKey: ['audit-security-center'] }),
  });
  const revokeDevice = useMutation({
    mutationFn: async (input: { deviceId: string; reason: string }) => {
      if (auth.isMock) return input;
      return rpc('revoke_managed_device', { p_device_id: input.deviceId, p_reason: input.reason });
    },
    onSuccess: async () => client.invalidateQueries({ queryKey: ['audit-security-center'] }),
  });
  return { handleEvent, revokeDevice };
}

export function useIntegrationCenter() {
  const auth = useAuth();
  return useQuery({
    queryKey: ['integration-center', auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<IntegrationCenterData> => {
      if (auth.isMock) return (await loadDomainMocks()).mockIntegrations;
      const raw = await rpc<Record<string, unknown>>('get_integration_center_data');
      const integrationRows = rows(raw.integrations);
      const logRows = rows(raw.logs);
      const outboxRows = rows(raw.outbox);
      const runRows = rows(raw.automationRuns);
      return {
        integrations: integrationRows.map((item) => ({
          id: string(item.id),
          name: string(item.name_ar),
          provider: string(item.provider),
          category: string(item.category),
          status: string(item.status),
          enabled: boolean(item.is_enabled),
          lastSyncAt: nullableString(item.last_sync_at),
          lastError: nullableString(item.last_error),
        })),
        logs: logRows.map((item) => ({
          id: string(item.id),
          integrationId: nullableString(item.integration_id),
          operation: nullableString(item.operation),
          direction: string(item.direction),
          status: string(item.status),
          httpStatus: typeof item.http_status === 'number' ? item.http_status : null,
          durationMs: typeof item.duration_ms === 'number' ? item.duration_ms : null,
          occurredAt: string(item.occurred_at),
          error: nullableString(item.error_message),
        })),
        outbox: outboxRows.map((item) => ({
          id: string(item.id),
          eventType: string(item.event_type),
          status: string(item.status),
          attempts: number(item.attempts),
          maxAttempts: number(item.max_attempts, 8),
          nextAttemptAt: string(item.next_attempt_at),
          createdAt: string(item.created_at),
          error: nullableString(item.last_error),
        })),
        automationRuns: runRows.map((item) => ({
          id: string(item.id),
          status: string(item.status),
          attempts: number(item.attempts),
          createdAt: string(item.created_at),
          completedAt: nullableString(item.completed_at),
          error: nullableString(item.error_detail),
        })),
      };
    },
  });
}

export function useIntegrationCommands() {
  const auth = useAuth();
  const client = useQueryClient();
  const toggle = useMutation({
    mutationFn: async (input: { id: string; enabled: boolean }) => {
      if (auth.isMock) return input;
      await rpc('admin_toggle_integration', { p_id: input.id, p_enabled: input.enabled });
      return input;
    },
    onSuccess: async () => client.invalidateQueries({ queryKey: ['integration-center'] }),
  });
  return { toggle };
}
