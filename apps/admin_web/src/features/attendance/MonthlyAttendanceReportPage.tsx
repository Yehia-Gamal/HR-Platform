import type { AttendanceStatement, AttendanceStatementDay } from '@ahla/shared-contracts';
import {
  AlertTriangle,
  ArrowDownRight,
  ArrowUpRight,
  CalendarDays,
  Clock,
  Download,
  FileDown,
  Printer,
  Search,
  Timer,
  TrendingUp,
  UserCheck,
  Users,
} from 'lucide-react';
import { useMemo, useState } from 'react';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { safeErrorMessage } from '../../core/errorMapper';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { MetricSkeletonRow, SkeletonCard } from '../../ui/Skeletons';
import { UserAvatar } from '../../ui/UserAvatar';
import { useEmployees } from '../employees/useEmployees';
import { AttendancePercentageRing, attendanceRateParts, buildDayTags, DayTag, fmtTime, hoursRateParts, MONTHS, StatItem, WARN_STATUSES } from './attendanceShared';
import { AttendanceDayEditor } from './AttendanceDayEditor';
import { exportAttendancePDF } from './exportAttendancePDF';
import { useEmployeeMonthlyStatement } from './useMonthlyStatement';

// ─── تصدير CSV ─────────────────────────────────────────────────

