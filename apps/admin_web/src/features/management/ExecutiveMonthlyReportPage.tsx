import React, { useState } from 'react';
import {
  Calendar,
  Download,
  RefreshCw,
  Users,
  CheckCircle2,
  Clock,
  AlertTriangle,
  Briefcase,
  FileText,
  DollarSign,
  TrendingUp,
  BarChart3,
  Award,
} from 'lucide-react';
import { useExecutiveMonthlyReport } from './useExecutiveMonthlyReport';
import { exportExecutiveMonthlyReport } from './exportExecutiveMonthlyReport';

const MONTH_NAMES = [
  { value: 1, label: 'يناير' },
  { value: 2, label: 'فبراير' },
  { value: 3, label: 'مارس' },
  { value: 4, label: 'أبريل' },
  { value: 5, label: 'مايو' },
  { value: 6, label: 'يونيو' },
  { value: 7, label: 'يوليو' },
  { value: 8, label: 'أغسطس' },
  { value: 9, label: 'سبتمبر' },
  { value: 10, label: 'أكتوبر' },
  { value: 11, label: 'نوفمبر' },
  { value: 12, label: 'ديسمبر' },
];

const AVAILABLE_YEARS = [2026, 2025, 2024];

export function ExecutiveMonthlyReportPage() {
  const now = new Date();
  const [selectedYear, setSelectedYear] = useState<number>(now.getFullYear());
  const [selectedMonth, setSelectedMonth] = useState<number>(now.getMonth() + 1);
  const [isExporting, setIsExporting] = useState<boolean>(false);
  const [exportError, setExportError] = useState<string | null>(null);

  const { data: report, isLoading, isError, error, refetch, regenerate, isRegenerating } =
    useExecutiveMonthlyReport(selectedYear, selectedMonth);

  const handleExportPdf = async () => {
    if (!report) return;
    setIsExporting(true);
    setExportError(null);
    try {
      await exportExecutiveMonthlyReport(report);
    } catch (err) {
      console.error(err);
      setExportError('حدث خطأ أثناء تصدير التقرير، يرجى المحاولة مرة أخرى.');
    } finally {
      setIsExporting(false);
    }
  };

  const handleRegenerate = async () => {
    try {
      await regenerate();
    } catch (err) {
      console.error('Failed to regenerate report:', err);
    }
  };

  return (
    <div className="space-y-6" dir="rtl">
      {/* رأس الصفحة وأدوات التحكم */}
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <div className="flex items-center gap-2">
            <h1 className="text-2xl font-black text-[var(--text-strong)]">
              التقرير الشهري التنفيذي الشامل
            </h1>
            {report && (
              <span
                className={`inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-xs font-black ${
                  report.period.isFinal
                    ? 'bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 border border-emerald-500/20'
                    : 'bg-blue-500/10 text-blue-600 dark:text-blue-400 border border-blue-500/20'
                }`}
              >
                {report.period.isFinal ? 'نهائي ومعتمد' : `مؤقت حتى ${report.period.effectiveEndDate}`}
              </span>
            )}
          </div>
          <p className="mt-1 text-sm text-[var(--text-muted)]">
            الملخص الاستراتيجي لحضور المؤسسة، أداء الإدارات، الطلبات والمأموريات ومؤشرات الحوكمة
          </p>
        </div>

        {/* أدوات التاريخ والأزرار */}
        <div className="flex flex-wrap items-center gap-2">
          <div className="flex items-center gap-1 rounded-xl border border-[var(--border)] bg-[var(--surface-raised)] p-1">
            <Calendar className="mr-2 h-4 w-4 text-[var(--text-muted)]" />
            <select
              aria-label="اختر الشهر"
              value={selectedMonth}
              onChange={(e) => setSelectedMonth(Number(e.target.value))}
              className="rounded-lg bg-transparent px-2 py-1 text-sm font-bold text-[var(--text-strong)] focus:outline-none"
            >
              {MONTH_NAMES.map((m) => (
                <option key={m.value} value={m.value} className="bg-[var(--surface)] text-[var(--text-strong)]">
                  {m.label}
                </option>
              ))}
            </select>
            <select
              aria-label="اختر السنة"
              value={selectedYear}
              onChange={(e) => setSelectedYear(Number(e.target.value))}
              className="rounded-lg bg-transparent px-2 py-1 text-sm font-bold text-[var(--text-strong)] focus:outline-none"
            >
              {AVAILABLE_YEARS.map((y) => (
                <option key={y} value={y} className="bg-[var(--surface)] text-[var(--text-strong)]">
                  {y}
                </option>
              ))}
            </select>
          </div>

          <button
            type="button"
            onClick={handleRegenerate}
            disabled={isRegenerating || isLoading}
            className="flex items-center gap-1.5 rounded-xl border border-[var(--border)] bg-[var(--surface-raised)] px-3.5 py-2 text-xs font-bold text-[var(--text-strong)] hover:bg-[var(--surface-hover)] disabled:opacity-50"
            title="إعادة احتساب وتحديث التقرير"
          >
            <RefreshCw className={`h-4 w-4 ${isRegenerating ? 'animate-spin text-[var(--brand-primary)]' : ''}`} />
            <span>تحديث التقرير</span>
          </button>

          <button
            type="button"
            onClick={handleExportPdf}
            disabled={isExporting || isLoading || !report}
            className="flex items-center gap-1.5 rounded-xl bg-[var(--brand-primary)] px-4 py-2 text-xs font-bold text-white shadow-sm hover:opacity-90 disabled:opacity-50 transition-opacity"
          >
            <Download className={`h-4 w-4 ${isExporting ? 'animate-bounce' : ''}`} />
            <span>{isExporting ? 'جارٍ التصدير...' : 'تصدير PDF'}</span>
          </button>
        </div>
      </div>

      {exportError && (
        <div className="rounded-xl border border-red-500/20 bg-red-500/10 p-3 text-xs text-red-600 dark:text-red-400">
          {exportError}
        </div>
      )}

      {/* حالة التحميل أو الخطأ */}
      {isLoading ? (
        <div className="flex h-64 flex-col items-center justify-center gap-3 rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-8 text-center">
          <RefreshCw className="h-8 w-8 animate-spin text-[var(--brand-primary)]" />
          <p className="text-sm font-bold text-[var(--text-muted)]">جارٍ استخراج وتجميع بيانات التقرير الشهري...</p>
        </div>
      ) : isError ? (
        <div className="flex h-64 flex-col items-center justify-center gap-3 rounded-2xl border border-red-500/20 bg-red-500/5 p-8 text-center">
          <AlertTriangle className="h-8 w-8 text-red-500" />
          <p className="text-sm font-bold text-red-600 dark:text-red-400">
            فشل استخراج التقرير: {(error as Error)?.message || 'تأكد من الصلاحيات أو محاولة الشهر'}
          </p>
          <button
            type="button"
            onClick={() => void refetch()}
            className="mt-2 rounded-lg bg-[var(--surface-raised)] px-4 py-1.5 text-xs font-bold text-[var(--text-strong)] hover:bg-[var(--surface-hover)]"
          >
            إعادة المحاولة
          </button>
        </div>
      ) : report ? (
        <>
          {/* بطاقات المؤشرات الرئيسية (KPI Cards) */}
          <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
            <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-4 shadow-sm">
              <div className="flex items-center justify-between">
                <span className="text-xs font-bold text-[var(--text-muted)]">نسبة الحضور العامة</span>
                <span className="rounded-lg bg-emerald-500/10 p-2 text-emerald-600 dark:text-emerald-400">
                  <TrendingUp className="h-4 w-4" />
                </span>
              </div>
              <div className="mt-2 flex items-baseline gap-2">
                <span className="text-2xl font-black text-[var(--text-strong)]">
                  {report.attendance.attendance_rate.toFixed(1)}%
                </span>
                <span className="text-xs text-[var(--text-muted)]">
                  ({report.attendance.attended_days} من {report.attendance.required_days} يوم)
                </span>
              </div>
            </div>

            <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-4 shadow-sm">
              <div className="flex items-center justify-between">
                <span className="text-xs font-bold text-[var(--text-muted)]">الموظفون النشطون</span>
                <span className="rounded-lg bg-blue-500/10 p-2 text-blue-600 dark:text-blue-400">
                  <Users className="h-4 w-4" />
                </span>
              </div>
              <div className="mt-2 flex items-baseline gap-2">
                <span className="text-2xl font-black text-[var(--text-strong)]">
                  {report.attendance.active_employees_count}
                </span>
                <span className="text-xs text-[var(--text-muted)]">موظف بالمنظومة</span>
              </div>
            </div>

            <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-4 shadow-sm">
              <div className="flex items-center justify-between">
                <span className="text-xs font-bold text-[var(--text-muted)]">حركة الطلبات والمعتمدة</span>
                <span className="rounded-lg bg-purple-500/10 p-2 text-purple-600 dark:text-purple-400">
                  <CheckCircle2 className="h-4 w-4" />
                </span>
              </div>
              <div className="mt-2 flex items-baseline gap-2">
                <span className="text-2xl font-black text-[var(--text-strong)]">
                  {report.requests.approved_count}
                </span>
                <span className="text-xs text-[var(--text-muted)]">
                  معتمد من إجمالي {report.requests.total_requests}
                </span>
              </div>
            </div>

            <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-4 shadow-sm">
              <div className="flex items-center justify-between">
                <span className="text-xs font-bold text-[var(--text-muted)]">سرعة الاعتماد (SLA)</span>
                <span className="rounded-lg bg-amber-500/10 p-2 text-amber-600 dark:text-amber-400">
                  <Clock className="h-4 w-4" />
                </span>
              </div>
              <div className="mt-2 flex items-baseline gap-2">
                <span className="text-2xl font-black text-[var(--text-strong)]">
                  {report.sla.avg_turnaround_hours.toFixed(1)} س
                </span>
                <span className="text-xs text-[var(--text-muted)]">
                  وسيط: {report.sla.median_turnaround_hours.toFixed(1)} س
                </span>
              </div>
            </div>
          </div>

          {/* جدول أداء وانضباط الإدارات */}
          <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-5 shadow-sm">
            <div className="mb-4 flex items-center justify-between">
              <div className="flex items-center gap-2">
                <BarChart3 className="h-5 w-5 text-[var(--brand-primary)]" />
                <h2 className="text-base font-black text-[var(--text-strong)]">
                  أداء الحضور والانضباط عبر الإدارات والأقسام
                </h2>
              </div>
              <span className="text-xs text-[var(--text-muted)]">
                {report.departments.length} إدارات مسجلة
              </span>
            </div>

            <div className="overflow-x-auto">
              <table className="w-full text-right text-xs">
                <thead>
                  <tr className="border-b border-[var(--border)] text-[var(--text-muted)]">
                    <th className="pb-3 font-black">الإدارة / القسم</th>
                    <th className="pb-3 text-center font-black">الموظفون</th>
                    <th className="pb-3 text-center font-black">الأيام المطلوبة</th>
                    <th className="pb-3 text-center font-black">الحضور</th>
                    <th className="pb-3 text-center font-black">الغياب</th>
                    <th className="pb-3 text-center font-black">التأخير (أيام)</th>
                    <th className="pb-3 text-center font-black">دقائق التأخير</th>
                    <th className="pb-3 text-center font-black">نسبة الانضباط</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-[var(--border)]">
                  {report.departments.map((dept, idx) => (
                    <tr key={idx} className="hover:bg-[var(--surface-hover)] transition-colors">
                      <td className="py-3 font-bold text-[var(--text-strong)]">
                        {dept.department_name}
                      </td>
                      <td className="py-3 text-center text-[var(--text-muted)] font-medium">
                        {dept.employees_count}
                      </td>
                      <td className="py-3 text-center text-[var(--text-muted)] font-medium">
                        {dept.required_days}
                      </td>
                      <td className="py-3 text-center font-bold text-emerald-600 dark:text-emerald-400">
                        {dept.attended_days}
                      </td>
                      <td className="py-3 text-center font-bold">
                        {dept.absent_days > 0 ? (
                          <span className="text-red-600 dark:text-red-400">{dept.absent_days}</span>
                        ) : (
                          <span className="text-[var(--text-muted)]">0</span>
                        )}
                      </td>
                      <td className="py-3 text-center text-[var(--text-muted)]">
                        {dept.late_days}
                      </td>
                      <td className="py-3 text-center text-[var(--text-muted)]">
                        {dept.total_late_minutes} د
                      </td>
                      <td className="py-3 text-center">
                        <span
                          className={`inline-block rounded-md px-2 py-0.5 font-black ${
                            dept.attendance_rate >= 90
                              ? 'bg-emerald-500/10 text-emerald-600 dark:text-emerald-400'
                              : dept.attendance_rate >= 75
                              ? 'bg-amber-500/10 text-amber-600 dark:text-amber-400'
                              : 'bg-red-500/10 text-red-600 dark:text-red-400'
                          }`}
                        >
                          {dept.attendance_rate.toFixed(1)}%
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>

          {/* شبكة التفاصيل المتخصصة */}
          <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
            {/* إحصاءات الحضور التفصيلية */}
            <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-5 shadow-sm">
              <div className="mb-3 flex items-center gap-2">
                <Award className="h-5 w-5 text-blue-500" />
                <h3 className="text-sm font-black text-[var(--text-strong)]">
                  حقائق الحضور والغياب (Attendance Day Facts)
                </h3>
              </div>
              <div className="space-y-2 text-xs divide-y divide-[var(--border)]">
                <div className="flex justify-between py-1.5">
                  <span className="text-[var(--text-muted)]">أيام التقويم الإجمالية للموظفين:</span>
                  <span className="font-bold text-[var(--text-strong)]">{report.attendance.total_calendar_days}</span>
                </div>
                <div className="flex justify-between py-1.5">
                  <span className="text-[var(--text-muted)]">أيام العمل الواجبة:</span>
                  <span className="font-bold text-[var(--text-strong)]">{report.attendance.required_days}</span>
                </div>
                <div className="flex justify-between py-1.5">
                  <span className="text-[var(--text-muted)]">أيام الحضور الفعلي:</span>
                  <span className="font-bold text-emerald-600 dark:text-emerald-400">{report.attendance.attended_days}</span>
                </div>
                <div className="flex justify-between py-1.5">
                  <span className="text-[var(--text-muted)]">أيام الغياب غير المصرح:</span>
                  <span className="font-bold text-red-600 dark:text-red-400">{report.attendance.absent_days}</span>
                </div>
                <div className="flex justify-between py-1.5">
                  <span className="text-[var(--text-muted)]">إجمالي دقائق التأخير المسجلة:</span>
                  <span className="font-bold text-amber-600 dark:text-amber-400">{report.attendance.total_late_minutes} دقيقة</span>
                </div>
                <div className="flex justify-between py-1.5">
                  <span className="text-[var(--text-muted)]">أيام الإجازات المعتمدة:</span>
                  <span className="font-bold text-[var(--text-strong)]">{report.attendance.leave_days}</span>
                </div>
                <div className="flex justify-between py-1.5">
                  <span className="text-[var(--text-muted)]">أيام المأموريات والقوافل الميدانية:</span>
                  <span className="font-bold text-[var(--text-strong)]">{report.attendance.offsite_days}</span>
                </div>
              </div>
            </div>

            {/* حركة الطلبات والمعاملات */}
            <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-5 shadow-sm">
              <div className="mb-3 flex items-center gap-2">
                <FileText className="h-5 w-5 text-purple-500" />
                <h3 className="text-sm font-black text-[var(--text-strong)]">
                  حركة الطلبات والمعاملات الإدارية
                </h3>
              </div>
              <div className="space-y-2 text-xs divide-y divide-[var(--border)]">
                <div className="flex justify-between py-1.5">
                  <span className="text-[var(--text-muted)]">إجمالي الطلبات المقدمة:</span>
                  <span className="font-bold text-[var(--text-strong)]">{report.requests.total_requests}</span>
                </div>
                <div className="flex justify-between py-1.5">
                  <span className="text-[var(--text-muted)]">الطلبات المعتمدة:</span>
                  <span className="font-bold text-emerald-600 dark:text-emerald-400">{report.requests.approved_count}</span>
                </div>
                <div className="flex justify-between py-1.5">
                  <span className="text-[var(--text-muted)]">الطلبات المرفوضة:</span>
                  <span className="font-bold text-red-600 dark:text-red-400">{report.requests.rejected_count}</span>
                </div>
                <div className="flex justify-between py-1.5">
                  <span className="text-[var(--text-muted)]">طلبات قيد المراجعة:</span>
                  <span className="font-bold text-amber-600 dark:text-amber-400">{report.requests.pending_count}</span>
                </div>
                <div className="flex justify-between py-1.5">
                  <span className="text-[var(--text-muted)]">طلبات الإجازات:</span>
                  <span className="font-bold text-[var(--text-strong)]">{report.requests.leave_requests}</span>
                </div>
                <div className="flex justify-between py-1.5">
                  <span className="text-[var(--text-muted)]">المأموريات والقوافل الميدانية:</span>
                  <span className="font-bold text-[var(--text-strong)]">
                    {report.requests.mission_requests + report.requests.convoy_requests}
                  </span>
                </div>
                <div className="flex justify-between py-1.5">
                  <span className="text-[var(--text-muted)]">أذونات التأخير والانصراف:</span>
                  <span className="font-bold text-[var(--text-strong)]">{report.requests.permit_requests}</span>
                </div>
              </div>
            </div>

            {/* المأموريات الميدانية والامتثال */}
            <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-5 shadow-sm">
              <div className="mb-3 flex items-center gap-2">
                <Briefcase className="h-5 w-5 text-indigo-500" />
                <h3 className="text-sm font-black text-[var(--text-strong)]">
                  المأموريات الميدانية ومتابعة التقارير
                </h3>
              </div>
              <div className="space-y-2 text-xs divide-y divide-[var(--border)]">
                <div className="flex justify-between py-1.5">
                  <span className="text-[var(--text-muted)]">إجمالي المأموريات المنفذة:</span>
                  <span className="font-bold text-[var(--text-strong)]">{report.missions.total_executions}</span>
                </div>
                <div className="flex justify-between py-1.5">
                  <span className="text-[var(--text-muted)]">المأموريات المنجزة بالكامل:</span>
                  <span className="font-bold text-emerald-600 dark:text-emerald-400">{report.missions.completed_count}</span>
                </div>
                <div className="flex justify-between py-1.5">
                  <span className="text-[var(--text-muted)]">أغلقت تلقائياً لعدم الإكمال:</span>
                  <span className="font-bold text-amber-600 dark:text-amber-400">{report.missions.auto_closed_count}</span>
                </div>
                <div className="flex justify-between py-1.5">
                  <span className="text-[var(--text-muted)]">تقارير المأموريات الموثقة:</span>
                  <span className="font-bold text-[var(--text-strong)]">{report.missions.reported_count}</span>
                </div>
              </div>
            </div>

            {/* الغرامات وصندوق الزمالة وسرعة الرد */}
            <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-5 shadow-sm">
              <div className="mb-3 flex items-center gap-2">
                <DollarSign className="h-5 w-5 text-emerald-500" />
                <h3 className="text-sm font-black text-[var(--text-strong)]">
                  الغرامات الفورية وصندوق الزمالة والـ SLA
                </h3>
              </div>
              <div className="space-y-2 text-xs divide-y divide-[var(--border)]">
                <div className="flex justify-between py-1.5">
                  <span className="text-[var(--text-muted)]">إجمالي الغرامات المحررة:</span>
                  <span className="font-bold text-[var(--text-strong)]">{report.penalties.total_penalties}</span>
                </div>
                <div className="flex justify-between py-1.5">
                  <span className="text-[var(--text-muted)]">المبالغ المسددة لصندوق الزمالة:</span>
                  <span className="font-bold text-emerald-600 dark:text-emerald-400">
                    {report.penalties.paid_amount} ج.م ({report.penalties.paid_count} مسددة)
                  </span>
                </div>
                <div className="flex justify-between py-1.5">
                  <span className="text-[var(--text-muted)]">غرامات معلقة أو قيد النزاع:</span>
                  <span className="font-bold text-amber-600 dark:text-amber-400">
                    {report.penalties.total_amount - report.penalties.paid_amount} ج.م ({report.penalties.unpaid_count} متبقية)
                  </span>
                </div>
                <div className="flex justify-between py-1.5">
                  <span className="text-[var(--text-muted)]">وسيط سرعة اتخاذ القرارات:</span>
                  <span className="font-bold text-[var(--text-strong)]">{report.sla.median_turnaround_hours.toFixed(1)} ساعة</span>
                </div>
                <div className="flex justify-between py-1.5">
                  <span className="text-[var(--text-muted)]">الطلبات المصعدة لتجاوز الـ SLA:</span>
                  <span className="font-bold text-amber-600 dark:text-amber-400">{report.sla.escalated_count}</span>
                </div>
              </div>
            </div>
          </div>
        </>
      ) : null}
    </div>
  );
}
