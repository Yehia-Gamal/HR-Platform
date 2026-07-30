import { AlertTriangle, RefreshCcw } from 'lucide-react';
import { Component, type ErrorInfo, type PropsWithChildren } from 'react';
import { captureError } from '../core/sentry';
import { AppLogo } from './AppLogo';

interface State { hasError: boolean; errorId: string | null }

export class AppErrorBoundary extends Component<PropsWithChildren, State> {
  state: State = { hasError: false, errorId: null };

  static getDerivedStateFromError(): State {
    return { hasError: true, errorId: crypto.randomUUID().slice(0, 8).toUpperCase() };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    captureError(error, { componentStack: info.componentStack });

    // Avoid logging session tokens or request payloads. Production monitoring may
    // capture only the error name, message and component stack after PII scrubbing.
    if (import.meta.env.DEV) {
      console.error('Application render failure', {
        name: error.name,
        message: error.message,
        componentStack: info.componentStack,
        errorId: this.state.errorId,
      });
    }
  }

  private recover = () => {
    window.location.assign('/');
  };

  render() {
    if (!this.state.hasError) return this.props.children;
    return (
      <main className="grid min-h-screen place-items-center bg-[var(--page-bg)] p-5" dir="rtl">
        <section className="card w-full max-w-xl p-7 text-center sm:p-9" role="alert">
          <div className="mx-auto mb-7 flex justify-center"><AppLogo /></div>
          <span className="mx-auto grid size-14 place-items-center rounded-2xl bg-[var(--danger-soft)] text-[var(--danger)]"><AlertTriangle className="size-6" aria-hidden="true" /></span>
          <h1 className="mt-5 text-2xl font-black">حدث خطأ غير متوقع في عرض الصفحة</h1>
          <p className="mt-3 text-sm leading-7 text-[var(--text-muted)]">لم يتم تنفيذ أي إجراء جديد. أعد تحميل المساحة، ثم تواصل مع الدعم وأرسل رقم الخطأ إذا تكررت المشكلة.</p>
          {this.state.errorId ? <p className="mt-3 font-mono text-xs text-[var(--text-muted)]" dir="ltr">Error ID: {this.state.errorId}</p> : null}
          <button type="button" className="btn-primary mx-auto mt-6" onClick={this.recover}><RefreshCcw className="size-4" aria-hidden="true" />إعادة تحميل المنصة</button>
        </section>
      </main>
    );
  }
}
