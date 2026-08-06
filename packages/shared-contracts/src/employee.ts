import { z } from 'zod';

export const employeeStatusSchema = z.enum([
  'draft',
  'invited',
  'onboarding',
  'active',
  'suspended',
  'notice_period',
  'terminated',
  'archived',
  'probation_failed',
]);

const optionalUuid = z.string().uuid().nullable().optional();

export const employeeSummarySchema = z.object({
  id: z.string().uuid(),
  employeeCode: z.string(),
  fullNameAr: z.string(),
  fullNameEn: z.string().nullable(),
  phoneE164: z.string().nullable(),
  status: employeeStatusSchema,
  isActive: z.boolean(),
  photoUrl: z.string().nullable(),
  departmentId: z.string().uuid().nullable(),
  teamId: z.string().uuid().nullable(),
  branchId: z.string().uuid().nullable(),
  // أسماء مُثراة من get_employees_enriched (اختياري للتوافق مع الاستعلام القديم)
  department: z.string().nullable().optional(),
  team: z.string().nullable().optional(),
  branch: z.string().nullable().optional(),
  jobTitle: z.string().nullable().optional(),
  createdAt: z.string(),
});

export type EmployeeSummary = z.infer<typeof employeeSummarySchema>;

export const createEmployeeInputSchema = z.object({
  fullNameAr: z.string().trim().min(3).max(160),
  fullNameEn: z.string().trim().max(160).optional(),
  employeeCode: z.string().trim().min(2).max(50).optional(),
  email: z.string().email(),
  // رقم هاتف مصري محلي بصيغة عادية مثل 01154869616 (11 رقماً يبدأ بـ 01)،
  // أو صيغة دولية E.164 (‎+20…) للتوافق مع البيانات القديمة.
  phoneE164: z
    .string()
    .trim()
    // إزالة أي أحرف غير مرئية (RTL/LTR marks, zero-width spaces) قبل التحقق
    .transform((v) => v.replace(/[^\d+]/g, ''))
    .pipe(z.string().regex(/^(01\d{9}|\+[1-9]\d{7,14})$/, 'رقم هاتف غير صالح')),
  roleSlug: z.string().trim().min(2),
  jobTitleName: z.string().trim().max(160).optional(),
  // كلمة المرور الأولية (اختيارية): إن أدخلها مسؤول HR تُفحص قوّتها فورياً،
  // وإن تُركت فارغة تولّد Edge Function كلمة مرور مؤقتة آمنة تلقائياً وتعيدها
  // في الاستجابة لعرضها مرة واحدة. لا تُشتق من الهاتف/الكود/الاسم أبداً.
  initialPassword: z.string().trim().min(8, 'كلمة المرور يجب ألا تقل عن 8 أحرف').max(15, 'كلمة المرور يجب ألا تزيد عن 15 حرفًا').optional(),
  photoUrl: z.string().url().max(1000).optional(),
  managerEmployeeId: optionalUuid,
  departmentId: optionalUuid,
  teamId: optionalUuid,
  branchId: optionalUuid,
  workSiteId: optionalUuid,
  jobTitleId: optionalUuid,
  positionId: optionalUuid,
  gradeId: optionalUuid,
  employmentTypeId: optionalUuid,
  hireDate: z.preprocess((v) => (v === '' ? undefined : v), z.string().date().optional()),
  sendInvite: z.boolean().default(false),
}).superRefine((data, ctx) => {
  // مرآة قواعد validateHrIssuedPassword (edge function) — تعليق فوري في المتصفح
  // بدل 400 عام من الخادم. الحقل اختياري: عند فراغه تولّد الخادم كلمة مؤقتة.
  const pwd = data.initialPassword;
  const path = ['initialPassword'];

  const fail = (message: string) => ctx.addIssue({ code: 'custom', message, path });

  if (!pwd) return;

  if (!/[A-Z]/.test(pwd)) return fail('كلمة المرور تحتاج حرفًا كبيرًا واحدًا على الأقل.');
  if (!/[a-z]/.test(pwd)) return fail('كلمة المرور تحتاج حرفًا صغيرًا واحدًا على الأقل.');
  if (!/\d/.test(pwd)) return fail('كلمة المرور تحتاج رقمًا واحدًا على الأقل.');
  if (/(.)\1{3,}/.test(pwd)) return fail('كلمة المرور ضعيفة (تكرار مفرط للأحرف).');

  const sequences = [
    'qwertyuiop', 'asdfghjkl', 'zxcvbnm',
    'abcdefghijklmnopqrstuvwxyz',
    '0123456789', '١٢٣٤٥٦٧٨٩٠',
  ];
  const lower = pwd.toLowerCase();
  for (const seq of sequences) {
    const chunks: string[] = [];
    const s = seq.toLowerCase();
    const r = [...s].reverse().join('');
    for (let i = 0; i + 4 <= s.length; i++) {
      chunks.push(s.slice(i, i + 4), r.slice(i, i + 4));
    }
    if (chunks.some((c) => lower.includes(c))) {
      return fail('كلمة المرور تحتوي تسلسلًا لوحة مفاتيح مألوفًا.');
    }
  }

  const commonWords = [
    'password', 'admin', 'user', 'login', 'welcome', 'letmein', 'iloveyou',
    'احبتك', 'مرحبا', 'كلمهالسر', 'كلمةالسر', 'كلمةالمرور', 'باسورد', 'سكرت',
    'الله', 'محمد', 'احمد', 'قاهرة', 'مصر', 'السعودية',
  ];
  if (commonWords.some((w) => lower.includes(w.toLowerCase()))) {
    return fail('كلمة المرور تحتوي كلمة شائعة.');
  }

  // منع تضمين معرّفات الموظف داخل كلمة المرور (سلاسل ≥ 4 أحرف).
  const identifiers = [data.email, data.phoneE164, data.employeeCode, data.fullNameAr];
  const parts = new Set<string>();
  for (const v of identifiers) {
    if (!v) continue;
    const s = String(v).toLowerCase();
    if (s.length >= 4) parts.add(s);
    const local = s.split('@')[0];
    if (local && local.length >= 4) parts.add(local);
    for (const token of s.split(/[\s\u0600-\u06FF]+/)) {
      if (token.length >= 4) parts.add(token);
    }
    if (s.startsWith('+2')) parts.add(s.slice(2));
    else if (s.startsWith('+')) parts.add(s.slice(1));
  }
  if ([...parts].some((p) => p.length >= 4 && lower.includes(p))) {
    return fail('كلمة المرور لا يجوز أن تحتوي البريد أو الهاتف أو الكود أو الاسم.');
  }
});

