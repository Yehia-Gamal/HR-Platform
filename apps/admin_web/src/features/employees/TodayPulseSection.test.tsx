import { describe, expect, it } from 'vitest';
import type { EmployeeOverviewRow } from '../management/controlCenterTypes';
import {
  absentEmployees,
  lateEmployees,
  locationRequestEmployees,
  presentEmployees,
  presentPercent,
  totalLateMinutes,
} from './TodayPulseSection';

function makeEmployee(overrides: Partial<EmployeeOverviewRow>): EmployeeOverviewRow {
  return {
    id: '00000000-0000-4000-8000-000000000000',
    name: 'موظف اختبار',
    employeeCode: 'EMP-000',
    department: null,
    jobTitle: null,
    status: 'present',
    managerName: null,
    activeRequestStatus: null,
    activeRequestId: null,
    lateMinutes: null,
    lastLatitude: null,
    lastLongitude: null,
    lastAccuracy: null,
    lastAddressAr: null,
    lastLocationAt: null,
    checkInAt: null,
    checkOutAt: null,
    ...overrides,
  };
}

const employees: EmployeeOverviewRow[] = [
  makeEmployee({ id: '1-present', status: 'present', checkInAt: '2026-08-05T06:30:00Z' }),
  makeEmployee({ id: '2-late', status: 'late', lateMinutes: 25 }),
  makeEmployee({ id: '3-left-early', status: 'left_early', lateMinutes: 0 }),
  makeEmployee({ id: '4-checked-out', status: 'checked_out' }),
  makeEmployee({ id: '5-absent', status: 'absent' }),
  makeEmployee({ id: '6-leave', status: 'on_leave' }),
  makeEmployee({ id: '7-mission', status: 'assignment' }),
  makeEmployee({ id: '8-not-yet', status: 'not_yet' }),
  makeEmployee({ id: '9-with-request', status: 'present', activeRequestId: 'req-1', activeRequestStatus: 'pending' }),
  makeEmployee({ id: '10-responded', status: 'checked_out', activeRequestId: 'req-2', activeRequestStatus: 'completed' }),
];

describe('TodayPulseSection classification', () => {
  it('present = حاضر + متأخر + انصرف + انصرف مبكرًا', () => {
    const ids = presentEmployees(employees).map((e) => e.id);
    expect(ids).toContain('1-present');
    expect(ids).toContain('2-late');
    expect(ids).toContain('3-left-early');
    expect(ids).toContain('4-checked-out');
    expect(ids).not.toContain('5-absent');
    expect(ids).not.toContain('6-leave');
    expect(ids).not.toContain('7-mission');
    expect(ids).not.toContain('8-not-yet');
  });

  it('absent = غائب فقط — الإجازة والمأمورية لا تُحسب غيابًا', () => {
    const ids = absentEmployees(employees).map((e) => e.id);
    expect(ids).toEqual(['5-absent']);
  });

  it('late = متأخر + انصرف مبكرًا', () => {
    const ids = lateEmployees(employees).map((e) => e.id);
    expect(ids).toContain('2-late');
    expect(ids).toContain('3-left-early');
    expect(ids).not.toContain('1-present');
  });

  it('location requests = من لديهم طلب نشط فقط', () => {
    const ids = locationRequestEmployees(employees).map((e) => e.id);
    expect(ids).toEqual(['9-with-request', '10-responded']);
  });

  it('totalLateMinutes يجمع دقائق التأخير ويتجاهل القيم السالبة/المفقودة', () => {
    expect(totalLateMinutes(employees)).toBe(25);
    expect(
      totalLateMinutes([
        makeEmployee({ id: 'a', status: 'late', lateMinutes: 10 }),
        makeEmployee({ id: 'b', status: 'late', lateMinutes: null }),
        makeEmployee({ id: 'c', status: 'left_early', lateMinutes: 5 }),
      ]),
    ).toBe(15);
  });

  it('presentPercent = نسبة من حضروا إلى الإجمالي، و0 للقائمة الفارغة', () => {
    // 6 من 10 حضروا (present, late, left_early, checked_out, with-request, responded)
    expect(presentPercent(employees)).toBe(60);
    expect(presentPercent([])).toBe(0);
  });
});
