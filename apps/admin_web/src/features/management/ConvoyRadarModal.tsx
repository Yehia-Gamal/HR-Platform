import React, { useState } from 'react';
import {
  BusFront,
  CheckCircle2,
  Clock,
  Flag,
  MapPin,
  MessageCircle,
  Package,
  Plus,
  Radio,
  Send,
  Sparkles,
  Users,
  X,
} from 'lucide-react';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { openWhatsApp } from '../../core/whatsappShare';
import {
  ConvoyCheckpoint,
  ConvoyRadarData,
  formatConvoyWhatsAppBroadcast,
  generateDefaultCheckpoints,
} from './convoyRadarTypes';

export function ConvoyRadarModal({
  convoy,
  onClose,
}: {
  convoy: {
    id: string;
    name: string;
    employeeName: string;
    origin: string;
    destination: string;
    departureAt: string | null;
    passengers: number;
    vehicles: number;
    status: string;
  };
  onClose: () => void;
}) {
  const [aidType, setAidType] = useState<string>('كراتين مواد غذائية وبطاطين');
  const [targetAid, setTargetAid] = useState<number>(250);
  const [deliveredAid, setDeliveredAid] = useState<number>(145);
  const [checkpoints, setCheckpoints] = useState<ConvoyCheckpoint[]>(() =>
    generateDefaultCheckpoints(convoy.destination || 'القرية المستهدفة'),
  );

  const [activeNoteInputId, setActiveNoteInputId] = useState<string | null>(null);
  const [noteText, setNoteText] = useState<string>('');

  const percent = targetAid > 0 ? Math.min(100, Math.round((deliveredAid / targetAid) * 100)) : 0;

  const currentRadar: ConvoyRadarData = {
    id: convoy.id,
    name: convoy.name,
    origin: convoy.origin,
    destination: convoy.destination,
    responsibleName: convoy.employeeName,
    status: convoy.status,
    departureAt: convoy.departureAt || '',
    passengers: convoy.passengers,
    vehicles: convoy.vehicles,
    aidType,
    targetAid,
    deliveredAid,
    checkpoints,
  };

  function handleAdvanceCheckpoint(id: string, newStatus: 'in_progress' | 'completed') {
    const nowTime = new Intl.DateTimeFormat('ar-EG-u-nu-latn', {
      timeStyle: 'short',
    }).format(new Date());

    setCheckpoints((prev) =>
      prev.map((c) => {
        if (c.id === id) {
          return {
            ...c,
            status: newStatus,
            time: nowTime,
          };
        }
        return c;
      }),
    );
  }

  function handleSaveNote(id: string) {
    if (!noteText.trim()) return;
    setCheckpoints((prev) =>
      prev.map((c) => {
        if (c.id === id) {
          return {
            ...c,
            notes: noteText.trim(),
          };
        }
        return c;
      }),
    );
    setActiveNoteInputId(null);
    setNoteText('');
  }

  function handleAddDelivered(amount: number) {
    setDeliveredAid((prev) => Math.min(targetAid, Math.max(0, prev + amount)));
  }

  function handleBroadcastWhatsApp() {
    const text = formatConvoyWhatsAppBroadcast(currentRadar);
    openWhatsApp(text);
  }

  return (
    <DialogOverlay
      title={`رادار القافلة الميداني — ${convoy.name}`}
      onClose={onClose}
      maxWidth="max-w-2xl"
    >
      <div className="space-y-5" dir="rtl">
        {/* Header Summary */}
        <div className="rounded-2xl border border-brand/20 bg-brand/5 p-4 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
          <div className="flex items-center gap-3">
            <div className="flex h-11 w-11 items-center justify-center rounded-xl bg-brand/10 text-brand font-bold">
              <BusFront className="size-6" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h3 className="font-black text-sm text-[var(--text-primary)]">{convoy.name}</h3>
                <span className="inline-flex items-center gap-1 rounded-full bg-emerald-500/15 text-emerald-600 dark:text-emerald-400 px-2 py-0.5 text-[10px] font-black animate-pulse">
                  <Radio className="size-3" />
                  مباشر
                </span>
              </div>
              <p className="text-xs text-[var(--text-muted)] mt-0.5">
                المسؤول: <strong>{convoy.employeeName}</strong> · المسار: {convoy.origin} ← {convoy.destination}
              </p>
            </div>
          </div>

          <button
            type="button"
            onClick={handleBroadcastWhatsApp}
            className="inline-flex items-center justify-center gap-1.5 rounded-xl border border-emerald-500/30 bg-emerald-500/10 px-3 py-2 text-xs font-bold text-emerald-700 dark:text-emerald-300 hover:bg-emerald-500/20 transition-colors shadow-sm shrink-0"
            title="بث تقرير المحطات الحالي لمجموعات واتساب الجمعية"
          >
            <MessageCircle className="size-4" />
            <span>بث لجروب الواتساب</span>
          </button>
        </div>

        {/* Aid Distribution Progress Card */}
        <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface-card)] p-4 space-y-3">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Package className="size-4 text-brand" />
              <span className="text-xs font-bold text-[var(--text-primary)]">
                نسبة توزيع المساعدات ({aidType})
              </span>
            </div>
            <span className="text-xs font-black text-brand">{percent}% مكتمل</span>
          </div>

          <div className="h-2.5 w-full rounded-full bg-[var(--surface-muted)] overflow-hidden">
            <div
              className="h-full rounded-full bg-brand transition-all duration-500"
              style={{ width: `${percent}%` }}
            />
          </div>

          <div className="flex flex-wrap items-center justify-between gap-2 pt-1 text-xs">
            <span className="text-[var(--text-muted)]">
              المنفذ حتى الآن: <strong className="text-emerald-600 dark:text-emerald-400 font-bold">{deliveredAid}</strong> من{' '}
              <strong>{targetAid}</strong>
            </span>
            <div className="flex items-center gap-1.5">
              <span className="text-[11px] text-[var(--text-muted)]">تحديث سريع:</span>
              <button
                type="button"
                onClick={() => handleAddDelivered(5)}
                className="rounded-lg border border-[var(--border)] bg-[var(--surface-raised)] px-2 py-0.5 text-[11px] font-bold hover:bg-[var(--surface-muted)]"
              >
                +5
              </button>
              <button
                type="button"
                onClick={() => handleAddDelivered(20)}
                className="rounded-lg border border-[var(--border)] bg-[var(--surface-raised)] px-2 py-0.5 text-[11px] font-bold hover:bg-[var(--surface-muted)]"
              >
                +20
              </button>
              <button
                type="button"
                onClick={() => handleAddDelivered(50)}
                className="rounded-lg border border-[var(--border)] bg-[var(--surface-raised)] px-2 py-0.5 text-[11px] font-bold hover:bg-[var(--surface-muted)]"
              >
                +50
              </button>
            </div>
          </div>
        </div>

        {/* Checkpoint Timeline */}
        <div className="space-y-2">
          <div className="flex items-center justify-between">
            <h4 className="text-xs font-black text-[var(--text-primary)]">محطات ومسار القافلة الميدانية</h4>
            <span className="text-[11px] text-[var(--text-muted)]">
              {checkpoints.filter((c) => c.status === 'completed').length} من {checkpoints.length} محطات أُنجزت
            </span>
          </div>

          <div className="space-y-3">
            {checkpoints.map((cp, idx) => {
              const isCompleted = cp.status === 'completed';
              const isInProgress = cp.status === 'in_progress';
              const isPending = cp.status === 'pending';

              return (
                <div
                  key={cp.id}
                  className={`rounded-2xl border p-3.5 transition-all ${
                    isInProgress
                      ? 'border-brand/40 bg-brand/5 shadow-sm'
                      : isCompleted
                        ? 'border-emerald-500/20 bg-emerald-500/5'
                        : 'border-[var(--border)] bg-[var(--surface-card)] opacity-75'
                  }`}
                >
                  <div className="flex items-start justify-between gap-2">
                    <div className="flex items-start gap-2.5">
                      <div
                        className={`mt-0.5 flex h-6 w-6 shrink-0 items-center justify-center rounded-full text-xs font-black ${
                          isCompleted
                            ? 'bg-emerald-500 text-white'
                            : isInProgress
                              ? 'bg-brand text-white animate-pulse'
                              : 'bg-[var(--surface-muted)] text-[var(--text-muted)]'
                        }`}
                      >
                        {isCompleted ? <CheckCircle2 className="size-4" /> : idx + 1}
                      </div>
                      <div>
                        <div className="flex items-center gap-2">
                          <h5 className="font-bold text-xs text-[var(--text-primary)]">{cp.title}</h5>
                          {cp.time ? (
                            <span className="text-[10px] text-[var(--text-muted)] font-mono">({cp.time})</span>
                          ) : null}
                        </div>
                        {cp.notes ? (
                          <p className="mt-1 text-[11px] text-[var(--text-muted)] leading-relaxed">
                            {cp.notes}
                          </p>
                        ) : null}
                      </div>
                    </div>

                    <div className="flex items-center gap-1.5 shrink-0">
                      {isPending && (
                        <button
                          type="button"
                          onClick={() => handleAdvanceCheckpoint(cp.id, 'in_progress')}
                          className="rounded-lg border border-brand/30 bg-brand/10 px-2 py-1 text-[11px] font-bold text-brand hover:bg-brand/20 transition-colors"
                        >
                          بدء المحطة
                        </button>
                      )}
                      {isInProgress && (
                        <button
                          type="button"
                          onClick={() => handleAdvanceCheckpoint(cp.id, 'completed')}
                          className="rounded-lg border border-emerald-500/30 bg-emerald-500/10 px-2 py-1 text-[11px] font-bold text-emerald-600 dark:text-emerald-400 hover:bg-emerald-500/20 transition-colors"
                        >
                          إتمام المحطة ✓
                        </button>
                      )}
                      <button
                        type="button"
                        onClick={() => {
                          setActiveNoteInputId(activeNoteInputId === cp.id ? null : cp.id);
                          setNoteText(cp.notes || '');
                        }}
                        className="rounded-lg border border-[var(--border)] px-2 py-1 text-[11px] text-[var(--text-muted)] hover:text-[var(--text-primary)]"
                        title="إضافة ملاحظة ميدانية"
                      >
                        ملاحظة
                      </button>
                    </div>
                  </div>

                  {activeNoteInputId === cp.id && (
                    <div className="mt-3 flex items-center gap-2 border-t border-[var(--border)] pt-2.5">
                      <input
                        type="text"
                        placeholder="اكتب ملاحظة ميدانية توثيقية..."
                        value={noteText}
                        onChange={(e) => setNoteText(e.target.value)}
                        className="input text-xs flex-1 h-8"
                      />
                      <button
                        type="button"
                        onClick={() => handleSaveNote(cp.id)}
                        className="btn-primary text-xs px-3 py-1.5 h-8 shrink-0"
                      >
                        حفظ
                      </button>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </DialogOverlay>
  );
}
