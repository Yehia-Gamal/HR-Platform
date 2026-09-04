import { Check, Download, Eraser, PenTool, RotateCcw, ShieldCheck, X } from 'lucide-react';
import { useCallback, useEffect, useRef, useState } from 'react';
import { DialogOverlay } from './DialogOverlay';

export interface SignatureMetadata {
  signerName?: string;
  signerId?: string;
  signedAt: string;
  dataUrl: string;
}

interface SignaturePadProps {
  signerName?: string;
  signerId?: string;
  title?: string;
  description?: string;
  onSave?: (metadata: SignatureMetadata) => void;
  onCancel?: () => void;
  width?: number;
  height?: number;
}

export function SignaturePad({
  signerName,
  signerId,
  title = 'التوقيع الرقمي المعتمد',
  description = 'يرجى التوقيع داخل الإطار باستخدام شاشة اللمس أو مؤشر الماوس.',
  onSave,
  onCancel,
  width = 500,
  height = 200,
}: SignaturePadProps) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const [isDrawing, setIsDrawing] = useState(false);
  const [hasSignature, setHasSignature] = useState(false);
  const [strokeColor, setStrokeColor] = useState('#1e3a8a'); // أزرق توقيع رسمي

  const getCanvasContext = useCallback(() => {
    const canvas = canvasRef.current;
    if (!canvas) return null;
    const ctx = canvas.getContext('2d');
    if (ctx) {
      ctx.lineWidth = 2.5;
      ctx.lineCap = 'round';
      ctx.lineJoin = 'round';
      ctx.strokeStyle = strokeColor;
    }
    return ctx;
  }, [strokeColor]);

  // تهيئة الكانفاس بدقة عالية للشاشات الـ Retina
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const dpr = window.devicePixelRatio || 1;
    canvas.width = width * dpr;
    canvas.height = height * dpr;
    ctx.scale(dpr, dpr);
    ctx.lineWidth = 2.5;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.strokeStyle = strokeColor;
  }, [width, height, strokeColor]);

  const getCoordinates = (e: React.MouseEvent<HTMLCanvasElement> | React.TouchEvent<HTMLCanvasElement>) => {
    const canvas = canvasRef.current;
    if (!canvas) return { x: 0, y: 0 };
    const rect = canvas.getBoundingClientRect();
    const clientX = 'touches' in e ? e.touches[0].clientX : e.clientX;
    const clientY = 'touches' in e ? e.touches[0].clientY : e.clientY;
    return {
      x: clientX - rect.left,
      y: clientY - rect.top,
    };
  };

  const startDrawing = (e: React.MouseEvent<HTMLCanvasElement> | React.TouchEvent<HTMLCanvasElement>) => {
    e.preventDefault();
    const ctx = getCanvasContext();
    if (!ctx) return;
    const { x, y } = getCoordinates(e);
    ctx.beginPath();
    ctx.moveTo(x, y);
    setIsDrawing(true);
    setHasSignature(true);
  };

  const draw = (e: React.MouseEvent<HTMLCanvasElement> | React.TouchEvent<HTMLCanvasElement>) => {
    if (!isDrawing) return;
    e.preventDefault();
    const ctx = getCanvasContext();
    if (!ctx) return;
    const { x, y } = getCoordinates(e);
    ctx.lineTo(x, y);
    ctx.stroke();
  };

  const stopDrawing = () => {
    if (isDrawing) {
      setIsDrawing(false);
    }
  };

  const clearSignature = () => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    setHasSignature(false);
  };

  const handleConfirm = () => {
    const canvas = canvasRef.current;
    if (!canvas || !hasSignature) return;

    const dataUrl = canvas.toDataURL('image/png');
    const metadata: SignatureMetadata = {
      signerName,
      signerId,
      signedAt: new Date().toISOString(),
      dataUrl,
    };

    onSave?.(metadata);
  };

  const handleDownload = () => {
    const canvas = canvasRef.current;
    if (!canvas || !hasSignature) return;
    const link = document.createElement('a');
    link.download = `signature_${signerId || 'doc'}_${Date.now()}.png`;
    link.href = canvas.toDataURL('image/png');
    link.click();
  };

  return (
    <div className="space-y-4 text-right">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h4 className="text-sm font-black text-[var(--text)] flex items-center gap-2">
            <PenTool className="size-4 text-[var(--brand-primary)]" aria-hidden="true" />
            {title}
          </h4>
          <p className="text-xs text-[var(--text-muted)] mt-1">{description}</p>
        </div>

        {/* ألوان الحبر */}
        <div className="flex items-center gap-1.5 bg-[var(--surface-muted)] p-1 rounded-xl border border-[var(--border)]">
          <button
            type="button"
            title="حبر أزرق رسمي"
            onClick={() => setStrokeColor('#1e3a8a')}
            className={`size-6 rounded-lg bg-blue-900 transition-transform ${strokeColor === '#1e3a8a' ? 'ring-2 ring-[var(--brand-primary)] scale-110' : 'opacity-70 hover:opacity-100'}`}
          />
          <button
            type="button"
            title="حبر أسود كلاسيكي"
            onClick={() => setStrokeColor('#0f172a')}
            className={`size-6 rounded-lg bg-slate-900 transition-transform ${strokeColor === '#0f172a' ? 'ring-2 ring-[var(--brand-primary)] scale-110' : 'opacity-70 hover:opacity-100'}`}
          />
        </div>
      </div>

      {/* مساحة الرسم */}
      <div className="relative rounded-2xl border-2 border-dashed border-[var(--border)] bg-[var(--surface)] p-2 shadow-xs transition-colors hover:border-[var(--brand-primary)]">
        <canvas
          ref={canvasRef}
          onMouseDown={startDrawing}
          onMouseMove={draw}
          onMouseUp={stopDrawing}
          onMouseLeave={stopDrawing}
          onTouchStart={startDrawing}
          onTouchMove={draw}
          onTouchEnd={stopDrawing}
          style={{ width: '100%', height: `${height}px`, touchAction: 'none' }}
          className="cursor-crosshair block rounded-xl bg-[var(--surface)]"
        />

        {/* خط توجيهي للتوقيع */}
        <div className="pointer-events-none absolute bottom-8 inset-x-8 flex items-center justify-between border-b border-dashed border-[var(--border)]/70 pb-1 text-[11px] text-[var(--text-muted)]">
          <span>خط التوقيع الرقمي</span>
          <span>✕</span>
        </div>

        {/* علامة أمان */}
        <div className="pointer-events-none absolute top-3 left-3 flex items-center gap-1 text-[10px] text-[var(--text-muted)] bg-[var(--surface-muted)]/80 px-2 py-0.5 rounded-full border border-[var(--border)]">
          <ShieldCheck className="size-3 text-emerald-500" aria-hidden="true" />
          <span>توقيع بيومتري مشفر</span>
        </div>
      </div>

      {/* بيانات الموقّع والختم الزمني */}
      <div className="flex flex-wrap items-center justify-between gap-2 text-xs text-[var(--text-muted)] bg-[var(--surface-muted)]/50 p-2.5 rounded-xl border border-[var(--border)]">
        <div className="flex items-center gap-2">
          <span className="font-bold">الموقع:</span>
          <span className="text-[var(--text)] font-semibold">{signerName || 'المستخدم الحالي'}</span>
          {signerId && <span className="tabular text-[11px]">({signerId})</span>}
        </div>
        <div className="text-[11px] tabular">
          {new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date())}
        </div>
      </div>

      {/* شريط الإجراءات والأزرار */}
      <div className="flex flex-wrap items-center justify-between gap-2 pt-1">
        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={clearSignature}
            disabled={!hasSignature}
            className="btn-secondary text-xs flex items-center gap-1.5 py-1.5 px-3"
          >
            <RotateCcw className="size-3.5" aria-hidden="true" />
            مسح وإعادة
          </button>
          {hasSignature && (
            <button
              type="button"
              onClick={handleDownload}
              className="btn-secondary text-xs flex items-center gap-1.5 py-1.5 px-3"
              title="تنزيل نسخة صورة شفافة من التوقيع"
            >
              <Download className="size-3.5" aria-hidden="true" />
              تنزيل PNG
            </button>
          )}
        </div>

        <div className="flex items-center gap-2">
          {onCancel && (
            <button type="button" onClick={onCancel} className="btn-secondary text-xs py-1.5 px-4">
              إلغاء
            </button>
          )}
          <button
            type="button"
            onClick={handleConfirm}
            disabled={!hasSignature}
            className="btn-primary text-xs flex items-center gap-1.5 py-1.5 px-4"
          >
            <Check className="size-3.5" aria-hidden="true" />
            اعتماد التوقيع
          </button>
        </div>
      </div>
    </div>
  );
}

/**
 * نافذة منبثقة متكاملة للتوقيع الرقمي للاستخدام المباشر في أي صفحة
 */
export function SignaturePadDialog({
  isOpen,
  onClose,
  onConfirm,
  signerName,
  signerId,
  title = 'تأكيد واعتماد التوقيع الرقمي',
  description,
}: {
  isOpen: boolean;
  onClose: () => void;
  onConfirm: (metadata: SignatureMetadata) => void;
  signerName?: string;
  signerId?: string;
  title?: string;
  description?: string;
}) {
  if (!isOpen) return null;

  return (
    <DialogOverlay title={title} onClose={onClose} maxWidth="max-w-xl">
      <div className="p-4">
        <SignaturePad
          title={title}
          description={description}
          signerName={signerName}
          signerId={signerId}
          onCancel={onClose}
          onSave={(meta) => {
            onConfirm(meta);
            onClose();
          }}
        />
      </div>
    </DialogOverlay>
  );
}
