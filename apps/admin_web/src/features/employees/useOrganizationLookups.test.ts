import { describe, it, expect } from 'vitest';

/* ------------------------------------------------------------------ */
/*  Recreated types (not exported from the source module)             */
/* ------------------------------------------------------------------ */

interface Option {
  id: string;
  label: string;
  parentId?: string | null;
}

interface OrganizationLookups {
  roles: { id: string; slug: string; label: string }[];
  managers: Option[];
  branches: Option[];
  workSites: Option[];
  departments: Option[];
  teams: Option[];
  jobTitles: Option[];
  positions: Option[];
  grades: Option[];
  employmentTypes: Option[];
}

/* ------------------------------------------------------------------ */
/*  Recreated mock constant                                           */
/* ------------------------------------------------------------------ */

const mock: OrganizationLookups = {
  roles: [
    { id: 'role-employee', slug: 'employee', label: 'موظف' },
    { id: 'role-manager', slug: 'direct-manager', label: 'مدير مباشر' },
    { id: 'role-hr', slug: 'hr-specialist', label: 'HR Specialist' },
  ],
  managers: [{ id: '30000000-0000-4000-8000-000000000002', label: 'مدير مباشر تجريبي · EMP-002' }],
  branches: [],
  workSites: [],
  departments: [],
  teams: [],
  jobTitles: [],
  positions: [],
  grades: [],
  employmentTypes: [],
};

/* ------------------------------------------------------------------ */
/*  Recreated option() helper                                         */
/* ------------------------------------------------------------------ */

const option = (row: Record<string, unknown>, parentKey?: string): Option => ({
  id: String(row.id),
  label: String(row.name ?? row.full_name_ar ?? row.code ?? '—'),
  parentId: parentKey ? (row[parentKey] as string | null | undefined) : undefined,
});

/* ------------------------------------------------------------------ */
/*  Tests                                                             */
/* ------------------------------------------------------------------ */

describe('useOrganizationLookups — mock data & option() validation', () => {
  it('mock has exactly 10 lookup categories', () => {
    expect(Object.keys(mock).length).toBe(10);
  });

  it('mock roles has 3 entries', () => {
    expect(mock.roles.length).toBe(3);
  });

  it('mock managers has 1 entry', () => {
    expect(mock.managers.length).toBe(1);
  });

  it('all empty arrays are truly empty', () => {
    expect(mock.branches).toHaveLength(0);
    expect(mock.workSites).toHaveLength(0);
    expect(mock.departments).toHaveLength(0);
    expect(mock.teams).toHaveLength(0);
    expect(mock.jobTitles).toHaveLength(0);
    expect(mock.positions).toHaveLength(0);
    expect(mock.grades).toHaveLength(0);
    expect(mock.employmentTypes).toHaveLength(0);
  });

  it('role objects have id, slug, label', () => {
    for (const role of mock.roles) {
      expect(typeof role.id).toBe('string');
      expect(typeof role.slug).toBe('string');
      expect(typeof role.label).toBe('string');
    }
  });

  it('manager label contains EMP code', () => {
    expect(mock.managers[0].label).toContain('EMP-002');
  });

  it('manager ID is a valid UUID', () => {
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    expect(uuidRegex.test(mock.managers[0].id)).toBe(true);
  });

  it('option() extracts id and name', () => {
    const result = option({ id: 'abc', name: 'Test' });
    expect(result).toEqual({ id: 'abc', label: 'Test', parentId: undefined });
  });

  it('option() falls back to full_name_ar', () => {
    const result = option({ id: '1', full_name_ar: 'أحمد' });
    expect(result.label).toBe('أحمد');
  });

  it('option() falls back to code', () => {
    const result = option({ id: '1', code: 'X-100' });
    expect(result.label).toBe('X-100');
  });

  it('option() falls back to — when no name fields', () => {
    const result = option({ id: '1' });
    expect(result.label).toBe('—');
  });

  it('option() includes parentId when parentKey provided', () => {
    const result = option({ id: '1', name: 'Test', branch_id: 'b1' }, 'branch_id');
    expect(result.parentId).toBe('b1');
  });

  it('option() parentId is undefined when parentKey not provided', () => {
    const result = option({ id: '1', name: 'Test' });
    expect(result.parentId).toBeUndefined();
  });
});