export type CreateEmployeeInput = z.infer<typeof createEmployeeInputSchema>;

export const createEmployeeResultSchema = z.object({
  employeeId: z.string().uuid(),
  userId: z.string().uuid(),
  invitationSent: z.boolean(),
  // كلمة مرور مؤقتة مولّدة تلقائياً (عند ترك حقل كلمة المرور فارغاً) — تُعرض
  // مرة واحدة فقط على شاشة الإنشاء ولا تُعاد ثانية.
  temporaryPassword: z.string().min(8).max(15).optional(),
});

export type CreateEmployeeResult = z.infer<typeof createEmployeeResultSchema>;

export const employee360Schema = z.object({
  id: z.string().uuid(),
  employeeCode: z.string(),
  fullNameAr: z.string(),
  fullNameEn: z.string().nullable(),
  phoneE164: z.string().nullable(),
  photoUrl: z.string().nullable(),
  status: employeeStatusSchema,
  isActive: z.boolean(),
  hireDate: z.string().nullable(),
  contractEnd: z.string().nullable(),
  probationEnd: z.string().nullable(),
  jobTitle: z.string().nullable(),
  position: z.string().nullable(),
  grade: z.string().nullable(),
  department: z.string().nullable(),
  team: z.string().nullable(),
  branch: z.string().nullable(),
  workSite: z.string().nullable(),
  managerName: z.string().nullable(),
  accountStatus: z.string().nullable(),
  email: z.string().email().nullable().optional(),
  // معرّفات FK خام — للاستخدام في نموذج التعديل (0129)
  departmentId: z.string().uuid().nullable().optional(),
  teamId: z.string().uuid().nullable().optional(),
  branchId: z.string().uuid().nullable().optional(),
  workSiteId: z.string().uuid().nullable().optional(),
  jobTitleId: z.string().uuid().nullable().optional(),
  positionId: z.string().uuid().nullable().optional(),
  gradeId: z.string().uuid().nullable().optional(),
  employmentTypeId: z.string().uuid().nullable().optional(),
  managerId: z.string().uuid().nullable().optional(),
  // إدارات الموظف (V17 — multi-department)
  departments: z.array(z.object({
    id: z.string().uuid(),
    departmentId: z.string().uuid(),
    departmentName: z.string(),
    jobTitle: z.string().nullable(),
    isPrimary: z.boolean(),
    assignedAt: z.string(),
  })).optional().default([]),
  roles: z.array(z.object({ slug: z.string(), name: z.string() })),
  directReports: z.number(),
  attendance30: z.object({
    present: z.number(),
    lateDays: z.number(),
    absent: z.number(),
    workMinutes: z.number(),
  }),
  requestCounts: z.object({ pending: z.number(), approved: z.number(), rejected: z.number() }),
  latestKpi: z.object({
    id: z.string().uuid(),
    periodMonth: z.string(),
    currentStage: z.string(),
    finalScore: z.number().nullable(),
    finalRating: z.string().nullable(),
  }).nullable(),
  documents: z.array(z.object({
    id: z.string().uuid(), type: z.string(), title: z.string(), expiryDate: z.string().nullable(), status: z.string(),
  })),
  assets: z.array(z.object({
    id: z.string().uuid(), assetName: z.string(), assetType: z.string(), serial: z.string().nullable(), handedOverAt: z.string().nullable(), returnedAt: z.string().nullable(),
  })),
  recentRequests: z.array(z.object({
    id: z.string().uuid(), requestNumber: z.number(), requestType: z.string(), title: z.string().nullable(), status: z.string(), createdAt: z.string(),
  })),
  recentTasks: z.array(z.object({
    id: z.string().uuid(), title: z.string(), status: z.string(), priority: z.string(), dueDate: z.string().nullable(),
  })),
  lastUpdatedAt: z.string(),
});

export type Employee360 = z.infer<typeof employee360Schema>;
