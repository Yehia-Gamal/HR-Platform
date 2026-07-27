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

// ─── إعدادات الحضور على مستوى الخادم (V23 §4) ─────────────────────────────
// تعكس جدول attendance_settings (singleton) — المصدر الوحيد للحقيقة.

export const attendanceSettingsSchema = z.object({
  /** نصف قطر السياج الافتراضي (متر) — V23 §4 */
  geofenceRadiusDefaultMeters: z.number().min(50).max(5000).default(300),
  /** أقصى عمر للموقع (ثانية) — الخادم يرفض موقعاً أقدم من هذا */
  locationAgeMaxSeconds: z.number().int().min(5).max(120).default(15),
  /** أقصى دقة مقبولة (متر) — احتياطي إذا لم يُحدد في السياج */
  accuracyMaxDefaultMeters: z.number().min(10).max(1000).default(100),
  /** فترة سماح بعد انتهاء الوردية لانتظار بصمة الخروج (دقيقة) */
  missingCheckoutGraceMinutes: z.number().int().min(15).max(480).default(60),
  /** عتبة سرعة الانتقال المستحيل (م/ث) — 42 ≈ 150 كم/س */
  impossibleTravelSpeedMps: z.number().min(10).max(200).default(42),
  /** المنطقة الزمنية الرسمية */
  timezone: z.string().default('Africa/Cairo'),
});
export type AttendanceSettings = z.infer<typeof attendanceSettingsSchema>;

/** الحالات المسموحة لـ attendance_daily.status — V23 §4. */
export const attendanceDailyStatus = z.enum([
  'present', 'absent', 'late', 'on_leave', 'holiday',
  'weekend', 'partial', 'pending', 'missing_checkout',
]);
export type AttendanceDailyStatus = z.infer<typeof attendanceDailyStatus>;
