import { cairoTodayIso } from '../../../core/cairoTime';
import { downloadCsv, downloadReportHtml, printReport, toCsv, type ExportColumn } from '../../../core/exportUtils';
import {
  INSTANT_PENALTY_ESCALATION_LABELS,
  INSTANT_PENALTY_STATUS_LABELS,
  type InstantPenalty,
  type PendingPenaltyEmployee,
} from '../useInstantPenalties';
import { fmtDateWithDay, fmtLateDisplay, formatCurrency, getYesterdayIso } from './penaltyFormatters';

export type DateFilterMode = 'today' | 'yesterday' | 'specific' | 'all';
export type StatusFilter = 'unpaid' | 'all' | 'pending_payment' | 'doubled' | 'suspended' | 'paid' | 'cancelled';

export function exportPenaltiesCsv(rows: InstantPenalty[]): void {
  const cols: ExportColumn<InstantPenalty>[] = [
    { key: 'employee', header: 'الموظف', get: (p) => p.employeeName },
    { key: 'code', header: 'الكود', get: (p) => p.employeeCode },
    { key: 'department', header: 'الإدارة', get: (p) => p.departmentName },
    { key: 'date', header: 'التاريخ', get: (p) => p.workDate },
    { key: 'lateMinutes', header: 'التأخير', get: (p) => fmtLateDisplay(p.lateMinutes) },
    { key: 'originalAmount', header: 'الغرامة الأصلية', get: (p) => p.originalAmount },
    { key: 'currentAmount', header: 'المبلغ المطلوب', get: (p) => p.currentAmount },
    { key: 'escalation', header: 'التصعيد', get: (p) => INSTANT_PENALTY_ESCALATION_LABELS[p.escalationLevel] ?? p.escalationLevel },
    { key: 'status', header: 'الحالة', get: (p) => INSTANT_PENALTY_STATUS_LABELS[p.status] ?? p.status },
  ];
  downloadCsv(`instant-penalties-${cairoTodayIso()}.csv`, toCsv(cols, rows));
}

export function buildPenaltiesExportData(
  rows: InstantPenalty[],
  dateFilterMode: DateFilterMode,
  specificDate: string,
  statusFilter: StatusFilter,
) {
  const pendingRows = rows.filter((r) => r.status === 'pending_payment' || r.status === 'doubled' || r.status === 'suspended');
  const owedAmount = pendingRows.reduce((s, p) => s + (p.currentAmount ?? 0), 0);
  const paidRows = rows.filter((r) => r.status === 'paid');
  const paidAmount = paidRows.reduce((s, p) => s + (p.currentAmount ?? 0), 0);
  const cancelledRows = rows.filter((r) => r.status === 'cancelled');

  const dateLabel =
    dateFilterMode === 'today'
      ? `اليوم (${cairoTodayIso()})`
      : dateFilterMode === 'yesterday'
        ? `أمس (${getYesterdayIso()})`
        : dateFilterMode === 'specific'
          ? `تاريخ ${specificDate}`
          : 'كافة التواريخ';

  const statusLabel =
    statusFilter === 'unpaid'
      ? 'المطالبون بالسداد فقط (غير مدفوعة)'
      : statusFilter === 'all'
        ? 'كافة الحالات'
        : (INSTANT_PENALTY_STATUS_LABELS[statusFilter] ?? statusFilter);

  const sections = [
    {
      title: 'بيان وتفاصيل الغرامات المسجلة للتأخير',
      subtitle: `الحالة: ${statusLabel} | العدد: ${rows.length} غرامة | إجمالي المطلوب سداده: ${formatCurrency(owedAmount)}`,
      table: {
        headers: ['الموظف', 'الإدارة', 'التاريخ', 'التأخير', 'الغرامة الأصلية', 'المطلوب', 'التصعيد', 'الحالة'],
        rows: rows.map((p) => [
          p.employeeName ?? '—',
          p.departmentName ?? '—',
          fmtDateWithDay(p.workDate),
          fmtLateDisplay(p.lateMinutes),
          formatCurrency(p.originalAmount),
          formatCurrency(p.currentAmount),
          INSTANT_PENALTY_ESCALATION_LABELS[p.escalationLevel] ?? p.escalationLevel,
          INSTANT_PENALTY_STATUS_LABELS[p.status] ?? p.status,
        ]),
      },
    },
  ];

  const summaryCards = [
    { label: 'عدد الغرامات بالكشف', value: rows.length.toString() },
    { label: 'المطالبون بالسداد', value: pendingRows.length.toString() },
    { label: 'إجمالي المطلوب سداده', value: formatCurrency(owedAmount) },
    ...(paidRows.length > 0 ? [{ label: 'تم سداده', value: `${paidRows.length} (${formatCurrency(paidAmount)})` }] : []),
    ...(cancelledRows.length > 0 ? [{ label: 'ملغاة / معفى', value: cancelledRows.length.toString() }] : []),
  ];

  return {
    sections,
    docTitle: `كشف الغرامات الفورية — ${dateLabel}`,
    summaryCards,
  };
}

export function exportPenaltiesPdf(
  rows: InstantPenalty[],
  dateFilterMode: DateFilterMode,
  specificDate: string,
  statusFilter: StatusFilter,
): void {
  const { sections, docTitle, summaryCards } = buildPenaltiesExportData(rows, dateFilterMode, specificDate, statusFilter);
  printReport(sections, docTitle, summaryCards);
}

