import { Ban, Clock, Coins, FileSpreadsheet, Printer } from 'lucide-react';
import { Link } from 'react-router';
import { cairoTodayIso } from '../../../core/cairoTime';
import { downloadCsv, toCsv, type ExportColumn } from '../../../core/exportUtils';
import { DialogOverlay } from '../../../ui/DialogOverlay';
import { isPhoneLikeCode } from '../../../ui/phoneDisplay';
import { StatusBadge } from '../../../ui/StatusBadge';
import { INSTANT_PENALTY_STATUS_LABELS, type InstantPenalty, type PendingPenaltyEmployee } from '../useInstantPenalties';
import { dateFormatter, fmtLateDisplay, formatCurrency } from './penaltyFormatters';

export type ModalTier = 'pending' | 'tier-20' | 'tier-50' | 'tier-150' | 'tier-500' | 'suspended' | 'total';
export type SelectedTier = 'all' | 'pending' | 'tier-20' | 'tier-50' | 'tier-150' | 'tier-500' | 'suspended';

export interface TierBucketStats {
  count: number;
  total: number;
  pendingCount: number;
  paidCount: number;
  items: InstantPenalty[];
}

export interface TierStatsMap {
  tier20: TierBucketStats;
  tier50: TierBucketStats;
  tier150: TierBucketStats;
  tier500: TierBucketStats;
}

interface PenaltyTierDetailModalProps {
  activeModalTier: ModalTier | null;
  pendingEmployees: PendingPenaltyEmployee[];
  allPenalties: InstantPenalty[];
  stats: { totalOwed: number; suspendedCount: number };
  tierStats: TierStatsMap;
  fellowshipFundPath: string;
  onExportPdf: (tier: string) => void;
  onOpenPaymentDialog: (penalty: InstantPenalty) => void;
  onOpenLiftDialog: (penalty: InstantPenalty) => void;
  onFilterByEmployee: (employeeName: string) => void;
  onSelectTier: (tier: SelectedTier) => void;
  onClose: () => void;
}

const MODAL_TITLES: Record<ModalTier, string> = {
  pending: 'كشف الموظفين المطالبين بالدفع حالياً',
  suspended: 'كشف الموظفين الموقوفين عن العمل (اليوم الثالث)',
  total: 'البيان الشامل وتفنيط الغرامات الفورية',
  'tier-20': 'صندوق غرامات 20 ج.م (تأخير 16-30 دقيقة)',
  'tier-50': 'صندوق غرامات 50 ج.م (تأخير 31 دقيقة - أقل من ساعتين)',
  'tier-150': 'صندوق غرامات 150 ج.م (تأخير ساعتين فأكثر أو عدم البصمة)',
  'tier-500': 'صندوق الغرامات المضاعفة 500 ج.م (اليوم الثاني)',
};

const TIER_DETAIL_META = {
  'tier-20': { label: 'غرامات 20 ج.م', color: 'text-sky-600 dark:text-sky-400', key: 'tier20' as const },
  'tier-50': { label: 'غرامات 50 ج.م', color: 'text-amber-600 dark:text-amber-400', key: 'tier50' as const },
  'tier-150': { label: 'غرامات 150 ج.م', color: 'text-orange-600 dark:text-orange-400', key: 'tier150' as const },
  'tier-500': { label: 'غرامات مضاعفة 500 ج.م', color: 'text-purple-600 dark:text-purple-400', key: 'tier500' as const },
};

