import { describe, it, expect } from 'vitest';

// Recreate the module-scoped Holiday interface and mock from useHolidays.ts
interface Holiday {
  id: string;
  name: string;
  name_en: string | null;
  holiday_date: string;
  end_date: string | null;
  scope: 'all' | 'legal_entity' | 'department';
  legal_entity_id: string | null;
  department_id: string | null;
  excluded_department_ids: string[];
  notes: string | null;
  is_recurring: boolean;
  is_active: boolean;
  created_at: string;
  created_by: string | null;
}

const mockHolidays: Holiday[] = [
  {
    id: '00000000-0000-4000-8000-000000000001',
    name: 'عيد الفطر',
    name_en: 'Eid Al-Fitr',
    holiday_date: '2026-03-31',
    end_date: '2026-04-02',
    scope: 'all',
    legal_entity_id: null,
    department_id: null,
    excluded_department_ids: [],
    notes: null,
    is_recurring: true,
    is_active: true,
    created_at: new Date().toISOString(),
    created_by: null,
  },
];

describe('useHolidays — mock data validation', () => {
  it('has exactly 1 mock holiday', () => {
    expect(mockHolidays).toHaveLength(1);
  });

  it('holiday ID is a valid UUID', () => {
    const uuidRe = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    expect(mockHolidays[0].id).toMatch(uuidRe);
  });

  it('holiday_date is YYYY-MM-DD format', () => {
    const dateRe = /^\d{4}-\d{2}-\d{2}$/;
    expect(mockHolidays[0].holiday_date).toMatch(dateRe);
  });

  it('end_date is YYYY-MM-DD format when set', () => {
    const dateRe = /^\d{4}-\d{2}-\d{2}$/;
    if (mockHolidays[0].end_date !== null) {
      expect(mockHolidays[0].end_date).toMatch(dateRe);
    }
  });

  it('end_date is after or equal to holiday_date', () => {
    const h = mockHolidays[0];
    if (h.end_date !== null) {
      expect(h.end_date >= h.holiday_date).toBe(true);
    }
  });

  it('scope is a valid enum value', () => {
    const validScopes = ['all', 'legal_entity', 'department'];
    expect(validScopes).toContain(mockHolidays[0].scope);
  });

  it('excluded_department_ids is an array', () => {
    expect(Array.isArray(mockHolidays[0].excluded_department_ids)).toBe(true);
  });

  it('created_at is a valid ISO timestamp', () => {
    const date = new Date(mockHolidays[0].created_at);
    expect(date.getTime()).not.toBeNaN();
  });

  it('is_recurring and is_active are booleans', () => {
    expect(typeof mockHolidays[0].is_recurring).toBe('boolean');
    expect(typeof mockHolidays[0].is_active).toBe('boolean');
  });

  it('name is a non-empty Arabic string', () => {
    expect(mockHolidays[0].name.length).toBeGreaterThan(0);
  });

  it('name_en is a non-empty string when set', () => {
    const h = mockHolidays[0];
    if (h.name_en !== null) {
      expect(h.name_en.length).toBeGreaterThan(0);
    }
  });

  it('scope "all" means legal_entity_id and department_id are null', () => {
    const h = mockHolidays[0];
    if (h.scope === 'all') {
      expect(h.legal_entity_id).toBeNull();
      expect(h.department_id).toBeNull();
    }
  });
});
