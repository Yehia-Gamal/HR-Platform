import type { AttendanceStatementDay } from '@ahla/shared-contracts';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { Pencil, Send, X } from 'lucide-react';
import { useEffect, useState } from 'react';
import { rpc } from '../../core/rpc';
import { safeErrorMessage } from '../../core/errorMapper';

const DAY_TYPES = [
  ['work', 'يوم عمل'],
  ['leave', 'إجازة'],
  ['mission', 'مأمورية'],
  ['convoy', 'قافلة'],
  ['fundraising', 'فاندي'],
  ['holiday', 'عطلة رسمية'],
  ['rest', 'راحة'],
  ['absent', 'غياب'],
] as const;

type DayType = (typeof DAY_TYPES)[number][0];

/** أنواع الإجازة عند الترميز الإداري المباشر (0355 — تُخصم من الرصيد). */
const LEAVE_TYPES = [
  ['annual', 'إجازة سنوية (اعتيادية)'],
  ['casual', 'إجازة عارضة'],
  ['sick', 'إجازة مرضية'],
  ['unpaid', 'إجازة بدون راتب'],
] as const;

/** الافتراضي لكل ترميز إداري (إجازة ← سنوية، غياب ← بدون راتب). */
const DEFAULT_LEAVE_TYPE: Record<'leave' | 'absent', string> = {
  leave: 'annual',
  absent: 'unpaid',
};

/** أنواع تحديد اليوم عبر طلب (بموافقة المدير المباشر) — 0325. */
const MARK_OPTIONS = [
  ['mission', 'مأمورية'],
  ['convoy', 'قافلة'],
  ['fundraising', 'فاندي'],
  ['annual', 'إجازة سنوية (اعتيادية)'],
  ['casual', 'إجازة عارضة (تنفيذ فوري)'],
  ['unpaid', 'إجازة بدون راتب'],
] as const;

const OPERATIONAL_MARKS: ReadonlySet<string> = new Set(['mission', 'convoy', 'fundraising']);

/** أسباب مُسبقة سريعة حسب نوع اليوم — لتقليل الكتابة اليدوية */
const PRESET_REASONS: Record<DayType, string[]> = {
  work: ['تصحيح وقت الحضور', 'تصحيح وقت الانصراف', 'إضافة بصمة منسية', 'تعديل إداري للأوقات'],
  leave: ['إجازة اعتيادية معتمدة', 'إجازة مرضية', 'إجازة طارئة', 'إجازة بأثر رجعي'],
  mission: ['مأمورية ميدانية', 'مأمورية إدارية', 'انتداب رسمي'],
  convoy: ['قافلة خيرية', 'حملة توعوية'],
  fundraising: ['فاندي جمع تبرعات'],
  holiday: ['عطلة رسمية', 'إجازة رسمية'],
  rest: ['راحة أسبوعية', 'يوم راحة'],
  absent: ['غياب بدون إذن', 'غياب غير مبرر', 'تأكيد غياب'],
} as Record<DayType, string[]>;

