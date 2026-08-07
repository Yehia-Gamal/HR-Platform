import { z } from 'zod';

// عقد بيانات شجرة الهيكل التنظيمي الإداري (مدير → مرؤوسون).
// تطابق مُخرجات RPC ‹get_admin_org_chart› في migration 0313.

export const orgChartEmployeeSchema = z.object({
  id: z.string().uuid(),
  fullNameAr: z.string(),
  fullNameEn: z.string().nullable(),
  photoUrl: z.string().nullable(),
  jobTitle: z.string(),
  departmentName: z.string(),
  employeeCode: z.string(),
  departmentId: z.string().uuid().nullable(),
  status: z.string(),
  managerEmployeeId: z.string().uuid().nullable(),
  directReportsCount: z.number().int().nonnegative(),
  depth: z.number().int().nonnegative(),
  path: z.array(z.string().uuid()),
});

export type OrgChartEmployee = z.infer<typeof orgChartEmployeeSchema>;

export const orgChartResponseSchema = z.object({
  employees: z.array(orgChartEmployeeSchema),
});

export type OrgChartResponse = z.infer<typeof orgChartResponseSchema>;

// عقدة شجرة هرمية (موظف + أبناؤه المباشرون)
export interface OrgChartTreeNode {
  employee: OrgChartEmployee;
  children: OrgChartTreeNode[];
}
