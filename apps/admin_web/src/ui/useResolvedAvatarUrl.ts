import { useEffect, useState } from 'react';
import { getSupabase } from '../core/supabase';
import { hasSupabaseConfig } from '../core/env';
import { extractAvatarPath } from './avatarUrl';

/**
 * يحل photo_url إلى رابط قابل للعرض.
 * الروابط الخارجية (mock/CDN) تُعاد كما هي. روابط bucket employee-avatars
 * تُحوَّل إلى Signed URL صالحة ساعة — Chrome يستطيع كاشها طبيعياً
 * بعكس blob URLs الناتجة عن download() التي تسبب ERR_CACHE_READ_FAILURE.
 * يُرجع null مؤقتًا أثناء التحميل ليُظهر المكوّن بديله (الحرف الأول + skeleton).
 */
export function useResolvedAvatarUrl(photoUrl: string | null | undefined): string | null {
  const [resolved, setResolved] = useState<string | null>(null);

  useEffect(() => {
    const input = photoUrl?.trim() || null;
    if (!input) {
      setResolved(null);
      return;
    }

    const path = extractAvatarPath(input);
    if (!path) {
      setResolved(input);
      return;
    }

    if (!hasSupabaseConfig) {
      setResolved(null);
      return;
    }

    let cancelled = false;
    setResolved(null);

    (async () => {
      const supabase = await getSupabase();
      const { data, error } = await supabase.storage
        .from('employee-avatars')
        .createSignedUrl(path, 3600);
      if (cancelled || error || !data?.signedUrl) return;
      if (!cancelled) setResolved(data.signedUrl);
    })().catch(() => {
      // يبقى null — المكوّن يعرض الحرف الأول.
    });

    return () => { cancelled = true; };
  }, [photoUrl]);

  return resolved;
}
