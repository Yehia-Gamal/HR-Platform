import { z } from 'zod';

// عقود إعدادات الحضور — V17 §7.
// الوقت الافتراضي: 10:00–18:00، المنطقة الزمنية: Africa/Cairo.

// ─── فترات السماح ────────────────────────────────────────────────────────────

export const gracePeriodSchema = z.object({
  /** فترة السماح بالتأخير بعد وقت الحضور (بالدقائق) */
  lateGraceMinutes: z.number().int().min(0).max(60).default(15),
  /** فترة السماح بالانصراف المبكر قبل وقت الانصراف (بالدقائق) */
  earlyLeaveGraceMinutes: z.number().int().min(0).max(60).default(15),
});
export type GracePeriod = z.infer<typeof gracePeriodSchema>;

// ─── جدول التذكيرات ──────────────────────────────────────────────────────────

export const attendanceReminderSchema = z.object({
  /** وقت التذكير بصيغة HH:mm */
  time: z.string().regex(/^\d{2}:\d{2}$/),
  /** نوع التذكير */
  type: z.enum(['check_in_reminder', 'check_in_due', 'check_out_reminder', 'check_out_due']),
});
export type AttendanceReminder = z.infer<typeof attendanceReminderSchema>;

/** جدول التذكيرات الافتراضي — V17 §7. */
export const DEFAULT_ATTENDANCE_REMINDERS: readonly AttendanceReminder[] = [
  { time: '09:45', type: 'check_in_reminder' },
  { time: '10:00', type: 'check_in_due' },
  { time: '17:45', type: 'check_out_reminder' },
  { time: '18:00', type: 'check_out_due' },
] as const;

// ─── إعداد الحضور الكامل ─────────────────────────────────────────────────────

export const attendanceConfigSchema = z.object({
  /** وقت بداية الدوام بصيغة HH:mm */
  checkInTime: z.string().regex(/^\d{2}:\d{2}$/).default('10:00'),
  /** وقت نهاية الدوام بصيغة HH:mm */
  checkOutTime: z.string().regex(/^\d{2}:\d{2}$/).default('18:00'),
  /** المنطقة الزمنية */
  timezone: z.string().default('Africa/Cairo'),
  /** فترات السماح */
  gracePeriod: gracePeriodSchema.default({ lateGraceMinutes: 15, earlyLeaveGraceMinutes: 15 }),
  /** جدول التذكيرات */
  reminders: z.array(attendanceReminderSchema).default([...DEFAULT_ATTENDANCE_REMINDERS]),
  /** الفئات المستثناة من الحضور الإلزامي */
  exemptRoles: z.array(z.string()).default(['executive_director']),
});
export type AttendanceConfig = z.infer<typeof attendanceConfigSchema>;
