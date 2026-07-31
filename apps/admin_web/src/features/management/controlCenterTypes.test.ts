import { describe, it, expect } from 'vitest';
import type { LocationDirectoryItem, OperationsCenterData, AuditSecurityData, IntegrationCenterData } from './controlCenterTypes';

describe('controlCenterTypes', () => {
  it('LocationDirectoryItem accepts a valid shape', () => {
    const item: LocationDirectoryItem = {
      id: 'abc',
      name: 'Test',
      employeeCode: 'EMP-1',
      jobTitle: 'Dev',
      department: 'IT',
      lastLatitude: 30.0,
      lastLongitude: 31.0,
      lastAccuracy: 10,
      lastRecordedAt: '2026-01-01T00:00:00Z',
      activeRequestId: null,
      activeRequestStatus: null,
    };
    expect(item.id).toBe('abc');
    expect(item.lastLatitude).toBe(30.0);
    expect(item.activeRequestId).toBeNull();
  });

  it('LocationDirectoryItem accepts null coordinates', () => {
    const item: LocationDirectoryItem = {
      id: '1',
      name: 'No GPS',
      employeeCode: 'EMP-2',
      jobTitle: null,
      department: null,
      lastLatitude: null,
      lastLongitude: null,
      lastAccuracy: null,
      lastRecordedAt: null,
      activeRequestId: '123',
      activeRequestStatus: 'pending',
    };
    expect(item.lastLatitude).toBeNull();
    expect(item.activeRequestStatus).toBe('pending');
  });

  it('OperationsCenterData has employees, tasks, missions, convoys', () => {
    const data: OperationsCenterData = {
      employees: [{ id: '1', name: 'Test' }],
      tasks: [],
      missions: [],
      convoys: [],
    };
    expect(data.employees).toHaveLength(1);
    expect(Array.isArray(data.tasks)).toBe(true);
    expect(Array.isArray(data.missions)).toBe(true);
    expect(Array.isArray(data.convoys)).toBe(true);
  });

  it('AuditSecurityData has three event arrays', () => {
    const data: AuditSecurityData = {
      securityEvents: [],
      auditEvents: [],
      devices: [],
    };
    expect(Array.isArray(data.securityEvents)).toBe(true);
    expect(Array.isArray(data.auditEvents)).toBe(true);
    expect(Array.isArray(data.devices)).toBe(true);
  });

  it('IntegrationCenterData has four arrays', () => {
    const data: IntegrationCenterData = {
      integrations: [],
      logs: [],
      outbox: [],
      automationRuns: [],
    };
    expect(Array.isArray(data.integrations)).toBe(true);
    expect(Array.isArray(data.logs)).toBe(true);
    expect(Array.isArray(data.outbox)).toBe(true);
    expect(Array.isArray(data.automationRuns)).toBe(true);
  });

  it('OperationsCenterData task has all required fields', () => {
    const data: OperationsCenterData = {
      employees: [],
      tasks: [
        {
          id: 't1',
          title: 'مهمة تجريبية',
          description: 'وصف المهمة',
          assigneeId: 'emp1',
          assigneeName: 'أحمد',
          priority: 'urgent',
          dueDate: '2026-08-01',
          status: 'in_progress',
        },
      ],
      missions: [
        {
          id: 'm1',
          employeeName: 'سارة',
          destination: 'فرع الجيزة',
          purpose: 'متابعة',
          startAt: '2026-08-01T08:00:00Z',
          endAt: '2026-08-01T16:00:00Z',
          status: 'approved',
          transportMode: 'company_vehicle',
        },
      ],
      convoys: [
        {
          id: 'c1',
          employeeName: 'محمود',
          name: 'قافلة خدمة',
          origin: 'المقر',
          destination: 'فرع أكتوبر',
          departureAt: '2026-08-01T06:00:00Z',
          returnAt: '2026-08-01T18:00:00Z',
          passengers: 10,
          vehicles: 2,
          status: 'approved',
        },
      ],
    };
    expect(data.tasks[0].priority).toBe('urgent');
    expect(data.missions[0].transportMode).toBe('company_vehicle');
    expect(data.convoys[0].passengers).toBe(10);
  });
});