export function exportPenaltiesHtml(
  rows: InstantPenalty[],
  dateFilterMode: DateFilterMode,
  specificDate: string,
  statusFilter: StatusFilter,
): void {
  const { sections, docTitle, summaryCards } = buildPenaltiesExportData(rows, dateFilterMode, specificDate, statusFilter);
  downloadReportHtml(sections, docTitle, summaryCards);
}

export function exportModalTierPdf(params: {
  tier: string;
  allPenalties: InstantPenalty[];
  pendingEmployees: PendingPenaltyEmployee[];
  totalOwed: number;
  suspendedCount: number;
}): void {
  const { tier, allPenalties, pendingEmployees, totalOwed, suspendedCount } = params;

  if (tier === 'pending') {
    printReport(
      [
        {
          title: 'بيان الموظفين المطالبين بالسداد',
          subtitle: `${pendingEmployees.length} موظف مطالب بالسداد — إجمالي المطلوب: ${formatCurrency(totalOwed)}`,
          table: {
            headers: ['الموظف', 'الكود', 'الإدارة', 'عدد الغرامات', 'المبلغ المطلوب', 'حالة الحساب'],
            rows: pendingEmployees.map((e) => [
              e.employeeName ?? '—',
              e.employeeCode ?? '—',
              e.departmentName ?? '—',
              String(e.pendingCount),
              formatCurrency(e.totalAmount),
              e.isSuspended ? 'معلق عن العمل' : 'نشط',
            ]),
          },
        },
      ],
      'كشف المطالبين بسداد غرامات التأخير',
      [
        { label: 'إجمالي المطالبين', value: String(pendingEmployees.length) },
        { label: 'المعلقون عن العمل', value: String(suspendedCount) },
        { label: 'المبالغ المطلوبة', value: formatCurrency(totalOwed) },
      ],
    );
    return;
  }

  if (tier === 'suspended') {
    const items = allPenalties.filter((p) => p.status === 'suspended');
    const totalAmount = items.reduce((s, p) => s + (p.currentAmount ?? 0), 0);
    printReport(
      [
        {
          title: 'بيان الموظفين الموقوفين عن العمل لعدم السداد',
          subtitle: `${items.length} موظف موقوف — إجمالي المطلوب: ${formatCurrency(totalAmount)}`,
          table: {
            headers: ['الموظف', 'الكود', 'الإدارة', 'التاريخ', 'التأخير', 'الغرامة الأصلية', 'المطلوب (500 ج.م)', 'الحالة'],
            rows: items.map((p) => [
              p.employeeName ?? '—',
              p.employeeCode ?? '—',
              p.departmentName ?? '—',
              fmtDateWithDay(p.workDate),
              fmtLateDisplay(p.lateMinutes),
              formatCurrency(p.originalAmount),
              formatCurrency(p.currentAmount),
              'معلق عن العمل',
            ]),
          },
        },
      ],
      'كشف الموقوفين عن العمل (اليوم الثالث)',
      [
        { label: 'الموظفون الموقوفون', value: String(items.length) },
        { label: 'إجمالي المبالغ المستحقة', value: formatCurrency(totalAmount) },
      ],
    );
    return;
  }

  let filtered = allPenalties;
  let tierTitle = 'البيان الشامل وتفنيط الغرامات الفورية';
  if (tier === 'tier-20') {
    filtered = allPenalties.filter((p) => p.lateMinutes > 15 && p.lateMinutes <= 30);
    tierTitle = 'كشف غرامات 20 ج.م (تأخير 16-30 دقيقة)';
  } else if (tier === 'tier-50') {
    filtered = allPenalties.filter((p) => p.lateMinutes > 30 && p.lateMinutes <= 60);
    tierTitle = 'كشف غرامات 50 ج.م (تأخير 31-60 دقيقة / حتى 11:00 ص)';
  } else if (tier === 'tier-150') {
    filtered = allPenalties.filter((p) => p.lateMinutes > 60);
    tierTitle = 'كشف غرامات 150 ج.م (تأخير 61-120 دقيقة / من 11:01 وحتى 12:00)';
  } else if (tier === 'doubled') {
    filtered = allPenalties.filter((p) => p.status === 'doubled');
    tierTitle = 'كشف الغرامات المضاعفة 500 ج.م (اليوم الثاني)';
  }

  const total = filtered.reduce((s, p) => s + (p.currentAmount ?? 0), 0);
  printReport(
    [
      {
        title: 'بيان وتفاصيل الغرامات المسجلة',
        subtitle: `${filtered.length} غرامة — إجمالي المبالغ: ${formatCurrency(total)}`,
        table: {
          headers: ['الموظف', 'الإدارة', 'التاريخ', 'التأخير', 'الغرامة الأصلية', 'المطلوب', 'التصعيد', 'الحالة'],
          rows: filtered.map((p) => [
            p.employeeName ?? '—',
            p.departmentName ?? '—',
            fmtDateWithDay(p.workDate),
            fmtLateDisplay(p.lateMinutes),
            formatCurrency(p.originalAmount),
            formatCurrency(p.currentAmount),
            INSTANT_PENALTY_ESCALATION_LABELS[p.escalationLevel] ?? p.escalationLevel,
            INSTANT_PENALTY_STATUS_LABELS[p.status] ?? p.status,
          ]),
        },
      },
    ],
    tierTitle,
    [
      { label: 'عدد الغرامات', value: String(filtered.length) },
      { label: 'إجمالي المبالغ', value: formatCurrency(total) },
    ],
  );
}
