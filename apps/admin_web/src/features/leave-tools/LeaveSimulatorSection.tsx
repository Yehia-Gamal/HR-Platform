import React, { useMemo, useState } from 'react';
import {
  AlertTriangle,
  CalendarCheck,
  CalendarDays,
  CheckCircle2,
  Clock,
  Sparkles,
  Users,
  Send,
  Info,
} from 'lucide-react';
import { cairoTodayIso } from '../../core/cairoTime';
import { safeErrorMessage } from '../../core/errorMapper';
import { useEmployees } from '../employees/useEmployees';
import { useAdminLeaves } from '../leaves/useLeaves';
import { useCreateLeaveForEmployee, useLeaveTypes } from './useLeaveTools';
import { UserAvatar } from '../../ui/UserAvatar';

const LEAVE_TYPE_CODES: Record<string, string> = {
  annual: 'سنوية',
  casual: 'عارضة',
  sick: 'مرضية',
  weekly_rest_comp: 'بدل راحة',
  unpaid: 'بدون أجر',
};

// حساب الأيام المستبعد منها الجمعة والسبت كإجازات أسبوعية اعتيادية
function countWorkingDays(startStr: string, endStr: string): { totalDays: number; workDays: number } {
  if (!startStr || !endStr) return { totalDays: 0, workDays: 0 };
  const start = new Date(startStr);
  const end = new Date(endStr);
  if (end < start) return { totalDays: 0, workDays: 0 };

  let totalDays = 0;
  let workDays = 0;
  const current = new Date(start);

  while (current <= end) {
    totalDays++;
    const dayOfWeek = current.getDay(); // 5 = Friday
    if (dayOfWeek !== 5) {
      workDays++;
    }
    current.setDate(current.getDate() + 1);
  }

  return { totalDays, workDays };
}