const TOTAL_SUMMARY_CARDS = [
  {
    key: 'tier20' as const,
    title: 'شريحة 20 ج.م',
    badge: '16-30 د',
    boxClass: 'border-sky-500/30 bg-sky-50/40 dark:bg-sky-950/20',
    titleClass: 'text-sky-700 dark:text-sky-300',
    badgeClass: 'bg-sky-100 dark:bg-sky-900/50 text-sky-700 dark:text-sky-300',
    valueClass: 'text-sky-600 dark:text-sky-400',
  },
  {
    key: 'tier50' as const,
    title: 'شريحة 50 ج.م',
    badge: '31-60 د',
    boxClass: 'border-amber-500/30 bg-amber-50/40 dark:bg-amber-950/20',
    titleClass: 'text-amber-700 dark:text-amber-300',
    badgeClass: 'bg-amber-100 dark:bg-amber-900/50 text-amber-700 dark:text-amber-300',
    valueClass: 'text-amber-600 dark:text-amber-400',
  },
  {
    key: 'tier150' as const,
    title: 'شريحة 150 ج.م',
    badge: 'ساعتين+',
    boxClass: 'border-orange-500/30 bg-orange-50/40 dark:bg-orange-950/20',
    titleClass: 'text-orange-700 dark:text-orange-300',
    badgeClass: 'bg-orange-100 dark:bg-orange-900/50 text-orange-700 dark:text-orange-300',
    valueClass: 'text-orange-600 dark:text-orange-400',
  },
  {
    key: 'tier500' as const,
    title: 'مضاعفة 500 ج.م',
    badge: 'اليوم الثاني',
    boxClass: 'border-purple-500/30 bg-purple-50/40 dark:bg-purple-950/20',
    titleClass: 'text-purple-700 dark:text-purple-300',
    badgeClass: 'bg-purple-100 dark:bg-purple-900/50 text-purple-700 dark:text-purple-300',
    valueClass: 'text-purple-600 dark:text-purple-400',
  },
];

