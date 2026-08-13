import { describe, expect, it } from 'vitest';
import {
  assetItemSchema,
  clearanceItemSchema,
  documentItemSchema,
  documentsCatalogSchema,
  offboardingCaseSchema,
} from './documents.js';

const UUID = '11111111-1111-4111-8111-111111111111';
const UUID2 = '22222222-2222-4222-8222-222222222222';

describe('documents contracts', () => {
  it('يقبل عنصر مستند صالحاً', () => {
    const doc = documentItemSchema.parse({
      id: UUID,
      employeeId: UUID2,
      employeeName: 'أحمد',
      employeeCode: 'EMP-1',
      type: 'passport',
      title: 'جواز السفر',
      number: 'A123',
      issueDate: '2020-01-01',
      expiryDate: '2030-01-01',
      status: 'valid',
      verified: true,
      storagePath: '/docs/p.pdf',
      createdAt: '2026-01-01T00:00:00Z',
    });
    expect(doc.verified).toBe(true);
  });

  it('يقبل أصل مع تخصيص متداخل', () => {
    const asset = assetItemSchema.parse({
      id: UUID,
      assetCode: 'AST-1',
      type: 'laptop',
      name: 'Dell Latitude',
      serial: 'SN1',
      status: 'assigned',
      condition: 'good',
      location: 'HR',
      assignment: {
        id: UUID2,
        employeeId: UUID,
        employeeName: 'أحمد',
        status: 'handed_over',
        handedOverAt: '2026-01-01',
        returnedAt: null,
      },
    });
    expect(asset.assignment?.status).toBe('handed_over');
  });

  it('يقبل أصل بتخصيص null', () => {
    const asset = assetItemSchema.parse({
      id: UUID,
      assetCode: null,
      type: 'laptop',
      name: 'X',
      serial: null,
      status: null,
      condition: null,
      location: null,
      assignment: null,
    });
    expect(asset.assignment).toBeNull();
  });

  it('يقبل بند مخلّص وبقضية offboarding مع clearance', () => {
    const clearance = clearanceItemSchema.parse({
      id: UUID,
      category: 'assets',
      title: 'تسليم الأصول',
      status: 'pending',
      assigneeId: UUID2,
      dueAt: '2026-02-01',
      completionNote: null,
    });
    const offboarding = offboardingCaseSchema.parse({
      id: UUID,
      caseNumber: 'OFF-1',
      employeeId: UUID2,
      employeeName: 'أحمد',
      employeeCode: 'EMP-1',
      reasonType: 'resignation',
      lastWorkingDate: '2026-02-28',
      status: 'open',
      handoverEmployeeId: UUID,
      clearance: [clearance],
    });
    expect(offboarding.clearance).toHaveLength(1);
  });

  it('يقبل كتالوج المستندات الكامل', () => {
    const catalog = documentsCatalogSchema.parse({
      documents: [],
      assets: [],
      offboarding: [],
      expiringDocuments: 0,
      assignedAssets: 0,
      openOffboarding: 0,
      lastUpdatedAt: '2026-01-01T00:00:00Z',
    });
    expect(catalog.expiringDocuments).toBe(0);
  });

  it('يرفض معرّف غير UUID في عنصر المستند', () => {
    const base = {
      id: UUID,
      employeeId: UUID2,
      employeeName: 'x',
      employeeCode: null,
      type: 't',
      title: 't',
      number: null,
      issueDate: null,
      expiryDate: null,
      status: 'ok',
      verified: false,
      storagePath: null,
      createdAt: null,
    };
    expect(() => documentItemSchema.parse({ ...base, id: 'bad' })).toThrow();
    expect(() => documentItemSchema.parse({ ...base, employeeId: 'bad' })).toThrow();
  });
});
