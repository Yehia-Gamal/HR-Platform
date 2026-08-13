import { useMemo } from 'react';
import { env, hasSupabaseConfig } from '../core/env';
import { toPublicAvatarUrl } from './avatarUrl';

/**
 * يحل photo_url إلى رابط قابل للعرض.
 * الـ bucket عام (0293) لذا نستخدم رابطًا عامًا مباشرًا متزامنًا — أبسط وأسرع
 * ولا ينتهي (بعكس Signed URL الذي كان ينتهي بعد ساعة فيتسبب في اختفاء الصور
 * بعد الجلسات الطويلة). الروابط الخارجية (mock/CDN) تُعاد كما هي.
 * يُرجع null لو لم يُعثر على رابط صالح (فيُظهر المكوّن بديله: الحرف الأول).
 */
export function useResolvedAvatarUrl(
  photoUrl: string | null | undefined,
): string | null {
  return useMemo(() => {
    const input = photoUrl?.trim() || null;
    if (!input) return null;
    if (!hasSupabaseConfig) {
      // بلا إعداد: الروابط الخارجية تعمل، روابط bucket لا يمكن بناؤها.
      const external = toPublicAvatarUrl(input, '');
      return external;
    }
    return toPublicAvatarUrl(input, env.supabaseUrl);
  }, [photoUrl]);
}
