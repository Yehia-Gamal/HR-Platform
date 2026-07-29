import type { AttendanceStatement } from '@ahla/shared-contracts';
import { CalendarDays, Clock, AlertTriangle, TrendingUp, UserCheck, Timer, ArrowDownRight, ArrowUpRight, FileDown } from 'lucide-react';
import { useState } from 'react';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { MetricCard } from '../../ui/MetricCard';
import { SkeletonCard } from '../../ui/Skeletons';
import { AttendancePercentageRing, buildDayTags, DayTag, fmtTime, MONTHS, StatItem, WARN_STATUSES } from './attendanceShared';
import { exportAttendancePDF } from './exportAttendancePDF';
import { useEmployeeMonthlyStatement } from './useMonthlyStatement';

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
          {query.data && (
            <button
              type="button"
              className="btn btn-secondary flex items-center gap-1.5 text-xs"
              onClick={() => exportAttendancePDF(query.data!)}
            >
              <FileDown className="size-4" aria-hidden="true" />
              تصدير PDF
            </button>
          )}
        </div>
      </div>
      {query.isError ? <ErrorState description="تعذر تحميل كشف الحضور. أعد المحاولة أو تواصل مع الدعم." onRetry={() => void query.refetch()} />
        : query.isLoading ? <SkeletonCard className="h-64" />
        : !query.data ? <EmptyState title="لا يوجد كشف" description="لا توجد بيانات كشف لهذا الشهر." />
        : <StatementBody data={query.data} />}
    </section>
  );
}

