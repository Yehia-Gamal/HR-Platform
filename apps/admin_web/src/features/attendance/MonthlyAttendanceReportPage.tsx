import type { AttendanceStatement, AttendanceStatementDay } from '@ahla/shared-contracts';
import {
  AlertTriangle,
  ArrowDownRight,
  ArrowUpRight,
  CalendarDays,
  Clock,
  Download,
  Printer,
  Search,
  Timer,
  TrendingUp,
  UserCheck,
  Users,
} from 'lucide-react';
import type { ReactNode } from 'react';
import { useMemo, useState } from 'react';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { MetricSkeletonRow, SkeletonCard } from '../../ui/Skeletons';
import { UserAvatar } from '../../ui/UserAvatar';
import { useEmployees } from '../employees/useEmployees';
import { useEmployeeMonthlyStatement } from './useMonthlyStatement';

const MONTHS = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
const WARN_STATUSES = new Set(['غائب دون إذن', 'يحتاج مراجعة']);

// ─── تصدير CSV ─────────────────────────────────────────────────
function exportCSV(data: AttendanceStatement) {
  const { employee: emp, period, days, summary: s } = data;
  const header = [
    `كشف الحضور والانصراف الشهري — ${emp.fullNameAr}`,
    `الكود: ${emp.employeeCode ?? '—'} | الإدارة: ${emp.department} | المسمى: ${emp.jobTitle}`,
    `الفترة: ${MONTHS[period.month - 1]} ${period.year} (${period.startDate} — ${period.endDate})`,
    '',
    'التاريخ,اليوم,الحضور,الانصراف,الوردية,ساعات فعلية,ساعات مطلوبة,التأخير (د),خروج مبكر (د),إضافي (د),الحالة,إجازة,إذن,مأمورية,قافلة/فاندي,نقص حضور,نقص انصراف,تصحيح,ملاحظة',
  ].join('\n');

  const rows = days.map((d) =>
    [
      d.date, d.dayNameAr,
      d.checkIn?.slice(0, 5) ?? '', d.checkOut?.slice(0, 5) ?? '',
      d.shiftName, d.workHours.toFixed(1), d.requiredHours.toFixed(1),
      d.lateMinutes, d.earlyLeaveMinutes, d.overtimeMinutes,
      d.status,
      d.hasLeave ? 'نعم' : '', d.hasPermit ? 'نعم' : '', d.hasMission ? 'نعم' : '',
      d.hasConvoyFundi ? 'نعم' : '', d.missingCheckIn ? 'نعم' : '',
      d.missingCheckOut ? 'نعم' : '', d.hasCorrection ? 'نعم' : '',
      d.correctionNote ?? '',
    ].join(','),
  ).join('\n');

  const summaryBlock = [
    '',
    'ملخص الشهر',
    `إجمالي الأيام,${s.totalDays}`,
    `الأيام المجدولة,${s.scheduledDays}`,
    `أيام الحضور,${s.presentDays}`,
    `أيام الغياب,${s.absentDays}`,
    `أيام الإجازات,${s.leaveDays}`,
    `أيام المأموريات,${s.missionDays}`,
    `قوافل/فاندي,${s.convoyFundiDays}`,
    `إذنات,${s.permitCount}`,
    `عطل رسمية,${s.holidayDays}`,
    `أيام الراحة,${s.restDays}`,
    `إجمالي ساعات العمل,${s.totalWorkHours.toFixed(1)}`,
    `متوسط ساعات/يوم,${s.averageWorkHours.toFixed(1)}`,
    `إجمالي التأخير (د),${s.totalLateMinutes}`,
    `إجمالي الخروج المبكر (د),${s.totalEarlyLeaveMinutes}`,
    `إجمالي الإضافي (د),${s.totalOvertimeMinutes}`,
    `نقص حضور,${s.missingCheckInCount}`,
    `نقص انصراف,${s.missingCheckOutCount}`,
    `تصحيحات,${s.correctionCount}`,
  ].join('\n');

  const csv = header + '\n' + rows + summaryBlock;
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8' }));
  a.download = `كشف-حضور-${emp.employeeCode ?? emp.fullNameAr}-${period.year}-${String(period.month).padStart(2, '0')}.csv`;
  a.click();
  URL.revokeObjectURL(a.href);
}

// ─── طباعة ─────────────────────────────────────────────────────
function handlePrint() {
  window.print();
}

