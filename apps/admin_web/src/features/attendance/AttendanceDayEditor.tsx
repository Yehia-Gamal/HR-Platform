import type { AttendanceStatementDay } from '@ahla/shared-contracts';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { Pencil, X } from 'lucide-react';
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

export function AttendanceDayEditor({ employeeId, day }: { employeeId: string; day: AttendanceStatementDay }) {
  const queryClient = useQueryClient();
  const [open, setOpen] = useState(false);
  const [dayType, setDayType] = useState<DayType>((day.adminOverride?.dayType as DayType | undefined) ?? 'work');
  const [checkIn, setCheckIn] = useState(day.checkIn?.slice(0, 5) ?? '');
  const [checkOut, setCheckOut] = useState(day.checkOut?.slice(0, 5) ?? '');
  const [clearCheckIn, setClearCheckIn] = useState(false);
  const [clearCheckOut, setClearCheckOut] = useState(false);
  const [reason, setReason] = useState(day.adminOverride?.reason ?? 'تصحيح إداري موثق');
  const [notes, setNotes] = useState(day.adminOverride?.notes ?? '');

  useEffect(() => {
    setDayType((day.adminOverride?.dayType as DayType | undefined) ?? 'work');
    setCheckIn(day.checkIn?.slice(0, 5) ?? '');
    setCheckOut(day.checkOut?.slice(0, 5) ?? '');
    setReason(day.adminOverride?.reason ?? 'تصحيح إداري موثق');
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
      }),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['attendance-statement', employeeId] });
      setOpen(false);
    },
  });

  return (
    <>
      <button type="button" className="btn btn-secondary !px-2 !py-1 text-[11px]" onClick={() => setOpen(true)} title="تعديل اليوم بسجل تدقيق">
        <Pencil className="size-3.5" aria-hidden="true" />
        تعديل
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
              <select className="input w-full" value={dayType} onChange={(event) => setDayType(event.target.value as DayType)}>
                {DAY_TYPES.map(([value, label]) => <option key={value} value={value}>{label}</option>)}
              </select>
            </label>

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

            <label className="space-y-1 text-sm font-bold">
              <span>سبب التعديل (إلزامي)</span>
              <input className="input w-full" value={reason} minLength={5} required onChange={(event) => setReason(event.target.value)} />
            </label>
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
    </>
  );
}
