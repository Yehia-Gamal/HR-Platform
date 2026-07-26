import { type ReactNode } from 'react';
import { createPortal } from 'react-dom';

/**
 * يعرض المحتوى عبر React Portal في document.body
 * يحل مشكلة المودالات التي تظهر تحت الشاشة بسبب stacking context
 * (backdrop-filter / transform على العناصر الأب تكسر position: fixed)
 */
export function DialogPortal({ children }: { children: ReactNode }) {
  return createPortal(children, document.body);
}