// ─── الصفحة الرئيسية ───────────────────────────────────────────
export function MonthlyAttendanceReportPage() {
  const now = new Date();
  const [year, setYear] = useState(now.getFullYear());
  const [month, setMonth] = useState(now.getMonth() + 1);
  const [selectedEmployeeId, setSelectedEmployeeId] = useState<string | null>(null);
  const [employeeSearch, setEmployeeSearch] = useState('');

  const employeesQuery = useEmployees(employeeSearch || undefined, 'active');
  const statementQuery = useEmployeeMonthlyStatement(selectedEmployeeId, year, month);

  const selectedEmployee = useMemo(() => {
    if (!selectedEmployeeId || !employeesQuery.data) return null;
    return employeesQuery.data.find((e) => e.id === selectedEmployeeId) ?? null;
  }, [selectedEmployeeId, employeesQuery.data]);

  return (
    <div className="space-y-6 print:space-y-3">
      <PageHeader
        title="كشف الحضور والانصراف الشهري"
        description="عرض وتصدير كشف الحضور التفصيلي لأي موظف. اختر الموظف والشهر لعرض البيانات."
        actions={
          <div className="flex gap-2 print:hidden">
            {statementQuery.data ? (
              <>
                <button className="btn-secondary" onClick={handlePrint}>
                  <Printer className="size-4" aria-hidden="true" />طباعة
                </button>
                <button className="btn-primary" onClick={() => exportCSV(statementQuery.data!)}>
                  <Download className="size-4" aria-hidden="true" />تصدير CSV
                </button>
              </>
            ) : null}
          </div>
        }
      />

      {/* ─── شريط الفلاتر ─── */}
      <section className="card space-y-4 p-5 print:hidden" aria-label="اختيار الموظف والفترة">
        <div className="grid gap-4 sm:grid-cols-[1fr_auto_auto]">
          {/* اختيار الموظف */}
          <div className="relative">
            <label className="text-sm font-bold">
              <span className="block mb-1">الموظف</span>
              <div className="relative">
                <Search className="pointer-events-none absolute right-3 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted)]" aria-hidden="true" />
                <input
                  type="search"
                  className="input w-full pr-9"
                  placeholder="ابحث بالاسم أو الكود…"
                  value={employeeSearch}
                  onChange={(e) => {
                    setEmployeeSearch(e.target.value);
                    if (!e.target.value) setSelectedEmployeeId(null);
                  }}
                  aria-label="بحث الموظف"
                />
              </div>
            </label>
            {/* قائمة نتائج البحث */}
            {employeeSearch && !selectedEmployeeId && employeesQuery.data ? (
              <div className="absolute z-20 mt-1 max-h-60 w-full overflow-auto rounded-xl border border-[var(--border)] bg-[var(--surface)] shadow-lg">
                {employeesQuery.data.length === 0 ? (
                  <p className="p-3 text-center text-sm text-[var(--text-muted)]">لا توجد نتائج</p>
                ) : (
                  employeesQuery.data.slice(0, 20).map((emp) => (
                    <button
                      key={emp.id}
                      type="button"
                      className="flex w-full items-center gap-3 px-3 py-2.5 text-right hover:bg-[var(--surface-muted)] transition-colors"
                      onClick={() => {
                        setSelectedEmployeeId(emp.id);
                        setEmployeeSearch(emp.fullNameAr);
                      }}
                    >
                      <UserAvatar displayName={emp.fullNameAr} size="sm" />
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-sm font-bold">{emp.fullNameAr}</p>
                        <p className="truncate text-xs text-[var(--text-muted)]">{emp.employeeCode} · {emp.department ?? '—'}</p>
                      </div>
                    </button>
                  ))
                )}
              </div>
            ) : null}
          </div>

          {/* اختيار الشهر */}
          <label className="text-sm font-bold">
            <span className="block mb-1">الشهر</span>
            <select className="input" value={month} onChange={(e) => setMonth(Number(e.target.value))} aria-label="الشهر">
              {MONTHS.map((label, index) => <option key={label} value={index + 1}>{label}</option>)}
            </select>
          </label>

          {/* اختيار السنة */}
          <label className="text-sm font-bold">
            <span className="block mb-1">السنة</span>
            <select className="input" value={year} onChange={(e) => setYear(Number(e.target.value))} aria-label="السنة">
              {[now.getFullYear(), now.getFullYear() - 1, now.getFullYear() - 2].map((y) => <option key={y} value={y}>{y}</option>)}
            </select>
          </label>
        </div>

        {/* بطاقة الموظف المختار */}
        {selectedEmployee ? (
          <div className="flex items-center gap-3 rounded-xl border border-[var(--border)] bg-[var(--surface-muted)]/40 p-3">
            <UserAvatar displayName={selectedEmployee.fullNameAr} size="md" />
            <div className="min-w-0 flex-1">
              <p className="font-bold">{selectedEmployee.fullNameAr}</p>
              <p className="text-xs text-[var(--text-muted)]">
                {selectedEmployee.employeeCode} · {selectedEmployee.department ?? '—'} · {selectedEmployee.jobTitle ?? '—'}
              </p>
            </div>
            <button
              className="btn-secondary text-xs"
              onClick={() => { setSelectedEmployeeId(null); setEmployeeSearch(''); }}
            >
              تغيير
            </button>
          </div>
        ) : null}
      </section>

      {/* ─── حالات العرض ─── */}
      {!selectedEmployeeId ? (
        <EmptyState title="اختر موظفًا" description="ابحث واختر موظفًا من القائمة أعلاه لعرض كشف حضوره الشهري." />
      ) : statementQuery.isError ? (
        <ErrorState description={statementQuery.error instanceof Error ? statementQuery.error.message : undefined} onRetry={() => void statementQuery.refetch()} />
      ) : statementQuery.isLoading ? (
        <><MetricSkeletonRow count={4} /><SkeletonCard className="h-64" /></>
      ) : !statementQuery.data ? (
        <EmptyState title="لا يوجد كشف" description="تعذر تحميل بيانات الشهر المحدد." />
      ) : (
        <StatementReport data={statementQuery.data} />
      )}
    </div>
  );
}

