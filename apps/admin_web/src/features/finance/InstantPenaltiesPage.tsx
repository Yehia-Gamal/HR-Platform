import { cairoTodayIso } from '../../core/cairoTime';
import { useMemo, useState, type FormEvent } from 'react';
import { AlertTriangle, Ban, CheckCircle2, Clock, FileSpreadsheet, Printer, ShieldAlert, XCircle, Zap } from 'lucide-react';
import { safeErrorMessage } from '../../core/errorMapper';
import { downloadCsv, printReport, toCsv, type ExportColumn } from '../../core/exportUtils';
import { DataTable, type DataTableColumn } from '../../ui/DataTable';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { FilterBar } from '../../ui/FilterBar';
import { PageHeader } from '../../ui/PageHeader';
import { ListSkeleton } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';
import { useEmployees } from '../employees/useEmployees';
import {
  INSTANT_PENALTY_ESCALATION_LABELS,
  INSTANT_PENALTY_STATUS_LABELS,
  useCancelInstantPenalty,
  useConfirmInstantPenaltyPayment,
  useGenerateInstantPenalty,
  useInstantPenalties,
  useLiftInstantPenaltySuspension,
  usePendingPenaltyEmployees,
} from './useInstantPenalties';

const dateFormatter = new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium' });
const currencyFmt = new Intl.NumberFormat('ar-EG', { style: 'currency', currency: 'EGP', maximumFractionDigits: 0 });

function formatCurrency(amount: number | null | undefined): string {
  if (amount == null) return '—';
  return currencyFmt.format(amount);
}

/** أيقونة + لون حسب الحالة */
function StatusIcon({ status }: { status: string }) {
  switch (status) {
    case 'pending_payment':
      return <Clock className="size-4 text-amber-500" aria-hidden="true" />;
    case 'paid':
      return <CheckCircle2 className="size-4 text-emerald-500" aria-hidden="true" />;
    case 'doubled':
      return <ShieldAlert className="size-4 text-orange-500" aria-hidden="true" />;
    case 'suspended':
      return <Ban className="size-4 text-red-600" aria-hidden="true" />;
    case 'cancelled':
      return <XCircle className="size-4 text-gray-400" aria-hidden="true" />;
    default:
      return null;
  }
}

