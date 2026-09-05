import type { AttendanceStatementDay } from '@ahla/shared-contracts';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import {
  AlertCircle,
  Briefcase,
  Calendar,
  CheckCircle2,
  Clock,
  Compass,
  HeartHandshake,
  Pencil,
  RotateCcw,
  Send,
  Sparkles,
  Sun,
  Umbrella,
  XCircle,
} from 'lucide-react';
import { useEffect, useId, useState } from 'react';
import { rpc } from '../../core/rpc';
import { safeErrorMessage } from '../../core/errorMapper';
import { DialogOverlay } from '../../ui/DialogOverlay';

interface DayTypeConfig {
  key: string;
  label: string;
  desc: string;
  icon: typeof Briefcase;
  color: string;
  bgColor: string;
}

const DAY_TYPE_CONFIGS: DayTypeConfig[] = [
  {
    key: 'work',
    label: 'يوم عمل (حاضر)',
    desc: 'تسجيل أو تعديل ساعات وأوقات الحضور والانصراف',
    icon: Briefcase,
    color: 'text-emerald-700 dark:text-emerald-300',
    bgColor: 'bg-emerald-50 dark:bg-emerald-950/40 border-emerald-300 dark:border-emerald-800',
  },
  {
    key: 'leave',
    label: 'إجازة معتمدة',
    desc: 'سنوية، عارضة، مرضية، أو بدون راتب',
    icon: Umbrella,
    color: 'text-indigo-700 dark:text-indigo-300',
    bgColor: 'bg-indigo-50 dark:bg-indigo-950/40 border-indigo-300 dark:border-indigo-800',
  },
  {
    key: 'mission',
    label: 'مأمورية عمل',
    desc: 'مهمة رسمية ميدانية أو إدارية',
    icon: Compass,
    color: 'text-sky-700 dark:text-sky-300',
    bgColor: 'bg-sky-50 dark:bg-sky-950/40 border-sky-300 dark:border-sky-800',
  },
  {
    key: 'convoy',
    label: 'قافلة خيرية',
    desc: 'مشاركة في قوافل الإغاثة والتوعية',
    icon: HeartHandshake,
    color: 'text-purple-700 dark:text-purple-300',
    bgColor: 'bg-purple-50 dark:bg-purple-950/40 border-purple-300 dark:border-purple-800',
  },
  {
    key: 'fundraising',
    label: 'فاندي (جمع تبرعات)',
    desc: 'يوم مشاركة في حملات جمع التبرعات',
    icon: Sparkles,
    color: 'text-violet-700 dark:text-violet-300',
    bgColor: 'bg-violet-50 dark:bg-violet-950/40 border-violet-300 dark:border-violet-800',
  },
  {
    key: 'rest',
    label: 'راحة أسبوعية',
    desc: 'يوم عطلة وراحة مجدولة للموظف',
    icon: Sun,
    color: 'text-slate-700 dark:text-slate-300',
    bgColor: 'bg-slate-50 dark:bg-slate-900/40 border-slate-300 dark:border-slate-800',
  },
  {
    key: 'holiday',
    label: 'عطلة رسمية',
    desc: 'إجازة رسمية معتمدة للدولة/المؤسسة',
    icon: Calendar,
    color: 'text-amber-700 dark:text-amber-300',
    bgColor: 'bg-amber-50 dark:bg-amber-950/40 border-amber-300 dark:border-amber-800',
  },
  {
    key: 'absent',
    label: 'غياب إداري',
    desc: 'تسجيل أو تأكيد غياب غير مبرر مع الخصم',
    icon: XCircle,
    color: 'text-rose-700 dark:text-rose-300',
    bgColor: 'bg-rose-50 dark:bg-rose-950/40 border-rose-300 dark:border-rose-800',
  },
];