export function PenaltyTierDetailModal({
  activeModalTier,
  pendingEmployees,
  allPenalties,
  stats,
  tierStats,
  fellowshipFundPath,
  onExportPdf,
  onOpenPaymentDialog,
  onOpenLiftDialog,
  onFilterByEmployee,
  onSelectTier,
  onClose,
}: PenaltyTierDetailModalProps) {
  if (!activeModalTier) return null;

  const suspendedList = pendingEmployees.filter((e) => e.isSuspended);

  return (
    <DialogOverlay title={MODAL_TITLES[activeModalTier]} onClose={onClose} maxWidth="max-w-4xl">
      <div className="space-y-4 max-h-[75vh] overflow-y-auto px-1">
        {/* ─── شريط التصدير السريع للكشف ─── */}
        <div className="flex items-center justify-between gap-3 p-3 rounded-xl border border-[var(--border-subtle)] bg-[var(--surface-muted)]/60">
          <div className="flex items-center gap-2">
            <FileSpreadsheet className="size-4 text-emerald-600 dark:text-emerald-400" />
            <span className="text-xs font-bold text-[var(--text-secondary)]">كشف معتمد جاهز للتصدير والطباعة</span>
          </div>
          <button
            type="button"
            className="btn-secondary text-xs font-bold flex items-center gap-1.5 !py-1.5 !px-3 shadow-xs hover:border-emerald-500/50"
            onClick={() => onExportPdf(activeModalTier)}
            title="تصدير هذا الكشف كملف PDF"
          >
            <Printer className="size-3.5 text-emerald-600 dark:text-emerald-400" />
            <span>تصدير هذا الكشف PDF</span>
          </button>
        </div>

        {/* 1. كشف المطالبين بالدفع */}
        {activeModalTier === 'pending' && (
          <div className="space-y-4">
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
              <div className="rounded-xl bg-amber-500/10 border border-amber-500/20 p-3 text-center">
                <span className="text-xs text-[var(--text-muted)] block">إجمالي المطالبين</span>
                <span className="text-xl font-black text-amber-600 dark:text-amber-400">{pendingEmployees.length}</span>
                <span className="text-[11px] text-[var(--text-muted)] mr-1">موظف</span>
              </div>
              <div className="rounded-xl bg-orange-500/10 border border-orange-500/20 p-3 text-center">
                <span className="text-xs text-[var(--text-muted)] block">إجمالي المبالغ المطلوبة</span>
                <span className="text-xl font-black text-orange-600 dark:text-orange-400 font-mono">{formatCurrency(stats.totalOwed)}</span>
              </div>
              <div className="rounded-xl bg-red-500/10 border border-red-500/20 p-3 text-center col-span-2 sm:col-span-1">
                <span className="text-xs text-[var(--text-muted)] block">المعلقون عن العمل</span>
                <span className="text-xl font-black text-red-600 dark:text-red-400">{stats.suspendedCount}</span>
                <span className="text-[11px] text-[var(--text-muted)] mr-1">موظف</span>
              </div>
            </div>

            <div className="overflow-x-auto rounded-xl border border-[var(--border-subtle)] bg-[var(--surface)]">
              <table className="w-full text-start text-xs">
                <thead className="bg-[var(--surface-muted)] text-[var(--text-muted)] font-bold border-b border-[var(--border-subtle)]">
                  <tr>
                    <th className="p-3 text-start">الموظف</th>
                    <th className="p-3 text-start">الإدارة</th>
                    <th className="p-3 text-center">عدد الغرامات</th>
                    <th className="p-3 text-end">إجمالي المبلغ</th>
                    <th className="p-3 text-center">حالة الحساب</th>
                    <th className="p-3 text-center">إجراء سريع</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-[var(--border-subtle)]">
                  {pendingEmployees.length === 0 ? (
                    <tr>
                      <td colSpan={6} className="p-6 text-center text-[var(--text-muted)]">
                        لا يوجد أي موظف مطالب بالدفع حالياً! 🎉
                      </td>
                    </tr>
                  ) : (
                    pendingEmployees.map((e) => {
                      const firstPenalty = allPenalties.find(
                        (p) => p.employeeId === e.employeeId && (p.status === 'pending_payment' || p.status === 'doubled' || p.status === 'suspended'),
                      );
                      return (
                        <tr key={e.employeeId} className="hover:bg-[var(--surface-hover)] transition-colors">
                          <td className="p-3">
                            <p className="font-bold text-[var(--text-primary)]">{e.employeeName ?? '—'}</p>
                            <p className="text-[10px] text-[var(--text-muted)] font-mono">
                              {isPhoneLikeCode(e.employeeCode) ? '—' : <bdi dir="ltr">{e.employeeCode}</bdi>}
                            </p>
                          </td>
                          <td className="p-3 text-[var(--text-secondary)]">{e.departmentName ?? '—'}</td>
                          <td className="p-3 text-center font-bold font-mono text-amber-600">{e.pendingCount}</td>
                          <td className="p-3 text-end font-black font-mono text-[var(--text-primary)]">{formatCurrency(e.totalAmount)}</td>
                          <td className="p-3 text-center">
                            {e.isSuspended ? (
                              <span className="inline-flex items-center gap-1 rounded-full bg-red-100 dark:bg-red-950/60 px-2 py-0.5 text-[10px] font-bold text-red-700 dark:text-red-300 border border-red-300 dark:border-red-800">
                                <Ban className="size-3" /> معلّق
                              </span>
                            ) : (
                              <span className="inline-flex items-center gap-1 rounded-full bg-amber-100 dark:bg-amber-950/60 px-2 py-0.5 text-[10px] font-bold text-amber-700 dark:text-amber-300 border border-amber-300 dark:border-amber-800">
                                <Clock className="size-3" /> مطالب بالسداد
                              </span>
                            )}
                          </td>
                          <td className="p-3 text-center">
                            <div className="flex items-center justify-center gap-1.5">
                              {firstPenalty && (
                                <button
                                  type="button"
                                  className="btn-primary !py-1 !px-2 text-[11px] bg-emerald-600 hover:bg-emerald-700 text-white font-bold"
                                  onClick={() => onOpenPaymentDialog(firstPenalty)}
                                  title="استلام وإيداع بالصندوق"
                                >
                                  <Coins className="size-3 text-amber-300" />
                                  <span>إيداع بالصندوق</span>
                                </button>
                              )}
                              <button
                                type="button"
                                className="btn-secondary !py-1 !px-2 text-[11px]"
                                onClick={() => onFilterByEmployee(e.employeeName ?? '')}
                                title="تصفية غرامات هذا الموظف في الجدول الرئيسي"
                              >
                                عرض غراماته
                              </button>
                            </div>
                          </td>
                        </tr>
                      );
                    })
                  )}
                </tbody>
              </table>
            </div>

            <div className="flex flex-wrap items-center justify-between gap-2 pt-2 border-t border-[var(--border-subtle)]">
              <button
                type="button"
                className="btn-secondary text-xs flex items-center gap-1.5"
                onClick={() => {
                  const cols: ExportColumn<PendingPenaltyEmployee>[] = [
                    { key: 'employee', header: 'الموظف', get: (e) => e.employeeName },
                    { key: 'code', header: 'الكود', get: (e) => e.employeeCode },
                    { key: 'department', header: 'الإدارة', get: (e) => e.departmentName },
                    { key: 'count', header: 'عدد الغرامات', get: (e) => e.pendingCount },
                    { key: 'amount', header: 'إجمالي المبلغ', get: (e) => e.totalAmount },
                    { key: 'suspended', header: 'معلّق عن العمل', get: (e) => (e.isSuspended ? 'نعم' : 'لا') },
                  ];
                  downloadCsv(`pending-penalty-employees-${cairoTodayIso()}.csv`, toCsv(cols, pendingEmployees));
                }}
                disabled={pendingEmployees.length === 0}
              >
                <FileSpreadsheet className="size-4" />
                <span>تصدير كشف المطالبين Excel</span>
              </button>

              <div className="flex items-center gap-2">
                <button type="button" className="btn-primary !py-1.5 !px-3 text-xs" onClick={() => onSelectTier('pending')}>
                  تصفية الجدول بهؤلاء الموظفين ←
                </button>
                <button type="button" className="btn-secondary !py-1.5 !px-3 text-xs" onClick={onClose}>
                  إغلاق
                </button>
              </div>
            </div>
          </div>
        )}

        {/* 2. كشف المعلقين عن العمل */}
        {activeModalTier === 'suspended' && (
          <div className="space-y-4">
            <div className="rounded-xl border border-red-500/30 bg-red-50/60 dark:bg-red-950/30 p-3.5 text-xs text-red-800 dark:text-red-300">
              <p className="font-bold flex items-center gap-1.5">
                <Ban className="size-4 text-red-600" />
                تنبيه إيقاف الحسابات ومباشرة العمل (اليوم الثالث):
              </p>
              <p className="mt-1">
                تم إيقاف حسابات هؤلاء الزملاء برمجياً بسبب عدم سداد غرامة الـ 500 ج.م المضاعفة. لا يمكنهم تسجيل الدخول على المنظومة حتى يتم استلام المبلغ
                وتوريده لصندوق الزمالة والتكافل.
              </p>
            </div>

            <div className="overflow-x-auto rounded-xl border border-[var(--border-subtle)] bg-[var(--surface)]">
              <table className="w-full text-start text-xs">
                <thead className="bg-[var(--surface-muted)] text-[var(--text-muted)] font-bold border-b border-[var(--border-subtle)]">
                  <tr>
                    <th className="p-3 text-start">الموظف</th>
                    <th className="p-3 text-start">الإدارة</th>
                    <th className="p-3 text-center">عدد الغرامات</th>
                    <th className="p-3 text-end">إجمالي المبلغ</th>
                    <th className="p-3 text-center">الإجراءات المتاحة</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-[var(--border-subtle)]">
                  {suspendedList.length === 0 ? (
                    <tr>
                      <td colSpan={5} className="p-6 text-center text-[var(--text-muted)]">
                        الحمد لله، لا يوجد أي موظف معلّق عن العمل حالياً! ✨
                      </td>
                    </tr>
                  ) : (
                    suspendedList.map((e) => {
                      const suspendedPenalty = allPenalties.find((p) => p.employeeId === e.employeeId && p.status === 'suspended');
                      return (
                        <tr key={e.employeeId} className="hover:bg-[var(--surface-hover)] transition-colors">
                          <td className="p-3">
                            <p className="font-bold text-red-700 dark:text-red-400">{e.employeeName ?? '—'}</p>
                            <p className="text-[10px] text-[var(--text-muted)] font-mono">
                              {isPhoneLikeCode(e.employeeCode) ? '—' : <bdi dir="ltr">{e.employeeCode}</bdi>}
                            </p>
                          </td>
                          <td className="p-3 text-[var(--text-secondary)]">{e.departmentName ?? '—'}</td>
                          <td className="p-3 text-center font-bold font-mono text-red-600">{e.pendingCount}</td>
                          <td className="p-3 text-end font-black font-mono text-red-600">{formatCurrency(e.totalAmount)}</td>
                          <td className="p-3 text-center">
                            <div className="flex items-center justify-center gap-1.5">
                              {suspendedPenalty && (
                                <button
                                  type="button"
                                  className="btn-primary !py-1 !px-2.5 text-[11px] bg-emerald-600 hover:bg-emerald-700 text-white font-bold"
                                  onClick={() => onOpenPaymentDialog(suspendedPenalty)}
                                >
                                  <Coins className="size-3 text-amber-300" />
                                  <span>استلام 500 ج.م وإيداع بالصندوق</span>
                                </button>
                              )}
                              {suspendedPenalty && (
                                <button
                                  type="button"
                                  className="btn-secondary !py-1 !px-2 text-[11px]"
                                  onClick={() => onOpenLiftDialog(suspendedPenalty)}
                                >
                                  رفع التعليق يدوياً
                                </button>
                              )}
                            </div>
                          </td>
                        </tr>
                      );
                    })
                  )}
                </tbody>
              </table>
            </div>

            <div className="flex flex-wrap items-center justify-between gap-2 pt-2 border-t border-[var(--border-subtle)]">
              <button
                type="button"
                className="btn-secondary text-xs flex items-center gap-1.5"
                onClick={() => {
                  const cols: ExportColumn<PendingPenaltyEmployee>[] = [
                    { key: 'employee', header: 'الموظف', get: (e) => e.employeeName },
                    { key: 'code', header: 'الكود', get: (e) => e.employeeCode },
                    { key: 'department', header: 'الإدارة', get: (e) => e.departmentName },
                    { key: 'count', header: 'عدد الغرامات', get: (e) => e.pendingCount },
                    { key: 'amount', header: 'إجمالي المبلغ', get: (e) => e.totalAmount },
                  ];
                  downloadCsv(`suspended-employees-${cairoTodayIso()}.csv`, toCsv(cols, suspendedList));
                }}
                disabled={suspendedList.length === 0}
              >
                <FileSpreadsheet className="size-4" />
                <span>تصدير كشف المعلقين Excel</span>
              </button>

              <div className="flex items-center gap-2">
                <button type="button" className="btn-primary !py-1.5 !px-3 text-xs" onClick={() => onSelectTier('suspended')}>
                  تصفية الجدول بالمعلقين ←
                </button>
                <button type="button" className="btn-secondary !py-1.5 !px-3 text-xs" onClick={onClose}>
                  إغلاق
                </button>
              </div>
            </div>
          </div>
        )}

        {/* 3. تفنيط المبالغ الشامل (total) */}
        {activeModalTier === 'total' && (
          <div className="space-y-4">
            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
              {TOTAL_SUMMARY_CARDS.map((card) => {
                const bucket = tierStats[card.key];
                return (
                  <div key={card.key} className={`rounded-xl border p-3 ${card.boxClass}`}>
                    <div className="flex items-center justify-between">
                      <span className={`text-xs font-bold ${card.titleClass}`}>{card.title}</span>
                      <span className={`text-[10px] px-1.5 py-0.5 rounded font-mono ${card.badgeClass}`}>{card.badge}</span>
                    </div>
                    <p className={`mt-2 text-xl font-black font-mono ${card.valueClass}`}>{formatCurrency(bucket.total)}</p>
                    <p className="text-[11px] text-[var(--text-muted)] mt-1 flex justify-between">
                      <span>العدد: {bucket.count}</span>
                      <span className="text-amber-600 font-bold">{bucket.pendingCount} معلق</span>
                    </p>
                  </div>
                );
              })}
            </div>

            <div className="flex flex-col sm:flex-row items-center justify-between gap-3 rounded-xl border border-emerald-500/30 bg-emerald-50/50 dark:bg-emerald-950/20 p-4">
              <div>
                <h4 className="font-bold text-sm text-emerald-800 dark:text-emerald-300">صندوق الزمالة والتكافل</h4>
                <p className="text-xs text-[var(--text-muted)] mt-0.5">
                  كل جنيه يتم تحصيله من هذه الغرامات يُودع مباشرة في الصندوق لصالح الفريق، وله سجل حركات كامل ومتاح لجميع الموظفين.
                </p>
              </div>
              <div className="flex items-center gap-2">
                <Link
                  to={fellowshipFundPath}
                  className="btn-primary !py-2 !px-4 text-xs font-bold whitespace-nowrap bg-emerald-600 hover:bg-emerald-700"
                  onClick={onClose}
                >
                  فتح صندوق الزمالة ↗
                </Link>
                <button type="button" className="btn-secondary !py-2 !px-4 text-xs font-bold whitespace-nowrap" onClick={onClose}>
                  إغلاق
                </button>
              </div>
            </div>
          </div>
        )}

        {/* 4. تفاصيل الشرائح المحددة (20 / 50 / 150 / 500) */}
        {(activeModalTier === 'tier-20' || activeModalTier === 'tier-50' || activeModalTier === 'tier-150' || activeModalTier === 'tier-500') &&
          (() => {
            const meta = TIER_DETAIL_META[activeModalTier];
            const bucket = tierStats[meta.key];
            return (
              <div className="space-y-4">
                <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                  <div className="rounded-xl bg-[var(--surface-muted)] border border-[var(--border-subtle)] p-3 text-center">
                    <span className="text-xs text-[var(--text-muted)] block">إجمالي الغرامات</span>
                    <span className="text-lg font-black text-[var(--text-primary)] font-mono">{bucket.count}</span>
                  </div>
                  <div className="rounded-xl bg-[var(--surface-muted)] border border-[var(--border-subtle)] p-3 text-center">
                    <span className="text-xs text-[var(--text-muted)] block">إجمالي القيمة</span>
                    <span className={`text-lg font-black font-mono ${meta.color}`}>{formatCurrency(bucket.total)}</span>
                  </div>
                  <div className="rounded-xl bg-amber-500/10 border border-amber-500/20 p-3 text-center">
                    <span className="text-xs text-amber-700 dark:text-amber-300 block">بانتظار التحصيل</span>
                    <span className="text-lg font-black text-amber-600 dark:text-amber-400 font-mono">{bucket.pendingCount}</span>
                  </div>
                  <div className="rounded-xl bg-emerald-500/10 border border-emerald-500/20 p-3 text-center">
                    <span className="text-xs text-emerald-700 dark:text-emerald-300 block">مُورّدة بالصندوق</span>
                    <span className="text-lg font-black text-emerald-600 dark:text-emerald-400 font-mono">{bucket.paidCount}</span>
                  </div>
                </div>

                <div className="overflow-x-auto rounded-xl border border-[var(--border-subtle)] bg-[var(--surface)]">
                  <table className="w-full text-start text-xs">
                    <thead className="bg-[var(--surface-muted)] text-[var(--text-muted)] font-bold border-b border-[var(--border-subtle)]">
                      <tr>
                        <th className="p-3 text-start">الموظف</th>
                        <th className="p-3 text-start">الإدارة</th>
                        <th className="p-3 text-start">تاريخ التأخير</th>
                        <th className="p-3 text-center">التأخير</th>
                        <th className="p-3 text-end">المطلوب</th>
                        <th className="p-3 text-center">الحالة</th>
                        <th className="p-3 text-center">إجراء سريع</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-[var(--border-subtle)]">
                      {bucket.items.length === 0 ? (
                        <tr>
                          <td colSpan={7} className="p-6 text-center text-[var(--text-muted)]">
                            لا توجد أي غرامات مسجلة في هذه الشريحة حالياً.
                          </td>
                        </tr>
                      ) : (
                        bucket.items.map((p) => {
                          const isPending = p.status === 'pending_payment' || p.status === 'doubled' || p.status === 'suspended';
                          return (
                            <tr key={p.id} className="hover:bg-[var(--surface-hover)] transition-colors">
                              <td className="p-3 font-bold text-[var(--text-primary)]">
                                {p.employeeName ?? '—'}
                                {p.employeeCode && !isPhoneLikeCode(p.employeeCode) && (
                                  <span className="block text-[10px] text-[var(--text-muted)] font-mono">
                                    <bdi dir="ltr">{p.employeeCode}</bdi>
                                  </span>
                                )}
                              </td>
                              <td className="p-3 text-[var(--text-secondary)]">{p.departmentName ?? '—'}</td>
                              <td className="p-3 whitespace-nowrap text-[var(--text-muted)]">{dateFormatter.format(new Date(p.workDate + 'T00:00:00'))}</td>
                              <td className="p-3 text-center">
                                <span className="font-bold text-amber-600 dark:text-amber-400">{p.lateMinutes} د</span>
                              </td>
                              <td className="p-3 text-end font-black font-mono text-[var(--text-primary)]">{formatCurrency(p.currentAmount)}</td>
                              <td className="p-3 text-center">
                                <StatusBadge status={p.status} label={INSTANT_PENALTY_STATUS_LABELS[p.status] ?? p.status} />
                              </td>
                              <td className="p-3 text-center">
                                {isPending ? (
                                  <button
                                    type="button"
                                    className="btn-primary !py-1 !px-2.5 text-[11px] bg-emerald-600 hover:bg-emerald-700 text-white font-bold whitespace-nowrap"
                                    onClick={() => onOpenPaymentDialog(p)}
                                  >
                                    <Coins className="size-3 text-amber-300" />
                                    <span>إيداع بالصندوق</span>
                                  </button>
                                ) : p.status === 'paid' ? (
                                  <span className="text-[11px] text-emerald-600 dark:text-emerald-400 font-bold">✓ تم الإيداع</span>
                                ) : (
                                  <span className="text-[11px] text-[var(--text-muted)]">ملغاة</span>
                                )}
                              </td>
                            </tr>
                          );
                        })
                      )}
                    </tbody>
                  </table>
                </div>

                <div className="flex flex-wrap items-center justify-between gap-2 pt-2 border-t border-[var(--border-subtle)]">
                  <button
                    type="button"
                    className="btn-secondary text-xs flex items-center gap-1.5"
                    onClick={() => {
                      const cols: ExportColumn<InstantPenalty>[] = [
                        { key: 'employee', header: 'الموظف', get: (p) => p.employeeName },
                        { key: 'code', header: 'الكود', get: (p) => p.employeeCode },
                        { key: 'department', header: 'الإدارة', get: (p) => p.departmentName },
                        { key: 'date', header: 'التاريخ', get: (p) => p.workDate },
                        { key: 'lateMinutes', header: 'التأخير', get: (p) => fmtLateDisplay(p.lateMinutes) },
                        { key: 'amount', header: 'المبلغ', get: (p) => p.currentAmount },
                        { key: 'status', header: 'الحالة', get: (p) => INSTANT_PENALTY_STATUS_LABELS[p.status] ?? p.status },
                      ];
                      downloadCsv(`penalties-${activeModalTier}-${cairoTodayIso()}.csv`, toCsv(cols, bucket.items));
                    }}
                    disabled={bucket.items.length === 0}
                  >
                    <FileSpreadsheet className="size-4" />
                    <span>تصدير هذه الشريحة Excel</span>
                  </button>

                  <div className="flex items-center gap-2">
                    <button type="button" className="btn-primary !py-1.5 !px-3 text-xs" onClick={() => onSelectTier(activeModalTier)}>
                      تصفية الجدول الرئيسي بهذه الشريحة ←
                    </button>
                    <button type="button" className="btn-secondary !py-1.5 !px-3 text-xs" onClick={onClose}>
                      إغلاق
                    </button>
                  </div>
                </div>
              </div>
            );
          })()}
      </div>
    </DialogOverlay>
  );
}
