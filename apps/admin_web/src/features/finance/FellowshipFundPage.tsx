import { useState, useMemo } from 'react';
import {
  Coins,
  HeartHandshake,
  ArrowDownLeft,
  ArrowUpRight,
  ShieldCheck,
  History,
  Users,
  Search,
  AlertTriangle,
  FileText,
  Clock,
  CheckCircle2,
  TrendingUp,
  TrendingDown,
  Sparkles,
  Receipt,
  UserCheck,
} from 'lucide-react';
import {
  useFellowshipFundSummary,
  useFellowshipFundTransactions,
  useWithdrawFromFellowshipFund,
  FELLOWSHIP_CATEGORIES,
  type FellowshipFundTransaction,
} from './useFellowshipFund';
import { useAuth } from '../auth/AuthProvider';
import { hasPermission } from '../workspaces/access';
import { useEmployees } from '../employees/useEmployees';
import { PageHeader } from '../../ui/PageHeader';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { EmptyState } from '../../ui/EmptyState';

export function FellowshipFundPage() {
  const auth = useAuth();
  const { data: summary, isLoading: summaryLoading } = useFellowshipFundSummary();
  const [typeFilter, setTypeFilter] = useState<'all' | 'inflow' | 'outflow'>('all');
  const [search, setSearch] = useState('');
  const { data: transactions, isLoading: txLoading } = useFellowshipFundTransactions({
    type: typeFilter,
    search,
  });

  const [withdrawOpen, setWithdrawOpen] = useState(false);
  const [withdrawAmount, setWithdrawAmount] = useState('');
  const [withdrawCategory, setWithdrawCategory] = useState<string>('مساعدة زميل');
  const [withdrawReason, setWithdrawReason] = useState('');
  const [beneficiaryId, setBeneficiaryId] = useState('');
  const [withdrawNotes, setWithdrawNotes] = useState('');
  const [actionError, setActionError] = useState<string | null>(null);

  const withdrawMutation = useWithdrawFromFellowshipFund();
  const { data: employeesData } = useEmployees();
  const employees = employeesData ?? [];

  // صلاحية الإدارة للسحب
  const canWithdraw = Boolean(
    auth.access && (
      hasPermission(auth.access, 'payroll.run.manage') ||
      hasPermission(auth.access, 'finance.manage') ||
      auth.access.workspaces?.includes('main_admin') ||
      auth.access.permissions?.includes('*')
    )
  );

  const currentBalance = summary?.currentBalance ?? 0;

  async function handleWithdrawSubmit(e: React.FormEvent) {
    e.preventDefault();
    setActionError(null);
    const amount = Number(withdrawAmount);
    if (!amount || amount <= 0) {
      setActionError('يرجى إدخال مبلغ سحب صحيح أكبر من صفر');
      return;
    }
    if (amount > currentBalance) {
      setActionError(`الرصيد المتاح (${currentBalance.toLocaleString('ar-EG')} ج.م) لا يكفي لسحب هذا المبلغ`);
      return;
    }
    if (!withdrawReason.trim() || withdrawReason.trim().length < 3) {
      setActionError('يرجى توضيح سبب السحب بالتفصيل لضمان الشفافية وإشعار الفريق');
      return;
    }

    try {
      await withdrawMutation.mutateAsync({
        amount,
        category: withdrawCategory,
        reason: withdrawReason.trim(),
        beneficiaryEmployeeId: beneficiaryId || undefined,
        notes: withdrawNotes.trim() || undefined,
      });
      setWithdrawOpen(false);
      setWithdrawAmount('');
      setWithdrawReason('');
      setWithdrawNotes('');
      setBeneficiaryId('');
    } catch (err: unknown) {
      setActionError(err instanceof Error ? err.message : 'فشل تنفيذ عملية السحب');
    }
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="صندوق الزمالة والتكافل"
        description="صندوق مالي تشاركي بشفافية كاملة لكافة أعضاء الفريق — إيداعات غرامات التأخير والمساهمات، وسحوبات المساعدات بعلم الجميع."
        actions={
          <div className="flex items-center gap-3">
            {canWithdraw && (
              <button
                onClick={() => {
                  setActionError(null);
                  setWithdrawOpen(true);
                }}
                className="btn-primary flex items-center gap-2 bg-gradient-to-r from-amber-600 to-amber-700 hover:from-amber-700 hover:to-amber-800 text-white shadow-lg shadow-amber-600/20"
              >
                <ArrowUpRight className="w-4 h-4" /> سحب من الصندوق
              </button>
            )}
          </div>
        }
      />

      {/* ═══ بطاقة الخزنة الرقمية الفاخرة (The Digital Vault Card) ═══ */}
      <div className="relative overflow-hidden rounded-3xl border-2 border-emerald-500/30 bg-gradient-to-br from-gray-900 via-emerald-950/40 to-gray-950 p-6 md:p-8 text-white shadow-[0_0_40px_rgba(16,185,129,0.15)]">
        {/* توهج خلفي زخرفي */}
        <div className="absolute -right-20 -top-20 h-64 w-64 rounded-full bg-emerald-500/10 blur-3xl pointer-events-none" />
        <div className="absolute -left-20 -bottom-20 h-64 w-64 rounded-full bg-amber-500/10 blur-3xl pointer-events-none" />

        <div className="relative z-10 flex flex-col md:flex-row md:items-center md:justify-between gap-6">
          <div className="space-y-3">
            <div className="inline-flex items-center gap-2 rounded-full border border-emerald-500/30 bg-emerald-500/10 px-3.5 py-1 text-xs font-bold text-emerald-400">
              <Coins className="w-3.5 h-3.5 animate-pulse text-amber-400" />
              <span>خزنة صندوق الزمالة والتكافل</span>
              <span className="text-emerald-300/50">•</span>
              <span className="flex items-center gap-1 text-emerald-300">
                <ShieldCheck className="w-3.5 h-3.5" /> شفاف ومتاح للفريق
              </span>
            </div>

            <div>
              <p className="text-xs text-gray-400 font-medium">الرصيد المتاح حالياً بالصندوق</p>
              <div className="flex items-baseline gap-2 mt-1">
                <h2 className="text-4xl md:text-5xl font-black tracking-tight text-white font-mono">
                  {currentBalance.toLocaleString('ar-EG', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
                </h2>
                <span className="text-lg md:text-xl font-bold text-emerald-400">جنيه مصري</span>
              </div>
            </div>

            <p className="text-xs text-gray-400 max-w-xl leading-relaxed">
              تُورّد كل مبالغ غرامات الحضور والانصراف تلقائياً إلى هذا الصندوق لمساعدة الزملاء والمناسبات الاجتماعية، ويكون كل سحب أو إيداع معلناً للجميع بإشعار فوري.
            </p>
          </div>

          {/* كروت سريعة للإحصائيات في الخزنة */}
          <div className="grid grid-cols-2 gap-3 w-full md:w-auto shrink-0">
            <div className="rounded-2xl border border-emerald-500/20 bg-black/40 p-4 backdrop-blur-sm">
              <div className="flex items-center gap-2 text-xs font-bold text-emerald-400 mb-1">
                <ArrowDownLeft className="w-4 h-4 text-emerald-400" />
                <span>إجمالي الوارد</span>
              </div>
              <p className="text-xl font-black font-mono text-emerald-300">
                {(summary?.totalInflows ?? 0).toLocaleString('ar-EG')} ج.م
              </p>
              <p className="text-[11px] text-gray-400 mt-1">
                {summary?.inflowsCount ?? 0} عملية إيداع
              </p>
            </div>

            <div className="rounded-2xl border border-red-500/20 bg-black/40 p-4 backdrop-blur-sm">
              <div className="flex items-center gap-2 text-xs font-bold text-red-400 mb-1">
                <ArrowUpRight className="w-4 h-4 text-red-400" />
                <span>إجمالي المنصرف</span>
              </div>
              <p className="text-xl font-black font-mono text-red-300">
                {(summary?.totalOutflows ?? 0).toLocaleString('ar-EG')} ج.م
              </p>
              <p className="text-[11px] text-gray-400 mt-1">
                {summary?.outflowsCount ?? 0} عملية سحب
              </p>
            </div>
          </div>
        </div>
      </div>

      {/* ═══ تفنيط مصادر وأبواب الصندوق (Breakdown by Category) ═══ */}
      {summary?.categoryBreakdown && summary.categoryBreakdown.length > 0 && (
        <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface-base)] p-5 shadow-sm space-y-4">
          <div className="flex items-center justify-between">
            <h3 className="text-sm font-bold flex items-center gap-2">
              <Sparkles className="w-4 h-4 text-amber-500" />
              تفنيط مبالغ الصندوق وأبواب الصرف والإيداع
            </h3>
            <span className="text-xs text-[var(--text-muted)]">
              {summary.categoryBreakdown.length} فئات نشطة
            </span>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3">
            {summary.categoryBreakdown.map((cat, idx) => {
              const isInflow = cat.type === 'inflow';
              return (
                <div
                  key={idx}
                  className={`rounded-xl p-3.5 border transition-all ${
                    isInflow
                      ? 'border-emerald-500/20 bg-emerald-50/40 dark:bg-emerald-950/15'
                      : 'border-amber-500/20 bg-amber-50/40 dark:bg-amber-950/15'
                  }`}
                >
                  <div className="flex items-center justify-between mb-1.5">
                    <span className="text-xs font-bold truncate">{cat.category}</span>
                    <span
                      className={`text-[10px] px-2 py-0.5 rounded-full font-bold ${
                        isInflow
                          ? 'bg-emerald-100 text-emerald-700 dark:bg-emerald-900/40 dark:text-emerald-300'
                          : 'bg-amber-100 text-amber-700 dark:bg-amber-900/40 dark:text-amber-300'
                      }`}
                    >
                      {isInflow ? 'وارد' : 'منصرف'}
                    </span>
                  </div>
                  <div className="flex items-baseline justify-between mt-2">
                    <span className="text-lg font-black font-mono">
                      {cat.totalAmount.toLocaleString('ar-EG')} ج.م
                    </span>
                    <span className="text-xs text-[var(--text-muted)]">{cat.count} حركة</span>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* ═══ سجل الحركات الشفاف (Transparency Ledger) ═══ */}
      <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface-base)] p-5 shadow-sm space-y-4">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div className="flex items-center gap-2">
            <History className="w-5 h-5 text-emerald-600 dark:text-emerald-400" />
            <h3 className="font-bold text-base">سجل الحركات والمعاملات الشفاف</h3>
            <span className="text-xs px-2 py-0.5 rounded-full bg-[var(--surface-raised)] text-[var(--text-muted)] font-medium">
              {transactions?.length ?? 0} حركة
            </span>
          </div>

          <div className="flex flex-wrap items-center gap-3">
            {/* فلاتر النوع */}
            <div className="flex bg-[var(--surface-raised)] rounded-lg p-0.5 text-xs font-bold">
              <button
                onClick={() => setTypeFilter('all')}
                className={`px-3 py-1.5 rounded-md transition-colors ${
                  typeFilter === 'all'
                    ? 'bg-[var(--brand-primary)] text-white'
                    : 'text-[var(--text-muted)] hover:text-[var(--text-primary)]'
                }`}
              >
                الكل
              </button>
              <button
                onClick={() => setTypeFilter('inflow')}
                className={`px-3 py-1.5 rounded-md transition-colors ${
                  typeFilter === 'inflow'
                    ? 'bg-emerald-600 text-white'
                    : 'text-[var(--text-muted)] hover:text-[var(--text-primary)]'
                }`}
              >
                الإيداعات فقط (الوارد)
              </button>
              <button
                onClick={() => setTypeFilter('outflow')}
                className={`px-3 py-1.5 rounded-md transition-colors ${
                  typeFilter === 'outflow'
                    ? 'bg-red-600 text-white'
                    : 'text-[var(--text-muted)] hover:text-[var(--text-primary)]'
                }`}
              >
                السحوبات فقط (المنصرف)
              </button>
            </div>

            {/* البحث */}
            <div className="relative">
              <Search className="w-3.5 h-3.5 absolute right-3 top-1/2 -translate-y-1/2 text-gray-400" />
              <input
                type="text"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="بحث بالاسم أو السبب أو الفئة..."
                className="input pr-8 text-xs py-1.5 w-56"
              />
            </div>
          </div>
        </div>

        {/* عرض الحركات */}
        {txLoading ? (
          <div className="py-12 text-center text-xs text-[var(--text-muted)]">جاري تحميل حركات الصندوق...</div>
        ) : !transactions || transactions.length === 0 ? (
          <EmptyState
            title="لا توجد حركات مسجلة"
            description={
              search
                ? 'لا توجد حركات تطابق معايير البحث الحالية'
                : 'لم يتم تسجيل أي إيداعات أو سحوبات في صندوق الزمالة حتى الآن'
            }
          />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-right text-xs">
              <thead>
                <tr className="border-b border-[var(--border)] text-[var(--text-muted)] bg-[var(--surface-raised)]/40">
                  <th className="p-3 font-bold">الحركة</th>
                  <th className="p-3 font-bold">المبلغ</th>
                  <th className="p-3 font-bold">الموظف / المستفيد</th>
                  <th className="p-3 font-bold">السبب والتفاصيل (لماذا)</th>
                  <th className="p-3 font-bold">الفئة</th>
                  <th className="p-3 font-bold">الرصيد المتبقي (الباقي)</th>
                  <th className="p-3 font-bold">التاريخ والقائم بالعملية</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[var(--border)]">
                {transactions.map((tx) => {
                  const isInflow = tx.transactionType === 'inflow';
                  return (
                    <tr key={tx.id} className="hover:bg-[var(--surface-raised)]/30 transition-colors">
                      <td className="p-3">
                        <span
                          className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full font-bold text-[11px] ${
                            isInflow
                              ? 'bg-emerald-100 text-emerald-800 dark:bg-emerald-950/40 dark:text-emerald-300'
                              : 'bg-red-100 text-red-800 dark:bg-red-950/40 dark:text-red-300'
                          }`}
                        >
                          {isInflow ? (
                            <>
                              <ArrowDownLeft className="w-3.5 h-3.5 text-emerald-600 dark:text-emerald-400" />
                              إيداع (وارد)
                            </>
                          ) : (
                            <>
                              <ArrowUpRight className="w-3.5 h-3.5 text-red-600 dark:text-red-400" />
                              سحب (منصرف)
                            </>
                          )}
                        </span>
                      </td>

                      <td className="p-3 font-mono font-black text-sm">
                        <span className={isInflow ? 'text-emerald-600 dark:text-emerald-400' : 'text-red-600 dark:text-red-400'}>
                          {isInflow ? '+' : '-'}{tx.amount.toLocaleString('ar-EG')} ج.م
                        </span>
                      </td>

                      <td className="p-3">
                        <div className="flex items-center gap-1.5 font-bold text-[var(--text-primary)]">
                          <UserCheck className="w-3.5 h-3.5 text-gray-400" />
                          <span>{tx.employeeName}</span>
                        </div>
                      </td>

                      <td className="p-3 max-w-xs">
                        <p className="font-medium text-[var(--text-primary)] leading-tight">{tx.reason}</p>
                        {tx.notes && <p className="text-[11px] text-[var(--text-muted)] mt-0.5">{tx.notes}</p>}
                      </td>

                      <td className="p-3">
                        <span className="rounded-md bg-[var(--surface-raised)] px-2 py-1 text-[11px] font-medium border border-[var(--border)]">
                          {tx.category}
                        </span>
                      </td>

                      <td className="p-3 font-mono font-bold text-gray-700 dark:text-gray-300">
                        {tx.balanceAfter.toLocaleString('ar-EG')} ج.م
                      </td>

                      <td className="p-3 text-[var(--text-muted)]">
                        <p className="flex items-center gap-1">
                          <Clock className="w-3 h-3 text-gray-400" />
                          {new Date(tx.createdAt).toLocaleDateString('ar-EG', {
                            year: 'numeric',
                            month: 'short',
                            day: 'numeric',
                            hour: '2-digit',
                            minute: '2-digit',
                          })}
                        </p>
                        {tx.performerName && (
                          <p className="text-[10px] text-gray-400 mt-0.5">بواسطة: {tx.performerName}</p>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* ═══ حوار سحب مبلغ من صندوق الزمالة (خاص بالأدمن فقط) ═══ */}
      {withdrawOpen && (
        <DialogOverlay title="سحب مبلغ من صندوق الزمالة والتكافل" onClose={() => setWithdrawOpen(false)} maxWidth="max-w-lg">
          <form onSubmit={handleWithdrawSubmit} className="space-y-4 p-4 text-right">
            {/* لافتة الشفافية والتنبيه */}
            <div className="rounded-xl border border-amber-500/30 bg-amber-50/50 dark:bg-amber-950/20 p-3 text-xs text-amber-800 dark:text-amber-300 space-y-1">
              <div className="flex items-center gap-1.5 font-bold">
                <AlertTriangle className="w-4 h-4 text-amber-500 shrink-0" />
                <span>إشعار شفافية إلزامي لكامل الفريق</span>
              </div>
              <p className="leading-relaxed">
                سيتم إرسال إشعار فوري لكافة أعضاء الفريق بمبلغ السحب والسبب والرصيد المتبقي بمجرد التنفيذ لضمان علم الجميع.
              </p>
              <div className="pt-1 text-[11px] font-mono">
                الرصيد المتاح حالياً: <span className="font-bold">{currentBalance.toLocaleString('ar-EG')} ج.م</span>
              </div>
            </div>

            {actionError && (
              <div className="rounded-lg bg-red-50 dark:bg-red-950/30 p-2.5 text-xs text-red-600 dark:text-red-400 border border-red-200">
                {actionError}
              </div>
            )}

            <div>
              <label className="block text-xs font-bold mb-1">المبلغ المراد سحبه (ج.م) *</label>
              <input
                type="number"
                step="any"
                min={1}
                max={currentBalance}
                required
                value={withdrawAmount}
                onChange={(e) => setWithdrawAmount(e.target.value)}
                placeholder="أدخل المبلغ..."
                className="input w-full font-mono font-bold"
              />
            </div>

            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block text-xs font-bold mb-1">فئة السحب *</label>
                <select
                  value={withdrawCategory}
                  onChange={(e) => setWithdrawCategory(e.target.value)}
                  className="input w-full text-xs"
                >
                  {FELLOWSHIP_CATEGORIES.filter((c) => c !== 'غرامة تأخير حضور').map((cat) => (
                    <option key={cat} value={cat}>{cat}</option>
                  ))}
                </select>
              </div>

              <div>
                <label className="block text-xs font-bold mb-1">الموظف المستفيد (اختياري)</label>
                <select
                  value={beneficiaryId}
                  onChange={(e) => setBeneficiaryId(e.target.value)}
                  className="input w-full text-xs"
                >
                  <option value="">دعم عام / جهة مؤسسية</option>
                  {employees.map((emp) => (
                    <option key={emp.id} value={emp.id}>{emp.fullNameAr}</option>
                  ))}
                </select>
              </div>
            </div>

            <div>
              <label className="block text-xs font-bold mb-1">سبب السحب بالتفصيل (لماذا) *</label>
              <textarea
                required
                rows={3}
                value={withdrawReason}
                onChange={(e) => setWithdrawReason(e.target.value)}
                placeholder="وضح سبب السحب بدقة ومبرراته ليتم إرساله في الإشعار للفريق..."
                className="input w-full text-xs"
              />
            </div>

            <div>
              <label className="block text-xs font-bold mb-1">ملاحظات إدارية (اختياري)</label>
              <input
                type="text"
                value={withdrawNotes}
                onChange={(e) => setWithdrawNotes(e.target.value)}
                placeholder="أي ملاحظات أو مستندات مرجعية..."
                className="input w-full text-xs"
              />
            </div>

            <div className="flex gap-3 pt-2">
              <button
                type="button"
                onClick={() => setWithdrawOpen(false)}
                className="btn-secondary flex-1"
                disabled={withdrawMutation.isPending}
              >
                إلغاء
              </button>
              <button
                type="submit"
                className="btn-primary flex-1 bg-red-600 hover:bg-red-700 text-white"
                disabled={withdrawMutation.isPending}
              >
                {withdrawMutation.isPending ? 'جاري تنفيذ السحب...' : 'تأكيد السحب وإشعار الفريق'}
              </button>
            </div>
          </form>
        </DialogOverlay>
      )}
    </div>
  );
}
