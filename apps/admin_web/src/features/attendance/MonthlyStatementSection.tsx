import type { AttendanceStatement } from '@ahla/shared-contracts';
import {
  CalendarDays,
  Clock,
  AlertTriangle,
  TrendingUp,
  UserCheck,
  Timer,
  ArrowDownRight,
  ArrowUpRight,
  FileDown,
  Filter,
  Printer,
  Search,
} from 'lucide-react';
import { useMemo, useState } from 'react';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { SkeletonCard } from '../../ui/Skeletons';
import {
  AttendancePercentageRing,
  attendanceRateParts,
  buildDayTags,
  DayTag,
  DAY_FILTERS,
  DAY_SORTS,
  filterDays,
  fmtTime,
  hoursRateParts,
  MONTHS,
  QuickStat,
  sortDays,
  StatBox,
  StatusPill,
  type DayFilter,
  type DaySort,
} from './attendanceShared';
import { AttendanceDayEditor } from './AttendanceDayEditor';
import { exportAttendancePDF } from './exportAttendancePDF';
import { useEmployeeMonthlyStatement } from './useMonthlyStatement';

export function MonthlyStatementSection({ employeeId }: { employeeId: string }) {
  const now = new Date();
  const [year, setYear] = useState(now.getFullYear());
  const [month, setMonth] = useState(now.getMonth() + 1);
  const query = useEmployeeMonthlyStatement(employeeId, year, month);
  const statementData = query.data;

  return (
    <section aria-labelledby="stmt-heading" className="card stmt-section">
      <div className="stmt-header">
        <h2 id="stmt-heading" className="stmt-title">
          <CalendarDays className="size-5" aria-hidden="true" />
          كشف الحضور والانصراف الشهري
        </h2>
        <div className="stmt-controls">
          <div className="stmt-select">
            <select className="input" aria-label="الشهر" value={month} onChange={(e) => setMonth(Number(e.target.value))}>
              {MONTHS.map((label, index) => (
                <option key={label} value={index + 1}>
                  {label}
                </option>
              ))}
            </select>
          </div>
          <div className="stmt-select">
            <select className="input" aria-label="السنة" value={year} onChange={(e) => setYear(Number(e.target.value))}>
              {[now.getFullYear(), now.getFullYear() - 1, now.getFullYear() - 2].map((y) => (
                <option key={y} value={y}>
                  {y}
                </option>
              ))}
            </select>
          </div>
          {statementData && (
            <>
              <button type="button" className="stmt-btn" onClick={() => exportAttendancePDF(statementData)} title="تنزيل نسخة PDF من كشف الحضور والانصراف">
                <FileDown className="size-4" aria-hidden="true" />
                تصدير PDF
              </button>
              <button
                type="button"
                className="stmt-btn stmt-btn--primary"
                onClick={() => exportAttendancePDF(statementData)}
                title="فتح نسخة قابلة للطباعة فوراً"
              >
                <Printer className="size-4" aria-hidden="true" />
                طباعة
              </button>
            </>
          )}
        </div>
      </div>

      {query.isError ? (
        <ErrorState description="تعذر تحميل كشف الحضور. أعد المحاولة أو تواصل مع الدعم." onRetry={() => void query.refetch()} />
      ) : query.isLoading ? (
        <SkeletonCard className="h-64" />
      ) : !query.data ? (
        <EmptyState title="لا يوجد كشف" description="لا توجد بيانات كشف لهذا الشهر." />
      ) : (
        <StatementBody data={query.data} />
      )}
    </section>
  );
}

