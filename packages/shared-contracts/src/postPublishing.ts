import { z } from 'zod';

// عقود نشر المنشورات الرسمية — V17 §18.
// صلاحيات النشر محددة بدقة: الأدمن الرئيسي (ويب) + HR (ويب) + التنفيذي (موبايل).

// ─── أدوار النشر ─────────────────────────────────────────────────────────────

export const publisherRoleSchema = z.enum([
  'main_admin',
  'hr_web',
  'executive_mobile',
]);
export type PublisherRole = z.infer<typeof publisherRoleSchema>;

/** مخطط أدوار النشر المختصر — V17 §18 (اسم بديل بأكواد مختصرة). */
export const postPublishingRoleSchema = z.enum(['main_admin', 'hr', 'executive']);
export type PostPublishingRole = z.infer<typeof postPublishingRoleSchema>;

/** القنوات المسموحة لكل دور نشر. */
export const PUBLISHER_CHANNELS: Record<PublisherRole, 'web' | 'mobile'> = {
  main_admin: 'web',
  hr_web: 'web',
  executive_mobile: 'mobile',
};

// ─── أنواع المنشورات ─────────────────────────────────────────────────────────

export const postTypeSchema = z.enum([
  'standard',
  'announcement',
  'decision',
  'alert',
  'poll',
  'meeting',
  'holiday_notice',
  'kpi_notice',
  'attendance_notice',
]);
export type PostType = z.infer<typeof postTypeSchema>;

// ─── مدخلات إنشاء منشور ──────────────────────────────────────────────────────

export const createPostInputSchema = z.object({
  type: postTypeSchema.default('announcement'),
  title: z.string().min(3).max(300),
  body: z.string().min(3).max(5000),
  category: z.string().max(100).optional(),
  /** هل يتطلب إقرار بالاطلاع؟ */
  requiresAcknowledgement: z.boolean().default(false),
  /** صورة مرفقة (معرّف تخزين) */
  imageId: z.string().uuid().optional(),
  /** تاريخ انتهاء المنشور */
  expiresAt: z.string().datetime().optional(),
  /** خيارات الاستطلاع (2–6 خيارات — مطلوبة لنوع poll فقط) — V23 §17 */
  pollOptions: z.array(z.string().min(1).max(500)).min(2).max(6).optional(),
  /** تاريخ انتهاء الاستطلاع */
  pollExpiresAt: z.string().datetime().optional(),
});
export type CreatePostInput = z.infer<typeof createPostInputSchema>;
