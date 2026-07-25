import { z } from 'zod';

// أدوات تحقق مشتركة — V17 §1.3.
// الحد الأدنى 3 أحرف والحد الأقصى 300 حرف لحقول النصوص القصيرة.

// ─── قيود عدد الأحرف ─────────────────────────────────────────────────────────

/** الحد الأدنى للأحرف في الحقول النصية (V17 §1.3). */
export const TEXT_MIN_LENGTH = 3;

/** الحد الأقصى للأحرف في الحقول النصية القصيرة (V17 §1.3). */
export const TEXT_MAX_LENGTH = 300;

/** نطاق عدد الأحرف — V17 §1.3 (اسم بديل لـ TEXT_MIN_LENGTH/TEXT_MAX_LENGTH). */
export const wordCountRange = { min: TEXT_MIN_LENGTH, max: TEXT_MAX_LENGTH } as const;

/** مخطط نص قصير: 3–300 حرف. يُستخدم لأسباب الطلبات والتعليقات والملاحظات. */
export const shortTextSchema = z.string().min(TEXT_MIN_LENGTH).max(TEXT_MAX_LENGTH);

/** اسم بديل لـ shortTextSchema — V17 §1.3 textField convention. */
export const textFieldSchema = shortTextSchema;

/** مخطط نص طويل: 3–2000 حرف. يُستخدم للأوصاف التفصيلية. */
export const longTextSchema = z.string().min(TEXT_MIN_LENGTH).max(2000);

/** مخطط نص اختياري قصير: أقصى 300 حرف (بدون حد أدنى). */
export const optionalShortTextSchema = z.string().max(TEXT_MAX_LENGTH).optional();

// ─── دالة مساعدة ─────────────────────────────────────────────────────────────

/**
 * يتحقق من أن النص يقع ضمن نطاق 3–300 حرف.
 * يُرجع `true` إذا كان صالحاً، `false` إذا لم يكن.
 */
export function isValidShortText(text: string): boolean {
  return text.length >= TEXT_MIN_LENGTH && text.length <= TEXT_MAX_LENGTH;
}

/**
 * يقص النص إلى الحد الأقصى مع إضافة علامة القطع.
 */
export function truncateText(text: string, maxLength: number = TEXT_MAX_LENGTH): string {
  if (text.length <= maxLength) return text;
  return text.slice(0, maxLength - 1) + '…';
}