const LEAVE_TYPES = [
  ['annual', 'إجازة سنوية (اعتيادية)'],
  ['casual', 'إجازة عارضة'],
  ['sick', 'إجازة مرضية'],
  ['unpaid', 'إجازة بدون راتب'],
  ['weekly_rest_comp', 'بدل راحة أسبوعية (لا تُخصم من الرصيد)'],
] as const;

const DEFAULT_LEAVE_TYPE: Record<string, string> = {
  leave: 'annual',
  absent: 'unpaid',
};

const QUICK_HOURS_PRESETS = [
  { label: 'دوام كامل (8 ساعات)', in: '09:00', out: '17:00' },
  { label: 'دوام مبكر (8 ساعات)', in: '08:00', out: '16:00' },
  { label: 'نصف دوام (4 ساعات)', in: '09:00', out: '13:00' },
  { label: 'دوام ممتد (10 ساعات)', in: '08:00', out: '18:00' },
];

const PRESET_REASONS: Record<string, string[]> = {
  work: ['تعديل ساعات العمل المعتمدة', 'تصحيح وقت الحضور والانصراف', 'إضافة بصمة منسية', 'دوام كامل معتمد'],
  leave: ['إجازة اعتيادية معتمدة', 'إجازة مرضية بتقرير طبي', 'إجازة طارئة بموافقة الإدارة', 'إجازة معتمدة بأثر رجعي'],
  mission: ['مأمورية عمل ميدانية', 'مأمورية إدارية رسمية', 'انتداب رسمي خارج المقر'],
  convoy: ['مشاركة في قافلة خيرية', 'حملة توعية ميدانية'],
  fundraising: ['مشاركة في فاندي جمع تبرعات'],
  holiday: ['عطلة رسمية بالدولة', 'إجازة رسمية معتمدة'],
  rest: ['راحة أسبوعية معتمدة', 'تبديل يوم راحة'],
  absent: ['تأكيد غياب بدون إذن', 'غياب غير مبرر'],
};

