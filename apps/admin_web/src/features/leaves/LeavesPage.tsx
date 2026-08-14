import { LEAVE_TYPE_COLORS, LEAVE_TYPE_LABELS, type LeaveAdminRow } from '@ahla/shared-contracts';
import { CalendarDays, Check, Clock3, Download, FileX, X } from 'lucide-react';
import { useMemo, useState } from 'react';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { ListSkeleton, MetricSkeletonRow } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';
import { UserAvatar } from '../../ui/UserAvatar';
import { safeErrorMessage } from '../../core/errorMapper';
import { useAdminLeaveDecision, useAdminLeaves } from './useLeaves';

// ─── ثوابت ───────────────────────────────────────────────────────────────────

const STATUS_TABS = [
  { key: '', label: 'الكل' },
  { key: 'pending', label: 'قيد المراجعة' },
  { key: 'approved', label: 'معتمدة' },
  { key: 'rejected', label: 'مرفوضة' },
  { key: 'cancelled', label: 'ملغية' },
  { key: 'returned', label: 'معادة' },
  { key: 'withdrawn', label: 'مسحوبة' },
  { key: 'escalated', label: 'مُصعَّدة' },
] as const;

const LEAVE_TYPE_TABS = [
  { key: '', label: 'كل الأنواع' },
  { key: 'annual', label: 'سنوية' },
  { key: 'casual', label: 'عارضة' },
  { key: 'sick', label: 'مرضية' },
  { key: 'unpaid', label: 'بدون أجر' },
] as const;

const STATUS_AR: Record<string, string> = {
  pending: 'قيد المراجعة',
  approved: 'معتمدة',
  rejected: 'مرفوضة',
  cancelled: 'ملغية',
  returned: 'معادة للمراجعة',
  withdrawn: 'مسحوبة',
  escalated: 'مُصعَّدة',
  draft: 'مسودة',
  expired: 'منتهية الصلاحية',
};

const CURRENT_YEAR = new Date().getFullYear();
const YEAR_OPTIONS = Array.from({ length: 3 }, (_, i) => CURRENT_YEAR - i);

// ─── مساعدات ─────────────────────────────────────────────────────────────────

function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString('ar-EG', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
}

