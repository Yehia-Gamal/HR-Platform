import type { AttendanceStatement } from '@ahla/shared-contracts';
import { CalendarDays } from 'lucide-react';
import { useState } from 'react';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { MetricCard } from '../../ui/MetricCard';
import { SkeletonCard } from '../../ui/Skeletons';
import { useEmployeeMonthlyStatement } from './useMonthlyStatement';

const MONTHS = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];

// حالات اليوم التي تُعرض بلون تحذيري.
const WARN_STATUSES = new Set(['غائب دون إذن', 'يحتاج مراجعة']);

// كشف الحضور والانصراف الشهري داخل ملف الموظف (V12 §18).
export function MonthlyStatementSection({ employeeId }: { employeeId: string }) {
  const now = new Date();
  const [year, setYear] = useState(now.getFullYear());
  const [month, setMonth] = useState(now.getMonth() + 1);
  const query = useEmployeeMonthlyStatement(employeeId, year, month);

  return (
    <section aria-labelledby="stmt-heading" className="card space-y-4 p-5">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 id="stmt-heading" className="flex items-center gap-2 text-lg font-black">
          <CalendarDays className="size-5 text-brand" aria-hidden="true" />
          كشف الحضور والانصراف الشهري
        </h2>
        <div className="flex gap-2">
          <select className="input" aria-label="الشهر" value={month} onChange={(e) => setMonth(Number(e.target.value))}>
            {MONTHS.map((label, index) => <option key={label} value={index + 1}>{label}</option>)}
          </select>
          <select className="input" aria-label="السنة" value={year} onChange={(e) => setYear(Number(e.target.value))}>
            {[now.getFullYear(), now.getFullYear() - 1, now.getFullYear() - 2].map((y) => <option key={y} value={y}>{y}</option>)}
          </select>
        </div>
      </div>
      {query.isError ? <ErrorState description={query.error instanceof Error ? query.error.message : undefined} onRetry={() => void query.refetch()} />
        : query.isLoading ? <SkeletonCard className="h-64" />
        : !query.data ? <EmptyState title="لا يوجد كشف" description="تعذر تحميل بيانات الشهر." />
        : <StatementBody data={query.data} />}
    </section>
  );
}

function StatementBody({ data }: { data: AttendanceStatement }) {
  const s = data.summary;
  const fmtTime = (t: string | null) => t ? t.slice(0, 5) : '—';
  return (
    <div className="space-y-4">
      <div className="grid gap-3 sm:grid-cols-3 xl:grid-cols-6">
        <MetricCard label="أيام الحضور" value={s.presentDays} hint={`من ${s.scheduledDays} مجدولة`} icon={CalendarDays} />
        <MetricCard label="أيام الغياب" value={s.absentDays} icon={CalendarDays} />
        <MetricCard label="أيام الإجازات" value={s.leaveDays} icon={CalendarDays} />
        <MetricCard label="أيام المأموريات" value={s.missionDays} icon={CalendarDays} />
        <MetricCard label="قوافل/فاندي" value={s.convoyFundiDays} icon={CalendarDays} />
        <MetricCard label="إجمالي ساعات العمل" value={s.totalWorkHours} hint={`متوسط ${s.averageWorkHours} س/يوم`} icon={CalendarDays} />
      </div>
      <div className="overflow-x-auto rounded-xl border border-[var(--border)]">
        <table className="w-full min-w-[720px] text-right text-sm">
          <thead className="bg-[var(--surface-muted)] text-xs font-black">
            <tr>
              <th className="p-2">التاريخ</th><th className="p-2">اليوم</th>
              <th className="p-2">الحضور</th><th className="p-2">الانصراف</th>
              <th className="p-2">الوردية</th><th className="p-2">ساعات فعلية</th>
              <th className="p-2">التأخير</th><th className="p-2">الحالة</th>
              <th className="p-2">ملاحظات</th>
            </tr>
          </thead>
          <tbody>
            {data.days.map((d) => (
              <tr key={d.date} className="border-t border-[var(--border)] odd:bg-[var(--surface-muted)]/30">
                <td className="p-2 tabular-nums" dir="ltr">{d.date}</td>
                <td className="p-2">{d.dayNameAr}</td>
                <td className="p-2 tabular-nums" dir="ltr">{fmtTime(d.checkIn)}</td>
                <td className="p-2 tabular-nums" dir="ltr">{fmtTime(d.checkOut)}</td>
                <td className="p-2">{d.shiftName || '—'}</td>
                <td className="p-2 tabular-nums">{d.workHours || '—'}</td>
                <td className="p-2 tabular-nums">{d.lateMinutes ? `${d.lateMinutes} د` : '—'}</td>
                <td className={`p-2 font-bold ${WARN_STATUSES.has(d.status) ? 'text-red-600' : ''}`}>{d.status}</td>
                <td className="p-2 text-xs">{d.correctionNote || (d.missingCheckOut ? 'لم يسجل انصراف' : '')}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="muted text-xs">تأخير كلي: {s.totalLateMinutes} د · خروج مبكر: {s.totalEarlyLeaveMinutes} د · نسيان ختم حضور: {s.missingCheckInCount} · نسيان ختم انصراف: {s.missingCheckOutCount} · تصحيحات: {s.correctionCount}</p>
    </div>
  );
}
