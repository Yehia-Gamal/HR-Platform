import { useEffect, useRef, useState } from 'react';
import { useSearchParams } from 'react-router';

/**
 * إبراز عنصر بعينه بعد الوصول من إشعار.
 *
 * الإشعار يفتح `…?focus={id}`؛ هذا الخطاف يلتقط المعرّف، يمرّر الصفحة إليه
 * (scrollIntoView على العنصر الحامل لـ `data-focus-id`)، ويعيده للصفحة كي
 * تُلوّن صفّه لبضع ثوانٍ. المعلمة تُحذف من الرابط فوراً حتى لا يتكرر الإبراز
 * عند كل إعادة رسم أو تحديث للصفحة.
 *
 * @param ready مرّر `true` حين تكون بيانات القائمة قد رُسمت فعلاً — قبلها لا
 *              يوجد عنصر في DOM لنمرّر إليه.
 */
export function useEntityFocus(ready: boolean, param = 'focus', onMissing?: (id: string) => void): string | null {
  const [searchParams, setSearchParams] = useSearchParams();
  const pending = searchParams.get(param);
  const [focusedId, setFocusedId] = useState<string | null>(null);
  const handledRef = useRef<string | null>(null);
  // مرجع ثابت حتى لا يعيد التأثير التشغيل عند كل رسم بدالة جديدة.
  const onMissingRef = useRef(onMissing);
  onMissingRef.current = onMissing;

  useEffect(() => {
    if (!pending || !ready || handledRef.current === pending) return;
    handledRef.current = pending;
    const id = pending;
    setFocusedId(id);
    setSearchParams(
      (prev) => {
        const next = new URLSearchParams(prev);
        next.delete(param);
        return next;
      },
      { replace: true },
    );

    // البحث عن العنصر عبر عدة إطارات: بعض القوائم تُركّب صفوفها تدريجياً
    // (صور، قوائم افتراضية) فلا يكفي إطار واحد بعد تغيّر `ready`.
    const selector = `[data-focus-id="${CSS.escape(id)}"]`;
    let attempts = 0;
    let frame = 0;
    const seek = () => {
      const element = document.querySelector<HTMLElement>(selector);
      if (element) {
        element.scrollIntoView({ behavior: 'smooth', block: 'center' });
        return;
      }
      attempts += 1;
      if (attempts < 30) {
        frame = requestAnimationFrame(seek);
        return;
      }
      // العنصر خارج الفلتر أو الصفحة الحالية — نُبلغ الصفحة بدل صمت يبدو كعطل.
      onMissingRef.current?.(id);
      setFocusedId(null);
    };
    frame = requestAnimationFrame(seek);
    const timer = setTimeout(() => setFocusedId(null), 6000);
    return () => {
      cancelAnimationFrame(frame);
      clearTimeout(timer);
    };
  }, [pending, ready, param, setSearchParams]);

  return focusedId;
}

/** صنف الإبراز الموحّد — يُضاف على الصف المطابق للمعرّف المطلوب. */
export const ENTITY_FOCUS_CLASS = 'entity-focus-highlight';

/** مساعد مختصر: خصائص العنصر القابل للإبراز. */
export function focusProps(id: string, focusedId: string | null) {
  return {
    'data-focus-id': id,
    className: focusedId === id ? ENTITY_FOCUS_CLASS : undefined,
  };
}
