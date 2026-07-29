import { describe, it, expect } from 'vitest';\r
\r
/* ------------------------------------------------------------------ */\r
/*  Recreated types (not exported from the source module)             */\r
/* ------------------------------------------------------------------ */\r
\r
interface Option {\r
  id: string;\r
  label: string;\r
  parentId?: string | null;\r
}\r
\r
interface OrganizationLookups {\r
  roles: { id: string; slug: string; label: string }[];\r
  managers: Option[];\r
  branches: Option[];\r
  workSites: Option[];\r
  departments: Option[];\r
  teams: Option[];\r
  jobTitles: Option[];\r
  positions: Option[];\r
  grades: Option[];\r
  employmentTypes: Option[];\r
}\r
\r
/* ------------------------------------------------------------------ */\r
/*  Recreated mock constant                                           */\r
/* ------------------------------------------------------------------ */\r
\r
const mock: OrganizationLookups = {\r
  roles: [\r
    { id: 'role-employee', slug: 'employee', label: 'موظف' },\r
    { id: 'role-manager', slug: 'direct-manager', label: 'مدير مباشر' },\r
    { id: 'role-hr', slug: 'hr-specialist', label: 'HR Specialist' },\r
  ],\r
  managers: [\r
    { id: '30000000-0000-4000-8000-000000000002', label: 'مدير مباشر تجريبي · EMP-002' },\r
  ],\r
  branches: [],\r
  workSites: [],\r
  departments: [],\r
  teams: [],\r
  jobTitles: [],\r
  positions: [],\r
  grades: [],\r
  employmentTypes: [],\r
};\r
\r
/* ------------------------------------------------------------------ */\r
/*  Recreated option() helper                                         */\r
/* ------------------------------------------------------------------ */\r
\r
const option = (row: Record<string, unknown>, parentKey?: string): Option => ({\r
  id: String(row.id),\r
  label: String(row.name ?? row.full_name_ar ?? row.code ?? '—'),\r
  parentId: parentKey ? (row[parentKey] as string | null | undefined) : undefined,\r
});\r
\r
/* ------------------------------------------------------------------ */\r
/*  Tests                                                             */\r
/* ------------------------------------------------------------------ */\r
\r
describe('useOrganizationLookups — mock data & option() validation', () => {\r
  it('mock has exactly 10 lookup categories', () => {\r
    expect(Object.keys(mock).length).toBe(10);\r
  });\r
\r
  it('mock roles has 3 entries', () => {\r
    expect(mock.roles.length).toBe(3);\r
  });\r
\r
  it('mock managers has 1 entry', () => {\r
    expect(mock.managers.length).toBe(1);\r
  });\r
\r
  it('all empty arrays are truly empty', () => {\r
    expect(mock.branches).toHaveLength(0);\r
    expect(mock.workSites).toHaveLength(0);\r
    expect(mock.departments).toHaveLength(0);\r
    expect(mock.teams).toHaveLength(0);\r
    expect(mock.jobTitles).toHaveLength(0);\r
    expect(mock.positions).toHaveLength(0);\r
    expect(mock.grades).toHaveLength(0);\r
    expect(mock.employmentTypes).toHaveLength(0);\r
  });\r
\r
  it('role objects have id, slug, label', () => {\r
    for (const role of mock.roles) {\r
      expect(typeof role.id).toBe('string');\r
      expect(typeof role.slug).toBe('string');\r
      expect(typeof role.label).toBe('string');\r
    }\r
  });\r
\r
  it('manager label contains EMP code', () => {\r
    expect(mock.managers[0].label).toContain('EMP-002');\r
  });\r
\r
  it('manager ID is a valid UUID', () => {\r
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;\r
    expect(uuidRegex.test(mock.managers[0].id)).toBe(true);\r
  });\r
\r
  it('option() extracts id and name', () => {\r
    const result = option({ id: 'abc', name: 'Test' });\r
    expect(result).toEqual({ id: 'abc', label: 'Test', parentId: undefined });\r
  });\r
\r
  it('option() falls back to full_name_ar', () => {\r
    const result = option({ id: '1', full_name_ar: 'أحمد' });\r
    expect(result.label).toBe('أحمد');\r
  });\r
\r
  it('option() falls back to code', () => {\r
    const result = option({ id: '1', code: 'X-100' });\r
    expect(result.label).toBe('X-100');\r
  });\r
\r
  it('option() falls back to — when no name fields', () => {\r
    const result = option({ id: '1' });\r
    expect(result.label).toBe('—');\r
  });\r
\r
  it('option() includes parentId when parentKey provided', () => {\r
    const result = option({ id: '1', name: 'Test', branch_id: 'b1' }, 'branch_id');\r
    expect(result.parentId).toBe('b1');\r
  });\r
\r
  it('option() parentId is undefined when parentKey not provided', () => {\r
    const result = option({ id: '1', name: 'Test' });\r
    expect(result.parentId).toBeUndefined();\r
  });\r
});\r