// ─── عرض الكشف الكامل ──────────────────────────────────────────
function StatementReport({ data }: { data: AttendanceStatement }) {
  const { employee: emp, period, summary: s } = data;
  const attendancePct = s.scheduledDays > 0 ? (s.presentDays / s.scheduledDays * 100) : 0;

  return (
    <div className="space-y-5 print:space-y-3">
      {/* رأس التقرير للطباعة */}
      <div className="hidden print:block text-center mb-4">
        <h1 className="text-xl font-black">كشف الحضور والانصراف الشهري</h1>
        <p className="text-sm mt-1">{emp.fullNameAr} — {emp.employeeCode}</p>
        <p className="text-xs text-gray-500">{emp.department} · {emp.jobTitle}</p>
        <p className="text-xs text-gray-500">{MONTHS[period.month - 1]} {period.year} ({period.startDate} — {period.endDate})</p>
      </div>

      {/* بطاقة بيانات الموظف */}
      <section className="card p-5 print:border print:p-3" aria-label="بيانات الموظف">
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <InfoField label="الاسم" value={emp.fullNameAr} />
          <InfoField label="الكود" value={emp.employeeCode ?? '—'} />
          <InfoField label="الإدارة" value={emp.department} />
          <InfoField label="المسمى الوظيفي" value={emp.jobTitle} />
          <InfoField label="الفرع" value={emp.branch} />
          <InfoField label="المدير المباشر" value={emp.manager} />
          <InfoField label="تاريخ التعيين" value={emp.hireDate ?? '—'} dir="ltr" />
          <InfoField label="الفترة" value={`${MONTHS[period.month - 1]} ${period.year}`} />
        </div>
      </section>

      {/* نسبة الحضور + ملخص رئيسي */}
      <div className="grid gap-4 lg:grid-cols-[auto_1fr]">
        <div className="flex items-center justify-center rounded-xl border border-[var(--border)] bg-[var(--surface-muted)]/50 p-6 print:p-3">
          <AttendancePercentageRing percentage={attendancePct} />
        </div>
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4 print:grid-cols-4">
          <MetricCard label="أيام الحضور" value={s.presentDays} hint={`من ${s.scheduledDays} مجدولة`} icon={UserCheck} />
          <MetricCard label="أيام الغياب" value={s.absentDays} icon={AlertTriangle} />
          <MetricCard label="أيام الإجازات" value={s.leaveDays} icon={CalendarDays} />
          <MetricCard label="أيام المأموريات" value={s.missionDays} icon={TrendingUp} />
          <MetricCard label="إذنات" value={s.permitCount} icon={Clock} />
          <MetricCard label="قوافل/فاندي" value={s.convoyFundiDays} icon={CalendarDays} />
          <MetricCard label="إجمالي ساعات العمل" value={s.totalWorkHours.toFixed(1)} hint={`متوسط ${s.averageWorkHours.toFixed(1)} س/يوم`} icon={Timer} />
          <MetricCard label="ساعات إضافية" value={`${s.totalOvertimeMinutes} د`} icon={ArrowUpRight} />
        </div>
      </div>

      {/* شريط الإحصائيات السريعة */}
      <div className="flex flex-wrap gap-4 rounded-lg border border-[var(--border)] bg-[var(--surface-muted)]/40 px-4 py-3 text-xs print:py-2 print:text-[10px]">
        <StatItem label="تأخير كلي" value={`${s.totalLateMinutes} د`} icon={<ArrowDownRight className="size-3.5 text-amber-500" />} />
        <StatItem label="خروج مبكر" value={`${s.totalEarlyLeaveMinutes} د`} icon={<ArrowUpRight className="size-3.5 text-amber-500" />} />
        <StatItem label="نسيان حضور" value={`${s.missingCheckInCount}`} icon={<AlertTriangle className="size-3.5 text-red-500" />} />
        <StatItem label="نسيان انصراف" value={`${s.missingCheckOutCount}`} icon={<AlertTriangle className="size-3.5 text-red-500" />} />
        <StatItem label="عطل رسمية" value={`${s.holidayDays}`} icon={<CalendarDays className="size-3.5 text-[var(--text-muted)]" />} />
        <StatItem label="أيام راحة" value={`${s.restDays}`} icon={<CalendarDays className="size-3.5 text-[var(--text-muted)]" />} />
        <StatItem label="تصحيحات" value={`${s.correctionCount}`} icon={<Clock className="size-3.5 text-slate-500" />} />
      </div>

      {/* الجدول اليومي */}
      <section className="overflow-x-auto rounded-xl border border-[var(--border)] print:overflow-visible" aria-label="تفاصيل الحضور اليومي">
        <table className="w-full min-w-[1000px] text-right text-sm print:min-w-0 print:text-[9px]">
          <thead className="bg-[var(--surface-muted)] text-xs font-black print:text-[8px] print:bg-gray-100">
            <tr>
              <th className="p-2.5 print:p-1">التاريخ</th>
              <th className="p-2.5 print:p-1">اليوم</th>
              <th className="p-2.5 print:p-1">الحضور</th>
              <th className="p-2.5 print:p-1">الانصراف</th>
              <th className="p-2.5 print:p-1">الوردية</th>
              <th className="p-2.5 print:p-1">ساعات فعلية</th>
              <th className="p-2.5 print:p-1">ساعات مطلوبة</th>
              <th className="p-2.5 print:p-1">التأخير</th>
              <th className="p-2.5 print:p-1">خروج مبكر</th>
              <th className="p-2.5 print:p-1">إضافي</th>
              <th className="p-2.5 print:p-1">الحالة</th>
              <th className="p-2.5 print:p-1">ملاحظات</th>
            </tr>
          </thead>
          <tbody>
            {data.days.map((d) => <DayRow key={d.date} d={d} />)}
          </tbody>
        </table>
      </section>
    </div>
  );
}