export function LeaveSimulatorSection() {
  const today = cairoTodayIso();
  const currentYear = new Date().getFullYear();

  const { data: employees = [], isLoading: loadingEmployees } = useEmployees();
  const { data: leaveTypes = [] } = useLeaveTypes();
  const { data: leavesData } = useAdminLeaves({ year: currentYear });
  const createLeave = useCreateLeaveForEmployee();

  const [employeeId, setEmployeeId] = useState<string>('');
  const [leaveTypeCode, setLeaveTypeCode] = useState<string>('annual');
  const [startDate, setStartDate] = useState<string>(today);
  const [endDate, setEndDate] = useState<string>(today);
  const [reason, setReason] = useState<string>('تخطيط إجازة ومحاكاة الرصيد');
  const [submittedSuccess, setSubmittedSuccess] = useState<boolean>(false);
  const [submitError, setSubmitError] = useState<string | null>(null);

  // الموظف المحدد
  const selectedEmployee = useMemo(() => {
    if (!employeeId && employees.length > 0) {
      return employees[0];
    }
    return employees.find((e) => e.id === employeeId) ?? employees[0];
  }, [employees, employeeId]);

  // تعيين الموظف الافتراضي
  React.useEffect(() => {
    if (!employeeId && employees.length > 0) {
      setEmployeeId(employees[0].id);
    }
  }, [employees, employeeId]);

  // حساب الأيام
  const { totalDays, workDays } = useMemo(
    () => countWorkingDays(startDate, endDate),
    [startDate, endDate],
  );

  // رصيد افتراضي وتقديري للمحاكاة
  const balanceInfo = useMemo(() => {
    let initialBalance = 21;
    if (leaveTypeCode === 'casual') initialBalance = 5;
    if (leaveTypeCode === 'weekly_rest_comp') initialBalance = 4;
    if (leaveTypeCode === 'sick') initialBalance = 30;

    const remainingNow = Math.max(0, initialBalance - workDays);
    const isSufficient = leaveTypeCode === 'sick' || leaveTypeCode === 'unpaid' || initialBalance >= workDays;

    return {
      initialBalance,
      workDays,
      totalDays,
      remainingNow,
      isSufficient,
      endOfYearForecast: remainingNow,
    };
  }, [leaveTypeCode, workDays, totalDays]);

  // كاشف تعارض إجازات الزملاء في نفس القسم
  const conflicts = useMemo(() => {
    if (!selectedEmployee || !startDate || !endDate || !leavesData?.rows) {
      return [];
    }

    const start = new Date(startDate).getTime();
    const end = new Date(endDate).getTime();
    const myDept = selectedEmployee.department;

    return leavesData.rows.filter((row) => {
      // استبعاد نفس الموظف
      if (row.employeeId === selectedEmployee.id) return false;

      // تحقق من نفس القسم
      const peerEmp = employees.find((e) => e.id === row.employeeId);
      const isSameDept = peerEmp && myDept && peerEmp.department === myDept;
      if (!isSameDept && myDept) return false;

      // استبعاد الطلبات المرفوضة أو الملغية
      if (['rejected', 'cancelled', 'withdrawn'].includes(row.status)) return false;

      // فحص التداخل الزمني
      const rowStart = new Date(row.startDate).getTime();
      const rowEnd = new Date(row.endDate).getTime();

      const overlaps = rowStart <= end && rowEnd >= start;
      return overlaps;
    });
  }, [selectedEmployee, startDate, endDate, leavesData, employees]);

  async function handleCreateLeave() {
    if (!selectedEmployee || !startDate || !endDate) return;
    setSubmitError(null);
    setSubmittedSuccess(false);

    try {
      await createLeave.mutateAsync({
        employeeId: selectedEmployee.id,
        leaveType: leaveTypeCode,
        startDate,
        endDate,
        reason,
        title: `إجازة ${LEAVE_TYPE_CODES[leaveTypeCode] ?? leaveTypeCode}`,
      });
      setSubmittedSuccess(true);
    } catch (err) {
      setSubmitError(safeErrorMessage(err));
    }
  }

  return (
    <div className="card space-y-5 p-5 border border-brand/20 bg-[var(--surface-card)]">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2.5">
          <span className="rounded-xl bg-brand/10 p-2 text-brand">
            <Sparkles className="size-5" aria-hidden="true" />
          </span>
          <div>
            <h2 className="text-sm font-black text-[var(--text-primary)]">محاكي ومخطط الإجازات الذكي</h2>
            <p className="text-xs text-[var(--text-muted)]">
              محاكاة الرصيد حتى نهاية العام وكشف تعارض إجازات الزملاء في نفس القسم مسبقاً
            </p>
          </div>
        </div>
        <span className="rounded-lg bg-emerald-500/10 px-2.5 py-1 text-xs font-bold text-emerald-600 dark:text-emerald-400 border border-emerald-500/20">
          منع التعارضات
        </span>
      </div>

      {submitError ? (
        <div className="rounded-xl bg-rose-500/10 p-3 text-xs text-rose-600 dark:text-rose-400 border border-rose-500/20">
          {submitError}
        </div>
      ) : null}

      {submittedSuccess ? (
        <div className="rounded-xl bg-emerald-500/10 p-3 text-xs text-emerald-600 dark:text-emerald-400 border border-emerald-500/20 flex items-center gap-2">
          <CheckCircle2 className="size-4 shrink-0" />
          <span>تم إنشاء واعتماد طلب الإجازة بنجاح في سجلات المنظومة!</span>
        </div>
      ) : null}

      {/* Inputs Grid */}
      <div className="grid gap-3 sm:grid-cols-2">
        {/* الموظف */}
        <label className="block">
          <span className="mb-1.5 block text-xs font-bold text-[var(--text-muted)]">اختيار الموظف</span>
          <select
            value={selectedEmployee?.id ?? ''}
            onChange={(e) => setEmployeeId(e.target.value)}
            disabled={loadingEmployees || createLeave.isPending}
            className="input w-full text-xs font-bold"
          >
            {employees.map((emp) => (
              <option key={emp.id} value={emp.id}>
                {emp.fullNameAr} {emp.department ? `(${emp.department})` : ''}
              </option>
            ))}
          </select>
        </label>

        {/* نوع الإجازة */}
        <label className="block">
          <span className="mb-1.5 block text-xs font-bold text-[var(--text-muted)]">نوع الإجازة</span>
          <select
            value={leaveTypeCode}
            onChange={(e) => setLeaveTypeCode(e.target.value)}
            disabled={createLeave.isPending}
            className="input w-full text-xs font-bold"
          >
            <option value="annual">إجازة سنوية (اعتيادية)</option>
            <option value="casual">إجازة عارضة</option>
            <option value="weekly_rest_comp">بدل راحة أسبوعي</option>
            <option value="sick">إجازة مرضية</option>
            <option value="unpaid">إجازة بدون أجر</option>
          </select>
        </label>

        {/* من تاريخ */}
        <label className="block">
          <span className="mb-1.5 block text-xs font-bold text-[var(--text-muted)]">من تاريخ</span>
          <input
            type="date"
            value={startDate}
            onChange={(e) => {
              setStartDate(e.target.value);
              if (new Date(e.target.value) > new Date(endDate)) {
                setEndDate(e.target.value);
              }
            }}
            disabled={createLeave.isPending}
            className="input w-full text-xs font-bold"
          />
        </label>

        {/* إلى تاريخ */}
        <label className="block">
          <span className="mb-1.5 block text-xs font-bold text-[var(--text-muted)]">إلى تاريخ</span>
          <input
            type="date"
            value={endDate}
            onChange={(e) => setEndDate(e.target.value)}
            min={startDate}
            disabled={createLeave.isPending}
            className="input w-full text-xs font-bold"
          />
        </label>
      </div>

      {/* Simulator Metrics Box */}
      <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface-raised)] p-4 space-y-3">
        <div className="flex items-center justify-between border-b border-[var(--border)] pb-2.5">
          <div className="flex items-center gap-2">
            <CalendarCheck className="size-4 text-brand" />
            <span className="text-xs font-black text-[var(--text-primary)]">نتيجة المحاكاة التقديرية</span>
          </div>
          <span className="text-xs font-bold text-[var(--text-muted)]">
            المدة: {totalDays} يوم تقويمي ({workDays} يوم عمل)
          </span>
        </div>

        <div className="grid grid-cols-3 gap-2 text-center">
          <div className="rounded-xl border border-[var(--border)] bg-[var(--surface-card)] p-2.5">
            <span className="block text-[10px] text-[var(--text-muted)]">الرصيد التقديري</span>
            <strong className="text-sm font-black text-[var(--text-primary)]">{balanceInfo.initialBalance} يوم</strong>
          </div>
          <div className="rounded-xl border border-[var(--border)] bg-[var(--surface-card)] p-2.5">
            <span className="block text-[10px] text-[var(--text-muted)]">المطلوب خصمه</span>
            <strong className="text-sm font-black text-amber-600 dark:text-amber-400">{workDays} يوم</strong>
          </div>
          <div className="rounded-xl border border-[var(--border)] bg-[var(--surface-card)] p-2.5">
            <span className="block text-[10px] text-[var(--text-muted)]">المتبقي لنهاية العام</span>
            <strong className="text-sm font-black text-emerald-600 dark:text-emerald-400">{balanceInfo.remainingNow} يوم</strong>
          </div>
        </div>

        {balanceInfo.isSufficient ? (
          <div className="flex items-center gap-2 rounded-xl bg-emerald-500/10 px-3 py-2 text-xs text-emerald-700 dark:text-emerald-300 border border-emerald-500/20">
            <CheckCircle2 className="size-4 shrink-0 text-emerald-600" />
            <span>رصيد الموظف كافٍ وسيتبقى له {balanceInfo.remainingNow} أيام حتى نهاية العام.</span>
          </div>
        ) : (
          <div className="flex items-center gap-2 rounded-xl bg-rose-500/10 px-3 py-2 text-xs text-rose-700 dark:text-rose-300 border border-rose-500/20">
            <AlertTriangle className="size-4 shrink-0 text-rose-600" />
            <span>تنبيه: الرصيد المتاح غير كافٍ لتغطية كامل مدة الإجازة المطلوبة!</span>
          </div>
        )}
      </div>

      {/* Conflict Radar Box */}
      <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface-raised)] p-4 space-y-2.5">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Users className="size-4 text-[var(--text-muted)]" />
            <span className="text-xs font-black text-[var(--text-primary)]">
              رادار تعارضات القسم ({selectedEmployee?.department || 'القسم التابع'})
            </span>
          </div>
          {conflicts.length > 0 ? (
            <span className="rounded-lg bg-amber-500/15 px-2 py-0.5 text-[11px] font-black text-amber-600 dark:text-amber-400">
              يوجد {conflicts.length} تعارض
            </span>
          ) : (
            <span className="rounded-lg bg-emerald-500/15 px-2 py-0.5 text-[11px] font-black text-emerald-600 dark:text-emerald-400">
              لا يوجد تعارض
            </span>
          )}
        </div>

        {conflicts.length > 0 ? (
          <div className="space-y-2">
            {conflicts.map((c) => (
              <div
                key={c.requestId}
                className="flex items-start gap-2.5 rounded-xl border border-amber-500/30 bg-amber-500/10 p-3 text-xs text-amber-800 dark:text-amber-200"
              >
                <AlertTriangle className="size-4 shrink-0 text-amber-600 mt-0.5" />
                <div className="space-y-0.5">
                  <p className="font-bold">
                    الزميل <strong>«{c.employeeName}»</strong> لديه إجازة {c.leaveTypeName || 'مجدولة'}
                  </p>
                  <p className="text-[11px] opacity-90">
                    من {c.startDate} إلى {c.endDate} — يُرجى التنسيق المسبق لتفادي انقطاع العمل بالقسم.
                  </p>
                </div>
              </div>
            ))}
          </div>
        ) : (
          <p className="text-xs text-[var(--text-muted)] flex items-center gap-1.5">
            <CheckCircle2 className="size-3.5 text-emerald-500 shrink-0" />
            <span>لا توجد إجازات معتمدة أو معلقة لزملاء آخرين في نفس القسم خلال هذه الفترة.</span>
          </p>
        )}
      </div>

      {/* Action Button */}
      <button
        type="button"
        onClick={() => void handleCreateLeave()}
        disabled={createLeave.isPending || totalDays <= 0}
        className="btn-primary w-full py-2.5 text-xs font-black flex items-center justify-center gap-2"
      >
        <Send className="size-3.5" />
        <span>
          {createLeave.isPending
            ? 'جارٍ اعتماد الإجازة...'
            : `اعتماد وإنشاء الإجازة لـ ${selectedEmployee?.fullNameAr || 'الموظف'} (${workDays} أيام)`}
        </span>
      </button>
    </div>
  );
}
