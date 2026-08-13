import { describe, expect, it } from 'vitest';
import { orgChartEmployeeSchema, orgChartResponseSchema } from './orgChart.js';

const validEmployee = {
  id: '11111111-1111-4111-8111-111111111111',
  fullNameAr: 'أحمد محمود',
  fullNameEn: 'Ahmed Mahmoud',
  photoUrl: null,
  jobTitle: 'مدير',
  departmentName: 'الموارد البشرية',
  employeeCode: 'EMP-001',
  departmentId: '22222222-2222-4222-8222-222222222222',
  status: 'active',
  managerEmployeeId: null,
  directReportsCount: 5,
  depth: 0,
  path: [],
};

describe('orgChart contracts', () => {
  it('يقبل موظف شجرة صالحاً', () => {
    const emp = orgChartEmployeeSchema.parse(validEmployee);
    expect(emp.directReportsCount).toBe(5);
    expect(emp.path).toEqual([]);
  });

  it('يقبل استجابة شجرة كاملة', () => {
    const res = orgChartResponseSchema.parse({ employees: [validEmployee] });
    expect(res.employees).toHaveLength(1);
  });

  it('يرفض معرّف موظف غير UUID', () => {
    expect(() => orgChartEmployeeSchema.parse({ ...validEmployee, id: 'nope' })).toThrow();
  });

  it('يرفض عدد مرؤوسين سالباً', () => {
    expect(() => orgChartEmployeeSchema.parse({ ...validEmployee, directReportsCount: -1 })).toThrow();
  });

  it('يرفض عمقاً غير صحيح (كسري)', () => {
    expect(() => orgChartEmployeeSchema.parse({ ...validEmployee, depth: 1.5 })).toThrow();
  });

  it('يرفض path يحوي قيم غير UUID', () => {
    expect(() =>
      orgChartEmployeeSchema.parse({ ...validEmployee, path: ['not-a-uuid'] }),
    ).toThrow();
  });

  it('يقبل path صحيح من معرّفات UUID', () => {
    const emp = orgChartEmployeeSchema.parse({
      ...validEmployee,
      path: ['33333333-3333-4333-8333-333333333333'],
      managerEmployeeId: '33333333-3333-4333-8333-333333333333',
    });
    expect(emp.path).toHaveLength(1);
  });
});
