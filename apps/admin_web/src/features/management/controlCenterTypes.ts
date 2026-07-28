export interface LocationDirectoryItem {
  id: string;
  name: string;
  employeeCode: string;
  jobTitle: string | null;
  department: string | null;
  lastLatitude: number | null;
  lastLongitude: number | null;
  lastAccuracy: number | null;
  lastRecordedAt: string | null;
  activeRequestId: string | null;
  activeRequestStatus: string | null;
}

export interface OperationsCenterData {
  employees: Array<{ id: string; name: string }>;
  tasks: Array<{
    id: string;
    title: string;
    description: string | null;
    assigneeId: string | null;
    assigneeName: string;
    priority: string;
    dueDate: string | null;
    status: string;
  }>;
  missions: Array<{
    id: string;
    employeeName: string;
    destination: string;
    purpose: string;
    startAt: string;
    endAt: string;
    status: string;
    transportMode: string | null;
  }>;
  convoys: Array<{
    id: string;
    employeeName: string;
    name: string;
    origin: string;
    destination: string;
    departureAt: string;
    returnAt: string | null;
    passengers: number;
    vehicles: number;
    status: string;
  }>;
}

export interface AuditSecurityData {
  securityEvents: Array<{
    id: string;
    eventType: string;
    severity: string;
    outcome: string;
    handled: boolean;
    occurredAt: string;
  }>;
  auditEvents: Array<{
    id: string;
    eventType: string;
    category: string;
    severity: string;
    summary: string | null;
    targetTable: string | null;
    occurredAt: string;
  }>;
  devices: Array<{
    id: string;
    name: string;
    platform: string;
    appVersion: string;
    environment: string;
    trusted: boolean;
    status: string;
    lastSeenAt: string;
    employeeId: string | null;
    employeeName: string | null;
    deviceModel: string | null;
    osVersion: string | null;
    firstSeenAt: string;
  }>;
}

export interface IntegrationCenterData {
  integrations: Array<{
    id: string;
    name: string;
    provider: string;
    category: string;
    status: string;
    enabled: boolean;
    lastSyncAt: string | null;
    lastError: string | null;
  }>;
  logs: Array<{
    id: string;
    integrationId: string | null;
    operation: string | null;
    direction: string;
    status: string;
    httpStatus: number | null;
    durationMs: number | null;
    occurredAt: string;
    error: string | null;
  }>;
  outbox: Array<{
    id: string;
    eventType: string;
    status: string;
    attempts: number;
    maxAttempts: number;
    nextAttemptAt: string;
    createdAt: string;
    error: string | null;
  }>;
  automationRuns: Array<{
    id: string;
    status: string;
    attempts: number;
    createdAt: string;
    completedAt: string | null;
    error: string | null;
  }>;
}
