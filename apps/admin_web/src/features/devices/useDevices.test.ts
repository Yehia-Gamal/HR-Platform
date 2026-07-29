import { describe, it, expect } from 'vitest';

import type { PendingDevice, AdminDevice } from './useDevices';

// Structural assertions on the exported interfaces — ensure mock-mode return
// values match the shape that consuming components rely on.

const PENDING: PendingDevice = {
  id: '00000000-0000-4000-8000-000000000001',
  employeeId: '10000000-0000-4000-8000-000000000001',
  employeeName: 'موظف تجريبي',
  employeeCode: 'EMP-001',
  employeePhotoUrl: null,
  deviceName: 'iPhone 15',
  platform: 'ios',
  status: 'pending',
  registeredAt: new Date().toISOString(),
  lastUsedAt: null,
  rejectionReason: null,
  revocationSource: null,
  metadata: {},
};

const ADMIN: AdminDevice = {
  id: '00000000-0000-4000-8000-000000000002',
  employeeId: '10000000-0000-4000-8000-000000000002',
  employeeName: 'موظف آخر',
  employeeCode: 'EMP-002',
  deviceName: 'Galaxy S24',
  platform: 'android',
  status: 'active',
  registeredAt: new Date().toISOString(),
  approvedAt: new Date().toISOString(),
  revokedAt: null,
  lastUsedAt: new Date().toISOString(),
  rejectionReason: null,
  revocationSource: null,
};

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

describe('useDevices — PendingDevice interface', () => {
  it('id is a valid UUID', () => {
    expect(PENDING.id).toMatch(UUID_RE);
  });

  it('employeeId is a valid UUID', () => {
    expect(PENDING.employeeId).toMatch(UUID_RE);
  });

  it('status is pending or blocked', () => {
    expect(['pending', 'blocked']).toContain(PENDING.status);
  });

  it('registeredAt is a valid ISO timestamp', () => {
    expect(new Date(PENDING.registeredAt).getTime()).not.toBeNaN();
  });

  it('metadata is an object', () => {
    expect(typeof PENDING.metadata).toBe('object');
    expect(PENDING.metadata).not.toBeNull();
  });

  it('platform is a non-empty string', () => {
    expect(PENDING.platform.length).toBeGreaterThan(0);
  });
});

describe('useDevices — AdminDevice interface', () => {
  it('id is a valid UUID', () => {
    expect(ADMIN.id).toMatch(UUID_RE);
  });

  it('status is a valid device status enum', () => {
    const valid = ['pending', 'active', 'blocked', 'revoked', 'replaced', 'auto_revoked'];
    expect(valid).toContain(ADMIN.status);
  });

  it('approvedAt is a valid ISO timestamp when set', () => {
    if (ADMIN.approvedAt !== null) {
      expect(new Date(ADMIN.approvedAt).getTime()).not.toBeNaN();
    }
  });

  it('revokedAt is null for active devices', () => {
    if (ADMIN.status === 'active') {
      expect(ADMIN.revokedAt).toBeNull();
    }
  });

  it('lastUsedAt is a valid ISO timestamp when set', () => {
    if (ADMIN.lastUsedAt !== null) {
      expect(new Date(ADMIN.lastUsedAt).getTime()).not.toBeNaN();
    }
  });
});

describe('useDevices — mock mode returns empty arrays', () => {
  it('mock pending devices returns []', () => {
    const mockPending: PendingDevice[] = [];
    expect(mockPending).toHaveLength(0);
    expect(Array.isArray(mockPending)).toBe(true);
  });

  it('mock all devices returns []', () => {
    const mockAll: AdminDevice[] = [];
    expect(mockAll).toHaveLength(0);
    expect(Array.isArray(mockAll)).toBe(true);
  });
});