export function AttendanceDayEditor({ employeeId, day }: { employeeId: string; day: AttendanceStatementDay }) {
  const queryClient = useQueryClient();
  const [open, setOpen] = useState(false);
  const [markOpen, setMarkOpen] = useState(false);

  const [dayType, setDayType] = useState<string>((day.adminOverride?.dayType as string | undefined) ?? 'work');
  const [leaveType, setLeaveType] = useState<string>(
    day.adminOverride?.leaveType ?? (day.adminOverride?.dayType === 'leave' || day.adminOverride?.dayType === 'absent' ? DEFAULT_LEAVE_TYPE[day.adminOverride.dayType] : 'annual'),
  );
  const [checkIn, setCheckIn] = useState(day.checkIn?.slice(0, 5) ?? '09:00');
  const [checkOut, setCheckOut] = useState(day.checkOut?.slice(0, 5) ?? '17:00');
  const [clearCheckIn, setClearCheckIn] = useState(false);
  const [clearCheckOut, setClearCheckOut] = useState(false);
  const [reason, setReason] = useState(day.adminOverride?.reason ?? 'تعديل ساعات وحضور معتمد');
  const [notes, setNotes] = useState(day.adminOverride?.notes ?? '');

  // طلب تحديد يوم
  const [markType, setMarkType] = useState<string>('mission');
  const [markReason, setMarkReason] = useState('طلب تحديد يوم معتمد');
  const [markLocation, setMarkLocation] = useState('');

  // إعادة ضبط الحقول عند تغيير اليوم
  useEffect(() => {
    const existingType = (day.adminOverride?.dayType as string | undefined) ?? 'work';
    setDayType(existingType);
    setLeaveType(
      day.adminOverride?.leaveType ?? (existingType === 'leave' || existingType === 'absent' ? DEFAULT_LEAVE_TYPE[existingType] : 'annual'),
    );
    setCheckIn(day.checkIn?.slice(0, 5) ?? '09:00');
    setCheckOut(day.checkOut?.slice(0, 5) ?? '17:00');
    setReason(day.adminOverride?.reason ?? 'تعديل ساعات وحضور معتمد');
    setNotes(day.adminOverride?.notes ?? '');
    setClearCheckIn(false);
    setClearCheckOut(false);
  }, [day]);

  // حفظ التعديل الإداري
  const saveMutation = useMutation({
    mutationFn: () =>
      rpc('set_employee_attendance_day_admin', {
        p_employee_id: employeeId,
        p_work_date: day.date,
        p_day_type: dayType,
        p_check_in: dayType === 'work' && !clearCheckIn ? checkIn : null,
        p_check_out: dayType === 'work' && !clearCheckOut ? checkOut : null,
        p_clear_check_in: dayType !== 'work' || clearCheckIn,
        p_clear_check_out: dayType !== 'work' || clearCheckOut,
        p_reason: reason.trim() || 'تعديل إداري معتمد',
        p_notes: notes.trim() || null,
        p_leave_type: dayType === 'leave' || dayType === 'absent' ? leaveType || DEFAULT_LEAVE_TYPE[dayType] : null,
      }),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['attendance-statement', employeeId] });
      setOpen(false);
    },
  });

  // إلغاء التعديل الإداري والعودة لاحتساب النظام الأصلي
  const clearMutation = useMutation({
    mutationFn: () =>
      rpc('clear_employee_attendance_day_admin', {
        p_employee_id: employeeId,
        p_work_date: day.date,
      }),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['attendance-statement', employeeId] });
      setOpen(false);
    },
  });

  // طلب تحديد يوم
  const markMutation = useMutation({
    mutationFn: () => {
      const isOperational = ['mission', 'convoy', 'fundraising'].includes(markType);
      return rpc('submit_employee_day_mark', {
        p_employee_id: employeeId,
        p_request_type: isOperational ? markType : 'leave',
        p_title: `تحديد يوم ${day.date}`,
        p_reason: markReason.trim() || 'تحديد يوم إداري',
        p_payload: {
          startDate: day.date,
          endDate: day.date,
          ...(isOperational ? { location: markLocation.trim() } : { leaveType: markType }),
          dayMark: true,
        },
      });
    },
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['attendance-statement', employeeId] });
      await queryClient.invalidateQueries({ queryKey: ['requests'] });
      setMarkOpen(false);
    },
  });

  // حساب ساعات العمل تقريبياً
  const calculatedHours = (() => {
    if (dayType !== 'work' || clearCheckIn || clearCheckOut || !checkIn || !checkOut) return null;
    const [inH, inM] = checkIn.split(':').map(Number);
    const [outH, outM] = checkOut.split(':').map(Number);
    if (isNaN(inH) || isNaN(inM) || isNaN(outH) || isNaN(outM)) return null;
    const totalMin = outH * 60 + outM - (inH * 60 + inM);
    if (totalMin <= 0) return null;
    return (totalMin / 60).toFixed(1);
  })();

  const clearCheckInId = useId();
  const clearCheckOutId = useId();

  return (
    <>
      <div className="flex items-center gap-1">
        <button
          type="button"
          className="inline-flex items-center gap-1 rounded-md px-2 py-1 text-xs font-bold transition hover:bg-[var(--surface-hover)]"
          onClick={() => setOpen(true)}
          title="تعديل حالة اليوم أو ساعات العمل"
        >
          <Pencil className="size-3.5 text-[var(--primary)]" aria-hidden="true" />
          <span>تعديل</span>
        </button>
        <button
          type="button"
          className="inline-flex items-center gap-1 rounded-md px-2 py-1 text-xs font-medium text-[var(--text-muted)] transition hover:bg-[var(--surface-hover)]"
          onClick={() => setMarkOpen(true)}
          title="إرسال طلب تحديد نوع اليوم (بموافقة المدير)"
        >
          <Send className="size-3 text-[var(--text-muted)]" aria-hidden="true" />
          <span>طلب تحديد</span>
        </button>
      </div>

      {open ? (
        <DialogOverlay title={`تعديل يوم ${day.dayNameAr} (${day.date})`} onClose={() => setOpen(false)} maxWidth="max-w-2xl">
          <div className="space-y-4 text-right">
            {/* إشعار وجود تعديل إداري سابق مع زر الإلغاء */}
            {day.adminOverride ? (
              <div className="flex flex-col gap-2 rounded-xl border border-amber-300 bg-amber-50/80 p-3.5 text-xs dark:border-amber-800/80 dark:bg-amber-950/30 sm:flex-row sm:items-center sm:justify-between">
                <div className="flex items-start gap-2 text-amber-900 dark:text-amber-200">
                  <AlertCircle className="mt-0.5 size-4 shrink-0 text-amber-600 dark:text-amber-400" />
                  <div>
                    <span className="font-bold">يوجد تعديل إداري مسجل لهذا اليوم: </span>
                    <span>
                      الحالة: <b>{day.adminOverride.dayType}</b>
                      {day.adminOverride.reason ? ` · السبب: ${day.adminOverride.reason}` : ''}
                    </span>
                  </div>
                </div>
                <button
                  type="button"
                  className="inline-flex items-center justify-center gap-1.5 rounded-lg border border-rose-200 bg-rose-50 px-2.5 py-1.5 text-xs font-bold text-rose-700 transition hover:bg-rose-100 dark:border-rose-800 dark:bg-rose-950/50 dark:text-rose-300 dark:hover:bg-rose-900/50"
                  disabled={clearMutation.isPending}
                  onClick={() => {
                    if (window.confirm('هل أنت متأكد من رغبتك في إلغاء التعديل الإداري والعودة لاحتساب النظام الأصلي؟')) {
                      clearMutation.mutate();
                    }
                  }}
                  title="حذف الاستثناء الإداري والعودة التلقائية لحسابات النظام"
                >
                  <RotateCcw className="size-3.5" />
                  <span>{clearMutation.isPending ? 'جارٍ الإلغاء…' : 'إلغاء التعديل والعودة للنظام'}</span>
                </button>
              </div>
            ) : null}

            {/* 1. اختيار نوع اليوم */}
            <div className="space-y-2">
              <label className="block text-xs font-bold text-[var(--text-secondary)]">اختر حالة اليوم الجديدة</label>
              <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
                {DAY_TYPE_CONFIGS.map((cfg) => {
                  const Icon = cfg.icon;
                  const isSelected = dayType === cfg.key;
                  return (
                    <button
                      key={cfg.key}
                      type="button"
                      onClick={() => {
                        setDayType(cfg.key);
                        if (cfg.key === 'leave' || cfg.key === 'absent') {
                          setLeaveType(DEFAULT_LEAVE_TYPE[cfg.key]);
                        }
                        const presets = PRESET_REASONS[cfg.key];
                        if (presets && presets.length > 0) {
                          setReason(presets[0]);
                        }
                      }}
                      className={`flex flex-col items-start gap-1 rounded-xl border p-2.5 text-right transition ${
                        isSelected
                          ? `${cfg.bgColor} ring-2 ring-[var(--primary)] shadow-sm`
                          : 'border-[var(--border)] bg-[var(--surface)] hover:bg-[var(--surface-hover)]'
                      }`}
                    >
                      <div className="flex w-full items-center justify-between">
                        <Icon className={`size-4 ${cfg.color}`} />
                        {isSelected ? <CheckCircle2 className="size-3.5 text-[var(--primary)]" /> : null}
                      </div>
                      <span className="text-xs font-bold leading-tight text-[var(--text-primary)]">{cfg.label}</span>
                    </button>
                  );
                })}
              </div>
            </div>

            {/* 2. تفاصيل الإجازة إن اختيرت */}
            {dayType === 'leave' || dayType === 'absent' ? (
              <div className="rounded-xl border border-[var(--border)] bg-[var(--surface-subtle)] p-3 space-y-1.5">
                <label className="block text-xs font-bold text-[var(--text-secondary)]">نوع الإجازة (يتم الخصم طبقاً للائحة)</label>
                <select className="input w-full" value={leaveType} onChange={(e) => setLeaveType(e.target.value)}>
                  {LEAVE_TYPES.map(([val, lbl]) => (
                    <option key={val} value={val}>
                      {lbl}
                    </option>
                  ))}
                </select>
              </div>
            ) : null}

            {/* 3. تفاصيل ساعات وأوقات العمل عند اختيار "يوم عمل" */}
            {dayType === 'work' ? (
              <div className="space-y-3 rounded-xl border border-[var(--border)] bg-[var(--surface-subtle)] p-3.5">
                <div className="flex items-center justify-between">
                  <span className="text-xs font-bold text-[var(--text-secondary)] flex items-center gap-1.5">
                    <Clock className="size-3.5 text-[var(--primary)]" />
                    ضبط ساعات وأوقات الدوام
                  </span>
                  {calculatedHours ? (
                    <span className="rounded-full bg-emerald-100 px-2 py-0.5 text-[11px] font-bold text-emerald-800 dark:bg-emerald-950 dark:text-emerald-300">
                      إجمالي العمل: {calculatedHours} ساعة
                    </span>
                  ) : null}
                </div>

                {/* أزرار سريعة لساعات العمل */}
                <div className="flex flex-wrap gap-1.5">
                  {QUICK_HOURS_PRESETS.map((p) => (
                    <button
                      key={p.label}
                      type="button"
                      className={`filter-chip ${checkIn === p.in && checkOut === p.out && !clearCheckIn && !clearCheckOut ? 'is-active' : ''}`}
                      onClick={() => {
                        setCheckIn(p.in);
                        setCheckOut(p.out);
                        setClearCheckIn(false);
                        setClearCheckOut(false);
                      }}
                    >
                      {p.label}
                    </button>
                  ))}
                </div>

                <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                  <div className="space-y-1">
                    <label className="text-xs font-bold text-[var(--text-secondary)]">وقت الحضور</label>
                    <input
                      type="time"
                      className="input w-full"
                      value={checkIn}
                      disabled={clearCheckIn}
                      onChange={(e) => setCheckIn(e.target.value)}
                    />
                    <label htmlFor={clearCheckInId} className="flex items-center gap-1.5 text-xs text-[var(--text-muted)] cursor-pointer">
                      <input
                        id={clearCheckInId}
                        type="checkbox"
                        checked={clearCheckIn}
                        onChange={(e) => setClearCheckIn(e.target.checked)}
                      />
                      <span>حذف وقت الحضور (بدون بصمة حضور)</span>
                    </label>
                  </div>

                  <div className="space-y-1">
                    <label className="text-xs font-bold text-[var(--text-secondary)]">وقت الانصراف</label>
                    <input
                      type="time"
                      className="input w-full"
                      value={checkOut}
                      disabled={clearCheckOut}
                      onChange={(e) => setCheckOut(e.target.value)}
                    />
                    <label htmlFor={clearCheckOutId} className="flex items-center gap-1.5 text-xs text-[var(--text-muted)] cursor-pointer">
                      <input
                        id={clearCheckOutId}
                        type="checkbox"
                        checked={clearCheckOut}
                        onChange={(e) => setClearCheckOut(e.target.checked)}
                      />
                      <span>حذف وقت الانصراف (بدون بصمة انصراف)</span>
                    </label>
                  </div>
                </div>
              </div>
            ) : null}

            {/* 4. سبب التعديل */}
            <div className="space-y-1.5">
              <label className="block text-xs font-bold text-[var(--text-secondary)]">سبب التعديل</label>
              {(PRESET_REASONS[dayType] ?? []).length > 0 ? (
                <div className="flex flex-wrap gap-1.5">
                  {(PRESET_REASONS[dayType] ?? []).map((preset) => (
                    <button
                      key={preset}
                      type="button"
                      className={`filter-chip ${reason === preset ? 'is-active' : ''}`}
                      onClick={() => setReason(preset)}
                    >
                      {preset}
                    </button>
                  ))}
                </div>
              ) : null}
              <input
                className="input w-full"
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                placeholder="اكتب سبب التعديل أو اختر من الأسباب السريعة…"
              />
            </div>

            {/* 5. ملاحظات إضافية */}
            <div className="space-y-1">
              <label className="block text-xs font-bold text-[var(--text-secondary)]">ملاحظات إدارية (اختيارية)</label>
              <textarea
                className="input min-h-16 w-full text-xs"
                value={notes}
                onChange={(e) => setNotes(e.target.value)}
                placeholder="أي توضيحات أو أرقام قرارات تدعم التعديل…"
              />
            </div>

            {saveMutation.isError ? (
              <p className="rounded-lg bg-[var(--danger-soft)] p-3 text-xs font-bold text-[var(--danger)]">
                {safeErrorMessage(saveMutation.error)}
              </p>
            ) : null}

            <div className="flex justify-end gap-2 pt-2">
              <button type="button" className="btn-secondary text-xs" onClick={() => setOpen(false)}>
                إلغاء
              </button>
              <button
                type="button"
                className="btn-primary text-xs"
                disabled={saveMutation.isPending}
                onClick={() => saveMutation.mutate()}
              >
                {saveMutation.isPending ? 'جارٍ الحفظ…' : 'حفظ التعديل'}
              </button>
            </div>
          </div>
        </DialogOverlay>
      ) : null}

      {/* مودال طلب تحديد يوم بموافقة المدير */}
      {markOpen ? (
        <DialogOverlay title={`طلب تحديد يوم ${day.date}`} onClose={() => setMarkOpen(false)} maxWidth="max-w-lg">
          <form
            className="space-y-4 text-right"
            onSubmit={(e) => {
              e.preventDefault();
              markMutation.mutate();
            }}
          >
            <p className="text-xs text-[var(--text-muted)]">يُرسل الطلب للمدير المباشر للاعتماد ليزول الغياب تلقائياً فور الموافقة.</p>
            <label className="block space-y-1 text-xs font-bold">
              <span>نوع اليوم المطلوب</span>
              <select className="input w-full" value={markType} onChange={(e) => setMarkType(e.target.value)}>
                <option value="mission">مأمورية</option>
                <option value="convoy">قافلة</option>
                <option value="fundraising">فاندي</option>
                <option value="annual">إجازة سنوية</option>
                <option value="casual">إجازة عارضة</option>
                <option value="unpaid">إجازة بدون راتب</option>
                <option value="weekly_rest_comp">بدل راحة أسبوعية</option>
              </select>
            </label>

            {['mission', 'convoy', 'fundraising'].includes(markType) ? (
              <label className="block space-y-1 text-xs font-bold">
                <span>المكان / الجهة</span>
                <input
                  className="input w-full"
                  value={markLocation}
                  onChange={(e) => setMarkLocation(e.target.value)}
                  placeholder="مقر الفرع، اسم القافلة، مكان المأمورية…"
                />
              </label>
            ) : null}

            <label className="block space-y-1 text-xs font-bold">
              <span>السبب</span>
              <input className="input w-full" value={markReason} required onChange={(e) => setMarkReason(e.target.value)} />
            </label>

            {markMutation.isError ? (
              <p className="rounded-lg bg-[var(--danger-soft)] p-3 text-xs font-bold text-[var(--danger)]">
                {safeErrorMessage(markMutation.error)}
              </p>
            ) : null}

            <div className="flex justify-end gap-2 pt-2">
              <button type="button" className="btn-secondary text-xs" onClick={() => setMarkOpen(false)}>
                إلغاء
              </button>
              <button type="submit" className="btn-primary text-xs" disabled={markMutation.isPending}>
                {markMutation.isPending ? 'جارٍ الإرسال…' : 'إرسال الطلب'}
              </button>
            </div>
          </form>
        </DialogOverlay>
      ) : null}
    </>
  );
}