export function InstantPenaltiesPage() {
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('all');
  const penalties = useInstantPenalties(statusFilter === 'all' ? {} : { status: statusFilter });
  const pendingEmployees = usePendingPenaltyEmployees();
  const confirmPayment = useConfirmInstantPenaltyPayment();
  const generatePenalty = useGenerateInstantPenalty();
  const cancelPenalty = useCancelInstantPenalty();
  const liftSuspension = useLiftInstantPenaltySuspension();
  const { data: employees } = useEmployees();

  const [formOpen, setFormOpen] = useState(false);
  const [employeeId, setEmployeeId] = useState('');
  const [lateMinutes, setLateMinutes] = useState('');
  const [workDate, setWorkDate] = useState(cairoTodayIso());

  // ─── بيانات الجدول ─────────────────────────────────────────────────

  const rows = useMemo(() => {
    const q = search.trim().toLowerCase();
    const items = penalties.data ?? [];
    return q
      ? items.filter(
          (p) =>
            (p.employeeName ?? '').toLowerCase().includes(q) ||
            (p.employeeCode ?? '').toLowerCase().includes(q) ||
            (p.departmentName ?? '').toLowerCase().includes(q),
        )
      : items;
  }, [penalties.data, search]);

  // ─── إحصائيات سريعة ───────────────────────────────────────────────

  const stats = useMemo(() => {
    const pending = pendingEmployees.data ?? [];
    const suspendedCount = pending.filter((e) => e.isSuspended).length;
    const pendingCount = pending.length;
    const totalOwed = pending.reduce((s, e) => s + e.totalAmount, 0);
    return { suspendedCount, pendingCount, totalOwed };
  }, [pendingEmployees.data]);

  // ─── أعمدة الجدول ─────────────────────────────────────────────────

  const columns: DataTableColumn<(typeof rows)[number]>[] = [
    {
      key: 'employeeName',
      header: 'الموظف',
      sortable: true,
      render: (p) => (
        <div className="flex items-center gap-2">
          <span className="font-bold">{p.employeeName ?? '—'}</span>
          {p.status === 'suspended' && <span className="inline-block rounded-full bg-red-100 px-1.5 py-0.5 text-[10px] font-black text-red-700">معلّق</span>}
        </div>
      ),
    },
    { key: 'departmentName', header: 'الإدارة', render: (p) => p.departmentName ?? '—' },
    { key: 'workDate', header: 'التاريخ', sortable: true, render: (p) => dateFormatter.format(new Date(p.workDate + 'T00:00:00')) },
    {
      key: 'lateMinutes',
      header: 'التأخير',
      sortable: true,
      render: (p) => (
        <span className="font-bold text-amber-600">
          {p.lateMinutes} <span className="text-xs font-normal">دقيقة</span>
        </span>
      ),
    },
    {
      key: 'originalAmount',
      header: 'الغرامة الأصلية',
      render: (p) => <span className="text-[var(--text-muted)]">{formatCurrency(p.originalAmount)}</span>,
    },
    {
      key: 'currentAmount',
      header: 'المبلغ المطلوب',
      sortable: true,
      render: (p) => (
        <span className={`font-black ${p.status === 'paid' ? 'text-emerald-600' : 'text-[var(--danger)]'}`}>
          {formatCurrency(p.currentAmount)}
        </span>
      ),
    },
    {
      key: 'escalationLevel',
      header: 'التصعيد',
      render: (p) => (
        <span
          className={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-black ${
            p.escalationLevel === 'initial'
              ? 'bg-blue-50 text-blue-700'
              : p.escalationLevel === 'doubled'
                ? 'bg-orange-50 text-orange-700'
                : 'bg-red-50 text-red-700'
          }`}
        >
          {INSTANT_PENALTY_ESCALATION_LABELS[p.escalationLevel] ?? p.escalationLevel}
        </span>
      ),
    },
    {
      key: 'status',
      header: 'الحالة',
      render: (p) => (
        <div className="flex items-center gap-1.5">
          <StatusIcon status={p.status} />
          <StatusBadge status={p.status} label={INSTANT_PENALTY_STATUS_LABELS[p.status] ?? p.status} />
        </div>
      ),
    },
    {
      key: 'actions',
      header: 'إجراءات',
      render: (p) => {
        if (p.status === 'paid') {
          return <span className="text-xs text-emerald-600 font-bold">✓ مدفوعة ومُزيلَة</span>;
        }
        if (p.status === 'cancelled') {
          return <span className="text-xs text-gray-400 font-bold">ملغاة</span>;
        }
        return (
          <div className="flex items-center gap-1">
            <button
              type="button"
              className={`text-xs ${p.status === 'suspended' ? 'btn-danger' : 'btn-primary'}`}
              disabled={confirmPayment.isPending}
              onClick={() => {
                const confirmMsg =
                  p.status === 'suspended'
                    ? `هل استلمت 500 ج.م من ${p.employeeName ?? 'الموظف'}؟ سيتم رفع التعليق فوراً وفتح السيستم وعودته للعمل وإشعار الفريق.`
                    : p.status === 'doubled'
                      ? `هل استلمت 500 ج.م من ${p.employeeName ?? 'الموظف'}؟`
                      : `تأكيد استلام ${formatCurrency(p.currentAmount)} من ${p.employeeName ?? 'الموظف'} وإزالة الخصم؟`;
                if (!window.confirm(confirmMsg)) return;
                const notes = window.prompt('ملاحظات الدفع (اختياري):');
                void confirmPayment.mutateAsync({ penaltyId: p.id, notes: notes?.trim() || undefined });
              }}
            >
              <CheckCircle2 className="size-3.5" aria-hidden="true" />
              {p.status === 'suspended'
                ? 'استلام 500 ج وفتح السيستم'
                : p.status === 'doubled'
                  ? 'استلام 500 ج'
                  : 'تأكيد الدفع'}
            </button>
            {p.status === 'suspended' && (
              <button
                type="button"
                className="btn-secondary text-xs"
                disabled={liftSuspension.isPending}
                onClick={() => {
                  if (!window.confirm(`هل تريد رفع التعليق عن ${p.employeeName ?? 'الموظف'} بدون سداد؟ (full-access فقط)`)) return;
                  const notes = window.prompt('سبب رفع التعليق:');
                  if (!notes?.trim()) return;
                  void liftSuspension.mutateAsync({ penaltyId: p.id, notes: notes.trim() });
                }}
              >
                رفع التعليق
              </button>
            )}
            {(p.status === 'pending_payment' || p.status === 'doubled') && (
              <button
                type="button"
                className="btn-secondary text-xs text-[var(--danger)]"
                disabled={cancelPenalty.isPending}
                onClick={() => {
                  const reason = window.prompt(`إلغاء غرامة ${p.employeeName ?? 'الموظف'} — اذكر السبب:`);
                  if (!reason?.trim()) return;
                  void cancelPenalty.mutateAsync({ penaltyId: p.id, reason: reason.trim() });
                }}
              >
                <XCircle className="size-3.5" aria-hidden="true" />
                إلغاء
              </button>
            )}
          </div>
        );
      },
    },
  ];

  // ─── فلاتر ─────────────────────────────────────────────────────────

  const dirty = Boolean(search.trim() || statusFilter !== 'all');
  const clearFilters = () => {
    setSearch('');
    setStatusFilter('all');
  };

  // ─── إنشاء غرامة يدوية ────────────────────────────────────────────

  const submitPenalty = async (ev: FormEvent) => {
    ev.preventDefault();
    if (!employeeId) return;
    const mins = Number(lateMinutes);
    if (!Number.isFinite(mins) || mins <= 0) return;
    await generatePenalty.mutateAsync({
      employeeId,
      workDate,
      lateMinutes: mins,
    });
    setFormOpen(false);
    setEmployeeId('');
    setLateMinutes('');
    setWorkDate(cairoTodayIso());
  };

  // ─── تصدير ─────────────────────────────────────────────────────────

  const handleCsvExport = () => {
    const cols: ExportColumn<(typeof rows)[number]>[] = [
      { key: 'employee', header: 'الموظف', get: (p) => p.employeeName },
      { key: 'code', header: 'الكود', get: (p) => p.employeeCode },
      { key: 'department', header: 'الإدارة', get: (p) => p.departmentName },
      { key: 'date', header: 'التاريخ', get: (p) => p.workDate },
      { key: 'lateMinutes', header: 'التأخير (دقيقة)', get: (p) => p.lateMinutes },
      { key: 'originalAmount', header: 'الغرامة الأصلية', get: (p) => p.originalAmount },
      { key: 'currentAmount', header: 'المبلغ المطلوب', get: (p) => p.currentAmount },
      { key: 'escalation', header: 'التصعيد', get: (p) => INSTANT_PENALTY_ESCALATION_LABELS[p.escalationLevel] ?? p.escalationLevel },
      { key: 'status', header: 'الحالة', get: (p) => INSTANT_PENALTY_STATUS_LABELS[p.status] ?? p.status },
    ];
    downloadCsv(`instant-penalties-${cairoTodayIso()}.csv`, toCsv(cols, rows));
  };

  const handlePdfExport = () => {
    printReport(
      [
        {
          title: 'الغرامات الفورية للتأخير',
          subtitle: `${rows.length} غرامة`,
          table: {
            headers: ['الموظف', 'الإدارة', 'التاريخ', 'التأخير', 'الغرامة الأصلية', 'المطلوب', 'التصعيد', 'الحالة'],
            rows: rows.map((p) => [
              p.employeeName ?? '—',
              p.departmentName ?? '—',
              p.workDate,
              p.lateMinutes + ' دقيقة',
              formatCurrency(p.originalAmount),
              formatCurrency(p.currentAmount),
              INSTANT_PENALTY_ESCALATION_LABELS[p.escalationLevel] ?? p.escalationLevel,
              INSTANT_PENALTY_STATUS_LABELS[p.status] ?? p.status,
            ]),
          },
        },
      ],
      'الغرامات الفورية',
    );
  };

  return (
    <div className="space-y-5">
      <PageHeader
        eyebrow="الموارد البشرية"
        title="الغرامات الفورية للتأخير"
        description="نظام الغرامات الفورية: الحضور يبدأ 10:00 ص، سماح 15 دقيقة (10:00 - 10:15 بدون خصم) | حتى 10:30 (20 ج.م) | حتى 11:00 (50 ج.م) | حتى 12:00 (150 ج.م). عدم السداد في نفس اليوم يُضاعف الخصم لـ 500 ج.م في اليوم الثاني، وعدم السداد في اليوم الثاني يؤدي لغلق السيستم وإيقاف الموظف عن العمل في اليوم الثالث مع إشعار كامل الفريق حتى السداد للـ HR."
        actions={
          <button type="button" className="btn-primary" onClick={() => setFormOpen((v) => !v)} disabled={generatePenalty.isPending}>
            <Zap className="size-4" aria-hidden="true" />
            إنشاء غرامة يدوياً
          </button>
        }
      />

      {/* ─── إحصائيات سريعة ─────────────────────────────────────────── */}
      {(stats.pendingCount > 0 || stats.suspendedCount > 0) && (
        <div className="grid gap-3 sm:grid-cols-3">
          <div className="card flex items-center gap-3 p-4">
            <div className="rounded-lg bg-amber-100 p-2">
              <AlertTriangle className="size-5 text-amber-600" aria-hidden="true" />
            </div>
            <div>
              <p className="text-2xl font-black text-amber-600">{stats.pendingCount}</p>
              <p className="text-xs text-[var(--text-muted)]">موظف مطالب بالدفع</p>
            </div>
          </div>
          <div className="card flex items-center gap-3 p-4">
            <div className="rounded-lg bg-red-100 p-2">
              <Ban className="size-5 text-red-600" aria-hidden="true" />
            </div>
            <div>
              <p className="text-2xl font-black text-red-600">{stats.suspendedCount}</p>
              <p className="text-xs text-[var(--text-muted)]">موظف معلّق عن العمل (مغلق السيستم)</p>
            </div>
          </div>
          <div className="card flex items-center gap-3 p-4">
            <div className="rounded-lg bg-orange-100 p-2">
              <ShieldAlert className="size-5 text-orange-600" aria-hidden="true" />
            </div>
            <div>
              <p className="text-2xl font-black text-orange-600">{formatCurrency(stats.totalOwed)}</p>
              <p className="text-xs text-[var(--text-muted)]">إجمالي المستحق</p>
            </div>
          </div>
        </div>
      )}

      {/* ─── نموذج الإنشاء اليدوي ──────────────────────────────────── */}
      {formOpen && (
        <section className="card p-5">
          <h2 className="font-black">إنشاء غرامة فورية للتأخير</h2>
          <p className="mt-1 text-xs text-[var(--text-muted)]">
            الحضور يبدأ 10:00 ص: من 1-15 دقيقة = سماح بدون خصم (0 ج.م) | حتى 10:30 (16-30 دقيقة) = 20 ج.م | حتى 11:00 (31-60 دقيقة) = 50 ج.م | حتى 12:00 (61-120 دقيقة) = 150 ج.م.
          </p>
          <form className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-4" onSubmit={(ev) => void submitPenalty(ev)}>
            <label className="block">
              <span className="muted text-xs">الموظف *</span>
              <select className="input mt-1" value={employeeId} onChange={(ev) => setEmployeeId(ev.target.value)} required>
                <option value="">اختر الموظف…</option>
                {(employees ?? []).map((e) => (
                  <option key={e.id} value={e.id}>
                    {e.fullNameAr}
                  </option>
                ))}
              </select>
            </label>
            <label className="block">
              <span className="muted text-xs">تاريخ التأخير *</span>
              <input className="input mt-1" type="date" value={workDate} onChange={(ev) => setWorkDate(ev.target.value)} required />
            </label>
            <label className="block">
              <span className="muted text-xs">دقائق التأخير *</span>
              <input
                className="input mt-1"
                type="number"
                min="1"
                max="480"
                step="1"
                value={lateMinutes}
                onChange={(ev) => setLateMinutes(ev.target.value)}
                placeholder="25"
                required
              />
              {Number(lateMinutes) > 0 && (
                <span className={`mt-1 block text-[11px] font-bold ${Number(lateMinutes) <= 15 ? 'text-emerald-600' : 'text-amber-600'}`}>
                  {Number(lateMinutes) <= 15
                    ? '✓ فترة سماح (10:00 - 10:15) — بدون أي خصم (0 ج.م)'
                    : Number(lateMinutes) <= 30
                      ? 'خصم 20 ج.م (حضور حتى 10:30)'
                      : Number(lateMinutes) <= 60
                        ? 'خصم 50 ج.م (حضور حتى 11:00)'
                        : 'خصم 150 ج.م (حضور حتى 12:00)'}
                </span>
              )}
            </label>
            <div className="flex items-end gap-2">
              <button
                type="submit"
                className="btn-primary"
                disabled={generatePenalty.isPending || !employeeId || !(Number(lateMinutes) > 0)}
              >
                {generatePenalty.isPending ? 'جارٍ الحفظ…' : 'تسجيل الغرامة'}
              </button>
              <button type="button" className="btn-secondary" onClick={() => setFormOpen(false)}>
                إلغاء
              </button>
            </div>
            {generatePenalty.isError && <p className="text-sm text-[var(--danger)] sm:col-span-2 lg:col-span-4">{safeErrorMessage(generatePenalty.error)}</p>}
          </form>
        </section>
      )}

      {/* ─── الموظفين المعلقين ──────────────────────────────────────── */}
      {(pendingEmployees.data ?? []).some((e) => e.isSuspended) && (
        <section className="card border-2 border-red-200 bg-red-50/50 p-4">
          <div className="flex items-center justify-between">
            <h3 className="flex items-center gap-2 font-black text-red-700">
              <Ban className="size-4" aria-hidden="true" />
              موظفون موقوفون عن العمل ومغلق السيستم عليهم (اليوم الثالث لعدم سداد 500 ج.م)
            </h3>
            <span className="text-xs font-bold text-red-600">تم إشعار كامل الفريق</span>
          </div>
          <p className="mt-1 text-xs text-red-600">
            لن يتمكن الموظف من تسجيل الدخول أو البصمة حتى يتم سداد مبلغ الـ 500 ج.م للـ HR وتأكيد الدفع لفتح السيستم.
          </p>
          <div className="mt-3 grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
            {(pendingEmployees.data ?? [])
              .filter((e) => e.isSuspended)
              .map((e) => (
                <div key={e.employeeId} className="flex items-center justify-between rounded-lg bg-white p-3 shadow-sm border border-red-200">
                  <div>
                    <p className="font-bold text-red-700">{e.employeeName ?? '—'}</p>
                    <p className="text-xs text-[var(--text-muted)]">{e.departmentName ?? '—'}</p>
                  </div>
                  <div className="text-left">
                    <span className="font-black text-red-600 block">{formatCurrency(e.totalAmount)}</span>
                    <span className="text-[10px] text-red-500 font-bold">مطلوب 500 ج.م</span>
                  </div>
                </div>
              ))}
          </div>
        </section>
      )}

      {/* ─── شريط الفلاتر ──────────────────────────────────────────── */}
      <FilterBar
        searchValue={search}
        onSearchChange={setSearch}
        searchPlaceholder="ابحث بالموظف أو الإدارة…"
        resultText={`عرض ${rows.length} من ${penalties.data?.length ?? 0}`}
        isDirty={dirty}
        onClear={clearFilters}
      >
        <select className="input" value={statusFilter} onChange={(ev) => setStatusFilter(ev.target.value)} aria-label="تصفية حسب الحالة">
          <option value="all">كل الحالات</option>
          {Object.entries(INSTANT_PENALTY_STATUS_LABELS).map(([key, label]) => (
            <option key={key} value={key}>
              {label}
            </option>
          ))}
        </select>
        <button type="button" className="btn-secondary" onClick={handleCsvExport} disabled={rows.length === 0} title="تصدير Excel (CSV)">
          <FileSpreadsheet className="size-4" aria-hidden="true" />
          تصدير
        </button>
        <button type="button" className="btn-secondary" onClick={handlePdfExport} disabled={rows.length === 0} title="طباعة PDF">
          <Printer className="size-4" aria-hidden="true" />
          PDF
        </button>
      </FilterBar>

      {/* ─── الجدول الرئيسي ────────────────────────────────────────── */}
      {penalties.isError ? (
        <ErrorState description={safeErrorMessage(penalties.error)} onRetry={() => void penalties.refetch()} />
      ) : penalties.isLoading ? (
        <ListSkeleton rows={4} label="جارٍ تحميل الغرامات الفورية…" />
      ) : rows.length === 0 ? (
        <EmptyState title="لا توجد غرامات فورية" description="لم تُسجل أي غرامات فورية للتأخير بعد." />
      ) : (
        <DataTable
          ariaLabel="جدول الغرامات الفورية للتأخير"
          rowKey={(p) => p.id}
          data={rows}
          minWidth="1000px"
          columns={columns}
          emptyTitle="لا توجد نتائج"
          emptyDescription="جرّب تعديل البحث أو الحالة."
        />
      )}

      {confirmPayment.isError && (
        <p className="text-sm text-[var(--danger)]">{safeErrorMessage(confirmPayment.error)}</p>
      )}
    </div>
  );
}
