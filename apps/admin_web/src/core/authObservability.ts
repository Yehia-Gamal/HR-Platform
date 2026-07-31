// ─── Initiative: Production Observability ───────────────────────────────────
// Hooks AuthProvider state transitions into Sentry (user context + auth breadcrumbs).
// Indirectly imported via AuthProvider to keep bundle impact minimal when DSN absent.

import { addBreadcrumb, setUserContext, clearUserContext } from './sentry';

export function attachAuthObservability(): {
  onAuthChange(event: string, userId: string | null, role?: string): void;
} {
  return {
    onAuthChange(event, userId, role) {
      // لا نضع userId في بيانات الـ breadcrumb (PII). الهوية تُرفق عبر setUserContext فقط.
      addBreadcrumb('auth', `Auth event: ${event}`, { event });
      if (event === 'SIGNED_IN' && userId) {
        setUserContext(userId, role);
      } else if (event === 'SIGNED_OUT') {
        clearUserContext();
      }
    },
  };
}
