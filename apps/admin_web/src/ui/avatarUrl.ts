const PRIVATE_BUCKET = 'employee-avatars';
const PUBLIC_MARKER = `/storage/v1/object/public/${PRIVATE_BUCKET}/`;
const AUTHENTICATED_MARKER = `/storage/v1/object/authenticated/${PRIVATE_BUCKET}/`;
// صيغة قديمة: /storage/v1/object/employee-avatars/ (بدون public/authenticated)
const LEGACY_MARKER = `/storage/v1/object/${PRIVATE_BUCKET}/`;

/**
 * يستخرج مسار الملف داخل bucket الصور الخاص من رابط مخزّن.
 * يدعم صيغة public القديمة وصيغة authenticated الحالية، ويعيد null لأي
 * رابط خارجي (CDN/mock/…) بحيث يُحمَّل مباشرة دون توسّط.
 */
export function extractAvatarPath(url: string): string | null {
  if (!url) return null;
  for (const marker of [PUBLIC_MARKER, AUTHENTICATED_MARKER, LEGACY_MARKER]) {
    const index = url.indexOf(marker);
    if (index >= 0) {
      const path = url.substring(index + marker.length).split('?')[0];
      try {
        return decodeURIComponent(path);
      } catch {
        return path;
      }
    }
  }
  return null;
}

/**
 * يحوّل رابطًا عامًا قديمًا إلى نقطة نهاية authenticated. يُستخدم لكتابة
 * photo_url الجديدة بحيث تفشل بصمت في أي عميل لم يُحدَّث بعد بدل عرض بيانات
 * قديمة مضللة.
 */
export function toAuthenticatedAvatarUrl(url: string): string {
  const index = url.indexOf(PUBLIC_MARKER);
  if (index < 0) return url;
  return url.slice(0, index) + AUTHENTICATED_MARKER + url.substring(index + PUBLIC_MARKER.length);
}