function StatementBody({ data }: { data: AttendanceStatement }) {
  const s = data.summary;
  // V23: استخدام النسب من الخادم بدلاً من الحساب المحلي
  const attendancePct = s.attendanceRate ?? (s.scheduledDays > 0 ? (s.presentDays / s.scheduledDays * 100) : 0);
  const compliancePct = s.hoursComplianceRate ?? 0;

  return (
    <div className="space-y-5">
      {/* ─── نسب الحضور والالتزام + ملخص رئيسي ─── */}
      <div className="grid gap-4 lg:grid-cols-[auto_1fr]">
        {/* دوائر النسب */}
        <div className="flex items-center justify-center gap-4 rounded-xl border border-[var(--border)] bg-[var(--surface-muted)]/50 p-6">
          <AttendancePercentageRing percentage={attendancePct} />
          <AttendancePercentageRing percentage={compliancePct} label="التزام" />
        </div>

        {/* بطاقات الملخص */}
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
          <MetricCard label="أيام الحضور" value={s.presentDays} hint={`من ${s.scheduledDays} مجدولة`} icon={UserCheck} />
          <MetricCard label="أيام الغياب" value={s.absentDays} icon={AlertTriangle} />
          <MetricCard label="أيام الإجازات" value={s.leaveDays} icon={CalendarDays} />
          <MetricCard label="أيام المأموريات" value={s.missionDays} icon={TrendingUp} />
          <MetricCard label="إذنات" value={s.permitCount} icon={Clock} />
          <MetricCard label="قوافل/فاندي" value={s.convoyFundiDays} icon={CalendarDays} />
          <MetricCard label="ساعات العمل" value={s.totalWorkHours.toFixed(1)} hint={`مطلوب ${(s.totalRequiredHours ?? 0).toFixed(1)} | متوسط ${s.averageWorkHours.toFixed(1)} س/يوم`} icon={Timer} />
          <MetricCard label="ساعات إضافية" value={`${s.totalOvertimeMinutes} د`} icon={ArrowUpRight} />
        </div>
      </div>

      {/* ─── شريط الإحصائيات السريعة ─── */}
      <div className="flex flex-wrap gap-4 rounded-lg border border-[var(--border)] bg-[var(--surface-muted)]/40 px-4 py-3 text-xs">
        <StatItem label="تأخير كلي" value={`${s.totalLateMinutes} د`} icon={<ArrowDownRight className="size-3.5 text-amber-500" aria-hidden="true" />} />
        <StatItem label="خروج مبكر" value={`${s.totalEarlyLeaveMinutes} د`} icon={<ArrowUpRight className="size-3.5 text-amber-500" aria-hidden="true" />} />
        <StatItem label="نسبة الحضور" value={`${attendancePct.toFixed(0)}%`} icon={<UserCheck className="size-3.5 text-emerald-500" aria-hidden="true" />} />
        <StatItem label="التزام الساعات" value={`${compliancePct.toFixed(0)}%`} icon={<Timer className="size-3.5 text-blue-500" aria-hidden="true" />} />
        <StatItem label="نسيان حضور" value={`${s.missingCheckInCount}`} icon={<AlertTriangle className="size-3.5 text-red-500" aria-hidden="true" />} />
        <StatItem label="نسيان انصراف" value={`${s.missingCheckOutCount}`} icon={<AlertTriangle className="size-3.5 text-red-500" aria-hidden="true" />} />
        <StatItem label="عطل رسمية" value={`${s.holidayDays}`} icon={<CalendarDays className="size-3.5 text-[var(--text-muted)]" aria-hidden="true" />} />
        <StatItem label="أيام راحة" value={`${s.restDays}`} icon={<CalendarDays className="size-3.5 text-[var(--text-muted)]" aria-hidden="true" />} />
        <StatItem label="تصحيحات" value={`${s.correctionCount}`} icon={<Clock className="size-3.5 text-slate-500" aria-hidden="true" />} />
      </div>

      {/* ─── الجدول اليومي ─── */}
      <div className="overflow-x-auto rounded-xl border border-[var(--border)]">
        <table className="w-full min-w-[900px] text-start text-sm">
          <thead className="bg-[var(--surface-muted)] text-xs font-black">
            <tr>
              <th scope="col" className="p-2.5">التاريخ</th><th scope="col" className="p-2.5">اليوم</th>
              <th scope="col" className="p-2.5">الحضور</th><th scope="col" className="p-2.5">الانصراف</th>
              <th scope="col" className="p-2.5">الوردية</th><th scope="col" className="p-2.5">ساعات فعلية</th>
              <th scope="col" className="p-2.5">التأخير</th><th scope="col" className="p-2.5">خروج مبكر</th>
              <th scope="col" className="p-2.5">إضافي</th><th scope="col" className="p-2.5">الحالة</th>
              <th scope="col" className="p-2.5">ملاحظات</th>
            </tr>
          </thead>
          <tbody>
            {data.days.map((d) => {
              const tags = buildDayTags(d);
              return (
                <tr key={d.date} className="border-t border-[var(--border)] odd:bg-[var(--surface-muted)]/30 hover:bg-[var(--surface-muted)]/60 transition-colors">
                  <td className="p-2.5 tabular-nums" dir="ltr">{d.date}</td>
                  <td className="p-2.5">{d.dayNameAr}</td>
                  <td className="p-2.5 tabular-nums" dir="ltr">{fmtTime(d.checkIn)}</td>
                  <td className="p-2.5 tabular-nums" dir="ltr">{fmtTime(d.checkOut)}</td>
                  <td className="p-2.5">{d.shiftName || '—'}</td>
                  <td className="p-2.5 tabular-nums">{d.workHours ? d.workHours.toFixed(1) : '—'}</td>
                  <td className={`p-2.5 tabular-nums ${d.lateMinutes > 0 ? 'text-amber-600 font-bold' : ''}`}>
                    {d.lateMinutes ? `${d.lateMinutes} د` : '—'}
                  </td>
                  <td className={`p-2.5 tabular-nums ${d.earlyLeaveMinutes > 0 ? 'text-amber-600 font-bold' : ''}`}>
                    {d.earlyLeaveMinutes ? `${d.earlyLeaveMinutes} د` : '—'}
                  </td>
                  <td className={`p-2.5 tabular-nums ${d.overtimeMinutes > 0 ? 'text-emerald-600 font-bold' : ''}`}>
                    {d.overtimeMinutes ? `${d.overtimeMinutes} د` : '—'}
                  </td>
                  <td className={`p-2.5 font-bold ${WARN_STATUSES.has(d.status) ? 'text-red-600' : ''}`}>{d.status}</td>
                  <td className="p-2.5">
                    <div className="flex flex-wrap gap-1">
                      {tags.map((t) => <DayTag key={t.label} label={t.label} variant={t.variant} />)}
                      {d.correctionNote && !tags.length && <span className="text-xs text-[var(--text-muted)]">{d.correctionNote}</span>}
                    </div>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}
