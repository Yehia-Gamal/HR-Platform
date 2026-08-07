import { AlertTriangle, RefreshCcw } from 'lucide-react';
import { Component, type ErrorInfo, type PropsWithChildren } from 'react';
import { captureError } from '../core/sentry';

/**
 * Route-level error boundary — يُلف حول `<Outlet />` داخل الـ Shell
 * حتى لو انهارت صفحة واحدة يبقى الشريط الجانبي والترويسة يعملان
 * ويستطيع المستخدم التنقل لصفحة أخرى بدون إعادة تحميل كاملة.
 *
 * يختلف عن AppErrorBoundary (في main.tsx) الذي يمسك الأخطاء الكارثية
 * التي تُسقط كل التطبيق.
 */

interface State {
  hasError: boolean;
  errorId: string | null;
}

export class RouteErrorBoundary extends Component<PropsWithChildren, State> {
  state: State = { hasError: false, errorId: null };

  static getDerivedStateFromError(): State {
    return { hasError: true, errorId: crypto.randomUUID().slice(0, 8).toUpperCase() };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    captureError(error, {
      componentStack: info.componentStack,
      boundary: 'RouteErrorBoundary',
      errorId: this.state.errorId,
    });
    if (import.meta.env.DEV) {
      console.error('Route render failure', {
        name: error.name,
        message: error.message,
        componentStack: info.componentStack,
        errorId: this.state.errorId,
      });
    }
  }

  private retry = () => {
    this.setState({ hasError: false, errorId: null });
  };

  render() {
    if (!this.state.hasError) return this.props.children;
    return (
      <div className="grid min-h-[60vh] place-items-center p-6" role="alert">
        <section className="card w-full max-w-md p-7 text-center">
          <span className="mx-auto grid size-12 place-items-center rounded-2xl bg-[var(--danger-soft)] text-[var(--danger)]">
            <AlertTriangle className="size-5" aria-hidden="true" />
          </span>
          <h2 className="mt-4 text-lg font-black">تعذر عرض هذه الصفحة</h2>
          <p className="mt-2 text-sm leading-7 text-[var(--text-muted)]">
            حدث خطأ أثناء تحميل المحتوى. يمكنك إعادة المحاولة أو الانتقال لصفحة أخرى من القائمة الجانبية.
          </p>
          {this.state.errorId ? (
            <p className="mt-2 font-mono text-xs text-[var(--text-muted)]" dir="ltr">
              Error ID: {this.state.errorId}
            </p>
          ) : null}
          <button type="button" className="btn-primary mx-auto mt-5" onClick={this.retry}>
            <RefreshCcw className="size-4" aria-hidden="true" />
            إعادة المحاولة
          </button>
        </section>
      </div>
    );
  }
}
