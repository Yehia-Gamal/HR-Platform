import { z } from 'zod';

// عقود طلب الموقع الحي + فيديو التحقق (Migration 0067).
// تطابق مخرجات RPCs: get_location_directory / get_live_location_response /
// get_executive_attendance_overview.

export const liveLocationModeSchema = z.enum([
  'snapshot',
  'video_5s',
  'location_video', // الوضع المدمج للمدير التنفيذي: نقطة + فيديو 5 ثوانٍ
  'track_5',
  'track_10',
  'track_15',
  'track_30',
]);
export type LiveLocationMode = z.infer<typeof liveLocationModeSchema>;

export const liveLocationStatusSchema = z.enum([
  'pending',
  'accepted',
  'active',
  'completed',
  'rejected',
  'expired',
  'cancelled',
]);
export type LiveLocationStatus = z.infer<typeof liveLocationStatusSchema>;

export const liveLocationVideoStatusSchema = z.enum([
  'pending',
  'uploading',
  'uploaded',
  'processing',
  'ready',
  'failed',
  'deleted',
]);
export type LiveLocationVideoStatus = z.infer<typeof liveLocationVideoStatusSchema>;

// عنصر دليل الموقع (من يمكن طلب موقعه) — get_location_directory.
export const locationDirectoryItemSchema = z.object({
  id: z.string().uuid(),
  name: z.string(),
  employeeCode: z.string().nullable(),
  jobTitle: z.string().nullable(),
  department: z.string().nullable(),
  lastLatitude: z.number().nullable(),
  lastLongitude: z.number().nullable(),
  lastAccuracy: z.number().nullable(),
  lastRecordedAt: z.string().nullable(),
  activeRequestId: z.string().uuid().nullable(),
  activeRequestStatus: z.string().nullable(),
});
export type LocationDirectoryItem = z.infer<typeof locationDirectoryItemSchema>;

// نقطة موقع واحدة ضمن نتيجة الطلب.
export const liveLocationPointSchema = z.object({
  id: z.string().uuid(),
  latitude: z.number(),
  longitude: z.number(),
  accuracy: z.number().nullable(),
  altitude: z.number().nullable(),
  speed: z.number().nullable(),
  heading: z.number().nullable(),
  isMock: z.boolean(),
  source: z.string().nullable(),
  addressAr: z.string().nullable(),
  recordedAt: z.string(),
  createdAt: z.string(),
});
export type LiveLocationPoint = z.infer<typeof liveLocationPointSchema>;

// بيانات فيديو التحقق (بدون رابط خام — الرابط يُوقَّع عند الطلب).
export const liveLocationVideoMetaSchema = z.object({
  id: z.string().uuid(),
  durationSeconds: z.number(),
  sizeBytes: z.number(),
  mimeType: z.string(),
  capturedLat: z.number().nullable(),
  capturedLng: z.number().nullable(),
  capturedAccuracy: z.number().nullable(),
  capturedAt: z.string().nullable(),
  status: liveLocationVideoStatusSchema,
  retentionDeleteAfter: z.string().nullable(),
  legalHoldUntil: z.string().nullable(),
});
export type LiveLocationVideoMeta = z.infer<typeof liveLocationVideoMetaSchema>;

// نتيجة الطلب الكاملة — get_live_location_response.
export const liveLocationResponseSchema = z.object({
  request: z.object({
    id: z.string().uuid(),
    status: liveLocationStatusSchema,
    mode: liveLocationModeSchema,
    reason: z.string().nullable(),
    purpose: z.string().nullable(),
    requestedAt: z.string(),
    respondedAt: z.string().nullable(),
    startsAt: z.string().nullable(),
    expiresAt: z.string().nullable(),
    durationMinutes: z.number().nullable(),
    needsVideo: z.boolean(),
    needsPoint: z.boolean(),
  }),
  employee: z.object({
    id: z.string().uuid(),
    name: z.string(),
    employeeCode: z.string().nullable(),
    jobTitle: z.string().nullable(),
    department: z.string().nullable(),
  }),
  requesterName: z.string().nullable(),
  points: z.array(liveLocationPointSchema),
  video: liveLocationVideoMetaSchema.nullable(),
});
export type LiveLocationResponse = z.infer<typeof liveLocationResponseSchema>;

// صف موظف في لوحة المتابعة اليومية — get_executive_attendance_overview.
export const executiveAttendanceStatusSchema = z.enum([
  'present',
  'late',
  'not_yet',
  'absent',
  'checked_out',
  'left_early',
  'on_leave',
  'assignment',
]);
export type ExecutiveAttendanceStatus = z.infer<typeof executiveAttendanceStatusSchema>;

export const executiveAttendanceRowSchema = z.object({
  id: z.string().uuid(),
  name: z.string(),
  employeeCode: z.string().nullable(),
  avatarUrl: z.string().nullable(),
  jobTitle: z.string().nullable(),
  department: z.string().nullable(),
  managerName: z.string().nullable(),
  status: executiveAttendanceStatusSchema,
  attStatus: z.string().nullable(),
  firstCheckIn: z.string().nullable(),
  lastCheckOut: z.string().nullable(),
  lateMinutes: z.number().nullable(),
  earlyLeaveMinutes: z.number().nullable(),
  onLeave: z.boolean(),
  assignmentType: z.enum(['MISSION', 'CONVOY', 'FUNDRAISING']).nullable(),
  lastLatitude: z.number().nullable(),
  lastLongitude: z.number().nullable(),
  lastAccuracy: z.number().nullable(),
  lastLocationAt: z.string().nullable(),
  lastAddressAr: z.string().nullable(),
  locationSource: z.string().nullable(),
  statusUpdatedAt: z.string().nullable(),
  activeRequestId: z.string().uuid().nullable(),
  activeRequestStatus: z.string().nullable(),
});
export type ExecutiveAttendanceRow = z.infer<typeof executiveAttendanceRowSchema>;

export const executiveAttendanceOverviewSchema = z.object({
  date: z.string(),
  summary: z.object({
    total: z.number(),
    present: z.number().optional(),
    late: z.number().optional(),
    notYet: z.number().optional(),
    absent: z.number().optional(),
    checkedOut: z.number().optional(),
    leftEarly: z.number().optional(),
    onLeave: z.number().optional(),
    onAssignment: z.number().optional(),
    onMission: z.number().optional(),
    onConvoy: z.number().optional(),
    onFundraising: z.number().optional(),
    activeLocationRequests: z.number().optional(),
  }),
  employees: z.array(executiveAttendanceRowSchema),
  generatedAt: z.string(),
});
export type ExecutiveAttendanceOverview = z.infer<typeof executiveAttendanceOverviewSchema>;

// طلب توقيع رابط فيديو (مدخلات دالة Edge live-location-video-url).
export const liveLocationVideoUrlRequestSchema = z.object({ videoId: z.string().uuid() });
export type LiveLocationVideoUrlRequest = z.infer<typeof liveLocationVideoUrlRequestSchema>;

export const liveLocationVideoUrlResponseSchema = z.object({
  url: z.string().url(),
  expiresInSeconds: z.number(),
});
export type LiveLocationVideoUrlResponse = z.infer<typeof liveLocationVideoUrlResponseSchema>;