export function AttendanceDayEditor({ employeeId, day }: { employeeId: string; day: AttendanceStatementDay }) {
  const queryClient = useQueryClient();
  const [open, setOpen] = useState(false);
  const [markOpen, setMarkOpen] = useState(false);
  const [markType, setMarkType] = useState<string>('mission');
  const [markReason, setMarkReason] = useState('');
  const [markLocation, setMarkLocation] = useState('');
  const [dayType, setDayType] = useState<DayType>((day.adminOverride?.dayType as DayType | undefined) ?? 'work');
  const [leaveType, setLeaveType] = useState<string>(day.adminOverride?.leaveType ?? (day.adminOverride?.dayType === 'leave' || day.adminOverride?.dayType === 'absent' ? DEFAULT_LEAVE_TYPE[day.adminOverride.dayType] : ''));
  const [checkIn, setCheckIn] = useState(day.checkIn?.slice(0, 5) ?? '');
  const [checkOut, setCheckOut] = useState(day.checkOut?.slice(0, 5) ?? '');
  const [clearCheckIn, setClearCheckIn] = useState(false);
  const [clearCheckOut, setClearCheckOut] = useState(false);
  const [reason, setReason] = useState(day.adminOverride?.reason ?? '');
  const [notes, setNotes] = useState(day.adminOverride?.notes ?? '');

  useEffect(() => {
    setDayType((day.adminOverride?.dayType as DayType | undefined) ?? 'work');
    setLeaveType(day.adminOverride?.leaveType ?? (day.adminOverride?.dayType === 'leave' || day.adminOverride?.dayType === 'absent' ? DEFAULT_LEAVE_TYPE[day.adminOverride.dayType] : ''));
    setCheckIn(day.checkIn?.slice(0, 5) ?? '');
    setCheckOut(day.checkOut?.slice(0, 5) ?? '');
    setReason(day.adminOverride?.reason ?? '');
    setNotes(day.adminOverride?.notes ?? '');
    setClearCheckIn(false);
    setClearCheckOut(false);
  }, [day]);

  const mutation = useMutation({
    mutationFn: () =>
      rpc('set_employee_attendance_day_admin', {
        p_employee_id: employeeId,
        p_work_date: day.date,
        p_day_type: dayType,
        p_check_in: dayType === 'work' && checkIn && !clearCheckIn ? checkIn : null,
        p_check_out: dayType === 'work' && checkOut && !clearCheckOut ? checkOut : null,
        p_clear_check_in: dayType !== 'work' || clearCheckIn,
        p_clear_check_out: dayType !== 'work' || clearCheckOut,
        p_reason: reason.trim(),
        p_notes: notes.trim() || null,
        p_leave_type: dayType === 'leave' || dayType === 'absent' ? (leaveType || DEFAULT_LEAVE_TYPE[dayType]) : null,
      }),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['attendance-statement', employeeId] });
      setOpen(false);
    },
  });

  const markMutation = useMutation({
    mutationFn: () => {
      const operational = OPERATIONAL_MARKS.has(markType);
      return rpc('submit_employee_day_mark', {
        p_employee_id: employeeId,
        p_request_type: operational ? markType : 'leave',
        p_title: `تحديد يوم ${day.date}`,
        p_reason: markReason.trim(),
        p_payload: {
          startDate: day.date,
          endDate: day.date,
          ...(operational ? { location: markLocation.trim() } : { leaveType: markType }),
          dayMark: true,
        },
      });
    },
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['attendance-statement', employeeId] });
      await queryClient.invalidateQueries({ queryKey: ['requests'] });
      setMarkOpen(false);
      setMarkReason('');
      setMarkLocation('');
    },
  });

  return (
    <>
      <button type="button" className="stmt-edit-btn" onClick={() => setOpen(true)} title="تعديل اليوم بسجل تدقيق">
        <Pencil className="size-3.5" aria-hidden="true" />
        تعديل
      </button>
      <button
        type="button"
        className="stmt-edit-btn"
        onClick={() => setMarkOpen(true)}
        title="إرسال طلب تحديد نوع اليوم (بموافقة المدير المباشر)"
      >
        <Send className="size-3.5" aria-hidden="true" />
        طلب تحديد
      </button>
      {open ? (
        <div className="fixed inset-0 z-50 grid place-items-center bg-slate-950/45 p-4" role="dialog" aria-modal="true" aria-label={`تعديل يوم ${day.date}`}>
          <form
            className="card w-full max-w-xl space-y-4 p-5 text-right shadow-2xl"
            onSubmit={(event) => {
              event.preventDefault();
              mutation.mutate();
            }}
          >
            <div className="flex items-center justify-between gap-3">
              <div>
                <h3 className="text-lg font-black">تعديل يوم {day.date}</h3>
                <p className="text-xs text-[var(--text-muted)]">تُحفظ البصمات الأصلية ويُسجل التعديل وسببه في سجل التدقيق.</p>
              </div>
              <button type="button" className="btn btn-ghost !p-2" onClick={() => setOpen(false)} aria-label="إغلاق">
                <X className="size-5" />
              </button>
            </div>

            <label className="space-y-1 text-sm font-bold">
              <span>تصنيف اليوم</span>
              <select
                className="input w-full"
                value={dayType}
                onChange={(event) => {
                  const next = event.target.value as DayType;
                  setDayType(next);
                  if (next === 'leave' || next === 'absent') setLeaveType(DEFAULT_LEAVE_TYPE[next]);
                  else setLeaveType('');
                }}
              >
                {DAY_TYPES.map(([value, label]) => <option key={value} value={value}>{label}</option>)}
              </select>
            </label>

            {dayType === 'leave' || dayType === 'absent' ? (
              <label className="space-y-1 text-sm font-bold">
                <span>نوع الإجازة ({dayType === 'absent' ? 'يُسجل غيابًا مخصومًا' : 'تُخصم من الرصيد'})</span>
                <select className="input w-full" value={leaveType} onChange={(event) => setLeaveType(event.target.value)}>
                  {LEAVE_TYPES.map(([value, label]) => <option key={value} value={value}>{label}</option>)}
                </select>
              </label>
            ) : null}

            {day.shiftName ? (
              <p className="text-xs text-[var(--text-muted)]">
                الوردية الحالية: <b className="text-[var(--text-secondary)]">{day.shiftName}</b>
                {day.requiredHours ? ` · مطلوب ${day.requiredHours.toFixed(1)} ساعة` : ''}
              </p>
            ) : null}

            {dayType === 'work' ? (
              <div className="grid gap-3 sm:grid-cols-2">
                <label className="space-y-1 text-sm font-bold">
                  <span>وقت الحضور</span>
                  <input className="input w-full" type="time" value={checkIn} disabled={clearCheckIn} onChange={(event) => setCheckIn(event.target.value)} />
                  <span className="flex items-center gap-2 text-xs font-normal"><input type="checkbox" checked={clearCheckIn} onChange={(event) => setClearCheckIn(event.target.checked)} /> حذف وقت الحضور الفعّال</span>
                </label>
                <label className="space-y-1 text-sm font-bold">
                  <span>وقت الانصراف</span>
                  <input className="input w-full" type="time" value={checkOut} disabled={clearCheckOut} onChange={(event) => setCheckOut(event.target.value)} />
                  <span className="flex items-center gap-2 text-xs font-normal"><input type="checkbox" checked={clearCheckOut} onChange={(event) => setClearCheckOut(event.target.checked)} /> حذف وقت الانصراف الفعّال</span>
                </label>
              </div>
            ) : null}

            <div className="space-y-1.5">
              <label className="text-sm font-bold">سبب التعديل (إلزامي)</label>
              {(PRESET_REASONS[dayType] ?? []).length > 0 ? (
                <div className="flex flex-wrap gap-1.5">
                  {(PRESET_REASONS[dayType] ?? []).map((preset) => (
                    <button
                      key={preset}
                      type="button"
                      className={`filter-chip${reason === preset ? ' is-active' : ''}`}
                      onClick={() => setReason(preset)}
                    >
                      {preset}
                    </button>
                  ))}
                </div>
              ) : null}
              <input className="input w-full" value={reason} minLength={5} required onChange={(event) => setReason(event.target.value)} placeholder="اكتب سببًا مخصصًا أو اختر من الأعلى…" />
            </div>
            <label className="space-y-1 text-sm font-bold">
              <span>ملاحظات</span>
              <textarea className="input min-h-20 w-full" value={notes} onChange={(event) => setNotes(event.target.value)} />
            </label>

            {mutation.isError ? <p className="rounded-lg bg-red-50 p-3 text-sm font-bold text-red-700">{safeErrorMessage(mutation.error)}</p> : null}

            <div className="flex justify-end gap-2">
              <button type="button" className="btn btn-secondary" onClick={() => setOpen(false)}>إلغاء</button>
              <button type="submit" className="btn btn-primary" disabled={mutation.isPending || reason.trim().length < 5}>
                {mutation.isPending ? 'جارٍ الحفظ…' : 'حفظ التعديل'}
              </button>
            </div>
          </form>
        </div>
      ) : null}
      {markOpen ? (
        <div className="fixed inset-0 z-50 grid place-items-center bg-slate-950/45 p-4" role="dialog" aria-modal="true" aria-label={`طلب تحديد يوم ${day.date}`}>
          <form
            className="card w-full max-w-xl space-y-4 p-5 text-right shadow-2xl"
            onSubmit={(event) => {
              event.preventDefault();
              markMutation.mutate();
            }}
          >
            <div className="flex items-center justify-between gap-3">
              <div>
                <h3 className="text-lg font-black">طلب تحديد يوم {day.date}</h3>
                <p className="text-xs text-[var(--text-muted)]">يُرسل للمدير المباشر للموافقة؛ عند الاعتماد يزول اليوم من الغياب.</p>
              </div>
              <button type="button" className="btn btn-ghost !p-2" onClick={() => setMarkOpen(false)} aria-label="إغلاق">
                <X className="size-5" />
              </button>
            </div>

            <label className="space-y-1 text-sm font-bold">
              <span>نوع اليوم</span>
              <select className="input w-full" value={markType} onChange={(event) => setMarkType(event.target.value)}>
                {MARK_OPTIONS.map(([value, label]) => <option key={value} value={value}>{label}</option>)}
              </select>
            </label>

            {OPERATIONAL_MARKS.has(markType) ? (
              <label className="space-y-1 text-sm font-bold">
                <span>المكان</span>
                <input className="input w-full" value={markLocation} onChange={(event) => setMarkLocation(event.target.value)} />
              </label>
            ) : null}

            <label className="space-y-1 text-sm font-bold">
              <span>السبب (إلزامي)</span>
              <input className="input w-full" value={markReason} minLength={5} required onChange={(event) => setMarkReason(event.target.value)} />
            </label>

            {markMutation.isError ? <p className="rounded-lg bg-red-50 p-3 text-sm font-bold text-red-700">{safeErrorMessage(markMutation.error)}</p> : null}
            {markMutation.isSuccess ? <p className="rounded-lg bg-emerald-50 p-3 text-sm font-bold text-emerald-700">أُرسل الطلب ووصل المدير المباشر.</p> : null}

            <div className="flex justify-end gap-2">
              <button type="button" className="btn btn-secondary" onClick={() => setMarkOpen(false)}>إلغاء</button>
              <button type="submit" className="btn btn-primary" disabled={markMutation.isPending || markReason.trim().length < 5}>
                {markMutation.isPending ? 'جارٍ الإرسال…' : 'إرسال الطلب'}
              </button>
            </div>
          </form>
        </div>
      ) : null}
    </>
  );
}