function StatementBody({ data }: { data: AttendanceStatement }) {
  const s = data.summary;
  const { dueDays, presentInDue } = attendanceRateParts(s);
  const { workedHours, requiredHours, deficitHours } = hoursRateParts(s);
  const attendancePct = s.attendanceRate ?? (dueDays > 0 ? (presentInDue / dueDays) * 100 : 0);
  const compliancePct = s.hoursComplianceRate ?? 0;
  const complianceAvailable = s.hoursComplianceAvailable || s.totalRequiredHours > 0;

  // ── فلترة وترتيب الأيام ──
  const [dayFilter, setDayFilter] = useState<DayFilter>('all');
  const [daySort, setDaySort] = useState<DaySort>('date-asc');
  const [daySearch, setDaySearch] = useState('');
  const filteredSortedDays = useMemo(() => sortDays(filterDays(data.days, dayFilter, daySearch), daySort), [data.days, dayFilter, daySort, daySearch]);

  return (
    <div className="space-y-5">
      <div className="stmt-hero">
        <div className="stmt-rings">
          <AttendancePercentageRing percentage={attendancePct} label="حضور الشهر" />
          <AttendancePercentageRing percentage={compliancePct} label="ساعات الشهر" available={complianceAvailable} />
          <AttendancePercentageRing percentage={s.coverageRate} label="تغطية الأيام" />
        </div>

        <div className="stmt-stats">
          <StatBox label="أيام الحضور" value={presentInDue} hint={`من ${dueDays} يوم عمل في الشهر`} icon={UserCheck} tone="success" />
          <StatBox label="أيام الغياب" value={s.absentDays} icon={AlertTriangle} tone={s.absentDays > 0 ? 'danger' : undefined} />
          <StatBox label="وردية مفتوحة" value={s.openShiftDays} hint="حاضر — بانتظار الانصراف" icon={Clock} tone={s.openShiftDays > 0 ? 'warn' : undefined} />
          <StatBox label="أيام قادمة" value={s.upcomingDays} hint={`من ${s.scheduledDays} مجدولة شهريًا`} icon={CalendarDays} />
          <StatBox label="أيام الإجازات" value={s.leaveDays} icon={CalendarDays} />
          <StatBox label="أيام المأموريات" value={s.missionDays} icon={TrendingUp} />
          <StatBox label="إذنات" value={s.permitCount} icon={Clock} />
          <StatBox label="قوافل/فاندي" value={s.convoyFundiDays} icon={CalendarDays} />
          <StatBox
            label="ساعات العمل"
            value={workedHours.toFixed(1)}
            hint={complianceAvailable ? `من ${requiredHours.toFixed(1)} س شهريًا · عجز ${deficitHours.toFixed(1)} س` : 'الساعات المطلوبة غير متاحة'}
            icon={Timer}
            tone={deficitHours > 0 ? 'warn' : 'success'}
          />
          <StatBox label="ساعات إضافية" value={`${s.totalOvertimeMinutes} د`} icon={ArrowUpRight} tone={s.totalOvertimeMinutes > 0 ? 'success' : undefined} />
        </div>
      </div>

      <div className="quick-stats">
        <QuickStat
          label="تأخير كلي"
          value={`${s.totalLateMinutes} د`}
          icon={<ArrowDownRight className="size-3.5 text-[var(--warning)]" aria-hidden="true" />}
        />
        <QuickStat
          label="خروج مبكر"
          value={`${s.totalEarlyLeaveMinutes} د`}
          icon={<ArrowUpRight className="size-3.5 text-[var(--warning)]" aria-hidden="true" />}
        />
        <QuickStat
          label="نسبة الحضور"
          value={`${attendancePct.toFixed(0)}%`}
          icon={<UserCheck className="size-3.5 text-[var(--success)]" aria-hidden="true" />}
        />
        <QuickStat
          label="نسيان حضور"
          value={`${s.missingCheckInCount}`}
          icon={<AlertTriangle className="size-3.5 text-[var(--danger)]" aria-hidden="true" />}
        />
        <QuickStat
          label="نسيان انصراف"
          value={`${s.missingCheckOutCount}`}
          icon={<AlertTriangle className="size-3.5 text-[var(--danger)]" aria-hidden="true" />}
        />
        <QuickStat label="تصحيحات" value={`${s.correctionCount}`} icon={<Clock className="size-3.5 text-[var(--text-muted)]" aria-hidden="true" />} />
      </div>

      <div className="filter-bar">
        <div className="filter-bar-heading">
          <span className="filter-bar-title">
            <Filter className="size-3.5" aria-hidden="true" />
            فلترة الأيام
          </span>
          {(dayFilter !== 'all' || daySearch || daySort !== 'date-asc') && (
            <button
              type="button"
              className="filter-clear"
              onClick={() => {
                setDayFilter('all');
                setDaySearch('');
                setDaySort('date-asc');
              }}
            >
              مسح الفلاتر
            </button>
          )}
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <div className="filter-search relative flex-1 min-w-[200px]">
            <Search className="pointer-events-none absolute right-3 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted)]" aria-hidden="true" />
            <input
              type="search"
              className="input pr-9"
              placeholder="بحث بالتاريخ أو اليوم أو الحالة…"
              value={daySearch}
              onChange={(e) => setDaySearch(e.target.value)}
              aria-label="بحث في الأيام"
            />
          </div>
          <div className="flex flex-wrap gap-1.5">
            {DAY_FILTERS.map((f) => (
              <button
                key={f.key}
                type="button"
                className={`filter-chip${dayFilter === f.key ? ' is-active' : ''}`}
                onClick={() => setDayFilter(f.key)}
                aria-pressed={dayFilter === f.key}
              >
                {f.label}
              </button>
            ))}
          </div>
          <div className="stmt-select">
            <select className="input min-w-[140px]" value={daySort} onChange={(e) => setDaySort(e.target.value as DaySort)} aria-label="ترتيب الأيام">
              {DAY_SORTS.map((so) => (
                <option key={so.key} value={so.key}>
                  {so.label}
                </option>
              ))}
            </select>
          </div>
        </div>
        <p className="filter-result">
          {filteredSortedDays.length} من {data.days.length} يوم
        </p>
      </div>

      <div className="stmt-table-wrap">
        <table className="stmt-table">
          <thead>
            <tr>
              <th scope="col">التاريخ</th>
              <th scope="col">اليوم</th>
              <th scope="col">الحضور</th>
              <th scope="col">الانصراف</th>
              <th scope="col">الوردية</th>
              <th scope="col">ساعات فعلية</th>
              <th scope="col">التأخير</th>
              <th scope="col">خروج مبكر</th>
              <th scope="col">إضافي</th>
              <th scope="col">الحالة</th>
              <th scope="col">ملاحظات</th>
              {data.capabilities.canEditDays ? <th scope="col">إجراء</th> : null}
            </tr>
          </thead>
          <tbody>
            {filteredSortedDays.map((d) => {
              const tags = buildDayTags(d);
              const rowClass = d.isAbsent ? 'row-absent' : d.isOpenShift ? 'row-open' : d.isFuture ? 'row-future' : '';
              return (
                <tr key={d.date} className={rowClass}>
                  <td className="cell-date">{d.date}</td>
                  <td className="cell-day">{d.dayNameAr}</td>
                  <td className="cell-time">{fmtTime(d.checkIn)}</td>
                  <td className="cell-time">{fmtTime(d.checkOut)}</td>
                  <td className="cell-shift">{d.shiftName || <span className="dash">—</span>}</td>
                  <td className="cell-num">{d.workHours ? d.workHours.toFixed(1) : <span className="dash">—</span>}</td>
                  <td className={`cell-num${d.lateMinutes > 0 ? ' text-[var(--warning)] font-bold' : ''}`}>
                    {d.lateMinutes ? `${d.lateMinutes} د` : <span className="dash">—</span>}
                  </td>
                  <td className={`cell-num${d.earlyLeaveMinutes > 0 ? ' text-[var(--warning)] font-bold' : ''}`}>
                    {d.earlyLeaveMinutes ? `${d.earlyLeaveMinutes} د` : <span className="dash">—</span>}
                  </td>
                  <td className={`cell-num${d.overtimeMinutes > 0 ? ' text-[var(--success)] font-bold' : ''}`}>
                    {d.overtimeMinutes ? `${d.overtimeMinutes} د` : <span className="dash">—</span>}
                  </td>
                  <td>
                    <StatusPill d={d} />
                  </td>
                  <td>
                    <div className="flex flex-wrap gap-1">
                      {tags.map((t) => (
                        <DayTag key={t.label} label={t.label} variant={t.variant} />
                      ))}
                      {d.correctionNote && !tags.length && <span className="text-xs text-[var(--text-muted)]">{d.correctionNote}</span>}
                    </div>
                  </td>
                  {data.capabilities.canEditDays ? (
                    <td className="cell-actions">
                      <AttendanceDayEditor employeeId={data.employee.id} day={d} />
                    </td>
                  ) : null}
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}
