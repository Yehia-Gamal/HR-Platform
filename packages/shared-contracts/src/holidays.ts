import { z } from 'zod';

// عقود العطل الرسمية — V17 §1.7.
// العطلة لها نطاق (الكل / جهة / إدارة) واستثناءات.

// ─── نطاق العطلة ─────────────────────────────────────────────────────────────

export const holidayScopeSchema = z.enum([
  'all',
  'legal_entity',
  'department',
]);
export type HolidayScope = z.infer<typeof holidayScopeSchema>;

// ─── مخطط العطلة الرسمية ─────────────────────────────────────────────────────

export const officialHolidaySchema = z.object({
  id: z.string().uuid(),
  /** اسم العطلة بالعربية */
  name: z.string().min(3).max(200),
  /** تاريخ العطلة (YYYY-MM-DD) */
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  /** تاريخ نهاية العطلة (للعطل متعددة الأيام) */
  endDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable(),
  /** نطاق العطلة */
  scope: holidayScopeSchema,
  /** معرّف الجهة (إذا كان النطاق legal_entity) */
  legalEntityId: z.string().uuid().nullable(),
  /** معرّف الإدارة (إذا كان النطاق department) */
  departmentId: z.string().uuid().nullable(),
  /** إدارات مستثناة من العطلة */
  excludedDepartmentIds: z.array(z.string().uuid()).default([]),
  /** ملاحظات */
  notes: z.string().max(500).nullable(),
  /** منشئ العطلة */
  createdBy: z.string().uuid(),
  createdAt: z.string().datetime(),
});
export type OfficialHoliday = z.infer<typeof officialHolidaySchema>;

// ─── مدخلات إنشاء عطلة ───────────────────────────────────────────────────────

export const createHolidayInputSchema = z
  .object({
    name: z.string().min(3).max(200),
    date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
    endDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
    scope: holidayScopeSchema.default('all'),
    legalEntityId: z.string().uuid().optional(),
    departmentId: z.string().uuid().optional(),
    excludedDepartmentIds: z.array(z.string().uuid()).default([]),
    notes: z.string().max(500).optional(),
  })
  .refine(
    (data) => {
      if (data.scope === 'legal_entity' && !data.legalEntityId) return false;
      if (data.scope === 'department' && !data.departmentId) return false;
      return true;
    },
    { message: 'يجب تحديد الجهة أو الإدارة حسب النطاق المختار' }
  );
export type CreateHolidayInput = z.infer<typeof createHolidayInputSchema>;

// ─── مدخلات تعديل عطلة ───────────────────────────────────────────────────────

export const updateHolidayInputSchema = z.object({
  holidayId: z.string().uuid(),
  name: z.string().min(3).max(200).optional(),
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  endDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable().optional(),
  scope: holidayScopeSchema.optional(),
  legalEntityId: z.string().uuid().nullable().optional(),
  departmentId: z.string().uuid().nullable().optional(),
  excludedDepartmentIds: z.array(z.string().uuid()).optional(),
  notes: z.string().max(500).nullable().optional(),
});
export type UpdateHolidayInput = z.infer<typeof updateHolidayInputSchema>;
