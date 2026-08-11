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
export const postPublishingRoleSchema = z.enum(["main_admin", "hr", "executive"]);
export type PostPublishingRole = z.infer<typeof postPublishingRoleSchema>;

/** القنوات المسموحة لكل دور نشر. */
export const PUBLISHER_CHANNELS: Record<PublisherRole, "web" | "mobile"> = {
  main_admin: "web",
  hr_web: "web",
  executive_mobile: "mobile",
};

// ─── أنواع المنشورات ─────────────────────────────────────────────────────────

export const postTypeSchema = z.enum([
  "standard",
  "announcement",
  "decision",
  "alert",
  "poll",
  "meeting",
  "holiday_notice",
  "kpi_notice",
  "attendance_notice",
]);
export type PostType = z.infer<typeof postTypeSchema>;

// ─── تفاعلات الإعلانات (mig 0372) ───────────────────────────────────────────

export const reactionTypeSchema = z.enum(["like", "celebrate", "support", "insightful"]);
export type ReactionType = z.infer<typeof reactionTypeSchema>;

export const announcementReactionEntrySchema = z.object({
  employeeId: z.string().uuid(),
  name: z.string(),
  photoUrl: z.string().nullable(),
  at: z.string(),
  reactionType: reactionTypeSchema,
});
export type AnnouncementReactionEntry = z.infer<typeof announcementReactionEntrySchema>;

export const announcementEngagementSchema = z.object({
  viewCount: z.number().int(),
  reactionCount: z.number().int(),
  myReaction: reactionTypeSchema.nullable(),
  reactions: z.array(announcementReactionEntrySchema),
});
export type AnnouncementEngagement = z.infer<typeof announcementEngagementSchema>;

export const toggleReactionResultSchema = z.object({
  active: z.boolean(),
  myReaction: reactionTypeSchema.nullable(),
  reactionCount: z.number().int(),
  reactionSummary: z.record(z.string(), z.number()),
});
export type ToggleReactionResult = z.infer<typeof toggleReactionResultSchema>;

// ─── مدخلات إنشاء منشور ──────────────────────────────────────────────────────

export const createPostInputSchema = z.object({
  type: postTypeSchema.default("announcement"),
  title: z.string().min(3).max(300),
  body: z.string().min(3).max(5000),
  category: z.string().max(100).optional(),
  requiresAcknowledgement: z.boolean().default(false),
  imageId: z.string().uuid().optional(),
  expiresAt: z.string().datetime().optional(),
  pollOptions: z.array(z.string().min(1).max(500)).min(2).max(6).optional(),
  pollExpiresAt: z.string().datetime().optional(),
});
export type CreatePostInput = z.infer<typeof createPostInputSchema>;
