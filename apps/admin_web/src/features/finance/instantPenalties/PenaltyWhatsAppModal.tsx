import { CheckCircle2, Copy, MessageCircle } from 'lucide-react';
import { cairoTodayIso } from '../../../core/cairoTime';
import { openWhatsApp } from '../../../core/whatsappShare';
import { DialogOverlay } from '../../../ui/DialogOverlay';
import { UserAvatar } from '../../../ui/UserAvatar';
import type { InstantPenalty } from '../useInstantPenalties';
import { fmtLateDisplay, formatCurrency, generateEmployeePenaltyWhatsAppText } from './penaltyFormatters';

export interface WhatsAppEmployeeInfo {
  id: string;
  fullNameAr?: string | null;
  department?: string | null;
  phoneE164?: string | null;
  photoUrl?: string | null;
}

interface PenaltyWhatsAppModalProps {
  open: boolean;
  selectedPenalties: InstantPenalty[];
  employees?: WhatsAppEmployeeInfo[];
  employeePhotoMap: Map<string, string | null>;
  sentWhatsAppIds: Set<string>;
  onMarkSent: (penaltyId: string) => void;
  onNotify: (message: string) => void;
  onClose: () => void;
}

export function PenaltyWhatsAppModal({
  open,
  selectedPenalties,
  employees,
  employeePhotoMap,
  sentWhatsAppIds,
  onMarkSent,
  onNotify,
  onClose,
}: PenaltyWhatsAppModalProps) {
  if (!open || selectedPenalties.length === 0) return null;

  const nextUnsent = selectedPenalties.find((p) => !sentWhatsAppIds.has(p.id));

  return (
    <DialogOverlay
      title={`إرسال تنبيهات واتساب المخصصة (${selectedPenalties.length} ${selectedPenalties.length <= 10 ? 'غرامات' : 'غرامة'})`}
      onClose={onClose}
      maxWidth="max-w-3xl"
    >
      <div className="space-y-4 max-h-[75vh] overflow-y-auto px-1">
        {/* بطاقة التوجيه والإحصائيات العلوية */}
        <div className="rounded-xl border border-emerald-500/30 bg-emerald-500/10 p-3.5 space-y-2.5">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <div className="flex items-center gap-2">
              <MessageCircle className="size-5 text-emerald-600 dark:text-emerald-400 shrink-0" />
              <span className="text-xs sm:text-sm font-bold text-emerald-950 dark:text-emerald-200">
                تم إنشاء رسالة مخصصة لكل موظف باسمه وتاريخ وسبب غرامته
              </span>
            </div>
            <div className="flex items-center gap-2">
              <button
                type="button"
                onClick={() => {
                  const summaryLines = [
                    `📊 *كشف غرامات الحضور المحددة — جمعية أحلى شباب*`,
                    `📅 التاريخ: ${cairoTodayIso()}`,
                    `👥 إجمالي الموظفين: ${selectedPenalties.length}`,
                    `💰 إجمالي المبالغ: ${formatCurrency(selectedPenalties.reduce((s, p) => s + p.currentAmount, 0))}`,
                    ``,
                    ...selectedPenalties.map((p, i) => {
                      const emp = employees?.find((e) => e.id === p.employeeId);
                      const name = p.employeeName ?? emp?.fullNameAr ?? 'موظف';
                      return `${i + 1}) *${name}* (${p.departmentName ?? '—'}) — ${formatCurrency(p.currentAmount)} (${fmtLateDisplay(p.lateMinutes)} تأخير)`;
                    }),
                    ``,
                    `🤝 تودع جميع المبالغ بصندوق الزمالة والتكافل لدعم الزملاء.`,
                  ];
                  navigator.clipboard.writeText(summaryLines.join('\n'));
                  onNotify('تم نسخ الكشف المجمع بنجاح');
                }}
                className="btn-secondary text-xs !py-1 !px-2.5 flex items-center gap-1 font-bold cursor-pointer"
                title="نسخ كشف ملخص بكافة الموظفين المحددين لمشاركته في جروب الإدارة"
              >
                <Copy className="size-3.5" />
                <span>نسخ كشف مجمع</span>
              </button>
              {nextUnsent && (
                <button
                  type="button"
                  onClick={() => {
                    const emp = employees?.find((e) => e.id === nextUnsent.employeeId);
                    const empName = nextUnsent.employeeName ?? emp?.fullNameAr ?? 'الزميل العزيز';
                    const msg = generateEmployeePenaltyWhatsAppText(nextUnsent, empName);
                    openWhatsApp(msg, emp?.phoneE164);
                    onMarkSent(nextUnsent.id);
                  }}
                  className="btn-primary text-xs !py-1 !px-3 flex items-center gap-1.5 font-bold cursor-pointer"
                >
                  <MessageCircle className="size-3.5" />
                  <span>إرسال التالي: {nextUnsent.employeeName?.split(' ')[0] ?? 'الموظف'} 💬</span>
                </button>
              )}
            </div>
          </div>

          {/* شريط الإنجاز لعدد الرسائل المفتوحة */}
          <div className="flex items-center justify-between text-xs font-semibold text-emerald-800 dark:text-emerald-300 pt-1 border-t border-emerald-500/20">
            <span>
              حالة الإرسال: {sentWhatsAppIds.size} من {selectedPenalties.length} تم فتح محادثاتهم
            </span>
            {sentWhatsAppIds.size === selectedPenalties.length && (
              <span className="text-emerald-700 dark:text-emerald-400 font-bold flex items-center gap-1">
                <CheckCircle2 className="size-3.5" /> تم إرسال كافة التنبيهات بنجاح
              </span>
            )}
          </div>
        </div>

        {/* قائمة كروت الموظفين المحددين */}
        <div className="space-y-3">
          {selectedPenalties.map((p) => {
            const emp = employees?.find((e) => e.id === p.employeeId);
            const empName = p.employeeName ?? emp?.fullNameAr ?? 'الزميل العزيز';
            const phone = emp?.phoneE164 ?? null;
            const msgText = generateEmployeePenaltyWhatsAppText(p, empName);
            const isSent = sentWhatsAppIds.has(p.id);

            return (
              <div
                key={p.id}
                className={`rounded-xl border p-3.5 space-y-2.5 transition-all ${
                  isSent
                    ? 'border-emerald-500/40 bg-emerald-500/5 dark:bg-emerald-950/20 shadow-xs'
                    : 'border-[var(--border)] bg-[var(--surface)] hover:border-[var(--border-strong)]'
                }`}
              >
                {/* الرأس: اسم الموظف والتفاصيل */}
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div className="flex items-center gap-2.5 min-w-0">
                    <UserAvatar displayName={empName} photoUrl={emp?.photoUrl ?? employeePhotoMap.get(p.employeeId)} size="sm" announceName={false} />
                    <div className="min-w-0">
                      <div className="flex items-center gap-2">
                        <span className="font-bold text-sm text-[var(--text-primary)] truncate">{empName}</span>
                        {isSent && (
                          <span className="inline-flex items-center gap-1 text-[10px] font-bold text-emerald-700 dark:text-emerald-300 bg-emerald-500/15 px-2 py-0.5 rounded-full border border-emerald-500/30">
                            <CheckCircle2 className="size-3" /> تم الإرسال
                          </span>
                        )}
                      </div>
                      <div className="flex items-center gap-2 text-[11px] text-[var(--text-muted)] mt-0.5">
                        <span>{p.departmentName ?? emp?.department ?? '—'}</span>
                        {phone ? (
                          <span className="font-mono text-[var(--text-secondary)]">
                            <bdi dir="ltr">{phone}</bdi>
                          </span>
                        ) : (
                          <span className="text-amber-600 dark:text-amber-400 font-semibold">(لا يوجد رقم مسجل)</span>
                        )}
                      </div>
                    </div>
                  </div>

                  <div className="flex items-center gap-2">
                    <span className="font-mono font-bold text-xs bg-[var(--surface-muted)] px-2 py-1 rounded-md border border-[var(--border-subtle)]">
                      {formatCurrency(p.currentAmount)}
                    </span>
                    <span className="text-xs text-[var(--text-secondary)] font-medium">{fmtLateDisplay(p.lateMinutes)}</span>
                  </div>
                </div>

                {/* صندوق معاينة الرسالة المخصصة */}
                <div className="rounded-lg bg-[var(--surface-muted)]/70 border border-[var(--border-subtle)] p-2.5 text-xs text-[var(--text-secondary)] font-sans leading-relaxed whitespace-pre-wrap select-all max-h-32 overflow-y-auto">
                  {msgText}
                </div>

                {/* أزرار الإجراء الخاصة بهذا الموظف */}
                <div className="flex items-center justify-end gap-2 pt-1 border-t border-[var(--border-subtle)]">
                  <button
                    type="button"
                    onClick={() => {
                      navigator.clipboard.writeText(msgText);
                      onNotify(`تم نسخ رسالة ${empName}`);
                    }}
                    className="btn-secondary text-xs !py-1 !px-2.5 flex items-center gap-1 font-medium cursor-pointer"
                  >
                    <Copy className="size-3" />
                    <span>نسخ النص</span>
                  </button>
                  <button
                    type="button"
                    onClick={() => {
                      openWhatsApp(msgText, phone);
                      onMarkSent(p.id);
                    }}
                    className="inline-flex items-center gap-1.5 rounded-lg px-3 py-1 text-xs font-bold text-white bg-emerald-600 hover:bg-emerald-700 shadow-xs transition-all active:scale-95 cursor-pointer"
                  >
                    <MessageCircle className="size-3.5" />
                    <span>{isSent ? 'إعادة الإرسال واتساب 💬' : 'إرسال واتساب 💬'}</span>
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </DialogOverlay>
  );
}
