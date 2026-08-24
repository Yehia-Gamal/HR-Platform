import { useEffect, useState } from 'react';
import type { ReactNode } from 'react';
import { BellRing } from 'lucide-react';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { useToast } from '../../ui/Toast';
import { useAuth } from '../auth/AuthProvider';
import { hasPermission } from '../workspaces/access';
import { safeErrorMessage } from '../../core/errorMapper';
import { useActiveBroadcastAlert, useSendBroadcastAlert } from './useBroadcastAlert';

/**
 * زر "تنبيه شامل" — يظهر فقط لمن يملك صلاحية alerts.broadcast.send
 * (المدير التنفيذي وHR). يفتح حوار كتابة الرسالة ثم يرسل التنبيه
 * لكامل الموظفين.
 *
 * فحص الصلاحية يسبق تركيب أي خطافات (useMutation تحتاج QueryClient)
 * حتى يعمل الزر بأمان في أي شجرة بلا مزوّد استعلامات عند غياب الصلاحية.
 */
export function BroadcastAlertButton(): ReactNode {
  const auth = useAuth();
  if (!(auth.access != null && hasPermission(auth.access, 'alerts.broadcast.send'))) return null;
  return <BroadcastAlertButtonInner />;
}

function BroadcastAlertButtonInner(): ReactNode {
  const { toast } = useToast();
  const [open, setOpen] = useState(false);
  const [message, setMessage] = useState('');
  const send = useSendBroadcastAlert();

  const submit = () => {
    send.mutate(message.trim(), {
      onSuccess: () => {
        setOpen(false);
        setMessage('');
        toast({ message: 'أُرسل التنبيه الشامل لكل الموظفين', tone: 'success' });
      },
      onError: (error) => toast({ message: safeErrorMessage(error), tone: 'error' }),
    });
  };

  return (
    <>
      <button type="button" onClick={() => setOpen(true)} className="btn-danger" aria-label="إرسال تنبيه شامل لكامل الموظفين">
        <BellRing className="size-4" aria-hidden="true" />
        تنبيه شامل
      </button>
      {open ? (
        <DialogOverlay title="إرسال تنبيه شامل" onClose={() => setOpen(false)} maxWidth="max-w-lg">
          <div className="space-y-4">
            <p className="muted text-sm leading-6">
              سيصل التنبيه فورًا لكامل الموظفين — تومض الشاشة ويُشغَّل فلاش الجهاز والاهتزاز حتى ينتهي التنبّه أو يعطلوه. استخدمه للحالات الطارئة فقط.
            </p>
            <textarea
              autoFocus
              value={message}
              onChange={(e) => setMessage(e.target.value)}
              maxLength={300}
              rows={3}
              placeholder="نص التنبيه (3 أحرف على الأقل)… مثال: اجتماع طارئ فورًا في المقر الرئيسي"
              className="input-field w-full text-sm leading-7"
              aria-label="نص التنبيه"
            />
            <div className="flex items-center justify-between gap-3">
              <span className="muted text-xs">{message.trim().length}/300</span>
              <button type="button" disabled={send.isPending || message.trim().length < 3} onClick={submit} className="btn-danger disabled:opacity-50">
                {send.isPending ? 'جارٍ الإرسال…' : 'إرسال التنبيه الآن'}
              </button>
            </div>
          </div>
        </DialogOverlay>
      ) : null}
    </>
  );
}

/** غطاء الاستقبال: يومض أحمر/أبيض على كامل الشاشة ما دام هناك تنبيه نشط. */
export function BroadcastAlertBanner(): ReactNode {
  const auth = useAuth();
  const enabled = !auth.isMock && auth.session != null;
  const q = useActiveBroadcastAlert(enabled);
  const [dismissedId, setDismissedId] = useState<string | null>(null);
  const [phase, setPhase] = useState(false);
  const alert = q.data ?? null;
  const visible = alert != null && alert.id !== dismissedId;

  useEffect(() => {
    if (!visible) return;
    const timer = setInterval(() => setPhase((p) => !p), 500);
    return () => clearInterval(timer);
  }, [visible]);

  // إخفاء تلقائي عند انتهاء صلاحية التنبيه.
  const expiresAt = visible && alert ? new Date(alert.expiresAt).getTime() : 0;
  const now = Date.now();
  useEffect(() => {
    if (!visible || expiresAt <= now) return;
    const timer = setTimeout(() => q.refetch(), Math.max(1000, expiresAt - now + 2000));
    return () => clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [visible, expiresAt]);

  if (!visible || !alert) return null;

  return (
    <div
      role="alert"
      aria-live="assertive"
      className={`fixed inset-0 z-[120] flex flex-col items-center justify-center gap-6 p-8 text-center transition-colors duration-150 ${
        phase ? 'bg-red-800 text-white' : 'bg-white text-red-700'
      }`}
    >
      <BellRing className="size-20 animate-bounce" aria-hidden="true" />
      <h2 className="text-3xl font-black">تنبيه عاجل</h2>
      <p className="max-w-xl text-xl font-bold leading-relaxed">{alert.message}</p>
      <button
        type="button"
        onClick={() => setDismissedId(alert.id)}
        className={`rounded-xl px-6 py-2.5 font-black shadow-lg ${phase ? 'bg-white text-red-700' : 'bg-red-700 text-white'}`}
      >
        حسنًا، تم الاطلاع
      </button>
    </div>
  );
}