// ─── صف يوم واحد ────────────────────────────────────────────────
function DayRow({ d }: { d: AttendanceStatementDay }) {
  const fmtTime = (t: string | null) => t ? t.slice(0, 5) : '—';
  const tags: { label: string; variant: 'info' | 'warn' | 'success' | 'purple' }[] = [];
  if (d.hasLeave) tags.push({ label: 'إجازة', variant: 'purple' });
  if (d.hasMission) tags.push({ label: 'مأمورية', variant: 'info' });
  if (d.hasPermit) tags.push({ label: 'إذن', variant: 'warn' });
  if (d.hasConvoyFundi) tags.push({ label: 'قافلة/فاندي', variant: 'purple' });
  if (d.missingCheckIn) tags.push({ label: 'نقص حضور', variant: 'warn' });
  if (d.missingCheckOut) tags.push({ label: 'نقص انصراف', variant: 'warn' });
  if (d.hasCorrection) tags.push({ label: 'تصحيح', variant: 'info' });

  return (
    <tr className="border-t border-[var(--border)] odd:bg-[var(--surface-muted)]/30 hover:bg-[var(--surface-muted)]/60 transition-colors print:hover:bg-transparent">
      <td className="p-2.5 tabular-nums print:p-1" dir="ltr">{d.date}</td>
      <td className="p-2.5 print:p-1">{d.dayNameAr}</td>
      <td className="p-2.5 tabular-nums print:p-1" dir="ltr">{fmtTime(d.checkIn)}</td>
      <td className="p-2.5 tabular-nums print:p-1" dir="ltr">{fmtTime(d.checkOut)}</td>
      <td className="p-2.5 print:p-1">{d.shiftName || '—'}</td>
      <td className="p-2.5 tabular-nums print:p-1">{d.workHours ? d.workHours.toFixed(1) : '—'}</td>
      <td className="p-2.5 tabular-nums print:p-1">{d.requiredHours ? d.requiredHours.toFixed(1) : '—'}</td>
      <td className={`p-2.5 tabular-nums print:p-1 ${d.lateMinutes > 0 ? 'text-amber-600 font-bold' : ''}`}>
        {d.lateMinutes ? `${d.lateMinutes} د` : '—'}
      </td>
      <td className={`p-2.5 tabular-nums print:p-1 ${d.earlyLeaveMinutes > 0 ? 'text-amber-600 font-bold' : ''}`}>
        {d.earlyLeaveMinutes ? `${d.earlyLeaveMinutes} د` : '—'}
      </td>
      <td className={`p-2.5 tabular-nums print:p-1 ${d.overtimeMinutes > 0 ? 'text-emerald-600 font-bold' : ''}`}>
        {d.overtimeMinutes ? `${d.overtimeMinutes} د` : '—'}
      </td>
      <td className={`p-2.5 font-bold print:p-1 ${WARN_STATUSES.has(d.status) ? 'text-red-600' : ''}`}>{d.status}</td>
      <td className="p-2.5 print:p-1">
        <div className="flex flex-wrap gap-1">
          {tags.map((t) => <DayTag key={t.label} label={t.label} variant={t.variant} />)}
          {d.correctionNote && !tags.length && <span className="text-xs text-[var(--text-muted)]">{d.correctionNote}</span>}
        </div>
      </td>
    </tr>
  );
}

