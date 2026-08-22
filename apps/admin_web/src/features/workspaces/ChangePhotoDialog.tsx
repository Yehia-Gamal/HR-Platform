import { useEffect, useRef, useState } from 'react';
import { Camera, CheckCircle2, Loader2 } from 'lucide-react';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { prepareAvatarFile } from '../../ui/avatarImage';
import { UserAvatar } from '../../ui/UserAvatar';
import { getSupabase } from '../../core/supabase';
import { rpc } from '../../core/rpc';
import { safeErrorMessage } from '../../core/errorMapper';
import { useAuth } from '../auth/AuthProvider';

/** يستخرج مسار الكائن داخل bucket employee-avatars من رابط عام/مصادق — لتنظيف الصورة القديمة. */
function avatarPathFromUrl(url: string | null | undefined): string | null {
  if (!url) return null;
  for (const marker of ['/storage/v1/object/public/employee-avatars/', '/storage/v1/object/authenticated/employee-avatars/']) {
    const index = url.indexOf(marker);
    if (index < 0) continue;
    const raw = url.substring(index + marker.length).split('?')[0];
    try {
      return decodeURIComponent(raw);
    } catch {
      return raw;
    }
  }
  return null;
}

/**
 * حوار تغيير الصورة الشخصية للمستخدم الحالي على الويب.
 * نفس مسار الموبايل: رفع إلى {auth.uid}/ داخل employee-avatars ثم set_my_photo_url
 * (سياسات التخزيس تسمح للعضو بإدارة ملفات مجلد معرّفه فقط).
 */
export function ChangePhotoDialog({ open, currentPhotoUrl, onClose }: { open: boolean; currentPhotoUrl: string | null; onClose: () => void }) {
  const auth = useAuth();
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const preparedRef = useRef<File | null>(null);
  const objectUrlRef = useRef<string | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  const clearObjectPreview = () => {
    if (objectUrlRef.current) URL.revokeObjectURL(objectUrlRef.current);
    objectUrlRef.current = null;
  };

  useEffect(() => clearObjectPreview, []);

  if (!open) return null;

  const onPick = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    event.target.value = '';
    if (!file) return;
    setError(null);
    try {
      const prepared = await prepareAvatarFile(file);
      preparedRef.current = prepared;
      clearObjectPreview();
      objectUrlRef.current = URL.createObjectURL(prepared);
      setPreviewUrl(objectUrlRef.current);
    } catch (pickError) {
      preparedRef.current = null;
      setPreviewUrl(null);
      // رسائل التحقق المحلية (صيغة/حجم/دقة) عربية جاهزة
      setError(pickError instanceof Error ? pickError.message : safeErrorMessage(pickError));
    }
  };

  const save = async () => {
    const prepared = preparedRef.current;
    if (!prepared || busy) return;
    setBusy(true);
    setError(null);
    try {
      if (!auth.isMock) {
        const uid = auth.session?.user.id;
        if (!uid) throw new Error('الجلسة غير متاحة. أعد تسجيل الدخول.');
        const supabase = await getSupabase();
        const path = `${uid}/self_${Date.now()}.webp`;
        const { error: uploadError } = await supabase.storage.from('employee-avatars').upload(path, prepared, { upsert: false, contentType: 'image/webp' });
        if (uploadError) throw uploadError;
        const { data } = supabase.storage.from('employee-avatars').getPublicUrl(path);
        await rpc('set_my_photo_url', { p_photo_url: data.publicUrl });
        const previousPath = avatarPathFromUrl(currentPhotoUrl);
        if (previousPath && previousPath !== path) {
          try {
            await supabase.storage.from('employee-avatars').remove([previousPath]);
          } catch {
            // الصورة الجديدة نشطة بالفعل — التنظيف اختياري ويمكن إجراؤه لاحقاً.
          }
        }
      }
      await auth.refreshAccess();
      setDone(true);
      window.setTimeout(onClose, 900);
    } catch (saveError) {
      setError(safeErrorMessage(saveError));
    } finally {
      setBusy(false);
    }
  };

  return (
    <DialogOverlay title="تغيير صورتي الشخصية" onClose={busy ? () => {} : onClose} maxWidth="max-w-md">
      <div className="grid place-items-center text-center">
        <UserAvatar displayName={auth.access?.displayName ?? ''} photoUrl={previewUrl ?? currentPhotoUrl} size="lg" eager announceName={false} />
        <p className="mt-3 text-xs leading-6 text-[var(--text-muted)]">
          JPG أو PNG أو WEBP · لا تقل عن 512×512 بكسل · حتى 5 ميجابايت.
          <br />
          تُقصّ الصورة تلقائياً إلى مربع وتُضغط قبل الرفع.
        </p>
        <input ref={inputRef} type="file" accept="image/jpeg,image/png,image/webp" className="hidden" onChange={onPick} disabled={busy} />
        <button type="button" className="btn-secondary mt-4" onClick={() => inputRef.current?.click()} disabled={busy}>
          <Camera className="size-4" aria-hidden="true" />
          اختيار صورة من الجهاز
        </button>
      </div>

      {error ? <p className="mt-4 rounded-xl bg-[var(--danger-soft)] p-3 text-center text-sm font-bold text-[var(--danger)]">{error}</p> : null}
      {done ? (
        <p className="mt-4 flex items-center justify-center gap-2 text-sm font-black text-[var(--info)]">
          <CheckCircle2 className="size-4" aria-hidden="true" />
          تم تحديث الصورة بنجاح
        </p>
      ) : null}

      <div className="mt-6 flex gap-3">
        <button className="btn-secondary flex-1" onClick={onClose} disabled={busy}>
          إلغاء
        </button>
        <button className="btn-primary flex-1" onClick={() => void save()} disabled={busy || !preparedRef.current || done}>
          {busy && <Loader2 className="size-4 animate-spin" aria-hidden="true" />}
          حفظ الصورة
        </button>
      </div>
    </DialogOverlay>
  );
}
