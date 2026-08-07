import { useEffect, useState } from 'react';
import { getSupabase } from '../core/supabase';
import { hasSupabaseConfig } from '../core/env';
import { extractAvatarPath } from './avatarUrl';

/**
 * يحل photo_url إلى رابط قابل للعرض.
 * الروابط الخارجية (mock/CDN) تُعاد كما هي. روابط bucket employee-avatars
 * الخاص تُحمَّل عبر التخزين مع جلسة المستخدم مصادقًا وتُحوَّل إلى object URL
 * مؤقت حتى لا يعتمد العرض على صلاحية الوصول العام (bucket private منذ 0211).
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
      // وضع التطوير/mock بدون supabase — لا يمكن تحميل الصورة.
      setResolved(null);
      return;
    }

    let cancelled = false;
    let objectUrl: string | null = null;
    setResolved(null);

    (async () => {
      const supabase = await getSupabase();
      const { data, error } = await supabase.storage.from('employee-avatars').download(path);
      if (cancelled || error || !data) return;
      objectUrl = URL.createObjectURL(data);
      if (!cancelled) setResolved(objectUrl);
    })().catch(() => {
      // يبقى null — المكوّن يعرض الحرف الأول.
    });

    return () => {
      cancelled = true;
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [photoUrl]);

  return resolved;
}