// ─── مكونات مساعدة ──────────────────────────────────────────────
function DayTag({ label, variant }: { label: string; variant: 'info' | 'warn' | 'success' | 'purple' }) {
  const styles = {
    info: 'bg-sky-50 text-sky-700 border-sky-200',
    warn: 'bg-amber-50 text-amber-700 border-amber-200',
    success: 'bg-emerald-50 text-emerald-700 border-emerald-200',
    purple: 'bg-violet-50 text-violet-700 border-violet-200',
  };
  return (
    <span className={`inline-block rounded px-1.5 py-0.5 text-[10px] font-bold border print:text-[7px] print:px-1 ${styles[variant]}`}>
      {label}
    </span>
  );
}

function AttendancePercentageRing({ percentage }: { percentage: number }) {
  const pct = Math.min(100, Math.max(0, percentage));
  const color = pct >= 90 ? 'text-emerald-600' : pct >= 75 ? 'text-amber-500' : 'text-red-600';
  const bgColor = pct >= 90 ? 'stroke-emerald-100' : pct >= 75 ? 'stroke-amber-100' : 'stroke-red-100';
  const fgColor = pct >= 90 ? 'stroke-emerald-600' : pct >= 75 ? 'stroke-amber-500' : 'stroke-red-600';
  const r = 40;
  const circ = 2 * Math.PI * r;
  const offset = circ - (pct / 100) * circ;

  return (
    <div className="relative flex flex-col items-center gap-1">
      <svg width="100" height="100" viewBox="0 0 100 100" className="-rotate-90" aria-hidden="true">
        <circle cx="50" cy="50" r={r} fill="none" strokeWidth="8" className={bgColor} />
        <circle cx="50" cy="50" r={r} fill="none" strokeWidth="8" className={fgColor}
          strokeLinecap="round" strokeDasharray={circ} strokeDashoffset={offset}
          style={{ transition: 'stroke-dashoffset 0.6s ease' }} />
      </svg>
      <div className="absolute inset-0 flex flex-col items-center justify-center">
        <span className={`text-2xl font-black ${color}`}>{pct.toFixed(0)}%</span>
        <span className="text-[10px] text-[var(--text-muted)]">حضور</span>
      </div>
    </div>
  );
}

function InfoField({ label, value, dir }: { label: string; value: string; dir?: 'ltr' | 'rtl' }) {
  return (
    <div>
      <dt className="text-xs font-bold text-[var(--text-muted)]">{label}</dt>
      <dd className="mt-0.5 text-sm font-bold" dir={dir}>{value}</dd>
    </div>
  );
}

function StatItem({ label, value, icon }: { label: string; value: string; icon: ReactNode }) {
  return (
    <div className="flex items-center gap-1.5">
      {icon}
      <span className="text-[var(--text-muted)]">{label}:</span>
      <span className="font-bold">{value}</span>
    </div>
  );
}
