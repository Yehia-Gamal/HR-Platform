import { describe, expect, it } from 'vitest';
import {
  holidayScopeSchema,
  officialHolidaySchema,
  createHolidayInputSchema,
  updateHolidayInputSchema,
} from './holidays.js';

const uuid = '11111111-1111-4111-8111-111111111111';
const uuid2 = '22222222-2222-4222-8222-222222222222';
const now = '2026-07-25T10:00:00.000Z';

describe('official holiday contracts — V17 §1.7', () => {
  it('scope enum covers all, legal_entity, department', () => {
    expect(holidayScopeSchema.options).toEqual(['all', 'legal_entity', 'department']);
    expect(() => holidayScopeSchema.parse('branch')).toThrow();
  });

  it('official holiday round-trips a full record', () => {
    const holiday = officialHolidaySchema.parse({
      id: uuid,
      name: 'عيد الفطر المبارك',
      date: '2026-03-30',
      endDate: '2026-04-02',
      scope: 'all',
      legalEntityId: null,
      departmentId: null,
      excludedDepartmentIds: [uuid2],
      notes: 'عطلة رسمية لجميع الموظفين',
      createdBy: uuid,
      createdAt: now,
    });
    expect(holiday.name).toBe('عيد الفطر المبارك');
    expect(holiday.scope).toBe('all');
    expect(holiday.excludedDepartmentIds).toHaveLength(1);
  });

  it('create input enforces name 3–200 chars and date format', () => {
    const valid = createHolidayInputSchema.parse({
      name: 'اليوم الوطني',
      date: '2026-09-23',
    });
    expect(valid.scope).toBe('all');
    expect(valid.excludedDepartmentIds).toEqual([]);

    expect(() => createHolidayInputSchema.parse({ name: 'ab', date: '2026-09-23' })).toThrow();
    expect(() => createHolidayInputSchema.parse({ name: 'عطلة', date: '2026/09/23' })).toThrow();
  });

  it('scoped holiday requires entity/department id', () => {
    const deptHoliday = createHolidayInputSchema.parse({
      name: 'عطلة إدارية',
      date: '2026-12-01',
      scope: 'department',
      departmentId: uuid,
    });
    expect(deptHoliday.scope).toBe('department');
    expect(deptHoliday.departmentId).toBe(uuid);
  });

  it('update input allows partial fields', () => {
    const update = updateHolidayInputSchema.parse({
      holidayId: uuid,
      name: 'عيد الأضحى المبارك',
    });
    expect(update.name).toBe('عيد الأضحى المبارك');
    expect(update.date).toBeUndefined();
  });

  it('date format rejects non-ISO dates', () => {
    expect(() => createHolidayInputSchema.parse({ name: 'عطلة', date: '30-03-2026' })).toThrow();
    expect(() => createHolidayInputSchema.parse({ name: 'عطلة', date: '2026-3-30' })).toThrow();
  });
});