function exportToCsv(rows: LeaveAdminRow[], year: number) {
  const headers = ['#', 'الموظف', 'الكود', 'نوع الإجازة', 'الحالة', 'من', 'إلى', 'المدة', 'بأجر', 'السبب'];
  const escape = (v: string | null | number) => {
    const s = String(v ?? '');
    return s.includes(',') || s.includes('"') || s.includes('\n') ? `"${s.replace(/"/g, '""')}"` : s;
  };
  const csvRows = [
    headers.join(','),
    ...rows.map((r, i) =>
      [
        i + 1,
        escape(r.employeeName),
        escape(r.employeeCode),
        escape(LEAVE_TYPE_LABELS[r.leaveTypeCode] ?? r.leaveTypeName),
        escape(STATUS_AR[r.status] ?? r.status),
        r.startDate,
        r.endDate,
        escape(formatDuration(r)),
        r.isPaid ? 'نعم' : 'لا',
        escape(r.reason),
      ].join(','),
    ),
  ];
  const bom = '﻿';
  const blob = new Blob([bom + csvRows.join('\n')], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `إجازات-${year}.csv`;
  a.click();
  URL.revokeObjectURL(url);
}

function formatDuration(row: LeaveAdminRow) {
  if (row.durationUnit === 'hour' && row.hoursCount) {
    return `${row.hoursCount} ساعة`;
  }
  if (row.isHalfDay) return 'نصف يوم';
  const d = Number(row.daysCount);
  if (d === 1) return 'يوم واحد';
  if (d === 2) return 'يومان';
  return `${d} أيام`;
}

// ─── تفاصيل طلب مع موافقة/رفض ───────────────────────────────────────────────

function LeaveDetailDialog({ row, onClose, onDecided }: { row: LeaveAdminRow; onClose: () => void; onDecided: () => void }) {
  const typeColor = LEAVE_TYPE_COLORS[row.leaveTypeCode] ?? '';
  const typeLabel = LEAVE_TYPE_LABELS[row.leaveTypeCode] ?? row.leaveTypeName;
  const [rejectReason, setRejectReason] = useState('');
  const [showRejectForm, setShowRejectForm] = useState(false);
  const decision = useAdminLeaveDecision();

  const isPending = row.status === 'pending';

  function handleApprove() {
    decision.mutate(
      { requestId: row.requestId, decision: 'approve' },
      {
        onSuccess: () => {
          onDecided();
          onClose();
        },
      },
    );
  }

  function handleReject() {
    decision.mutate(
      { requestId: row.requestId, decision: 'reject', comment: rejectReason || undefined },
      {
        onSuccess: () => {
          onDecided();
          onClose();
        },
      },
    );
  }

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label="تفاصيل طلب الإجازة"
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
      onClick={onClose}
    >
      <div className="card w-full max-w-lg space-y-4 p-6" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-start justify-between gap-3">
          <h2 className="text-lg font-bold">تفاصيل طلب الإجازة #{row.requestNumber}</h2>
          <button type="button" onClick={onClose} aria-label="إغلاق" className="rounded-lg p-1 hover:bg-[var(--surface-raised)]">
            <X className="size-5" />
          </button>
        </div>

        {/* الموظف */}
        <div className="flex items-center gap-3 rounded-xl bg-[var(--surface-raised)] p-3">
          <UserAvatar displayName={row.employeeName} size="md" />
          <div>
            <p className="font-bold">{row.employeeName}</p>
            {row.employeeCode && !row.employeeCode.match(/^\+?\d{9,}$/) && <p className="text-xs text-[var(--text-muted)]">{row.employeeCode}</p>}
          </div>
        </div>

        {/* نوع الإجازة والحالة */}
        <div className="flex flex-wrap items-center gap-2">
          <span className={`rounded-full px-2.5 py-0.5 text-xs font-bold ${typeColor}`}>{typeLabel}</span>
          <StatusBadge status={row.status} />
          {row.isPaid ? (
            <span className="rounded-full bg-green-100 px-2.5 py-0.5 text-xs font-bold text-green-700 dark:bg-green-900/40 dark:text-green-300">بأجر</span>
          ) : (
            <span className="rounded-full bg-gray-100 px-2.5 py-0.5 text-xs font-bold text-gray-600 dark:bg-gray-700 dark:text-gray-300">بدون أجر</span>
          )}
        </div>

        {/* التواريخ */}
        <dl className="grid grid-cols-2 gap-3 text-sm">
          <div>
            <dt className="text-xs text-[var(--text-muted)]">من</dt>
            <dd className="font-semibold">{formatDate(row.startDate)}</dd>
          </div>
          <div>
            <dt className="text-xs text-[var(--text-muted)]">إلى</dt>
            <dd className="font-semibold">{formatDate(row.endDate)}</dd>
          </div>
          <div>
            <dt className="text-xs text-[var(--text-muted)]">المدة</dt>
            <dd className="font-semibold">{formatDuration(row)}</dd>
          </div>
          <div>
            <dt className="text-xs text-[var(--text-muted)]">تاريخ الطلب</dt>
            <dd className="font-semibold">{formatDate(row.createdAt)}</dd>
          </div>
        </dl>

        {/* السبب */}
        {row.reason && (
          <div>
            <p className="mb-1 text-xs font-bold text-[var(--text-muted)]">السبب</p>
            <p className="rounded-lg bg-[var(--surface-raised)] p-3 text-sm leading-6">{row.reason}</p>
          </div>
        )}

        {/* ملاحظات التسليم */}
        {row.handoverNotes && (
          <div>
            <p className="mb-1 text-xs font-bold text-[var(--text-muted)]">ملاحظات التسليم</p>
            <p className="rounded-lg bg-[var(--surface-raised)] p-3 text-sm leading-6">{row.handoverNotes}</p>
          </div>
        )}

        {/* المرفق */}
        {row.attachmentUrl && (
          <a
            href={row.attachmentUrl}
            target="_blank"
            rel="noopener noreferrer"
            className="flex items-center gap-2 rounded-lg border border-[var(--border)] p-3 text-sm font-semibold hover:bg-[var(--surface-raised)]"
          >
            <Download className="size-4 shrink-0 text-[var(--brand-primary)]" />
            عرض المرفق
          </a>
        )}

        {/* أزرار الموافقة/الرفض — تظهر فقط للطلبات المعلقة */}
        {isPending && (
          <div className="border-t border-[var(--border)] pt-4 space-y-3">
            {decision.isError && (
              <p className="rounded-lg bg-red-50 p-3 text-sm text-red-700 dark:bg-red-900/20 dark:text-red-400">{safeErrorMessage(decision.error)}</p>
            )}

            {showRejectForm ? (
              <div className="space-y-2">
                <label className="text-xs font-bold text-[var(--text-muted)]">سبب الرفض (اختياري)</label>
                <textarea
                  value={rejectReason}
                  onChange={(e) => setRejectReason(e.target.value)}
                  rows={2}
                  placeholder="أدخل سبب الرفض..."
                  className="input-field w-full resize-none text-sm"
                />
                <div className="flex gap-2">
                  <button
                    type="button"
                    onClick={handleReject}
                    disabled={decision.isPending}
                    className="flex-1 rounded-lg bg-red-600 px-4 py-2 text-sm font-bold text-white transition-colors hover:bg-red-700 disabled:opacity-50"
                  >
                    {decision.isPending ? 'جارٍ الرفض...' : 'تأكيد الرفض'}
                  </button>
                  <button
                    type="button"
                    onClick={() => {
                      setShowRejectForm(false);
                      setRejectReason('');
                    }}
                    disabled={decision.isPending}
                    className="rounded-lg border border-[var(--border)] px-4 py-2 text-sm font-semibold transition-colors hover:bg-[var(--surface-raised)] disabled:opacity-50"
                  >
                    إلغاء
                  </button>
                </div>
              </div>
            ) : (
              <div className="flex gap-2">
                <button
                  type="button"
                  onClick={handleApprove}
                  disabled={decision.isPending}
                  className="flex flex-1 items-center justify-center gap-1.5 rounded-lg bg-green-600 px-4 py-2 text-sm font-bold text-white transition-colors hover:bg-green-700 disabled:opacity-50"
                >
                  <Check className="size-4" />
                  {decision.isPending ? 'جارٍ الاعتماد...' : 'اعتماد'}
                </button>
                <button
                  type="button"
                  onClick={() => setShowRejectForm(true)}
                  disabled={decision.isPending}
                  className="flex flex-1 items-center justify-center gap-1.5 rounded-lg border border-red-300 px-4 py-2 text-sm font-bold text-red-600 transition-colors hover:bg-red-50 disabled:opacity-50 dark:border-red-700 dark:text-red-400 dark:hover:bg-red-900/20"
                >
                  <FileX className="size-4" />
                  رفض
                </button>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

// ─── صف في الجدول ───────────────────────────────────────────────────────────

function LeaveRow({ row, onSelect }: { row: LeaveAdminRow; onSelect: (r: LeaveAdminRow) => void }) {
  const typeColor = LEAVE_TYPE_COLORS[row.leaveTypeCode] ?? '';
  const typeLabel = LEAVE_TYPE_LABELS[row.leaveTypeCode] ?? row.leaveTypeName;

  return (
    <button
      type="button"
      onClick={() => onSelect(row)}
      className="w-full rounded-xl border border-[var(--border)] bg-[var(--surface)] p-4 text-start transition-colors hover:bg-[var(--surface-raised)] focus-visible:ring-2"
    >
      <div className="flex flex-wrap items-center gap-3">
        <UserAvatar displayName={row.employeeName} size="sm" />

        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <span className="font-bold">{row.employeeName}</span>
            {row.employeeCode && !row.employeeCode.match(/^\+?\d{9,}$/) && <span className="text-xs text-[var(--text-muted)]">{row.employeeCode}</span>}
          </div>
          <div className="mt-1 flex flex-wrap items-center gap-2 text-xs text-[var(--text-muted)]">
            <CalendarDays className="size-3.5 shrink-0" aria-hidden="true" />
            <span>
              {formatDate(row.startDate)} — {formatDate(row.endDate)}
            </span>
            <span className="text-[var(--border)]">·</span>
            <span>{formatDuration(row)}</span>
          </div>
        </div>

        <div className="flex shrink-0 flex-wrap items-center gap-2">
          <span className={`rounded-full px-2.5 py-0.5 text-xs font-bold ${typeColor}`}>{typeLabel}</span>
          <StatusBadge status={row.status} />
        </div>
      </div>
    </button>
  );
}

// ─── الصفحة الرئيسية ─────────────────────────────────────────────────────────

export function LeavesPage() {
  const [year, setYear] = useState(CURRENT_YEAR);
  const [status, setStatus] = useState('');
  const [leaveType, setLeaveType] = useState('');
  const [selected, setSelected] = useState<LeaveAdminRow | null>(null);

  const query = useAdminLeaves({
    year,
    status: status || undefined,
    leaveType: leaveType || undefined,
  });

  const rows = useMemo(() => query.data?.rows ?? [], [query.data?.rows]);

  const metrics = useMemo(
    () => ({
      total: rows.length,
      pending: rows.filter((r) => r.status === 'pending').length,
      approved: rows.filter((r) => r.status === 'approved').length,
      rejected: rows.filter((r) => r.status === 'rejected').length,
    }),
    [rows],
  );

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow="الموارد البشرية"
        title="إدارة الإجازات"
        description="مراجعة واعتماد طلبات إجازات الموظفين"
        actions={
          <div className="flex items-center gap-2">
            <select value={year} onChange={(e) => setYear(Number(e.target.value))} className="input-field h-9 w-28 text-sm" aria-label="اختر السنة">
              {YEAR_OPTIONS.map((y) => (
                <option key={y} value={y}>
                  {y}
                </option>
              ))}
            </select>
            <button
              type="button"
              onClick={() => exportToCsv(rows, year)}
              disabled={rows.length === 0}
              className="flex h-9 items-center gap-1.5 rounded-lg border border-[var(--border)] px-3 text-sm font-semibold transition-colors hover:bg-[var(--surface-raised)] disabled:cursor-not-allowed disabled:opacity-50"
              aria-label="تصدير CSV"
            >
              <Download className="size-4" />
              <span className="hidden sm:inline">تصدير</span>
            </button>
          </div>
        }
      />

      {/* مؤشرات */}
      {query.isLoading ? (
        <MetricSkeletonRow />
      ) : (
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <MetricCard label="إجمالي الطلبات" value={metrics.total} icon={CalendarDays} />
          <MetricCard label="قيد المراجعة" value={metrics.pending} icon={Clock3} />
          <MetricCard label="معتمدة" value={metrics.approved} icon={Check} />
          <MetricCard label="مرفوضة" value={metrics.rejected} icon={FileX} />
        </div>
      )}

      {/* فلاتر */}
      <div className="flex flex-wrap gap-3">
        {/* فلتر الحالة */}
        <div className="flex flex-wrap gap-1 rounded-xl border border-[var(--border)] p-1">
          {STATUS_TABS.map((tab) => (
            <button
              key={tab.key}
              type="button"
              onClick={() => setStatus(tab.key)}
              className={`rounded-lg px-3 py-1.5 text-xs font-bold transition-colors ${
                status === tab.key ? 'bg-[var(--brand-primary)] text-white' : 'text-[var(--text-muted)] hover:bg-[var(--surface-raised)]'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>

        {/* فلتر نوع الإجازة */}
        <div className="flex flex-wrap gap-1 rounded-xl border border-[var(--border)] p-1">
          {LEAVE_TYPE_TABS.map((tab) => (
            <button
              key={tab.key}
              type="button"
              onClick={() => setLeaveType(tab.key)}
              className={`rounded-lg px-3 py-1.5 text-xs font-bold transition-colors ${
                leaveType === tab.key ? 'bg-[var(--brand-primary)] text-white' : 'text-[var(--text-muted)] hover:bg-[var(--surface-raised)]'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>
      </div>

      {/* المحتوى */}
      {query.isLoading ? (
        <ListSkeleton rows={5} />
      ) : query.isError ? (
        <ErrorState title="تعذّر تحميل الإجازات" description={safeErrorMessage(query.error)} onRetry={() => void query.refetch()} />
      ) : rows.length === 0 ? (
        <EmptyState
          title="لا توجد طلبات إجازات"
          description={status || leaveType ? 'لا توجد نتائج تطابق الفلاتر المحددة.' : `لا توجد طلبات إجازات مسجلة لعام ${year}.`}
        />
      ) : (
        <div className="space-y-2">
          <p className="text-xs text-[var(--text-muted)]">{query.data?.total ?? rows.length} طلب</p>
          <div className="space-y-2">
            {rows.map((row) => (
              <LeaveRow key={row.requestId} row={row} onSelect={setSelected} />
            ))}
          </div>
        </div>
      )}

      {/* تفاصيل الطلب */}
      {selected && <LeaveDetailDialog row={selected} onClose={() => setSelected(null)} onDecided={() => void query.refetch()} />}
    </div>
  );
}
