import { Eye, EyeOff } from 'lucide-react';
import { useState, type FormEvent } from 'react';
import { safeErrorMessage } from '../../../core/errorMapper';
import { ErrorBanner } from '../../../ui/ErrorState';
import { useSetEmployeePassword } from '../useEmployees';

export function EditEmployeePasswordSection({ employeeId }: { employeeId: string }) {
  const passwordMutation = useSetEmployeePassword();
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [showPwd, setShowPwd] = useState(false);
  const [pwdError, setPwdError] = useState<string | null>(null);
  const [pwdSuccess, setPwdSuccess] = useState(false);

  const onPasswordSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setPwdError(null);
    setPwdSuccess(false);

    // SEC: سياسة مبسّطة بطلب الإدارة — 6 أحرف كحد أدنى بلا شروط تعقيد.
    // المطابق لـ validateHrIssuedPassword في admin-set-password Edge Function.
    const pwd = newPassword;
    let err: string | null = null;
    if (pwd.length < 6) {
      err = 'كلمة المرور يجب أن تكون 6 أحرف على الأقل.';
    } else if (pwd.length > 72) {
      err = 'كلمة المرور يجب ألا تتجاوز 72 حرفًا.';
    }
    if (err) {
      setPwdError(err);
      return;
    }
    if (newPassword !== confirmPassword) {
      setPwdError('كلمتا المرور غير متطابقتين.');
      return;
    }
    try {
      await passwordMutation.mutateAsync({ employeeId, password: newPassword });
      setPwdSuccess(true);
      setNewPassword('');
      setConfirmPassword('');
    } catch (submitErr) {
      setPwdError(safeErrorMessage(submitErr));
    }
  };

  return (
    <form onSubmit={(e) => void onPasswordSubmit(e)} className="mt-6 space-y-4 border-t border-[var(--border)] pt-5">
      <h3 className="font-black">تعيين كلمة المرور</h3>
      <p className="muted text-xs">كلمة مرور (6–72 حرفًا — بلا شروط تعقيد) — يعيّنها الإداري ويتعين على الموظف تغييرها عند أول دخول.</p>
      {pwdError ? <ErrorBanner message={pwdError} /> : null}
      {pwdSuccess ? (
        <p className="rounded-lg bg-[var(--success-soft)] px-3 py-2 text-sm text-[var(--success)]">
          تم تعيين كلمة المرور بنجاح. سيُجبر الموظف على تغييرها عند أول دخول.
        </p>
      ) : null}
      <div className="grid gap-4 sm:grid-cols-2">
        <label className="block">
          <span className="mb-1.5 block text-sm font-semibold">كلمة المرور الجديدة (6–72 حرفًا)</span>
          <div className="relative">
            <input
              className="input w-full pe-10"
              type={showPwd ? 'text' : 'password'}
              value={newPassword}
              onChange={(e) => {
                setNewPassword(e.target.value);
                setPwdSuccess(false);
              }}
              autoComplete="new-password"
              minLength={6}
              maxLength={72}
              disabled={passwordMutation.isPending}
            />
            <button
              type="button"
              className="absolute start-2 top-1/2 -translate-y-1/2 text-[var(--muted)] hover:text-[var(--text)]"
              onClick={() => setShowPwd((v) => !v)}
              aria-label={showPwd ? 'إخفاء' : 'إظهار'}
            >
              {showPwd ? <EyeOff className="size-4" aria-hidden="true" /> : <Eye className="size-4" aria-hidden="true" />}
            </button>
          </div>
        </label>
        <label className="block">
          <span className="mb-1.5 block text-sm font-semibold">تأكيد كلمة المرور</span>
          <input
            className="input w-full"
            type={showPwd ? 'text' : 'password'}
            value={confirmPassword}
            onChange={(e) => {
              setConfirmPassword(e.target.value);
              setPwdSuccess(false);
            }}
            autoComplete="new-password"
            minLength={6}
            maxLength={72}
            disabled={passwordMutation.isPending}
          />
        </label>
        <div className="sm:col-span-2">
          <button type="submit" disabled={passwordMutation.isPending || newPassword.length < 6 || newPassword !== confirmPassword} className="btn-primary">
            {passwordMutation.isPending ? 'جارٍ التعيين…' : 'تعيين كلمة المرور'}
          </button>
        </div>
      </div>
    </form>
  );
}