/** يحمي خلايا CSV من كسر الأعمدة (فاصلة / سطر جديد) ومن حقن الصيغ (=+−@) */
function csvSafe(v: unknown): string {
  let s = String(v ?? '');
  // حماية من حقن الصيغ: أي خلية تبدأ بحرف صيغة يُسبق بفاصلة عليا
  if (/^[=+\-@\t\r]/.test(s)) s = "'" + s;
  // إن احتوت على فاصلة أو علامة تنصيص أو سطر جديد — تُغلّف بتنصيص مزدوج
  if (/[",\n\r]/.test(s)) s = '"' + s.replace(/"/g, '""') + '"';
  return s;
}

function exportCSV(data: AttendanceStatement) {
  const { employee: emp, period, days, summary: s } = data;
  const { presentInDue } = attendanceRateParts(s);
  const header = [
    `كشف الحضور والانصراف الشهري — ${csvSafe(emp.fullNameAr)}`,
    `الكود: ${csvSafe(emp.employeeCode ?? '—')} | الإدارة: ${csvSafe(emp.department)} | المسمى: ${csvSafe(emp.jobTitle)}`,
    `الفترة: ${MONTHS[period.month - 1]} ${period.year} (${period.startDate} — ${period.endDate})`,
    '',
    'التاريخ,اليوم,الحضور,الانصراف,الوردية,ساعات فعلية,ساعات مطلوبة,التأخير (د),خروج مبكر (د),إضافي (د),الحالة,غائب,عطلة رسمية,إجازة,إذن حضور,إذن انصراف,مأمورية,قافلة/فاندي,نقص حضور,نقص انصراف,تصحيح,جزاءات,ملاحظة',
  ].join('\n');

  const rows = days
    .map((d) =>
      [
        d.date,
        d.dayNameAr,
        d.checkIn?.slice(0, 5) ?? '',
        d.checkOut?.slice(0, 5) ?? '',
        csvSafe(d.shiftName),
        d.workHours.toFixed(1),
        d.requiredHours.toFixed(1),
        d.lateMinutes,
        d.earlyLeaveMinutes,
        d.overtimeMinutes,
        csvSafe(d.status),
        d.isAbsent ? 'نعم' : '',
        d.isOfficialHoliday ? 'نعم' : '',
        d.hasLeave ? 'نعم' : '',
        d.hasLatePermit ? 'نعم' : '',
        d.hasEarlyPermit ? 'نعم' : '',
        d.hasMission ? 'نعم' : '',
        d.hasConvoyFundi ? 'نعم' : '',
        d.missingCheckIn ? 'نعم' : '',
        d.missingCheckOut ? 'نعم' : '',
        d.hasCorrection ? 'نعم' : '',
        d.penalties > 0 ? d.penalties : '',
        csvSafe(d.correctionNote ?? ''),
      ].join(','),
    )
    .join('\n');

  const summaryBlock = [
    '',
    'ملخص الشهر',
    `إجمالي الأيام,${s.totalDays}`,
    `الأيام المجدولة,${s.scheduledDays}`,
    `الأيام المستحقة حتى الآن,${s.dueScheduledDays}`,
    `الأيام القادمة,${s.upcomingDays}`,
    `أيام الحضور,${s.presentDays}`,
    `الحضور المحتسب في النسبة,${presentInDue}`,
    `أيام الغياب,${s.absentDays}`,
    `ورديات مفتوحة,${s.openShiftDays}`,
    `أيام الإجازات,${s.leaveDays}`,
    `أيام المأموريات,${s.missionDays}`,
    `قوافل/فاندي,${s.convoyFundiDays}`,
    `إذنات,${s.permitCount}`,
    `عطل رسمية,${s.holidayDays}`,
    `أيام الراحة,${s.restDays}`,
    `إجمالي ساعات العمل,${s.totalWorkHours.toFixed(1)}`,
    `إجمالي الساعات المطلوبة,${(s.totalRequiredHours ?? 0).toFixed(1)}`,
    `متوسط ساعات/يوم,${s.averageWorkHours.toFixed(1)}`,
    `إجمالي التأخير (د),${s.totalLateMinutes}`,
    `إجمالي الخروج المبكر (د),${s.totalEarlyLeaveMinutes}`,
    `إجمالي الإضافي (د),${s.totalOvertimeMinutes}`,
    `نقص حضور,${s.missingCheckInCount}`,
    `نقص انصراف,${s.missingCheckOutCount}`,
    `تصحيحات,${s.correctionCount}`,
    `نسبة الحضور %,${(s.attendanceRate ?? 0).toFixed(1)}`,
    `التزام الساعات %,${s.hoursComplianceAvailable || s.totalRequiredHours > 0 ? (s.hoursComplianceRate ?? 0).toFixed(1) : 'غير متاح'}`,
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
  const [filterText, setFilterText] = useState('');

  // تحميل كل الموظفين النشطين مرة واحدة
  const employeesQuery = useEmployees(undefined, 'active');
  const statementQuery = useEmployeeMonthlyStatement(selectedEmployeeId, year, month);
  const statementData = statementQuery.data;

  // فلترة محلية للبطاقات حسب النص
  const filteredEmployees = useMemo(() => {
    const all = employeesQuery.data ?? [];
    if (!filterText.trim()) return all;
    const q = filterText.trim().toLowerCase();
    return all.filter(
      (e) => e.fullNameAr.toLowerCase().includes(q) || (e.employeeCode ?? '').toLowerCase().includes(q) || (e.department ?? '').toLowerCase().includes(q),
    );
  }, [employeesQuery.data, filterText]);

  return (
    <div className="space-y-6 print:space-y-3">
      <PageHeader
        title="كشف الحضور والانصراف الشهري"
        description="عرض وتصدير كشف الحضور التفصيلي لأي موظف. اختر الموظف والشهر لعرض البيانات."
        actions={
          <div className="flex gap-2 print:hidden">
            {statementData ? (
              <>
                <button className="btn-secondary" onClick={handlePrint}>
                  <Printer className="size-4" aria-hidden="true" />
                  طباعة
                </button>
                <button className="btn-secondary" onClick={() => exportAttendancePDF(statementData)}>
                  <FileDown className="size-4" aria-hidden="true" />
                  تصدير PDF
                </button>
                <button className="btn-primary" onClick={() => exportCSV(statementData)}>
                  <Download className="size-4" aria-hidden="true" />
                  تصدير CSV
                </button>
              </>
            ) : null}
          </div>
        }
      />

      {/* ─── شريط الفترة + البحث ─── */}
      <section className="card space-y-4 p-5 print:hidden" aria-label="اختيار الموظف والفترة">
        <div className="grid gap-4 sm:grid-cols-[1fr_auto_auto]">
          {/* بحث فلترة سريع */}
          <label className="text-sm font-bold">
            <span className="block mb-1">بحث سريع</span>
            <div className="relative">
              <Search className="pointer-events-none absolute right-3 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted)]" aria-hidden="true" />
              <input
                type="search"
                className="input w-full pr-9"
                placeholder="فلترة بالاسم أو الكود أو الإدارة…"
                value={filterText}
                onChange={(e) => setFilterText(e.target.value)}
                aria-label="فلترة الموظفين"
              />
            </div>
          </label>

          {/* اختيار الشهر */}
          <label className="text-sm font-bold">
            <span className="block mb-1">الشهر</span>
            <select className="input" value={month} onChange={(e) => setMonth(Number(e.target.value))} aria-label="الشهر">
              {MONTHS.map((label, index) => (
                <option key={label} value={index + 1}>
                  {label}
                </option>
              ))}
            </select>
          </label>

          {/* اختيار السنة */}
          <label className="text-sm font-bold">
            <span className="block mb-1">السنة</span>
            <select className="input" value={year} onChange={(e) => setYear(Number(e.target.value))} aria-label="السنة">
              {[now.getFullYear(), now.getFullYear() - 1, now.getFullYear() - 2].map((y) => (
                <option key={y} value={y}>
                  {y}
                </option>
              ))}
            </select>
          </label>
        </div>
      </section>

      {/* ─── شبكة بطاقات الموظفين ─── */}
      <section className="print:hidden" aria-label="اختيار الموظف">
        {employeesQuery.isLoading ? (
          <div className="grid gap-3 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5">
            {Array.from({ length: 10 }).map((_, i) => (
              <SkeletonCard key={i} className="h-24" />
            ))}
          </div>
        ) : employeesQuery.isError ? (
          <ErrorState description="تعذر تحميل قائمة الموظفين." onRetry={() => void employeesQuery.refetch()} />
        ) : filteredEmployees.length === 0 ? (
          <EmptyState title="لا توجد نتائج" description={filterText ? 'جرّب كلمة بحث مختلفة.' : 'لا يوجد موظفون نشطون.'} />
        ) : (
          <>
            <div className="mb-3 flex items-center gap-2 text-sm text-[var(--text-muted)]">
              <Users className="size-4" />
              <span>{filteredEmployees.length} موظف</span>
              {selectedEmployeeId ? <span className="font-bold text-[var(--brand-primary)]">— تم الاختيار</span> : <span>— اختر موظفًا لعرض الكشف</span>}
            </div>
            <div className="grid gap-3 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5">
              {filteredEmployees.map((emp) => {
                const isSelected = emp.id === selectedEmployeeId;
                return (
                  <button
                    key={emp.id}
                    type="button"
                    onClick={() => setSelectedEmployeeId(isSelected ? null : emp.id)}
                    className={`relative flex items-center gap-3 rounded-xl border-2 p-3 text-right transition-all duration-200 ${
                      isSelected
                        ? 'border-[var(--brand-primary)] bg-[var(--brand-primary)]/5 shadow-md ring-2 ring-[var(--brand-primary)]/20'
                        : 'border-[var(--border)] bg-[var(--surface)] hover:border-[var(--brand-primary)]/40 hover:shadow-sm'
                    }`}
                    aria-pressed={isSelected}
                    aria-label={`${emp.fullNameAr}${isSelected ? ' — محدد' : ''}`}
                  >
                    {isSelected ? (
                      <span className="absolute top-2 left-2 flex size-5 items-center justify-center rounded-full bg-[var(--brand-primary)] text-white">
                        <UserCheck className="size-3" />
                      </span>
                    ) : null}
                    <UserAvatar displayName={emp.fullNameAr} photoUrl={emp.photoUrl} size="sm" />
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm font-black">{emp.fullNameAr}</p>
                      <p className="truncate text-[11px] text-[var(--text-muted)]">{emp.department ?? '—'}</p>
                      <p className="truncate text-[11px] text-[var(--text-muted)]">{emp.jobTitle ?? '—'}</p>
                    </div>
                  </button>
                );
              })}
            </div>
          </>
        )}
      </section>

      {/* ─── حالات العرض ─── */}
      {!selectedEmployeeId ? null : statementQuery.isError ? (
        <ErrorState description={safeErrorMessage(statementQuery.error)} onRetry={() => void statementQuery.refetch()} />
      ) : statementQuery.isLoading ? (
        <>
          <MetricSkeletonRow count={4} />
          <SkeletonCard className="h-64" />
        </>
      ) : !statementQuery.data ? (
        <EmptyState title="لا يوجد كشف" description="لا توجد بيانات كشف لهذا الشهر." />
      ) : (
        <StatementReport data={statementQuery.data} />
      )}
    </div>
  );
}

// ─── عرض الكشف الكامل ──────────────────────────────────────────
function StatementReport({ data }: { data: AttendanceStatement }) {
  const { employee: emp, period, summary: s } = data;
  const { dueDays, presentInDue } = attendanceRateParts(s);
  const { workedHours, requiredHours, deficitHours } = hoursRateParts(s);
  // V23: استخدام النسب من الخادم بدلاً من الحساب المحلي
  const attendancePct = s.attendanceRate ?? (dueDays > 0 ? (presentInDue / dueDays) * 100 : 0);
  const compliancePct = s.hoursComplianceRate ?? 0;
  const complianceAvailable = s.hoursComplianceAvailable || s.totalRequiredHours > 0;

  return (
    <div className="space-y-5 print:space-y-3">
      {/* رأس التقرير للطباعة */}
      <div className="hidden print:block text-center mb-4">
        <h1 className="text-xl font-black">كشف الحضور والانصراف الشهري</h1>
        <p className="text-sm mt-1">
          {emp.fullNameAr} — {emp.employeeCode}
        </p>
        <p className="text-xs text-gray-500">
          {emp.department} · {emp.jobTitle}
        </p>
        <p className="text-xs text-gray-500">
          {MONTHS[period.month - 1]} {period.year} ({period.startDate} — {period.endDate})
        </p>
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

      {/* V23: نسب الحضور والالتزام + ملخص رئيسي */}
      <div className="grid gap-4 lg:grid-cols-[auto_1fr]">
        <div className="flex flex-wrap items-center justify-center gap-4 rounded-xl border border-[var(--border)] bg-[var(--surface-muted)]/50 p-6 print:p-3">
          <AttendancePercentageRing percentage={attendancePct} label="حضور الشهر" />
          <AttendancePercentageRing percentage={compliancePct} label="ساعات الشهر" available={complianceAvailable} />
          <AttendancePercentageRing percentage={s.coverageRate} label="تغطية الأيام" />
        </div>
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4 print:grid-cols-4">
          <MetricCard label="أيام الحضور" value={presentInDue} hint={`من ${dueDays} يوم عمل في الشهر`} icon={UserCheck} />
          <MetricCard label="أيام الغياب" value={s.absentDays} icon={AlertTriangle} />
          <MetricCard label="وردية مفتوحة" value={s.openShiftDays} hint="حاضر — بانتظار الانصراف" icon={Clock} />
          <MetricCard label="أيام قادمة" value={s.upcomingDays} hint={`من ${s.scheduledDays} مجدولة شهريًا`} icon={CalendarDays} />
          <MetricCard label="أيام الإجازات" value={s.leaveDays} icon={CalendarDays} />
          <MetricCard label="أيام المأموريات" value={s.missionDays} icon={TrendingUp} />
          <MetricCard label="إذنات" value={s.permitCount} icon={Clock} />
          <MetricCard label="قوافل/فاندي" value={s.convoyFundiDays} icon={CalendarDays} />
          <MetricCard
            label="ساعات العمل"
            value={workedHours.toFixed(1)}
            hint={
              complianceAvailable
                ? `من ${requiredHours.toFixed(1)} س شهريًا | عجز ${deficitHours.toFixed(1)} س`
                : 'الساعات المطلوبة غير متاحة'
            }
            icon={Timer}
          />
          <MetricCard label="ساعات إضافية" value={`${s.totalOvertimeMinutes} د`} icon={ArrowUpRight} />
        </div>
      </div>

      {/* شريط الإحصائيات السريعة */}
      <div className="flex flex-wrap gap-4 rounded-lg border border-[var(--border)] bg-[var(--surface-muted)]/40 px-4 py-3 text-xs print:py-2 print:text-[10px]">
        <StatItem label="تأخير كلي" value={`${s.totalLateMinutes} د`} icon={<ArrowDownRight className="size-3.5 text-amber-500" />} />
        <StatItem label="خروج مبكر" value={`${s.totalEarlyLeaveMinutes} د`} icon={<ArrowUpRight className="size-3.5 text-amber-500" />} />
        <StatItem label="نسبة الحضور" value={`${attendancePct.toFixed(0)}%`} icon={<UserCheck className="size-3.5 text-emerald-500" />} />
        <StatItem
          label="التزام الساعات"
          value={complianceAvailable ? `${compliancePct.toFixed(0)}%` : 'غير متاح'}
          icon={<Timer className="size-3.5 text-blue-500" />}
        />
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
              {data.capabilities.canEditDays ? <th className="p-2.5 print:hidden">إدارة اليوم</th> : null}
            </tr>
          </thead>
          <tbody>
            {data.days.map((d) => (
              <DayRow key={d.date} d={d} employeeId={emp.id} canEdit={data.capabilities.canEditDays} />
            ))}
          </tbody>
        </table>
      </section>
    </div>
  );
}

// ─── صف يوم واحد ────────────────────────────────────────────────
function DayRow({ d, employeeId, canEdit }: { d: AttendanceStatementDay; employeeId: string; canEdit: boolean }) {
  const tags = buildDayTags(d);

  return (
    <tr
      className={`border-t border-[var(--border)] transition-colors print:hover:bg-transparent ${d.isFuture ? 'bg-slate-50/80 text-slate-400' : d.isOpenShift ? 'bg-sky-50/70 hover:bg-sky-50' : 'odd:bg-[var(--surface-muted)]/30 hover:bg-[var(--surface-muted)]/60'}`}
    >
      <td className="p-2.5 tabular-nums print:p-1" dir="ltr">
        {d.date}
      </td>
      <td className="p-2.5 print:p-1">{d.dayNameAr}</td>
      <td className="p-2.5 tabular-nums print:p-1" dir="ltr">
        {fmtTime(d.checkIn)}
      </td>
      <td className="p-2.5 tabular-nums print:p-1" dir="ltr">
        {fmtTime(d.checkOut)}
      </td>
      <td className="p-2.5 print:p-1">{d.shiftName || '—'}</td>
      <td className="p-2.5 tabular-nums print:p-1">{d.workHours ? d.workHours.toFixed(1) : '—'}</td>
      <td className="p-2.5 tabular-nums print:p-1">{d.requiredHours ? d.requiredHours.toFixed(1) : '—'}</td>
      <td className={`p-2.5 tabular-nums print:p-1 ${d.lateMinutes > 0 ? 'text-amber-600 font-bold' : ''}`}>{d.lateMinutes ? `${d.lateMinutes} د` : '—'}</td>
      <td className={`p-2.5 tabular-nums print:p-1 ${d.earlyLeaveMinutes > 0 ? 'text-amber-600 font-bold' : ''}`}>
        {d.earlyLeaveMinutes ? `${d.earlyLeaveMinutes} د` : '—'}
      </td>
      <td className={`p-2.5 tabular-nums print:p-1 ${d.overtimeMinutes > 0 ? 'text-emerald-600 font-bold' : ''}`}>
        {d.overtimeMinutes ? `${d.overtimeMinutes} د` : '—'}
      </td>
      <td className={`p-2.5 font-bold print:p-1 ${WARN_STATUSES.has(d.status) ? 'text-red-600' : ''}`}>{d.status}</td>
      <td className="p-2.5 print:p-1">
        <div className="flex flex-wrap gap-1">
          {tags.map((t) => (
            <DayTag key={t.label} label={t.label} variant={t.variant} />
          ))}
          {d.correctionNote && !tags.length && <span className="text-xs text-[var(--text-muted)]">{d.correctionNote}</span>}
        </div>
      </td>
      {canEdit ? <td className="p-2.5 print:hidden"><AttendanceDayEditor employeeId={employeeId} day={d} /></td> : null}
    </tr>
  );
}

// ─── مكون مساعد خاص بالصفحة ─────────────────────────────────────
function InfoField({ label, value, dir }: { label: string; value: string; dir?: 'ltr' | 'rtl' }) {
  return (
    <div>
      <dt className="text-xs font-bold text-[var(--text-muted)]">{label}</dt>
      <dd className="mt-0.5 text-sm font-bold" dir={dir}>
        {value}
      </dd>
    </div>
  );
}
